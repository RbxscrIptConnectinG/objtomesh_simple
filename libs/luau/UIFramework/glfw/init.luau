--[[
	glfw.luau - GLFW 3.3+ bindings for Zune (v0.5.x), built on zune.ffi

	Usage:
		local glfw = require("./glfw")
		glfw.init()
		local window, err = glfw.createWindow(800, 600, "Hello")
		assert(window, err)
		glfw.run(window, function(dt) ... end)
		glfw.terminate()

	NOT TESTED against a real Zune install - written from the v0.5.0 FFI docs.
	Things I could not verify (each is isolated in one place, easy to patch):
	  * bare library names ("libglfw.so.3") resolving through the system loader
	  * `p == ffi.null` working on FFIPointer (see isNull)
	  * how long an ffi.closure lives (closures are kept referenced per window)

	Requirements: GLFW shared library >= 3.3 installed on the system.
	Run GLFW calls from the main Luau thread (not inside zune.thread).
]]

local ffi = zune.ffi
local T = ffi.types

local ptr, i32, u32, f64, void = T.pointer, T.i32, T.u32, T.double, T.void

export type Definition = { returns: any, args: { any } }

export type WindowOptions = {
	glVersion: { number }?, -- {major, minor}, default {3, 3}
	coreProfile: boolean?, -- default true (applied for GL >= 3.2)
	resizable: boolean?,
	visible: boolean?,
	decorated: boolean?,
	samples: number?, -- MSAA samples
	vsync: boolean?, -- default true
	makeCurrent: boolean?, -- default true
	hints: { [number]: number }?, -- raw GLFW hints, applied last
	noApi: boolean?, -- true = no OpenGL context (use with Vulkan)
}

local function fn(returns: any, args: { any }): Definition
	return { returns = returns, args = args }
end

--------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------

local Action = { Release = 0, Press = 1, Repeat = 2 }

local Mod = { Shift = 1, Control = 2, Alt = 4, Super = 8, CapsLock = 16, NumLock = 32 }

local MouseButton = { Left = 0, Right = 1, Middle = 2 }

local CursorMode = { Normal = 0x00034001, Hidden = 0x00034002, Disabled = 0x00034003 }
local INPUT_MODE_CURSOR = 0x00033001

local Hint = {
	Focused = 0x00020001,
	Resizable = 0x00020003,
	Visible = 0x00020004,
	Decorated = 0x00020005,
	AutoIconify = 0x00020006,
	Floating = 0x00020007,
	Maximized = 0x00020008,
	Samples = 0x0002100D,
	DoubleBuffer = 0x00021010,
	ClientApi = 0x00022001,
	ContextVersionMajor = 0x00022002,
	ContextVersionMinor = 0x00022003,
	OpenGLForwardCompat = 0x00022006,
	OpenGLDebugContext = 0x00022007,
	OpenGLProfile = 0x00022008,
}
local OPENGL_CORE_PROFILE = 0x00032001

local Key: { [string]: number } = {
	Space = 32,
	Apostrophe = 39,
	Comma = 44,
	Minus = 45,
	Period = 46,
	Slash = 47,
	Semicolon = 59,
	Equal = 61,
	LeftBracket = 91,
	Backslash = 92,
	RightBracket = 93,
	GraveAccent = 96,
	Escape = 256,
	Enter = 257,
	Tab = 258,
	Backspace = 259,
	Insert = 260,
	Delete = 261,
	Right = 262,
	Left = 263,
	Down = 264,
	Up = 265,
	PageUp = 266,
	PageDown = 267,
	Home = 268,
	End = 269,
	CapsLock = 280,
	ScrollLock = 281,
	NumLock = 282,
	PrintScreen = 283,
	Pause = 284,
	KeypadEnter = 335,
	LeftShift = 340,
	LeftControl = 341,
	LeftAlt = 342,
	LeftSuper = 343,
	RightShift = 344,
	RightControl = 345,
	RightAlt = 346,
	RightSuper = 347,
	Menu = 348,
}
for c = 65, 90 do -- Key.A .. Key.Z
	Key[string.char(c)] = c
end
for d = 0, 9 do -- Key.Digit0 .. Key.Digit9, Key.Keypad0 .. Key.Keypad9
	Key["Digit" .. d] = 48 + d
	Key["Keypad" .. d] = 320 + d
end
for f = 1, 12 do -- Key.F1 .. Key.F12
	Key["F" .. f] = 289 + f
end

local ERROR_NAMES: { [number]: string } = {
	[0x00010001] = "NOT_INITIALIZED",
	[0x00010002] = "NO_CURRENT_CONTEXT",
	[0x00010003] = "INVALID_ENUM",
	[0x00010004] = "INVALID_VALUE",
	[0x00010005] = "OUT_OF_MEMORY",
	[0x00010006] = "API_UNAVAILABLE",
	[0x00010007] = "VERSION_UNAVAILABLE",
	[0x00010008] = "PLATFORM_ERROR",
	[0x00010009] = "FORMAT_UNAVAILABLE",
	[0x0001000A] = "NO_WINDOW_CONTEXT",
}

--------------------------------------------------------------------------
-- Native function table
--------------------------------------------------------------------------

local SIGNATURES = {
	glfwInit = fn(i32, {}),
	glfwTerminate = fn(void, {}),
	glfwGetVersion = fn(void, { ptr, ptr, ptr }),
	glfwGetError = fn(i32, { ptr }),

	glfwDefaultWindowHints = fn(void, {}),
	glfwWindowHint = fn(void, { i32, i32 }),
	glfwCreateWindow = fn(ptr, { i32, i32, ptr, ptr, ptr }),
	glfwDestroyWindow = fn(void, { ptr }),
	glfwWindowShouldClose = fn(i32, { ptr }),
	glfwSetWindowShouldClose = fn(void, { ptr, i32 }),
	glfwSetWindowTitle = fn(void, { ptr, ptr }),
	glfwGetWindowSize = fn(void, { ptr, ptr, ptr }),
	glfwSetWindowSize = fn(void, { ptr, i32, i32 }),
	glfwGetFramebufferSize = fn(void, { ptr, ptr, ptr }),
	glfwShowWindow = fn(void, { ptr }),
	glfwHideWindow = fn(void, { ptr }),

	glfwMakeContextCurrent = fn(void, { ptr }),
	glfwSwapInterval = fn(void, { i32 }),
	glfwSwapBuffers = fn(void, { ptr }),
	glfwGetProcAddress = fn(ptr, { ptr }),

	glfwPollEvents = fn(void, {}),
	glfwWaitEvents = fn(void, {}),
	glfwWaitEventsTimeout = fn(void, { f64 }),
	glfwGetTime = fn(f64, {}),
	glfwSetTime = fn(void, { f64 }),

	glfwGetKey = fn(i32, { ptr, i32 }),
	glfwGetMouseButton = fn(i32, { ptr, i32 }),
	glfwGetCursorPos = fn(void, { ptr, ptr, ptr }),
	glfwSetInputMode = fn(void, { ptr, i32, i32 }),

	glfwSetKeyCallback = fn(ptr, { ptr, ptr }),
	glfwSetCharCallback = fn(ptr, { ptr, ptr }),
	glfwSetCursorPosCallback = fn(ptr, { ptr, ptr }),
	glfwSetMouseButtonCallback = fn(ptr, { ptr, ptr }),
	glfwSetScrollCallback = fn(ptr, { ptr, ptr }),
	glfwSetFramebufferSizeCallback = fn(ptr, { ptr, ptr }),
	glfwSetWindowSizeCallback = fn(ptr, { ptr, ptr }),
	glfwSetWindowCloseCallback = fn(ptr, { ptr, ptr }),
	glfwGetClipboardString = fn(ptr, { ptr }),
	glfwSetClipboardString = fn(void, { ptr, ptr }),

	-- Vulkan support
	glfwVulkanSupported = fn(i32, {}),
	glfwGetRequiredInstanceExtensions = fn(ptr, { ptr }),
	glfwCreateWindowSurface = fn(i32, { ptr, ptr, ptr, ptr }),
}

-- event name -> { setter function, C callback argument types (window pointer first) }
local CALLBACKS = {
	key = { setter = "glfwSetKeyCallback", args = { ptr, i32, i32, i32, i32 } }, -- win, key, scancode, action, mods
	char = { setter = "glfwSetCharCallback", args = { ptr, u32 } }, -- win, codepoint
	cursorPos = { setter = "glfwSetCursorPosCallback", args = { ptr, f64, f64 } }, -- win, x, y
	mouseButton = { setter = "glfwSetMouseButtonCallback", args = { ptr, i32, i32, i32 } }, -- win, button, action, mods
	scroll = { setter = "glfwSetScrollCallback", args = { ptr, f64, f64 } }, -- win, dx, dy
	framebufferSize = { setter = "glfwSetFramebufferSizeCallback", args = { ptr, i32, i32 } }, -- win, w, h
	windowSize = { setter = "glfwSetWindowSizeCallback", args = { ptr, i32, i32 } }, -- win, w, h
	close = { setter = "glfwSetWindowCloseCallback", args = { ptr } }, -- win
}

--------------------------------------------------------------------------
-- Library loading / state
--------------------------------------------------------------------------

local NOT_LOADED = setmetatable({}, {
	__index = function()
		error("glfw: not initialized, call glfw.init() first", 2)
	end,
})

local lib: any = NOT_LOADED
local initialized = false
local scratch: { any } = {} -- 3 x 8 bytes of native memory for out-parameters
local windows: { any } = {}
local pendingError: any = nil -- error thrown inside a callback, rethrown from pollEvents

local function openLibrary(custom: string?): any
	local candidates = if custom then { custom } else { "./libs/bin/glfw3.dll" }
	local lastError: any = nil
	for _, path in candidates do
		local ok, result = pcall(ffi.dlopen, path, SIGNATURES)
		if ok then
			return result
		end
		lastError = result
	end
	error(
		"glfw: could not load the GLFW library (need 3.3+). Tried: "
			.. table.concat(candidates, ", ")
			.. "\nLast error: "
			.. tostring(lastError)
			.. "\nPass an explicit path: glfw.init('/path/to/libglfw.so.3')",
		3
	)
end

-- Null check lives in one place because `==` on FFIPointer is unverified.
local function isNull(p: any): boolean
	return p == nil or p == ffi.null
end

-- Lua string -> freshly allocated NUL-terminated native string. Caller must ffi.free() it.
local function cstr(s: string): any
	return ffi.dupe(buffer.fromstring(s .. "\0"))
end

local function errorName(code: number): string
	return ERROR_NAMES[code] or string.format("UNKNOWN(0x%X)", code)
end

local function b(v: boolean): number
	return if v then 1 else 0
end

local function requireInit()
	if not initialized then
		error("glfw: not initialized, call glfw.init() first", 3)
	end
end

local function rethrowPending()
	if pendingError ~= nil then
		local e = pendingError
		pendingError = nil
		error(e, 0)
	end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window:shouldClose(): boolean
	return lib.glfwWindowShouldClose(self.handle) ~= 0
end

function Window:setShouldClose(value: boolean)
	lib.glfwSetWindowShouldClose(self.handle, b(value))
end

function Window:makeContextCurrent()
	lib.glfwMakeContextCurrent(self.handle)
end

function Window:swapBuffers()
	lib.glfwSwapBuffers(self.handle)
end

function Window:setTitle(title: string)
	local s = cstr(title)
	lib.glfwSetWindowTitle(self.handle, s)
	ffi.free(s)
end

function Window:getSize(): (number?, number?)
	lib.glfwGetWindowSize(self.handle, scratch[1], scratch[2])
	return scratch[1]:readi32(0), scratch[2]:readi32(0)
end

function Window:setSize(width: number, height: number)
	lib.glfwSetWindowSize(self.handle, width, height)
end

function Window:getFramebufferSize(): (number?, number?)
	lib.glfwGetFramebufferSize(self.handle, scratch[1], scratch[2])
	return scratch[1]:readi32(0), scratch[2]:readi32(0)
end

function Window:show()
	lib.glfwShowWindow(self.handle)
end

function Window:hide()
	lib.glfwHideWindow(self.handle)
end

-- Returns Action.Press / Release / Repeat
function Window:getKey(key: number): number
	return lib.glfwGetKey(self.handle, key)
end

function Window:isKeyDown(key: number): boolean
	return lib.glfwGetKey(self.handle, key) ~= Action.Release
end

function Window:isMouseDown(button: number): boolean
	return lib.glfwGetMouseButton(self.handle, button) == Action.Press
end

function Window:getCursorPos(): (number?, number?)
	lib.glfwGetCursorPos(self.handle, scratch[1], scratch[2])
	return scratch[1]:readf64(0), scratch[2]:readf64(0)
end

function Window:setCursorMode(mode: number)
	lib.glfwSetInputMode(self.handle, INPUT_MODE_CURSOR, mode)
end

-- Installs (once per event) the native callback that fans out to the primary handler and all listeners.
function Window:_refreshEvent(event: string)
	local spec = CALLBACKS[event]
	local h = self._handlers[event]
	local active = h ~= nil and (h.primary ~= nil or #h.list > 0)
	if not active then
		if self._callbacks[event] then
			lib[spec.setter](self.handle, ffi.null)
			self._callbacks[event] = nil
		end
		return
	end
	if self._callbacks[event] then
		return -- already installed; it dispatches dynamically
	end
	local win = self
	local function call(f: any, ...)
		local ok, err = pcall(f, win, ...)
		if not ok and pendingError == nil then
			pendingError = err
		end
	end
	local closure = ffi.closure(fn(void, spec.args), function(_, ...)
		local hs = win._handlers[event]
		if not hs then
			return
		end
		if hs.primary then
			call(hs.primary, ...)
		end
		for _, f in table.clone(hs.list) do
			call(f, ...)
		end
	end)
	self._callbacks[event] = closure -- keep the closure referenced
	lib[spec.setter](self.handle, closure)
end

local function handlersFor(self: any, event: string): any
	if not CALLBACKS[event] then
		error("glfw: unknown event '" .. tostring(event) .. "'", 3)
	end
	local h = self._handlers[event]
	if not h then
		h = { primary = nil, list = {} }
		self._handlers[event] = h
	end
	return h
end

--[[
	Register (or clear, with nil) the single primary handler of an event. The handler receives the
	Window first, then the event's values:
		key:             (win, key, scancode, action, mods)
		char:            (win, codepoint)
		cursorPos:       (win, x, y)
		mouseButton:     (win, button, action, mods)
		scroll:          (win, dx, dy)
		framebufferSize: (win, width, height)
		windowSize:      (win, width, height)
		close:           (win)
	Errors inside a handler are stored and rethrown from glfw.pollEvents().
	The UI toolkit uses connect() (below), so your own `on` handlers keep working next to it.
]]
function Window:on(event: string, handler: ((...any) -> ())?)
	handlersFor(self, event).primary = handler
	self:_refreshEvent(event)
end

-- Adds an extra listener (any number per event). Returns a function that removes it again.
function Window:connect(event: string, handler: (...any) -> ()): () -> ()
	local h = handlersFor(self, event)
	table.insert(h.list, handler)
	self:_refreshEvent(event)
	return function()
		local i = table.find(h.list, handler)
		if i then
			table.remove(h.list, i)
			self:_refreshEvent(event)
		end
	end
end

-- Clipboard text (nil when the clipboard holds no text).
function Window:getClipboard(): string?
	local p = lib.glfwGetClipboardString(self.handle)
	if p == nil or p == ffi.null then
		return nil
	end
	local n = 0
	while n < 4194304 and p:readu8(n) ~= 0 do
		n += 1
	end
	local b = buffer.create(n)
	for i = 0, n - 1 do
		buffer.writeu8(b, i, p:readu8(i))
	end
	return buffer.tostring(b)
end

function Window:setClipboard(str: string)
	local c = cstr(str)
	lib.glfwSetClipboardString(self.handle, c)
	ffi.free(c)
end

function Window:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	lib.glfwDestroyWindow(self.handle)
	self._callbacks = {}
	self._handlers = {}
	local i = table.find(windows, self)
	if i then
		table.remove(windows, i)
	end
end

--------------------------------------------------------------------------
-- Public module
--------------------------------------------------------------------------

local glfw = {
	Key = Key,
	Action = Action,
	Mod = Mod,
	MouseButton = MouseButton,
	CursorMode = CursorMode,
	Hint = Hint,
	types = T, -- re-export of zune.ffi.types
	fn = fn, -- fn(returns, args) -> function definition
}

-- Load the library and initialize GLFW. `libraryPath` overrides the search list.
function glfw.init(libraryPath: string?)
	if initialized then
		return
	end
	if lib == NOT_LOADED then
		lib = openLibrary(libraryPath)
	end
	if lib.glfwInit() ~= 1 then
		local _, name = glfw.getError()
		error("glfw: glfwInit failed (" .. name .. ")", 2)
	end
	scratch = { ffi.alloc(8, 8), ffi.alloc(8, 8), ffi.alloc(8, 8) }
	initialized = true
end

function glfw.terminate()
	if not initialized then
		return
	end
	for i = #windows, 1, -1 do
		windows[i]:destroy()
	end
	lib.glfwTerminate()
	for _, p in scratch do
		ffi.free(p)
	end
	scratch = {}
	initialized = false
end

-- Returns the last GLFW error code and its name (and clears it).
function glfw.getError(): (number?, string?)
	local code = lib.glfwGetError(ffi.null)
	return code, if code == 0 then "NO_ERROR" else errorName(code)
end

function glfw.getVersion(): (number?, number?, number?)
	requireInit()
	lib.glfwGetVersion(scratch[1], scratch[2], scratch[3])
	return scratch[1]:readi32(0), scratch[2]:readi32(0), scratch[3]:readi32(0)
end

-- Raw hint access, e.g. glfw.windowHint(glfw.Hint.Samples, 4)
function glfw.windowHint(hint: number, value: number)
	requireInit()
	lib.glfwWindowHint(hint, value)
end

-- Returns (window, nil) on success or (nil, errorMessage) on failure.
function glfw.createWindow(width: number, height: number, title: string, options: WindowOptions?): (any?, string?)
	requireInit()
	local o: WindowOptions = options or {}
	lib.glfwDefaultWindowHints()

	if o.noApi then
		lib.glfwWindowHint(Hint.ClientApi, 0) -- GLFW_NO_API
	else
		local major, minor = 3, 3
		if o.glVersion then
			major, minor = o.glVersion[1], o.glVersion[2]
		end
		lib.glfwWindowHint(Hint.ContextVersionMajor, major)
		lib.glfwWindowHint(Hint.ContextVersionMinor, minor)
		if o.coreProfile ~= false and (major > 3 or (major == 3 and minor >= 2)) then
			lib.glfwWindowHint(Hint.OpenGLProfile, OPENGL_CORE_PROFILE)
			lib.glfwWindowHint(Hint.OpenGLForwardCompat, 1) -- required on macOS
		end
	end

	if o.resizable ~= nil then
		lib.glfwWindowHint(Hint.Resizable, b(o.resizable))
	end
	if o.visible ~= nil then
		lib.glfwWindowHint(Hint.Visible, b(o.visible))
	end
	if o.decorated ~= nil then
		lib.glfwWindowHint(Hint.Decorated, b(o.decorated))
	end
	if o.samples ~= nil then
		lib.glfwWindowHint(Hint.Samples, o.samples)
	end
	if o.hints then
		for hint, value in o.hints do
			lib.glfwWindowHint(hint, value)
		end
	end

	lib.glfwGetError(ffi.null) -- clear stale errors; failure is detected via the error code
	local titlePtr = cstr(title)
	local handle = lib.glfwCreateWindow(width, height, titlePtr, ffi.null, ffi.null)
	ffi.free(titlePtr)

	local code = lib.glfwGetError(ffi.null)
	if code ~= 0 then
		return nil, "glfwCreateWindow failed: " .. errorName(code)
	end

	local window = setmetatable({
		handle = handle,
		_callbacks = {},
		_handlers = {},
		_destroyed = false,
	}, Window)
	table.insert(windows, window)

	if o.makeCurrent ~= false and not o.noApi then
		window:makeContextCurrent()
		lib.glfwSwapInterval(if o.vsync == false then 0 else 1)
	end

	return window, nil
end

-- Vulkan helpers ---------------------------------------------------------

function glfw.vulkanSupported(): boolean
	requireInit()
	return lib.glfwVulkanSupported() == 1
end

-- Returns (count, pointer-to-const-char*-array). Pass both straight into
-- VkInstanceCreateInfo (enabledExtensionCount / ppEnabledExtensionNames).
function glfw.getRequiredInstanceExtensions(): (number?, any?)
	requireInit()
	lib.glfwGetError(ffi.null)
	scratch[1]:writeu32(0, 0)
	local names = lib.glfwGetRequiredInstanceExtensions(scratch[1])
	return scratch[1]:readu32(0), names
end

-- Creates a VkSurfaceKHR for `window`. `outHandle` must be >= 8 bytes of native memory
-- (e.g. ffi.alloc(8, 8)). Returns the VkResult (0 = success); read the handle with outHandle:readptr(0).
function glfw.createWindowSurface(instance: any, window: any, outHandle: any): number
	requireInit()
	return lib.glfwCreateWindowSurface(instance, window.handle, ffi.null, outHandle)
end

function glfw.swapInterval(interval: number)
	requireInit()
	lib.glfwSwapInterval(interval)
end

function glfw.pollEvents()
	lib.glfwPollEvents()
	rethrowPending()
end

function glfw.waitEvents(timeoutSeconds: number?)
	if timeoutSeconds then
		lib.glfwWaitEventsTimeout(timeoutSeconds)
	else
		lib.glfwWaitEvents()
	end
	rethrowPending()
end

function glfw.getTime(): number
	return lib.glfwGetTime()
end

function glfw.setTime(seconds: number)
	lib.glfwSetTime(seconds)
end

-- Raw OpenGL function pointer (needs a current context).
function glfw.getProcAddress(name: string): any
	requireInit()
	local n = cstr(name)
	local p = lib.glfwGetProcAddress(n)
	ffi.free(n)
	return p
end

--[[
	Load OpenGL functions through GLFW (replaces glad/GLEW). Needs a current context.
		local gl = glfw.loadGL({
			glClear = glfw.fn(T.void, { T.u32 }),
		})
		gl.glClear(0x4000)
]]
function glfw.loadGL(defs: { [string]: Definition }): { [string]: any }
	requireInit()
	local out = {}
	for name, def in defs do
		lib.glfwGetError(ffi.null)
		local p = glfw.getProcAddress(name)
		local code = lib.glfwGetError(ffi.null)
		if code ~= 0 then
			error("glfw.loadGL('" .. name .. "'): " .. errorName(code) .. " (is a context current?)", 2)
		end
		if isNull(p) then
			error("glfw.loadGL: OpenGL function '" .. name .. "' is not available", 2)
		end
		out[name] = ffi.fn(def, p)
	end
	return out
end

--[[
	Simple main loop: step(dt, window) -> swapBuffers -> pollEvents, until the
	window should close. Pass `opts.yield` (e.g. a zune.task wait function - check
	the task docs for the exact call) to let other Zune async work run each frame.
]]
function glfw.run(window: any, step: (dt: number, window: any) -> (), opts: { yield: (() -> ())? }?)
	local yield = opts and opts.yield
	local last = glfw.getTime()
	while not window:shouldClose() do
		local now = glfw.getTime()
		local dt = now - last
		last = now
		step(dt, window)
		window:swapBuffers()
		glfw.pollEvents()
		if yield then
			yield()
		end
	end
end

export type Window = typeof(setmetatable(
	{} :: { handle: any, _callbacks: { [string]: any }, _destroyed: boolean },
	Window
))

return glfw
