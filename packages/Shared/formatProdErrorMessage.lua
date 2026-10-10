-- ROBLOX upstream: https://github.com/facebook/react/blob/75955bf1d7ff6c2c1f4052f4a84dd2ce6944c62e/packages/shared/formatProdErrorMessage.js
--!strict
--[[*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 ]]

-- Do not require this module directly! Use normal `invariant` calls with
-- template literal strings. The messages will be replaced with error codes
-- during build.

-- (Roblox's HttpService:UrlEncode, i.e. encodeURIComponent)
local function urlEncode(value)
	return (string.gsub(tostring(value), "[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function formatProdErrorMessage(code, ...)
	local url = "https://reactjs.org/docs/error-decoder.html?invariant=" .. tostring(code)
	local argsLength = select("#", ...)
	for i = 1, argsLength, 1 do
		-- deviation: UrlEncode should be equivalent to encodeURIComponent
		url = url .. "&args[]=" .. urlEncode((select(i, ...)))
	end
	return string.format(
		"Minified React error #%d; visit %s for the full message or "
			.. "use the non-minified dev environment for full errors and additional "
			.. "helpful warnings.",
		code,
		url
	)
end

return formatProdErrorMessage
