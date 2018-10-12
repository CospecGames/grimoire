/**
    Grimoire virtual machine.

    Copyright: (c) Enalye 2018
    License: Zlib
    Authors: Enalye
*/

module grimoire.runtime.engine;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.math;

import grimoire.core.indexedarray;
import grimoire.compiler;
import grimoire.assembly;
import grimoire.runtime.context;
import grimoire.runtime.dynamic;
import grimoire.runtime.array;

/** Grimoire virtual machine */
class GrEngine {
    private {
        /// Opcodes.
        immutable(uint)[] _opcodes;
        /// Integral constants.
        immutable(int)[] _iconsts;
        /// Floating point constants.
        immutable(float)[] _fconsts;
        /// String constants.
        immutable(dstring)[] _sconsts;

        /// Global integral variables.
        int[] _iglobals;
        /// Global floating point variables.
        float[] _fglobals;
        /// Global string variables.
        dstring[] _sglobals;

        /// Global integral stack.
        int[] _iglobalStack;
        /// Global floating point stack.
        float[] _fglobalStack;
        /// Global string stack.
        dstring[] _sglobalStack;
        /// Global array stack.
        GrDynamicValue[][] _nglobalStack;
        /// Global dynamic value stack.
        GrDynamicValue[] _aglobalStack;
        /// Global object stack.
        void*[] _oglobalStack;
        /// Global user data stack.
        void*[] _uglobalStack;

        /// Context array.
	    IndexedArray!(GrContext, 256u) _contexts;
    
        /// Global panic state.
        /// It means that the throwing context didn't handle the exception.
        bool _isPanicking;
        /// Unhandled panic message.
        dstring _panicMessage;
    }

    __gshared bool isRunning = true;

    @property {
        /// Check if there is a coroutine currently running.
        bool hasCoroutines() const { return _contexts.length > 0uL; }

        /// Whether the whole VM has panicked, true if an unhandled error occurred.
        bool isPanicking() const { return _isPanicking; }

        /// The unhandled error message.
        dstring panicMessage() const { return _panicMessage; }
    }

    /// Default.
	this() {
        _contexts = new IndexedArray!(GrContext, 256u)();
    }

    /// Load the bytecode.
	this(GrBytecode bytecode) {
		load(bytecode);
	}

    /// Load the bytecode.
	void load(GrBytecode bytecode) {
		_iconsts = bytecode.iconsts.idup;
		_fconsts = bytecode.fconsts.idup;
		_sconsts = bytecode.sconsts.idup;
		_opcodes = bytecode.opcodes.idup;
	}

    /**
        Create the main context.
        You must call this function before running the vm.
    */
    void spawn() {
		_contexts.push(new GrContext(this));
	}

    /**
        Captures an unhandled error and kill the VM.
    */
    void panic() {
        _contexts.reset();
    }

    void raise(GrContext context, dstring message) {
        if(context.isPanicking)
            return;
        //Error message.
        _sglobalStack ~= message;
        
        //We indicate that the coroutine is in a panic state until a catch is found.
        context.isPanicking = true;
        
        //Exception handler found in the current function, just jump.
        if(context.exceptionHandlers[context.exceptionHandlersPos].length) {
            context.pc = context.exceptionHandlers[context.exceptionHandlersPos][$ - 1];
        }
        //No exception handler in the current function, unwinding the deferred code, then return.
        
        //Check for deferred calls as we will exit the current function.
        else if(context.deferStack[context.deferPos].length) {
            //Pop the last defer and run it.
            context.pc = context.deferStack[context.deferPos][$ - 1];
            context.deferStack[context.deferPos].length --;
            //The search for an exception handler will be done by Unwind after all defer
            //has been called for this function.
        }
        else if(context.stackPos) {
            //Pop the defer scope.
            context.deferPos --;

            //Pop the exception handlers as well.
            context.exceptionHandlersPos --;

            //Then returns to the last context, raise will be run again.
            context.stackPos -= 2;
            context.localsPos -= context.callStack[context.stackPos];
        }
        else {
            //Kill the others.
            foreach(coroutine; _contexts) {
                coroutine.pc = cast(uint)(_opcodes.length - 1);
                coroutine.isKilled = true;
            }

            //The VM is now panicking.
            _isPanicking = true;
            _panicMessage = _sglobalStack[$ - 1];
            _sglobalStack.length --;
        }
    }

    /// Run the vm until all the contexts are finished or in yield.
	void process() {
		contextsLabel: for(uint index = 0u; index < _contexts.length; index ++) {
			GrContext context = _contexts.data[index];
			while(isRunning) {
				uint opcode = _opcodes[context.pc];
				switch (grBytecode_getOpcode(opcode)) with(GrOpcode) {
                case Nop:
                    context.pc ++;
                    break;
                case Raise:
                    if(!context.isPanicking) {
                        //Error message.
                        _sglobalStack ~= context.sstack[context.sstackPos];
                        context.sstackPos --;

                        //We indicate that the coroutine is in a panic state until a catch is found.
                        context.isPanicking = true;
                    }

                    //Exception handler found in the current function, just jump.
                    if(context.exceptionHandlers[context.exceptionHandlersPos].length) {
                        context.pc = context.exceptionHandlers[context.exceptionHandlersPos][$ - 1];
                    }
                    //No exception handler in the current function, unwinding the deferred code, then return.
                    
                    //Check for deferred calls as we will exit the current function.
                    else if(context.deferStack[context.deferPos].length) {
                        //Pop the last defer and run it.
                        context.pc = context.deferStack[context.deferPos][$ - 1];
                        context.deferStack[context.deferPos].length --;
                        //The search for an exception handler will be done by Unwind after all defer
                        //has been called for this function.
                    }
                    else if(context.stackPos) {
                        //Pop the defer scope.
                        context.deferPos --;

                        //Pop the exception handlers as well.
                        context.exceptionHandlersPos --;

                        //Then returns to the last context, raise will be run again.
                        context.stackPos -= 2;
                        context.localsPos -= context.callStack[context.stackPos];
                    }
                    else {
                        //Kill the others.
                        foreach(coroutine; _contexts) {
                            coroutine.pc = cast(uint)(_opcodes.length - 1);
                            coroutine.isKilled = true;
                        }

                        //The VM is now panicking.
                        _isPanicking = true;
                        _panicMessage = _sglobalStack[$ - 1];
                        _sglobalStack.length --;

                        //Every deferred call has been executed, now die.
                        _contexts.markInternalForRemoval(index);
                        continue contextsLabel;
                    }
                    break;
                case Try:
                    context.exceptionHandlers[context.exceptionHandlersPos] ~= context.pc + grBytecode_getSignedValue(opcode);
                    context.pc ++;
                    break;
                case Catch:
                    context.exceptionHandlers[context.exceptionHandlersPos].length --;
                    if(context.isPanicking) {
                        context.isPanicking = false;
                        context.pc ++;
                    }
                    else {
                        context.pc += grBytecode_getSignedValue(opcode);
                    }
                    break;
				case Task:
					GrContext newCoro = new GrContext(this);
					newCoro.pc = grBytecode_getUnsignedValue(opcode);
					_contexts.push(newCoro);
					context.pc ++;
					break;
				case AnonymousTask:
					GrContext newCoro = new GrContext(this);
					newCoro.pc = context.istack[context.istackPos];
					context.istackPos --;
					_contexts.push(newCoro);
					context.pc ++;
					break;
				case Kill:
                    //Check for deferred calls.
                    if(context.deferStack[context.deferPos].length) {
                        //Pop the last defer and run it.
                        context.pc = context.deferStack[context.deferPos][$ - 1];
                        context.deferStack[context.deferPos].length --;

                        //Flag as killed so the entire stack will be unwinded.
                        context.isKilled = true;
                    }
                    else if(context.stackPos) {
                        //Pop the defer scope.
                        context.deferPos --;

                        //Then returns to the last context.
                        context.stackPos -= 2;
                        context.pc = context.callStack[context.stackPos + 1u];
                        context.localsPos -= context.callStack[context.stackPos];

                        //Flag as killed so the entire stack will be unwinded.
                        context.isKilled = true;
                    }
                    else {
                        //No need to flag if the call stac is empty without any deferred statement.
                        _contexts.markInternalForRemoval(index);
					    continue contextsLabel;
                    }
					break;
				case Yield:
					context.pc ++;
					continue contextsLabel;
				case PopStack_Int:
					context.istackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case PopStack_Float:
					context.fstackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case PopStack_String:
					context.sstackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
                case PopStack_Array:
					context.nstackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case PopStack_Any:
					context.astackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case PopStack_Object:
					context.ostackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
                case PopStack_UserData:
					context.ustackPos -= grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case LocalStore_Int:
					context.ilocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.istack[context.istackPos];
                    context.istackPos --;	
					context.pc ++;
					break;
				case LocalStore_Float:
					context.flocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.fstack[context.fstackPos];
                    context.fstackPos --;	
					context.pc ++;
					break;
				case LocalStore_String:
					context.slocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.sstack[context.sstackPos];		
                    context.sstackPos --;	
					context.pc ++;
					break;
                case LocalStore_Array:
					context.nlocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.nstack[context.nstackPos];		
                    context.nstackPos --;	
					context.pc ++;
					break;
				case LocalStore_Any:
					context.alocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.astack[context.astackPos];
                    context.astackPos --;	
					context.pc ++;
					break;
                case LocalStore_Ref:
                    context.astack[context.astackPos - 1].setRef(context.astack[context.astackPos]);
                    context.astackPos -= 2;
                    context.pc ++;
                    break;
				case LocalStore_Object:
					context.olocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.ostack[context.ostackPos];
                    context.ostackPos --;	
					context.pc ++;
					break;
                case LocalStore_UserData:
					context.ulocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.ustack[context.ustackPos];
                    context.ustackPos --;	
					context.pc ++;
					break;
                case LocalStore2_Int:
					context.ilocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.istack[context.istackPos];
					context.pc ++;
					break;
				case LocalStore2_Float:
					context.flocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.fstack[context.fstackPos];
					context.pc ++;
					break;
				case LocalStore2_String:
					context.slocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.sstack[context.sstackPos];		
					context.pc ++;
					break;
                case LocalStore2_Array:
					context.nlocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.nstack[context.nstackPos];		
					context.pc ++;
					break;
				case LocalStore2_Any:
					context.alocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.astack[context.astackPos];
					context.pc ++;
					break;
                case LocalStore2_Ref:
                    context.astackPos --;
                    context.astack[context.astackPos].setRef(context.astack[context.astackPos + 1]);
                    context.pc ++;
                    break;
				case LocalStore2_Object:
					context.olocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.ostack[context.ostackPos];
					context.pc ++;
					break;
                case LocalStore2_UserData:
					context.ulocals[context.localsPos + grBytecode_getUnsignedValue(opcode)] = context.ustack[context.ustackPos];
					context.pc ++;
					break;
				case LocalLoad_Int:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.ilocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
                    context.pc ++;
					break;
				case LocalLoad_Float:
                    context.fstackPos ++;
					context.fstack[context.fstackPos] = context.flocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case LocalLoad_String:
                    context.sstackPos ++;
					context.sstack[context.sstackPos] = context.slocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
                case LocalLoad_Array:
                    context.nstackPos ++;
					context.nstack[context.nstackPos] = context.nlocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case LocalLoad_Any:
                    context.astackPos ++;
					context.astack[context.astackPos] = context.alocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
                case LocalLoad_Ref:
                    GrDynamicValue value;
                    value.setRefArray(&context.nlocals[context.localsPos + grBytecode_getUnsignedValue(opcode)]);
                    context.astackPos ++;
                    context.astack[context.astackPos] = value;			
					context.pc ++;
					break;
				case LocalLoad_Object:
                    context.ostackPos ++;
					context.ostack[context.ostackPos] = context.olocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
                case LocalLoad_UserData:
                    context.ustackPos ++;
					context.ustack[context.ustackPos] = context.ulocals[context.localsPos + grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case Const_Int:
                    context.istackPos ++;
					context.istack[context.istackPos] = _iconsts[grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case Const_Float:
                    context.fstackPos ++;
					context.fstack[context.fstackPos] = _fconsts[grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case Const_Bool:
                    context.istackPos ++;
					context.istack[context.istackPos] = grBytecode_getUnsignedValue(opcode);
					context.pc ++;
					break;
				case Const_String:
                    context.sstackPos ++;
					context.sstack[context.sstackPos] = _sconsts[grBytecode_getUnsignedValue(opcode)];
					context.pc ++;
					break;
				case GlobalPush_Int:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_iglobalStack ~= context.istack[(context.istackPos - nbParams) + i];
					context.istackPos -= nbParams;
					context.pc ++;
					break;
				case GlobalPush_Float:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_fglobalStack ~= context.fstack[(context.fstackPos - nbParams) + i];
					context.fstackPos -= nbParams;
					context.pc ++;
					break;
				case GlobalPush_String:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_sglobalStack ~= context.sstack[(context.sstackPos - nbParams) + i];
					context.sstackPos -= nbParams;
					context.pc ++;
					break;
                case GlobalPush_Array:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_nglobalStack ~= context.nstack[(context.nstackPos - nbParams) + i];
					context.nstackPos -= nbParams;
					context.pc ++;
					break;
				case GlobalPush_Any:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_aglobalStack ~= context.astack[(context.astackPos - nbParams) + i];
					context.astackPos -= nbParams;
					context.pc ++;
					break;
				case GlobalPush_Object:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_oglobalStack ~= context.ostack[(context.ostackPos - nbParams) + i];
					context.ostackPos -= nbParams;
					context.pc ++;
					break;
                case GlobalPush_UserData:
					uint nbParams = grBytecode_getUnsignedValue(opcode);
					for(uint i = 1u; i <= nbParams; i++)
						_uglobalStack ~= context.ustack[(context.ustackPos - nbParams) + i];
					context.ustackPos -= nbParams;
					context.pc ++;
					break;
				case GlobalPop_Int:
                    context.istackPos ++;
					context.istack[context.istackPos] = _iglobalStack[$ - 1];
					_iglobalStack.length --;
					context.pc ++;
					break;
				case GlobalPop_Float:
                    context.fstackPos ++;
					context.fstack[context.fstackPos] = _fglobalStack[$ - 1];
					_fglobalStack.length --;
					context.pc ++;
					break;
				case GlobalPop_String:
                    context.sstackPos ++;
					context.sstack[context.sstackPos] = _sglobalStack[$ - 1];
					_sglobalStack.length --;
					context.pc ++;
					break;
                case GlobalPop_Array:
                    context.nstackPos ++;
					context.nstack[context.nstackPos] = _nglobalStack[$ - 1];
					_nglobalStack.length --;
					context.pc ++;
					break;
				case GlobalPop_Any:
                    context.astackPos ++;
					context.astack[context.astackPos] = _aglobalStack[$ - 1];
					_aglobalStack.length --;
					context.pc ++;
					break;
				case GlobalPop_Object:
                    context.ostackPos ++;
					context.ostack[context.ostackPos] = _oglobalStack[$ - 1];
					_oglobalStack.length --;
					context.pc ++;
					break;
                case GlobalPop_UserData:
                    context.ustackPos ++;
					context.ustack[context.ustackPos] = _uglobalStack[$ - 1];
					_uglobalStack.length --;
					context.pc ++;
					break;
				case Equal_Int:
                    context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] == context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case Equal_Float:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] == context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
				case Equal_String:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.sstack[context.sstackPos - 1] == context.sstack[context.sstackPos];
					context.sstackPos -= 2;
					context.pc ++;
					break;
				//Equal_Any
				case NotEqual_Int:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] != context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case NotEqual_Float:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] != context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
				case NotEqual_String:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.sstack[context.sstackPos - 1] != context.sstack[context.sstackPos];
					context.sstackPos -= 2;
					context.pc ++;
					break;
				//NotEqual_Any
				case GreaterOrEqual_Int:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] >= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case GreaterOrEqual_Float:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] >= context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
					//Any
				case LesserOrEqual_Int:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] <= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case LesserOrEqual_Float:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] <= context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
					//any
				case GreaterInt:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] > context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case GreaterFloat:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] > context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
					//any
				case LesserInt:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] < context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case LesserFloat:
                    context.istackPos ++;
					context.istack[context.istackPos] = context.fstack[context.fstackPos - 1] < context.fstack[context.fstackPos];
					context.fstackPos -= 2;
					context.pc ++;
					break;
					//any
				case AndInt:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] && context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case OrInt:
					context.istackPos --;
					context.istack[context.istackPos] = context.istack[context.istackPos] || context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case NotInt:
					context.istack[context.istackPos] = !context.istack[context.istackPos];
					context.pc ++;
					break;
					//any
				case AddInt:
					context.istackPos --;
					context.istack[context.istackPos] += context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case AddFloat:
					context.fstackPos --;
					context.fstack[context.fstackPos] += context.fstack[context.fstackPos + 1];
					context.pc ++;
					break;
				case AddAny:
					context.astackPos --;
					context.astack[context.astackPos] += context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case ConcatenateString:
					context.sstackPos --;
					context.sstack[context.sstackPos] ~= context.sstack[context.sstackPos + 1];
					context.pc ++;
					break;
				case ConcatenateAny:
					context.astackPos --;
					context.astack[context.astackPos] ~= context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case SubstractInt:
					context.istackPos --;
					context.istack[context.istackPos] -= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case SubstractFloat:
					context.fstackPos --;
					context.fstack[context.fstackPos] -= context.fstack[context.fstackPos + 1];
					context.pc ++;
					break;
				case SubstractAny:
					context.astackPos --;
					context.astack[context.astackPos] -= context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case MultiplyInt:
					context.istackPos --;
					context.istack[context.istackPos] *= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case MultiplyFloat:
					context.fstackPos --;
					context.fstack[context.fstackPos] *= context.fstack[context.fstackPos + 1];
					context.pc ++;
					break;
				case MultiplyAny:
					context.astackPos --;
					context.astack[context.astackPos] *= context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case DivideInt:
					context.istackPos --;
					context.istack[context.istackPos] /= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case DivideFloat:
					context.fstackPos --;
					context.fstack[context.fstackPos] /= context.fstack[context.fstackPos + 1];
					context.pc ++;
					break;
				case DivideAny:
					context.astackPos --;
					context.astack[context.astackPos] /= context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case RemainderInt:
					context.istackPos --;
					context.istack[context.istackPos] %= context.istack[context.istackPos + 1];
					context.pc ++;
					break;
				case RemainderFloat:
					context.fstackPos --;
					context.fstack[context.fstackPos] %= context.fstack[context.fstackPos + 1];
					context.pc ++;
					break;
				case RemainderAny:
					context.astackPos --;
					context.astack[context.astackPos] %= context.astack[context.astackPos + 1];
					context.pc ++;
					break;
				case NegativeInt:
					context.istack[context.istackPos] = -context.istack[context.istackPos];
					context.pc ++;
					break;
				case NegativeFloat:
					context.fstack[context.fstackPos] = -context.fstack[context.fstackPos];
					context.pc ++;
					break;
				case NegativeAny:
					context.astack[context.astackPos] = -context.astack[context.astackPos];
					context.pc ++;
					break;
				case IncrementInt:
					context.istack[context.istackPos] ++;
					context.pc ++;
					break;
				case IncrementFloat:
					context.fstack[context.fstackPos] += 1f;
					context.pc ++;
					break;
				case IncrementAny:
					context.astack[context.astackPos] ++;
					context.pc ++;
					break;
				case DecrementInt:
					context.istack[context.istackPos] --;
					context.pc ++;
					break;
				case DecrementFloat:
					context.fstack[context.fstackPos] -= 1f;
					context.pc ++;
					break;
				case DecrementAny:
					context.astack[context.astackPos] --;
					context.pc ++;
					break;
				case SetupIterator:
					if(context.istack[context.istackPos] < 0)
						context.istack[context.istackPos] = 0;
					context.istack[context.istackPos] ++;
					context.pc ++;
					break;
				case Return:
                    //If another task was killed by an exception,
                    //we might end up there if the task has just been spawned.
                    if(!context.deferPos && context.isKilled) {
                        _contexts.markInternalForRemoval(index);
					    continue contextsLabel;
                    }
                    //Check for deferred calls.
                    else if(context.deferStack[context.deferPos].length) {
                        //Pop the last defer and run it.
                        context.pc = context.deferStack[context.deferPos][$ - 1];
                        context.deferStack[context.deferPos].length --;
                    }
                    else {
                        //Pop the defer scope.
                        context.deferPos --;

                        //Pop the exception handlers as well.
                        context.exceptionHandlersPos --;

                        //Then returns to the last context.
                        context.stackPos -= 2;
                        context.pc = context.callStack[context.stackPos + 1u];
                        context.localsPos -= context.callStack[context.stackPos];
                    }
					break;
                case Unwind:
                    //If another task was killed by an exception,
                    //we might end up there if the task has just been spawned.
                    if(!context.deferPos) {
                        _contexts.markInternalForRemoval(index);
					    continue contextsLabel;
                    }
                    //Check for deferred calls.
                    else if(context.deferStack[context.deferPos].length) {
                        //Pop the next defer and run it.
                        context.pc = context.deferStack[context.deferPos][$ - 1];
                        context.deferStack[context.deferPos].length --;
                    }
                    else if(context.isKilled) {
                        if(context.stackPos) {
                            //Pop the defer scope.
                            context.deferPos --;

                            //Pop the exception handlers as well.
                            context.exceptionHandlersPos --;

                            //Then returns to the last context without modifying the pc.
                            context.stackPos -= 2;
                            context.localsPos -= context.callStack[context.stackPos];
                        }
                        else {
                            //Every deferred call has been executed, now die.
                            _contexts.markInternalForRemoval(index);
					        continue contextsLabel;
                        }
                    }
                    else if(context.isPanicking) {
                        //An exception has been raised without any try/catch inside the function.
                        //So all deferred code is run here before searching in the parent function.
                        if(context.stackPos) {
                            //Pop the defer scope.
                            context.deferPos --;

                            //Pop the exception handlers as well.
                            context.exceptionHandlersPos --;

                            //Then returns to the last context without modifying the pc.
                            context.stackPos -= 2;
                            context.localsPos -= context.callStack[context.stackPos];

                            //Exception handler found in the current function, just jump.
                            if(context.exceptionHandlers[context.exceptionHandlersPos].length) {
                                context.pc = context.exceptionHandlers[context.exceptionHandlersPos][$ - 1];
                            }
                        }
                        else {
                            //Kill the others.
                            foreach(coroutine; _contexts) {
                                coroutine.pc = cast(uint)(_opcodes.length - 1);
                                coroutine.isKilled = true;
                            }

                            //The VM is now panicking.
                            _isPanicking = true;
                            _panicMessage = _sglobalStack[$ - 1];
                            _sglobalStack.length --;

                            //Every deferred call has been executed, now die.
                            _contexts.markInternalForRemoval(index);
					        continue contextsLabel;
                        }
                    }
                    else {
                        //Pop the defer scope.
                        context.deferPos --;

                        //Pop the exception handlers as well.
                        context.exceptionHandlersPos --;

                        //Then returns to the last context.
                        context.stackPos -= 2;
                        context.pc = context.callStack[context.stackPos + 1u];
                        context.localsPos -= context.callStack[context.stackPos];
                    }
                    break;
                case Defer:
                    context.deferStack[context.deferPos] ~= context.pc + grBytecode_getSignedValue(opcode);
					context.pc ++;
                    break;
				case LocalStack:
                    auto stackSize = grBytecode_getUnsignedValue(opcode);
					context.callStack[context.stackPos] = stackSize;
                    context.deferPos ++;
                    context.exceptionHandlersPos ++;
					context.pc ++;
					break;
				case Call:
                    if((context.stackPos >> 1) >= context.callStackLimit) {
                        context.doubleCallStackSize();
                    }
					context.localsPos += context.callStack[context.stackPos];
					context.callStack[context.stackPos + 1u] = context.pc + 1u;
					context.stackPos += 2;
					context.pc = grBytecode_getUnsignedValue(opcode);
					break;
				case AnonymousCall:
                    if((context.stackPos >> 1) >= context.callStackLimit) {
                        context.doubleCallStackSize();
                    }
					context.localsPos += context.callStack[context.stackPos];
					context.callStack[context.stackPos + 1u] = context.pc + 1u;
					context.stackPos += 2;
					context.pc = context.istack[context.istackPos];
					context.istackPos --;
					break;
				case PrimitiveCall:
					primitives[grBytecode_getUnsignedValue(opcode)].callObject.call(context);
					context.pc ++;
					break;
				case Jump:
					context.pc += grBytecode_getSignedValue(opcode);
					break;
				case JumpEqual:
					if(context.istack[context.istackPos])
						context.pc ++;
					else
						context.pc += grBytecode_getSignedValue(opcode);
					context.istackPos --;
					break;
				case JumpNotEqual:
					if(context.istack[context.istackPos])
						context.pc += grBytecode_getSignedValue(opcode);
					else
						context.pc ++;
					context.istackPos --;
					break;
                case Build_Array:
                    GrDynamicValue[] ary;
                    const auto arySize = grBytecode_getUnsignedValue(opcode);
                    for(int i = arySize - 1; i >= 0; i --) {
                        ary ~= context.astack[context.astackPos - i];
                    }
                    context.astackPos -= arySize;
                    context.nstackPos ++;
                    context.nstack[context.nstackPos] = ary;
                    context.pc ++;
                    break;
				case Length_Array:
                    context.istackPos ++;
					context.istack[context.istackPos] = cast(int)context.nstack[context.nstackPos].length;
                    context.nstackPos --;
					context.pc ++;
					break;
				case Index_Array:
                    context.astackPos ++;
					context.astack[context.astackPos] = context.nstack[context.nstackPos][context.istack[context.istackPos]];
					context.nstackPos --;					
					context.istackPos --;					
					context.pc ++;
					break;
                case IndexRef_Array:
                    context.astack[context.astackPos].setArrayIndex(context.istack[context.istackPos]);
                    context.istackPos --;
					context.pc ++;
					break;
				default:
					throw new Exception("Invalid instruction at (" ~ to!string(context.pc) ~ "): " ~ to!string(grBytecode_getOpcode(opcode)));
                }
			}
		}
		_contexts.sweepMarkedData();
    }
}