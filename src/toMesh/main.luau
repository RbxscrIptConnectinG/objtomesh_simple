local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs
local process = zune.process
local task = zune.task
local time = zune.time

local tick = time.timestampMillis

local arguments = process.args

local __environment = {
	IsVSC = #fs.embeddedFiles() <= 0,
}

-- that's for another update.
--[[if #arguments > 0 then
	local out, outIndex = "./", nil
	for index, argument: string in ipairs(arguments) do
		if string.match(argument, "^--out=") then
			out, outIndex = string.gsub(argument, "^--out=", ""), index
		end
	end
	print("OUTPOINT:", out)
	print(arguments)
	zune.process.exit(0)
	return
end
]]

print("working on:", process.cwd())

--[[if true then
	-- fuzzy
	local raylib = require("@libs/luau/raylib")
	raylib.lib.InitWindow(450, 450, "TestWindow")
	raylib.lib.SetTargetFPS(60)
	local thang = 0.001
	while raylib.lib.WindowShouldClose() == 0 do
		local delta = raylib.lib.GetFrameTime()
		local FPS = raylib.lib.GetFPS()

		local render_width = raylib.lib.GetRenderWidth()
		local render_height = raylib.lib.GetRenderHeight()

		local center_render_width = render_width // 2
		local center_render_height = render_height // 2

		local ratio = render_width // render_height
		raylib.lib.BeginDrawing()
		do
			raylib.lib.ClearBackground(raylib.const.BLACK)

			raylib.lib.DrawCubeWires(
				vector.create(0, 0, 0),
				20,
				center_render_width,
				center_render_height,
				raylib.const.GREEN
			)

			--raylib.lib.DrawRectangle(center_render_width - 10, center_render_height - 1, 20, 2, raylib.const.GREEN)
			--raylib.lib.DrawRectangle(center_render_width - 1, center_render_height - 10, 2, 20, raylib.const.GREEN)

			raylib.lib.DrawText(tostring(FPS), 0, 0, 20 / ratio, raylib.const.GREEN)
		end
		raylib.lib.EndDrawing()
	end
	process.exit(0)
	return
end]]

local meshUtils = require("@applibs/mesh")

local APP_TYPES = require("./types")
local APP_COORDINATION = require("./coordination")

local localEntries = fs.entries("./")
local appFolderExists = false

for index, folder in pairs(localEntries) do
	if folder.name == "objtomesh" and folder.kind == "directory" then
		appFolderExists = true
		break
	end
end
if not appFolderExists then
	print("no folder yet, making one right up!")
	fs.makeDir(APP_COORDINATION.SYSTEM.CORE, true)
	fs.makeDir(APP_COORDINATION.SYSTEM.CORE .. "/obj", true)
	fs.makeDir(APP_COORDINATION.SYSTEM.CORE .. "/mesh", true)

	fs.writeFileSync(
		`{APP_COORDINATION.SYSTEM.CORE}/obj/file.obj`,
		fs.embedFile(`{APP_COORDINATION.EMBEDDED.ASSETS}/baseCude.obj`)
	)
	fs.writeFileSync(
		`{APP_COORDINATION.SYSTEM.CORE}/readme.txt`,
		fs.embedFile(`{APP_COORDINATION.EMBEDDED.ASSETS}/readme.txt`)
	)
else
	print("folder already exists")
end

fs.makeDir(APP_COORDINATION.SYSTEM.BINS, true)
do
	-- doin unpacking em' bins

	if __environment.IsVSC then
		local entries = fs.entries(APP_COORDINATION.EMBEDDED.BINS)

		for index, file in pairs(entries) do
			if file.kind == "file" and string.match(file.name, ".dll$") then
				local data = fs.readFileSync(`{APP_COORDINATION.EMBEDDED.BINS}/{file.name}`)
				fs.writeFileSync(`{APP_COORDINATION.SYSTEM.BINS}/{file.name}`, data)

				break
			end
		end
	else
		local draco_data = fs.embedFile(`{APP_COORDINATION.EMBEDDED.BINS}/draco.dll`)

		fs.writeFileSync(`{APP_COORDINATION.SYSTEM.BINS}/draco.dll`, draco_data)
	end
end

do
	local settingsExist = false
	local entries = fs.entries(APP_COORDINATION.SYSTEM.CORE)
	for index, file in pairs(entries) do
		if file.name == "settings.json" and file.kind == "file" then
			settingsExist = true
			break
		end
	end
	if not settingsExist then
		fs.writeFileSync(
			`{APP_COORDINATION.SYSTEM.CORE}/settings.json`,
			fs.embedFile(`{APP_COORDINATION.EMBEDDED.ASSETS}/settings.json`)
		)
	end
end

local settings: APP_TYPES.Settings = serde.json5.decode(fs.readFileSync(`{APP_COORDINATION.SYSTEM.CORE}/settings.json`))

local objs = fs.entries(APP_COORDINATION.SYSTEM.INPUT)
for index, file in ipairs(objs) do
	if file.kind == "file" and string.match(file.name, ".obj$") then
		local rawFileName = string.gsub(file.name, ".obj$", "")
		local object = fs.readFileSync(`{APP_COORDINATION.SYSTEM.INPUT}/{rawFileName}.obj`)
		fs.writeFileSync(
			`{APP_COORDINATION.SYSTEM.OUTPUT}/{rawFileName}.mesh`,
			meshUtils.objToMesh(settings.encoderVer or "2.00", object)
		)
	end
end

process.exit(0)
