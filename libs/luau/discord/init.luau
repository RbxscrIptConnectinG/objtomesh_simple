--!nonstrict
--[[
	discord.luau - Discord Rich Presence for Zune (v0.5.x), built on zune.ffi. No dependencies, no C compiler.

	local discord = require("./discord")

	local rpc = discord.new("123456789012345678")        -- your Application (client) ID from discord.com/developers
	rpc:on("ready", function(user) print("connected as", user.username) end)
	rpc:on("disconnected", function(reason) print("lost Discord:", reason) end)
	rpc:on("error", function(code, message) warn(code, message) end)

	rpc:setActivity({
		details = "Editing main.luau",
		state = "In the editor",
		startTimestamp = discord.now(),
		largeImage = "logo", largeText = "My app",          -- asset keys uploaded under Rich Presence > Art Assets
		smallImage = "luau", smallText = "Luau",
		buttons = { { label = "Website", url = "https://example.com" } },
	})

	rpc:run()            -- background loop (zune.task.spawn); OR call rpc:update() yourself every frame / every ~0.5 s
	...
	rpc:close()          -- clears the presence and disconnects

	How it talks to Discord
	  Discord listens on a local IPC endpoint: a unix socket `discord-ipc-0..9` (Linux/macOS, looked up in $XDG_RUNTIME_DIR, $TMPDIR, /tmp
	  and the Flatpak / Snap sub-folders) or the named pipe `\\.\pipe\discord-ipc-0..9` (Windows). Frames are
	  `u32 opcode | u32 length | JSON` (little-endian). libc / kernel32 are called directly through zune.ffi.
	  The Discord desktop client must be running; if it is not, the module keeps retrying (reconnectDelay) and re-sends the
	  last activity as soon as it connects, so you can set the activity before Discord is even started.

	Activity fields (all optional; Luau-style names, nil = leave out)
	  details, state                 text lines (2..128 bytes; longer is cut)
	  startTimestamp, endTimestamp   unix seconds -> "elapsed" / "left" counter (endTimestamp wins if both are set)
	  largeImage, largeText          asset key OR an https image URL, and its hover text
	  smallImage, smallText
	  partyId, partySize, partyMax   "(2 of 4)"
	  matchSecret, joinSecret, spectateSecret
	  buttons                        up to 2 of { label = string (<= 32), url = string (http/https) }
	  type                           "Playing" (default) | "Listening" | "Watching" | "Competing"
	  statusDisplayType              "Name" | "State" | "Details"   (what the member-list status line shows; newer Discord clients)
	  detailsUrl, stateUrl           make the text lines links (newer Discord clients)
	  instance                       boolean
	  raw                            table merged into the JSON activity as-is, for fields not listed here
]]

local ffi = zune.ffi
local T = ffi.types
local ptr, i32, u32, i64, u64 = T.pointer, T.i32, T.u32, T.i64, T.u64

local OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

export type Activity = {
	details: string?,
	state: string?,
	startTimestamp: number?,
	endTimestamp: number?,
	largeImage: string?,
	largeText: string?,
	smallImage: string?,
	smallText: string?,
	partyId: string?,
	partySize: number?,
	partyMax: number?,
	matchSecret: string?,
	joinSecret: string?,
	spectateSecret: string?,
	buttons: { { label: string, url: string } }?,
	type: string?,
	statusDisplayType: string?,
	detailsUrl: string?,
	stateUrl: string?,
	instance: boolean?,
	raw: { [string]: any }?,
}

export type Options = {
	reconnectDelay: number?, -- seconds between connection attempts while Discord is not reachable (default 5)
	minInterval: number?, -- minimum seconds between activity updates (default 4)
	pid: number?, -- process id shown to Discord (default: this process)
	autoReconnect: boolean?, -- default true
	debug: boolean?, -- print every frame sent / received
}

--------------------------------------------------------------------------
-- JSON (zune.serde.json)
-- Note: the Zune encoder writes an EMPTY table as `[]`, so never send an empty table where an object is expected.
--------------------------------------------------------------------------

local json = zune.serde.json5
local encode = json.encode
local decode = json.decode

--------------------------------------------------------------------------
-- Transports (the only OS-specific part)
--   open(index) -> boolean        try discord-ipc-<index>
--   read()      -> string | nil | false      bytes / nothing available right now / connection closed
--   write(s)    -> boolean
--   close()
--------------------------------------------------------------------------

local RECV_SIZE = 4096

-- zune.ffi returns 64-bit integers as 8-byte buffers
local function i64ToNumber(b: buffer): number
	return buffer.readi32(b, 4) * 4294967296 + buffer.readu32(b, 0)
end

-- copy n bytes out of native memory into a Lua string
local function nativeToString(p: any, n: number): string
	local out = buffer.create(n)
	p:read(0, out, 0, n)
	return buffer.tostring(out)
end

local function posixTransport(os: string): any
	local isLinux = os == "linux"
	-- poll()'s nfds_t is `unsigned long` on Linux and `unsigned int` on macOS / FreeBSD
	local nfds = if isLinux then u64 else u32
	local SIGNATURES = {
		socket = { returns = i32, args = { i32, i32, i32 } },
		connect = { returns = i32, args = { i32, ptr, u32 } },
		send = { returns = i64, args = { i32, ptr, u64, i32 } },
		recv = { returns = i64, args = { i32, ptr, u64, i32 } },
		poll = { returns = i32, args = { ptr, nfds, i32 } },
		close = { returns = i32, args = { i32 } },
		setsockopt = { returns = i32, args = { i32, i32, i32, ptr, u32 } },
		getuid = { returns = u32, args = {} },
	}
	local names = if os == "macos"
		then { "/usr/lib/libSystem.B.dylib", "libSystem.B.dylib", "libc.dylib" }
		elseif os == "freebsd" then { "libc.so.7" }
		else { "libc.so.6", "libc.so", "libc.musl-x86_64.so.1", "libc.musl-aarch64.so.1" }
	local libc: any = nil
	local last: any = nil
	for _, name in names do
		local ok, result = pcall(ffi.dlopen, name, SIGNATURES)
		if ok then
			libc = result
			break
		end
		last = result
	end
	if not libc then
		error("discord: could not load libc: " .. tostring(last), 0)
	end

	local isBSD = not isLinux
	local sockaddrSize = if isBSD then 106 else 110 -- sizeof(struct sockaddr_un)
	local maxPath = if isBSD then 103 else 107
	local sendFlags = if os == "macos" then 0 elseif os == "freebsd" then 0x20000 else 0x4000 -- MSG_NOSIGNAL (macOS uses SO_NOSIGPIPE below)
	local AF_UNIX, SOCK_STREAM = 1, 1
	local POLLIN = 1

	-- candidate directories, most likely first
	local function directories(): { string }
		local env = zune.process.env
		local bases = {}
		local function add(dir: string?)
			if dir and dir ~= "" then
				dir = string.gsub(dir, "/+$", "")
				if not table.find(bases, dir) then
					table.insert(bases, dir)
				end
			end
		end
		add(env.XDG_RUNTIME_DIR)
		add(env.TMPDIR)
		add(env.TMP)
		add(env.TEMP)
		local okUid, uid = pcall(libc.getuid)
		if okUid then
			add("/run/user/" .. uid)
		end
		add("/tmp")
		local out = {}
		for _, base in bases do
			for _, sub in
				{
					"",
					"/app/com.discordapp.Discord",
					"/app/com.discordapp.DiscordCanary",
					"/snap.discord",
					"/snap.discord-canary",
				}
			do
				table.insert(out, base .. sub)
			end
		end
		return out
	end

	local dirs: { string }? = nil
	local pfd = ffi.alloc(8, 8) -- struct pollfd { int fd; short events; short revents; }
	local rbuf = ffi.alloc(RECV_SIZE, 8)
	local one = ffi.alloc(8, 8)
	one:writei32(0, 1)
	local fd = -1
	local self = {}

	local function tryPath(path: string): boolean
		if #path > maxPath then
			return false
		end
		local s = libc.socket(AF_UNIX, SOCK_STREAM, 0)
		if s < 0 then
			return false
		end
		if os == "macos" then
			libc.setsockopt(s, 0xffff, 0x1022, one, 4) -- SOL_SOCKET, SO_NOSIGPIPE
		end
		local addr = buffer.create(sockaddrSize) -- passed as a buffer: Zune copies it for the call
		if isBSD then
			buffer.writeu8(addr, 0, sockaddrSize) -- sun_len
			buffer.writeu8(addr, 1, AF_UNIX)
		else
			buffer.writeu16(addr, 0, AF_UNIX)
		end
		buffer.writestring(addr, 2, path)
		if libc.connect(s, addr, sockaddrSize) ~= 0 then
			libc.close(s)
			return false
		end
		fd = s
		return true
	end

	function self.open(index: number): boolean
		if not dirs then
			dirs = directories()
		end
		for _, dir in dirs :: any do
			if tryPath(`{dir}/discord-ipc-{index}`) then
				return true
			end
		end
		return false
	end

	function self.read(): any
		if fd < 0 then
			return false
		end
		pfd:writei32(0, fd)
		pfd:writei16(4, POLLIN) -- events
		pfd:writei16(6, 0) -- revents
		local n = libc.poll(pfd, 1, 0)
		if n < 0 then
			return false
		elseif n == 0 then
			return nil
		end
		-- readable (or hung up): recv() will not block; 0 = peer closed
		local got = i64ToNumber(libc.recv(fd, rbuf, RECV_SIZE, 0))
		if got <= 0 then
			return false
		end
		return nativeToString(rbuf, got)
	end

	function self.write(data: string): boolean
		if fd < 0 then
			return false
		end
		local remaining = buffer.fromstring(data)
		while buffer.len(remaining) > 0 do
			local sent = i64ToNumber(libc.send(fd, remaining, buffer.len(remaining), sendFlags))
			if sent <= 0 then
				return false
			end
			if sent >= buffer.len(remaining) then
				break
			end
			local rest = buffer.create(buffer.len(remaining) - sent)
			buffer.copy(rest, 0, remaining, sent)
			remaining = rest
		end
		return true
	end

	function self.close()
		if fd >= 0 then
			libc.close(fd)
			fd = -1
		end
	end

	return self
end

local function windowsTransport(): any
	local SIGNATURES = {
		CreateFileA = { returns = i64, args = { ptr, u32, u32, ptr, u32, u32, ptr } }, -- HANDLE
		PeekNamedPipe = { returns = i32, args = { i64, ptr, u32, ptr, ptr, ptr } },
		ReadFile = { returns = i32, args = { i64, ptr, u32, ptr, ptr } },
		WriteFile = { returns = i32, args = { i64, ptr, u32, ptr, ptr } },
		CloseHandle = { returns = i32, args = { i64 } },
	}
	local ok, k32 = pcall(ffi.dlopen, "kernel32.dll", SIGNATURES)
	if not ok then
		error("discord: could not load kernel32.dll: " .. tostring(k32), 0)
	end

	local GENERIC_READ_WRITE = 0xC0000000
	local OPEN_EXISTING = 3
	local rbuf = ffi.alloc(RECV_SIZE, 8)
	local counter = ffi.alloc(8, 8) -- DWORD out-parameter
	local handle = 0
	local isOpen = false
	local self = {}

	function self.open(index: number): boolean
		-- the path is a Lua string: Zune passes it NUL-terminated
		local h = i64ToNumber(
			k32.CreateFileA(`\\\\.\\pipe\\discord-ipc-{index}`, GENERIC_READ_WRITE, 0, nil, OPEN_EXISTING, 0, nil)
		)
		if h == -1 or h == 0 then -- INVALID_HANDLE_VALUE
			return false
		end
		handle = h
		isOpen = true
		return true
	end

	function self.read(): any
		if not isOpen then
			return false
		end
		counter:writeu32(0, 0)
		if k32.PeekNamedPipe(handle, nil, 0, nil, counter, nil) == 0 then
			return false -- pipe broken / closed
		end
		local avail = counter:readu32(0)
		if avail == 0 then
			return nil
		end
		counter:writeu32(0, 0)
		if k32.ReadFile(handle, rbuf, math.min(avail, RECV_SIZE), counter, nil) == 0 then
			return false
		end
		local got = counter:readu32(0)
		if got == 0 then
			return nil
		end
		return nativeToString(rbuf, got)
	end

	function self.write(data: string): boolean
		if not isOpen then
			return false
		end
		counter:writeu32(0, 0)
		local r = k32.WriteFile(handle, buffer.fromstring(data), #data, counter, nil)
		return r ~= 0 and counter:readu32(0) == #data
	end

	function self.close()
		if isOpen then
			k32.CloseHandle(handle)
			isOpen = false
		end
	end

	return self
end

local function newTransport(): any
	if zune.platform.os == "windows" then
		return windowsTransport()
	end
	return posixTransport(zune.platform.os)
end

--------------------------------------------------------------------------
-- Framing
--------------------------------------------------------------------------

local function frame(op: number, payload: string): string
	local b = buffer.create(8)
	buffer.writeu32(b, 0, op)
	buffer.writeu32(b, 4, #payload)
	return buffer.tostring(b) .. payload
end

--------------------------------------------------------------------------
-- Activity -> Discord JSON
--------------------------------------------------------------------------

local ACTIVITY_TYPE = { playing = 0, listening = 2, watching = 3, competing = 5 }
local STATUS_DISPLAY = { name = 0, state = 1, details = 2 }

local function lookup(map: { [string]: number }, value: any, prop: string): number
	if type(value) == "number" then
		return value
	end
	local key = string.lower(tostring(value))
	local found = map[key]
	if found == nil then
		error(`discord: invalid {prop} '{tostring(value)}'`, 4)
	end
	return found
end

-- cut to `max` bytes without splitting a UTF-8 character
local function clip(s: any, max: number): string?
	if s == nil then
		return nil
	end
	s = tostring(s)
	if #s <= max then
		return s
	end
	local cut = max
	while cut > 0 do
		local byte = string.byte(s, cut + 1)
		if byte == nil or byte < 0x80 or byte >= 0xC0 then
			break
		end
		cut -= 1
	end
	return string.sub(s, 1, cut)
end

local function buildActivity(a: Activity): any
	local out: any = {}
	out.details = clip(a.details, 128)
	out.state = clip(a.state, 128)
	out.details_url = clip(a.detailsUrl, 512)
	out.state_url = clip(a.stateUrl, 512)

	if a.startTimestamp or a.endTimestamp then
		out.timestamps = {
			start = a.startTimestamp and math.floor(a.startTimestamp) or nil,
			["end"] = a.endTimestamp and math.floor(a.endTimestamp) or nil,
		}
	end

	if a.largeImage or a.largeText or a.smallImage or a.smallText then
		out.assets = {
			large_image = clip(a.largeImage, 256),
			large_text = clip(a.largeText, 128),
			small_image = clip(a.smallImage, 256),
			small_text = clip(a.smallText, 128),
		}
	end

	if a.partyId or a.partySize or a.partyMax then
		out.party = { id = clip(a.partyId, 128) }
		if a.partySize and a.partyMax then
			out.party.size = { math.floor(a.partySize), math.floor(a.partyMax) }
		end
	end

	if a.matchSecret or a.joinSecret or a.spectateSecret then
		out.secrets = {
			match = clip(a.matchSecret, 128),
			join = clip(a.joinSecret, 128),
			spectate = clip(a.spectateSecret, 128),
		}
	end

	if a.buttons and #a.buttons > 0 then
		if #a.buttons > 2 then
			error("discord: at most 2 buttons are allowed", 3)
		end
		local list = {}
		for _, bt in a.buttons do
			if type(bt) ~= "table" or not bt.label or not bt.url then
				error("discord: every button needs a label and a url", 3)
			end
			table.insert(list, { label = clip(bt.label, 32), url = clip(bt.url, 512) })
		end
		out.buttons = list
	end

	if a.type ~= nil then
		out.type = lookup(ACTIVITY_TYPE, a.type, "type")
	end
	if a.statusDisplayType ~= nil then
		out.status_display_type = lookup(STATUS_DISPLAY, a.statusDisplayType, "statusDisplayType")
	end
	if a.instance ~= nil then
		out.instance = a.instance
	end
	if a.raw then
		for k, v in a.raw do
			out[k] = v
		end
	end
	return out
end

--------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------

local Client = {}
Client.__index = Client

local discord = {}

-- current unix time in seconds, for startTimestamp / endTimestamp
function discord.now(): number
	return os.time()
end

function discord.new(clientId: string, options: Options?): any
	if type(clientId) ~= "string" or not string.match(clientId, "^%d+$") then
		error('discord.new: clientId must be the numeric Application ID as a string, e.g. "123456789012345678"', 2)
	end
	local opts = options or {}
	local self = setmetatable({
		clientId = clientId,
		reconnectDelay = opts.reconnectDelay or 5,
		minInterval = opts.minInterval or 4,
		autoReconnect = opts.autoReconnect ~= false,
		debug = opts.debug == true,
		pid = opts.pid or zune.process.pid(),
		state = "disconnected", -- "disconnected" | "handshaking" | "ready"
		user = nil,
		_transport = nil,
		_inbox = "",
		_listeners = {},
		_activity = nil, -- Activity table, or nil = no presence
		_dirty = false, -- activity needs (re)sending
		_lastSend = -math.huge,
		_lastSignature = nil,
		_nextConnect = 0,
		_nonce = 0,
		_runToken = 0,
		_closed = false,
	}, Client)
	return self
end

function Client:on(event: string, callback: (...any) -> ()): any
	if event ~= "ready" and event ~= "disconnected" and event ~= "error" then
		error("discord: unknown event '" .. tostring(event) .. "' (ready | disconnected | error)", 2)
	end
	local list = self._listeners[event]
	if not list then
		list = {}
		self._listeners[event] = list
	end
	table.insert(list, callback)
	return self
end

-- remove one listener (or all listeners of the event when callback is nil)
function Client:off(event: string, callback: ((...any) -> ())?): any
	if callback == nil then
		self._listeners[event] = nil
	else
		local list = self._listeners[event]
		local i = list and table.find(list, callback)
		if i then
			table.remove(list, i)
		end
	end
	return self
end

function Client:_emit(event: string, ...)
	local list = self._listeners[event]
	if list then
		for _, cb in table.clone(list) do
			local ok, err = pcall(cb, ...)
			if not ok then
				print("discord: '" .. event .. "' callback failed: " .. tostring(err))
			end
		end
	end
end

function Client:_log(...)
	if self.debug then
		print("[discord]", ...)
	end
end

function Client:_send(op: number, payload: any): boolean
	local transport = self._transport
	if not transport then
		return false
	end
	local json = if type(payload) == "string" then payload else encode(payload)
	self:_log(">", op, json)
	return transport.write(frame(op, json))
end

function Client:_drop(reason: string)
	if self._transport then
		self._transport.close()
		self._transport = nil
	end
	local wasConnected = self.state ~= "disconnected"
	self.state = "disconnected"
	self.user = nil
	self._inbox = ""
	self._nextConnect = os.clock() + self.reconnectDelay
	if wasConnected then
		self._dirty = self._activity ~= nil -- re-announce after reconnecting
		self._lastSignature = nil
		self:_emit("disconnected", reason)
	end
end

function Client:_connect(): boolean
	local ok, transport = pcall(newTransport)
	if not ok then
		self._nextConnect = os.clock() + self.reconnectDelay
		self:_emit("error", "TRANSPORT", tostring(transport))
		return false
	end
	for index = 0, 9 do
		if transport.open(index) then
			self._transport = transport
			self.state = "handshaking"
			self._inbox = ""
			if not self:_send(OP_HANDSHAKE, { v = 1, client_id = self.clientId }) then
				self:_drop("handshake could not be sent")
				return false
			end
			return true
		end
	end
	transport.close()
	self._nextConnect = os.clock() + self.reconnectDelay
	return false
end

function Client:_handle(op: number, text: string)
	self:_log("<", op, text)
	if op == OP_PING then
		self:_send(OP_PONG, text)
		return
	elseif op == OP_CLOSE then
		local ok, data = pcall(decode, text)
		local code = ok and type(data) == "table" and data.code or nil
		local message = ok and type(data) == "table" and data.message or text
		self:_emit("error", code or "CLOSED", message)
		self:_drop("Discord closed the connection: " .. tostring(message))
		return
	elseif op ~= OP_FRAME then
		return
	end
	local ok, data = pcall(decode, text)
	if not ok or type(data) ~= "table" then
		return
	end
	if data.evt == "READY" then
		self.state = "ready"
		self.user = data.data and data.data.user or {}
		self._dirty = self._activity ~= nil
		self:_emit("ready", self.user)
	elseif data.evt == "ERROR" then
		local d = data.data or {}
		self:_emit("error", d.code, d.message)
	end
end

-- Read and dispatch everything that has arrived.
function Client:_pump()
	local transport = self._transport
	while transport do
		local chunk = transport.read()
		if chunk == nil then
			break
		elseif chunk == false then
			self:_drop("connection closed")
			return
		end
		self._inbox ..= chunk
		-- complete frames
		while #self._inbox >= 8 do
			local header = buffer.fromstring(string.sub(self._inbox, 1, 8))
			local op, len = buffer.readu32(header, 0), buffer.readu32(header, 4)
			if len > 1048576 then
				self:_drop("protocol error (frame too large)")
				return
			end
			if #self._inbox < 8 + len then
				break
			end
			local body = string.sub(self._inbox, 9, 8 + len)
			self._inbox = string.sub(self._inbox, 9 + len)
			self:_handle(op, body)
			if self.state == "disconnected" then
				return
			end
		end
		transport = self._transport
	end
end

function Client:_sendActivity()
	self._nonce += 1
	local args: any = { pid = self.pid }
	if self._activity then
		local built = buildActivity(self._activity)
		if next(built) ~= nil then -- an empty table would be encoded as [] by zune.serde.json
			args.activity = built
		end
	end
	-- identical to what Discord already shows: do not spend rate limit on it
	local signature = encode(args)
	if signature == self._lastSignature then
		self._dirty = false
		return
	end
	self._lastSignature = signature
	local ok = self:_send(OP_FRAME, { cmd = "SET_ACTIVITY", args = args, nonce = tostring(self._nonce) })
	if ok then
		self._dirty = false
		self._lastSend = os.clock()
	else
		self:_drop("write failed")
	end
end

-- Non-blocking. Call every frame, or let run() do it. Connects, answers pings, reconnects, and sends the pending activity.
function Client:update()
	if self._closed then
		return
	end
	local now = os.clock()
	if self.state == "disconnected" then
		if self.autoReconnect or not self._everTried then
			if now >= self._nextConnect then
				self._everTried = true
				self:_connect()
			end
		end
	end
	if self._transport then
		self:_pump()
	end
	if self.state == "ready" and self._dirty and now - self._lastSend >= self.minInterval then
		self:_sendActivity()
	end
end

-- Connects once, right now, and waits up to `timeout` seconds (default 2) for Discord's READY.
-- Returns true when ready. Optional: update() / run() connect on their own.
function Client:connect(timeout: number?): boolean
	if self._closed then
		return false
	end
	local deadline = os.clock() + (timeout or 2)
	self._nextConnect = 0
	while os.clock() < deadline do
		self:update()
		if self.state == "ready" then
			return true
		end
		if self.state == "disconnected" and self._everTried and os.clock() < self._nextConnect then
			return false -- Discord is not reachable
		end
		zune.task.wait(0.05)
	end
	return self.state == "ready"
end

-- Set (or replace) the presence. Pass nil to clear it. Sent on the next update() once connected.
function Client:setActivity(activity: Activity?)
	if activity ~= nil then
		buildActivity(activity) -- validate now so mistakes are reported at the call site
	end
	self._activity = activity
	self._dirty = true
end

-- Merge fields into the current activity (keeps start time etc.). A field set to false is removed.
function Client:updateActivity(fields: Activity)
	local merged: any = {}
	for k, v in self._activity or {} do
		merged[k] = v
	end
	for k, v in fields do
		merged[k] = if v == false then nil else v
	end
	self:setActivity(merged)
end

function Client:clearActivity()
	self:setActivity(nil)
end

function Client:isReady(): boolean
	return self.state == "ready"
end

-- Starts a background loop that calls update() every `interval` seconds (default 0.5). Stop it with stop() or close().
function Client:run(interval: number?)
	self._runToken += 1
	local token = self._runToken
	local step = interval or 0.5
	zune.task.spawn(function()
		while self._runToken == token and not self._closed do
			local ok, err = pcall(self.update, self)
			if not ok then
				print("discord: update failed: " .. tostring(err))
			end
			zune.task.wait(step)
		end
	end)
end

function Client:stop()
	self._runToken += 1
end

-- Clears the presence, disconnects, and stops the background loop. The client cannot be reused afterwards.
function Client:close()
	self._runToken += 1
	if self.state == "ready" and self._transport then
		self._nonce += 1
		self:_send(OP_FRAME, { cmd = "SET_ACTIVITY", args = { pid = self.pid }, nonce = tostring(self._nonce) })
	end
	self._closed = true
	self._activity = nil
	if self._transport then
		self._transport.close()
		self._transport = nil
	end
	self.state = "disconnected"
end

discord.encode = encode -- exposed for debugging
discord.decode = decode

return discord
