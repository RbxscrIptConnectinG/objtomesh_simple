-- fallback
local V3 = require("./v3.01")

return function(objData)
	return V3(objData, "3.00")
end
