local meshTypes = require("@applibs/mesh/types")
local sift = require("@pkgs/Sift")

return function(
	root,
	objData: string,
	noInvertUV: boolean?,
	autoLods: {
		method: string | "QEM" | "MC" | "ZeuxMeshOptimizer",
		levels: number,
		resolution: number,
		[any]: any,
	}?
): meshTypes.MeshData
	local positions: { { number } } = {}
	local normals: { { number } } = {}
	local uvs: { { number } } = {}
	local rawFaces: { { meshTypes.RawCorner } } = {}
	local lodBoundaries: { number } = {}
	local sawLodGroup = false

	for line in objData:gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
			local tokens = {}
			for tok in trimmed:gmatch("%S+") do
				table.insert(tokens, tok)
			end
			local keyword = tokens[1]

			if keyword == "o" and tokens[2] and tokens[2]:match("^[Ll][Oo][Dd]%d+$") then
				sawLodGroup = true
				table.insert(lodBoundaries, #rawFaces)
			elseif keyword == "v" then
				table.insert(
					positions,
					{ tonumber(tokens[2]) or 0, tonumber(tokens[3]) or 0, tonumber(tokens[4]) or 0 }
				)
			elseif keyword == "vn" then
				table.insert(normals, { tonumber(tokens[2]) or 0, tonumber(tokens[3]) or 0, tonumber(tokens[4]) or 0 })
			elseif keyword == "vt" then
				table.insert(uvs, { tonumber(tokens[2]) or 0, tonumber(tokens[3]) or 0 })
			elseif keyword == "f" then
				local corners: { meshTypes.RawCorner } = {}
				for i = 2, #tokens do
					local p, t, n = tokens[i]:match("^(-?%d*)/?(-?%d*)/?(-?%d*)$")
					table.insert(corners, {
						p = root.utils.parseIndex(p :: string, #positions) :: number,
						t = root.utils.parseIndex(t :: string, #uvs),
						n = root.utils.parseIndex(n :: string, #normals),
					})
				end
				-- Fan-triangulate polygons with more than 3 vertices.
				for i = 2, #corners - 1 do
					table.insert(rawFaces, { corners[1], corners[i], corners[i + 1] })
				end
			end
		end
	end

	local vertices: { meshTypes.Vertex } = table.create(#rawFaces * 3)
	local faces: { meshTypes.Face } = table.create(#rawFaces)

	for _, corners in rawFaces do
		local faceVertIndex: { number } = {}

		-- Fallback flat normal, only computed if this face's first corner
		-- has no vn (i.e. the file doesn't supply normals for this face).
		local flatNormal: { number }? = nil
		if not corners[1].n then
			local p0, p1, p2 = positions[corners[1].p], positions[corners[2].p], positions[corners[3].p]
			local ux, uy, uz = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
			local wx, wy, wz = p2[1] - p0[1], p2[2] - p0[2], p2[3] - p0[3]
			local nx = uy * wz - uz * wy
			local ny = uz * wx - ux * wz
			local nz = ux * wy - uy * wx
			local len = math.sqrt(nx * nx + ny * ny + nz * nz)
			flatNormal = if len > 1e-8 then { nx / len, ny / len, nz / len } else { 0, 0, 0 }
		end

		for _, corner in corners do
			local pos = positions[corner.p]
			local nrm = if corner.n then normals[corner.n] elseif flatNormal then flatNormal else { 0, 0, 0 }
			local uv = if corner.t then uvs[corner.t] else { 0, 0 }

			table.insert(vertices, {
				vx = pos[1],
				vy = pos[2],
				vz = pos[3],
				nx = nrm[1],
				ny = nrm[2],
				nz = nrm[3],
				tu = uv[1],
				tv = noInvertUV and uv[2] or 1 - uv[2],
				tw = 0,
			})
			table.insert(faceVertIndex, #vertices)
		end

		table.insert(faces, { a = faceVertIndex[1], b = faceVertIndex[2], c = faceVertIndex[3] })
	end

	if sawLodGroup then
		local lodOffsets: { number } = { 0 }
		for _, b in lodBoundaries do
			table.insert(lodOffsets, b)
		end
		table.insert(lodOffsets, #faces)
		return { vertices = vertices, faces = faces, lodOffsets = lodOffsets }
	elseif
		autoLods ~= nil
		and math.floor(autoLods.levels) > 0
		and root.utils.autoLOD[string.lower(autoLods.method)] ~= nil
	then
		local methodName = string.lower(autoLods.method)
		local levels = math.floor(autoLods.levels)
		local baseFaceCount = #faces
		local allVerts = vertices
		local allFaces = faces
		local lodOffsets: { number } = { 0, #allFaces }

		print(`generating lods... [LEVELS: {levels}] [METHOD: {autoLods.method}]`)

		for level = 1, levels do
			print(`[LV{level}] generating...`)
			local calc_div = autoLods.resolution ^ level

			local targetCount = math.max(4, math.floor(baseFaceCount * calc_div))
			local lodVerts, lodFaces =
				root.utils.autoLOD[methodName](vertices, faces, targetCount, autoLods.methodOptions[methodName] or {})

			local base = #allVerts
			for _, v in lodVerts do
				table.insert(allVerts, v)
			end
			for _, f in lodFaces do
				table.insert(allFaces, { a = f.a + base, b = f.b + base, c = f.c + base })
			end
			table.insert(lodOffsets, #allFaces)
			print(`[LV{level}] generated!`)
		end
		return { vertices = allVerts, faces = allFaces, lodOffsets = lodOffsets }
	elseif
		autoLods ~= nil
		and math.floor(autoLods.levels) > 0
		and root.utils.autoLOD[string.lower(autoLods.method)] == nil
	then
		print(`autoLOD method "{autoLods.method}" doesn't seem to exist yet.`)
	end

	return { vertices = vertices, faces = faces }
end
