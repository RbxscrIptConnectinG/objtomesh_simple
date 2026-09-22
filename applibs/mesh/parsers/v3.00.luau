--fallback.

local V3 = require("./v3.01")

return function(data: string, headerOffset: number)
	return V3(data, headerOffset)
end
