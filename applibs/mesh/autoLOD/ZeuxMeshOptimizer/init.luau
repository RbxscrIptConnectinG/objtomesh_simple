--!strict
-- Zeux's Mesh Optimizer Method
local meshTypes = require("@applibs/mesh/types")

local meshopt = require("@self/meshopt")

return function(
	baseVerts: { meshTypes.Vertex },
	baseFaces: { meshTypes.Face },
	targetFaceCount: number,
	options: any
): ({ meshTypes.Vertex }, { meshTypes.Face })
	local weldAttributes = options.weldAttributes ~= false
	local NORMAL_EPS, UV_EPS = 1e-3, 1e-4

	local welded: { meshTypes.Vertex } = {}
	local grid: { [number]: { [number]: { [number]: { number } } } } = {} -- position bucket -> welded indices
	local cornerToWelded: { number } = table.create(#baseVerts)

	for i, v in baseVerts do
		local qx, qy, qz =
			math.floor(v.vx * 100000 + 0.5), math.floor(v.vy * 100000 + 0.5), math.floor(v.vz * 100000 + 0.5)
		local gx = grid[qx]
		if not gx then
			gx = {}
			grid[qx] = gx
		end
		local gy = gx[qy]
		if not gy then
			gy = {}
			gx[qy] = gy
		end
		local bucket = gy[qz]
		if not bucket then
			bucket = {}
			gy[qz] = bucket
		end

		local found: number
		for _, wi in bucket do
			if not weldAttributes then
				found = wi
				break
			end
			local w = welded[wi]
			if
				math.abs(w.nx - v.nx) <= NORMAL_EPS
				and math.abs(w.ny - v.ny) <= NORMAL_EPS
				and math.abs(w.nz - v.nz) <= NORMAL_EPS
				and math.abs(w.tu - v.tu) <= UV_EPS
				and math.abs(w.tv - v.tv) <= UV_EPS
			then
				found = wi
				break
			end
		end
		if not found then
			table.insert(welded, v)
			found = #welded
			table.insert(bucket, found :: any)
		end
		cornerToWelded[i] = found
	end

	local weldedFaces: { meshTypes.Face } = table.create(#baseFaces)
	for _, f in baseFaces do
		local a, b, c = cornerToWelded[f.a], cornerToWelded[f.b], cornerToWelded[f.c]
		if a ~= b and b ~= c and a ~= c then
			table.insert(weldedFaces, { a = a, b = b, c = c })
		end
	end

	local simplifiedVerts, simplified = meshopt.simplify(welded, weldedFaces, targetFaceCount * 3, options)

	local outVerts: { meshTypes.Vertex } = {}
	local outFaces: { meshTypes.Face } = table.create(#simplified)
	local emitted: { [number]: number } = {}

	local function emit(v: number): number
		local existing = emitted[v]
		if existing then
			return existing
		end
		table.insert(outVerts, simplifiedVerts[v])
		local idx = #outVerts
		emitted[v] = idx
		return idx
	end

	for _, f in simplified do
		table.insert(outFaces, { a = emit(f.a), b = emit(f.b), c = emit(f.c) })
	end

	return outVerts, outFaces
end
