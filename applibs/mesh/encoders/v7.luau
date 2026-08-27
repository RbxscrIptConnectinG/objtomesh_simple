local Draco = require("@applibs/draco")
local meshTypes = require("@applibs/meshTypes")
local parseObj = require("@applibs/mesh/parsers/obj")

return function(objData)
	local mesh = parseObj(objData, true)

	local dracoBytes = Draco.encodeMeshFull(mesh.vertices, mesh.faces, nil)
	local dracoSize = buffer.len(dracoBytes)

	local headerText = "version 7.00\n"

	local coreChunkDataSize = 4 + dracoSize
	local coreChunkTotalSize = 8 + 4 + 4 + coreChunkDataSize

	local lodsChunkDataSize = 2 + 1 + 4 + 4 + 4
	local lodsChunkTotalSize = 8 + 4 + 4 + lodsChunkDataSize

	local totalSize = #headerText + coreChunkTotalSize + lodsChunkTotalSize
	local out = buffer.create(totalSize)
	local offset = 0

	buffer.writestring(out, offset, headerText)
	offset += #headerText

	buffer.writestring(out, offset, "COREMESH")
	offset += 8
	buffer.writeu32(out, offset, 2)
	offset += 4
	buffer.writeu32(out, offset, coreChunkDataSize)
	offset += 4
	buffer.writeu32(out, offset, dracoSize)
	offset += 4
	buffer.copy(out, offset, dracoBytes, 0, dracoSize)
	offset += dracoSize

	buffer.writestring(out, offset, "LODS")
	buffer.writeu8(out, offset + 4, 0)
	buffer.writeu8(out, offset + 5, 0)
	buffer.writeu8(out, offset + 6, 0)
	buffer.writeu8(out, offset + 7, 0)
	offset += 8
	buffer.writeu32(out, offset, 1)
	offset += 4
	buffer.writeu32(out, offset, lodsChunkDataSize)
	offset += 4
	buffer.writeu16(out, offset, 0)
	offset += 2
	buffer.writeu8(out, offset, 1)
	offset += 1
	buffer.writeu32(out, offset, 2)
	offset += 4
	buffer.writeu32(out, offset, 0)
	offset += 4
	buffer.writeu32(out, offset, 0)
	offset += 4

	return out
end
