local meshtypes = require("@applibs/meshtypes")
local IsDev = false

local mesh = {}
mesh.parsers = {
	v1 = require("@self/parsers/v1"),
	v2 = require("@self/parsers/v2"),
	v3 = require("@self/parsers/v3"),
	v4 = require("@self/parsers/v4"),
	--v5 = require("@self/parsers/v5"),
	--v6 = require("@self/parsers/v6"),
}

-- this is stupid. i  know...
mesh.parsers.v5 = mesh.parsers.v4
mesh.parsers.v6 = mesh.parsers.v5

if IsDev then
	mesh.parsers.v7 = require("@self/parsers/v7")
end

function mesh.decodeMesh(data: string): meshtypes.MeshData
	local lineEnd = data:find("\n")
	if not lineEnd then
		error("Invalid mesh file: missing header newline")
	end

	local header = data:sub(1, lineEnd - 1):match("^%s*(.-)%s*$")
	local contentOffset = lineEnd + 1

	if header == "version 1.00" then
		return mesh.parsers.v1(data, contentOffset, 0.5)
	elseif header == "version 1.01" then
		return mesh.parsers.v1(data, contentOffset, 1.0)
	elseif header == "version 2.00" then
		return mesh.parsers.v2(data, contentOffset)
	elseif header == "version 3.00" or header == "version 3.01" then
		return mesh.parsers.v3(data, contentOffset)
	elseif header == "version 4.00" or header == "version 4.01" then
		return mesh.parsers.v4(data, contentOffset)
	elseif header == "version 5.00" then
		return mesh.parsers.v5(data, contentOffset)
	elseif header == "version 6.00" then
		return mesh.parsers.v6(data, contentOffset)
	elseif header == "version 7.00" and IsDev then
		return mesh.parsers.v7(data, contentOffset)
	else
		error("Unsupported mesh version: " .. tostring(header))
	end
end

function mesh.meshToOBJ(mesh: meshtypes.MeshData): string
	local lines = { "# Exported from Roblox FileMesh" }

	for _, v in ipairs(mesh.vertices) do
		table.insert(lines, string.format("v %.6f %.6f %.6f", v.vx or 0, v.vy or 0, v.vz or 0))
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
function mesh.objToMesh(objData: string): string
	local positions: { { number } } = {}
	local uvs: { { number } } = {}
	local normals: { { number } } = {}

	local uniqueVertices: { meshtypes.Vertex } = {}
	local vertexMap: { [string]: number } = {}
	local faces: { meshtypes.Face } = {}

	local function getOrAddVertex(vIdx: number, vtIdx: number, vnIdx: number): number
		local key = string.format("%d/%d/%d", vIdx, vtIdx, vnIdx)
		if vertexMap[key] then
			return vertexMap[key]
		end

		local pos = positions[vIdx] or { 0, 0, 0 }
		local uv = uvs[vtIdx] or { 0, 0 }
		local norm = normals[vnIdx] or { 0, 0, 0 }

		local vertex: meshtypes.Vertex = {
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

function mesh.convertMeshToOBJ(data: string): string
	local mesh = mesh.decodeMesh(data)
	return mesh.meshToOBJ(mesh)
end

function mesh.objToTable(objData)
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

return mesh
