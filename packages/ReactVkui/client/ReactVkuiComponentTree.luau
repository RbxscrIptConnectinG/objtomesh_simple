--!nonstrict
-- Bookkeeping that maps vkui widgets <-> React fibers (trimmed version of react-roblox's ReactRobloxComponentTree).

local Shared = require("@pkgs/Shared")
local invariant = Shared.invariant

local exports = {}

-- weak keys: a widget that nobody references anymore must not be kept alive by these maps
local weak = { __mode = "k" }
local containerToRoot = setmetatable({}, weak)
local instanceToFiber = setmetatable({}, weak)
local instanceToProps = setmetatable({}, weak)

local ReactWorkTags
local HostComponent, HostText, HostRoot, SuspenseComponent

exports.precacheFiberNode = function(fiber, node)
	instanceToFiber[node] = fiber
end

exports.uncacheFiberNode = function(node)
	instanceToFiber[node] = nil
	instanceToProps[node] = nil
end

exports.markContainerAsRoot = function(hostRoot, node)
	containerToRoot[node] = hostRoot
end

exports.unmarkContainerAsRoot = function(node)
	containerToRoot[node] = nil
end

exports.isContainerMarkedAsRoot = function(node): boolean
	return not not containerToRoot[node]
end

-- closest fiber of a widget or of one of its ancestors
exports.getClosestInstanceFromNode = function(targetNode)
	local node = targetNode
	while node ~= nil do
		local fiber = instanceToFiber[node]
		if fiber then
			return fiber
		end
		node = node.parent
	end
	return nil
end

exports.getInstanceFromNode = function(node)
	if ReactWorkTags == nil then
		ReactWorkTags = require("../ReactReconciler.vkui").ReactWorkTags
		HostComponent = ReactWorkTags.HostComponent
		HostText = ReactWorkTags.HostText
		HostRoot = ReactWorkTags.HostRoot
		SuspenseComponent = ReactWorkTags.SuspenseComponent
	end
	local inst = instanceToFiber[node] or containerToRoot[node]
	if inst then
		local tag = inst.tag
		if tag == HostComponent or tag == HostText or tag == SuspenseComponent or tag == HostRoot then
			return inst
		end
	end
	return nil
end

exports.getNodeFromInstance = function(inst)
	if ReactWorkTags == nil then
		exports.getInstanceFromNode({}) -- loads the tags
	end
	if inst.tag == HostComponent or inst.tag == HostText then
		return inst.stateNode
	end
	invariant(false, "getNodeFromInstance: Invalid argument.")
	error("getNodeFromInstance: Invalid argument.")
end

exports.getFiberCurrentPropsFromNode = function(node)
	return instanceToProps[node]
end

exports.updateFiberProps = function(node, props)
	instanceToProps[node] = props
end

return exports
