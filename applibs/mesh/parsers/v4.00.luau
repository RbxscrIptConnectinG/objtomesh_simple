--fallback.

local V4 = require("./v4.01")

return function(data: string, headerOffset: number)
	return V4(data, headerOffset)
end
