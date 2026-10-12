--[=[
	Tests a selector function's memoization. If the selector function is not
	memoized, it will output a warning in Roblox Studio.
	@param selector The selector function to test.
	@param expectedValue The expected value of the selector function.
	@param ... The arguments to pass to the selector function.
	@returns Whether the test passed.
]=]
local function testSelector<T, U...>(selector: (U...) -> T, expectedValue: T, ...: U...)
	if selector(...) == expectedValue then
		return true
	end

	return false
end

return testSelector
