local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")
local parseObj = require("@applibs/mesh/parsers/obj")

export type options = { __forceVer: string? }

return function(objData, options: options): string
	options = options or {} :: options

	local mesh = parseObj(objData, true)

	local version = options.__forceVer or "4.01"

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = meshUtils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets

	local headerText = `version {version}\n`
	local headerSize = 24

	local totalSize = #headerText
		+ headerSize
		+ numVerts * meshUtils.VERTEX_SIZE
		+ numFaces * meshUtils.FACE_SIZE
		+ numLodOffsets * 4
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
	buffer.writeu8(out, pos + 22, math.max(#lodOffsets - 1, 1)) -- numHighQualityLODs

	buffer.writeu8(out, pos + 23, 0) -- unused

	pos += headerSize

	for _, v in mesh.vertices do
		meshUtils.writeVertex(out, pos, v)
		pos += meshUtils.VERTEX_SIZE
	end

	for _, f in mesh.faces do
		meshUtils.writeFace(out, pos, f)
		pos += meshUtils.FACE_SIZE
	end

	for _, v in lodOffsets do
		buffer.writeu32(out, pos, v)
		pos += 4
	end

	return buffer.tostring(out)
end
