--!nonstrict

local ReactVkui = require("@self/client/ReactVkui")

local M = {}
M.ReactVkui = ReactVkui

-- Renders `element` into an app (its root widget) or into any widget. Concurrent root by default: the work runs while the
-- app loop yields to Zune's scheduler. { legacy = true } renders synchronously instead (the UI exists right after mount()).

function M.mount(target: any, element: any, options: { legacy: boolean? }?): any
	local container = if target.root ~= nil then target.root else target
	local root = if options and options.legacy
		then ReactVkui.createLegacyRoot(container)
		else ReactVkui.createRoot(container)
	root:render(element)
	return root
end

-- options: step = function(dt) (see App:run), yield = (see App:run), legacy = boolean
function M.run(app: any, element: any, options: { step: any?, yield: any?, legacy: boolean? }?)
	local o = options or {}
	local root = M.mount(app, element, { legacy = o.legacy })
	app:run(o.step, if o.yield ~= nil then { yield = o.yield } else nil)
	return root
end

return M
