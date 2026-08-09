local MeshConverter = {}

export type Vertex = {
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

export type Face = {
	a: number,
	b: number,
	c: number,
}

export type MeshData = {
	vertices: { Vertex },
	faces: { Face },
}

local function parseV1(data: string, headerOffset: number, scaler: number): MeshData
	local offset = headerOffset

	local numFacesStr, nextOffset = data:match("^(%d+)%s*()", offset)
	if not numFacesStr then
		error("Failed to parse face count in v1 mesh header")
	end

	local numFaces = tonumber(numFacesStr) :: number
	offset = nextOffset

	local vertices: { Vertex } = {}
	local faces: { Face } = {}

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
				vx = vx,
				vy = vy,
				vz = vz,
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

local function parseV2(data: string, headerOffset: number): MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1
	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)
	local numVertices = buffer.readu32(buf, offset + 4)
	local numFaces = buffer.readu32(buf, offset + 8)

	offset += 12

	if cbSize ~= 12 or cbVerticesStride ~= 36 or cbFaceStride ~= 12 then
		error("Incompatible version 2.00 mesh stride or size header")
	end

	local vertices: { Vertex } = table.create(numVertices)
	for i = 1, numVertices do
		local vx = buffer.readf32(buf, offset)
		local vy = buffer.readf32(buf, offset + 4)
		local vz = buffer.readf32(buf, offset + 8)

		local nx = buffer.readf32(buf, offset + 12)
		local ny = buffer.readf32(buf, offset + 16)
		local nz = buffer.readf32(buf, offset + 20)

		local tu = buffer.readf32(buf, offset + 24)
		local tv = buffer.readf32(buf, offset + 28)
		local tw = buffer.readf32(buf, offset + 32)

		vertices[i] = {
			vx = vx,
			vy = vy,
			vz = vz,
			nx = nx,
			ny = ny,
			nz = nz,
			tu = tu,
			tv = 1 - tv,
			tw = tw,
		}

		offset += cbVerticesStride
	end

	local faces: { Face } = table.create(numFaces)
	for i = 1, numFaces do
		local a = buffer.readu32(buf, offset) + 1
		local b = buffer.readu32(buf, offset + 4) + 1
		local c = buffer.readu32(buf, offset + 8) + 1

		faces[i] = { a = a, b = b, c = c }
		offset += cbFaceStride
	end

	return { vertices = vertices, faces = faces }
end

local function parseV3(data: string, headerOffset: number): MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1

	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)

	local numLODs = buffer.readu16(buf, offset + 4)
	local numSubsets = buffer.readu16(buf, offset + 6)

	local numFaces = buffer.readu32(buf, offset + 8)
	local numVertices = buffer.readu32(buf, offset + 12)

	offset += cbSize

	if cbVerticesStride ~= 36 or cbFaceStride ~= 12 then
		error("Incompatible version 3.00 mesh stride")
	end

	local vertices: { Vertex } = table.create(numVertices)
	for i = 1, numVertices do
		vertices[i] = {
			vx = buffer.readf32(buf, offset),
			vy = buffer.readf32(buf, offset + 4),
			vz = buffer.readf32(buf, offset + 8),
			nx = buffer.readf32(buf, offset + 12),
			ny = buffer.readf32(buf, offset + 16),
			nz = buffer.readf32(buf, offset + 20),
			tu = buffer.readf32(buf, offset + 24),
			tv = 1 - buffer.readf32(buf, offset + 28),
			tw = buffer.readf32(buf, offset + 32),
		}
		offset += cbVerticesStride
	end

	local faces: { Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = {
			a = buffer.readu32(buf, offset) + 1,
			b = buffer.readu32(buf, offset + 4) + 1,
			c = buffer.readu32(buf, offset + 8) + 1,
		}
		offset += cbFaceStride
	end

	return { vertices = vertices, faces = faces }
end

local function parseV4(data: string, headerOffset: number): MeshData
	local buf = buffer.fromstring(data)
	local offset = headerOffset - 1

	local cbSize = buffer.readu16(buf, offset)
	local cbVerticesStride = buffer.readu8(buf, offset + 2)
	local cbFaceStride = buffer.readu8(buf, offset + 3)

	local numLODs = buffer.readu16(buf, offset + 4)
	local numSubsets = buffer.readu16(buf, offset + 6)

	local numFaces = buffer.readu32(buf, offset + 8)
	local numVertices = buffer.readu32(buf, offset + 12)
	local numBones = buffer.readu32(buf, offset + 16)

	offset += cbSize

	local vertices: { Vertex } = table.create(numVertices)
	for i = 1, numVertices do
		vertices[i] = {
			vx = buffer.readf32(buf, offset),
			vy = buffer.readf32(buf, offset + 4),
			vz = buffer.readf32(buf, offset + 8),
			nx = buffer.readf32(buf, offset + 12),
			ny = buffer.readf32(buf, offset + 16),
			nz = buffer.readf32(buf, offset + 20),
			tu = buffer.readf32(buf, offset + 24),
			tv = 1 - buffer.readf32(buf, offset + 28),
			tw = buffer.readf32(buf, offset + 32),
		}

		offset += cbVerticesStride
	end

	if numBones > 0 then
		offset += (numVertices * 8)
	end

	local faces: { Face } = table.create(numFaces)
	for i = 1, numFaces do
		faces[i] = {
			a = buffer.readu32(buf, offset) + 1,
			b = buffer.readu32(buf, offset + 4) + 1,
			c = buffer.readu32(buf, offset + 8) + 1,
		}
		offset += cbFaceStride
	end

	return { vertices = vertices, faces = faces }
end

local function parseV5(data: string, headerOffset: number): MeshData
	return parseV4(data, headerOffset)
end

local function parseV6(data: string, headerOffset: number): MeshData
	return parseV5(data, headerOffset)
end

function MeshConverter.decodeMesh(data: string): MeshData
	local lineEnd = data:find("\n")
	if not lineEnd then
		error("Invalid mesh file: missing header newline")
	end

	local header = data:sub(1, lineEnd - 1):match("^%s*(.-)%s*$")
	local contentOffset = lineEnd + 1

	if header == "version 1.00" then
		return parseV1(data, contentOffset, 0.5)
	elseif header == "version 1.01" then
		return parseV1(data, contentOffset, 1.0)
	elseif header == "version 2.00" then
		return parseV2(data, contentOffset)
	elseif header == "version 3.00" or header == "version 3.01" then
		return parseV3(data, contentOffset)
	elseif header == "version 4.00" or header == "version 4.01" then
		return parseV4(data, contentOffset)
	elseif header == "version 5.00" then
		return parseV5(data, contentOffset)
	elseif header == "version 6.00" then
		return parseV6(data, contentOffset)
	else
		error("Unsupported mesh version: " .. tostring(header))
	end
end

function MeshConverter.meshToOBJ(mesh: MeshData): string
	local lines = { "# Exported from Roblox FileMesh" }

	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("v %.6f %.6f %.6f", v.vx, v.vy, v.vz))
	end
	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("vt %.6f %.6f", v.tu, v.tv))
	end
	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("vn %.6f %.6f %.6f", v.nx, v.ny, v.nz))
	end
	for _, f in ipairs(mesh.faces) do
		table.insert(lines, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d", f.a, f.a, f.a, f.b, f.b, f.b, f.c, f.c, f.c))
	end

	return table.concat(lines, "\n")
end
function MeshConverter.objToMesh(objData: string): string
	local positions: { { number } } = {}
	local uvs: { { number } } = {}
	local normals: { { number } } = {}

	local uniqueVertices: { Vertex } = {}
	local vertexMap: { [string]: number } = {}
	local faces: { Face } = {}

	local function getOrAddVertex(vIdx: number, vtIdx: number, vnIdx: number): number
		local key = string.format("%d/%d/%d", vIdx, vtIdx, vnIdx)
		if vertexMap[key] then
			return vertexMap[key]
		end

		local pos = positions[vIdx] or { 0, 0, 0 }
		local uv = uvs[vtIdx] or { 0, 0 }
		local norm = normals[vnIdx] or { 0, 0, 0 }

		local vertex: Vertex = {
			vx = pos[1],
			vy = pos[2],
			vz = pos[3],
			nx = norm[1],
			ny = norm[2],
			nz = norm[3],
			tu = uv[1],
			tv = 1 - uv[2],
			tw = 0,
		}

		table.insert(uniqueVertices, vertex)
		local newIdx = #uniqueVertices
		vertexMap[key] = newIdx
		return newIdx
	end

	for line in objData:gmatch("[^\r\n]+") do
		line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")

		if line ~= "" then
			local parts = {}
			for part in line:gmatch("%S+") do
				table.insert(parts, part)
			end

			local tag = parts[1]
			if tag == "v" and #parts >= 4 then
				table.insert(positions, { tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]) })
			elseif tag == "vt" and #parts >= 3 then
				table.insert(uvs, { tonumber(parts[2]), tonumber(parts[3]) })
			elseif tag == "vn" and #parts >= 4 then
				table.insert(normals, { tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]) })
			elseif tag == "f" and #parts >= 4 then
				local faceIndices = {}
				for i = 2, #parts do
					local vI, vtI, vnI = parts[i]:match("^(%d*)/?(%d*)/?(%d*)")
					local vIdx = tonumber(vI) or 0
					local vtIdx = tonumber(vtI) or 0
					local vnIdx = tonumber(vnI) or 0

					if vIdx < 0 then
						vIdx = #positions + vIdx + 1
					end
					if vtIdx < 0 then
						vtIdx = #uvs + vtIdx + 1
					end
					if vnIdx < 0 then
						vnIdx = #normals + vnIdx + 1
					end

					table.insert(faceIndices, getOrAddVertex(vIdx, vtIdx, vnIdx))
				end

				for i = 2, #faceIndices - 1 do
					table.insert(faces, {
						a = faceIndices[1],
						b = faceIndices[i],
						c = faceIndices[i + 1],
					})
				end
			end
		end
	end

	local headerSize = 12
	local vertexStride = 36
	local faceStride = 12

	local numVertices = #uniqueVertices
	local numFaces = #faces

	local totalSize = headerSize + (numVertices * vertexStride) + (numFaces * faceStride)
	local buf = buffer.create(totalSize)

	buffer.writeu16(buf, 0, headerSize)
	buffer.writeu8(buf, 2, vertexStride)
	buffer.writeu8(buf, 3, faceStride)
	buffer.writeu32(buf, 4, numVertices)
	buffer.writeu32(buf, 8, numFaces)

	local offset = headerSize

	for _, v in ipairs(uniqueVertices) do
		buffer.writef32(buf, offset + 0, v.vx)
		buffer.writef32(buf, offset + 4, v.vy)
		buffer.writef32(buf, offset + 8, v.vz)

		buffer.writef32(buf, offset + 12, v.nx)
		buffer.writef32(buf, offset + 16, v.ny)
		buffer.writef32(buf, offset + 20, v.nz)

		buffer.writef32(buf, offset + 24, v.tu)
		buffer.writef32(buf, offset + 28, v.tv)
		buffer.writef32(buf, offset + 32, v.tw)

		offset += vertexStride
	end

	for _, f in ipairs(faces) do
		buffer.writeu32(buf, offset + 0, f.a - 1)
		buffer.writeu32(buf, offset + 4, f.b - 1)
		buffer.writeu32(buf, offset + 8, f.c - 1)

		offset += faceStride
	end

	return "version 2.00\n" .. buffer.tostring(buf)
end

function MeshConverter.convertMeshToOBJ(data: string): string
	local mesh = MeshConverter.decodeMesh(data)
	return MeshConverter.meshToOBJ(mesh)
end

function MeshConverter.objToTable(objData)
	local vertices = {}
	local texcoords = {}
	local normals = {}
	local faces = {}

	for line in objData:gmatch("[^\r\n]+") do
		if not line:match("^#") and line:match("%S") then
			local prefix, data = line:match("^([a-zA-Z]+)%s+(.*)")

			if prefix == "v" then
				local x, y, z = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(vertices, { tonumber(x), tonumber(y), tonumber(z) })
			elseif prefix == "vt" then
				local u, v, w = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(texcoords, { tonumber(u), tonumber(v), tonumber(w) })
			elseif prefix == "vn" then
				local nx, ny, nz = data:match("([%d%-%+%.e]+)%s+([%d%-%+%.e]+)%s+([%d%-%+%.e]+)")
				table.insert(normals, { tonumber(nx), tonumber(ny), tonumber(nz) })
			elseif prefix == "f" then
				local faceIndices = {}
				for vertexStr in data:gmatch("%S+") do
					local parts = {}
					for p in vertexStr:gmatch("[^/]*") do
						if p ~= "" then
							table.insert(parts, tonumber(p))
						end
					end
					table.insert(faceIndices, parts)
				end
				table.insert(faces, faceIndices)
			end
		end
	end

	return {
		vertices = vertices,
		texcoords = texcoords,
		normals = normals,
		faces = faces,
	}
end

return MeshConverter
