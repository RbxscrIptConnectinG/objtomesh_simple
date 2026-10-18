local fs = zune.fs

local react = require("@pkgs/React")
local reactReflex = require("@pkgs/ReactReflex")

local e = react.createElement

local theme = require("@toMesh/theme")

local props, state = {}, {}

export type props = {}
export type state = {}

return function(props: props, state: state)
	local producer = reactReflex.useProducer()
	local selected = reactReflex.useSelector(function(state)
		return state.intro.transparency
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
	}, {
		middle = e("Frame", {
			size = { 1, 0, 1, 0 },
			color = { 0, 0, 0, 1 },
			anchor = { 0.5, 0.5 },
			position = { 0.5, 0, 0.5, 0 },
			transparency = 1,
			layout = {
				direction = "horizontal",
				gap = 5,
				padding = 0,
				stretch = true,
				wrap = true,

				horizontalAlignment = "center",
				verticalAlignment = "center",
			},
		}, {
			GLFW = e("Image", {
				texture = "./assets/toMesh/images/icons/trademarks/glfw.png",
				antiAlias = "Grayscale",
				interpolation = "Linear",
				fit = "contain",
				anchor = { 1, 1 },
				size = { 0.15, 0, 0.15, 0 },
				position = { 1, 0, 1, 0 },
				autoSize = "xy",
				imageTransparency = selected,
				effects = {
					aspectRatio = {
						value = 1,
						type = "fitWithinMaxSize",
						dominantAxis = "height",
					},
				},
			}, {
				text = e("Text", {
					color = { 0, 0, 0, 1 },
					anchor = { 0.5, 0 },
					position = { 0.5, 0, 1, 0 },
					size = { 1, 0, 0.25, 0 },
					textColor = { 1, 1, 1, 1 - selected },
					antiAlias = "None",
					interpolation = "Nearest Neighbor",
					textScaled = true,
					valign = "center",
					align = "center",
					text = `GLFW`,
					font = "./assets/toMesh/fonts/Fira_Mono/FiraMono-Regular.ttf",
					transparency = selected,
					border = { width = 2, color = { 1, 1, 1, 0.15 - (selected * 0.15) } },
				}),
			}),
		}),
		lower = e("Frame", {
			size = { 1, 0, 1, 0 },
			color = { 0, 0, 0, 1 },
			anchor = { 0.5, 0.5 },
			position = { 0.5, 0, 0.5, 0 },
			transparency = 1,
			layout = {
				direction = "horizontal",
				gap = 5,
				padding = 0,
				stretch = true,
				wrap = true,

				horizontalAlignment = "center",
				verticalAlignment = "bottom",
			},
		}, {
			Vulkan = e("Image", {
				svg = "./assets/toMesh/images/icons/trademarks/vulkan.svg",
				antiAlias = "Grayscale",
				interpolation = "Linear",
				fit = "contain",
				anchor = { 0, 1 },
				size = { 0.5 / 2, 0, 0.5 / 4, 0 },
				autoSize = "xy",
				position = { 0, 0, 1, 0 },
				imageTransparency = selected,
				effects = {
					aspectRatio = {
						value = 2,
						type = "fitWithinMaxSize",
						dominantAxis = "width",
					},
				},
			}),
			SpirV = e("Image", {
				svg = "./assets/toMesh/images/icons/trademarks/spirv.svg",
				antiAlias = "Grayscale",
				interpolation = "Linear",
				fit = "contain",
				anchor = { 1, 1 },
				size = { 0.5 / 2, 0, 0.5 / 4, 0 },
				autoSize = "xy",
				position = { 1, 0, 1, 0 },
				imageTransparency = selected,
				effects = {
					aspectRatio = {
						value = 2,
						type = "fitWithinMaxSize",
						dominantAxis = "width",
					},
				},
			}),
		}),
	})
end
