module kmain;

import stl.arch.amd64.com;
import stl.io.log;
import stl.io.vga;
import stl.arch.amd64.gdt;
import stl.arch.amd64.idt;
import stl.arch.amd64.lapic;
import hw.ps2.keyboard;
import stl.vmm.frameallocator;
import stl.address;
import stl.vmm.heap;
import stl.vmm.paging;
import hw.pci.pci;
import hw.cmos.cmos;
import arch.paging;
import stl.vmm.vmm;
import fs.tarfs;
import task.scheduler;
import syscall;
import stl.elf64;

import powerd.api;

private immutable uint _major = __VERSION__ / 1000;
private immutable uint _minor = __VERSION__ % 1000;

private __gshared TarFSBlockDevice _blockDevice;
private __gshared TarFSSuperNode* _superNode;
/// The initrd
__gshared FSNode* initrdFS;

void kmainAP(size_t id) {
	import task.scheduler : Scheduler;

	asm pure nothrow {
		sti;
	}

	GDT.flush(id);
	IDT.flush();
	LAPIC.setup();

	Scheduler.addCPUCore(id);
	SyscallHandler.init(Scheduler.getCPUInfo(id));

	while (true) {
		asm @trusted nothrow @nogc {
			// pause;
			db 0xf3, 0x90;
		}
	}
}

extern (C) void kmain(PowerDAPI* papi) {
	assert(papi.magic == PowerDAPI.magicValue);
	preInit(papi);
	welcome();
	init(papi);
	asm pure nothrow {
		sti;
	}
	initFS(papi.getModule("tarfs"));

	{
		papi.toLoader.mainAP = &kmainAP;
		papi.toLoader.done = true;
		while (true) {
			LAPIC.sleep(500);
			asm @trusted nothrow @nogc {
				// pause;
				db 0xf3, 0x90;
			}
			Scheduler.cpuInfoMutex.lock();
			bool res = Scheduler.coresActive == papi.cpus.cpuThreads.length;
			Scheduler.cpuInfoMutex.unlock();
			if (res)
				break;
		}
	}

	Scheduler.isEnabled = true;

	/*size_t counter;
	while (true) {
		VGA.writeln("counter: ", counter++);
		asm @trusted nothrow @nogc {
			// pause;
			db 0xf3, 0x90;
		}
	}*/

	string initFile = "/binaries/init";
	TarFSNode* initNode = cast(TarFSNode*)initrdFS.findNode(initFile);
	if (!initNode)
		Log.fatal("'", initFile, "' is missing, boot halted!");

	{
		ELF64 init = ELF64(VirtMemoryRange.fromArray(initNode.data));

		if (!init.isValid)
			Log.fatal("'", initFile, "' is not a ELF, boot halted!");

		ELFInstance initELF = instantiateELF(init);

		void outputBoth(Args...)(Args args, string file = __MODULE__, string func = __PRETTY_FUNCTION__, int line = __LINE__) @trusted {
			import stl.io.vga : VGA;
			import stl.io.log : Log;

			VGA.writeln(args);
			Log.info!(Args)(args, file, func, line);
		}

		outputBoth("initELF.main: ", VirtAddress(initELF.main));
		outputBoth("initELF.ctors: ");
		foreach (idx, ctor; initELF.ctors)
			outputBoth("\t", idx, ": ", VirtAddress(ctor));

		outputBoth("initELF.dtors: ");
		foreach (idx, dtor; initELF.dtors)
			outputBoth("\t", idx, ": ", VirtAddress(dtor));

		() @trusted{
			foreach (ctor; initELF.ctors) {
				outputBoth("\t Running: ", VirtAddress(ctor));
				ctor();
			}
		}();

		auto stack = newUserStack();

		VirtAddress set(T)(ref VirtAddress stack, T value) {
			import stl.trait : Unqual;

			auto size = T.sizeof;
			size = (size + 7) & ~7;
			stack -= size;
			*stack.ptr!(Unqual!T) = value;
			return stack;
		}

		VirtAddress setArray(T)(ref VirtAddress stack, T[] value) {
			import stl.trait : Unqual;

			auto size = T.sizeof * value.length;
			size = (size + 7) & ~7;
			stack -= size;
			stack.array!(Unqual!T)(value.length)[] = value[];
			return stack;
		}

		size_t[4] argvArray = [
			setArray(stack, "/binaries/init\0").num, setArray(stack, "1\0").num, setArray(stack, "2\0").num, setArray(stack, "three\0").num
		];

		auto switchToUserMode = &.switchToUserMode;
		auto main = initELF.main;
		auto argc = argvArray.length;
		auto argv = setArray(stack, argvArray).ptr;
		auto stackPtr = stack.ptr;

		//auto argv = args.ptr;

		outputBoth("Transferring control to the init elf, Good luck!");

		asm @trusted nothrow @nogc {
			mov RAX, switchToUserMode;
			mov RDI, main;
			mov RSI, stackPtr;
			mov RDX, argc;
			mov RCX, argv;
			jmp RAX;
		}
	}

	VGA.color = CGASlotColor(CGAColor.red, CGAColor.yellow);
	VGA.writeln("kmain functions has exited!");
	Log.error("kmain functions has exited!");
	while (true) {
	}
}

extern extern (C) void switchToUserMode();
extern (C) VirtAddress newUserStack() @trusted {
	VirtAddress stack = makeAddress(255, 511, 511, 511);
	static foreach (i; 0 .. 0x10) {
		if (!getKernelPaging.mapAddress(stack - 0x1000 * i, PhysAddress(), VMPageFlags.present | VMPageFlags.writable | VMPageFlags.user))
			return VirtAddress();
		getKernelPaging().makeUserAccessable(stack - 0x1000 * i);
	}
	return stack + 0x1000;
}

void preInit(PowerDAPI* papi) {
	COM.init();
	VGA.init(papi.screenX, papi.screenY);
	VGA.color = CGASlotColor(CGAColor.lightCyan, CGAColor.black);

	// dfmt off
	VGA.writeln("
\xC9\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xBB
\xBA Welcome to the PowerNex Kernel \xBA
\xC8\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xCD\xBC");
	Log.info("
╔════════════════════════════════╗
║ Welcome to the PowerNex Kernel ║
╚════════════════════════════════╝");
	// dfmt on

	{
		import stl.elf64;

		auto elf = &papi.kernelELF;
		const(ELF64SectionHeader)* symtab, strtab;
		foreach (const ref ELF64SectionHeader section; elf.sectionHeaders) {
			if (elf.lookUpSectionName(section.name) == ".symtab")
				symtab = &section;
			else if (elf.lookUpSectionName(section.name) == ".strtab")
				strtab = &section;
		}

		// TODO: probably allocate space for these. These will break when the loader is unmapped! (probably)
		ELF64Symbol[] symbols = (elf.elfData.start + symtab.offset).ptr!ELF64Symbol[0 .. symtab.size / ELF64Symbol.sizeof];
		char[] strings = (elf.elfData.start + strtab.offset).ptr!char[0 .. strtab.size];

		Log.setSymbolMap(symbols, strings);
	}

	VGA.writeln("LAPIC initializing...");
	Log.info("LAPIC initializing...");
	LAPIC.init(papi.cpus.x2APIC, papi.cpus.lapicAddress, papi.cpus.cpuBusFreq);
	LAPIC.setup();

	VGA.writeln("GDT initializing...");
	Log.info("GDT initializing...");
	GDT.init();

	VGA.writeln("IDT initializing...");
	Log.info("IDT initializing...");
	IDT.init();
}

void welcome() {
	VGA.writeln("Welcome to PowerNex!");
	VGA.writeln("\tThe number one D kernel!");
	VGA.writeln("Compiled using '", __VENDOR__, "', D version ", _major, ".", _minor, "\n");
	Log.info("Welcome to PowerNex's serial console!");
	Log.info("Compiled using '", __VENDOR__, "', D version ", _major, ".", _minor, "\n");
}

void init(PowerDAPI* papi) {
	VGA.writeln("FrameAllocator initializing...");
	Log.info("FrameAllocator initializing...");
	FrameAllocator.init(papi.memory.maxFrames, papi.memory.usedFrames, papi.memory.bitmaps, papi.memory.currentBitmapIdx);

	VGA.writeln("KernelPaging initializing...");
	Log.info("KernelPaging initializing...");

	initKernelPaging();

	VGA.writeln("KernelPaging WORKED");
	Log.info("KernelPaging WORKED");

	VGA.writeln("Heap initializing...");
	Log.info("Heap initializing...");

	Heap.init(makeAddress(500, 0, 0, 0));

	VGA.writeln("CMOS initializing...");
	Log.info("CMOS initializing...");
	CMOS.init(papi.acpi.century);

	VGA.writeln("Keyboard initializing...");
	Log.info("Keyboard initializing...");
	PS2Keyboard.init();

	VGA.writeln("PCI initializing...");
	Log.info("PCI initializing...");
	PCI.init();

	VGA.writeln("Scheduler initializing...");
	Log.info("Scheduler initializing...");
	Scheduler.init(papi.kernelStack);

	VGA.writeln("Syscall initializing...");
	Log.info("Syscall initializing...");
	SyscallHandler.init(Scheduler.getCPUInfo(0));
}

void initFS(Module* disk) @trusted {
	_blockDevice = TarFSBlockDevice(disk.memory.toVirtual);
	_superNode = newStruct!TarFSSuperNode(&_blockDevice);

	initrdFS = _superNode.base.getNode(0);
}

// TODO: Move to scheduler.d
///
struct ELFInstance {
	import powerd.api : PowerDAPI;

	int function(int argc, char** argv) @system main;
	size_t function() @system[] ctors;
	size_t function() @system[] dtors;
}

ELFInstance instantiateELF(ref ELF64 elf) @safe {
	import stl.io.log : Log;
	import stl.vmm.frameallocator : FrameAllocator;
	import arch.amd64.paging : Paging, VMPageFlags;

	ELFInstance instance;
	instance.main = () @trusted{ return cast(typeof(instance.main))elf.header.entry.ptr; }();

	foreach (ref ELF64ProgramHeader hdr; elf.programHeaders) {
		if (hdr.type != ELF64ProgramHeader.Type.load)
			continue;

		VirtAddress vAddr = hdr.vAddr;
		VirtAddress data = elf.elfData.start + hdr.offset;
		PhysAddress pData = PhysAddress(elf.elfData.start) + hdr.offset;

		Log.info("Mapping [", vAddr, " - ", vAddr + hdr.memsz, "] to [", pData, " - ", pData + hdr.memsz, "]");
		FrameAllocator.markRange(pData, pData + hdr.memsz);
		for (size_t offset; offset < hdr.memsz; offset += 0x1000) {
			import stl.number : min;

			VirtAddress addr = vAddr + offset;
			PhysAddress pAddr = pData + offset;

			// Map with writable
			if (!getKernelPaging.mapAddress(addr, PhysAddress(), VMPageFlags.present | VMPageFlags.writable, false))
				Log.fatal("Failed to map ", addr, "( to ", pAddr, ")");

			// Copying the data over, and zeroing the excess
			size_t dataLen = (offset > hdr.filesz) ? 0 : min(hdr.filesz - offset, 0x1000);
			size_t zeroLen = min(0x1000 - dataLen, hdr.memsz - offset);

			addr.memcpy(data + offset, dataLen);
			(addr + dataLen).memset(0, zeroLen);

			// Remapping with correct flags
			VMPageFlags flags = VMPageFlags.user;
			if (hdr.flags & ELF64ProgramHeader.Flags.r)
				flags |= VMPageFlags.present;
			if (hdr.flags & ELF64ProgramHeader.Flags.w)
				flags |= VMPageFlags.writable;
			if (hdr.flags & ELF64ProgramHeader.Flags.x)
				flags |= VMPageFlags.execute;

			if (!getKernelPaging.remap(addr, PhysAddress(), flags))
				Log.fatal("Failed to remap ", addr);

			getKernelPaging().makeUserAccessable(addr);
		}
	}

	alias getSectionRange = (string name) {
		foreach (ref ELF64SectionHeader section; elf.sectionHeaders)
			if (elf.lookUpSectionName(section.name) == name)
				return VirtMemoryRange(section.addr, section.addr + section.size).array!(size_t function() @system);
		return null;
	};

	instance.ctors = getSectionRange(".ctors");
	instance.dtors = getSectionRange(".dtors");

	return instance;
}
