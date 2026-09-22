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
		CORE = "./objtomesh",
		BINS = `bin`,
	},
}

c.SYSTEM.INPUT = `{c.SYSTEM.CORE}/obj`
c.SYSTEM.OUTPUT = `{c.SYSTEM.CORE}/mesh`

return c
