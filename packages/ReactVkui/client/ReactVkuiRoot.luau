--!nonstrict
-- Roots (based on react-roblox's ReactRobloxRoot). A container is any vkui widget, normally `app.root`.

local Shared = require("@pkgs/Shared")
local invariant = Shared.invariant

local ComponentTree = require("./ReactVkuiComponentTree")
local markContainerAsRoot = ComponentTree.markContainerAsRoot
local unmarkContainerAsRoot = ComponentTree.unmarkContainerAsRoot

local ReactFiberReconciler = require("../ReactReconciler.vkui")
local createContainer = ReactFiberReconciler.createContainer
local updateContainer = ReactFiberReconciler.updateContainer

local BlockingRoot = ReactFiberReconciler.ReactRootTags.BlockingRoot
local ConcurrentRoot = ReactFiberReconciler.ReactRootTags.ConcurrentRoot
local LegacyRoot = ReactFiberReconciler.ReactRootTags.LegacyRoot

local ReactVkuiRoot = {}
ReactVkuiRoot.__index = ReactVkuiRoot

local function createRootImpl(container, tag, options)
	local hydrate = options ~= nil and options.hydrate == true
	local hydrationCallbacks = if options ~= nil then options.hydrationOptions else nil
	local root = createContainer(container, tag, hydrate, hydrationCallbacks)
	markContainerAsRoot(root.current, container)
	return root
end

local function newRoot(container, tag, options)
	local root = setmetatable({}, ReactVkuiRoot)
	root._internalRoot = createRootImpl(container, tag, options)
	return root
end

function ReactVkuiRoot:render(children)
	updateContainer(children, self._internalRoot, nil)
end

function ReactVkuiRoot:unmount()
	local root = self._internalRoot
	local container = root.containerInfo
	updateContainer(nil, root, nil, function()
		unmarkContainerAsRoot(container)
	end)
end

local exports = {}

-- a widget: has a `children` list and an `add` method
local function isValidContainer(node): boolean
	return type(node) == "table" and type(node.children) == "table" and type(node.add) == "function"
end
exports.isValidContainer = isValidContainer

-- Concurrent root: renders are scheduled (they run while your app loop yields to Zune's scheduler).
exports.createRoot = function(container, options)
	invariant(
		isValidContainer(container),
		"createRoot(...): Target container is not a vkui widget (pass app.root or any widget)."
	)
	return newRoot(container, ConcurrentRoot, options)
end

exports.createBlockingRoot = function(container, options)
	invariant(isValidContainer(container), "createBlockingRoot(...): Target container is not a vkui widget.")
	return newRoot(container, BlockingRoot, options)
end

-- Legacy root: root:render() and setState outside of event batches render synchronously.
exports.createLegacyRoot = function(container, options)
	invariant(isValidContainer(container), "createLegacyRoot(...): Target container is not a vkui widget.")
	return newRoot(container, LegacyRoot, options)
end

return exports
