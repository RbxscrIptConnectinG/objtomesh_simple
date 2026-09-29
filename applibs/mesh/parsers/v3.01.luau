local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")

return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)
	local vertexSize = buffer.readu8(buf, off + 2)
	-- byte at off+3 (sizeof_face) is always 12, not read
	-- u16 at off+4 (sizeof_LodOffset) is always 4, not read
	local numLodOffsets = buffer.readu16(buf, off + 6)
	local numVerts = buffer.readu32(buf, off + 8)
	local numFaces = buffer.readu32(buf, off + 12)
	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = meshUtils.readVertex(buf, off)
		off += vertexSize
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = meshUtils.readFace(buf, off)
		off += meshUtils.FACE_SIZE
	end

	local lodOffsets: { number } = table.create(numLodOffsets)
	for i = 1, numLodOffsets do
		lodOffsets[i] = buffer.readu32(buf, off)
		off += 4
	end

	return { vertices = vertices, faces = faces, lodOffsets = lodOffsets }
end

--[[

	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)
	local vertexSize = buffer.readu8(buf, off + 2)

	local numLodOffsets = buffer.readu16(buf, off + 6)
	local numVerts = buffer.readu32(buf, off + 8)
	local numFaces = buffer.readu32(buf, off + 12)
	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = meshUtils.readVertex(buf, off)
		off += vertexSize
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = {
			a = buffer.readu32(buf, off) + 1,
			b = buffer.readu32(buf, off + 4) + 1,
			c = buffer.readu32(buf, off + 8) + 1,
		}
		off += 12
	end

	off += numLodOffsets * 4

	return { vertices = vertices, faces = faces }

]]
