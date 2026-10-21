-- fallback
local sift = require("@pkgs/Sift")
local V4 = require("./v4.01")

export type options = {
	autoLODs: any?,
}

return function(root, objData, options: options): string
	options = options or {} :: options

	return V4(
		root,
		objData,
		sift.Dictionary.join(options, {
			__forceVer = "4.00",
		})
	)
end
