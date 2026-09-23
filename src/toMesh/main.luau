local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs
local process = zune.process
local task = zune.task
local time = zune.time

local tick = time.timestampMillis

local arguments = process.args

local sift = require("@libs/luau/sift")

local environment = require("@applibs/environment")

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

-- oh for fucks sake. it was hell to translate sift package to work w/ zune.

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

	if #arguments > 0 then
		local globals = {
			outputPath = "./",
		}
		arguments = sift.List.map(arguments, function(value: string, index: number)
			if value:match("^--output=") then
				globals.outputPath = value:gsub("^--output=", "")
				return value, index
			end
			return
		end)
		if #arguments > 0 then
			process.exit(0)
			return
		end
	end
end

fs.makeDir(APP_COORDINATION.SYSTEM.BINS, true)
do
	-- brain FUCKery.
	if environment.IsVSC then
		local entries = fs.entries(APP_COORDINATION.VSCODE.BINS)
		for index, file in pairs(entries) do
			if file.kind == "file" then
				local data = fs.readFileSync(`{APP_COORDINATION.VSCODE.BINS}/{file.name}`)
				fs.writeFileSync(`{APP_COORDINATION.SYSTEM.BINS}/{file.name}`, data)
			end
		end
	else
		local entries = sift.Dictionary.map(fs.embeddedFiles(), function(value: string, key: number)
			if string.match(value, "^libs\\bin\\") then
				value = value:gsub("\\", "/")
				return value, key
			end
			return nil, nil
		end)
		for index, filePath in pairs(entries) do
			local fileName = filePath:match("([^/]+)$")
			local data = fs.embedFile(`{APP_COORDINATION.EMBEDDED.ROOT}/{filePath}`)
			fs.writeFileSync(`{APP_COORDINATION.SYSTEM.BINS}/{fileName}`, data)
		end
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

local function transform(path, file, output, customSettings: APP_TYPES.Settings?)
	customSettings = customSettings and serde.json5.decode(fs.readFileSync(customSettings))

	print(file, file.kind == "file", fs.path.extension(file.name) == ".obj")
	if file.kind == "file" and fs.path.extension(file.name) == ".obj" then
		local rawFileName = fs.path.stem(file.name)
		local rawPath = fs.path.resolve(path, file.name)
		local object = fs.readFileSync(rawPath)
		local outputPath = fs.path.join(output, rawFileName)
		fs.writeFileSync(
			`{outputPath}.mesh`,
			meshUtils.objToMesh((customSettings or settings).encoderVer or "2.00", object)
		)
		print(`transformed obj into mesh, [output: {fs.realPath(`{outputPath}.mesh`)}]`)
	elseif file.kind == "file" and fs.path.extension(file.name) ~= ".obj" then
		print("oi!... wait, what the fuck?, who are you?,", `{fs.path.resolve(path, file.name)}?`)
	end
end
local function processPath(path, output)
	local pathStats = fs.stat(path)

	if pathStats.kind == "directory" then
		local objs = fs.entries(path)
		for index, file in ipairs(objs) do
			transform(path, file, output)
		end
	elseif pathStats.kind == "file" then
		local absolutePath = fs.realPath(path)
		local file = {
			name = fs.path.basename(absolutePath),
			kind = pathStats.kind,
		}
		transform(fs.path.dirname(absolutePath), file, output)
	end
end

processPath(`{APP_COORDINATION.SYSTEM.INPUT}`, `{APP_COORDINATION.SYSTEM.OUTPUT}`)

process.exit(0)
