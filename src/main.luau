local io = zune.io
local net = zune.net
local serde = zune.serde
local fs = zune.fs

local exist, object = pcall(fs.readFileSync, "./objtomesh/obj/file.obj")

if not exist then
	fs.makeDir("./objtomesh", true)
	fs.makeDir("./objtomesh/obj", true)
	fs.makeDir("./objtomesh/mesh", true)
	fs.writeFileSync("./objtomesh/obj/file.obj", require("./assets/file"))
	fs.writeFileSync("./objtomesh/readme.txt", require("./assets/readme"))
	object = fs.readFileSync("./objtomesh/obj/file.obj")
end

local convert = require("./buffalowings")

fs.writeFileSync("./objtomesh/mesh/file.mesh", convert(object))

zune.process.exit(0)
