local environment = require("@applibs/environment")

local meshTypes = require("@applibs/mesh/types")

local fs = zune.fs
local ffi = zune.ffi
local t = ffi.types

local function fn(returns: any, args: { any })
	return { returns = returns, args = args }
end

type MeshoptAPI = {
	MeshoptSimplify: (
		positions: FFIPointer,
		vertexCount: number,
		indices: FFIPointer,
		indexCount: number,
		targetIndexCount: number,
		targetError: number,
		lockBorder: number,
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
	-- Defaults to 1.0 (effectively "no error limit") so targetIndexCount is
	-- the only thing that decides how far simplification goes; lower this
	-- if you want simplification to stop early rather than risk visible
	-- distortion.
	targetError: number?,
	-- Locks vertices on open mesh boundaries in place so open rims/seams
	-- (e.g. an unclosed bottom on an OBJ) resist caving in during
	-- simplification, rather than shrinking toward the mesh's centroid.
	-- Defaults to true.
	lockBorder: boolean?,
}

function Meshopt.simplify(
	vertices: { meshTypes.Vertex },
	faces: { meshTypes.Face },
	targetIndexCount: number,
	options: SimplifyOptions
): ({ meshTypes.Face }, number)
	if lib == nil then
		lib = ffi.dlopen(libPath, {
			MeshoptSimplify = fn(
				t.i64,
				{ t.pointer, t.u32, t.pointer, t.u32, t.u32, t.float, t.i32, t.pointer, t.u32, t.pointer }
			),
		})
	end
	options = options or {} :: SimplifyOptions
	local targetError = options.targetError or 1.0
	local lockBorder = options.lockBorder and 1 or 0

	local vertexCount = #vertices
	local indexCount = #faces * 3

	local posBuf = buffer.create(vertexCount * 3 * 4)
	for i, v in vertices do
		local o = (i - 1) * 3 * 4
		buffer.writef32(posBuf, o, v.vx)
		buffer.writef32(posBuf, o + 4, v.vy)
		buffer.writef32(posBuf, o + 8, v.vz)
	end

	local idxBuf = buffer.create(indexCount * 4)
	local w = 0
	for _, f in faces do
		buffer.writeu32(idxBuf, w, f.a - 1) -- 1-based here -> 0-based for meshopt
		buffer.writeu32(idxBuf, w + 4, f.b - 1)
		buffer.writeu32(idxBuf, w + 8, f.c - 1)
		w += 12
	end

	local posPtr = upload(posBuf)
	local idxPtr = upload(idxBuf)
	local outIdxPtr = allocOut(indexCount * 4) -- worst case: same size as input
	local outErrorPtr = allocOut(4)

	local newIndexCount = readI64(
		lib.MeshoptSimplify(
			posPtr,
			vertexCount,
			idxPtr,
			indexCount,
			targetIndexCount,
			targetError,
			lockBorder,
			outIdxPtr,
			indexCount,
			outErrorPtr
		)
	)

	ffi.free(posPtr)
	ffi.free(idxPtr)

	if newIndexCount < 0 then
		ffi.free(outIdxPtr)
		ffi.free(outErrorPtr)
		error(`Meshopt.simplify: MeshoptSimplify failed with status {newIndexCount} - check vertex/face data`)
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
	return newFaces, resultError
end

return Meshopt
