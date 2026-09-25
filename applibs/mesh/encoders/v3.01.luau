local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")
local parseObj = require("@applibs/mesh/parsers/obj")

local VERTEX_SIZE = 40

return function(objData, version): string
	version = version or "3.01"
	local mesh = parseObj(objData, true)

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = { 0, numFaces } -- trivial: single quality level
	local numLodOffsets = #lodOffsets

	local headerText = `version {version}\n`
	local headerSize = 16

	local totalSize = #headerText + headerSize + numVerts * VERTEX_SIZE + numFaces * 12 + numLodOffsets * 4
	local out = buffer.create(totalSize)
	local pos = 0

	buffer.writestring(out, pos, headerText)
	pos += #headerText

	buffer.writeu16(out, pos, headerSize)
	buffer.writeu8(out, pos + 2, VERTEX_SIZE)
	buffer.writeu8(out, pos + 3, 12) -- sizeof_face
	buffer.writeu16(out, pos + 4, 4) -- sizeof_LodOffset, always 4
	buffer.writeu16(out, pos + 6, numLodOffsets)
	buffer.writeu32(out, pos + 8, numVerts)
	buffer.writeu32(out, pos + 12, numFaces)
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
