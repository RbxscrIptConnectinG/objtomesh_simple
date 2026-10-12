local types = require("@self/types")
local createProducer = require("@self/createProducer")
local combineProducers = require("@self/combineProducers")
local createSelector = require("@self/createSelector")
local applyMiddleware = require("@self/applyMiddleware")

local loggerMiddleware = require("@self/middleware/loggerMiddleware")
local shallowEqual = require("@self/utils/shallowEqual")

export type Broadcaster = types.Broadcaster
export type BroadcastAction = types.BroadcastAction
export type BroadcasterOptions = types.BroadcasterOptions

export type BroadcastReceiver = types.BroadcastReceiver
export type BroadcastReceiverOptions = types.BroadcastReceiverOptions

export type Producer<State = any, Dispatchers = { [string]: (...any) -> State }> = types.Producer<State, Dispatchers>
export type Middleware = types.Middleware

return {
	createProducer = createProducer,
	combineProducers = combineProducers,
	createSelector = createSelector,
	applyMiddleware = applyMiddleware,
	loggerMiddleware = loggerMiddleware,
	shallowEqual = shallowEqual,
}
