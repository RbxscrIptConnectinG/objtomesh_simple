local fromArray = require("../Set/fromArray")
local toArray = require("../Set/toArray")

local function dedupe<T>(arr: { T }): { T }
	return toArray(fromArray(arr))
end

return dedupe
