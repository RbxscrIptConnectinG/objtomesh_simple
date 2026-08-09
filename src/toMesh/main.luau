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

local converter = require("@applibs/converter")

local appAssets = "../../assets/toMesh/"
local appCore = "./objtomesh"
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
	fs.makeDir(appCore, true)
	fs.makeDir(appCore .. "/obj", true)
	fs.makeDir(appCore .. "/mesh", true)

	fs.writeFileSync(appCore .. "/obj/file.obj", fs.embedFile(appAssets .. "baseCude.obj"))
	fs.writeFileSync(appCore .. "/readme.txt", fs.embedFile(appAssets .. "readme.txt"))
else
	print("folder already exists")
end

local objs = fs.entries("./objtomesh/obj")
for index, file in ipairs(objs) do
	if file.kind == "file" and string.match(file.name, "obj$") then
		local rawFileName = string.gsub(file.name, ".obj$", "")
		local object = fs.readFileSync(`{appCore}/obj/{rawFileName}.obj`)
		fs.writeFileSync(`{appCore}/mesh/{rawFileName}.mesh`, converter.objToMesh(object))
	end
end

process.exit(0)
