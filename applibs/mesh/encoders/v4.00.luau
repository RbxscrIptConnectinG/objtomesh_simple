-- fallback
local sift = require("@libs/luau/sift")
local V4 = require("./v4.01")

export type options = {}

return function(objData, options: options)
	options = options or {} :: options

	return V4(
		objData,
		sift.Dictionary.join(options, {
			__forceVer = "4.00",
		})
	)
end
