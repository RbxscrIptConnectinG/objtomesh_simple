-- unused, but can be useful if you want to.
return function(objString)
	local vertices = {}
	local texcoords = {}
	local normals = {}
	local faces = {}

	for line in objString:gmatch("[^\r\n]+") do
		if not line:match("^#") and line:match("%S") then
			local prefix, data = line:match("^([a-zA-Z]+)%s+(.*)")

			if prefix == "v" then
				local x, y, z = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(vertices, { tonumber(x), tonumber(y), tonumber(z) })
			elseif prefix == "vt" then
				local u, v = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(texcoords, { tonumber(u), tonumber(v) })
			elseif prefix == "vn" then
				local nx, ny, nz = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(normals, { tonumber(nx), tonumber(ny), tonumber(nz) })
			elseif prefix == "f" then
				local faceIndices = {}
				for vertexStr in data:gmatch("%S+") do
					local parts = {}
					for p in vertexStr:gmatch("[^/]*") do
						if p ~= "" then
							table.insert(parts, tonumber(p))
						end
					end
					table.insert(faceIndices, parts)
				end
				table.insert(faces, faceIndices)
			end
		end
	end

	return {
		vertices = vertices,
		texcoords = texcoords,
		normals = normals,
		faces = faces,
	}
end
