--!nonstrict
--[[
	ReactVkuiContext - gives components access to the app's renderer / gui, like reflex's ReflexProvider + useProducer.

	local renderer = ReactVkui.useRenderer()          -- inside any component
	local model = React.useMemo(function() return renderer:createModel(...) end, { renderer })

	mount() / run() wrap your element in <RendererProvider> for you. For a root you create yourself:
	ReactVkui.createRoot(widget):render(e(ReactVkui.RendererProvider, { renderer = renderer, gui = gui }, tree))
]]

local React = require("@pkgs/React")

local VkuiContext = React.createContext(nil)

-- props: renderer, gui (optional), children
local function RendererProvider(props)
	-- one stable value per renderer / gui pair, so consumers only re-render when those change
	local value = React.useMemo(function()
		return { renderer = props.renderer, gui = props.gui }
	end, { props.renderer, props.gui })
	return React.createElement(VkuiContext.Provider, { value = value }, props.children)
end

-- The Renderer of the app this component tree was mounted into.
local function useRenderer()
	local value = React.useContext(VkuiContext)
	if value == nil or value.renderer == nil then
		error(
			"ReactVkui.useRenderer(): no renderer in this tree - mount it with ReactVkui.mount / ReactVkui.run "
				.. "(for a plain widget target pass { renderer = app.renderer }), or wrap it in <RendererProvider renderer=...>",
			2
		)
	end
	return value.renderer
end

-- The GUI object of the app (nil if none was provided).
local function useGui()
	local value = React.useContext(VkuiContext)
	if value == nil then
		error("ReactVkui.useGui(): no GUI in this tree - mount it with ReactVkui.mount / ReactVkui.run or wrap it in <RendererProvider>", 2)
	end
	return value.gui
end

-- element -> element wrapped in the provider (unchanged when there is neither a renderer nor a gui)
local function wrap(element, renderer, gui)
	if renderer == nil and gui == nil then
		return element
	end
	return React.createElement(RendererProvider, { renderer = renderer, gui = gui }, element)
end

return {
	VkuiContext = VkuiContext,
	RendererProvider = RendererProvider,
	useRenderer = useRenderer,
	useGui = useGui,
	wrap = wrap,
}
