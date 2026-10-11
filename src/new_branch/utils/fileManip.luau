local serde = zune.serde
local fs = zune.fs

local sift = require("@pkgs/Sift")

local fileManip = {}
fileManip.__index = fileManip

function fileManip.new(app)
	local self = setmetatable({}, fileManip)

	self.app = app

	return self
end

function fileManip:transform(path, file, output, customSettings, isParse: boolean?)
	customSettings = customSettings and serde.json5.decode(fs.readFileSync(customSettings))
	local local_settings = (customSettings or self.app.settings)
	if not isParse then
		if file.kind == "file" and fs.path.extension(file.name) == ".obj" then
			local rawFileName = fs.path.stem(file.name)
			local rawPath = fs.path.resolve(path, file.name)
			local object = fs.readFileSync(rawPath)
			local outputPath = fs.path.join(output, rawFileName)
			fs.writeFileSync(
				`{outputPath}.mesh`,
				self.app.mesh.objToMesh(local_settings.encoderVer or "2.00", object, local_settings.options)
			)
			print(`transformed obj into mesh, [output: {fs.realPath(`{outputPath}.mesh`)}]`)
		elseif file.kind == "file" and fs.path.extension(file.name) ~= ".obj" then
			print("oi!... wait, what the fuck?, who are you?,", `{fs.path.resolve(path, file.name)}?`)
		end
	else
		print("not implemented yet")
	end
end

function fileManip:processPath(input, output, customSettings, isParse)
	local function processIt(path)
		local pathStats = fs.stat(path)
		if pathStats.kind == "directory" then
			local objs = fs.entries(path)
			for index, file in ipairs(objs) do
				fileManip:transform(path, file, output, customSettings, isParse)
			end
		elseif pathStats.kind == "file" then
			local absolutePath = fs.realPath(path)
			local file = {
				name = fs.path.basename(absolutePath),
				kind = pathStats.kind,
			}
			fileManip:transform(fs.path.dirname(absolutePath), file, output, customSettings, isParse)
		end
	end

	if typeof(input) == "table" then
		sift.List.map(input, function(p, index: number)
			processIt(p)
		end)
	else
		processIt(input)
	end
end

return fileManip
