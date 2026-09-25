local fs = zune.fs
local environment = require("@applibs/environment")
local c = {
	VSCODE = {
		ASSETS = "./assets/toMesh",
		BINS = "./libs/bin",
	},
	EMBEDDED = {
		ROOT = "../..",
		ASSETS = "../../assets/toMesh",
		BINS = "../../libs/bin",
	},

	SYSTEM = {
		CORE = fs.path.join(environment.RootPath, "objtomesh"),
		BINS = fs.path.join(environment.RootPath, `bin`),
	},
}

c.SYSTEM.INPUT = `{c.SYSTEM.CORE}/obj`
c.SYSTEM.OUTPUT = `{c.SYSTEM.CORE}/mesh`

return c
