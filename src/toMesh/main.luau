local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs
local process = zune.process

local arguments = process.args

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

local meshUtils = require("@applibs/mesh")
local APP_TYPES = require("./types")

local APP_ASSETS = "../../assets/toMesh"
local APP_FFI_FILES = "../../libs"

local APP_CORE = "./objtomesh"
local APP_LIBS = `{APP_CORE}/libs`

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
	fs.makeDir(APP_CORE, true)
	fs.makeDir(APP_CORE .. "/obj", true)
	fs.makeDir(APP_CORE .. "/mesh", true)

	print()
	fs.writeFileSync(`{APP_CORE}/obj/file.obj`, fs.embedFile(`{APP_ASSETS}/baseCude.obj`))
	fs.writeFileSync(`{APP_CORE}/readme.txt`, fs.embedFile(`{APP_ASSETS}/readme.txt`))
else
	print("folder already exists")
end

fs.makeDir(APP_LIBS, true)
fs.writeFileSync(`{APP_LIBS}/draco.dll`, fs.embedFile(`{APP_FFI_FILES}/dlls/draco.dll`))

do
	local settingsExist = false
	local entries = fs.entries(APP_CORE)
	for index, file in pairs(entries) do
		if file.name == "settings.json" and file.kind == "file" then
			settingsExist = true
			break
		end
	end
	if not settingsExist then
		fs.writeFileSync(`{APP_CORE}/settings.json`, fs.embedFile(`{APP_ASSETS}/settings.json`))
	end
end

local settings: APP_TYPES.Settings = serde.json5.decode(fs.readFileSync(`{APP_CORE}/settings.json`))

local objs = fs.entries("./objtomesh/obj")
for index, file in ipairs(objs) do
	if file.kind == "file" and string.match(file.name, "obj$") then
		local rawFileName = string.gsub(file.name, ".obj$", "")
		local object = fs.readFileSync(`{APP_CORE}/obj/{rawFileName}.obj`)
		fs.writeFileSync(
			`{APP_CORE}/mesh/{rawFileName}.mesh`,
			meshUtils.objToMesh(settings.encoderVer or "2.00", object)
		)
	end
end

process.exit(0)
