local sift = require("@pkgs/Sift")
local net = zune.net
local serde = zune.serde

local NETWORK = {}
NETWORK.__index = NETWORK
NETWORK.__type = "NETWORK_HANDLER"

export type NETWORK<T...> = {
	defaultHeaders: {
		[string]: any,
	},
	APIs: {
		main: string,
	},
	requests: {
		[string]: {
			host: string,
			options: HttpRequestOptions,
			grab: { string },
		},
	},
}

NETWORK.defaultHeaders = {
	["Accept"] = "application/vnd.github+json",
	["X-GitHub-Api-Version"] = "2026-03-10",
}
NETWORK.APIs = {
	main = "https://api.github.com/repos/RbxscrIptConnectinG/objtomesh_simple",
}
NETWORK.requests = {
	stars = {
		host = `{NETWORK.APIs.main}/stargazers/count`,
		options = {
			method = "GET",
			headers = NETWORK.defaultHeaders,
		},
		grab = {
			"body",
			"@json5-decode",
			"count",
		},
	},
}

function NETWORK.processRequest<T...>(self: NETWORK<T...>, name: string)
	--
	local request = self.requests[name]

	local output = net.http.request(request.host, request.options)

	local grab = output
	for index = 1, #request.grab do
		local grabWhat = request.grab[index]

		if grabWhat == "@json5-decode" then
			grab = serde.json5.decode(grab)
			continue
		end

		grab = grab[grabWhat]
	end
	return grab
end

function NETWORK.new<T...>(): NETWORK<T...>
	local self = setmetatable({}, NETWORK)

	self.repo = {
		stars = self:processRequest("stars"),
	}

	return self
end

return NETWORK
