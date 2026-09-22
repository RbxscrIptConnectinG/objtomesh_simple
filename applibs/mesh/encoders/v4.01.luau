local meshTypes = require("@applibs/meshTypes")
local meshUtils = require("@applibs/mesh/utils")
local parseObj = require("@applibs/mesh/parsers/obj")

local VERTEX_SIZE = 40

return function(objData, version: string): string
	local mesh = parseObj(objData, true)

	local ver = version or "4.01"

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = { 0, numFaces }
	local numLodOffsets = #lodOffsets

	local headerText = `version {ver}\n`
	local headerSize = 24

	local totalSize = #headerText + headerSize + numVerts * VERTEX_SIZE + numFaces * 12 + numLodOffsets * 4
	local out = buffer.create(totalSize)
	local pos = 0

	buffer.writestring(out, pos, headerText)
	pos += #headerText

	buffer.writeu16(out, pos, headerSize)
	buffer.writeu16(out, pos + 2, 0) -- lodType = None
	buffer.writeu32(out, pos + 4, numVerts)
	buffer.writeu32(out, pos + 8, numFaces)
	buffer.writeu16(out, pos + 12, numLodOffsets)
	buffer.writeu16(out, pos + 14, 0) -- numBones
	buffer.writeu32(out, pos + 16, 0) -- sizeof_boneNames
	buffer.writeu16(out, pos + 20, 0) -- numSubsets
	buffer.writeu8(out, pos + 22, 1) -- numHighQualityLODs
	buffer.writeu8(out, pos + 23, 0) -- unused
	pos += headerSize

	for _, v in mesh.vertices do
		meshUtils.writeVertex(out, pos, v)
		pos += VERTEX_SIZE
	end

	for _, f in mesh.faces do
		buffer.writeu32(out, pos, f.a - 1)
		buffer.writeu32(out, pos + 4, f.b - 1)
		buffer.writeu32(out, pos + 8, f.c - 1)
		pos += 12
	end

	for _, v in lodOffsets do
		buffer.writeu32(out, pos, v)
		pos += 4
	end

	return buffer.tostring(out)
end
