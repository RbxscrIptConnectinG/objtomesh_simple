return {
	IsNotCompiled = not zune.compiled,
	IsDebug = zune.compiled and zune.compiled.mode == "debug" or false,
	RootPath = zune.fs.path.dirname(zune.fs.getExePath()),
}
