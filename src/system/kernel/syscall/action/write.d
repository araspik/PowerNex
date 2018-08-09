module syscall.action.write;

import syscall;

@Syscall(2) @SyscallArgument!(size_t) @SyscallArgument!(string) size_t write(size_t fileID, string msg) {
	import stl.io.vga : VGA;
	VGA.writeln("[", fileID, "] ", msg);
	return msg.length;
}
