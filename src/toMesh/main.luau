local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs

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
	fs.makeDir("./objtomesh", true)
	fs.makeDir("./objtomesh/obj", true)
	fs.makeDir("./objtomesh/mesh", true)
	fs.writeFileSync("./objtomesh/obj/file.obj", require("./assets/file"))
	fs.writeFileSync("./objtomesh/readme.txt", require("./assets/readme"))
else
	print("folder already exists")
end
local convert = require("./converts/main")

local objs = fs.entries("./objtomesh/obj")
for index, file in ipairs(objs) do
	if file.kind == "file" and string.match(file.name, "obj$") then
		local rawFileName = string.gsub(file.name, ".obj$", "")
		local object = fs.readFileSync(`./objtomesh/obj/{rawFileName}.obj`)
		fs.writeFileSync(`./objtomesh/mesh/{rawFileName}.mesh`, convert.objToMesh(object))
	end
end

zune.process.exit(0)
