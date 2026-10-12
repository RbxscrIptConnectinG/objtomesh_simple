local react = require("@pkgs/Reflex")

return {
	transparency = react.createProducer(0, {
		add = function(state: number, number: number)
			local nextState = math.clamp(state + number, 0, 1)
			return nextState
		end,
		remove = function(state: number, number: number)
			local nextState = math.clamp(state - number, 0, 1)
			return nextState
		end,
		set = function(state: number, number: number)
			local nextState = math.clamp(number, 0, 1)
			return nextState
		end,
	}),
}
