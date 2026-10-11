local react = require("@pkgs/Reflex")

return {
	transparency = react.createProducer(0, {
		set = function(state: number, number: number)
			return number
		end,
	}),
}
