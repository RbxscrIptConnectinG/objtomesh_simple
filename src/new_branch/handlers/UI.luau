local fs = zune.fs

local UIFW = require("@libs/luau/UIFramework")

local react = require("@pkgs/React")
local reactVkui = require("@pkgs/ReactVkui")
local reactReflex = require("@pkgs/ReactReflex")

local win_popups = require("@libs/luau/WinLibs/popup")

local types = require("@toMesh/types")

local e = react.createElement

local components = {
	intro = require("@toMesh/components/intro"),
}

local UI = {}
UI.__index = UI

function UI.new(root: types.App)
	local self = setmetatable({}, UI)
	self.root = root

	if fs.stat("C:/Windows/System32/vulkan-1.dll").kind == "none" then
		win_popups.alert(
			`Missing "{"C:/Windows/System32/vulkan-1.dll"}"\nplease install vulkan runtime {"https://vulkan.lunarg.com/sdk/home"}`,
			`DLL is missing`,
			"warning"
		)
		error(`missing "C:/Windows/System32/vulkan-1.dll"`)
	end

	self.app = UIFW.createApp({
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
		font = "./assets/toMesh/fonts/Inconsolata/Inconsolata-VariableFont_wdth,wght.ttf",
	})

	self.producers = {
		intro = require("../producers/intro"),
	}
	self.children = self:getRender()

	return self
end

function UI:getRender()
	return e("Frame", {
		size = { 1, 0, 1, 0 },
		color = { 0.08, 0.09, 0.11, 0 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
		backgroundTransparency = 0,
	}, {
		button = e("Button", {
			onClick = function()
				self.producers.intro.transparency.add(0.1)
			end,
		}),
		buttonplus = e("Button", {
			anchor = { 1, 0 },
			position = { 1, 0, 0, 0 },
			onClick = function()
				self.producers.intro.transparency.remove(0.1)
			end,
		}),
		e(reactReflex.ReflexProvider, {
			producer = self.producers.intro.transparency,
		}, {
			indicator = e(function(props)
				local producer = reactReflex.useProducer()
				local selected = reactReflex.useSelector(function(state)
					return state
				end)

				return e("Text", {
					anchor = { 0, 1 },
					position = { 0, 0, 1, 0 },
					size = { 0, 300, 0, 0 },
					autoSize = "y",
					text = `transparency: {string.format("%.3f", selected)}`,
				})
			end),
			intro = e(components.intro, {}),
		}),
	})
end

function UI:run()
	reactVkui.run(self.app, self.children, {
		step = function(dt) end,
	})
	self.app:destroy()
end

return UI
