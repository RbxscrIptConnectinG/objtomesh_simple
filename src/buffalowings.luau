return function(objText)
	local vertices = {}
	local normals = {}
	local uvs = {}
	local faces = {}

	for line in string.gmatch(objText, "[^\r\n]+") do
		local vx, vy, vz = string.match(line, "^v%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)")
		vx, vy, vz = tonumber(vx), tonumber(vy), tonumber(vz)
		if vx then
			table.insert(vertices, { vx * 0.5, vy * 0.5, vz * 0.5 })
		end

		local nx, ny, nz = string.match(line, "^vn%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)")
		if nx then
			table.insert(normals, { nx, ny, nz })
		end
		local tu, tv = string.match(line, "^vt%s+([%d.-]+)%s+([%d.-]+)")
		tu, tv = tonumber(tv), tonumber(tv)
		if tu then
			table.insert(uvs, { tu, 1 - tv })
		end

		if string.sub(line, 1, 2) == "f " then
			local faceVertices = {}
			for vStr in string.gmatch(line, "%s+([^%s]+)") do
				local v, vt, vn = string.match(vStr, "([%d.-]+)/?([%d.-]*)/?([%d.-]*)")
				if v then
					table.insert(faceVertices, {
						v = tonumber(v),
						vt = tonumber(vt) or 0,
						vn = tonumber(vn) or 0,
					})
				end
			end
			if #faceVertices >= 3 then
				for i = 2, #faceVertices - 1 do
					table.insert(faces, { faceVertices[1], faceVertices[i], faceVertices[i + 1] })
				end
			end
		end
	end
	local faceData = {}

	for _, face in ipairs(faces) do
		for i = 1, 3 do
			local vertIndices = face[i]

			local pos = vertices[vertIndices.v] or { 0, 0, 0 }

			local norm = normals[vertIndices.vn] or { 0, 1, 0 }

			local uv = uvs[vertIndices.vt] or { 0, 0 }

			local vertStr = string.format(
				"[%f,%f,%f][%f,%f,%f][%f,%f,0]",
				pos[1],
				pos[2],
				pos[3],
				norm[1],
				norm[2],
				norm[3],
				uv[1],
				uv[2]
			)
			table.insert(faceData, vertStr)
		end
	end

	local line1 = "version 1.00"
	local line2 = tostring(#faces)
	local line3 = table.concat(faceData, "\n")

	return line1 .. "\n" .. line2 .. "\n" .. line3
end
