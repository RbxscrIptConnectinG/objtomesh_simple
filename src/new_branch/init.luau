local serde = zune.serde
local fs = zune.fs
local process = zune.process
local net = zune.net

local sift = require("@pkgs/Sift")
local environment = require("@applibs/environment")
local types = require("@self/types")

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
app.handlers.RPC = require("@self/handlers/RPC").new()
app.handlers.NET = require("@self/handlers/NET").new()
do
	app.handlers.RPC:getHandle():setActivity({
		details = "main",
		state = "in menu",
		startTimestamp = app.handlers.RPC.discord.now(),
		type = "Playing",
		largeImage = "icon",
		buttons = {
			{
				label = `Github Page [★{app.handlers.NET.repo.stars}]`,
				url = "https://github.com/RbxscrIptConnectinG/objtomesh_simple",
			},
		},
	})

	app.handlers.RPC:run()
end

app.handlers.CLI = require("@self/handlers/CLI")
--local result = app.handlers.CLI(app, process.args)

app.handlers.UI = require("@self/handlers/UI").new(app)
app.handlers.UI:run()
app.handlers.RPC:close()
