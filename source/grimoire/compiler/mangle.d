/**
    Mangling functions for type signatures.

    Copyright: (c) Enalye 2018
    License: Zlib
    Authors: Enalye
*/

module grimoire.compiler.mangle;

import std.conv: to;
import grimoire.compiler.type;

/**
    Mangle a signature of types.

    Example:
    ---
    func(int i, string s, func(bool, float)) float {}
    ---
    Will be mangled as `$i$s$f($b$f)$v`

    The return type is not conserved in the mangled form as its not part of its signature.
    But function. passed as parameters have theirs.
*/
dstring grMangleFunction(GrType[] signature) {
	dstring mangledName;
	foreach(type; signature) {
		mangledName ~= "$";
		final switch(type.baseType) with(GrBaseType) {
		case VoidType:
			mangledName ~= "*";
			break;
		case IntType:
			mangledName ~= "i";
			break;
		case FloatType:
			mangledName ~= "r";
			break;
		case BoolType:
			mangledName ~= "b";
			break;
		case StringType:
			mangledName ~= "s";
			break;
		case ArrayType:
			mangledName ~= "n";
			break;
		case VariantType:
			mangledName ~= "v";
			break;
        case TupleType:
            mangledName ~= "l(" ~ type.mangledType ~ ")";
            break;
        case StructType:
			mangledName ~= "p(" ~ type.mangledType ~ ")";
			break;
        case UserType:
            mangledName ~= "u(" ~ type.mangledType ~ ")";
            break;
		case FunctionType:
			mangledName ~= "f(" ~ type.mangledType ~ ")(" ~ type.mangledReturnType ~ ")";
			break;
		case TaskType:
			mangledName ~= "t(" ~ type.mangledType ~ ")";
			break;
        case ChanType:
			mangledName ~= "c(" ~ type.mangledType ~ ")";
			break;
        case InternalTupleType:
            throw new Exception("Trying to mangle a tuple. Tuples should not exist here.");
		}
	}
	return mangledName;
}

dstring grMangleVariant(GrType type) {
    return grMangleFunction([type]);
}

/**
    Mangle a named function.

    Example:
    ---
    func test(int i, string s, func(bool, float)) float {}
    ---
    Will be mangled as `test$i$s$f($b$f)$v`

    The return type is not conserved in the mangled form as its not part of its signature.
    But function. passed as parameters have theirs.
*/
dstring grMangleNamedFunction(dstring name, GrType[] signature) {
	return name ~ grMangleFunction(signature);
}

/**
    Get the type of the function.
*/
GrType grGetFunctionAsType(GrFunction func) {
    GrType type = func.isTask ? GrBaseType.TaskType : GrBaseType.FunctionType;
    type.mangledType = grMangleNamedFunction("", func.inSignature);
    type.mangledReturnType = grMangleNamedFunction("", func.outSignature);
    return type;
}

/**
    Reverse the mangling operation for a function passed as a parameter.
*/
dstring grUnmangleSubFunction(dstring mangledSignature, ref int i) {
    dstring subString;
    int blockCount = 1;
    if(i >= mangledSignature.length && mangledSignature[i] != '(')
        throw new Exception("Invalid mangling format");
    i ++;

    for(; i < mangledSignature.length; i ++) {
        switch(mangledSignature[i]) {
        case '(':
            blockCount ++;
            break;
        case ')':
            blockCount --;
            if(blockCount == 0) {
                return subString;
            }
            break;
        default:
            break;
        }
        subString ~= mangledSignature[i];
    }
    throw new Exception("Invalid mangling format");
}

/**
    Reverse the mangling operation for a single type.
*/
GrType grUnmangle(dstring mangledSignature) {
    GrType currentType = GrBaseType.VoidType;

    int i;
    if(i < mangledSignature.length) {
        //Type separator
        if(mangledSignature[i] != '$')
            throw new Exception("Invalid mangling format");
        i ++;

        //Value
        switch(mangledSignature[i]) {
        case '*':
            currentType.baseType = GrBaseType.VoidType;
            break;
        case 'i':
            currentType.baseType = GrBaseType.IntType;
            break;
        case 'r':
            currentType.baseType = GrBaseType.FloatType;
            break;
        case 'b':
            currentType.baseType = GrBaseType.BoolType;
            break;
        case 's':
            currentType.baseType = GrBaseType.StringType;
            break;
        case 'n':
            currentType.baseType = GrBaseType.ArrayType;
            break;
        case 'v':
            currentType.baseType = GrBaseType.VariantType;
            break;
        case 'l':
            currentType.baseType = GrBaseType.TupleType;
            dstring tupleName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                tupleName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = tupleName;
            break;
        case 'p':
            currentType.baseType = GrBaseType.StructType;
            dstring structName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                structName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = structName;
            break;
        case 'u':
            currentType.baseType = GrBaseType.UserType;
            dstring userTypeName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                userTypeName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = userTypeName;
            break;
        case 'f':
            i ++;
            currentType.baseType = GrBaseType.FunctionType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            i ++;
            currentType.mangledReturnType = grUnmangleSubFunction(mangledSignature, i);
            i ++;
            break;
        case 't':
            i ++;
            currentType.baseType = GrBaseType.TaskType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            i ++;
            break;
        case 'c':
            i ++;
            currentType.baseType = GrBaseType.ChanType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            i ++;
            break;
        default:
            break;
        }
    }

    return currentType;
}

/**
    Reverse the mangling operation for a function signature (not named).
*/
GrType[] grUnmangleSignature(dstring mangledSignature) {
    GrType[] unmangledSignature;

    int i;
    while(i < mangledSignature.length) {
        //Type separator
        if(mangledSignature[i] != '$')
            throw new Exception("Invalid mangling format");
        i ++;

        //Value
        GrType currentType = GrBaseType.VoidType;
        switch(mangledSignature[i]) {
        case '*':
            currentType.baseType = GrBaseType.VoidType;
            break;
        case 'i':
            currentType.baseType = GrBaseType.IntType;
            break;
        case 'r':
            currentType.baseType = GrBaseType.FloatType;
            break;
        case 'b':
            currentType.baseType = GrBaseType.BoolType;
            break;
        case 's':
            currentType.baseType = GrBaseType.StringType;
            break;
        case 'n':
            currentType.baseType = GrBaseType.ArrayType;
            break;
        case 'v':
            currentType.baseType = GrBaseType.VariantType;
            break;
        case 'l':
            currentType.baseType = GrBaseType.TupleType;
            dstring tupleName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                tupleName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = tupleName;
            break;
        case 'p':
            currentType.baseType = GrBaseType.StructType;
            dstring structName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                structName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = structName;
            break;
        case 'u':
            currentType.baseType = GrBaseType.UserType;
            dstring userTypeName;
            if((i + 2) >= mangledSignature.length)
                throw new Exception("Invalid mangling format");
            i ++;
            if(mangledSignature[i] != '(')
                throw new Exception("Invalid mangling format");
            i ++;
            while(mangledSignature[i] != ')') {
                userTypeName ~= mangledSignature[i];
                i ++;
                if(i >= mangledSignature.length)
                    throw new Exception("Invalid mangling format");
            }
            currentType.mangledType = userTypeName;
            break;
        case 'f':
            i ++;
            currentType.baseType = GrBaseType.FunctionType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            i ++;
            currentType.mangledReturnType = grUnmangleSubFunction(mangledSignature, i);
            break;
        case 't':
            i ++;
            currentType.baseType = GrBaseType.TaskType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            break;
        case 'c':
            i ++;
            currentType.baseType = GrBaseType.ChanType;
            currentType.mangledType = grUnmangleSubFunction(mangledSignature, i);
            break;
        default:
            break;
        }
        unmangledSignature ~= currentType;
        i ++;
    }
    return unmangledSignature;
}

/**
    Convert a type into a pretty format for display.
*/
string grGetPrettyType(GrType variableType) {
    final switch(variableType.baseType) with(GrBaseType) {
    case VoidType:
        return "void";
    case IntType:
        return "int";
    case FloatType:
        return "float";
    case BoolType:
        return "bool";
    case StringType:
        return "string";
    case ArrayType:
        return "array";
    case VariantType:
        return "var";
    case FunctionType:
        string result = "func(";
        int i;
        auto inSignature = grUnmangleSignature(variableType.mangledType);
        foreach(type; inSignature) {
            result ~= grGetPrettyType(type);
            if((i + 2) <= inSignature.length)
                result ~= ", ";
            i ++;
        }
        result ~= ")";
        auto outSignature = grUnmangleSignature(variableType.mangledReturnType);
        if(outSignature.length)
            result ~= " ";
        foreach(type; outSignature) {
            result ~= grGetPrettyType(type);
            if((i + 2) <= outSignature.length)
                result ~= ", ";
            i ++;
        }
        return result;
    case ChanType:
        string result = "chan(";
        int i;
        auto parameters = grUnmangleSignature(variableType.mangledType);
        foreach(parameter; parameters) {
            result ~= grGetPrettyType(parameter);
            if((i + 2) <= parameters.length)
                result ~= ", ";
            i ++;
        }
        result ~= ")";
        return result;
    case TaskType:
        string result = "task(";
        int i;
        auto parameters = grUnmangleSignature(variableType.mangledType);
        foreach(parameter; parameters) {
            result ~= grGetPrettyType(parameter);
            if((i + 2) <= parameters.length)
                result ~= ", ";
            i ++;
        }
        result ~= ")";
        return result;
    case TupleType:
    case StructType:
    case UserType:
        return to!string(variableType.mangledType);
    case InternalTupleType:
        throw new Exception("Trying to display a tuple. Tuples should not exist here.");
    }
}
