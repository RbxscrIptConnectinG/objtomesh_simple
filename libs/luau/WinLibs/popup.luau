--[[
	popup.luau - Windows pop-up dialogs as plain functions (VBScript MsgBox / JS alert style, plus custom buttons)

	local popup = require("./popup")

	-- 1) VBScript-compatible MsgBox: the same numbers (16 critical, 32 question, 48 exclamation, 64 information,
	--    buttons 0..5, default button 256/512/768, ...) and the same return codes. Native Windows message box.
	local code = popup.msgBox("Disk is almost full", 48)                          -- MsgBox "Disk is almost full", 48
	local code = popup.msgBox("Delete it?", popup.vb.YesNo + popup.vb.Question, "Confirm")
	if code == popup.vb.Yes then ... end

	-- 2) Quick helpers
	popup.alert("Hello")                          -- OK only, no icon
	popup.alert("Saved", "My app", "info")       -- optional title and icon: "info" | "warning" | "error" | "question"
	if popup.confirm("Quit without saving?") then ... end          -- OK / Cancel -> boolean
	local name = popup.input("Your name:", "Welcome", "Player 1")  -- InputBox; nil when cancelled

	-- 3) Fully custom dialog with your own buttons
	local index, label = popup.show({
		title = "Unsaved changes",
		text = "Do you want to save your changes before closing?",
		icon = "warning",                         -- "none" (default) | "info" | "warning" | "error" | "question" | "shield"
		buttons = { "&Save", "Do&n't save", "Cancel" },   -- any number of buttons, any text (& marks the Alt shortcut letter)
		default = 1,                              -- button that has focus / reacts to Enter
		cancel = 3,                               -- button index returned for Esc and the window's X (0 / nil result when not set)
		topmost = false, sound = true,            -- always on top; play the system sound of the icon
		owner = app.window,                       -- glfw window (or raw HWND pointer): the dialog is modal to it and centred on it
		maxWidth = 480,                           -- text wraps at this many pixels (at 96 dpi)
	})
	-- index: 1-based number of the button that was pressed, label: its text (without the & marker)

	-- show() with an input field: input = true | "default text", password = true to mask it. Third result is the typed text.
	local index, label, text = popup.show({ text = "Server address", buttons = { "Connect", "Cancel" }, cancel = 2, input = "localhost" })

	How it works
		msgBox / alert / confirm call MessageBoxW from user32.dll through zune.ffi.
		show / input use a small dialog written in C that is compiled with zune.ffi.c.compile on first use (like importer.luau).
		It builds a standard-looking dialog (Segoe UI, system icons, white message area and grey button bar) with raw Win32 calls and
		runs its own modal message loop, so it is synchronous: the call returns when a button was pressed. That also makes it safe
		inside GLFW callbacks (e.g. Button onClick). The window you pass as `owner` is disabled while the dialog is open.

	Windows only: on other systems every function returns nil, "popup: only supported on Windows".
	Untested on real systems (written from the Win32 documentation and the Zune 0.5.9 FFI source).
]]

local ffi = zune.ffi
local T = ffi.types

local popup = {}

--------------------------------------------------------------------------
-- VBScript constants (MsgBox buttons / icons / defaults / return values)
--------------------------------------------------------------------------

popup.vb = {
	-- buttons
	OKOnly = 0,
	OKCancel = 1,
	AbortRetryIgnore = 2,
	YesNoCancel = 3,
	YesNo = 4,
	RetryCancel = 5,
	-- icons
	Critical = 16,
	Question = 32,
	Exclamation = 48,
	Information = 64,
	-- default button
	DefaultButton1 = 0,
	DefaultButton2 = 256,
	DefaultButton3 = 512,
	-- modality
	ApplicationModal = 0,
	SystemModal = 4096,
	-- extras (Win32 MB_ flags)
	Topmost = 0x40000,
	SetForeground = 0x10000,
	Help = 0x4000,
	-- return values
	OK = 1,
	Cancel = 2,
	Abort = 3,
	Retry = 4,
	Ignore = 5,
	Yes = 6,
	No = 7,
}

local UNSUPPORTED = "popup: only supported on Windows"

local function isWindows(): boolean
	return string.lower(zune.platform.os) == "windows"
end

--------------------------------------------------------------------------
-- UTF-8 <-> UTF-16
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
	local b = buffer.create((#units + 2) * 2) -- zero-filled: always ends with a double NUL
	for i, u in units do
		buffer.writeu16(b, (i - 1) * 2, u)
	end
	return b
end

-- Reads a NUL-terminated UTF-16 string from a pointer.
local function readWide(p: any): string
	local parts: { string } = {}
	local i = 0
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
	return table.concat(parts)
end

--------------------------------------------------------------------------
-- The custom dialog (C, compiled on first use)
--------------------------------------------------------------------------

local DIALOG_C = [[
#if defined(__i386__)
#define API __attribute__((stdcall))
typedef unsigned int UPTR;
typedef int IPTR;
#else
#define API
typedef unsigned long long UPTR;
typedef long long IPTR;
#endif

typedef unsigned short WCHAR;
typedef void* HANDLE;
typedef struct { int left, top, right, bottom; } RECT;
typedef struct { int x, y; } POINT;
typedef struct { HANDLE hwnd; unsigned int message; UPTR wParam; IPTR lParam; unsigned int time; POINT pt; unsigned int lPrivate; } MSG;
typedef IPTR (API *WNDPROC)(HANDLE, unsigned int, UPTR, IPTR);
typedef struct {
	unsigned int cbSize, style;
	WNDPROC lpfnWndProc;
	int cbClsExtra, cbWndExtra;
	HANDLE hInstance, hIcon, hCursor, hbrBackground;
	const WCHAR* lpszMenuName;
	const WCHAR* lpszClassName;
	HANDLE hIconSm;
} WNDCLASSEXW;

extern unsigned short API RegisterClassExW(const WNDCLASSEXW* wc);
extern HANDLE API CreateWindowExW(unsigned int exStyle, const WCHAR* cls, const WCHAR* name, unsigned int style, int x, int y, int w, int h,
                                  HANDLE parent, HANDLE menu, HANDLE inst, void* param);
extern IPTR API DefWindowProcW(HANDLE h, unsigned int m, UPTR w, IPTR l);
extern int API GetMessageW(MSG* msg, HANDLE h, unsigned int min, unsigned int max);
extern int API TranslateMessage(const MSG* msg);
extern IPTR API DispatchMessageW(const MSG* msg);
extern int API IsDialogMessageW(HANDLE dlg, MSG* msg);
extern int API DestroyWindow(HANDLE h);
extern void API PostQuitMessage(int code);
extern int API ShowWindow(HANDLE h, int cmd);
extern int API SetForegroundWindow(HANDLE h);
extern HANDLE API GetDC(HANDLE h);
extern int API ReleaseDC(HANDLE h, HANDLE dc);
extern int API DrawTextW(HANDLE dc, const WCHAR* text, int n, RECT* rc, unsigned int fmt);
extern IPTR API SendMessageW(HANDLE h, unsigned int m, UPTR w, IPTR l);
extern int API AdjustWindowRectEx(RECT* rc, unsigned int style, int menu, unsigned int exStyle);
extern int API EnableWindow(HANDLE h, int enable);
extern HANDLE API LoadIconW(HANDLE inst, const void* name);
extern HANDLE API LoadCursorW(HANDLE inst, const void* name);
extern HANDLE API SetFocus(HANDLE h);
extern int API GetWindowTextW(HANDLE h, WCHAR* out, int max);
extern int API GetWindowRect(HANDLE h, RECT* rc);
extern int API SystemParametersInfoW(unsigned int action, unsigned int param, void* pv, unsigned int ini);
extern int API MessageBeep(unsigned int type);
extern int API FillRect(HANDLE dc, const RECT* rc, HANDLE brush);
extern HANDLE API GetSysColorBrush(int index);
extern int API SetBkMode(HANDLE dc, int mode);
extern HANDLE API CreateFontW(int h, int w, int esc, int ori, int weight, unsigned int italic, unsigned int underline, unsigned int strike,
                              unsigned int charset, unsigned int outPrec, unsigned int clipPrec, unsigned int quality, unsigned int pitch, const WCHAR* face);
extern HANDLE API SelectObject(HANDLE dc, HANDLE obj);
extern int API DeleteObject(HANDLE obj);
extern int API GetDeviceCaps(HANDLE dc, int index);
extern HANDLE API GetModuleHandleW(const WCHAR* name);
extern int API MulDiv(int a, int b, int c);

static const WCHAR CLS[] = { 'Z','u','n','e','P','o','p','u','p',0 };
static const WCHAR STATIC_CLS[] = { 'S','T','A','T','I','C',0 };
static const WCHAR BUTTON_CLS[] = { 'B','U','T','T','O','N',0 };
static const WCHAR EDIT_CLS[] = { 'E','D','I','T',0 };
static const WCHAR FONT_FACE[] = { 'S','e','g','o','e',' ','U','I',0 };

#define MAXBTN 32
static int g_result, g_cancel, g_def, g_n, g_cw, g_ch, g_split, g_registered;
static HANDLE g_owner, g_edit;
static WCHAR* g_io;
static int g_ioChars;

static void zp_finish(HANDLE h, int result) {
	g_result = result;
	if (g_edit && g_io) GetWindowTextW(g_edit, g_io, g_ioChars);
	if (g_owner) EnableWindow(g_owner, 1);
	DestroyWindow(h);
}

static IPTR API zp_proc(HANDLE h, unsigned int m, UPTR w, IPTR l) {
	switch (m) {
	case 0x0111: { /* WM_COMMAND */
		int id = (int)(w & 0xFFFF);
		if (id == 1) { zp_finish(h, g_def); return 0; }      /* Enter */
		if (id == 2) { zp_finish(h, g_cancel); return 0; }   /* Esc */
		if (id >= 100 && id < 100 + g_n) { zp_finish(h, id - 99); return 0; }
		break;
	}
	case 0x0010: /* WM_CLOSE */
		zp_finish(h, g_cancel);
		return 0;
	case 0x0002: /* WM_DESTROY */
		PostQuitMessage(0);
		return 0;
	case 0x0014: { /* WM_ERASEBKGND: white message area, grey button bar */
		RECT top, bar;
		top.left = 0; top.top = 0; top.right = g_cw; top.bottom = g_split;
		bar.left = 0; bar.top = g_split; bar.right = g_cw; bar.bottom = g_ch;
		FillRect((HANDLE)w, &top, GetSysColorBrush(5));   /* COLOR_WINDOW */
		FillRect((HANDLE)w, &bar, GetSysColorBrush(15));  /* COLOR_BTNFACE */
		return 1;
	}
	case 0x0138: /* WM_CTLCOLORSTATIC */
		SetBkMode((HANDLE)w, 1);
		return (IPTR)GetSysColorBrush(5);
	}
	return DefWindowProcW(h, m, w, l);
}

static int S(int x, int dpi) { return MulDiv(x, dpi, 96); }

/*
 * labels: `n` NUL-separated UTF-16 strings. flags: 1 topmost, 2 input field, 4 password.
 * icon: system icon resource id (0 = none). beep: MB_ sound value, or -1 for silence.
 * io (optional, ioChars wide chars): initial text of the input field in, typed text out.
 * Returns the 1-based number of the pressed button (g_cancel for Esc / X).
 */
int zune_popup(void* owner, const WCHAR* title, const WCHAR* text, int icon, const WCHAR* labels, int n, int def, int cancel,
               int flags, int beep, WCHAR* io, int ioChars, int maxTextW) {
	const WCHAR* lab[MAXBTN];
	int bw[MAXBTN];
	HANDLE inst = GetModuleHandleW(0);
	int i;

	if (n < 1) n = 1;
	if (n > MAXBTN) n = MAXBTN;
	if (def < 1 || def > n) def = 1;
	if (cancel < 0 || cancel > n) cancel = 0;

	if (!g_registered) {
		WNDCLASSEXW wc;
		char* raw = (char*)&wc;
		for (i = 0; i < (int)sizeof(wc); i++) raw[i] = 0;
		wc.cbSize = sizeof(wc);
		wc.lpfnWndProc = zp_proc;
		wc.hInstance = inst;
		wc.hCursor = LoadCursorW(0, (const void*)(UPTR)32512); /* IDC_ARROW */
		wc.lpszClassName = CLS;
		if (!RegisterClassExW(&wc)) return -1;
		g_registered = 1;
	}

	HANDLE sdc = GetDC(0);
	int dpi = GetDeviceCaps(sdc, 90); /* LOGPIXELSY */
	if (dpi < 96) dpi = 96;
	HANDLE font = CreateFontW(-MulDiv(9, dpi, 72), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, FONT_FACE);
	HANDLE oldFont = SelectObject(sdc, font);

	/* split the label list and measure the buttons */
	const WCHAR* p = labels;
	for (i = 0; i < n; i++) {
		RECT rc;
		lab[i] = p;
		while (*p) p++;
		p++;
		rc.left = 0; rc.top = 0; rc.right = 0; rc.bottom = 0;
		DrawTextW(sdc, lab[i], -1, &rc, 0x400 | 0x20); /* DT_CALCRECT | DT_SINGLELINE */
		bw[i] = rc.right - rc.left + S(28, dpi);
		if (bw[i] < S(80, dpi)) bw[i] = S(80, dpi);
	}

	/* measure the message */
	RECT tr;
	tr.left = 0; tr.top = 0; tr.right = S(maxTextW > 120 ? maxTextW : 120, dpi); tr.bottom = 0;
	DrawTextW(sdc, text, -1, &tr, 0x400 | 0x10 | 0x800); /* DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX */
	int tw = tr.right, th = tr.bottom;
	int hasInput = (flags & 2) != 0;
	int hasIcon = icon != 0;
	if (hasInput && tw < S(300, dpi)) tw = S(300, dpi);
	if (tw < S(120, dpi)) tw = S(120, dpi);

	SelectObject(sdc, oldFont);
	ReleaseDC(0, sdc);

	/* layout */
	int margin = S(16, dpi), pad = S(20, dpi), iconSize = S(32, dpi), iconGap = S(14, dpi), gap = S(8, dpi);
	int btnH = S(26, dpi), editH = S(23, dpi);
	int textX = margin + (hasIcon ? iconSize + iconGap : 0);
	int bodyH = th > (hasIcon ? iconSize : 0) ? th : (hasIcon ? iconSize : 0);
	int rowW = gap * (n - 1);
	for (i = 0; i < n; i++) rowW += bw[i];

	int topH = pad + bodyH + (hasInput ? S(10, dpi) + editH : 0) + pad;
	int cw = textX + tw + margin;
	if (cw < rowW + 2 * margin) cw = rowW + 2 * margin;
	int ch = topH + S(14, dpi) + btnH + S(14, dpi);
	g_cw = cw; g_ch = ch; g_split = topH;
	g_result = 0; g_cancel = cancel; g_def = def; g_n = n; g_owner = owner; g_edit = 0;
	g_io = io; g_ioChars = ioChars;

	/* the window itself */
	unsigned int style = 0x80000000u | 0x00C00000u | 0x00080000u; /* WS_POPUP | WS_CAPTION | WS_SYSMENU */
	unsigned int exStyle = 0x1 | ((flags & 1) ? 0x8 : 0);       /* WS_EX_DLGMODALFRAME [| WS_EX_TOPMOST] */
	RECT adj;
	adj.left = 0; adj.top = 0; adj.right = cw; adj.bottom = ch;
	AdjustWindowRectEx(&adj, style, 0, exStyle);
	int ww = adj.right - adj.left, wh = adj.bottom - adj.top;

	RECT area;
	if (owner && GetWindowRect(owner, &area)) {
	} else {
		SystemParametersInfoW(48, 0, &area, 0); /* SPI_GETWORKAREA */
	}
	int x = area.left + ((area.right - area.left) - ww) / 2;
	int y = area.top + ((area.bottom - area.top) - wh) / 2;
	if (x < 0) x = 0;
	if (y < 0) y = 0;

	HANDLE hwnd = CreateWindowExW(exStyle, CLS, title, style, x, y, ww, wh, owner, 0, inst, 0);
	if (!hwnd) { DeleteObject(font); return -1; }

	HANDLE ctl;
	if (hasIcon) {
		ctl = CreateWindowExW(0, STATIC_CLS, 0, 0x50000000u | 0x3, margin, pad, iconSize, iconSize, hwnd, 0, inst, 0); /* SS_ICON */
		SendMessageW(ctl, 0x0170, (UPTR)LoadIconW(0, (const void*)(UPTR)icon), 0); /* STM_SETICON */
	}
	int textY = pad + ((hasIcon && th < iconSize) ? (iconSize - th) / 2 : 0);
	ctl = CreateWindowExW(0, STATIC_CLS, text, 0x50000000u | 0x80, textX, textY, tw, th, hwnd, 0, inst, 0); /* SS_NOPREFIX */
	SendMessageW(ctl, 0x30, (UPTR)font, 1);

	if (hasInput) {
		unsigned int es = 0x50000000u | 0x80 | 0x10000; /* ES_AUTOHSCROLL | WS_TABSTOP */
		if (flags & 4) es |= 0x20;                      /* ES_PASSWORD */
		g_edit = CreateWindowExW(0x200, EDIT_CLS, io, es, textX, pad + bodyH + S(10, dpi), tw, editH, hwnd, 0, inst, 0); /* WS_EX_CLIENTEDGE */
		SendMessageW(g_edit, 0x30, (UPTR)font, 1);
	}

	HANDLE btn[MAXBTN];
	int bx = cw - margin - rowW;
	for (i = 0; i < n; i++) {
		unsigned int bs = 0x50000000u | 0x10000 | (i == def - 1 ? 0x1 : 0x0); /* WS_TABSTOP | BS_DEFPUSHBUTTON */
		btn[i] = CreateWindowExW(0, BUTTON_CLS, lab[i], bs, bx, topH + S(14, dpi), bw[i], btnH, hwnd, (HANDLE)(UPTR)(100 + i), inst, 0);
		SendMessageW(btn[i], 0x30, (UPTR)font, 1);
		bx += bw[i] + gap;
	}

	if (g_owner) EnableWindow(g_owner, 0);
	if (beep >= 0) MessageBeep((unsigned int)beep);
	ShowWindow(hwnd, 5); /* SW_SHOW */
	SetForegroundWindow(hwnd);
	if (g_edit) {
		SetFocus(g_edit);
		SendMessageW(g_edit, 0x00B1, 0, -1); /* EM_SETSEL: select everything */
	} else {
		SetFocus(btn[def - 1]);
	}

	MSG msg;
	while (GetMessageW(&msg, 0, 0, 0) > 0) {
		if (!IsDialogMessageW(hwnd, &msg)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
	}

	DeleteObject(font);
	return g_result;
}
]]

local SYMBOLS = {
	user32 = {
		"RegisterClassExW",
		"CreateWindowExW",
		"DefWindowProcW",
		"GetMessageW",
		"TranslateMessage",
		"DispatchMessageW",
		"IsDialogMessageW",
		"DestroyWindow",
		"PostQuitMessage",
		"ShowWindow",
		"SetForegroundWindow",
		"GetDC",
		"ReleaseDC",
		"DrawTextW",
		"SendMessageW",
		"AdjustWindowRectEx",
		"EnableWindow",
		"LoadIconW",
		"LoadCursorW",
		"SetFocus",
		"GetWindowTextW",
		"GetWindowRect",
		"SystemParametersInfoW",
		"MessageBeep",
		"FillRect",
		"GetSysColorBrush",
	},
	gdi32 = { "SetBkMode", "CreateFontW", "SelectObject", "DeleteObject", "GetDeviceCaps" },
	kernel32 = { "GetModuleHandleW", "MulDiv" },
}

local state: any = nil

local function init(): any
	if state then
		return state
	end
	local libs: { any } = {}
	local symbols: { [string]: any } = {}
	for name, list in SYMBOLS do
		local lib = ffi.dlopen(name .. ".dll", {})
		table.insert(libs, lib) -- keep the handles alive: closing a library would unmap its symbols
		for _, symbol in list do
			symbols[symbol] = lib:getSymbol(symbol) or error(`popup: {name}.dll has no {symbol}`, 0)
		end
	end
	local compiled = ffi.c.compile(DIALOG_C, { symbols = symbols })
	local entry = compiled:getSymbol("zune_popup") or error("popup: zune_popup missing", 0)
	local user32 = ffi.dlopen("user32.dll", {
		MessageBoxW = { returns = T.i32, args = { T.pointer, T.pointer, T.pointer, T.u32 } },
	})
	state = {
		libs = libs,
		compiled = compiled,
		user32 = user32,
		call = ffi.fn({
			returns = T.i32,
			args = {
				T.pointer,
				T.pointer,
				T.pointer,
				T.i32,
				T.pointer,
				T.i32,
				T.i32,
				T.i32,
				T.i32,
				T.i32,
				T.pointer,
				T.i32,
				T.i32,
			},
		}, entry),
	}
	return state
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- owner: nil | glfw Window (getWin32Window) | raw HWND pointer
local function ownerHandle(owner: any): any
	if owner == nil then
		return ffi.null
	end
	if type(owner) == "table" and owner.getWin32Window then
		return owner:getWin32Window() or ffi.null
	end
	return owner
end

local ICONS: { [string]: { id: number, beep: number } } = {
	none = { id = 0, beep = 0 },
	info = { id = 32516, beep = 0x40 }, -- IDI_INFORMATION / MB_ICONINFORMATION
	information = { id = 32516, beep = 0x40 },
	warning = { id = 32515, beep = 0x30 },
	error = { id = 32513, beep = 0x10 },
	question = { id = 32514, beep = 0x20 },
	shield = { id = 32518, beep = 0 },
}

local VB_ICON: { [string]: number } = { info = 64, information = 64, warning = 48, error = 16, question = 32 }

local function stripMnemonic(label: string): string
	local out = string.gsub(label, "&(.)", "%1")
	return out
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

-- VBScript-style MsgBox. `buttons` are the VBScript flags (popup.vb.*), default 0 (OK only).
-- Returns the VBScript result code (popup.vb.OK .. popup.vb.No) or nil, error.
function popup.msgBox(text: any, buttons: number?, title: string?, owner: any?): (number?, string?)
	if not isWindows() then
		return nil, UNSUPPORTED
	end
	local ok, st = pcall(init)
	if not ok then
		return nil, tostring(st)
	end
	local textPtr = ffi.dupe(toUtf16(tostring(text)))
	local titlePtr = ffi.dupe(toUtf16(title or ""))
	local code = st.user32.MessageBoxW(ownerHandle(owner), textPtr, titlePtr, buttons or 0)
	ffi.free(textPtr)
	ffi.free(titlePtr)
	if code == 0 then
		return nil, "popup: MessageBoxW failed"
	end
	return code, nil
end

export type ShowOptions = {
	title: string?,
	text: any?, -- message (alias: message)
	message: any?,
	icon: string?, -- "none" | "info" | "warning" | "error" | "question" | "shield"
	buttons: { string }?, -- default { "OK" }
	default: number?, -- 1-based index of the default button (default 1)
	cancel: number?, -- 1-based index returned for Esc / closing the window
	topmost: boolean?,
	sound: boolean?, -- play the system sound of the icon (default true)
	owner: any?, -- glfw Window or HWND pointer
	maxWidth: number?, -- text wrap width in px at 96 dpi (default 480)
	input: (boolean | string)?, -- show a text field (true, or its initial text)
	password: boolean?, -- mask the text field
}

-- Custom dialog with your own buttons. Returns (index, label, inputText):
-- the 1-based button index (the `cancel` index for Esc / X, 0 when neither applies), its text, and the text field content (input only).
function popup.show(options: ShowOptions?): (number?, string?, string?)
	local o: ShowOptions = options or {}
	if not isWindows() then
		return nil, UNSUPPORTED, nil
	end
	local ok, st = pcall(init)
	if not ok then
		return nil, tostring(st), nil
	end

	local buttons: { string } = o.buttons or { "OK" }
	if #buttons == 0 then
		buttons = { "OK" }
	end
	if #buttons > 32 then
		return nil, "popup: at most 32 buttons", nil
	end
	local icon = ICONS[string.lower(o.icon or "none")]
	if not icon then
		return nil, `popup: unknown icon "{o.icon}"`, nil
	end

	local labels = ""
	for _, b in buttons do
		labels ..= tostring(b) .. "\0"
	end
	labels ..= "\0"

	local flags = 0
	if o.topmost then
		flags += 1
	end
	local hasInput = o.input ~= nil and o.input ~= false
	if hasInput then
		flags += 2
		if o.password then
			flags += 4
		end
	end

	-- input buffer (4096 wide chars), pre-filled with the initial text
	local ioChars = 4096
	local initial = buffer.create(ioChars * 2)
	if type(o.input) == "string" then
		local wide = toUtf16(o.input)
		buffer.copy(initial, 0, wide, 0, math.min(buffer.len(wide), (ioChars - 1) * 2))
	end
	local ioPtr = ffi.dupe(initial)

	local titlePtr = ffi.dupe(toUtf16(o.title or ""))
	local textPtr = ffi.dupe(toUtf16(tostring(if o.text ~= nil then o.text else (o.message or ""))))
	local labelsPtr = ffi.dupe(toUtf16(labels))
	local beep = if o.sound == false then -1 else icon.beep

	local result = st.call(
		ownerHandle(o.owner),
		titlePtr,
		textPtr,
		icon.id,
		labelsPtr,
		#buttons,
		o.default or 1,
		o.cancel or 0,
		flags,
		beep,
		ioPtr,
		ioChars,
		o.maxWidth or 480
	)

	local typed: string? = if hasInput then readWide(ioPtr) else nil
	ffi.free(titlePtr)
	ffi.free(textPtr)
	ffi.free(labelsPtr)
	ffi.free(ioPtr)

	if result < 0 then
		return nil, "popup: could not create the window", nil
	end
	local label: string? = if result >= 1 then stripMnemonic(tostring(buttons[result])) else nil
	return result, label, typed
end

-- OK-only box. icon: "info" | "warning" | "error" | "question" (default none)
function popup.alert(text: any, title: string?, icon: string?, owner: any?): (number?, string?)
	return popup.msgBox(text, (if icon then VB_ICON[string.lower(icon)] else nil) or 0, title or "", owner)
end

-- OK / Cancel box; true when OK was pressed
function popup.confirm(text: any, title: string?, owner: any?): boolean
	local code = popup.msgBox(text, popup.vb.OKCancel + popup.vb.Question, title or "", owner)
	return code == popup.vb.OK
end

-- VBScript InputBox: returns the text, or nil when cancelled (or on error)
function popup.input(prompt: any, title: string?, default: string?, options: ShowOptions?): string?
	local o: any = {}
	for k, v in (options or {}) :: any do
		o[k] = v
	end
	o.text = prompt
	o.title = title or o.title or ""
	o.input = default or o.input or true
	o.buttons = o.buttons or { "OK", "Cancel" }
	o.default = o.default or 1
	o.cancel = o.cancel or #o.buttons
	local index, _, typed = popup.show(o)
	if index == nil or index == 0 or index == o.cancel then
		return nil
	end
	return typed
end

return popup
