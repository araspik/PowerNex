module app;

import core.sys.powernex.io;

int main(string[] args) {
	write(StdFile.stdout, "Hello world from Userspace!");

	return cast(int)(0xC0DE_0000 + args.length);
}
