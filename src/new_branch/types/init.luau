local types = require("@applibs/types")

export type Utils = {
	coordination: { any },
	fileManip: {
		processPath: (
			input: string | { any },
			output: string,
			customSettings: types.meshSettings?,
			isParse: boolean?
		) -> nil,
	},
}

export type App = {
	mesh: types.MeshWorks,
	utils: Utils,
	handlers: {
		CLI: (root: App, arguments: { any }?) -> {
			outputPath: string,
			inputs: { string },
		}?,
		UI: {
			getRender: (self: any) -> { any },
			run: (self: any) -> nil,
		},
	},
}

return {}
