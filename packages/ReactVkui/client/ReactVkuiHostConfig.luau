--!nonstrict
--[[
	ReactVkuiHostConfig - the "host config" tells the reconciler how to create / update / move / remove vkui widgets.
	Modelled on react-roblox's ReactRobloxHostConfig (Instances -> vkui widgets, Parent -> widget.parent / children).

	Host instance  = a vkui widget (ui.Frame(...), ui.Button(...), ...)
	Container      = a widget too, normally app.root (React only ever touches the children it created itself)
	Text instances = not supported, a string/number child is only allowed as the single child of a widget (-> `text`)
]]

local LuauPolyfill = require("@pkgs/LuauPolyfill")
local Object = LuauPolyfill.Object
local setTimeout = LuauPolyfill.setTimeout
local clearTimeout = LuauPolyfill.clearTimeout
local Shared = require("@pkgs/Shared")
local console = Shared.console

local ReactFeatureFlags = Shared.ReactFeatureFlags
local enableCreateEventHandleAPI = ReactFeatureFlags.enableCreateEventHandleAPI

local ComponentTree = require("./ReactVkuiComponentTree")
local precacheFiberNode = ComponentTree.precacheFiberNode
local uncacheFiberNode = ComponentTree.uncacheFiberNode
local updateFiberProps = ComponentTree.updateFiberProps

local VKuiProps = require("./ReactVkuiProps")

local exports = {}
Object.assign(exports, Shared.ReactFiberHostConfig.WithNoPersistence)

-- bindings found while creating an instance, attached in finalizeInitialChildren
local pendingBindings = setmetatable({}, { __mode = "k" })

-- puts `child` into parent.children before `before` (or at the end); moves it when it already has a parent
local function insertChild(parent, child, before)
	local old = child.parent
	if old ~= nil then
		local i = table.find(old.children, child)
		if i then
			table.remove(old.children, i)
		end
	end
	child.parent = parent
	local list = parent.children
	if before ~= nil then
		local index = table.find(list, before)
		if index then
			table.insert(list, index, child)
			return
		end
	end
	table.insert(list, child)
end

local function detach(child)
	local parent = child.parent
	if parent ~= nil then
		local i = table.find(parent.children, child)
		if i then
			table.remove(parent.children, i)
		end
		child.parent = nil
	end
end

local function recursivelyUncache(node)
	uncacheFiberNode(node)
	if node.children then
		for _, child in node.children do
			recursivelyUncache(child)
		end
	end
end

exports.getRootHostContext = function(_rootContainerInstance)
	return "vkui"
end

exports.getChildHostContext = function(parentHostContext, _type, _rootContainerInstance)
	return parentHostContext
end

exports.getPublicInstance = function(instance)
	return instance
end

exports.prepareForCommit = function(_containerInfo)
	if enableCreateEventHandleAPI then
		error("ReactVkui: enableCreateEventHandleAPI is not supported", 0)
	end
	return nil
end

exports.beforeActiveInstanceBlur = function() end
exports.afterActiveInstanceBlur = function() end
exports.resetAfterCommit = function(_containerInfo) end
local printed = false
exports.createInstance = function(type_, props, _rootContainerInstance, _hostContext, internalInstanceHandle)
	local widget, bindings = VKuiProps.create(_rootContainerInstance.gui.renderer.UIFW, type_, props)
	pendingBindings[widget] = bindings
	precacheFiberNode(internalInstanceHandle, widget)
	updateFiberProps(widget, props)
	return widget
end

exports.appendInitialChild = function(parentInstance, child)
	insertChild(parentInstance, child, nil)
end

-- the constructor already applied the props; this is the moment to hook up bindings
exports.finalizeInitialChildren = function(widget, type_, _props, _rootContainerInstance, _hostContext): boolean
	local bindings = pendingBindings[widget]
	if bindings ~= nil then
		pendingBindings[widget] = nil
		VKuiProps.attachBindings(widget, type_, bindings)
	end
	return false
end

-- same diff as react-roblox: a flat { key, value, key, value, ... } list of changed props (removed -> Object.None)
exports.prepareUpdate = function(_widget, _type, oldProps, newProps, _rootContainerInstance, _hostContext)
	local updatePayload = nil
	for propKey in oldProps do
		if newProps[propKey] ~= nil then
			continue
		end
		updatePayload = updatePayload or table.create(2)
		table.insert(updatePayload, propKey)
		table.insert(updatePayload, Object.None)
	end
	for propKey, nextProp in newProps do
		if nextProp == oldProps[propKey] then
			continue
		end
		updatePayload = updatePayload or table.create(2)
		table.insert(updatePayload, propKey)
		table.insert(updatePayload, nextProp)
	end
	return updatePayload
end

-- a single string / number child is handed to the widget as its `text` instead of becoming a child fiber
exports.shouldSetTextContent = function(type_, props): boolean
	return type_ ~= "ImageSelector" and VKuiProps.isTextChild(props.children)
end

exports.createTextInstance = function(text, _rootContainerInstance, _hostContext, _internalInstanceHandle)
	error(
		'ReactVkui: the text "'
			.. tostring(text)
			.. '" is not inside a widget that can hold it. Raw text is only allowed '
			.. 'as the single child of a widget, e.g. e("Text", nil, "hello"); otherwise use the `text` prop.',
		0
	)
end

exports.isPrimaryRenderer = true
exports.warnsIfNotActing = true
exports.scheduleTimeout = setTimeout
exports.cancelTimeout = clearTimeout
exports.noTimeout = -1

-- -------------------
--     Mutation
-- -------------------

exports.supportsMutation = true

exports.commitMount = function() end

exports.commitUpdate = function(widget, updatePayload, type_, oldProps, newProps, _internalInstanceHandle)
	updateFiberProps(widget, newProps)
	VKuiProps.update(widget, type_, updatePayload, oldProps)
end

exports.resetTextContent = function(widget)
	if widget.kind == "TextBox" then
		if widget.text ~= "" then
			widget:setText("")
		end
	else
		widget.text = nil
	end
end

exports.appendChild = function(parentInstance, child)
	insertChild(parentInstance, child, nil)
end

exports.appendChildToContainer = function(container, child)
	insertChild(container, child, nil)
end

exports.insertBefore = function(parentInstance, child, beforeChild)
	insertChild(parentInstance, child, beforeChild)
end

exports.insertInContainerBefore = function(container, child, beforeChild)
	insertChild(container, child, beforeChild)
end

exports.removeChild = function(_parentInstance, child)
	VKuiProps.cleanup(child)
	recursivelyUncache(child)
	detach(child)
end

exports.removeChildFromContainer = function(_container, child)
	exports.removeChild(_container, child)
end

-- Suspense / Offscreen hide the host nodes of a subtree instead of removing them
exports.hideInstance = function(widget)
	if widget._reactVisible == nil then
		widget._reactVisible = if widget.visible == nil then true else widget.visible
	end
	widget.visible = false
end

exports.unhideInstance = function(widget, props)
	widget._reactVisible = nil
	if props.visible ~= nil then
		widget.visible = props.visible
	else
		widget.visible = true
	end
end

exports.hideTextInstance = function() end
exports.unhideTextInstance = function() end

-- The container (app.root) can hold widgets that were not created by React, so nothing is cleared here. React only
-- calls this on the very first render of a root, when it has not created anything yet.
exports.clearContainer = function(_container) end

exports.preparePortalMount = function(_portalInstance) end

return exports
