-- fallback
local sift = require("@pkgs/Sift")
local V3 = require("./v3.01")

export type options = {}

return function(objData, options: options)
	options = options or {} :: options

	return V3(
		objData,
		sift.Dictionary.join(options, {
			__forceVer = "3.00",
		})
	)
end
