--[[
	fx.luau - effect shaders ("shaders" / "viewShaders" props): GLSL parsing, settings layout, pipeline cache.

	An effect is a GLSL file that defines ONE function (no #version, no main, no uniforms of your own):

		#pragma setting float intensity 0.5          // settings: type name default...
		#pragma setting color tint 1 0.8 0.6 1
		vec4 effect(vec2 uv) {                        // uv: 0..1 over the whole window, (0,0) = top-left
			return source(uv) * vec4(tint.rgb, 1.0) * intensity;
		}

	Provided to the shader:
		source(uv)    the element drawn so far (or the previous effect's output). PREMULTIPLIED alpha. Return premultiplied rgba too.
		previous(uv)  this effect's own output of the previous frame (premultiplied; transparent at first). Only costs memory if you use it.
		resolution    vec2, window size in pixels      time  float, seconds (sum of the dt given to gui:update)   dt  float
		mouse         vec2, mouse position in pixels   frame int, frame counter                                  pixelSize vec2 = 1 / resolution
		<settings>    every `#pragma setting` is a variable of that name

	Setting types: float, int, bool, vec2, vec3, vec4, color (= vec4). Defaults follow the name (vecN: N numbers; bool: 0/1/true/false).
	Values from Lua: number | boolean | { x, y, z, w } (arrays), e.g. shaders = { ["datamosh.glsl"] = { blockSize = 24 } }.
	Reserved keys in the settings table: enabled (false = skip), order (number, default 0; effects run by order, then by file name).
	All settings together must fit 96 bytes (std430 layout; vec3 takes 16).
]]

local shaderLoader = require("./shader")

local M = {}

local TYPES: { [string]: { n: number, size: number, align: number, glsl: string } } = {
	float = { n = 1, size = 4, align = 4, glsl = "float" },
	int = { n = 1, size = 4, align = 4, glsl = "int" },
	bool = { n = 1, size = 4, align = 4, glsl = "uint" },
	vec2 = { n = 2, size = 8, align = 8, glsl = "vec2" },
	vec3 = { n = 3, size = 12, align = 16, glsl = "vec3" },
	vec4 = { n = 4, size = 16, align = 16, glsl = "vec4" },
	color = { n = 4, size = 16, align = 16, glsl = "vec4" },
}

local RESERVED = { enabled = true, order = true }
local TAKEN = {
	resolution = true,
	time = true,
	dt = true,
	mouse = true,
	frame = true,
	pixelSize = true,
	source = true,
	previous = true,
	effect = true,
	main = true,
	fx = true,
}

M.PUSH_SIZE = 128
local SETTINGS_START = 32 -- builtins: resolution @0, time @8, dt @12, mouse @16, frame @24

local function parseValue(kind: string, tokens: { string }, first: number, where: string): any
	local t = TYPES[kind]
	if kind == "bool" then
		local tok = tokens[first]
		return tok == "1" or tok == "true"
	end
	local list = {}
	for i = 1, t.n do
		local tok = tokens[first + i - 1]
		local n = if tok then tonumber(tok) else nil
		if tok ~= nil and n == nil then
			error(`{where}: default "{tok}" is not a number`, 0)
		end
		list[i] = n or (if kind == "color" and i == 4 then 1 else 0)
	end
	if t.n == 1 then
		return list[1]
	end
	return list
end

-- Returns { settings = {{ name, kind, default, offset }}, body = text for the compiler, usesPrevious }
function M.parse(source: string, where: string): any
	local settings: { any } = {}
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, line in string.split(source, "\n") do
		local pragma = string.match(line, "^%s*#pragma%s+setting%s+(.-)%s*$")
		if pragma then
			pragma = string.gsub(pragma, "//.*$", "")
			local tokens = {}
			for tok in string.gmatch(pragma, "%S+") do
				table.insert(tokens, tok)
			end
			local kind, name = tokens[1], tokens[2]
			if not kind or not TYPES[kind] then
				error(`{where}: unknown setting type "{tostring(kind)}" (float int bool vec2 vec3 vec4 color)`, 0)
			end
			if not name or not string.match(name, "^[%a_][%w_]*$") or TAKEN[name] or RESERVED[name] or seen[name] then
				error(`{where}: bad or reserved setting name "{tostring(name)}"`, 0)
			end
			seen[name] = true
			table.insert(
				settings,
				{ name = name, kind = kind, default = parseValue(kind, tokens, 3, `{where} ({name})`) }
			)
			table.insert(out, "")
		elseif string.match(line, "^%s*#version") then
			table.insert(out, "")
		else
			table.insert(out, line)
		end
	end
	local offset = SETTINGS_START
	for _, s in settings do
		local t = TYPES[s.kind]
		offset = math.ceil(offset / t.align) * t.align
		s.offset = offset
		offset += t.size
	end
	if offset > M.PUSH_SIZE then
		error(`{where}: settings need {offset - SETTINGS_START} bytes, the limit is {M.PUSH_SIZE - SETTINGS_START}`, 0)
	end
	local body = table.concat(out, "\n")
	return { settings = settings, body = body, usesPrevious = string.find(body, "previous%s*%(") ~= nil }
end

local function prologue(settings: { any }): string
	local members, defines = {}, {}
	for _, s in settings do
		local t = TYPES[s.kind]
		table.insert(members, `{t.glsl} u_{s.name};`)
		table.insert(
			defines,
			if s.kind == "bool" then `#define {s.name} (fx.u_{s.name} != 0u)` else `#define {s.name} fx.u_{s.name}`
		)
	end
	return table.concat({
		"#version 450",
		"layout(set = 0, binding = 0) uniform sampler2D u_source;",
		"layout(set = 1, binding = 0) uniform sampler2D u_previous;",
		"layout(push_constant) uniform FX { vec2 u_resolution; float u_time; float u_dt; vec2 u_mouse; uint u_frame; float u_pad0; "
			.. table.concat(members, " ")
			.. " } fx;",
		"layout(location = 0) in vec2 vUV;",
		"layout(location = 0) out vec4 outColor;",
		"#define resolution fx.u_resolution",
		"#define time fx.u_time",
		"#define dt fx.u_dt",
		"#define mouse fx.u_mouse",
		"#define frame int(fx.u_frame)",
		"#define pixelSize (1.0 / fx.u_resolution)",
		table.concat(defines, "\n"),
		"vec4 source(vec2 uv) { return texture(u_source, uv); }",
		"vec4 previous(vec2 uv) { return texture(u_previous, uv); }",
		"vec4 effect(vec2 uv);",
		"void main() { outColor = effect(vUV); }",
		"#line 1",
		"",
	}, "\n")
end

-- Finds, compiles and caches an effect file. Search: the path as given, then each folder in renderer.fxDirs.
function M.load(renderer: any, path: string): any
	local cached = renderer.fxCache[path]
	if cached then
		return cached
	end
	local text: string? = nil
	local found: string = path
	local tried = { path }
	local candidates = { path }
	for _, dir in renderer.fxDirs do
		table.insert(candidates, zune.fs.path.join(dir, path))
	end
	for _, candidate in candidates do
		local ok, data = pcall(zune.fs.readFileSync, candidate, false)
		if ok and type(data) == "string" then
			text, found = data, candidate
			break
		end
		table.insert(tried, candidate)
	end
	if not text then
		error(`vkui shaders: cannot find effect shader "{path}" (looked in: {table.concat(candidates, ", ")})`, 0)
	end
	local parsed = M.parse(text, found)
	local spirv, err = shaderLoader.compile(prologue(parsed.settings) .. parsed.body, "frag", found)
	if not spirv then
		error(`vkui shaders: {err}`, 0)
	end
	local entry = {
		path = found,
		settings = parsed.settings,
		usesPrevious = parsed.usesPrevious,
		byName = {},
		pipeline = renderer:_createEffectPipeline(spirv),
		warned = {},
	}
	for _, s in parsed.settings do
		entry.byName[s.name] = s
	end
	renderer.fxCache[path] = entry
	return entry
end

-- shaders: { [file] = { setting = value, enabled = bool?, order = number? } } -> ordered list { { fx = entry, values = table } }
function M.build(renderer: any, shaders: any): { any }
	local list: { any } = {}
	if type(shaders) ~= "table" then
		return list
	end
	for path, values in shaders do
		if type(path) ~= "string" then
			error('vkui shaders: keys must be effect file names, e.g. shaders = { ["datamosh.glsl"] = { ... } }', 0)
		end
		local settings = if type(values) == "table" then values else {}
		if values ~= false and settings.enabled ~= false then
			table.insert(
				list,
				{ path = path, order = settings.order or 0, values = settings, fx = M.load(renderer, path) }
			)
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.path < b.path
	end)
	return list
end

-- Writes the settings of one effect into the push-constant buffer (builtins are written by the renderer).
function M.pack(buf: buffer, entry: any, values: { [string]: any })
	for key in values do
		if not entry.byName[key] and not RESERVED[key] and not entry.warned[key] then
			entry.warned[key] = true
			print(`vkui shaders: "{entry.path}" has no setting "{tostring(key)}"`)
		end
	end
	for _, s in entry.settings do
		local v = values[s.name]
		if v == nil then
			v = s.default
		end
		local off = s.offset
		if s.kind == "float" then
			buffer.writef32(buf, off, tonumber(v) or s.default)
		elseif s.kind == "int" then
			buffer.writei32(buf, off, math.floor(tonumber(v) or s.default))
		elseif s.kind == "bool" then
			buffer.writeu32(buf, off, if v == true or v == 1 then 1 else 0)
		else
			local n = TYPES[s.kind].n
			local d = s.default
			for i = 1, n do
				local c = if type(v) == "table" then v[i] else nil
				buffer.writef32(buf, off + (i - 1) * 4, c or d[i])
			end
		end
	end
end

return M
