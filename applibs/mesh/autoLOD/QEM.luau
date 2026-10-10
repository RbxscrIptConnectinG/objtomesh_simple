--!strict
-- Quadric Error Metrics
local meshTypes = require("@applibs/mesh/types")

-- Binary min-heap of {cost, a, b}, ordered by cost. O(log n) push/pop.
local function heapPush(heap: { { number } }, item: { number })
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if heap[parent][1] <= heap[i][1] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function heapPop(heap: { { number } }): { number }?
	local n = #heap
	if n == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= n and heap[l][1] < heap[smallest][1] then
			smallest = l
		end
		if r <= n and heap[r][1] < heap[smallest][1] then
			smallest = r
		end
		if smallest == i then
			break
		end
		heap[i], heap[smallest] = heap[smallest], heap[i]
		i = smallest
	end
	return top
end

-- Evaluates v^T Q v for homogeneous v=(x,y,z,1) against a quadric stored as
-- {a,b,c,d,e,f,g,h,i,j}, representing the symmetric 4x4 error matrix
--   [a b c d; b e f g; c f h i; d g i j]
-- (Garland-Heckbert quadric error metric).
local function evalQuadric(Q: { number }, x: number, y: number, z: number): number
	local a, b, c, d, e, f, g, h, i, j = Q[1], Q[2], Q[3], Q[4], Q[5], Q[6], Q[7], Q[8], Q[9], Q[10]
	return a * x * x
		+ e * y * y
		+ h * z * z
		+ 2 * b * x * y
		+ 2 * c * x * z
		+ 2 * f * y * z
		+ 2 * d * x
		+ 2 * g * y
		+ 2 * i * z
		+ j
end

local function det3(m: { { number } }): number
	return m[1][1] * (m[2][2] * m[3][3] - m[2][3] * m[3][2])
		- m[1][2] * (m[2][1] * m[3][3] - m[2][3] * m[3][1])
		+ m[1][3] * (m[2][1] * m[3][2] - m[2][2] * m[3][1])
end

-- Picks where a collapsed pair of vertices should end up under their summed
-- quadric Q: the point minimizing surface error, found by solving the 3x3
-- "gradient of v^T Q v = 0" system via Cramer's rule. Falls back to the
-- cheapest of {a, b, midpoint} when that system is singular.
local function solveQuadric(Q: { number }, pa: { number }, pb: { number }): (number, number, number, number)
	local a, b, c, d, e, f, g, h, i = Q[1], Q[2], Q[3], Q[4], Q[5], Q[6], Q[7], Q[8], Q[9]
	local M = { { a, b, c }, { b, e, f }, { c, f, h } }
	local detM = det3(M)

	if math.abs(detM) > 1e-9 then
		local rx, ry, rz = -d, -g, -i
		local Mx = { { rx, b, c }, { ry, e, f }, { rz, f, h } }
		local My = { { a, rx, c }, { b, ry, f }, { c, rz, h } }
		local Mz = { { a, b, rx }, { b, e, ry }, { c, f, rz } }
		local x, y, z = det3(Mx) / detM, det3(My) / detM, det3(Mz) / detM
		return x, y, z, evalQuadric(Q, x, y, z)
	end

	local mx, my, mz = (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2, (pa[3] + pb[3]) / 2
	local costA = evalQuadric(Q, pa[1], pa[2], pa[3])
	local costB = evalQuadric(Q, pb[1], pb[2], pb[3])
	local costM = evalQuadric(Q, mx, my, mz)
	if costA <= costB and costA <= costM then
		return pa[1], pa[2], pa[3], costA
	elseif costB <= costM then
		return pb[1], pb[2], pb[3], costB
	end
	return mx, my, mz, costM
end

-- Quadric-error-metric collapse decimator (Garland-Heckbert): each collapse
-- is chosen and positioned to minimize deviation from the ORIGINAL surface
-- planes around it, rather than just picking the shortest edge and averaging
-- its endpoints. Plain shortest-edge/midpoint collapse behaves like
-- repeated local smoothing - it erodes flat regions and shrinks open
-- boundaries uniformly, which is why it visibly "balls up" closed shapes.
-- QEM instead keeps flat areas flat and (via the boundary-edge weighting
-- below) keeps open rims/seams from caving in.
--
-- Driven by a min-heap of candidate edges plus per-vertex face adjacency, so
-- each collapse only touches the (small) handful of faces actually touching
-- the collapsed edge, instead of rescanning every face in the mesh on every
-- single collapse - O((F + V) log V) overall rather than O(F^2).
return function(
	baseVerts: { meshTypes.Vertex },
	baseFaces: { meshTypes.Face },
	targetFaceCount: number
): ({ meshTypes.Vertex }, { meshTypes.Face })
	-- Dedupe vertices by position using a quantized grid (no string keys/
	-- string.format - just nested integer-indexed tables) to get a clean
	-- topological mesh to collapse edges on.
	local uniquePos: { { number } } = {}
	local uniqueAttr: { meshTypes.Vertex } = {}
	local grid: { [number]: { [number]: { [number]: number } } } = {}
	local cornerToUnique: { number } = table.create(#baseVerts)

	local function quant(x: number): number
		return math.floor(x * 100000 + 0.5)
	end

	for i, v in baseVerts do
		local qx, qy, qz = quant(v.vx), quant(v.vy), quant(v.vz)
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
		local idx = gy[qz]
		if not idx then
			table.insert(uniquePos, { v.vx, v.vy, v.vz })
			table.insert(uniqueAttr, v)
			idx = #uniquePos
			gy[qz] = idx
		end
		cornerToUnique[i] = idx
	end

	-- Mutable face records {a, b, c, dead(0/1)} + vertex -> incident-face
	-- adjacency, updated in place as collapses happen (no union-find/resolve
	-- needed: a collapsed vertex's faces are rewritten immediately).
	local faces: { { number } } = table.create(#baseFaces)
	local vertFaces: { { number } } = table.create(#uniquePos)
	for i = 1, #uniquePos do
		vertFaces[i] = {}
	end

	local liveCount = 0
	for _, f in baseFaces do
		local a, b, c = cornerToUnique[f.a], cornerToUnique[f.b], cornerToUnique[f.c]
		if a ~= b and b ~= c and a ~= c then
			local idx = #faces + 1
			faces[idx] = { a, b, c, 0 }
			table.insert(vertFaces[a], idx)
			table.insert(vertFaces[b], idx)
			table.insert(vertFaces[c], idx)
			liveCount += 1
		end
	end

	-- Per-vertex quadrics: sum of each adjacent face's plane quadric. Zero-
	-- initialized 10-tuples, accumulated below.
	local vertQuadric: { { number } } = table.create(#uniquePos)
	for i = 1, #uniquePos do
		vertQuadric[i] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	end

	local faceNormal: { { number } } = table.create(#faces)

	local function addFacePlaneQuadric(nx: number, ny: number, nz: number, d: number, weight: number, v: number)
		local Q = vertQuadric[v]
		Q[1] += weight * nx * nx
		Q[2] += weight * nx * ny
		Q[3] += weight * nx * nz
		Q[4] += weight * nx * d
		Q[5] += weight * ny * ny
		Q[6] += weight * ny * nz
		Q[7] += weight * ny * d
		Q[8] += weight * nz * nz
		Q[9] += weight * nz * d
		Q[10] += weight * d * d
	end

	-- 1. Face-plane quadrics, and an edge -> {count, faceIdx} map (built in
	--    the same pass) to find boundary edges afterwards.
	local edgeInfo: { [number]: { number } } = {} -- key -> {count, x, y, faceIdx}
	for faceIdx, f in faces do
		local a, b, c = f[1], f[2], f[3]
		local pa, pb, pc = uniquePos[a], uniquePos[b], uniquePos[c]
		local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
		local wx, wy, wz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
		local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
		local len = math.sqrt(nx * nx + ny * ny + nz * nz)
		if len > 1e-12 then
			nx, ny, nz = nx / len, ny / len, nz / len
		else
			nx, ny, nz = 0, 0, 0
		end
		faceNormal[faceIdx] = { nx, ny, nz }
		local d = -(nx * pa[1] + ny * pa[2] + nz * pa[3])
		addFacePlaneQuadric(nx, ny, nz, d, 1, a)
		addFacePlaneQuadric(nx, ny, nz, d, 1, b)
		addFacePlaneQuadric(nx, ny, nz, d, 1, c)

		for _, pair in { { a, b }, { b, c }, { c, a } } do
			local x, y = pair[1], pair[2]
			if x > y then
				x, y = y, x
			end
			local key = x * 2000000000 + y
			local info = edgeInfo[key]
			if not info then
				info = { 0, x, y, faceIdx }
				edgeInfo[key] = info
			end
			info[1] += 1
			info[4] = faceIdx
		end
	end

	-- 2. Boundary-edge constraint planes: a perpendicular "fin" through each
	--    edge used by exactly one face, heavily weighted so open rims/seams
	--    resist collapsing inward instead of shrinking toward the centroid.
	local BOUNDARY_WEIGHT = 1000
	for _, info in edgeInfo do
		if info[1] == 1 then
			local x, y, faceIdx = info[2], info[3], info[4]
			local px, py = uniquePos[x], uniquePos[y]
			local ex, ey, ez = py[1] - px[1], py[2] - px[2], py[3] - px[3]
			local elen = math.sqrt(ex * ex + ey * ey + ez * ez)
			if elen > 1e-12 then
				ex, ey, ez = ex / elen, ey / elen, ez / elen
				local fn = faceNormal[faceIdx]
				local nx = ey * fn[3] - ez * fn[2]
				local ny = ez * fn[1] - ex * fn[3]
				local nz = ex * fn[2] - ey * fn[1]
				local nlen = math.sqrt(nx * nx + ny * ny + nz * nz)
				if nlen > 1e-12 then
					nx, ny, nz = nx / nlen, ny / nlen, nz / nlen
					local d = -(nx * px[1] + ny * px[2] + nz * px[3])
					local weight = BOUNDARY_WEIGHT * (elen * elen)
					addFacePlaneQuadric(nx, ny, nz, d, weight, x)
					addFacePlaneQuadric(nx, ny, nz, d, weight, y)
				end
			end
		end
	end

	local function sumQuadric(a: number, b: number): { number }
		local Qa, Qb = vertQuadric[a], vertQuadric[b]
		local Q = table.create(10)
		for k = 1, 10 do
			Q[k] = Qa[k] + Qb[k]
		end
		return Q
	end

	local heap: { { number } } = {}
	local function pushEdge(a: number, b: number)
		if a ~= b then
			local _, _, _, cost = solveQuadric(sumQuadric(a, b), uniquePos[a], uniquePos[b])
			heapPush(heap, { cost, a, b })
		end
	end

	-- Seed with every unique edge in the base mesh.
	do
		local seen: { [number]: boolean } = {}
		for _, f in faces do
			local a, b, c = f[1], f[2], f[3]
			for _, pair in { { a, b }, { b, c }, { c, a } } do
				local x, y = pair[1], pair[2]
				if x > y then
					x, y = y, x
				end
				local key = x * 2000000000 + y
				if not seen[key] then
					seen[key] = true
					pushEdge(x, y)
				end
			end
		end
	end

	local alive: { boolean } = table.create(#uniquePos, true)

	while liveCount > targetFaceCount do
		local item = heapPop(heap)
		if not item then
			break -- no edges left to collapse (lazily-stale entries are skipped below)
		end
		local a, b = item[2], item[3]
		if alive[a] and alive[b] and a ~= b then
			-- Recompute fresh (not the possibly-stale heap values) in case a
			-- or b absorbed another vertex since this edge was queued.
			local Qsum = sumQuadric(a, b)
			local pa, pb = uniquePos[a], uniquePos[b]
			local x, y, z = solveQuadric(Qsum, pa, pb)
			pa[1], pa[2], pa[3] = x, y, z
			vertQuadric[a] = Qsum
			alive[b] = false

			for _, faceIdx in vertFaces[b] do
				local face = faces[faceIdx]
				if face[4] == 0 then
					for k = 1, 3 do
						if face[k] == b then
							face[k] = a
						end
					end
					if face[1] == face[2] or face[2] == face[3] or face[1] == face[3] then
						face[4] = 1
						liveCount -= 1
					else
						table.insert(vertFaces[a], faceIdx)
						pushEdge(face[1], face[2])
						pushEdge(face[2], face[3])
						pushEdge(face[3], face[1])
					end
				end
			end
			vertFaces[b] = {}
		end
	end

	local outVerts: { meshTypes.Vertex } = {}
	local outFaces: { meshTypes.Face } = {}
	local emitted: { [number]: number } = {}

	local function emit(v: number): number
		local existing = emitted[v]
		if existing then
			return existing
		end
		local attr, p = uniqueAttr[v], uniquePos[v]
		table.insert(outVerts, {
			vx = p[1],
			vy = p[2],
			vz = p[3],
			nx = attr.nx,
			ny = attr.ny,
			nz = attr.nz,
			tu = attr.tu,
			tv = attr.tv,
			tw = attr.tw,
		})
		local idx = #outVerts
		emitted[v] = idx
		return idx
	end

	for _, f in faces do
		if f[4] == 0 then
			table.insert(outFaces, { a = emit(f[1]), b = emit(f[2]), c = emit(f[3]) })
		end
	end

	return outVerts, outFaces
end
