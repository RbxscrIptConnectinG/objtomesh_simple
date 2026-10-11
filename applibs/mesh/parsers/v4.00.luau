--fallback.

local V4 = require("./v4.01")

return function(root, data: string, headerOffset: number)
	return V4(root, data, headerOffset)
end
