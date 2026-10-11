local meshTypes = require("./types")
local utils = {}
utils.VERTEX_SIZE = 40
utils.FACE_SIZE = 12
function utils.readVertex(data: buffer, offset: number): meshTypes.Vertex
	return {
		vx = buffer.readf32(data, offset),
		vy = buffer.readf32(data, offset + 4),
		vz = buffer.readf32(data, offset + 8),
		nx = buffer.readf32(data, offset + 12),
		ny = buffer.readf32(data, offset + 16),
		nz = buffer.readf32(data, offset + 20),
		tu = buffer.readf32(data, offset + 24),
		tv = 1 - buffer.readf32(data, offset + 28),
		tw = 0,
	}
end

function utils.writeVertex(out: buffer, offset: number, v: meshTypes.Vertex)
	buffer.writef32(out, offset, v.vx)
	buffer.writef32(out, offset + 4, v.vy)
	buffer.writef32(out, offset + 8, v.vz)
	buffer.writef32(out, offset + 12, v.nx)
	buffer.writef32(out, offset + 16, v.ny)
	buffer.writef32(out, offset + 20, v.nz)
	buffer.writef32(out, offset + 24, v.tu)
	buffer.writef32(out, offset + 28, 1 - v.tv)
	-- Placeholder tangent, roughly {X:1,Y:0,Z:0,Sign:+1}.
	buffer.writei8(out, offset + 32, 127)
	buffer.writei8(out, offset + 33, 0)
	buffer.writei8(out, offset + 34, 0)
	buffer.writei8(out, offset + 35, 127)
	-- Placeholder opaque white.
	buffer.writeu8(out, offset + 36, 255)
	buffer.writeu8(out, offset + 37, 255)
	buffer.writeu8(out, offset + 38, 255)
	buffer.writeu8(out, offset + 39, 255)
end

function utils.readFace(data: buffer, offset: number): meshTypes.Face
	return {
		a = buffer.readu32(data, offset) + 1, -- 0-based on disk -> 1-based here
		b = buffer.readu32(data, offset + 4) + 1,
		c = buffer.readu32(data, offset + 8) + 1,
	}
end

function utils.writeFace(out: buffer, offset: number, f: meshTypes.Face)
	buffer.writeu32(out, offset, f.a - 1) -- 1-based here -> 0-based on disk
	buffer.writeu32(out, offset + 4, f.b - 1)
	buffer.writeu32(out, offset + 8, f.c - 1)
end

function utils.resolveLodOffsets(mesh: meshTypes.MeshData): { number }
	local numFaces = #mesh.faces
	local provided = mesh.lodOffsets
	if not provided then
		return { 0, numFaces }
	end
	if provided[1] ~= 0 or provided[#provided] ~= numFaces then
		error(
			`meshUtils.resolveLodOffsets: lodOffsets must start at 0 and end at #faces ({numFaces}) - got \{{provided[1]}, ..., {provided[#provided]}\}`
		)
	end
	for i = 2, #provided do
		if provided[i] < provided[i - 1] then
			error("meshUtils.resolveLodOffsets: lodOffsets must be non-decreasing")
		end
	end
	return provided
end

function utils.fmt(n: number): string
	return string.format("%.6g", n)
end

function utils.parseIndex(token: string, count: number): number?
	if token == "" then
		return nil
	end
	local n = tonumber(token)
	if not n then
		return nil
	end
	if n < 0 then
		return count + n + 1 -- OBJ relative indices count back from the current total
	end
	return n
end

utils.autoLOD = {
	QEM = require("./autoLOD/QEM"),
	MC = require("./autoLOD/MC"),
}

return utils
