--!strict
local module = {}
module.__index = module

export type module<T...> = typeof(setmetatable({}, module)) & {
	new: () -> module<T...>,
	pack: <E>(self: module<T...>, E) -> { E },

	cool_value: number,
	gettingSomething: { number },
}

function module.new<T...>(): module<T...>
	local self = setmetatable({}, module) :: module<T...>
	self:init()
	print(self.cool_value)

	self.gettingSomething = self:pack(354545)

	return self
end

function module.init<T...>(self: module<T...>)
	self.cool_value = math.pi
end

function module.pack<E, T...>(self: module<T...>, ...: E): { E }
	return { ... }
end

return module
