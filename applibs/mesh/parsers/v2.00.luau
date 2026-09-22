local meshTypes = require("@applibs/meshTypes")
local meshUtils = require("@applibs/mesh/utils")

return function(data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local off = headerOffset

	local headerSize = buffer.readu16(buf, off)
	local vertexSize = buffer.readu8(buf, off + 2)
	local numVerts = buffer.readu32(buf, off + 4)
	local numFaces = buffer.readu32(buf, off + 8)
	off += headerSize

	local vertices: { meshTypes.Vertex } = table.create(numVerts)
	for i = 1, numVerts do
		vertices[i] = meshUtils.readVertex(buf, off)
		off += vertexSize
	end

	local faces: { meshTypes.Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = {
			a = buffer.readu32(buf, off) + 1,
			b = buffer.readu32(buf, off + 4) + 1,
			c = buffer.readu32(buf, off + 8) + 1,
		}
		off += 12
	end

	return { vertices = vertices, faces = faces }
end
