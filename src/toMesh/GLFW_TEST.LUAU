local time = zune.time
local fs = zune.fs

local ui = require("@libs/luau/UIFramework")
local win_popups = require("@libs/luau/WinLibs/popup")

local react = require("@pkgs/React")
local reactVkui = require("@pkgs/ReactVkui")

local e = react.createElement

local tick = time.timestampMillis

if fs.stat("C:/Windows/System32/vulkan-1.dll").kind == "none" then
	win_popups.alert(
		`Missing "{"C:/Windows/System32/vulkan-1.dll"}"\nplease install vulkan runtime {"https://vulkan.lunarg.com/sdk/home"}`,
		`DLL is missing`,
		"warning"
	)
	return
end

local app = ui.createApp({
	width = 640,
	height = 640,
	title = "vkui demo",
	glfwPath = "./libs/bin/glfw3.dll",
	renderer = {
		libraryPath = "C:/Windows/System32/vulkan-1.dll",
	},
	shaders = {
		libraryPath = "./libs/bin/shaderc_shared.dll",
		shaders = "./assets/toMesh/bin/shaders",
	},
	vsync = true,
	font = "./assets/toMesh/fonts/cour/Courier New.ttf",
})
local renderer = app.renderer
local function App()
	return e("Frame", {
		size = { 1, 0, 1, 0 },
		color = { 0.08, 0.09, 0.11, 1 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
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
		}),
		SpirV = e("Image", {
			svg = fs.readFileSync("./assets/toMesh/images/icons/trademarks/spirv.svg"),
			antiAlias = "Grayscale",
			interpolation = "Linear",
			fit = "contain",
			anchor = { 1, 1 },
			size = { 0.5 / 2, 0, 0.5 / 2, 0 },
			position = { 1, 0, 1, 0 },
		}),
		GLFW = e("Image", {
			texture = renderer:loadImage(fs.readFileSync("./assets/toMesh/images/icons/trademarks/glfw.png")),
			antiAlias = "Grayscale",
			interpolation = "Linear",
			fit = "contain",
			anchor = { 1, 1 },
			size = { 0.5 / 4, 0, 0.5 / 2, 0 },
			position = { 1, 0, 1, 0 },
		}),
	})
end

reactVkui.run(app, e(App))
app:destroy()
