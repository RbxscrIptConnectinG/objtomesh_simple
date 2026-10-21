local meshTypes = require("@applibs/mesh/types")

export type options = {
	__forceVer: string?,
	autoLODs: any?,
	lodType: string?,
}

return function(root, objData, options: options): string
	options = options or {} :: options

	local lodType = root.lodType[(options.lodType or "None"):lower()]

	local mesh = root.parsers.obj(root, objData, true, options.autoLODs)

	local version = options.__forceVer or "4.01"

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = root.utils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets

	local headerText = `version {version}\n`
	local headerSize = 24

	local totalSize = #headerText
		+ headerSize
		+ numVerts * root.utils.VERTEX_SIZE
		+ numFaces * root.utils.FACE_SIZE
		+ numLodOffsets * 4
	local out = buffer.create(totalSize)
	local pos = 0

	buffer.writestring(out, pos, headerText)
	pos += #headerText

	buffer.writeu16(out, pos, headerSize)
	buffer.writeu16(out, pos + 2, lodType) -- lodType
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
		root.utils.writeVertex(out, pos, v)
		pos += root.utils.VERTEX_SIZE
	end

	for _, f in mesh.faces do
		root.utils.writeFace(out, pos, f)
		pos += root.utils.FACE_SIZE
	end

	for _, v in lodOffsets do
		buffer.writeu32(out, pos, v)
		pos += 4
	end

	return buffer.tostring(out)
end
