local meshTypes = require("@applibs/mesh/types")

export type options = {}

return function(root, objData, options: options): string
	options = options or {} :: options

	local mesh = root.parsers.obj(root, objData)
	local parts: { string } = { "version 1.01\n", tostring(#mesh.faces), "\n" }

	for _, f in mesh.faces do
		for _, vi in { f.a, f.b, f.c } do
			local v = mesh.vertices[vi]
			table.insert(
				parts,
				`[{root.utils.fmt(v.vx)},{root.utils.fmt(v.vy)},{root.utils.fmt(v.vz)}]`
					.. `[{root.utils.fmt(v.nx)},{root.utils.fmt(v.ny)},{root.utils.fmt(v.nz)}]`
					.. `[{root.utils.fmt(v.tu)},{root.utils.fmt(1 - v.tv)},0]`
			)
		end
	end

	return table.concat(parts)
end
