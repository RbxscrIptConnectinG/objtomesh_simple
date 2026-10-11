local meshTypes = require("@applibs/mesh/types")

export type options = {
	__forceVer: string?,
	autoLODs: any?,
}

return function(root, objData, options: options): string
	options = options or {} :: options

	local mesh = root.parsers.obj(root, objData, true, options.autoLODs)

	local version = options.__forceVer or "3.01"

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local lodOffsets = root.utils.resolveLodOffsets(mesh)
	local numLodOffsets = #lodOffsets

	local headerText = `version {version}\n`
	local headerSize = 16

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
	buffer.writeu8(out, pos + 2, root.utils.VERTEX_SIZE)
	buffer.writeu8(out, pos + 3, root.utils.FACE_SIZE)
	buffer.writeu16(out, pos + 4, 4) -- sizeof_LodOffset, always 4
	buffer.writeu16(out, pos + 6, numLodOffsets)
	buffer.writeu32(out, pos + 8, numVerts)
	buffer.writeu32(out, pos + 12, numFaces)
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
