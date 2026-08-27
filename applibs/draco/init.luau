--!strict

local ffi = zune.ffi
local t = ffi.types

local function fn(returns: any, args: { any })
	return { returns = returns, args = args }
end

type DracoAPI = {
	DracoGetEncodedMeshSize: (
		vertices: FFIPointer,
		vertexCount: number,
		indices: FFIPointer,
		indexCount: number,
		quantizationBits: number
	) -> buffer,
	DracoEncodeMesh: (
		vertices: FFIPointer,
		vertexCount: number,
		indices: FFIPointer,
		indexCount: number,
		quantizationBits: number,
		outBuffer: FFIPointer,
		outCapacity: number
	) -> buffer,
	DracoGetEncodedMeshFullSize: (
		positions: FFIPointer,
		normals: FFIPointer,
		uvs: FFIPointer,
		cornerCount: number,
		qBitsPosition: number,
		qBitsNormal: number,
		qBitsUv: number
	) -> buffer,
	DracoEncodeMeshFull: (
		positions: FFIPointer,
		normals: FFIPointer,
		uvs: FFIPointer,
		cornerCount: number,
		qBitsPosition: number,
		qBitsNormal: number,
		qBitsUv: number,
		outBuffer: FFIPointer,
		outCapacity: number
	) -> buffer,
	DracoGetMeshInfo: (
		data: FFIPointer,
		dataSize: number,
		outVertexCount: FFIPointer,
		outIndexCount: FFIPointer
	) -> number,
	DracoDecodeMesh: (
		data: FFIPointer,
		dataSize: number,
		outVertices: FFIPointer,
		outVertexCapacity: number,
		outIndices: FFIPointer,
		outIndexCapacity: number
	) -> number,
	DracoGetMeshInfoFull: (
		data: FFIPointer,
		dataSize: number,
		outCornerCount: FFIPointer,
		outHasNormal: FFIPointer,
		outHasUv: FFIPointer
	) -> number,
	DracoDecodeMeshFull: (
		data: FFIPointer,
		dataSize: number,
		outPositions: FFIPointer,
		outPositionCapacity: number,
		outNormals: FFIPointer,
		outNormalCapacity: number,
		outUvs: FFIPointer,
		outUvCapacity: number
	) -> number,
}

local Draco = {}
local libPath = "./objtomesh/libs/draco.dll"
local lib: DracoAPI? = nil

function Draco.setLibraryPath(path: string)
	if lib then
		error("Draco.setLibraryPath must be called before the library is first used")
	end
	libPath = path
end

local function ensureLoaded(): DracoAPI
	if lib == nil then
		lib = ffi.dlopen(libPath, {
			DracoGetEncodedMeshSize = fn(t.i64, { t.pointer, t.u32, t.pointer, t.u32, t.i32 }),
			DracoEncodeMesh = fn(t.i64, { t.pointer, t.u32, t.pointer, t.u32, t.i32, t.pointer, t.u32 }),
			DracoGetEncodedMeshFullSize = fn(t.i64, { t.pointer, t.pointer, t.pointer, t.u32, t.i32, t.i32, t.i32 }),
			DracoEncodeMeshFull = fn(
				t.i64,
				{ t.pointer, t.pointer, t.pointer, t.u32, t.i32, t.i32, t.i32, t.pointer, t.u32 }
			),
			DracoGetMeshInfo = fn(t.i32, { t.pointer, t.u32, t.pointer, t.pointer }),
			DracoDecodeMesh = fn(t.i32, { t.pointer, t.u32, t.pointer, t.u32, t.pointer, t.u32 }),
			DracoGetMeshInfoFull = fn(t.i32, { t.pointer, t.u32, t.pointer, t.pointer, t.pointer }),
			DracoDecodeMeshFull = fn(t.i32, { t.pointer, t.u32, t.pointer, t.u32, t.pointer, t.u32, t.pointer, t.u32 }),
		}) :: DracoAPI
	end
	return lib :: DracoAPI
end

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

local function packFloats(values: { number }): buffer
	local buf = buffer.create(#values * 4)
	for i, v in values do
		buffer.writef32(buf, (i - 1) * 4, v)
	end
	return buf
end

local function packU32(values: { number }): buffer
	local buf = buffer.create(#values * 4)
	for i, v in values do
		buffer.writeu32(buf, (i - 1) * 4, v)
	end
	return buf
end

local function unpackFloats(buf: buffer, count: number): { number }
	local out = table.create(count)
	for i = 1, count do
		out[i] = buffer.readf32(buf, (i - 1) * 4)
	end
	return out
end

local function unpackU32(buf: buffer, count: number): { number }
	local out = table.create(count)
	for i = 1, count do
		out[i] = buffer.readu32(buf, (i - 1) * 4)
	end
	return out
end

local function readI64(buf: buffer): number
	local lo = buffer.readu32(buf, 0)
	local hi = buffer.readi32(buf, 4)
	return hi * 0x100000000 + lo
end

function Draco.encodeMesh(vertices: { number }, indices: { number }, quantizationBits: number?): buffer
	local api = ensureLoaded()
	local qbits = quantizationBits or 14

	local vertexCount = #vertices // 3
	local indexCount = #indices

	local vertPtr = upload(packFloats(vertices))
	local idxPtr = upload(packU32(indices))

	local size = readI64(api.DracoGetEncodedMeshSize(vertPtr, vertexCount, idxPtr, indexCount, qbits))
	if size < 0 then
		ffi.free(vertPtr)
		ffi.free(idxPtr)
		error(
			`Draco.encodeMesh: DracoGetEncodedMeshSize failed with status {size} - check mesh data / quantization bits`
		)
	end

	local outPtr = allocOut(size)
	local written = readI64(api.DracoEncodeMesh(vertPtr, vertexCount, idxPtr, indexCount, qbits, outPtr, size))

	ffi.free(vertPtr)
	ffi.free(idxPtr)

	if written < 0 then
		ffi.free(outPtr)
		error(`Draco.encodeMesh: DracoEncodeMesh failed with status {written}`)
	end

	local result = download(outPtr, written)
	ffi.free(outPtr)
	return result
end

function Draco.decodeMesh(data: buffer): ({ number }, { number })
	local api = ensureLoaded()
	local dataSize = buffer.len(data)
	local dataPtr = upload(data)

	local vertexCountPtr = allocOut(4)
	local indexCountPtr = allocOut(4)

	local infoStatus = api.DracoGetMeshInfo(dataPtr, dataSize, vertexCountPtr, indexCountPtr)
	if infoStatus ~= 0 then
		ffi.free(dataPtr)
		ffi.free(vertexCountPtr)
		ffi.free(indexCountPtr)
		error(`Draco.decodeMesh: DracoGetMeshInfo failed with status {infoStatus}`)
	end

	local vertexCount = buffer.readu32(download(vertexCountPtr, 4), 0)
	local indexCount = buffer.readu32(download(indexCountPtr, 4), 0)
	ffi.free(vertexCountPtr)
	ffi.free(indexCountPtr)

	local vertOutPtr = allocOut(vertexCount * 3 * 4)
	local idxOutPtr = allocOut(indexCount * 4)

	local decodeStatus = api.DracoDecodeMesh(dataPtr, dataSize, vertOutPtr, vertexCount * 3, idxOutPtr, indexCount)
	ffi.free(dataPtr)

	if decodeStatus ~= 0 then
		ffi.free(vertOutPtr)
		ffi.free(idxOutPtr)
		error(`Draco.decodeMesh: DracoDecodeMesh failed with status {decodeStatus}`)
	end

	local vertOutBuf = download(vertOutPtr, vertexCount * 3 * 4)
	local idxOutBuf = download(idxOutPtr, indexCount * 4)
	ffi.free(vertOutPtr)
	ffi.free(idxOutPtr)

	return unpackFloats(vertOutBuf, vertexCount * 3), unpackU32(idxOutBuf, indexCount)
end

export type FullVertex = {
	vx: number,
	vy: number,
	vz: number,
	nx: number,
	ny: number,
	nz: number,
	tu: number,
	tv: number,
	tw: number,
}
export type FullFace = { a: number, b: number, c: number }

function Draco.decodeMeshFull(data: buffer): ({ FullVertex }, { FullFace })
	local api = ensureLoaded()
	local dataSize = buffer.len(data)
	local dataPtr = upload(data)

	local cornerCountPtr = allocOut(4)
	local hasNormalPtr = allocOut(4)
	local hasUvPtr = allocOut(4)

	local infoStatus = api.DracoGetMeshInfoFull(dataPtr, dataSize, cornerCountPtr, hasNormalPtr, hasUvPtr)
	if infoStatus ~= 0 then
		ffi.free(dataPtr)
		ffi.free(cornerCountPtr)
		ffi.free(hasNormalPtr)
		ffi.free(hasUvPtr)
		error(`Draco.decodeMeshFull: DracoGetMeshInfoFull failed with status {infoStatus}`)
	end

	local cornerCount = buffer.readu32(download(cornerCountPtr, 4), 0)
	local hasNormal = buffer.readi32(download(hasNormalPtr, 4), 0) ~= 0
	local hasUv = buffer.readi32(download(hasUvPtr, 4), 0) ~= 0
	ffi.free(cornerCountPtr)
	ffi.free(hasNormalPtr)
	ffi.free(hasUvPtr)

	local posOutPtr = allocOut(cornerCount * 3 * 4)
	local nrmOutPtr = allocOut(if hasNormal then cornerCount * 3 * 4 else 4)
	local uvOutPtr = allocOut(if hasUv then cornerCount * 2 * 4 else 4)

	local decodeStatus = api.DracoDecodeMeshFull(
		dataPtr,
		dataSize,
		posOutPtr,
		cornerCount * 3,
		nrmOutPtr,
		if hasNormal then cornerCount * 3 else 0,
		uvOutPtr,
		if hasUv then cornerCount * 2 else 0
	)
	ffi.free(dataPtr)

	if decodeStatus ~= 0 then
		ffi.free(posOutPtr)
		ffi.free(nrmOutPtr)
		ffi.free(uvOutPtr)
		error(`Draco.decodeMeshFull: DracoDecodeMeshFull failed with status {decodeStatus}`)
	end

	local posBuf = download(posOutPtr, cornerCount * 3 * 4)
	local nrmBuf = if hasNormal then download(nrmOutPtr, cornerCount * 3 * 4) else nil
	local uvBuf = if hasUv then download(uvOutPtr, cornerCount * 2 * 4) else nil
	ffi.free(posOutPtr)
	ffi.free(nrmOutPtr)
	ffi.free(uvOutPtr)

	local vertices: { FullVertex } = table.create(cornerCount)
	for i = 1, cornerCount do
		local po = (i - 1) * 3 * 4
		local vx = buffer.readf32(posBuf, po)
		local vy = buffer.readf32(posBuf, po + 4)
		local vz = buffer.readf32(posBuf, po + 8)

		local nx, ny, nz = 0, 0, 0
		if nrmBuf then
			nx = buffer.readf32(nrmBuf, po)
			ny = buffer.readf32(nrmBuf, po + 4)
			nz = buffer.readf32(nrmBuf, po + 8)
		end

		local tu, tv = 0, 0
		if uvBuf then
			local uo = (i - 1) * 2 * 4
			tu = buffer.readf32(uvBuf, uo)
			tv = buffer.readf32(uvBuf, uo + 4)
		end

		vertices[i] = {
			vx = vx,
			vy = vy,
			vz = vz,
			nx = nx,
			ny = ny,
			nz = nz,
			tu = tu,
			tv = 1 - tv,
			tw = 0,
		}
	end

	local faces: { FullFace } = table.create(cornerCount // 3)
	for i = 1, cornerCount // 3 do
		local base = (i - 1) * 3
		faces[i] = { a = base + 1, b = base + 2, c = base + 3 }
	end

	return vertices, faces
end

export type EncodeOptions = {
	positionBits: number?,
	normalBits: number?,
	uvBits: number?,
}

function Draco.encodeMeshFull(vertices: { FullVertex }, faces: { FullFace }, options: EncodeOptions?): buffer
	local api = ensureLoaded()
	local posBits = (options and options.positionBits) or 14
	local nrmBits = (options and options.normalBits) or 10
	local uvBits = (options and options.uvBits) or 12

	local cornerCount = #faces * 3
	local posBuf = buffer.create(cornerCount * 3 * 4)
	local nrmBuf = buffer.create(cornerCount * 3 * 4)
	local uvBuf = buffer.create(cornerCount * 2 * 4)

	local corner = 0
	for _, face in faces do
		for _, vi in { face.a, face.b, face.c } do
			local v = vertices[vi]
			local po = corner * 3 * 4
			buffer.writef32(posBuf, po, v.vx)
			buffer.writef32(posBuf, po + 4, v.vy)
			buffer.writef32(posBuf, po + 8, v.vz)

			buffer.writef32(nrmBuf, po, v.nx)
			buffer.writef32(nrmBuf, po + 4, v.ny)
			buffer.writef32(nrmBuf, po + 8, v.nz)

			local uo = corner * 2 * 4
			buffer.writef32(uvBuf, uo, v.tu)
			buffer.writef32(uvBuf, uo + 4, 1 - v.tv)

			corner += 1
		end
	end

	local posPtr = upload(posBuf)
	local nrmPtr = upload(nrmBuf)
	local uvPtr = upload(uvBuf)

	local size = readI64(api.DracoGetEncodedMeshFullSize(posPtr, nrmPtr, uvPtr, cornerCount, posBits, nrmBits, uvBits))
	if size < 0 then
		ffi.free(posPtr)
		ffi.free(nrmPtr)
		ffi.free(uvPtr)
		local reason = if size == -3
			then "mesh build failed (bad/degenerate geometry - check for NaN/zero-length data, duplicate corners forming a zero-area triangle, etc.)"
			elseif size == -4 then "Draco encode failed"
			else `unknown status {size}`
		error(`Draco.encodeMeshFull: DracoGetEncodedMeshFullSize failed - {reason}`)
	end

	local outPtr = allocOut(size)
	local written =
		readI64(api.DracoEncodeMeshFull(posPtr, nrmPtr, uvPtr, cornerCount, posBits, nrmBits, uvBits, outPtr, size))

	ffi.free(posPtr)
	ffi.free(nrmPtr)
	ffi.free(uvPtr)

	if written < 0 then
		ffi.free(outPtr)
		error(`Draco.encodeMeshFull: DracoEncodeMeshFull failed with status {written}`)
	end

	local result = download(outPtr, written)
	ffi.free(outPtr)
	return result
end

return Draco
