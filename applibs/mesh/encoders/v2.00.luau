local meshTypes = require("@applibs/mesh/types")

export type options = {}

return function(root, objData, options: options)
	options = options or {} :: options

	local mesh = root.parsers.obj(root, objData)

	local numVerts = #mesh.vertices
	local numFaces = #mesh.faces
	local headerText = "version 2.00\n"
	local headerSize = 12

	local totalSize = #headerText + headerSize + numVerts * root.utils.VERTEX_SIZE + numFaces * root.utils.FACE_SIZE
	local out = buffer.create(totalSize)
	local pos = 0

	buffer.writestring(out, pos, headerText)
	pos += #headerText

	buffer.writeu16(out, pos, headerSize)
	buffer.writeu8(out, pos + 2, root.utils.VERTEX_SIZE)
	buffer.writeu8(out, pos + 3, 12)
	buffer.writeu32(out, pos + 4, numVerts)
	buffer.writeu32(out, pos + 8, numFaces)
	pos += headerSize

	for _, v in mesh.vertices do
		root.utils.writeVertex(out, pos, v)
		pos += root.utils.VERTEX_SIZE
	end

	for _, f in mesh.faces do
		buffer.writeu32(out, pos, f.a - 1)
		buffer.writeu32(out, pos + 4, f.b - 1)
		buffer.writeu32(out, pos + 8, f.c - 1)
		pos += 12
	end

	return buffer.tostring(out)
end
