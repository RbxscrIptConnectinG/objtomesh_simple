--!nonstrict
--[[
	Promise (minimal re-implementation for react-vkui)

	react-reconciler only requires a Promise library for `act()` and for recognising thenables, and user code may want
	to use it for Suspense / lazy components. API (subset of evaera's Promise):

	Promise.new(function(resolve, reject, onCancel) end)
	Promise.resolve(...), Promise.reject(...), Promise.is(v), Promise.delay(seconds), Promise.all(list), Promise.defer(fn)
	promise:andThen(onResolve, onReject), :catch(fn), :finally(fn), :await() -> (ok, ...), :expect(), :getStatus(), :cancel()

	Callbacks run through zune.task.defer, so they never run synchronously inside andThen().
]]

local Promise = {}
Promise.__index = Promise
Promise.Status = { Started = "Started", Resolved = "Resolved", Rejected = "Rejected", Cancelled = "Cancelled" }

local function defer(fn, ...)
	zune.task.defer(fn, ...)
end

local function isPromise(v)
	return type(v) == "table" and getmetatable(v) == Promise
end

local function settle(self, status, values)
	if self._status ~= "Started" then
		return
	end
	self._status = status
	self._values = values
	local callbacks = self._callbacks
	self._callbacks = {}
	for _, cb in callbacks do
		defer(cb)
	end
end

local resolveWith

-- resolves `self` with a value that may itself be a promise / thenable
resolveWith = function(self, ...)
	local value = ...
	if select("#", ...) == 1 and type(value) == "table" and type(value.andThen) == "function" then
		local called = false
		local ok, err = pcall(value.andThen, value, function(...)
			if not called then
				called = true
				resolveWith(self, ...)
			end
		end, function(...)
			if not called then
				called = true
				settle(self, "Rejected", table.pack(...))
			end
		end)
		if not ok and not called then
			called = true
			settle(self, "Rejected", table.pack(err))
		end
		return
	end
	settle(self, "Resolved", table.pack(...))
end

function Promise.new(executor)
	local self = setmetatable({ _status = "Started", _callbacks = {}, _values = nil, _cancelHooks = {} }, Promise)
	if executor then
		local function onCancel(hook)
			if self._status == "Cancelled" then
				hook()
			else
				table.insert(self._cancelHooks, hook)
			end
			return self._status == "Cancelled"
		end
		local ok, err = pcall(executor, function(...)
			resolveWith(self, ...)
		end, function(...)
			settle(self, "Rejected", table.pack(...))
		end, onCancel)
		if not ok then
			settle(self, "Rejected", table.pack(err))
		end
	end
	return self
end

function Promise.resolve(...)
	local args = table.pack(...)
	return Promise.new(function(resolve)
		resolve(table.unpack(args, 1, args.n))
	end)
end

function Promise.reject(...)
	local args = table.pack(...)
	return Promise.new(function(_, reject)
		reject(table.unpack(args, 1, args.n))
	end)
end

function Promise.is(v)
	return isPromise(v)
end

function Promise.defer(fn)
	return Promise.new(function(resolve, reject)
		defer(function()
			local ok, res = pcall(fn, resolve, reject)
			if not ok then
				reject(res)
			end
		end)
	end)
end

function Promise.delay(seconds)
	return Promise.new(function(resolve)
		zune.task.delay(seconds or 0, function()
			resolve(seconds)
		end)
	end)
end

function Promise.all(list)
	return Promise.new(function(resolve, reject)
		local n = #list
		local results, done = {}, 0
		if n == 0 then
			return resolve(results)
		end
		for i, p in list do
			Promise.resolve(p):andThen(function(v)
				results[i] = v
				done += 1
				if done == n then
					resolve(results)
				end
			end, reject)
		end
	end)
end

function Promise:getStatus()
	return self._status
end

function Promise:andThen(onResolve, onReject)
	return Promise.new(function(resolve, reject)
		local function run()
			if self._status == "Resolved" then
				if onResolve then
					local res = table.pack(pcall(onResolve, table.unpack(self._values, 1, self._values.n)))
					if res[1] then
						resolve(table.unpack(res, 2, res.n))
					else
						reject(res[2])
					end
				else
					resolve(table.unpack(self._values, 1, self._values.n))
				end
			elseif self._status == "Rejected" then
				if onReject then
					local res = table.pack(pcall(onReject, table.unpack(self._values, 1, self._values.n)))
					if res[1] then
						resolve(table.unpack(res, 2, res.n))
					else
						reject(res[2])
					end
				else
					reject(table.unpack(self._values, 1, self._values.n))
				end
			end
		end
		if self._status == "Started" then
			table.insert(self._callbacks, run)
		elseif self._status ~= "Cancelled" then
			defer(run)
		end
	end)
end

function Promise:catch(onReject)
	return self:andThen(nil, onReject)
end

function Promise:finally(fn)
	return self:andThen(function(...)
		fn(Promise.Status.Resolved)
		return ...
	end, function(...)
		fn(Promise.Status.Rejected)
		error((...), 0)
	end)
end

function Promise:cancel()
	if self._status ~= "Started" then
		return
	end
	self._status = "Cancelled"
	for _, hook in self._cancelHooks do
		pcall(hook)
	end
end

-- yields the current thread until the promise settles; returns (true, ...values) or (false, ...reason)
function Promise:await()
	if self._status == "Started" then
		local thread = coroutine.running()
		table.insert(self._callbacks, function()
			zune.task.defer(thread)
		end)
		coroutine.yield()
	end
	if self._status == "Resolved" then
		return true, table.unpack(self._values, 1, self._values.n)
	elseif self._status == "Rejected" then
		return false, table.unpack(self._values, 1, self._values.n)
	end
	return false, "Promise was cancelled"
end

function Promise:expect()
	local res = table.pack(self:await())
	if not res[1] then
		error(res[2], 0)
	end
	return table.unpack(res, 2, res.n)
end

return Promise
