--!nonstrict
-- ReactVkui public api (based on react-roblox's ReactRoblox.lua)

local environment = require("@applibs/environment")
local Shared = require("@pkgs/Shared")
local invariant = Shared.invariant

local ReactVkuiRoot = require("./ReactVkuiRoot")
local isValidContainer = ReactVkuiRoot.isValidContainer

local ReactReconciler = require("../ReactReconciler.vkui")
local createPortalImpl = ReactReconciler.createPortal

local ComponentTree = require("./ReactVkuiComponentTree")

local ReactVersion = Shared.ReactVersion

local function createPortal(children, container, key)
	invariant(isValidContainer(container), "Target container is not a vkui widget.")
	return createPortalImpl(children, container, nil, key)
end

local exports = {
	createPortal = createPortal,
	unstable_batchedUpdates = ReactReconciler.batchedUpdates,
	flushSync = ReactReconciler.flushSync,
	version = ReactVersion,
	createRoot = ReactVkuiRoot.createRoot,
	createBlockingRoot = ReactVkuiRoot.createBlockingRoot,
	createLegacyRoot = ReactVkuiRoot.createLegacyRoot,
	isValidContainer = isValidContainer,
	__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED = {
		Events = {
			getInstanceFromNode = ComponentTree.getInstanceFromNode,
			getNodeFromInstance = ComponentTree.getNodeFromInstance,
			getFiberCurrentPropsFromNode = ComponentTree.getFiberCurrentPropsFromNode,
			flushPassiveEffects = ReactReconciler.flushPassiveEffects,
			IsThisRendererActing = ReactReconciler.IsThisRendererActing,
		},
	},
	act = function(_: () -> ()): ()
		error("ReactVkui.act is only available in test setups")
	end,
}

if environment.__ROACT_17_MOCK_SCHEDULER__ then
	exports.act = ReactReconciler.act
end

ReactReconciler.injectIntoDevTools({
	findFiberByHostInstance = ComponentTree.getClosestInstanceFromNode,
	bundleType = if environment.__DEV__ then 1 else 0,
	version = ReactVersion,
	rendererPackageName = "ReactVkui",
})

return exports
