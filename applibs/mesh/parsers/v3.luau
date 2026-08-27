local meshTypes = require("@applibs/meshTypes")
-- probably broken too
return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1

	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)

	local numLODs = buffer.readu16(buf, offset + 4)
	local numSubsets = buffer.readu16(buf, offset + 6)

	local numFaces = buffer.readu32(buf, offset + 8)
	local numVertices = buffer.readu32(buf, offset + 12)

	offset += cbSize

	if cbVerticesStride ~= 36 or cbFaceStride ~= 12 then
		error("Incompatible version 3.00 mesh stride")
	end

	local vertices: { meshTypes.Vertex } = table.create(numVertices)
	for i = 1, numVertices do
		vertices[i] = {
			vx = buffer.readf32(buf, offset),
			vy = buffer.readf32(buf, offset + 4),
			vz = buffer.readf32(buf, offset + 8),
			nx = buffer.readf32(buf, offset + 12),
			ny = buffer.readf32(buf, offset + 16),
			nz = buffer.readf32(buf, offset + 20),
			tu = buffer.readf32(buf, offset + 24),
			tv = 1 - buffer.readf32(buf, offset + 28),
			tw = buffer.readf32(buf, offset + 32),
		}
		offset += cbVerticesStride
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = {
			a = buffer.readu32(buf, offset) + 1,
			b = buffer.readu32(buf, offset + 4) + 1,
			c = buffer.readu32(buf, offset + 8) + 1,
		}
		offset += cbFaceStride
	end

	return { vertices = vertices, faces = faces }
end
