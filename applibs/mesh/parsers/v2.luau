local meshTypes = require("@applibs/meshTypes")
return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1
	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)
	local numVertices = buffer.readu32(buf, offset + 4)
	local numFaces = buffer.readu32(buf, offset + 8)

	offset += 12

	if cbSize ~= 12 or cbVerticesStride ~= 36 or cbFaceStride ~= 12 then
		error("Incompatible version 2.00 mesh stride or size header")
	end

	local vertices: { meshTypes.Vertex } = table.create(numVertices)
	for i = 1, numVertices do
		local vx = buffer.readf32(buf, offset)
		local vy = buffer.readf32(buf, offset + 4)
		local vz = buffer.readf32(buf, offset + 8)

		local nx = buffer.readf32(buf, offset + 12)
		local ny = buffer.readf32(buf, offset + 16)
		local nz = buffer.readf32(buf, offset + 20)

		local tu = buffer.readf32(buf, offset + 24)
		local tv = buffer.readf32(buf, offset + 28)
		local tw = buffer.readf32(buf, offset + 32)

		vertices[i] = {
			vx = vx,
			vy = vy,
			vz = vz,
			nx = nx,
			ny = ny,
			nz = nz,
			tu = tu,
			tv = 1 - tv,
			tw = tw,
		}

		offset += cbVerticesStride
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		local a = buffer.readu32(buf, offset) + 1
		local b = buffer.readu32(buf, offset + 4) + 1
		local c = buffer.readu32(buf, offset + 8) + 1

		faces[i] = { a = a, b = b, c = c }
		offset += cbFaceStride
	end

	return { vertices = vertices, faces = faces }
end
