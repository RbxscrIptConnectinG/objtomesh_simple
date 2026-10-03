--[[
	mesh.luau - convert any parser's indexed mesh into the renderer's model format

	Accepted input (what your parsers produce):
		{
			vertices = { { vx, vy, vz, nx, ny, nz, tu, tv, tw }, ... },
			faces    = { { a, b, c }, ... },
		}

	local m = mesh.fromIndexed(parsed, { indexBase = 1, normals = "auto" })
	local model = renderer:createModel(m)        -- renderer:createModel(parsed) also works directly

	Options:
		indexBase  0 or 1. Default: auto-detect (any index 0 -> 0-based, otherwise 1-based).
		           If your indices never touch the first/last vertex the detection can't know - set it explicitly.
		normals    "auto"   (default) use vertex normals; vertices whose normal is missing/zero get a smooth normal
		           "smooth" ignore provided normals, compute area-weighted smooth normals
		           "flat"   ignore provided normals, one normal per face (faceted look)
		flipV      true = use v' = 1 - tv (default false)
		flipWinding true = reverse every triangle's winding. Back-face culling (ModelView doubleSided = false) treats
		           counter-clockwise triangles as front faces; use this if your parser emits clockwise ones.

	Invalid faces (index out of range, non-numbers) are skipped; the count is returned as `skipped`.
	UVs: tu/tv are used for texturing (tw ignored). Missing UVs become 0,0. If your parser's V origin is
	bottom-left (OBJ-style) and textures look upside down, pass flipV = true.
]]

local mesh = {}

export type Options = { indexBase: number?, normals: string?, flipV: boolean?, flipWinding: boolean? }

function mesh.fromIndexed(parsed: any, opts: Options?): any
	local o: Options = opts or {}
	local verts, faces = parsed.vertices, parsed.faces
	if type(verts) ~= "table" or type(faces) ~= "table" then
		error("mesh.fromIndexed: expected { vertices = {...}, faces = {...} }", 2)
	end
	local n = #verts
	local mode = o.normals or "auto"
	if mode ~= "auto" and mode ~= "smooth" and mode ~= "flat" then
		error("mesh.fromIndexed: normals must be 'auto', 'smooth' or 'flat'", 2)
	end

	-- detect index base
	local base = o.indexBase
	if base == nil then
		base = 1
		for _, f in faces do
			if f.a == 0 or f.b == 0 or f.c == 0 then
				base = 0
				break
			end
		end
	end

	-- collect valid faces as vertex references (1-based into `verts`)
	local tris: { { any } } = {}
	local skipped = 0
	for _, f in faces do
		local a, b, c = f.a, f.b, f.c
		if type(a) == "number" and type(b) == "number" and type(c) == "number" then
			local va, vb, vc = verts[a + (1 - base)], verts[b + (1 - base)], verts[c + (1 - base)]
			if va and vb and vc then
				if o.flipWinding then
					table.insert(tris, { va, vc, vb })
				else
					table.insert(tris, { va, vb, vc })
				end
			else
				skipped += 1
			end
		else
			skipped += 1
		end
	end
	if #tris == 0 then
		error(
			"mesh.fromIndexed: no valid faces"
				.. (if skipped > 0 then ` ({skipped} skipped - wrong indexBase?)` else ""),
			2
		)
	end

	local function faceNormal(va: any, vb: any, vc: any): (number, number, number)
		local e1x, e1y, e1z = vb.vx - va.vx, vb.vy - va.vy, vb.vz - va.vz
		local e2x, e2y, e2z = vc.vx - va.vx, vc.vy - va.vy, vc.vz - va.vz
		return e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x -- length = 2 * area
	end

	-- area-weighted smooth normals, keyed by vertex table (only built when needed)
	local smooth: { [any]: { number } } = {}
	local smoothBuilt = false
	local function ensureSmooth()
		if smoothBuilt then
			return
		end
		smoothBuilt = true
		for _, t in tris do
			local fx, fy, fz = faceNormal(t[1], t[2], t[3])
			for i = 1, 3 do
				local acc = smooth[t[i]]
				if not acc then
					acc = { 0, 0, 0 }
					smooth[t[i]] = acc
				end
				acc[1] += fx
				acc[2] += fy
				acc[3] += fz
			end
		end
	end

	local function normalize(x: number, y: number, z: number): (number?, number?, number?)
		local len = math.sqrt(x * x + y * y + z * z)
		if len < 1e-12 then
			return 0, 1, 0
		end
		return x / len, y / len, z / len
	end

	if mode == "smooth" then
		ensureSmooth()
	end

	local buf = buffer.create(#tris * 3 * 32)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local off = 0

	for _, t in tris do
		local fnx, fny, fnz = 0, 0, 0
		if mode == "flat" then
			fnx, fny, fnz = normalize(faceNormal(t[1], t[2], t[3]))
		end
		for i = 1, 3 do
			local v = t[i]
			local nx, ny, nz
			if mode == "flat" then
				nx, ny, nz = fnx, fny, fnz
			elseif mode == "smooth" then
				local s = smooth[v]
				nx, ny, nz = normalize(s[1], s[2], s[3])
			else -- auto
				local px, py, pz = v.nx, v.ny, v.nz
				if
					type(px) == "number"
					and type(py) == "number"
					and type(pz) == "number"
					and (px * px + py * py + pz * pz) > 1e-12
				then
					nx, ny, nz = normalize(px, py, pz)
				else
					ensureSmooth()
					local s = smooth[v]
					nx, ny, nz = normalize(s[1], s[2], s[3])
				end
			end

			buffer.writef32(buf, off, v.vx)
			buffer.writef32(buf, off + 4, v.vy)
			buffer.writef32(buf, off + 8, v.vz)
			buffer.writef32(buf, off + 12, nx)
			buffer.writef32(buf, off + 16, ny)
			buffer.writef32(buf, off + 20, nz)
			local tu = if type(v.tu) == "number" then v.tu else 0
			local tv = if type(v.tv) == "number" then v.tv else 0
			buffer.writef32(buf, off + 24, tu)
			buffer.writef32(buf, off + 28, if o.flipV then 1 - tv else tv)
			off += 32

			minX, minY, minZ = math.min(minX, v.vx), math.min(minY, v.vy), math.min(minZ, v.vz)
			maxX, maxY, maxZ = math.max(maxX, v.vx), math.max(maxY, v.vy), math.max(maxZ, v.vz)
		end
	end

	local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
	local r2 = 0
	for _, t in tris do
		for i = 1, 3 do
			local v = t[i]
			local dx, dy, dz = v.vx - cx, v.vy - cy, v.vz - cz
			r2 = math.max(r2, dx * dx + dy * dy + dz * dz)
		end
	end

	return {
		vertices = buf,
		vertexCount = #tris * 3,
		center = { cx, cy, cz },
		radius = math.max(math.sqrt(r2), 1e-6),
		skipped = skipped,
	}
end

return mesh
