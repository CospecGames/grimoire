/**
    Grimoire compiler.

    Copyright: (c) Enalye 2018
    License: Zlib
    Authors: Enalye
*/

module compiler.compiler;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import std.math;
import std.file;

import runtime.all;
import assembly.all;
import compiler.lexer;
import compiler.parser;
import lib.all;

/// Compile a source file into bytecode
GrBytecode grCompiler_compileFile(string fileName) {
	grLib_std_load();

	GrLexer lexer = new GrLexer;
	lexer.scanFile(to!dstring(fileName));

	Parser parser = new Parser;
	parser.parseScript(lexer);

	return generate(parser);
}

private {
	uint makeOpcode(uint instr, uint value) {
		return ((value << 8u) & 0xffffff00) | (instr & 0xff);
	}

	GrBytecode generate(Parser parser) {
		uint nbOpcodes, lastOpcodeCount;

		foreach(func; parser.functions)
			nbOpcodes += cast(uint)func.instructions.length;

		foreach(func; parser.anonymousFunctions)
			nbOpcodes += cast(uint)func.instructions.length;

		//Opcodes
		uint[] opcodes = new uint[nbOpcodes];

		//Write the main function first (not callable).
		auto mainFunc = "main"d in parser.functions;
		if(mainFunc is null)
			throw new Exception("No main declared.");

		foreach(uint i, instruction; mainFunc.instructions)
			opcodes[i] = makeOpcode(cast(uint)instruction.opcode, instruction.value);
		lastOpcodeCount = cast(uint)mainFunc.instructions.length;
		parser.functions.remove("main");

		//Every other functions.
		foreach(func; parser.anonymousFunctions) {
			foreach(uint i, instruction; func.instructions)
				opcodes[lastOpcodeCount + i] = makeOpcode(cast(uint)instruction.opcode, instruction.value);
			foreach(call; func.functionCalls)
				call.position += lastOpcodeCount;
			func.position = lastOpcodeCount;
			lastOpcodeCount += func.instructions.length;
		}
		foreach(func; parser.functions) {
			foreach(uint i, instruction; func.instructions)
				opcodes[lastOpcodeCount + i] = makeOpcode(cast(uint)instruction.opcode, instruction.value);
			foreach(call; func.functionCalls)
				call.position += lastOpcodeCount;
			func.position = lastOpcodeCount;
			lastOpcodeCount += func.instructions.length;
		}
		parser.solveFunctionCalls(opcodes);

		GrBytecode bytecode;
		bytecode.iconsts = parser.iconsts;
		bytecode.fconsts = parser.fconsts;
		bytecode.sconsts = parser.sconsts;
		bytecode.opcodes = opcodes;
		return bytecode;
	}
}