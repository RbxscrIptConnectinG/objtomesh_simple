local meshtypes = require("@applibs/meshtypes")
-- i'll have to fix it some day...
return function(data: string, headerOffset: number): meshtypes.MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1

	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)

	local numLODs = buffer.readu16(buf, offset + 4)
	local numSubsets = buffer.readu16(buf, offset + 6)

	local numFaces = buffer.readu32(buf, offset + 8)
	local numVertices = buffer.readu32(buf, offset + 12)
	local numBones = buffer.readu32(buf, offset + 16)

	offset += cbSize

	local vertices: { meshtypes.Vertex } = table.create(numVertices)
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
			vx = vx ~= vx and 0 or vx,
			vy = vy ~= vy and 0 or vy,
			vz = vz ~= vz and 0 or vz,
			nx = nx ~= nx and 0 or nx,
			ny = ny ~= ny and 0 or ny,
			nz = nz ~= nz and 0 or nz,
			tu = tu ~= tu and 0 or tu,
			tv = 1 - (tv ~= tv and 0 or tv),
			tw = tw ~= tw and 0 or tw,
		}

		offset += cbVerticesStride
	end

	if numBones > 0 then
		offset += (numVertices * 8)
	end

	local faces: { meshtypes.Face } = table.create(numFaces)
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
