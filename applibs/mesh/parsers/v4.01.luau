local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")

return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)

	local numVerts = buffer.readu32(buf, off + 4)
	local numFaces = buffer.readu32(buf, off + 8)
	local numLodOffsets = buffer.readu16(buf, off + 12)
	local numBones = buffer.readu16(buf, off + 14)
	local sizeofBoneNames = buffer.readu32(buf, off + 16)
	local numSubsets = buffer.readu16(buf, off + 20)

	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = meshUtils.readVertex(buf, off)
		off += meshUtils.VERTEX_SIZE
	end

	if numBones > 0 then
		off += numVerts * 8
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

	off += numBones * 60
	off += sizeofBoneNames
	off += numSubsets * 72

	return { vertices = vertices, faces = faces, lodOffsets = lodOffsets }
end

--[[return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)

	local numVerts = buffer.readu32(buf, off + 4)
	local numFaces = buffer.readu32(buf, off + 8)
	local numLodOffsets = buffer.readu16(buf, off + 12)
	local numBones = buffer.readu16(buf, off + 14)
	local sizeofBoneNames = buffer.readu32(buf, off + 16)
	local numSubsets = buffer.readu16(buf, off + 20)

	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = meshUtils.readVertex(buf, off)
		off += VERTEX_SIZE
	end

	if numBones > 0 then
		off += numVerts * 8
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
	off += numBones * 60
	off += sizeofBoneNames
	off += numSubsets * 72

	return { vertices = vertices, faces = faces }
end
]]
