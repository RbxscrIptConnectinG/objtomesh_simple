local meshTypes = require("@applibs/meshTypes")
return function(objData: string): meshTypes.MeshData
	local positions: { { number } } = {}
	local uvs: { { number } } = {}
	local normals: { { number } } = {}

	local uniqueVertices: { meshTypes.Vertex } = {}
	local vertexMap: { [string]: number } = {}
	local faces: { meshTypes.Face } = {}

	local function getOrAddVertex(vIdx: number, vtIdx: number, vnIdx: number): number
		local key = string.format("%d/%d/%d", vIdx, vtIdx, vnIdx)
		if vertexMap[key] then
			return vertexMap[key]
		end

		local pos = positions[vIdx] or { 0, 0, 0 }
		local uv = uvs[vtIdx] or { 0, 0 }
		local norm = normals[vnIdx] or { 0, 0, 0 }

		local vertex: meshTypes.Vertex = {
			vx = pos[1],
			vy = pos[2],
			vz = pos[3],
			nx = norm[1],
			ny = norm[2],
			nz = norm[3],
			tu = uv[1],
			tv = 1 - uv[2],
			tw = 0,
		}

		table.insert(uniqueVertices, vertex)
		local newIdx = #uniqueVertices
		vertexMap[key] = newIdx
		return newIdx
	end

	for line in objData:gmatch("[^\r\n]+") do
		line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")

		if line ~= "" then
			local parts = {}
			for part in line:gmatch("%S+") do
				table.insert(parts, part)
			end

			local tag = parts[1]
			if tag == "v" and #parts >= 4 then
				table.insert(positions, { tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]) })
			elseif tag == "vt" and #parts >= 3 then
				table.insert(uvs, { tonumber(parts[2]), tonumber(parts[3]) })
			elseif tag == "vn" and #parts >= 4 then
				table.insert(normals, { tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]) })
			elseif tag == "f" and #parts >= 4 then
				local faceIndices = {}
				for i = 2, #parts do
					local vI, vtI, vnI = parts[i]:match("^(%d*)/?(%d*)/?(%d*)")
					local vIdx = tonumber(vI) or 0
					local vtIdx = tonumber(vtI) or 0
					local vnIdx = tonumber(vnI) or 0

					if vIdx < 0 then
						vIdx = #positions + vIdx + 1
					end
					if vtIdx < 0 then
						vtIdx = #uvs + vtIdx + 1
					end
					if vnIdx < 0 then
						vnIdx = #normals + vnIdx + 1
					end

					table.insert(faceIndices, getOrAddVertex(vIdx, vtIdx, vnIdx))
				end

				for i = 2, #faceIndices - 1 do
					table.insert(faces, {
						a = faceIndices[1],
						b = faceIndices[i],
						c = faceIndices[i + 1],
					})
				end
			end
		end
	end

	return { vertices = uniqueVertices, faces = faces }
end
