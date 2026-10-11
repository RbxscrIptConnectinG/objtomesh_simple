local fs = zune.fs

local UIFW = require("@libs/luau/UIFramework")

local react = require("@pkgs/React")
local reactVkui = require("@pkgs/ReactVkui")
local reactReflex = require("@pkgs/ReactReflex")

local win_popups = require("@libs/luau/WinLibs/popup")

local e = react.createElement

local components = {
	intro = require("../components/intro"),
}

local UI = {}
UI.__index = UI

function UI.new(root)
	local self = setmetatable({}, UI)

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
		font = "./assets/toMesh/fonts/cour/Courier New.ttf",
	})
	self.producers = {
		intro = require("../producers/intro"),
	}
	self.children = self:getRender()

	return self
end

function UI:getRender()
	local clickCount = 0
	return e("Frame", {
		size = { 1, 0, 1, 0 },
		color = { 0.08, 0.09, 0.11, 1 },
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
	}, {
		button = e("Button", {
			onClick = function()
				clickCount += 0.1
				self.producers.intro.transparency.set(clickCount)
			end,
		}),
		e(reactReflex.ReflexProvider, {
			producer = self.producers.intro.transparency,
		}, {
			intro = e(components.intro, {}),
		}),
	})
end

function UI:run()
	reactVkui.run(self.app, self.children)
	self.app:destroy()
end

return UI
