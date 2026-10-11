local react = require("@pkgs/React")
local reactReflex = require("@pkgs/ReactReflex")

local fs = zune.fs

local e = react.createElement

local props, state = {}, {}

export type props = {}
export type state = {}

return function(props: props, state: state)
	local producer = reactReflex.useProducer()
	local selected = reactReflex.useSelector(function(state)
		return state
	end)
	if selected >= 1 then
		return nil
	end
	return e("Frame", {
		size = { 0.8, 0, 0.8, 0 },
		color = { 0, 0, 0, 1 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
		transparency = 1,
		layout = {
			direction = "horizontal",
			gap = 0,
			padding = 0,
			stretch = true,
			wrap = true,

			horizontalAlignment = "center",
			verticalAlignment = "bottom",
		},
	}, {
		Vulkan = e("Image", {
			svg = fs.readFileSync("./assets/toMesh/images/icons/trademarks/vulkan.svg"),
			antiAlias = "Grayscale",
			interpolation = "Linear",
			fit = "contain",
			anchor = { 0, 1 },
			size = { 0.5 / 2, 0, 0.5 / 2, 0 },
			position = { 0, 0, 1, 0 },
			imageTransparency = selected,
		}),
		SpirV = e("Image", {
			svg = fs.readFileSync("./assets/toMesh/images/icons/trademarks/spirv.svg"),
			antiAlias = "Grayscale",
			interpolation = "Linear",
			fit = "contain",
			anchor = { 1, 1 },
			size = { 0.5 / 2, 0, 0.5 / 2, 0 },
			position = { 1, 0, 1, 0 },
			imageTransparency = selected,
		}),
		--[[GLFW = e("Image", {
			texture = fs.readFileSync("./assets/toMesh/images/icons/trademarks/glfw.png"),
			antiAlias = "Grayscale",
			interpolation = "Linear",
			fit = "contain",
			anchor = { 1, 1 },
			size = { 0.5 / 4, 0, 0.5 / 2, 0 },
			position = { 1, 0, 1, 0 },
		}),]]
	})
end
