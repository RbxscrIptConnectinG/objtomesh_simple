local meshTypes = require("@applibs/mesh/types")
local DracoTypes = require("@applibs/draco/types")

local mesh = {}
mesh.parsers = {
	["v1.00"] = require("@self/parsers/v1.00"),
	["v1.01"] = require("@self/parsers/v1.01"),
	["v2.00"] = require("@self/parsers/v2.00"),

	["v3.00"] = require("@self/parsers/v3.00"),
	["v3.01"] = require("@self/parsers/v3.01"),

	["v4.00"] = require("@self/parsers/v4.00"),
	["v4.01"] = require("@self/parsers/v4.01"),

	--v5 = require("@self/parsers/v5"),
	--v6 = require("@self/parsers/v6"),
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

	["7.00"] = require("@self/encoders/v7.00"),
}

-- this is stupid. i  know...
mesh.parsers["v5.00"] = mesh.parsers["v4.00"]
mesh.parsers["v6.00"] = mesh.parsers["v5.00"]

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
		return mesh.parsers[simplified](data, contentOffset)
	else
		error(`Unsupported mesh version: "{tostring(header)}"`)
	end

	--[[	if header == "version 1.00" then
		return mesh.parsers.v1(data, contentOffset, 0.5)
	elseif header == "version 1.01" then
		return mesh.parsers.v1(data, contentOffset, 1.0)
	elseif header == "version 2.00" then
		return mesh.parsers.v2(data, contentOffset)
	elseif header == "version 3.00" or header == "version 3.01" then
		return mesh.parsers.v3(data, contentOffset)
	elseif header == "version 4.00" or header == "version 4.01" then
		return mesh.parsers.v4(data, contentOffset)
	elseif header == "version 5.00" then
		return mesh.parsers.v5(data, contentOffset)
	elseif header == "version 6.00" then
		return mesh.parsers.v6(data, contentOffset)
	elseif header == "version 7.00" then
		return mesh.parsers.v7(data, contentOffset)
	else
		error(`Unsupported mesh version: "{tostring(header)}"`)
	end]]
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

function mesh.objToMesh(version: string, objData: string, ...: DracoTypes.EncodeOptions? | any): string
	if not mesh.encoders[version] then
		error(`Version "{version}" encoder isn't implemented yet!`)
	end
	return mesh.encoders[version](objData, ...)
end

function mesh.convertMeshToOBJ(data: string): string
	local decodedmesh = mesh.decodeMesh(data)
	return mesh.meshToOBJ(decodedmesh)
end

return mesh
