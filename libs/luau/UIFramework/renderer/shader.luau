--[[
	shader.luau - load GLSL (.vert / .frag) or precompiled SPIR-V (.spv) files

	local shader = require("./shader")

	local spirv = shader.load("shaders/model.frag")             -- -> buffer of SPIR-V (compiled on the fly)
	local spirv, err = shader.compile(glslSource, "frag")       -- from a string; returns nil, err on failure
	shader.load("shaders/custom.vert", { cache = true })        -- also writes shaders/custom.vert.spv and reuses it while it is newer than the source

	`#include "other.glsl"` lines are expanded by this module (relative to the including file); error line numbers refer to the expanded text.

	Extensions: .vert / .frag (also .vs / .fs, .glsl needs `stage = "vert" | "frag"` in the options) are compiled; .spv is read as is.

	How it works: GLSL -> SPIR-V needs a compiler, and Vulkan itself only accepts SPIR-V. This module loads Google's shaderc
	library (shaderc_shared - it ships with the Vulkan SDK and most Linux packages: libshaderc / shaderc) through zune.ffi and calls
	shaderc_compile_into_spv. Call `shader.setLibraryPath("path/to/shaderc_shared.dll")` if it is not found automatically
	(the VULKAN_SDK environment variable is searched too). Without shaderc, .spv files and the built-in modules still work.

	Use it with the renderer:
		ui.createApp({ shaders = { libraryPath = "libs/shaderc_shared.dll", shaders = "path/to/shaders" } })    -- loads ui.vert ui.frag model.vert model.frag model_dither.frag
		ui.createApp({ shaders = { shaders = { modelFrag = "my/water.frag", modelVert = "my/model.vert" } } })  -- any subset, per file

]]

local ffi = zune.ffi
local T = ffi.types

-- Function definitions are plain tables in zune.ffi: { returns = type, args = { types } }
local function fn(returns: any, args: { any }): any
	return { returns = returns, args = args }
end

local KIND: { [string]: number } = { vert = 0, frag = 1 } -- shaderc_vertex_shader, shaderc_fragment_shader
local VULKAN_1_0 = 4194304 -- (1 << 22), shaderc_env_version_vulkan_1_0; Luau has no << operator
local STAGE_OF_EXT: { [string]: string } = { vert = "vert", vs = "vert", frag = "frag", fs = "frag" }

local ptr, u32, i32, u64, void = T.pointer, T.u32, T.i32, T.u64, T.void
local SIGNATURES: { [string]: any } = {
	shaderc_compiler_initialize = fn(ptr, {}),
	shaderc_compiler_release = fn(void, { ptr }),
	shaderc_compile_options_initialize = fn(ptr, {}),
	shaderc_compile_options_release = fn(void, { ptr }),
	shaderc_compile_options_set_target_env = fn(void, { ptr, u32, u32 }),
	shaderc_compile_options_set_optimization_level = fn(void, { ptr, u32 }),
	shaderc_compile_into_spv = fn(ptr, { ptr, ptr, u64, i32, ptr, ptr, ptr }),
	shaderc_result_release = fn(void, { ptr }),
	shaderc_result_get_length = fn(u32, { ptr }),
	shaderc_result_get_bytes = fn(ptr, { ptr }),
	shaderc_result_get_compilation_status = fn(i32, { ptr }),
	shaderc_result_get_error_message = fn(ptr, { ptr }),
}

local libraryPath: string? = nil

local lib: any = nil
local libError: string? = nil

local function openLibrary(): any
	return ffi.dlopen("./libs/bin/shaderc_shared.dll", SIGNATURES)
end

-- true when GLSL files can be compiled on this machine
local function available(): boolean
	return openLibrary() ~= nil
end

local function cstring(text: string): any
	return ffi.dupe(buffer.fromstring(text .. "\0"))
end

-- source: GLSL text; stage: "vert" | "frag"; name: only used in error messages
local function compile(source: string, stage: string, name: string?): (buffer?, string?)
	local kind = KIND[stage]
	if not kind then
		return nil, `shader: unknown stage "{stage}" (use "vert" or "frag")`
	end
	local L = openLibrary()
	if not L then
		return nil, libError
	end

	local compiler = L.shaderc_compiler_initialize()
	local options = L.shaderc_compile_options_initialize()
	L.shaderc_compile_options_set_target_env(options, 0, VULKAN_1_0) -- Vulkan 1.0
	L.shaderc_compile_options_set_optimization_level(options, 2) -- performance

	local src = buffer.fromstring(source)
	local srcPtr = ffi.dupe(src)
	local namePtr, entryPtr = cstring(name or "shader"), cstring("main")
	local result = L.shaderc_compile_into_spv(compiler, srcPtr, buffer.len(src), kind, namePtr, entryPtr, options)

	local out: buffer? = nil
	local err: string? = nil
	if L.shaderc_result_get_compilation_status(result) == 0 then
		local len = L.shaderc_result_get_length(result)
		local bytes = L.shaderc_result_get_bytes(result)
		local data = buffer.create(len)
		for i = 0, len // 4 - 1 do
			buffer.writeu32(data, i * 4, bytes:readu32(i * 4))
		end
		out = data
	else
		local msg = L.shaderc_result_get_error_message(result)
		local n = 0
		while n < 65536 and msg:readu8(n) ~= 0 do
			n += 1
		end
		local raw = buffer.create(n)
		for i = 0, n - 1 do
			buffer.writeu8(raw, i, msg:readu8(i))
		end
		err = `shader: {name or "shader"} failed to compile:\n` .. buffer.tostring(raw)
	end

	L.shaderc_result_release(result)
	L.shaderc_compile_options_release(options)
	L.shaderc_compiler_release(compiler)
	ffi.free(srcPtr)
	ffi.free(namePtr)
	ffi.free(entryPtr)
	return out, err
end

local function extension(path: string): string
	return string.lower(string.match(path, "%.([%w]+)$") or "")
end

-- Replaces `#include "file"` lines with the file's text (relative to the including file; GLSL has no include support of its own).
-- Every file read is appended to `deps` (the cache is stale when any of them is newer).
local function expand(path: string, deps: { string }, depth: number): string
	if depth > 8 then
		error(`shader: #include nesting too deep at {path}`, 0)
	end
	table.insert(deps, path)
	print(path)
	local source = zune.fs.readFileSync(path) :: string
	local dir = zune.fs.path.dirname(path) or "."
	local out: { string } = {}
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		local name = string.match(line, '^%s*#include%s+"([^"]+)"%s*$')
		if name then
			table.insert(out, expand(zune.fs.path.join(dir, name), deps, depth + 1))
		else
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

-- Reads a shader file and returns SPIR-V as a buffer. Raises an error with the compiler output when it fails.
-- options: stage (for .glsl or unusual extensions), cache (write/use "<path>.spv")
local function load(path: string, options: { stage: string?, cache: boolean? }?): buffer
	local o = options or {}
	local ext = extension(path)
	if ext == "spv" then
		return zune.fs.readFileSync(path, true) :: buffer
	end
	local stage = o.stage or STAGE_OF_EXT[ext]
	if not stage then
		error(`shader: cannot tell the stage of "{path}" - use .vert/.frag/.spv or pass options.stage`, 2)
	end

	local deps: { string } = {}
	local source = expand(path, deps, 0)

	local cachePath = path .. ".spv"
	if o.cache then
		local okC, cacheStat: any = pcall(zune.fs.metadata, cachePath)
		if okC then
			local fresh = true
			for _, dep in deps do
				local okD, depStat: any = pcall(zune.fs.metadata, dep)
				if not okD or depStat.modified_at > cacheStat.modified_at then
					fresh = false
					break
				end
			end
			if fresh then
				return zune.fs.readFileSync(cachePath, true) :: buffer
			end
		end
	end

	local spirv, err = compile(source, stage, path)
	if not spirv then
		error(err or "shader: compilation failed", 2)
	end
	if o.cache then
		pcall(zune.fs.writeFileSync, cachePath, spirv)
	end
	return spirv
end

local shader = {
	available = available,
	compile = compile,
	load = load,
	setLibraryPath = function(path: string?)
		libraryPath = path
		lib = nil
	end,
}

return shader
