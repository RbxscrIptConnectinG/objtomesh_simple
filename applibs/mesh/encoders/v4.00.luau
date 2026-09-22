-- fallback
local V4 = require("./v4.01")

return function(objData)
	return V4(objData, "4.00")
end
