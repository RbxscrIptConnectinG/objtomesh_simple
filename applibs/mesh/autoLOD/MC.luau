--!strict
-- midpoint collapse
local meshTypes = require("@applibs/mesh/types")

-- Binary min-heap of {lenSq, a, b}, ordered by lenSq. O(log n) push/pop.
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

-- Greedy shortest-edge-first collapse decimator - no quadric error metric,
-- just "merge whichever edge is shortest, repeat" until the target face
-- count is hit. Good enough for auto-generated LODs where approximate
-- silhouette preservation matters more than exact shape fidelity.
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

	local function edgeLenSq(a: number, b: number): number
		local pa, pb = uniquePos[a], uniquePos[b]
		local dx, dy, dz = pa[1] - pb[1], pa[2] - pb[2], pa[3] - pb[3]
		return dx * dx + dy * dy + dz * dz
	end

	local heap: { { number } } = {}
	local function pushEdge(a: number, b: number)
		if a ~= b then
			heapPush(heap, { edgeLenSq(a, b), a, b })
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
			-- Collapse b into a, moving a to the edge midpoint.
			local pa, pb = uniquePos[a], uniquePos[b]
			pa[1], pa[2], pa[3] = (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2, (pa[3] + pb[3]) / 2
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
