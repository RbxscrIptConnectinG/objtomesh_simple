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

local parsedObj
do
	local parser = require("@applibs/mesh/parsers/obj")
	parsedObj = parser(fs.readFileSync("./assets/toMesh/models/cat.obj"), false)
end

--local texture = renderer:createTexture(64, 64, checker(64, 8 / 4))

local model = renderer:createModel(parsedObj)

local w, h, tex = png.decode(fs.readFileSync("./assets/toMesh/images/PLACEHOLDERS/cat.png"))

local w2, h2, tex2 = png.decode(fs.readFileSync("./assets/toMesh/images/PLACEHOLDERS/Meow.png"))

-- right: model view

local baseFrame = app.root:add(ui.Frame({
	position = { 0, 0 },
	size = { 1, 0, 1, -0 },
	border = { width = 2, color = { 1, 1, 1, 0.15 } },
}))

local model_imageTransparency = nil

local view = baseFrame:add(ui.ModelView({
	position = { 0, 0 },
	size = { 1, 0, 1, -0 },
	model = model,
	texture = renderer:createTexture(w2, h2, tex2),
	border = { width = 2, color = { 1, 1, 1, 0.15 } },
	doubleSided = true,
	zoomable = true,
	interactive = true,
	fov = 1.5,
	zoom = 0.8,
	imageTransparency = model_imageTransparency,
	transparencyMethod = "dither",
	pixelated = true,
}))

local textholder = baseFrame:add(ui.Frame({
	size = { 0, 0, 0, 0 },
	position = { 0, 0 },
	anchor = { 0, 0 },
	ZIndex = 0,
	autoSize = "xy",
	ZIndexBehavior = "Global",
}))

local text = textholder:add(ui.Text({
	--font = "./assets/toMesh/fonts/DS-DIGI/DS-Digital.TTF",
	text = "Hello",
	position = { 0, 2, 0, 2 },
	textSize = 24,
	autoSize = "xy",
	align = "left",
	valign = "center",
	anchor = { 0, 0 },
	textColor = { 1, 1, 1, 1 },
	antiAlias = false,
	ZIndex = 1,
	ZIndexBehavior = "Global",
}))
transparencyBox = baseFrame:add(ui.TextBox({
	--font = "./assets/toMesh/fonts/DS-DIGI/DS-Digital.TTF",
	placeholder = "transparency",
	position = { 0, 2, 1, -2 },
	textSize = 24,
	autoSize = "xy",
	align = "center",
	valign = "center",
	anchor = { 0, 1 },
	size = { 0, 10, 0, 20 },
	textColor = { 1, 1, 1, 1 },
	antiAlias = true,
	ZIndex = 1,
	ZIndexBehavior = "Global",

	onSubmit = function(button, text)
		model_imageTransparency = tonumber(text) or nil
	end,
}))

local FPS_COUNTDOWN = 0
local FPS = 0
local elapsedTime = 0

app:run(function(dt)
	elapsedTime += dt

	if FPS_COUNTDOWN >= 1 then
		text.text = "FPS: " .. tostring(FPS)
		FPS = 0
		FPS_COUNTDOWN = 0
	end

	FPS_COUNTDOWN += dt
	FPS += 1

	view.imageTransparency = model_imageTransparency or 0.5 + math.sin(elapsedTime * 2) * 0.5
end)
app:destroy()
