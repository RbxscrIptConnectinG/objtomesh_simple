local time = zune.time
local fs = zune.fs

local ui = require("@libs/luau/UIFramework")
local png = require("@libs/luau/UIFramework/png")
local win_popups = require("@libs/luau/WinLibs/popup")

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

local elements = {
	container = ui.Frame({
		position = { 0, 0 },
		size = { 1, 0, 1, 0 },
		border = { width = 2, color = { 1, 1, 1, 0.15 } },
	}),
	FPS = {
		container = ui.Frame({
			size = { 0, 0, 0, 0 },
			position = { 0, 0 },
			anchor = { 0, 0 },
			ZIndex = 0,
			autoSize = "xy",
			ZIndexBehavior = "Global",
		}),
		counter = ui.Text({
			text = "Hello",
			position = { 0, 2, 0, 2 },
			textSize = 24,
			autoSize = "xy",
			align = "left",
			valign = "center",
			anchor = { 0, 0 },
			textColor = { 1, 1, 1, 1 },
			antiAlias = "off",
			ZIndex = 1,
			ZIndexBehavior = "Global",
		}),
	},
}

app.root:add(elements.container)

local FPS_COUNTDOWN = 0
local FPS = 0
local elapsedTime = 0

app:run(function(dt)
	elapsedTime += dt

	if FPS_COUNTDOWN >= 1 then
		--text.text = "FPS: " .. tostring(FPS)
		FPS = 0
		FPS_COUNTDOWN = 0
	end

	FPS_COUNTDOWN += dt
	FPS += 1

	--view.imageTransparency = model_imageTransparency or 0.5 + math.sin(elapsedTime * 2) * 0.5
end)
app:destroy()
