local fs = zune.fs

local react = require("@pkgs/React")
local reactReflex = require("@pkgs/ReactReflex")
local reactVkui = require("@pkgs/ReactVkui")

local e = react.createElement

local theme = require("@toMesh/theme")
local sift = require("@pkgs/Sift")
local mesh = require("@applibs/mesh/")
local cframe = require("@applibs/cframe")
local scenelib = require("@libs/luau/UIFramework/UI/scene")

local props, state = {}, {}

export type props = {}
export type state = {}

local padding = 16 / 2

local default = {
	texture = "./assets/toMesh/models/maw/c.png",
	normalMap = "./assets/toMesh/models/maw/n.png",
	roughnessMap = "./assets/toMesh/models/maw/r.png",
	metalnessMap = "./assets/toMesh/models/maw/m.png",
	--ambientOcclusionMap = "ao.png",
	normalMapFormat = "OpenGL",
	roughness = 1,
	metalness = 1,
	--ambientOcclusionStrength = 1,
}

local rot = 0

local prv = zune.time.timestampMillis()

local scene = scenelib.new()

--[[zune.task.spawn(function()
	while zune.process.pid() do
		local dt = (zune.time.timestampMillis() - prv) * 60

		rot = math.rad(math.deg(rot) + dt)
		prv = zune.time.timestampMillis()
		print(scene.objects)
		zune.task.wait()
	end
end)]]

return function(props: props, state: state)
	local renderer = reactVkui.useRenderer()
	local producer = reactReflex.useProducer()
	local selected: number = reactReflex.useSelector(function(state)
		return state.intro.transparency
	end)
	local scene = react.useMemo(function()
		local model =
			renderer:createModel(mesh.parsers.obj(mesh, fs.readFileSync("./assets/toMesh/models/maw/maw.obj")))
		local UIFW = renderer.UIFW

		scene.camera.cframe = cframe.new(0, 0, 15)
		local s = 0.1

		scene:addModel(
			model,
			s,
			cframe.new(7, 0, 0) * cframe.fromEulerAnglesYXZ(math.rad(90), rot, 0),
			sift.Dictionary.joinDeep(default, {
				shaders = {
					["chromatic.glsl"] = {},
				},
			})
		)
		scene:addModel(
			model,
			s,
			cframe.new(0, 0, 0) * cframe.fromEulerAnglesYXZ(math.rad(90), rot, 0),
			sift.Dictionary.joinDeep(default, {
				shaders = {
					["chromatic.glsl"] = {
						order = 2,
						offset = 5,
					},
					["datamosh.glsl"] = {
						order = 1,
						amount = 1,
						threshold = 0.6,
						refresh = 0.05,
						blockSize = 2,
						smear = 2,
					},
				},
			})
		)
		scene:addModel(
			model,
			s,
			cframe.new(-7, 0, 0) * cframe.fromEulerAnglesYXZ(math.rad(90), rot, 0),
			sift.Dictionary.joinDeep(default, {
				shaders = {
					["datamosh.glsl"] = {
						order = 1,
						amount = 1,
						threshold = 0.6,
						refresh = 0.05,
						blockSize = 2,
						smear = 2,
					},
				},
			})
		)

		return scene
	end, { renderer })
	if selected < 3 then
		return
	end

	return e("Frame", {
		size = { 1, 0, 1, 0 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
		backgroundTransparency = 1,
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
			scene = e("ViewportFrame", {
				size = { 1, 0, 1, 0 },
				anchor = { 0.5, 0.5 },
				position = { 0.5, 0, 0.5, 0 },
				scene = scene,
			}),
			--[[scroll = e("ScrollingFrame", {
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
				doubleSided = false,
				model = model,
				modelTransparencyMethod = "dither",
				imageTransparency = 0.9,
				viewShaders = {
					["chromatic.glsl"] = {
						order = 2,
					},
					["datamosh.glsl"] = {
						order = 1,
						amount = 1,
						threshold = 0.6,
						refresh = 0.05,
						blockSize = 2,
						smear = 2,
					},
				},
				zoomable = true,
			}),]]
		}),
	})
end
