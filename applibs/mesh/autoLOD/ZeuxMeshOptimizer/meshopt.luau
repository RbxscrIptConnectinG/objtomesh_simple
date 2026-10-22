local environment = require("@applibs/environment")

local meshTypes = require("@applibs/mesh/types")

local fs = zune.fs
local ffi = zune.ffi
local t = ffi.types

local function fn(returns: any, args: { any })
	return { returns = returns, args = args }
end

type MeshoptAPI = {
	MeshoptSimplifyEx: (
		positions: FFIPointer,
		vertexCount: number,
		attributes: FFIPointer,
		attributeCount: number,
		attributeWeights: FFIPointer,
		indices: FFIPointer,
		indexCount: number,
		targetIndexCount: number,
		targetError: number,
		options: number,
		updateVertices: number,
		outIndices: FFIPointer,
		outCapacity: number,
		outResultError: FFIPointer
	) -> buffer,
}

local Meshopt = {}

local libPath = environment.IsNotCompiled and "./libs/bin/ZMO.dll" or fs.path.join(environment.RootPath, "bin/ZMO.dll")

local lib: MeshoptAPI = nil

local function upload(buf: buffer): FFIPointer
	local size = buffer.len(buf)
	local nativePtr = ffi.alloc(size)
	nativePtr:write(0, buf, 0, size)
	return nativePtr
end

local function allocOut(size: number): FFIPointer
	return ffi.alloc(size)
end

local function download(ptr: FFIPointer, size: number): buffer
	local buf = buffer.create(size)
	ptr:read(0, buf, 0, size)
	return buf
end

local function readI64(buf: buffer): number
	local lo = buffer.readu32(buf, 0)
	local hi = buffer.readi32(buf, 4)
	return hi * 0x100000000 + lo
end

export type SimplifyOptions = {
	-- Error tolerance relative to mesh extents, e.g. 0.01 = 1% deformation.
	-- Default 1.0 (effectively no limit: targetIndexCount decides).
	targetError: number?,
	-- Keep vertices on open mesh boundaries in place. Default true.
	lockBorder: boolean?,
	-- More regular triangle sizes/shapes, at some cost to fidelity. Default false.
	regularize: boolean?,
	-- Remove small disconnected parts while simplifying. Default false.
	prune: boolean?,
	-- Allow collapses across attribute seams (needed if the mesh is so
	-- faceted/seamy that simplification gets stuck). Default false.
	permissive: boolean?,
	-- Importance of UV preservation vs position. Higher = less UV
	-- stretching/"melting", at the cost of position accuracy. Default 2.
	-- 0 ignores UVs entirely.
	uvWeight: number?,
	-- Same for vertex normals (shading). Default 1. 0 ignores normals.
	normalWeight: number?,
	-- true: collapsed vertices are moved to better positions and their
	-- UVs/normals are re-solved to match (best UV quality, returns modified
	-- copies). false: vertex data stays exactly as given and only the
	-- triangle list shrinks. Default true.
	updateVertices: boolean?,
}

function Meshopt.simplify(
	vertices: { meshTypes.Vertex },
	faces: { meshTypes.Face },
	targetIndexCount: number,
	options: any
): ({ meshTypes.Vertex }, { meshTypes.Face }, number)
	if lib == nil then
		lib = ffi.dlopen(libPath, {
			MeshoptSimplifyEx = fn(t.i64, {
				t.pointer,
				t.u32,
				t.pointer,
				t.u32,
				t.pointer,
				t.pointer,
				t.u32,
				t.u32,
				t.float,
				t.u32,
				t.i32,
				t.pointer,
				t.u32,
				t.pointer,
			}),
		})
	end
	options = options or {} :: any
	local targetError = options.targetError or 1.0
	local uvWeight = options.uvWeight or 2
	local normalWeight = options.normalWeight or 1
	local update = options.updateVertices ~= false

	local flags = 0
	if options.lockBorder ~= false then
		flags += 1
	end
	if options.prune then
		flags += 8
	end
	if options.regularize then
		flags += 16
	end
	if options.permissive then
		flags += 32
	end

	local vertexCount = #vertices
	local indexCount = #faces * 3
	local ATTRS = 5 -- nx, ny, nz, tu, tv

	local posBuf = buffer.create(vertexCount * 3 * 4)
	local attrBuf = buffer.create(vertexCount * ATTRS * 4)
	for i, v in vertices do
		local o = (i - 1) * 3 * 4
		buffer.writef32(posBuf, o, v.vx)
		buffer.writef32(posBuf, o + 4, v.vy)
		buffer.writef32(posBuf, o + 8, v.vz)
		local a = (i - 1) * ATTRS * 4
		buffer.writef32(attrBuf, a, v.nx)
		buffer.writef32(attrBuf, a + 4, v.ny)
		buffer.writef32(attrBuf, a + 8, v.nz)
		buffer.writef32(attrBuf, a + 12, v.tu)
		buffer.writef32(attrBuf, a + 16, v.tv)
	end

	local weightBuf = buffer.create(ATTRS * 4)
	for k = 0, 2 do
		buffer.writef32(weightBuf, k * 4, normalWeight)
	end
	buffer.writef32(weightBuf, 12, uvWeight)
	buffer.writef32(weightBuf, 16, uvWeight)

	local idxBuf = buffer.create(indexCount * 4)
	local w = 0
	for _, f in faces do
		buffer.writeu32(idxBuf, w, f.a - 1) -- 1-based here -> 0-based for meshopt
		buffer.writeu32(idxBuf, w + 4, f.b - 1)
		buffer.writeu32(idxBuf, w + 8, f.c - 1)
		w += 12
	end

	local posPtr = upload(posBuf)
	local attrPtr = upload(attrBuf)
	local weightPtr = upload(weightBuf)
	local idxPtr = upload(idxBuf)
	local outIdxPtr = allocOut(indexCount * 4) -- worst case: same size as input
	local outErrorPtr = allocOut(4)

	local newIndexCount = readI64(
		lib.MeshoptSimplifyEx(
			posPtr,
			vertexCount,
			attrPtr,
			ATTRS,
			weightPtr,
			idxPtr,
			indexCount,
			targetIndexCount,
			targetError,
			flags,
			if update then 1 else 0,
			outIdxPtr,
			indexCount,
			outErrorPtr
		)
	)

	local newPosBuf = if update and newIndexCount >= 0 then download(posPtr, vertexCount * 3 * 4) else nil
	local newAttrBuf = if update and newIndexCount >= 0 then download(attrPtr, vertexCount * ATTRS * 4) else nil

	ffi.free(posPtr)
	ffi.free(attrPtr)
	ffi.free(weightPtr)
	ffi.free(idxPtr)

	if newIndexCount < 0 then
		ffi.free(outIdxPtr)
		ffi.free(outErrorPtr)
		error(`Meshopt.simplify: MeshoptSimplifyEx failed with status {newIndexCount} - check vertex/face data`)
	end

	local newIdxBuf = download(outIdxPtr, newIndexCount * 4)
	local resultError = buffer.readf32(download(outErrorPtr, 4), 0)
	ffi.free(outIdxPtr)
	ffi.free(outErrorPtr)

	local newFaces: { meshTypes.Face } = table.create(newIndexCount // 3)
	for i = 1, newIndexCount // 3 do
		local o = (i - 1) * 12
		newFaces[i] = {
			a = buffer.readu32(newIdxBuf, o) + 1, -- 0-based from meshopt -> 1-based here
			b = buffer.readu32(newIdxBuf, o + 4) + 1,
			c = buffer.readu32(newIdxBuf, o + 8) + 1,
		}
	end

	if not newPosBuf or not newAttrBuf then
		return vertices, newFaces, resultError
	end

	local newVertices: { meshTypes.Vertex } = table.create(vertexCount)
	for i = 1, vertexCount do
		local o = (i - 1) * 3 * 4
		local a = (i - 1) * ATTRS * 4
		local nx, ny, nz =
			buffer.readf32(newAttrBuf, a), buffer.readf32(newAttrBuf, a + 4), buffer.readf32(newAttrBuf, a + 8)
		if normalWeight > 0 then
			-- Solved normals aren't unit length any more - renormalize.
			local len = math.sqrt(nx * nx + ny * ny + nz * nz)
			if len > 1e-8 then
				nx, ny, nz = nx / len, ny / len, nz / len
			else
				local orig = vertices[i]
				nx, ny, nz = orig.nx, orig.ny, orig.nz
			end
		end
		newVertices[i] = {
			vx = buffer.readf32(newPosBuf, o),
			vy = buffer.readf32(newPosBuf, o + 4),
			vz = buffer.readf32(newPosBuf, o + 8),
			nx = nx,
			ny = ny,
			nz = nz,
			tu = buffer.readf32(newAttrBuf, a + 12),
			tv = buffer.readf32(newAttrBuf, a + 16),
			tw = vertices[i].tw,
		}
	end

	return newVertices, newFaces, resultError
end

return Meshopt
