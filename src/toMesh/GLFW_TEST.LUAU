local time = zune.time
local fs = zune.fs

local ui = require("@libs/luau/UIFramework")
local png = require("@libs/luau/UIFramework/png")
local win_popups = require("@libs/luau/WinLibs/popup")

local React = require("@pkgs/React")
local ReactVkui = require("@pkgs/ReactVkui")

local e = React.createElement

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
	width = 1000,
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
		layout = { direction = "horizontal", gap = 12, padding = 12 },
	})
end

ReactVkui.run(app, e(App))
app:destroy()
