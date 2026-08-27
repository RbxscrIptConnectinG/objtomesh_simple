local meshTypes = require("@applibs/meshTypes")
local parseObj = require("@applibs/mesh/parsers/obj")

return function(objData)
	local parsedObj = parseObj(objData)

	local headerSize = 12
	local vertexStride = 36
	local faceStride = 12

	local numVertices = #parsedObj.vertices
	local numFaces = #parsedObj.faces

	local totalSize = headerSize + (numVertices * vertexStride) + (numFaces * faceStride)
	local buf = buffer.create(totalSize)

	buffer.writeu16(buf, 0, headerSize)
	buffer.writeu8(buf, 2, vertexStride)
	buffer.writeu8(buf, 3, faceStride)
	buffer.writeu32(buf, 4, numVertices)
	buffer.writeu32(buf, 8, numFaces)

	local offset = headerSize

	for _, v in ipairs(parsedObj.vertices) do
		buffer.writef32(buf, offset + 0, v.vx)
		buffer.writef32(buf, offset + 4, v.vy)
		buffer.writef32(buf, offset + 8, v.vz)

		buffer.writef32(buf, offset + 12, v.nx)
		buffer.writef32(buf, offset + 16, v.ny)
		buffer.writef32(buf, offset + 20, v.nz)

		buffer.writef32(buf, offset + 24, v.tu)
		buffer.writef32(buf, offset + 28, v.tv)
		buffer.writef32(buf, offset + 32, v.tw)

		offset += vertexStride
	end

	for _, f in ipairs(parsedObj.faces) do
		buffer.writeu32(buf, offset + 0, f.a - 1)
		buffer.writeu32(buf, offset + 4, f.b - 1)
		buffer.writeu32(buf, offset + 8, f.c - 1)

		offset += faceStride
	end

	return "version 2.00\n" .. buffer.tostring(buf)
end
