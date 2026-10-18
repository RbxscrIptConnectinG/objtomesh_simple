local fs = zune.fs

local UIFW = require("@libs/luau/UIFramework")

local react = require("@pkgs/React")
local reactVkui = require("@pkgs/ReactVkui")
local reactReflex = require("@pkgs/ReactReflex")
local reflex = require("@pkgs/Reflex")

local win_popups = require("@libs/luau/WinLibs/popup")

local types = require("@toMesh/types")

local theme = require("@toMesh/theme")

local e = react.createElement

local components = {
	intro = require("@toMesh/components/intro"),
	app = require("@toMesh/components/app"),
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
		height = 640 // 1.3,
		title = "ObjToMesh",
		glfwPath = "./libs/bin/glfw3.dll",
		resizable = true,
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
		main = require("../producers/main"),
	} :: { [any]: reflex.Producer<any, any> }
	self.children = self:getRender()
	self.runningTime = 0
	return self
end

function UI:getRender()
	return e("Frame", {
		size = { 1, 0, 1, 0 },
		color = theme.background,
		anchor = { 0.5, 0.5 },
		position = { 0.5, 0, 0.5, 0 },
		backgroundTransparency = 0,
	}, {

		provider = e(reactReflex.ReflexProvider, {
			producer = self.producers.main,
		}, {
			intro = e(components.intro, {}),
			provider = e(reactVkui.RendererProvider, {
				renderer = self.app.renderer,
				gui = self.app.gui,
			}, {
				app = e(components.app, {}),
			}),
		}),
	})
end

function UI:run()
	reactVkui.run(self.app, self.children, {
		step = function(dt)
			self.runningTime += dt
			local curstate = self.producers.main:getState()
			if not curstate.intro.ended and self.runningTime > 2 then
				local alpha = (self.runningTime - 2) / 1
				self.producers.main.setIntroTransparency(alpha)
			end
		end,
	})
	self.app:destroy()
end

return UI
