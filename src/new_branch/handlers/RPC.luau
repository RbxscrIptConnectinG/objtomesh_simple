local environment = require("@applibs/environment")

local RPC = {}
RPC.__index = RPC
RPC.discord = require("@libs/luau/discord")
RPC.appId = "1560644845788463154"

function RPC.new()
	local self = setmetatable({}, RPC)
	self.handle = self.discord.new(self.appId, {
		debug = environment.IsDebug,
	})
	self.handle:on("ready", function(user)
		print(`Rich presence: {tostring(user.username)} [CONNECTED]`)
	end)
	self.handle:on("disconnected", function(reason)
		print(`Rich presence: {tostring(reason)} [DISCONNECTED]`)
	end)
	self.handle:on("error", function(code, message)
		print(`Rich presence: {tostring(code)}: {tostring(message)} [ERROR]`)
	end)

	return self
end

function RPC:getHandle()
	return self.handle
end

function RPC:run(...)
	self.handle:run(...)
end

function RPC:close(...)
	self.handle:close(...)
end

return RPC
