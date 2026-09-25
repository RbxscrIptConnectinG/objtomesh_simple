local meshTypes = require("@applibs/mesh/types")

return function(data: string, headerOffset: number): meshTypes.MeshData
	local nl = data:find("\n", headerOffset + 1, true)

	local numFacesLine = data:sub(headerOffset + 1, nl - 1)
	local numFaces = tonumber(numFacesLine)

	local dataLineStart = nl + 1
	local dataLineEnd = data:find("\n", dataLineStart, true)
	local dataLine = if dataLineEnd then data:sub(dataLineStart, dataLineEnd - 1) else data:sub(dataLineStart)

	local groups: { { number } } = {}
	for inner in dataLine:gmatch("%[([^%]]+)%]") do
		local x, y, z = inner:match("^([^,]+),([^,]+),([^,]+)$")
		table.insert(groups, { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 })
	end

	local expectedGroups = numFaces * 9

	local vertices: { meshTypes.Vertex } = table.create(numFaces * 3)
	local faces: { meshTypes.Face } = table.create(numFaces)

	for f = 1, numFaces do
		local base = (f - 1) * 9
		for c = 0, 2 do
			local pos = groups[base + c * 3 + 1]
			local nrm = groups[base + c * 3 + 2]
			local uv = groups[base + c * 3 + 3]
			table.insert(vertices, {
				vx = pos[1],
				vy = pos[2],
				vz = pos[3],
				nx = nrm[1],
				ny = nrm[2],
				nz = nrm[3],
				tu = uv[1],
				tv = 1 - uv[2],
				tw = 0,
			})
		end
		local base3 = (f - 1) * 3
		faces[f] = { a = base3 + 1, b = base3 + 2, c = base3 + 3 }
	end

	return { vertices = vertices, faces = faces }
end
