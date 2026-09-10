local V1 = require("./v1")

return function(data, headerOffset)
	return V1(data, headerOffset, 1)
end
