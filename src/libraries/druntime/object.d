// PowerNexOS runtime
// Based on object.d in druntime
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file BOOST-LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

module object;

version (X86_64) {
	alias size_t = ulong;
	alias ptrdiff_t = long;
	alias string = immutable(char)[]; // TODO: Create wrapper for strings
}

version (PowerNex) import core.sys.powernex.io;

bool __equals(T1, T2)(T1[] lhs, T2[] rhs) {
	import stl.trait : Unqual;

	alias RealT1 = Unqual!T1;
	alias RealT2 = Unqual!T2;

	static if (is(RealT1 == RealT2) && is(RealT1 == void)) {
		auto lhs_ = cast(ubyte[])lhs;
		auto rhs_ = cast(ubyte[])rhs;
		if (lhs_.length != rhs_.length)
			return false;
		foreach (idx, a; lhs_)
			if (a != rhs_[idx])
				return false;
		return true;
	} else static if (is(RealT1 == RealT2)) {
		if (lhs.length != rhs.length)
			return false;
		foreach (idx, a; lhs)
			if (a != rhs[idx])
				return false;
		return true;
	} else static if (__traits(compiles, { RealT2 a; auto b = cast(RealT1)a; }())) {
		if (lhs.length != rhs.length)
			return false;
		foreach (idx, a; lhs)
			if (a != cast(RealT1)rhs[idx])
				return false;
		return true;

	} else {
		pragma(msg, "I don't know what to do!: ", __PRETTY_FUNCTION__);
		assert(0, "I don't know what to do!");
	}
}

void __switch_error()(string file = __FILE__, size_t line = __LINE__) {
	assert(0, "Final switch fallthough! " ~ __PRETTY_FUNCTION__);
}

extern (C) void[] _d_arraycast(ulong toTSize, ulong fromTSize, void[] a) @trusted {
	//import stl.io.log : Log;

	auto len = a.length * fromTSize;
	assert(len % toTSize == 0, "_d_arraycast failed!");

	return a[0 .. len / toTSize];
}

extern (C) void[] _d_arraycopy(size_t size, void[] from, void[] to) @trusted {
	import rt.memory : memmove;

	memmove(to.ptr, from.ptr, from.length * size);
	return to;
}

extern (C) void __assert(const char* msg_, const char* file_, int line) @trusted {
	import rt.text;

	//TODO: stderr.write("assert failed: ", msg, file, "<UNK>", line);
	write(StdFile.stderr, "assert failed!");
	string msg = cast(string)msg_[0 .. strlen(msg_)];
	string file = cast(string)file_[0 .. strlen(file_)];
	write(StdFile.stderr, msg);
	write(StdFile.stderr, file);

	while (true) {
	}
}

private extern (C) int _Dmain(char[][] args);
private alias extern (C) int function(char[][] args) MainFunc;

private extern (C) int _d_run_main(int argc, char** argv, MainFunc mainFunc) {
	import rt.text;

	char[][64] args = void;
	if (argc > args.length)
		argc = args.length;

	for (int i; i < argc; i++) {
		char* cArg = argv[i];
		args[i] = cArg[0 .. strlen(cArg)];
	}

	return mainFunc(args[0 .. argc]);
}

// Provided by dmd!
private extern (C) int main(int argc, char** argv);

private extern (C) void _start() {
	asm @trusted @nogc nothrow {
		naked;
		call main;
		mov RDI, RAX;
		mov RAX, 0;
		//syscall;
		int 0x80;
	}
}
