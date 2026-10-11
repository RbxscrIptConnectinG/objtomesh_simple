local types = require("../types")
local sift = require("@pkgs/Sift")
return function(app: types.App, arguments)
	if #arguments > 0 then
		local globals = {
			outputPath = nil,
			inputs = {},
		}
		arguments = sift.List.map(arguments, function(value: string, index: number)
			if value:match("^--output=") then
				globals.outputPath = value:gsub("^--output=", "")
				return value, index
			elseif value:match("^-f=") then
				table.insert(globals.inputs, select(1, value:gsub("^-f=", "")) :: any)
				return value, index
			end
			return
		end)
		if #arguments > 0 then
			--if not sift.isEmpty(globals.inputs) and globals.outputPath then
			--	print("we got them input and output paths, doing some magic...")

			--app.utils.fileManip.processPath(globals.inputs, globals.outputPath)
			--end

			return globals
		end
	end
	return nil
end
