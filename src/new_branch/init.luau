local serde = zune.serde
local fs = zune.fs
local process = zune.process

local sift = require("@pkgs/Sift")
local environment = require("@applibs/environment")
local types = require("@self/types")
local discord = require("@libs/luau/discord")

local RPC = discord.new("1560644845788463154")

RPC:on("ready", function(user)
	print("Connected to Discord as " .. tostring(user.username))
end)
RPC:on("disconnected", function(reason)
	print("Discord disconnected: " .. tostring(reason) .. " (retrying)")
end)
RPC:on("error", function(code, message)
	warn("Discord error " .. tostring(code) .. ": " .. tostring(message))
end)

RPC:setActivity({
	details = "nothing here",
	state = "don't mind it.",
	startTimestamp = discord.now(),
	--largeImage = ":placeholder:",
	--largeText = "oi",
	buttons = { {
		label = "example",
		url = "https://example.com",
	} },
})

RPC:run()

local app = {} :: types.App
app.mesh = require("@applibs/mesh")
app.utils = require("@self/utils")(app)

do
	local __settingsPath = fs.path.join(app.utils.coordination.SYSTEM.CORE, "settings.json")
	local __settingsValid = fs.stat(__settingsPath).kind == "file"

	app.settings = __settingsValid and serde.json5.decode(fs.readFileSync(__settingsPath))
		or fs.embedFile(`{app.utils.coordination.EMBEDDED.ASSETS}/json/settings.json`)
end

app.handlers = {}

app.handlers.CLI = require("@self/handlers/CLI")
--local result = app.handlers.CLI(app, process.args)

app.handlers.UI = require("@self/handlers/UI").new(app)
app.handlers.UI:run()
RPC:close()
