local meshTypes = require("@applibs/meshTypes")
local parseObj = require("@applibs/mesh/parsers/obj")

return function(objData, scale)
	scale = scale or 0.5
	local parsedObj = parseObj(objData)
	local faceData = {}

	for _, vert in ipairs(parsedObj.vertices) do
		for i = 1, 3 do
			local vertIndices = vert[i] :: meshTypes.Vertex

			local pos = { vertIndices.vx or 0, vertIndices.vy or 0, vertIndices.vz or 0 }

			local norm = { vertIndices.nx or 0, vertIndices.ny or 0, vertIndices.nz or 0 }

			local uv = { vertIndices.tu or 0, vertIndices.tv or 0, vertIndices.tw or 0 }

			local vertStr = string.format(
				"[%f,%f,%f][%f,%f,%f][%f,%f,%f]",
				pos[1] * scale,
				pos[2] * scale,
				pos[3] * scale,
				norm[1],
				norm[2],
				norm[3],
				uv[1],
				1 - uv[2],
				uv[3]
			)
			table.insert(faceData, vertStr)
		end
	end

	local line1 = "version 1.00"
	local line2 = tostring(#parsedObj.faces)
	local line3 = table.concat(faceData, "\n")

	return line1 .. "\n" .. line2 .. "\n" .. line3
end
