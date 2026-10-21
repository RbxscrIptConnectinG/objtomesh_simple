local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")

return function(root, data: string, headerOffset: number): meshTypes.MeshData
	local buf = buffer.fromstring(data)
	local size = buffer.len(buf)

	local vertices: { meshTypes.Vertex }? = nil
	local faces: { meshTypes.Face }? = nil
	local lodOffsets: { number }? = nil

	local offset = headerOffset
	while offset < size do
		if offset + 16 > size then
			break -- not enough bytes left for a full chunk header; stop
		end

		local chunkType = buffer.readstring(buf, offset, 8)
		local chunkVersion = buffer.readu32(buf, offset + 8)
		local chunkSize = buffer.readu32(buf, offset + 12)
		local dataStart = offset + 16

		if dataStart + chunkSize > size then
			error(`parsers/6_00: chunk '{chunkType}' claims {chunkSize} bytes but only {size - dataStart} remain`)
		end

		if chunkType == "COREMESH" then
			if chunkVersion ~= 1 then
				error(
					`parsers/6_00: COREMESH chunk version {chunkVersion} isn't the plain vertex/face layout (expected version 1)`
				)
			end

			local numVerts = buffer.readu32(buf, dataStart)
			local vertsStart = dataStart + 4
			local verts: { meshTypes.Vertex } = table.create(numVerts)
			for i = 0, numVerts - 1 do
				verts[i + 1] = meshUtils.readVertex(buf, vertsStart + i * meshUtils.VERTEX_SIZE)
			end

			local facesCountOffset = vertsStart + numVerts * meshUtils.VERTEX_SIZE
			local numFaces = buffer.readu32(buf, facesCountOffset)
			local facesStart = facesCountOffset + 4
			local fcs: { meshTypes.Face } = table.create(numFaces)
			for i = 0, numFaces - 1 do
				fcs[i + 1] = meshUtils.readFace(buf, facesStart + i * meshUtils.FACE_SIZE)
			end

			vertices, faces = verts, fcs
		elseif chunkType == "LODS\0\0\0\0" then
			local numLodOffsets = buffer.readu32(buf, dataStart + 3)
			local offsets = table.create(numLodOffsets)
			for i = 1, numLodOffsets do
				offsets[i] = buffer.readu32(buf, dataStart + 7 + (i - 1) * 4)
			end
			lodOffsets = offsets
		end
		-- Other chunk types (SKINNING, FACS, HSRAVIS) are skipped.

		offset = dataStart + chunkSize
	end

	if not vertices or not faces then
		error("parsers/6_00: no COREMESH chunk found in file")
	end

	return { vertices = vertices, faces = faces, lodOffsets = lodOffsets }
end
