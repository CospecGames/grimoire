/** 
 * Copyright: Enalye
 * License: Zlib
 * Authors: Enalye
 */
module grimoire.assembly.bytecode;

import std.stdio;
import std.file;
import std.outbuffer;

/// Low-level instructions for the VM.
enum GrOpcode {
    Nop, Raise, Try, Catch,
    Kill, KillAll, Yield, Task, AnonymousTask, New,

    Channel_Int, Channel_Float, Channel_String, Channel_Object,
    Send_Int, Send_Float, Send_String, Send_Object,
    Receive_Int, Receive_Float, Receive_String, Receive_Object,
    StartSelectChannel, EndSelectChannel, TryChannel, CheckChannel,

    ShiftStack_Int, ShiftStack_Float, ShiftStack_String, ShiftStack_Object,
    
    LocalStore_Int, LocalStore_Float, LocalStore_String, LocalStore_Object,
    LocalStore2_Int, LocalStore2_Float, LocalStore2_String, LocalStore2_Object,
    LocalLoad_Int, LocalLoad_Float, LocalLoad_String, LocalLoad_Object,
    
    GlobalStore_Int, GlobalStore_Float, GlobalStore_String, GlobalStore_Object,
    GlobalStore2_Int, GlobalStore2_Float, GlobalStore2_String, GlobalStore2_Object,
    GlobalLoad_Int, GlobalLoad_Float, GlobalLoad_String, GlobalLoad_Object,

    RefStore_Int, RefStore_Float, RefStore_String, RefStore_Object,
    RefStore2_Int, RefStore2_Float, RefStore2_String, RefStore2_Object,

    FieldStore_Int, FieldStore_Float, FieldStore_String, FieldStore_Object,
    FieldLoad,
    FieldLoad_Int, FieldLoad_Float, FieldLoad_String, FieldLoad_Object,
    FieldLoad2_Int, FieldLoad2_Float, FieldLoad2_String, FieldLoad2_Object,

    Const_Int, Const_Float, Const_Bool, Const_String, Const_Meta,
    
    GlobalPush_Int, GlobalPush_Float, GlobalPush_String, GlobalPush_Object,
    GlobalPop_Int, GlobalPop_Float, GlobalPop_String, GlobalPop_Object,

    Equal_Int, Equal_Float, Equal_String,
    NotEqual_Int, NotEqual_Float, NotEqual_String,
    GreaterOrEqual_Int, GreaterOrEqual_Float,
    LesserOrEqual_Int, LesserOrEqual_Float,
    Greater_Int, Greater_Float,
    Lesser_Int, Lesser_Float,
    IsNonNull_Object,

    And_Int, Or_Int, Not_Int,
    Concatenate_String,
    Add_Int, Add_Float,
    Substract_Int, Substract_Float,
    Multiply_Int, Multiply_Float,
    Divide_Int, Divide_Float,
    Remainder_Int, Remainder_Float,
    Negative_Int, Negative_Float,
    Increment_Int, Increment_Float,
    Decrement_Int, Decrement_Float,

    Swap_Int, Swap_Float, Swap_String, Swap_Object,

    SetupIterator,

    LocalStack_Int, LocalStack_Float, LocalStack_String, LocalStack_Object,
    Call, AnonymousCall, PrimitiveCall,
    Return, Unwind, Defer,
    Jump, JumpEqual, JumpNotEqual,

    Array_Int, Array_Float, Array_String, Array_Object,
    Length_Int, Length_Float, Length_String, Length_Object,
    Index_Int, Index_Float, Index_String, Index_Object,
    Index2_Int, Index2_Float, Index2_String, Index2_Object,
    Index3_Int, Index3_Float, Index3_String, Index3_Object,

    Concatenate_IntArray, Concatenate_FloatArray, Concatenate_StringArray, Concatenate_ObjectArray,
    Append_Int, Append_Float, Append_String, Append_Object,
    Prepend_Int, Prepend_Float, Prepend_String, Prepend_Object,

    Equal_IntArray, Equal_FloatArray, Equal_StringArray,
    NotEqual_IntArray, NotEqual_FloatArray, NotEqual_StringArray,

    Debug_ProfileBegin, Debug_ProfileEnd
}

/// Compiled form of grimoire.
struct GrBytecode {
    /// All the instructions.
	uint[] opcodes;

    /// Integer constants.
	int[] iconsts;

    /// Floating point constants.
	float[] fconsts;

    /// String constants.
	dstring[] sconsts;

    /// Number of int based global variables declared.
    uint iglobalsCount,
    /// Number of float based global variables declared.
        fglobalsCount,
    /// Number of string based global variables declared.
        sglobalsCount,
    /// Number of ptr based global variables declared.
        oglobalsCount;

    /// Global event functions.
    /// Their name are in a mangled state.
    uint[dstring] events;

    /// Serialize the content.
	void toOutBuffer(ref OutBuffer buffer) {
		buffer.write(cast(uint)iconsts.length);
		buffer.write(cast(uint)fconsts.length);
		buffer.write(cast(uint)sconsts.length);
		buffer.write(cast(uint)opcodes.length);
		buffer.write(cast(uint)events.length);

		foreach(uint i; iconsts)
			buffer.write(i);
		foreach(float i; fconsts)
			buffer.write(i);
		foreach(dstring i; sconsts)
			buffer.write(cast(ubyte[])i);
		foreach(uint i; opcodes)
			buffer.write(i);
        foreach(dstring ev, uint pos; events) {
			buffer.write(cast(ubyte[])ev);
			buffer.write(pos);
        }
	}
}

/// Fetch a compiled grimoire file
GrBytecode grCreateBytecodeFromFile(string fileName) {
	GrBytecode bytecode;
	File file = File(fileName, "rb");
    bytecode = grCreateBytecodeFromFile(file);
	file.close();
	return bytecode;
}

/// Fetch a compiled grimoire file
GrBytecode grCreateBytecodeFromFile(File file) {
	GrBytecode bytecode;
	uint[4] header;
	file.rawRead(header);
	bytecode.iconsts.length = cast(size_t)header[0];
	bytecode.fconsts.length = cast(size_t)header[1];
	bytecode.sconsts.length = cast(size_t)header[2];
	bytecode.opcodes.length = cast(size_t)header[3];

	if(bytecode.iconsts.length)
		file.rawRead(bytecode.iconsts);

	if(bytecode.fconsts.length)
		file.rawRead(bytecode.fconsts);

	if(bytecode.sconsts.length)
		file.rawRead(bytecode.sconsts);

	file.rawRead(bytecode.opcodes);
	return bytecode;
}

/// Get the unsigned value part of an instruction
pure uint grGetInstructionUnsignedValue(uint instruction) {
    return (instruction >> 8u) & 0xffffff;
}

/// Get the signed value part of an instruction
pure int grGetInstructionSignedValue(uint instruction) {
    return (cast(int)((instruction >> 8u) & 0xffffff)) - 0x800000;
}

/// Get the opcode part of an instruction
pure uint grGetInstructionOpcode(uint instruction) {
    return instruction & 0xff;
}

/// Format an instruction.
pure uint grMakeInstruction(uint instr, uint value1, uint value2) {
    return ((value2 << 16u) & 0xffff0000) | ((value1 << 8u) & 0xff00) | (instr & 0xff);
}