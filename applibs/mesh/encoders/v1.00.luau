local meshTypes = require("@applibs/mesh/types")
local meshUtils = require("@applibs/mesh/utils")
local parseObj = require("@applibs/mesh/parsers/obj")

local POSITION_SCALE = 2.0

return function(objData)
	local mesh = parseObj(objData)
	local parts: { string } = { "version 1.00\n", tostring(#mesh.faces), "\n" }

	for _, f in mesh.faces do
		for _, vi in { f.a, f.b, f.c } do
			local v = mesh.vertices[vi]
			table.insert(
				parts,
				`[{meshUtils.fmt(v.vx * POSITION_SCALE)},{meshUtils.fmt(v.vy * POSITION_SCALE)},{meshUtils.fmt(
					v.vz * POSITION_SCALE
				)}]`
					.. `[{meshUtils.fmt(v.nx)},{meshUtils.fmt(v.ny)},{meshUtils.fmt(v.nz)}]`
					.. `[{meshUtils.fmt(v.tu)},{meshUtils.fmt(1 - v.tv)},0]`
			)
		end
	end

	return table.concat(parts)
end
