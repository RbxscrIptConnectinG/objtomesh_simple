--!nonstrict
--[[
	ReactVkuiProps - turns React props into vkui widget fields.

	Elements are the vkui widget kinds, `React.createElement("Button", props, children)`:
	Frame, Button, Image, ModelView, ScrollingFrame, Text, TextBox

	* every prop is the same field you would pass to ui.Button({ ... }) etc. (size, position, color, onClick, ...)
	* a string / number as the ONLY child becomes the `text` prop:   e("Text", nil, "Hello")
	* a prop set to nil goes back to the widget's default value
	* TextBox `text` is applied with widget:setText (so the caret is kept sensible and onChanged does not fire)
	* a React binding (React.createBinding) as a prop value updates that field without re-rendering
]]

local Shared = require("@pkgs/Shared")
local console = Shared.console
local ReactSymbols = Shared.ReactSymbols
local React = require("@pkgs/React")
local None = require("@pkgs/LuauPolyfill").Object.None

local exports = {}

local instanceToBindings = setmetatable({}, { __mode = "k" })

local function isBinding(v): boolean
	return type(v) == "table" and v["$$typeof"] == ReactSymbols.REACT_BINDING_TYPE
end

local function isTextChild(v): boolean
	return type(v) == "string" or type(v) == "number"
end
exports.isTextChild = isTextChild

-- one untouched widget per kind, used to find the default value of a prop that was removed

local function describe(kind: string, key: any): string
	return `<{kind}> prop "{tostring(key)}"`
end

local function setProp(widget, kind: string, key: string, value: any)
	if key == "text" then
		if kind == "TextBox" then
			local text = if value == nil then "" else tostring(value)
			if widget.text ~= text then
				widget:setText(text)
			end
		else
			widget.text = value
		end
	else
		widget[key] = value
	end
end

local function removeBinding(widget, key: string)
	local bindings = instanceToBindings[widget]
	if bindings ~= nil and bindings[key] ~= nil then
		bindings[key]()
		bindings[key] = nil
	end
end

local function attachBinding(widget, kind: string, key: string, binding)
	local function update(newValue)
		local ok, err = pcall(setProp, widget, kind, key, newValue)
		if not ok then
			local message = `ReactVkui: error updating binding for {describe(kind, key)}: {tostring(err)}`
			console.error(message)
			error(message, 0)
		end
	end
	local bindings = instanceToBindings[widget]
	if bindings == nil then
		bindings = {}
		instanceToBindings[widget] = bindings
	end
	bindings[key] = React.__subscribeToBinding(binding, update)
	update(binding:getValue())
end

-- props -> (props for the widget constructor, bindings to attach afterwards)
local function splitProps(kind: string, props)
	local clean, bindings = {}, nil
	for key, value in props do
		if key == "ref" or key == "children" then
			continue
		end
		if type(key) ~= "string" then
			error(
				`ReactVkui: {describe(kind, key)} - only string prop names are supported (React.Event / React.Change / React.Tag are Roblox-only)`,
				0
			)
		end
		if isBinding(value) then
			bindings = bindings or {}
			bindings[key] = value
		else
			clean[key] = value
		end
	end
	if isTextChild(props.children) then
		clean.text = tostring(props.children)
	end
	return clean, bindings
end

-- creates the widget; bindings are returned so the host config can attach them once the widget is complete
function exports.create(root, kind: string, props)
	local clean, bindings = splitProps(kind, props)
	local ok, widget = pcall(root[kind], clean)
	if not ok then
		error(`ReactVkui: could not create <{kind}>: {tostring(widget)}`, 0)
	end
	return widget, bindings
end

function exports.attachBindings(widget, kind: string, bindings)
	if bindings == nil then
		return
	end
	for key, binding in bindings do
		attachBinding(widget, kind, key, binding)
	end
end

local function applyProp(widget, kind: string, key: any, value: any, oldValue: any)
	if key == "ref" then
		return
	end
	if key == "children" then
		if isTextChild(value) then
			setProp(widget, kind, "text", tostring(value))
		elseif isTextChild(oldValue) then
			setProp(widget, kind, "text", "")
		end
		return
	end
	if type(key) ~= "string" then
		error(`only string prop names are supported, got {typeof(key)}`, 0)
	end
	if isBinding(oldValue) then
		removeBinding(widget, key)
	end
	if isBinding(value) then
		attachBinding(widget, kind, key, value)
	else
		setProp(widget, kind, key, value)
	end
end

-- updatePayload is the flat { key1, value1, key2, value2, ... } list built by diffProperties
function exports.update(widget, kind: string, updatePayload, lastProps)
	for i = 1, #updatePayload, 2 do
		local key = updatePayload[i]
		local value = updatePayload[i + 1]
		if value == None then
			value = nil
		end
		local ok, err = pcall(applyProp, widget, kind, key, value, lastProps[key])
		if not ok then
			local message = `ReactVkui: error updating {describe(kind, key)}: {tostring(err)}`
			console.error(message)
			error(message, 0)
		end
	end
end

-- disconnects the bindings of a widget and everything below it
function exports.cleanup(widget)
	local bindings = instanceToBindings[widget]
	if bindings ~= nil then
		for _, disconnect in bindings do
			disconnect()
		end
		instanceToBindings[widget] = nil
	end
	if widget.children then
		for _, child in widget.children do
			exports.cleanup(child)
		end
	end
end

return exports
