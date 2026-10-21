local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")

export type options = {
	autoLODs: any?,
	lodType: string?,
}

return function(root, objData, options: options): string
	options = options or {} :: options

	local lodType = root.lodType[(options.lodType or "None"):lower()]

	local mesh = root.parsers.obj(root, objData, true, options.autoLODs)

	local lodOffsets = meshUtils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets
	local numHighQualityLODs = math.max(numLodOffsets - 1, 1)

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces

	local headerText = "version 6.00\n"

	-- COREMESH chunk
	local coreChunkDataSize = 4 + numVerts * meshUtils.VERTEX_SIZE + 4 + numFaces * meshUtils.FACE_SIZE
	local coreChunkTotalSize = 8 + 4 + 4 + coreChunkDataSize -- type + version + size + data

	-- LODS chunk
	local lodsChunkDataSize = 2 + 1 + 4 + numLodOffsets * 4 -- lodType(u16) + numHighQualityLODs(u8) + numLodOffsets(u32) + offsets(u32 each)
	local lodsChunkTotalSize = 8 + 4 + 4 + lodsChunkDataSize

	local totalSize = #headerText + coreChunkTotalSize + lodsChunkTotalSize
	local out = buffer.create(totalSize)
	local offset = 0

	buffer.writestring(out, offset, headerText)
	offset += #headerText

	-- COREMESH
	buffer.writestring(out, offset, "COREMESH") -- exactly 8 bytes, no padding needed
	offset += 8
	buffer.writeu32(out, offset, 1) -- chunkVersion
	offset += 4
	buffer.writeu32(out, offset, coreChunkDataSize)
	offset += 4
	buffer.writeu32(out, offset, numVerts)
	offset += 4
	for _, v in mesh.vertices do
		meshUtils.writeVertex(out, offset, v)
		offset += meshUtils.VERTEX_SIZE
	end
	buffer.writeu32(out, offset, numFaces)
	offset += 4
	for _, f in mesh.faces do
		meshUtils.writeFace(out, offset, f)
		offset += meshUtils.FACE_SIZE
	end

	-- LODS
	buffer.writestring(out, offset, "LODS")
	buffer.writeu8(out, offset + 4, 0)
	buffer.writeu8(out, offset + 5, 0)
	buffer.writeu8(out, offset + 6, 0)
	buffer.writeu8(out, offset + 7, 0)
	offset += 8
	buffer.writeu32(out, offset, 1) -- chunkVersion
	offset += 4
	buffer.writeu32(out, offset, lodsChunkDataSize)
	offset += 4
	buffer.writeu16(out, offset, lodType) -- lodType
	offset += 2
	buffer.writeu8(out, offset, numHighQualityLODs)
	offset += 1
	buffer.writeu32(out, offset, numLodOffsets)
	offset += 4
	for _, v in lodOffsets do
		buffer.writeu32(out, offset, v)
		offset += 4
	end

	return buffer.tostring(out)
end
