local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs
local process = zune.process

local arguments = process.args

-- ignore those tests.

--[[
local testing = true

if testing then
	--[[local meshmanip = require("@applibs/mesh")
	fs.makeDir("./TESTING_OUTPUT", true)
	local testingMaterials = fs.entries("./assets/testingMaterial")
	for index, file in ipairs(testingMaterials) do
		if file.kind == "file" and string.match(file.name, "mesh$") then
			local rawFileName = string.gsub(file.name, ".mesh$$", "")
			local filePath = "./assets/testingMaterial" .. "/" .. file.name
			local contents = fs.readFileSync(filePath)
			local meshData = meshmanip.decodeMesh(contents)

			fs.writeFileSync("./TESTING_OUTPUT/" .. rawFileName .. ".json", serde.json5.encode(meshData))
			fs.writeFileSync("./TESTING_OUTPUT/" .. rawFileName .. ".obj", meshmanip.meshToOBJ(meshData))
		end
	end]]
--[[
	local Draco = require("@applibs/FFI_DRACO")

	--local compressed = Draco.encodeMesh(vertices, indices, 14)
	--print(`Compressed size: {buffer.len(compressed)} bytes (raw was {#vertices * 4 + #indices * 4} bytes)`)
	local compressed = buffer.fromstring(fs.readFileSync("./assets/draco.mesh"))
	local outVerts, outIndices = Draco.decodeMesh(compressed)
	print(`Decoded {#outVerts // 3} vertices, {#outIndices} indices`)

	return
end
]]

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

local meshmanip = require("@applibs/mesh")

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
		fs.writeFileSync(`{appCore}/mesh/{rawFileName}.mesh`, meshmanip.objToMesh(object))
	end
end

process.exit(0)
