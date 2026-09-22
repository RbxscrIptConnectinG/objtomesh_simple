local meshTypes = require("@applibs/meshTypes")
local utils = {}
utils.VERTEX_SIZE = 40
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

function utils.fmt(n: number): string
	return string.format("%.6g", n)
end

return utils
