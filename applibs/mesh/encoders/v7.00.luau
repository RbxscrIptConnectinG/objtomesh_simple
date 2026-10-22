local Draco = require("@applibs/draco")
local meshTypes = require("@applibs/mesh/types")

export type options = {
	draco: Draco.EncodeOptions?,
	autoLODs: any?,
	lodType: string?,
}

return function(root, objData, options: options): string
	options = options or {} :: options

	local lodType = root.lodType[(options.lodType or "None"):lower()]

	local mesh = root.parsers.obj(root, objData, true, options.autoLODs)
	local dracoBytes = Draco.encodeMeshFull(mesh.vertices, mesh.faces, options.draco)
	local dracoSize = buffer.len(dracoBytes)
	local lodOffsets = root.utils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets
	local numHighQualityLODs = math.max(numLodOffsets - 1, 1)

	local headerText = "version 7.00\n"

	-- COREMESH chunk
	local coreChunkDataSize = 4 + dracoSize -- dracoBitStreamSize field + the stream itself
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
	buffer.writeu32(out, offset, 2) -- chunkVersion
	offset += 4
	buffer.writeu32(out, offset, coreChunkDataSize)
	offset += 4
	buffer.writeu32(out, offset, dracoSize)
	offset += 4
	buffer.copy(out, offset, dracoBytes, 0, dracoSize)
	offset += dracoSize

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
