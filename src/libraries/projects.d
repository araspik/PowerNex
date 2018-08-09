module src.libraries.projects;

void setupProject() {
	initDRuntime();
}

private:
import build;
import src.buildlib;

immutable {
	string dCompilerArgs = " -m64 -dip25 -dip1000 -dip1008 -fPIC -betterC -dw -color=on -debug -c -g -of$out$ $in$ -version=bare_metal -debug=allocations -defaultlib=build/objs/DRuntime/libdruntime.a -debuglib=build/objs/DRuntime/libdruntime.a -Isrc/libraries/druntime";
	string linkerArgs = " -o $out$ $in$ -nostdlib --gc-sections";
	string archiveArgs = " rcs $out$ $in$";
}

void initDRuntime() {
	Project druntime = new Project("DRuntime", SemVer(0, 1, 337));
	with (druntime) {
		// dfmt off
		auto dFiles = files!("src/libraries/druntime/",
			"core/sys/powernex/io.d",
			"rt/memory.d",
			"rt/text.d",
			"rt/trait.d",
			"object.d",
			"invariant.d"
		);
		// dfmt on

		auto dCompiler = Processor.combine(dCompilerPath ~ dCompilerArgs ~ " -version=Target_" ~ name ~ " -defaultlib= -debuglib=");
		auto archive = Processor.combine(archivePath ~ archiveArgs);

		outputs["libdruntime"] = archive("libdruntime.a", false, [dCompiler("dcode.o", false, dFiles)]);
	}
	registerProject(druntime);
}
