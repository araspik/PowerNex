/**
 * Contains everything related to logging.
 *
 * Copyright: © 2015-2017, Dan Printzell
 * License: $(LINK2 https://www.mozilla.org/en-US/MPL/2.0/, Mozilla Public License Version 2.0)
 *  (See accompanying file LICENSE)
 * Authors: $(LINK2 https://vild.io/, Dan Printzell)
 */
module stl.io.log;

import stl.address;

///
@safe enum LogLevel {
	verbose = 0,
	debug_,
	info,
	warning,
	error,
	fatal
}

///
char toChar(LogLevel level) @trusted {
	// dfmt off
	__gshared static char[LogLevel.max + 1] data = [
		LogLevel.verbose: '&',
		LogLevel.debug_: '+',
		LogLevel.info: '*',
		LogLevel.warning: '#',
		LogLevel.error: '-',
		LogLevel.fatal: '!'
	];
	// dfmt on

	return data[level];
}

///
@trusted static struct Log {
	import stl.elf64 : ELF64Symbol;

public static:

	/// XXX: Page fault if this is not wrapped like this!
	static ulong seconds() {
		return 0;
		/*import hw.cmos.cmos : CMOS;

		return CMOS.timeStamp();*/
	}

	///
	void setSymbolMap(ELF64Symbol[] symbols, char[] strings) @trusted {
		_symbols = symbols;
		_strings = strings;
	}

	///
	void log(Args...)(LogLevel level, Args args, string file, string func, int line) {
		import stl.arch.amd64.com : com1;
		import stl.text : itoa, BinaryInt, HexInt;
		import stl.trait : Unqual, enumMembers, isNumber, isFloating;
		import stl.address : VirtAddress, PhysAddress, PhysAddress32;

		import stl.spinlock;

		__gshared SpinLock mutex;
		mutex.lock();

		char[ulong.sizeof * 8] buf;

		_write('[', itoa(seconds(), buf, 10), ']');
		_write('[', level.toChar, "] ", file /*, ": ", func*/ , '@');

		_write(itoa(line, buf, 10));
		_write("> ");
		mainloop: foreach (arg; args) {
			alias T = Unqual!(typeof(arg));
			static if (is(T : const char[]))
				_write(arg);
			else static if (is(T == enum)) {
				foreach (i, e; enumMembers!T)
					if (arg == e) {
						_write(__traits(allMembers, T)[i]);
						continue mainloop;
					}
				_write("cast(");
				_write(T.stringof);
				_write(")");
				_write(itoa(cast(ulong)arg, buf, 10));
			} else static if (is(T == BinaryInt)) {
				_write("0b");
				_write(itoa(arg.number, buf, 2));
			} else static if (is(T == HexInt)) {
				_write("0x");
				_write(itoa(arg.number, buf, 16));
			} else static if (is(T : V*, V)) {
				_write("0x");
				string val = itoa(cast(ulong)arg, buf, 16, 16);
				_write(val[0 .. 8], '_', val[8 .. 16]);
			} else static if (is(T == VirtAddress) || is(T == PhysAddress) || is(T == PhysAddress32)) {
				_write("0x");
				string val = itoa(cast(ulong)arg.num, buf, 16, 16);
				_write(val[0 .. 8], '_', val[8 .. 16]);
			} else static if (is(T == bool))
				_write((arg) ? "true" : "false");
			else static if (is(T == char))
				_write(arg);
			else static if (isNumber!T)
				_write(itoa(arg, buf, 10));
			else static if (is(T : ubyte[])) {
				_write("[");
				foreach (idx, a; arg) {
					if (idx)
						_write(", ");
					_write(itoa(a, buf, 16));
				}
				_write("]");
			} else static if (isFloating!T)
				_write(dtoa(cast(double)arg, buf, 10));
			else
				_write("UNKNOWN TYPE '", T.stringof, "'");
		}

		_write("\r\n");

		if (level == LogLevel.fatal) {
			printStackTrace(2);

			while (!_e9 && !com1.canSend()) {
			}
			mutex.unlock();
			asm pure nothrow @trusted {
			forever:
				cli;
				hlt;
				jmp forever;
			}
		}
		while (!_e9 && !com1.canSend()) {
		}
		mutex.unlock();
	}

	///
	enum _helperFunctionsResult = _helperFunctions!();
	mixin(_helperFunctionsResult);

	///
	void printStackTrace(size_t skipLevels = 0) @trusted {
		import stl.address : VirtAddress;

		VirtAddress rbp;
		asm pure nothrow {
			mov rbp, RBP;
		}

		_printStackTrace(rbp, skipLevels);
	}

	///
	void printStackTrace(VirtAddress rbp) @trusted {
		_printStackTrace(rbp);
	}

	///
	struct Func {
		string name; ///
		ulong diff; ///
	}

	///
	Func getFuncName(VirtAddress addr) @trusted {
		import stl.text : strlen;
		import stl.vmm.paging : validAddress;

		if (!validAddress(addr))
			return Func("Address is not invalid", 0);

		if (!_symbols)
			return Func("No symbol map loaded", 0);

		foreach (symbol; _symbols) {
			if ((symbol.info & 0xF) != 0x2 /* Function */ )
				continue;

			if (addr < symbol.value || addr > symbol.value + symbol.size)
				continue;

			char* name = &_strings[symbol.name];

			return Func(cast(string)name[0 .. name.strlen], (addr - symbol.value).num);
		}

		return Func("Symbol not in map!", 0);
	}

private static:
	debug enum _e9 = true;
	else
		enum _e9 = false;
	__gshared ELF64Symbol[] _symbols;
	__gshared char[] _strings;

	void _write(Args...)(Args args) {
		import stl.io.e9;
		import stl.arch.amd64.com : com1;

		if (_e9)
			E9.write(args);
		else
			com1.write(args);
	}

	static template _helperFunctions() {
		import stl.trait : enumMembers;

		template data(LogLevel entry) {
			enum data = "///\n\tvoid " ~ __traits(allMembers, LogLevel)[entry]
					~ "(Args...)(Args args, string file = __MODULE__, string func = __PRETTY_FUNCTION__, int line = __LINE__) { log!Args(LogLevel." ~ __traits(allMembers,
							LogLevel)[entry] ~ ", args, file, func, line); }\n\n\t";
		}

		template generateWrapper(ulong idx, Trest...) {
			static if (idx == Trest.length)
				enum generateWrapper = "";
			else
				enum generateWrapper = generateWrapper!(idx + 1, Trest) ~ data!(Trest[idx]);
		}

		enum _helperFunctions = generateWrapper!(enumMembers!LogLevel);
	}

	void _printStackTrace(VirtAddress rbp, size_t skipLevels = 0) {
		import stl.address : VirtAddress;
		import stl.arch.amd64.com : com1;
		import stl.vmm.paging : validAddress;

		_write("\r\nSTACKTRACE:\r\n");
		VirtAddress rip;

		while (skipLevels--) {
			rip = rbp + ulong.sizeof;
			if (!(*rip.ptr!VirtAddress).validAddress)
				return;
			rbp = VirtAddress(*rbp.ptr!ulong);
		}

		while (rbp) {
			rip = rbp + ulong.sizeof;
			if (!rip.validAddress || !(*rip.ptr!VirtAddress).validAddress)
				break;

			_write("\t[");

			{
				import stl.text : itoa;

				char[ulong.sizeof * 8] buf;
				_write("0x");
				_write(itoa(*rip.ptr!ulong, buf, 16));
			}

			_write("] ");

			Func f = getFuncName(*rip.ptr!VirtAddress);

			_write(f.name);
			if (f.diff) {
				import stl.text : itoa;

				char[ulong.sizeof * 8] buf;
				_write("+0x");
				_write(itoa(f.diff, buf, 16));
			}

			_write("\r\n");
			rbp = VirtAddress(*rbp.ptr!ulong);
		}
	}
}
