local meshTypes = require("@applibs/meshTypes")
return function(data: string, headerOffset: number, scaler: number): meshTypes.MeshData
	scaler = scaler or 0.5
	local offset = headerOffset

	local numFacesStr, nextOffset = data:match("^(%d+)%s*()", offset)
	if not numFacesStr then
		error("Failed to parse face count in v1 mesh header")
	end

	local numFaces = tonumber(numFacesStr) :: number
	offset = nextOffset

	local vertices: { meshTypes.Vertex } = {}
	local faces: { meshTypes.Face } = {}

	local tokenPattern = "%s*%[%s*([%d%.%-%+eE]+)%s*,%s*([%d%.%-%+eE]+)%s*,%s*([%d%.%-%+eE]+)%s*%]"
	local vtxPattern = tokenPattern .. tokenPattern .. tokenPattern

	local vIndex = 1
	for f = 1, numFaces do
		for v = 1, 3 do
			local vxS, vyS, vzS, nxS, nyS, nzS, tuS, tvS, twS, endPos = data:match("^" .. vtxPattern .. "()", offset)
			if not vxS then
				error(string.format("Failed to parse vertex %d in face %d", v, f))
			end
			offset = endPos

			local vx, vy, vz =
				tonumber(vxS) :: number * scaler, tonumber(vyS) :: number * scaler, tonumber(vzS) :: number * scaler
			local nx, ny, nz = tonumber(nxS), tonumber(nyS), tonumber(nzS)
			local tu, tv, tw = tonumber(tuS), tonumber(tvS), tonumber(twS)

			local len = math.sqrt(nx * nx + ny * ny + nz * nz)
			if len > 0 then
				nx, ny, nz = nx / len, ny / len, nz / len
			else
				nx, ny, nz = 0, 0, 0
			end

			table.insert(vertices, {
				vx = vx * 0.5,
				vy = vy * 0.5,
				vz = vz * 0.5,
				nx = nx,
				ny = ny,
				nz = nz,
				tu = tu,
				tv = 1 - tv,
				tw = tw,
			})
		end

		table.insert(faces, {
			a = vIndex,
			b = vIndex + 1,
			c = vIndex + 2,
		})
		vIndex += 3
	end

	return { vertices = vertices, faces = faces }
end
