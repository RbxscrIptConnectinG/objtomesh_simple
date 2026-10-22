local sift = require("@pkgs/Sift")
local reflex = require("@pkgs/Reflex")

export type state = {
	intro: {
		ended: boolean,
		transparency: number,
	},
}
export type dispatchers = {
	setIntroTransparency: (number) -> state,
}

return reflex.createProducer({
	intro = {
		ended = false,
		transparency = 0,
	},
}, {
	setIntroTransparency = function(state: state, value: number)
		local nextState = sift.Dictionary.copyDeep(state)
		nextState.intro.transparency = math.clamp(value, 0, 3)

		nextState.intro.ended = nextState.intro.transparency >= 1

		return nextState
	end,
}) :: reflex.Producer<state, dispatchers>
