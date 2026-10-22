local fs = zune.fs

local react = require("@pkgs/React")
local reactReflex = require("@pkgs/ReactReflex")
local reactVkui = require("@pkgs/ReactVkui")

local e = react.createElement

local theme = require("@toMesh/theme")
local mesh = require("@applibs/mesh/")

local props, state = {}, {}

export type props = {}
export type state = {}

local padding = 16 / 2

return function(props: props, state: state)
	local renderer = reactVkui.useRenderer()
	local producer = reactReflex.useProducer()
	local selected: number = reactReflex.useSelector(function(state)
		return state.intro.transparency
	end)
	local model = react.useMemo(function()
		return renderer:createModel(mesh.parsers.obj(mesh, fs.readFileSync("./assets/toMesh/models/baseCube.obj")))
	end, { renderer })
	if selected < 1 then
		return
	end

	return e("Frame", {
		size = { 1, 0, 1, 0 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
		transparency = 1,
		border = { width = padding / 2, color = { 1, 1, 1, 0.15 } },
	}, {
		padding = e("Frame", {
			size = { 1, -padding, 1, -padding },
			anchor = { 0.5, 0.5 },
			position = { 0.5, 0, 0.5, 0 },
			transparency = 1,
			effects = {
				listLayout = {
					fillDirection = "horizontal",
					wraps = true,
					padding = 0,
					verticalFlex = "Fill",
					horizontalFlex = "Fill",
					itemLineAlignment = "Automatic",
				},
			},
		}, {
			scroll = e("ScrollingFrame", {
				size = { 0.5, 0, 1, 0 },
				anchor = { 0, 0.5 },
				position = { 0, 0, 0.5, 0 },
				listLayout = {
					fillDirection = "vertical",
					wraps = true,
					padding = 0,
					itemLineAlignment = "Automatic",
				},
			}, {
				button = e("Button", {
					size = { 1, 0, 0.1, 0 },
				}),
			}),
			modelview = e("ModelView", {
				size = { 1, 0, 1, 0 },
				anchor = { 1, 0.5 },
				position = { 1, 0, 0.5, 0 },
				model = model,
				viewShaders = { ["chromatic.glsl"] = { order = 1 }, ["datamosh.glsl"] = {
					blockSize = 5,
				} },
				zoomable = true,
			}),
		}),
	})
end
