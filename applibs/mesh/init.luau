local meshTypes = require("@self/types")
local Sift = require("@pkgs/Sift")
local DracoTypes = require("@applibs/draco/types")

local mesh = {}
mesh.utils = require("@self/utils")
mesh.parsers = {
	["obj"] = require("@self/parsers/obj"),
	["v1.00"] = require("@self/parsers/v1.00"),
	["v1.01"] = require("@self/parsers/v1.01"),
	["v2.00"] = require("@self/parsers/v2.00"),

	["v3.00"] = require("@self/parsers/v3.00"),
	["v3.01"] = require("@self/parsers/v3.01"),

	["v4.00"] = require("@self/parsers/v4.00"),
	["v4.01"] = require("@self/parsers/v4.01"),

	["v5.00"] = require("@self/parsers/v5.00"),

	["v6.00"] = require("@self/parsers/v6.00"),
	["v7.00"] = require("@self/parsers/v7.00"),
}
mesh.encoders = {
	["1.00"] = require("@self/encoders/v1.00"),
	["1.01"] = require("@self/encoders/v1.01"),
	["2.00"] = require("@self/encoders/v2.00"),

	["3.00"] = require("@self/encoders/v3.00"),
	["3.01"] = require("@self/encoders/v3.01"),

	["4.00"] = require("@self/encoders/v4.00"),
	["4.01"] = require("@self/encoders/v4.01"),
	["5.00"] = require("@self/encoders/v5.00"),

	["6.00"] = require("@self/encoders/v6.00"),
	["7.00"] = require("@self/encoders/v7.00"),
}

mesh.lodType = {
	None = 0,
	Unknown = 1,
	RbxSimplifier = 2,
	ZeuxMeshOptimizer = 3,
}

-- questionable.
mesh.lodType = Sift.Dictionary.map(mesh.lodType, function(value: number, key: string, dictionary)
	return value, key:lower()
end)

function mesh.decodeMesh(data: string): meshTypes.MeshData
	local lineEnd = data:find("\n")
	if not lineEnd then
		error("Invalid mesh file: missing header newline")
	end

	local header = data:sub(1, lineEnd - 1):match("^%s*(.-)%s*$")
	local contentOffset = lineEnd + 1

	local simplified = string.gsub(header, "version ", "v")
	print(header, simplified)
	if mesh.parsers[simplified] then
		return mesh.parsers[simplified](mesh, data, contentOffset)
	else
		error(`Unsupported mesh version: "{tostring(header)}"`)
	end
end

function mesh.meshToOBJ(mesh: meshTypes.MeshData): string
	local lines = { "# Exported from Roblox FileMesh" }

	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("v %.6f %.6f %.6f", v.vx or 0, v.vy or 0, v.vz or 0))
	end
	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("vt %.6f %.6f", v.tu, v.tv))
	end
	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("vn %.6f %.6f %.6f", v.nx, v.ny, v.nz))
	end
	for _, f in ipairs(mesh.faces) do
		table.insert(lines, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d", f.a, f.a, f.a, f.b, f.b, f.b, f.c, f.c, f.c))
	end

	return table.concat(lines, "\n")
end

function mesh.objToMesh(version: string, objData: string, ...: DracoTypes.EncodeOptions? | any?): string
	if not mesh.encoders[version] then
		error(`Version "{version}" encoder isn't implemented yet!`)
	end
	return mesh.encoders[version](mesh, objData, ...)
end

function mesh.convertMeshToOBJ(data: string): string
	local decodedmesh = mesh.decodeMesh(data)
	return mesh.meshToOBJ(decodedmesh)
end

return mesh
