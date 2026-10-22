local meshTypes = require("@applibs/mesh/types")

return function(root, data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)
	local lodType = buffer.readu16(buf, off + 2)

	local numVerts = buffer.readu32(buf, off + 4)
	local numFaces = buffer.readu32(buf, off + 8)
	local numLodOffsets = buffer.readu16(buf, off + 12)
	local numBones = buffer.readu16(buf, off + 14)
	local sizeofBoneNames = buffer.readu32(buf, off + 16)
	local numSubsets = buffer.readu16(buf, off + 20)

	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = root.utils.readVertex(buf, off)
		off += root.utils.VERTEX_SIZE
	end

	if numBones > 0 then
		off += numVerts * 8
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = root.utils.readFace(buf, off)
		off += root.utils.FACE_SIZE
	end

	local lodOffsets: { number } = table.create(numLodOffsets)
	for i = 1, numLodOffsets do
		lodOffsets[i] = buffer.readu32(buf, off)
		off += 4
	end

	off += numBones * 60
	off += sizeofBoneNames
	off += numSubsets * 72

	return {
		header = {
			lodType = lodType,
		},
		vertices = vertices,
		faces = faces,
		lodOffsets = lodOffsets,
	}
end
