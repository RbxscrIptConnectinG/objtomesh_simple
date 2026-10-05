local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")
local parseObj = require("@applibs/mesh/parsers/obj")

export type options = {
	__forceVer: string?,
	autoLODs: any?,
}

return function(objData, options: options): string
	options = options or {} :: options

	local mesh = parseObj(objData, true, options.autoLODs)

	local version = options.__forceVer or "3.01"

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = meshUtils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets

	local headerText = `version {version}\n`
	local headerSize = 16

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
	buffer.writeu8(out, pos + 2, meshUtils.VERTEX_SIZE)
	buffer.writeu8(out, pos + 3, meshUtils.FACE_SIZE)
	buffer.writeu16(out, pos + 4, 4) -- sizeof_LodOffset, always 4
	buffer.writeu16(out, pos + 6, numLodOffsets)
	buffer.writeu32(out, pos + 8, numVerts)
	buffer.writeu32(out, pos + 12, numFaces)
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
