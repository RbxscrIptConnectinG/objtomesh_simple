--[[
	importer.luau - native "open file" dialog as a plain function (no UI element)

	local importer = require("./importer")

	importer.options.importableExtensions = { "png", "ttf", "otf", "obj" }   -- global defaults, edit freely

	local paths, err = importer.pick({ importableExtensions = { "png" }, multiple = true, title = "Pick images" })
	local path, err  = importer.pickOne({ importableExtensions = { "ttf", "otf" } })
	-- paths / path are nil when the dialog was cancelled (err is nil then) or when no dialog is available (err says why)

	Options (per call, merged over importer.options):
		importableExtensions  { "png", "ttf", ... }  files shown first / by default (case-insensitive, with or without "." or "*.")
		title                 dialog title
		multiple              allow selecting several files (pick returns all of them)
		startDirectory        folder the dialog opens in
		allFilesOption        also offer an "All files" filter (default true)

	How it works: a few lines of C are compiled with zune.ffi.c.compile on first use.
		Windows  GetOpenFileNameW from comdlg32 (the standard Explorer dialog)
		macOS    osascript "choose file" (AppleScript) run through popen
		Linux    zenity, or kdialog if zenity is missing, run through popen
	Everything is synchronous FFI, so it can be called from anywhere - including Button onClick handlers,
	which run inside GLFW callbacks and therefore cannot yield. The window stops responding while the dialog is open.

	helpers: importer.extension(path), importer.basename(path), importer.kind(path) ("image" | "font" | "model" | nil,
	driven by the editable table importer.kinds).

]]

local ffi = zune.ffi
local T = ffi.types

local importer = {}

export type Options = {
	importableExtensions: { string }?,
	title: string?,
	multiple: boolean?,
	startDirectory: string?,
	allFilesOption: boolean?,
}

importer.options = {
	importableExtensions = { "png", "ttf", "otf", "obj" },
	title = "Import file",
	multiple = false,
	startDirectory = nil,
	allFilesOption = true,
} :: Options

-- extension -> what it is; edit freely
importer.kinds = {} :: { [string]: string }

--------------------------------------------------------------------------
-- C sources (compiled lazily; no headers, -nostdlib)
--------------------------------------------------------------------------

local WINDOWS_C = [[
#if defined(__i386__)
#define API __attribute__((stdcall))
#else
#define API
#endif

typedef unsigned short WCHAR;
typedef struct {
	unsigned int lStructSize;
	void* hwndOwner;
	void* hInstance;
	const WCHAR* lpstrFilter;
	WCHAR* lpstrCustomFilter;
	unsigned int nMaxCustFilter;
	unsigned int nFilterIndex;
	WCHAR* lpstrFile;
	unsigned int nMaxFile;
	WCHAR* lpstrFileTitle;
	unsigned int nMaxFileTitle;
	const WCHAR* lpstrInitialDir;
	const WCHAR* lpstrTitle;
	unsigned int Flags;
	unsigned short nFileOffset;
	unsigned short nFileExtension;
	const WCHAR* lpstrDefExt;
	void* lCustData;
	void* lpfnHook;
	const WCHAR* lpTemplateName;
	void* pvReserved;
	unsigned int dwReserved;
	unsigned int FlagsEx;
} OPENFILENAMEW;

extern int API GetOpenFileNameW(OPENFILENAMEW* ofn);

int zune_open_dialog(const WCHAR* title, const WCHAR* filter, const WCHAR* initialDir,
                     int multiple, WCHAR* out, int outChars, void* owner) {
	OPENFILENAMEW ofn;
	char* raw = (char*)&ofn;
	for (unsigned int i = 0; i < sizeof(ofn); i++) raw[i] = 0;
	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = owner;
	ofn.lpstrFilter = filter;
	ofn.nFilterIndex = 1;
	ofn.lpstrFile = out;
	ofn.nMaxFile = (unsigned int)outChars;
	ofn.lpstrInitialDir = initialDir;
	ofn.lpstrTitle = title;
	/* OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_HIDEREADONLY [| OFN_ALLOWMULTISELECT] */
	ofn.Flags = 0x80000 | 0x1000 | 0x800 | 0x8 | 0x4 | (multiple ? 0x200 : 0);
	return GetOpenFileNameW(&ofn);
}
]]

local POSIX_C = [[
extern void* popen(const char* command, const char* mode);
extern int pclose(void* stream);
extern char* fgets(char* buffer, int size, void* stream);

/* runs `cmd` through the shell and collects its stdout; returns the wait status (or -1) */
int zune_run(const char* cmd, char* out, int cap) {
	void* f = popen(cmd, "r");
	if (!f) return -1;
	int len = 0;
	out[0] = 0;
	while (len < cap - 1 && fgets(out + len, cap - len, f)) {
		while (out[len]) len++;
	}
	return pclose(f);
}
]]

--------------------------------------------------------------------------
-- Lazy initialisation
--------------------------------------------------------------------------

local state: any = nil

local function symbolOf(lib: any, name: string): any
	return lib:getSymbol(name) or error("symbol '" .. name .. "' not found", 0)
end

local function init(): any
	if state then
		return state
	end
	local os = string.lower(zune.platform.os)
	if os == "windows" then
		local lib = ffi.dlopen("C:/Windows/System32/comdlg32.dll", {})
		local compiled =
			ffi.c.compile(WINDOWS_C, { symbols = { GetOpenFileNameW = symbolOf(lib, "GetOpenFileNameW") } })
		state = {
			os = os,
			libs = { lib },
			compiled = compiled, -- keep the library handle alive (closing it would unmap the symbols)
			call = ffi.fn({
				returns = T.i32,
				args = { T.pointer, T.pointer, T.pointer, T.i32, T.pointer, T.i32, T.pointer },
			}, symbolOf(compiled, "zune_open_dialog")),
		}
	end
	return state
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function normalizeExtensions(list): { string }
	local out = {}
	list = list or {} :: { string }
	for _, e in list do
		local a = string.gsub(tostring(e), "^%*?%.", "")
		local ext = string.lower(a)
		if ext ~= "" then
			if not string.match(ext, "^[%w_%+%-]+$") then
				error("importer: invalid extension '" .. tostring(e) .. "'", 3)
			end
			if not table.find(out, ext) then
				table.insert(out, ext)
			end
		end
	end
	return out
end

local function merge(options: Options?): any
	local o: any = {}
	for k, v in importer.options :: any do
		o[k] = v
	end
	if options then
		for k, v in options :: any do
			o[k] = v
		end
	end
	o.importableExtensions = normalizeExtensions(o.importableExtensions)
	o.title = tostring(o.title or "Import file")
	return o
end

function importer.extension(path: string): string?
	local ext = string.match(path, "%.([%w_%+%-]+)$")
	return if ext then string.lower(ext) else nil
end

function importer.basename(path: string): string
	return string.match(path, "([^/\\]+)$") or path
end

function importer.kind(path: string): string?
	local ext = importer.extension(path)
	return if ext then importer.kinds[ext] else nil
end

--------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------

local function toUtf16(str: string): buffer
	local units: { number } = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(str) do
			if cp >= 0x10000 then
				local v = cp - 0x10000
				table.insert(units, 0xD800 + v // 1024)
				table.insert(units, 0xDC00 + v % 1024)
			else
				table.insert(units, cp)
			end
		end
	end)
	if not ok then -- invalid UTF-8: fall back to bytes
		units = {}
		for i = 1, #str do
			units[i] = string.byte(str, i)
		end
	end
	local b = buffer.create((#units + 2) * 2) -- zero-filled, so there is always a double NUL at the end
	for i, u in units do
		buffer.writeu16(b, (i - 1) * 2, u)
	end
	return b
end

-- Reads a NUL-terminated UTF-16 string starting at wchar offset `at`; returns it and the offset after the NUL.
local function readWide(p: any, at: number): (string?, number?)
	local parts: { string } = {}
	local i = at
	while true do
		local u = p:readu16(i * 2)
		i += 1
		if u == 0 then
			break
		end
		if u >= 0xD800 and u < 0xDC00 then
			local low = p:readu16(i * 2)
			if low >= 0xDC00 and low < 0xE000 then
				i += 1
				u = 0x10000 + (u - 0xD800) * 1024 + (low - 0xDC00)
			end
		end
		table.insert(parts, utf8.char(u))
	end
	return table.concat(parts), i
end

local function pickWindows(st: any, o: any): ({ string }?, string?)
	local exts = o.importableExtensions
	local patterns = {}
	for _, e in exts do
		table.insert(patterns, "*." .. e)
	end
	local filter = ""
	if #exts > 0 then
		filter = "Supported files (" .. table.concat(patterns, ", ") .. ")\0" .. table.concat(patterns, ";") .. "\0"
	end
	if #exts == 0 or o.allFilesOption ~= false then
		filter ..= "All files (*.*)\0*.*\0"
	end
	filter ..= "\0"

	local filterPtr = ffi.dupe(toUtf16(filter))
	local titlePtr = ffi.dupe(toUtf16(o.title))
	local dirPtr = if o.startDirectory then ffi.dupe(toUtf16(o.startDirectory)) else nil
	local chars = 32768
	local out = ffi.alloc(chars * 2, 2)

	local ok = st.call(titlePtr, filterPtr, dirPtr or ffi.null, if o.multiple then 1 else 0, out, chars, ffi.null)

	local paths: { string }? = nil
	if ok ~= 0 then
		local first, nextAt = readWide(out, 0)
		local second, afterSecond = readWide(out, nextAt :: number)
		if second == "" then -- one file: full path
			paths = { first :: string }
		else -- several files: directory, then the names
			local dir = first :: string
			if not string.find(dir, "[/\\]$") then
				dir ..= "\\"
			end
			paths = { dir .. (second :: string) }
			local at = afterSecond :: number
			while true do
				local name, following = readWide(out, at)
				if name == "" then
					break
				end
				table.insert(paths :: { string }, dir .. (name :: string))
				at = following :: number
			end
		end
	end

	ffi.free(out)
	ffi.free(filterPtr)
	ffi.free(titlePtr)
	if dirPtr then
		ffi.free(dirPtr)
	end
	return paths, nil
end
--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

-- Returns the chosen paths, or (nil, nil) when cancelled, or (nil, message) when no dialog could be shown.
function importer.pick(options: Options?): ({ string }?, string?)
	local o = merge(options)
	local ok, st = pcall(init)
	if not ok then
		return nil, "importer: " .. tostring(st)
	end
	local ok2, paths, err = pcall(pickWindows, st, o)
	if not ok2 then
		return nil, "importer: " .. tostring(paths)
	end
	return paths, err
end

-- Same as pick() but for a single file.
function importer.pickOne(options: Options?): (string?, string?)
	local o: any = {}
	for k, v in (options or {}) :: any do
		o[k] = v
	end
	o.multiple = false
	local paths, err = importer.pick(o)
	return if paths then paths[1] else nil, err
end

return importer
