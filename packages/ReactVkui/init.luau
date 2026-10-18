--!nonstrict

local ReactVkui = require("@self/client/ReactVkui")
local Context = require("@self/client/ReactVkuiContext")

local M = {}

-- Hooks / provider: the app's renderer and gui from any component, in any module (like reflex's useProducer).
--   local renderer = reactVKUI.useRenderer()
--   local model = React.useMemo(function() return renderer:createModel(obj.parse(text)) end, { renderer })
-- Textures and models live until the app closes, so create them once (useMemo / useState / module level), not on every render.
M.useRenderer = Context.useRenderer
M.useGui = Context.useGui
M.RendererProvider = Context.RendererProvider
M.VkuiContext = Context.VkuiContext

-- Renders `element` into an app (its root widget) or into any widget. Concurrent root by default: the work runs while the
-- app loop yields to Zune's scheduler. { legacy = true } renders synchronously instead (the UI exists right after mount()).
-- The element is wrapped in a RendererProvider so that useRenderer() / useGui() work below it. The renderer comes from the
-- app (target.gui.renderer); for a plain widget target it is taken from widget.gui when that is set, or from options.renderer /
-- options.gui. Returns a root with render(element) (also wrapped) and unmount().
function M.mount(target: any, element: any, options: { legacy: boolean?, renderer: any?, gui: any? }?): any
	local container = if target.root ~= nil then target.root else target
	local gui = (options and options.gui) or target.gui or container.gui
	local renderer = (options and options.renderer) or target.renderer or (if gui then gui.renderer else nil)
	local root = if options and options.legacy
		then ReactVkui.createLegacyRoot(container)
		else ReactVkui.createRoot(container)

	root:render(Context.wrap(element, renderer, gui))
	return {
		render = function(_self: any, el: any)
			root:render(Context.wrap(el, renderer, gui))
		end,
		unmount = function(_self: any)
			root:unmount()
		end,
		_root = root,
	}
end

-- options: step = function(dt) (see App:run), yield = (see App:run), legacy = boolean
function M.run(app: any, element: any, options: { step: any?, yield: any?, legacy: boolean? }?)
	local o = options or {}
	local root = M.mount(app, element, { legacy = o.legacy })
	app:run(o.step, if o.yield ~= nil then { yield = o.yield } else nil)
	return root
end

return M
