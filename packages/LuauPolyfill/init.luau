--!nonstrict
--[[
	LuauPolyfill (minimal re-implementation for react-vkui)

	The real @jsdotlua/luau-polyfill package is not part of the react-luau zip, so this file provides exactly
	the parts that react / react-reconciler / scheduler / shared / react-vkui use:

	Array, Object (+ Object.None), Error, Map, Set, WeakMap, Symbol, String, Number, Boolean, console,
	util.inspect, setTimeout, clearTimeout

	Semantics follow the real polyfill: Array helpers are 1-based, `Array.slice(t, a, b)` has an exclusive end,
	`Array.indexOf` returns -1 when missing.
]]

local polyfill = {}

----------------------------------------------------------------------------------------------------------------------
-- Object
----------------------------------------------------------------------------------------------------------------------

local None = setmetatable({}, {
	__tostring = function()
		return "Object.None"
	end,
})

local Object = { None = None }

function Object.keys(t)
	local out = {}
	if type(t) ~= "table" then
		return out
	end
	for k in t do
		out[#out + 1] = if type(k) == "string" then k else tostring(k)
	end
	return out
end

function Object.values(t)
	local out = {}
	for _, v in t do
		out[#out + 1] = v
	end
	return out
end

function Object.entries(t)
	local out = {}
	for k, v in t do
		out[#out + 1] = { k, v }
	end
	return out
end

function Object.assign(target, ...)
	for i = 1, select("#", ...) do
		local source = select(i, ...)
		if type(source) == "table" then
			for k, v in source do
				if v == None then
					target[k] = nil
				else
					target[k] = v
				end
			end
		end
	end
	return target
end

function Object.freeze(t)
	if type(t) == "table" and not table.isfrozen(t) then
		table.freeze(t)
	end
	return t
end

function Object.isFrozen(t)
	return type(t) ~= "table" or table.isfrozen(t)
end

-- Luau tables cannot be sealed / made non-extensible; these are accepted and ignored.
function Object.preventExtensions(t)
	return t
end
function Object.seal(t)
	return t
end

function Object.is(a, b)
	if a ~= a and b ~= b then
		return true
	end
	return a == b
end

function Object.getOwnPropertyDescriptor(t, key)
	local v = t[key]
	if v == nil then
		return nil
	end
	return { value = v, writable = true, enumerable = true, configurable = true }
end

function Object.defineProperty(t, key, descriptor)
	t[key] = descriptor.value
	return t
end

function Object.defineProperties(t, descriptors)
	for key, descriptor in descriptors do
		t[key] = descriptor.value
	end
	return t
end

polyfill.Object = Object

----------------------------------------------------------------------------------------------------------------------
-- Array (1-based)
----------------------------------------------------------------------------------------------------------------------

local Array = {}

function Array.isArray(value)
	if type(value) ~= "table" then
		return false
	end
	local count, max = 0, 0
	for k in value do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		count += 1
		if k > max then
			max = k
		end
	end
	return count == max
end

-- start is 1-based, `stop` is exclusive (so slice(t, 2) drops the first element)
function Array.slice(t, start, stop)
	local len = #t
	local a = start or 1
	local b = stop or len + 1
	if a < 0 then
		a = len + a + 1
	end
	if b < 0 then
		b = len + b + 1
	end
	if a < 1 then
		a = 1
	end
	if b > len + 1 then
		b = len + 1
	end
	local out = {}
	for i = a, b - 1 do
		out[#out + 1] = t[i]
	end
	return out
end

-- removes `deleteCount` items at 1-based `start`, inserts the extra args there, returns the removed items
function Array.splice(t, start, deleteCount, ...)
	local len = #t
	if start == nil then
		start = 1
	end
	if start < 1 then
		start = math.max(1, len + start + 1)
	end
	if start > len + 1 then
		start = len + 1
	end
	if deleteCount == nil then
		deleteCount = len - start + 1
	end
	deleteCount = math.max(0, math.min(deleteCount, len - start + 1))
	local removed = {}
	for _ = 1, deleteCount do
		removed[#removed + 1] = table.remove(t, start)
	end
	local n = select("#", ...)
	for i = n, 1, -1 do
		table.insert(t, start, (select(i, ...)))
	end
	return removed
end

function Array.map(t, fn)
	local out = table.create(#t)
	for i = 1, #t do
		out[i] = fn(t[i], i, t)
	end
	return out
end

function Array.filter(t, fn)
	local out = {}
	for i = 1, #t do
		if fn(t[i], i, t) then
			out[#out + 1] = t[i]
		end
	end
	return out
end

function Array.forEach(t, fn)
	for i = 1, #t do
		fn(t[i], i, t)
	end
end

function Array.join(t, sep)
	local parts = table.create(#t)
	for i = 1, #t do
		parts[i] = tostring(t[i])
	end
	return table.concat(parts, sep or ",")
end

function Array.indexOf(t, value, from)
	for i = from or 1, #t do
		if t[i] == value then
			return i
		end
	end
	return -1
end

function Array.includes(t, value)
	return Array.indexOf(t, value) ~= -1
end

function Array.concat(...)
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if Array.isArray(v) then
			for j = 1, #v do
				out[#out + 1] = v[j]
			end
		elseif v ~= nil then
			out[#out + 1] = v
		end
	end
	return out
end

function Array.from(value, mapFn)
	local out = {}
	if type(value) == "string" then
		for _, cp in utf8.codes(value) do
			out[#out + 1] = utf8.char(cp)
		end
	elseif type(value) == "table" then
		local mt = getmetatable(value)
		if mt and mt.__isCollection then
			value:forEach(function(v, k)
				out[#out + 1] = if mt.__isCollection == "map" then { k, v } else v
			end)
		else
			for _, v in value do
				out[#out + 1] = v
			end
		end
	end
	if mapFn then
		for i = 1, #out do
			out[i] = mapFn(out[i], i)
		end
	end
	return out
end

polyfill.Array = Array

----------------------------------------------------------------------------------------------------------------------
-- Boolean / Number / String
----------------------------------------------------------------------------------------------------------------------

polyfill.Boolean = {
	-- JS truthiness: nil/false/0/NaN/"" are falsy
	toJSBoolean = function(v)
		return not (v == nil or v == false or v == 0 or v ~= v or v == "")
	end,
}

polyfill.Number = {
	NaN = 0 / 0,
	MAX_SAFE_INTEGER = 9007199254740991,
	MIN_SAFE_INTEGER = -9007199254740991,
	isNaN = function(v)
		return v ~= v
	end,
	isFinite = function(v)
		return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
	end,
}

polyfill.String = {
	-- plain-text split; an empty separator splits into characters
	split = function(str, sep)
		local out = {}
		if sep == nil then
			return { str }
		end
		if sep == "" then
			for _, cp in utf8.codes(str) do
				out[#out + 1] = utf8.char(cp)
			end
			return out
		end
		local pos = 1
		while true do
			local a, b = string.find(str, sep, pos, true)
			if not a then
				out[#out + 1] = string.sub(str, pos)
				break
			end
			out[#out + 1] = string.sub(str, pos, a - 1)
			pos = b + 1
		end
		return out
	end,
	trim = function(str)
		return (string.gsub(str, "^%s*(.-)%s*$", "%1"))
	end,
}

----------------------------------------------------------------------------------------------------------------------
-- Symbol
----------------------------------------------------------------------------------------------------------------------

local symbolMeta = {
	__tostring = function(self)
		return "Symbol(" .. self.description .. ")"
	end,
}
local registry = {}
local Symbol = setmetatable({}, {
	__call = function(_, description)
		return setmetatable({ description = tostring(description or "") }, symbolMeta)
	end,
})
function Symbol.new(description)
	return setmetatable({ description = tostring(description or "") }, symbolMeta)
end
function Symbol.for_(key)
	local sym = registry[key]
	if sym == nil then
		sym = Symbol.new(key)
		registry[key] = sym
	end
	return sym
end
Symbol["for"] = Symbol.for_
Symbol.iterator = Symbol.new("Symbol.iterator")
Symbol.toStringTag = Symbol.new("Symbol.toStringTag")
polyfill.Symbol = Symbol

----------------------------------------------------------------------------------------------------------------------
-- Error
----------------------------------------------------------------------------------------------------------------------

local Error = {}
Error.__index = Error
Error.name = "Error"
Error.__tostring = function(self)
	if self.message ~= nil and self.message ~= "" then
		return tostring(self.name) .. ": " .. tostring(self.message)
	end
	return tostring(self.name)
end

function Error.new(message, _options)
	return setmetatable({
		message = if message == nil then "" else tostring(message),
		name = "Error",
		stack = debug.traceback(nil, 2),
	}, Error)
end

setmetatable(Error, {
	__call = function(_, message, options)
		return Error.new(message, options)
	end,
})
polyfill.Error = Error

----------------------------------------------------------------------------------------------------------------------
-- Map / Set / WeakMap
----------------------------------------------------------------------------------------------------------------------

local Map = {}
Map.__index = Map
Map.__isCollection = "map"

function Map.new(entries)
	local self = setmetatable({ size = 0, _keys = {}, _vals = {}, _idx = {} }, Map)
	if entries ~= nil then
		for _, pair in entries do
			self:set(pair[1], pair[2])
		end
	end
	return self
end

function Map:has(key)
	return self._idx[key] ~= nil
end

function Map:get(key)
	local i = self._idx[key]
	if i == nil then
		return nil
	end
	return self._vals[i]
end

function Map:set(key, value)
	local i = self._idx[key]
	if i == nil then
		i = #self._keys + 1
		self._keys[i] = key
		self._idx[key] = i
		self.size += 1
	end
	self._vals[i] = value
	return self
end

function Map:delete(key)
	local i = self._idx[key]
	if i == nil then
		return false
	end
	table.remove(self._keys, i)
	table.remove(self._vals, i)
	self._idx[key] = nil
	for j = i, #self._keys do
		self._idx[self._keys[j]] = j
	end
	self.size -= 1
	return true
end

function Map:clear()
	self._keys, self._vals, self._idx, self.size = {}, {}, {}, 0
end

-- callback(value, key, map), like JS
function Map:forEach(fn)
	local keys, vals = table.clone(self._keys), table.clone(self._vals)
	for i = 1, #keys do
		fn(vals[i], keys[i], self)
	end
end

function Map:keys()
	return table.clone(self._keys)
end
function Map:values()
	return table.clone(self._vals)
end

local Set = {}
Set.__index = Set
Set.__isCollection = "set"

function Set.new(values)
	local self = setmetatable({ size = 0, _vals = {}, _idx = {} }, Set)
	if values ~= nil then
		if getmetatable(values) == Set then
			for _, v in values._vals do
				self:add(v)
			end
		else
			for _, v in values do
				self:add(v)
			end
		end
	end
	return self
end

function Set:has(value)
	return self._idx[value] ~= nil
end

function Set:add(value)
	if self._idx[value] == nil then
		local i = #self._vals + 1
		self._vals[i] = value
		self._idx[value] = i
		self.size += 1
	end
	return self
end

function Set:delete(value)
	local i = self._idx[value]
	if i == nil then
		return false
	end
	table.remove(self._vals, i)
	self._idx[value] = nil
	for j = i, #self._vals do
		self._idx[self._vals[j]] = j
	end
	self.size -= 1
	return true
end

function Set:clear()
	self._vals, self._idx, self.size = {}, {}, 0
end

function Set:forEach(fn)
	local vals = table.clone(self._vals)
	for i = 1, #vals do
		fn(vals[i], vals[i], self)
	end
end

function Set:values()
	return table.clone(self._vals)
end

-- `for _, v in set do` walks the values in insertion order
Set.__iter = function(self)
	local vals = table.clone(self._vals)
	local i = 0
	return function()
		i += 1
		if i <= #vals then
			return i, vals[i]
		end
		return nil
	end
end

local WeakMap = {}
WeakMap.__index = WeakMap

function WeakMap.new()
	return setmetatable({ _data = setmetatable({}, { __mode = "k" }) }, WeakMap)
end
function WeakMap:get(key)
	return self._data[key]
end
function WeakMap:set(key, value)
	self._data[key] = value
	return self
end
function WeakMap:has(key)
	return self._data[key] ~= nil
end
function WeakMap:delete(key)
	local had = self._data[key] ~= nil
	self._data[key] = nil
	return had
end

polyfill.Map, polyfill.Set, polyfill.WeakMap = Map, Set, WeakMap

----------------------------------------------------------------------------------------------------------------------
-- util.inspect
----------------------------------------------------------------------------------------------------------------------

local function inspect(value, options)
	local maxDepth = (options and options.depth) or 2
	local seen = {}

	local function go(v, depth, indent)
		local t = type(v)
		if t == "string" then
			return if depth == 0 then v else string.format("%q", v)
		elseif t ~= "table" then
			return tostring(v)
		end
		local mt = getmetatable(v)
		if mt and mt.__tostring then
			return tostring(v)
		end
		if seen[v] then
			return "[Circular]"
		end
		if depth >= maxDepth + 1 then
			return "[Object]"
		end
		seen[v] = true
		local parts = {}
		local pad = indent .. "  "
		if Array.isArray(v) and next(v) ~= nil then
			for i = 1, #v do
				parts[#parts + 1] = pad .. go(v[i], depth + 1, pad)
			end
		else
			local keys = {}
			for k in v do
				keys[#keys + 1] = k
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in keys do
				local keyStr = if type(k) == "string" then k else "[" .. tostring(k) .. "]"
				parts[#parts + 1] = pad .. keyStr .. ": " .. go(v[k], depth + 1, pad)
			end
		end
		seen[v] = nil
		if #parts == 0 then
			return "{}"
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
	end

	return go(value, 0, "")
end

polyfill.util = { inspect = inspect }

----------------------------------------------------------------------------------------------------------------------
-- console
----------------------------------------------------------------------------------------------------------------------

-- "%s" style formatting; falls back to joining the arguments when the format does not fit them
local function format(fmt, ...)
	local n = select("#", ...)
	if type(fmt) ~= "string" then
		local parts = { type(fmt) == "table" and inspect(fmt) or tostring(fmt) }
		for i = 1, n do
			local a = select(i, ...)
			parts[#parts + 1] = if type(a) == "string" then a else inspect(a)
		end
		return table.concat(parts, " ")
	end
	if n == 0 then
		return fmt
	end
	local args = table.pack(...)
	for i = 1, n do
		local a = args[i]
		if type(a) ~= "number" and type(a) ~= "string" then
			args[i] = if type(a) == "table" and not (getmetatable(a) and getmetatable(a).__tostring)
				then inspect(a)
				else tostring(a)
		end
	end
	local ok, out = pcall(string.format, fmt, table.unpack(args, 1, n))
	if ok then
		return out
	end
	local parts = { fmt }
	for i = 1, n do
		parts[#parts + 1] = tostring(args[i])
	end
	return table.concat(parts, " ")
end

local console = {}
function console.log(...)
	print(format(...))
end
console.info = console.log
console.debug = console.log
function console.warn(...)
	print("[warn] " .. format(...))
end
function console.error(...)
	print("[error] " .. format(...))
end
polyfill.console = console

----------------------------------------------------------------------------------------------------------------------
-- timers (Zune scheduler)
----------------------------------------------------------------------------------------------------------------------

-- setTimeout(callback, delayMs, ...) -> handle ; the handle is the sleeping thread
function polyfill.setTimeout(callback, delayMs, ...)
	return zune.task.delay((delayMs or 0) / 1000, callback, ...)
end

function polyfill.clearTimeout(handle)
	if handle ~= nil and type(handle) == "thread" then
		pcall(zune.task.cancel, handle)
	end
end

export type Object = any
export type Array<T> = any

return polyfill
