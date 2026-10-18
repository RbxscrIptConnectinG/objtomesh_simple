--[[
	ui.luau - tiny retained-mode widget toolkit on top of renderer.luau

	local ui = require("./ui")
	local app = ui.createApp({ width = 960, height = 600, title = "Demo" })
	local panel = app.root:add(ui.Frame({ position = {20, 20}, size = {300, 400}, effects = { padding = 8, listLayout = { padding = 8, itemLineAlignment = "Stretch" } } }))
	panel:add(ui.Button({ size = {0, 40}, onClick = function(btn) print("clicked") end }))
	app:run()

	Widgets: Frame, Button, Image, ModelView, ScrollingFrame, Text, TextBox
	Common props: transparencyMethod ("blend" default | "dither" dot-pattern, for all 2D drawing of the widget: background, border, text, image), antiAlias (text glyph edges: nil / "Grayscale" smooth | "None" hard-edged 1-bit), interpolation (texture filtering of Image / ModelView / Button icon:
	                 "Linear" (default) | "Nearest Neighbor" | "Cubic" | "Cubic B-spline" | "Mitchell" | "Lanczos"), backgroundTransparency / textTransparency / imageTransparency (0 opaque .. 1 invisible; they override the optional 4th (alpha) value of the colour; `transparency` = old name of backgroundTransparency; background only - text, border, images and
	                 models stay fully visible), position, size, anchor, color {r,g,b,a}, visible, border {width=, color=}, clip, effects, LayoutOrder, name,
	  ZIndex (default 0): draw order. Higher draws on top (and wins hit tests). Any number, negatives allowed.
	  ZIndexBehavior ("Sibling" | "Global"): how a widget's descendants are ordered. Set it on app.root (everything) or on any
	    widget (that widget's subtree); unset = inherited from the parent, the root defaults to "Sibling".
	    "Sibling": ZIndex orders a widget against its siblings only; each widget and its descendants stay together
	               and children always draw above their parent. Equal ZIndex keeps insertion order (later = on top).
	    "Global":  ZIndex orders every widget of the subtree against every other one, overriding the order implied by
	               the hierarchy. Ties fall back to depth in the hierarchy (deeper = on top), then insertion order. A
	               child whose ZIndex is lower than its parent's draws behind the parent. Borders and scrollbars are
	               drawn with their widget, so with Global they can be covered by children that share its ZIndex.
	  position/size: {x, y} in pixels, or {scaleX, offsetX, scaleY, offsetY}
	  effects: { aspectRatio = {...}, listLayout = {...}, padding = ... }
	          (every widget; nil = off) things that change how a widget is sized, like Roblox's UI constraints. aspectRatio keeps the
	          width : height ratio (UIAspectRatioConstraint): "fitWithinMaxSize" (default) shrinks the widget to the largest box of
	          that ratio inside the size given by `size`; "scaleWithParentSize" keeps the dominant axis ("width" default) as given
	          by `size` and derives the other one, so with scale sizes it follows the parent. `aspectRatio = 2` is shorthand for { value = 2 }.
	  effects.listLayout (any widget, incl. ScrollingFrame; nothing is laid out unless you set it - there is no implicit list layout):
	          like Roblox's UIListLayout it stacks the widget's children, ignoring their `position`.
	          { fillDirection = "Vertical" (default) | "Horizontal",
	            padding = gap between items: pixels, or { scale, offset } (scale of the widget's size along the flow direction),
	            sortOrder = "LayoutOrder" (default: children sorted by their LayoutOrder prop, ties keep insertion order) | "Name" | function(a, b) -> boolean,
	            wraps = true (only with "Horizontal"): flows items into rows like a grid,
	            horizontalAlignment = "Left" (default) | "Center" | "Right", verticalAlignment = "Top" (default) | "Center" | "Bottom"
	              (they only matter when there is free space; along the flow direction the whole run moves, across it each item is placed on its own),
	            horizontalFlex / verticalFlex = "None" (default) | "Fill" | "SpaceBetween" | "SpaceAround" | "SpaceEvenly": how the free space is shared.
	              Along the flow direction (horizontalFlex when Horizontal, verticalFlex when Vertical):
	              Fill: the free space of a row goes to the items. Items whose size has a SCALE part along the flow direction share it in proportion
	              to that scale (two items with scale 1 get half each, scale 1 and 2 get 1/3 and 2/3; their offset part is added on top, items without
	              a scale part keep their size). When no item has a scale part, every item grows by the same amount. autoSize items count as fixed.
	              aspectRatio then acts on the grown size (e.g. dominantAxis "width" derives the height from the share the item got).
	              The Space* modes put the free space between / around the items. All of them replace the alignment along that axis.
	              Across the flow direction only "Fill" counts: every item gets the full inner width / height (= itemLineAlignment "Stretch"),
	            itemLineAlignment = "Automatic" (default: use the alignments) | "Start" | "Center" | "End" | "Stretch" (across the flow direction;
	              Stretch makes every item as wide / tall as the widget's inner area) }
	          `effects.listLayout = true` is the same as `{}`. Children with `visible = false` are skipped.
	  effects.padding (UIPadding, any widget): children are laid out inside a box shrunk by this much, whether they are stacked by a list layout or placed by
	          `position`. A number = all four sides in pixels, or { left, right, top, bottom } where each is a number (pixels) or { scale, offset }
	          (left / right scale with the widget's width, top / bottom with its height). With autoSize the widget grows by the padding; a ScrollingFrame's
	          scroll range includes it. Padding does not move the widget's own text (use textPadding for that).
	  layout: { direction = "vertical"|"horizontal", gap, padding, stretch, wrap, horizontalAlignment, verticalAlignment }
	          the older form of listLayout, still accepted (`padding` = inner padding, `gap` = spacing, `stretch` = itemLineAlignment "Stretch").
	          effects.listLayout wins when both are set.
	  autoSize ("x" | "y" | "xy" | false, default false; available on EVERY widget): the widget grows to fit its content on
	          those axes - its children (positions, sizes, layout padding/gap) and its own `text`. `size` on an automatic axis
	          is the MINIMUM (a widget created with autoSize and no `size` starts at 0). Nested autoSize widgets resolve
	          inside-out. While measuring, scale components on an automatic axis count as 0 (the parent is not finished
	          yet), so scale-sized children of an autoSize axis only contribute their offset; Stretch on an automatic
	          axis stretches children to the widest/tallest one afterwards. A widget with a wrapping list layout and autoSize "x"
	          wraps at its `size` width (no wrapping when that is 0).
	Button:          hoverColor, pressedColor, disabledColor, disabled, image (texture), svg (an SVG icon instead of `image`, see Image),
	                 onClick/onPress/onRelease/onHover
	Text:            text, font, textSize (px, default 16), textColor {r,g,b[,a]}, textTransparency, align ("left"|"center"|"right"),
	                 valign ("top"|"middle"|"bottom"), wrap, lineHeight (multiplier), textPadding,
	                 autoSize (see Common props: Text defaults to "xy" when you give no `size`, or "y" with wrap),
	                 textScaled (true = the font size is chosen so the text fills the box; minTextSize/maxTextSize bound it)
	                 `size` and `position` accept {scaleX, offsetX, scaleY, offsetY} like every widget, e.g. size = {1, 0, 1, -40}
	                 is "full parent width, parent height minus 40px"; {x, y} is plain pixels.
	                 `font` is a .ttf/.otf path (or a font.luau object) and is inherited from parent widgets, then from the
	                 app default (ui.createApp({ font = ... })). Any widget with a `text` prop draws it, so
	                 Buttons/Frames can carry labels too (Button: text centred, textPadding 6). With autoSize the widget
	                 resizes to its text and children (Text does this by default when you give no size).
	TextBox:         a Text that can be edited. text, editable (default true), multiline (Enter inserts a line break and the
	                 text wraps; otherwise Enter fires onSubmit and the box scrolls sideways), placeholder, placeholderColor,
	                 maxLength, filter(char) -> boolean, selectionColor, caretColor, focusColor, plus every Text prop.
	                 Events: onChanged(box, text), onSubmit(box, text), onFocus(box), onBlur(box).
	                 Methods: focus(), blur(), isFocused(), setText(str) (silent), selectAll().
	                 Keys: arrows (+Shift selects, +Ctrl/Alt moves by word), Home/End (+Ctrl = whole text), Backspace/Delete,
	                 Ctrl/Cmd+A/C/X/V (system clipboard), Enter, Esc (blur). Mouse: click, drag-select, Shift+click.
	Image:           texture (a Texture, or the path of a PNG / SVG file - loaded for you and cached; the same for Button `image`,
	                 and ModelView `texture`), fit = "stretch" | "contain" | "cover"; `color` is the tint; imageTransparency (0..1); optional backgroundColor {r,g,b,a} behind
	                 the picture, faded by `transparency`
	                 svg = "<svg ...>markup" | "path/to/file.svg" | svg.parse() document: drawn sharp at the widget's pixel size (it is rasterized again,
	                 after svgDelay seconds, when the widget is resized; fit decides the shape, "stretch" ignores the aspect ratio). Also on Button
	                 (the icon). svgColor = what `currentColor` means in the file ({r,g,b,a} 0..1 or a CSS colour), svgScale (default 1, e.g. 2 for
	                 extra sharpness), svgDelay (default 0.12), svgMaxSize (default 2048 px per side), svgBleed (see svg.luau). svg replaces
	                 `texture` (Image) / `image` (Button); set svg = nil to go back. gui:clearSvgCache() re-reads files. See svg.luau for what is supported.
	ModelView:       highlight = { fillColor, fillTransparency, outlineColor, outlineTransparency, outlineThickness, depthMode } (real highlight: flat fill over the visible
	                 surface + silhouette outline, no copied/inverted mesh; see README), modelTransparencyMethod ("blend" default | "dither" dot-pattern; applies to the model's imageTransparency / modelColor alpha; the ModelView `transparencyMethod` is its background), imageTransparency (0..1, fades the rendered model only; `transparency` fades the background only), model, texture, modelColor, yaw, pitch, zoom, fov, autoRotate (rad/s), zoomable,
	                 doubleSided (default true; false culls back faces - faster, but triangles must wind counter-clockwise)
	ScrollingFrame:  scrollY, scrollSpeed, scrollbarColor, thumbColor  (always clips; wheel + scrollbar drag)

]]

local glfw = require("./glfw")
local Renderer = require("./renderer")
local fontlib = require("@self/font")
local textlib = require("@self/text")
local imagelib = require("./image")

local ui = {}

local Widget = {}
Widget.__index = Widget

local BAR_W = 10

local DEFAULTS: { [string]: { [string]: any } } = {
	Frame = { color = { 0.15, 0.16, 0.2, 1 }, interactive = false },
	Text = { color = { 0, 0, 0, 0 }, interactive = false },
	TextBox = {
		color = { 0.09, 0.1, 0.13, 1 },
		interactive = true,
		editable = true,
		multiline = false,
		text = "",
		placeholder = "",
		textPadding = 8,
		border = { width = 2, color = { 1, 1, 1, 0.15 } },
		focusColor = { 0.35, 0.6, 1, 1 },
		selectionColor = { 0.25, 0.45, 0.9, 0.55 },
		placeholderColor = { 1, 1, 1, 0.35 },
	},
	Button = {
		color = { 0.25, 0.45, 0.85, 1 },
		hoverColor = { 0.33, 0.53, 0.93, 1 },
		pressedColor = { 0.18, 0.35, 0.7, 1 },
		disabledColor = { 0.3, 0.3, 0.33, 1 },
		interactive = true,
		align = "center",
		valign = "middle",
		textPadding = 6,
	},
	Image = { color = { 1, 1, 1, 1 }, interactive = false, fit = "stretch" },
	ModelView = {
		color = { 0.05, 0.05, 0.07, 1 },
		modelColor = { 0.8, 0.8, 0.88, 1 },
		interactive = true,
		yaw = 0.6,
		pitch = 0.35,
		zoom = 1,
		fov = 0.8,
		autoRotate = 0.5,
		zoomable = false,
		doubleSided = true,
	},
	ScrollingFrame = {
		color = { 0.12, 0.13, 0.16, 1 },
		interactive = true,
		scrollbarColor = { 1, 1, 1, 0.06 },
		thumbColor = { 1, 1, 1, 0.35 },
		scrollSpeed = 48,
	},
}

local function create(kind: string, props: { [string]: any }?): any
	local w: any = setmetatable({
		kind = kind,
		children = {},
		visible = true,
		ZIndex = 0,
		position = { 0, 0 },
		size = { 100, 100 },
		anchor = { 0, 0 },
		ax = 0,
		ay = 0,
		aw = 0,
		ah = 0,
		scrollY = 0,
		contentW = 0,
		contentH = 0,
		textColor = { 1, 1, 1, 1 },
		textSize = 16,
		align = "left",
		valign = "top",
		lineHeight = 1,
		textPadding = 0,
	}, Widget)
	for k, v in DEFAULTS[kind] do
		w[k] = if type(v) == "table" then table.clone(v) else v
	end
	if props then
		for k, v in props do
			w[k] = v
		end
		if props.autoSize and props.size == nil then
			w.size = { 0, 0 } -- `size` is the minimum on automatic axes, so start from nothing
		end
	end
	return w
end

function ui.Frame(props: any?): any
	return create("Frame", props)
end
function ui.Button(props: any?): any
	return create("Button", props)
end
function ui.Image(props: any?): any
	return create("Image", props)
end
function ui.ModelView(props: any?): any
	return create("ModelView", props)
end
function ui.ScrollingFrame(props: any?): any
	return create("ScrollingFrame", props)
end

-- Text label. Without `size` it fits its text (autoSize "xy"); with `wrap = true` and a width it grows downward ("y").
function ui.Text(props: any?): any
	local p: any = props or {}
	local w = create("Text", p)
	if p.textScaled and p.size == nil then
		w.size = { 1, 0, 1, 0 } -- scaled text fills its parent unless told otherwise
	elseif p.size == nil then
		w.size = { 0, 0 } -- minimum size when the widget fits its text
	end
	if p.autoSize == nil then
		w.autoSize = if p.textScaled then false elseif p.size == nil then "xy" elseif p.wrap then "y" else false
	end
	return w
end

-- Editable text. Single-line by default (36px high); multiline = true gives a wrapping, vertically scrolling box.
function ui.TextBox(props: any?): any
	local p: any = props or {}
	local w = create("TextBox", p)
	w.text = tostring(w.text or "")
	if p.size == nil then
		w.size = { 240, if w.multiline then 120 else 36 }
	end
	if p.valign == nil then
		w.valign = if w.multiline then "top" else "middle"
	end
	w.caret, w.selAnchor = 0, 0 -- caret = number of characters before the cursor; selAnchor = other end of the selection
	w._sx, w._sy = 0, 0 -- scroll offsets
	return w
end

function Widget:add(child: any): any
	if child.parent then
		child:remove()
	end
	child.parent = self
	table.insert(self.children, child)
	return child
end

function Widget:remove()
	local p = self.parent
	if p then
		local i = table.find(p.children, self)
		if i then
			table.remove(p.children, i)
		end
		self.parent = nil
	end
end

function Widget:clear()
	for _, c in self.children do
		c.parent = nil
	end
	table.clear(self.children)
end

function Widget:getRect(): (number?, number?, number?, number?)
	return self.ax, self.ay, self.aw, self.ah
end

function Widget:setScroll(y: number)
	self.scrollY = math.clamp(y, 0, math.max(0, self.contentH - self.ah))
end

local function udim(v: { number }, pw: number, ph: number): (number?, number?)
	if #v >= 4 then
		return v[1] * pw + v[2], v[3] * ph + v[4]
	end
	return v[1], v[2]
end

--------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------

function Widget:_font(): any
	local gui = self.gui
	local w: any = self
	while w do
		if w.font then
			return gui:_resolveFont(w.font)
		end
		w = w.parent
	end
	if gui.defaultFont then
		return gui:_resolveFont(gui.defaultFont)
	end
	error(
		'ui: this widget has text but no font. Set font = "path/to/font.ttf" on it (or a parent), or pass font to ui.createApp.',
		0
	)
end

function Widget:_textLayout(maxW: number?, override: string?, sizeOverride: number?): any
	local fnt = self:_font()
	local str = if override ~= nil then override else tostring(self.text)
	local fontSize = sizeOverride or self.textSize
	local key = `{tostring(fnt)}|{fontSize}|{self.lineHeight}|{tostring(maxW)}|{str}`
	local slot = if override ~= nil then "_tlp" else "_tl"
	local cached = self[slot]
	if cached and cached.key == key then
		return cached.layout
	end
	local layout = self.gui.text:layout(fnt, str, fontSize, maxW, self.lineHeight)
	self[slot] = { key = key, layout = layout }
	return layout
end

-- Content extent (children + own text), measured with `W`/`H` as the parent size children resolve their scale against.
-- limitW is the width at which wrapping layouts break rows; textWidth the width available to wrapped text (nil = unwrapped).
function Widget:_measureContent(
	W: number,
	H: number,
	limitW: number,
	autoW: boolean,
	autoH: boolean,
	textWidth: number?
): (number?, number?)
	local ex, ey = self:_flow(W, H, limitW, 0, 0, false, autoW, autoH)
	if self.kind == "ScrollingFrame" then
		ex += BAR_W + 2
	end
	if self.text ~= nil then
		local pad = self.textPadding or 0
		local wraps = self.wrap or (self.kind == "TextBox" and self.multiline)
		local layout = self:_textLayout(if wraps and textWidth then textWidth - 2 * pad else nil)
		ex = math.max(ex, layout.width + 2 * pad)
		ey = math.max(ey, layout.height + 2 * pad)
	end
	return ex, ey
end

-- Final size of this widget inside `parent` (anything with aw/ah), honouring autoSize. forcedW: width imposed by the
-- parent's layout (stretch), which wins over an automatic X axis.
function Widget:_resolveSize(parent: any, forcedW: number?): (number?, number?)
	local specW, specH = udim(self.size, parent.aw, parent.ah)
	local mode = self.autoSize
	local autoX = (mode == "x" or mode == "xy") and not forcedW
	local autoY = mode == "y" or mode == "xy"
	if not autoX and not autoY then
		return forcedW or specW, specH
	end
	local fixedW = forcedW or specW
	local W = if autoX then 0 else fixedW
	local H = if autoY then 0 else specH
	local limitW = if autoX then (if specW > 0 then specW else math.huge) else fixedW
	local cw, ch = self:_measureContent(W, H, limitW, autoX, autoY, if autoX then nil else fixedW)
	return if autoX then math.max(specW, cw) else fixedW, if autoY then math.max(specH, ch) else specH
end

-- Largest font size (within minTextSize..maxTextSize) at which the text fits the box (textScaled).
function Widget:_fitTextSize(innerW: number, innerH: number): number
	local fnt = self:_font()
	local str = tostring(self.text)
	local lo, hi = math.max(1, self.minTextSize or 6), math.max(1, self.maxTextSize or 200)
	local key = `{tostring(fnt)}|{innerW}|{innerH}|{str}|{tostring(self.wrap)}|{self.lineHeight}|{lo}|{hi}`
	local cached = self._fit
	if cached and cached.key == key then
		return cached.size
	end
	local best = lo
	while lo <= hi do
		local mid = (lo + hi) // 2
		local l = self.gui.text:layout(fnt, str, mid, if self.wrap then innerW else nil, self.lineHeight)
		if l.width <= innerW + 0.5 and l.height <= innerH + 0.5 then
			best = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	self._fit = { key = key, size = best }
	return best
end

-- interpolation (textures: Image, ModelView, Button icon): how texels are filtered when a texture is scaled. Case, spaces and dashes are ignored.
--   "Linear" (default; "Bilinear")        smooth
--   "Nearest Neighbor" ("Nearest", "Point")  hard blocky pixels
--   "Cubic" ("Bicubic", "Catmull-Rom")    sharper than linear
--   "Cubic B-spline" ("BSpline")          very smooth
--   "Mitchell"                            balanced cubic (little ringing)
--   "Lanczos"                             sharpest, best for downscaling
local INTERPOLATION: { [string]: number } = {
	linear = 0,
	bilinear = 0,
	nearest = 1,
	nearestneighbor = 1,
	nearestneighbour = 1,
	point = 1,
	cubic = 2,
	bicubic = 2,
	catmullrom = 2,
	bspline = 3,
	cubicbspline = 3,
	mitchell = 4,
	lanczos = 5,
	lanczos3 = 5,
}

local function normalizeName(value: any): string
	local key = string.lower(tostring(value))
	return (string.gsub(key, "[^%a%d]", ""))
end

-- antiAlias (text glyph smoothing): nil | "Grayscale" (default, smooth edges) | "None" (hard-edged 1-bit glyphs, for pixel fonts)
local ANTIALIAS: { [string]: boolean } =
	{ grayscale = true, greyscale = true, smooth = true, default = true, none = false, off = false }

function Widget:_interp(): number
	local value = self.interpolation
	if value == nil then
		return 0
	end
	local cached = self._interpCache
	if cached and cached[1] == value then
		return cached[2]
	end
	local id = INTERPOLATION[normalizeName(value)]
	if not id then
		error(
			`ui: unknown interpolation "{value}" (use "Linear", "Nearest Neighbor", "Cubic", "Cubic B-spline", "Mitchell" or "Lanczos")`,
			0
		)
	end
	self._interpCache = { value, id }
	return id
end

-- true = smooth glyph edges
function Widget:_smoothText(): boolean
	local value = self.antiAlias
	if value == nil or value == true then
		return true
	elseif value == false then
		return false
	end
	local smooth = ANTIALIAS[normalizeName(value)]
	if smooth == nil then
		error(`ui: unknown antiAlias "{value}" (use nil / "Grayscale" or "None")`, 0)
	end
	return smooth
end

-- Alpha rule: the 4th value of a colour is optional (default 1). A transparency property (0 opaque .. 1 invisible) that is set
-- (not nil) ALWAYS overrides the colour's own alpha:
--   backgroundTransparency (alias: transparency)  the background `color` (Frame, Button, Text, ...) and Image `backgroundColor`
--   textTransparency                               text of every widget with text (TextBox too: text, placeholder, caret)
--   imageTransparency                              the Image texture tint / the rendered ModelView model
-- Borders, scrollbars and the Button icon keep the alpha of their own colours.
local function resolveAlpha(color: { number }?, transparency: number?): number
	if transparency ~= nil then
		return 1 - math.clamp(transparency, 0, 1)
	end
	return (color and color[4]) or 1
end

-- transparencyMethod / modelTransparencyMethod: "blend" (default, smooth alpha blending) | "dither" (dot pattern, no blending)
local function methodName(value: any, prop: string): string
	if value == nil then
		return "blend"
	end
	local key = normalizeName(value)
	if key == "blend" or key == "dither" then
		return key
	end
	error(`ui: {prop} must be "blend" or "dither" (got "{tostring(value)}")`, 0)
end

function Widget:_bgAlpha(color: { number }?): number
	local t = self.backgroundTransparency
	if t == nil then
		t = self.transparency
	end
	return resolveAlpha(color, t)
end

function Widget:_imageAlpha(color: { number }?): number
	return resolveAlpha(color, self.imageTransparency)
end

-- textColor / any text colour with the final alpha (textTransparency overrides it; a disabled widget is dimmed)
function Widget:_textRGBA(color: { number }?): { number }
	local c = color or self.textColor
	local a = resolveAlpha(c, self.textTransparency)
	return { c[1], c[2], c[3], a * (if self.disabled then 0.5 else 1) }
end

-- A texture value may be a Texture, or a file path (PNG / SVG) / SVG markup that is loaded for you.
local function looksSvg(s: string): boolean
	return string.find(s, "<", 1, true) ~= nil or string.find(string.lower(s), "%.svg$") ~= nil
end

-- the SVG a widget shows: its `svg` prop, or an SVG path / markup given as `texture` (Image) / `image` (Button)
function Widget:_svgSource(): any?
	local src = self.svg
	if src ~= nil and src ~= false then
		return src
	end
	local v
	if self.kind == "Image" then
		v = self.texture
	elseif self.kind == "Button" then
		v = self.image
	end
	if type(v) == "string" and looksSvg(v) then
		return v
	end
	return nil
end

-- Texture object for a texture-like prop value (nil while it is unavailable)
function Widget:_resolveTex(value: any): any?
	if type(value) ~= "string" then
		return value
	end
	if (self.kind == "Image" or self.kind == "Button") and looksSvg(value) then
		return nil -- drawn by the SVG path (rasterized at the widget's size)
	end
	local gui = self.gui
	if not gui then
		return nil
	end
	return gui:_pathTexture(value)
end

-- SVG (Image `svg`, Button `svg`): keep a texture rasterized at the widget's current pixel size.
function Widget:_svgRelease()
	local tex = self._svgTex
	if not tex then
		return
	end
	self._svgTex, self._svgBase, self._svgSize, self._svgWant = nil, nil, nil, nil
	tex:destroy()
end

function Widget:_svgSync(gui: any)
	local src = self:_svgSource()
	local isImage, isButton = self.kind == "Image", self.kind == "Button"
	if src == nil or not (isImage or isButton) then
		self:_svgRelease()
		return
	end
	local doc = gui:_svgDoc(src)
	if not doc then
		return
	end
	local dw, dh = doc.width, doc.height
	local w, h = self.aw, self.ah
	local tw, th
	local stretch = false
	if isImage then
		if w < 1 or h < 1 then
			return
		end
		if self.fit == "contain" then
			local k = math.min(w / dw, h / dh)
			tw, th = dw * k, dh * k
		elseif self.fit == "cover" then
			local k = math.max(w / dw, h / dh)
			tw, th = dw * k, dh * k
		else
			tw, th = w, h
			stretch = true
		end
	else
		local s = math.min(w, h) * (self.imageScale or 0.6)
		if s < 1 then
			return
		end
		local ta = dw / dh
		tw, th = s, s
		if ta > 1 then
			th = s / ta
		elseif ta < 1 then
			tw = s * ta
		end
	end
	local k = self.svgScale or 1
	tw, th = tw * k, th * k
	local big = math.max(tw, th)
	local cap = self.svgMaxSize or 2048
	if big > cap then
		tw, th = tw * cap / big, th * cap / big
	end
	tw, th = math.max(1, math.floor(tw + 0.5)), math.max(1, math.floor(th + 0.5))

	local colorKey = self.svgColor
	if type(colorKey) == "table" then
		colorKey = table.concat(colorKey, ",")
	end
	local baseKey = `{gui._svgEpoch or 0}|{tostring(doc)}|{tostring(colorKey)}|{if stretch then "s" else "f"}|{tostring(
		self.svgBleed
	)}`
	local sizeKey = `{tw}x{th}`
	if baseKey == self._svgBase and sizeKey == self._svgSize then
		return
	end
	if self._svgTex and baseKey == self._svgBase then
		-- only the size changed: wait until it has settled (a window drag would otherwise rasterize every frame)
		if self._svgWant ~= sizeKey then
			self._svgWant = sizeKey
			self._svgWantTime = gui.time
		end
		if gui.time - self._svgWantTime < (self.svgDelay or 0.12) then
			return
		end
	end

	local ok, rw, rh, rgba = pcall(imagelib.libs.svg.render, doc, tw, th, {
		color = self.svgColor,
		bleed = self.svgBleed,
		preserveAspectRatio = if stretch then "none" else nil,
	})
	self._svgBase, self._svgSize, self._svgWant = baseKey, sizeKey, nil -- (also after an error, so it is not retried every frame)
	if not ok then
		gui:_svgWarn("ui: svg: " .. tostring(rw))
		return
	end
	local tex = gui.renderer:createTexture(rw, rh, rgba)
	local old = self._svgTex
	self._svgTex = tex
	gui._svgLive[self] = true
	if old then
		old:destroy()
	end
end

function Widget:_drawText(r: any)
	local pad = self.textPadding or 0
	local innerW, innerH = self.aw - 2 * pad, self.ah - 2 * pad
	local scaledSize = if self.textScaled and innerW > 0 and innerH > 0 then self:_fitTextSize(innerW, innerH) else nil
	local layout = self:_textLayout(if self.wrap then innerW else nil, nil, scaledSize)
	local color = self:_textRGBA(self.textColor)
	self.gui.text:draw(
		r,
		layout,
		self.ax + pad,
		self.ay + pad,
		innerW,
		innerH,
		color,
		self.align,
		self.valign,
		self:_smoothText()
	)
end

--------------------------------------------------------------------------
-- TextBox (editable text)
--------------------------------------------------------------------------

local KEY = {
	Enter = 257,
	Escape = 256,
	Backspace = 259,
	Delete = 261,
	Right = 262,
	Left = 263,
	Down = 264,
	Up = 265,
	Home = 268,
	End = 269,
	KpEnter = 335,
	A = 65,
	C = 67,
	V = 86,
	X = 88,
}

local function isWordChar(cp: number): boolean
	return cp ~= 32 and cp ~= 10 and cp ~= 9 and cp ~= 13
end

local function wordLeft(cps: { number }, c: number): number
	local i = c
	while i > 0 and not isWordChar(cps[i]) do
		i -= 1
	end
	while i > 0 and isWordChar(cps[i]) do
		i -= 1
	end
	return i
end

local function wordRight(cps: { number }, c: number): number
	local n, i = #cps, c
	while i < n and not isWordChar(cps[i + 1]) do
		i += 1
	end
	while i < n and isWordChar(cps[i + 1]) do
		i += 1
	end
	return i
end

-- Geometry shared by drawing and mouse hit-testing.
function Widget:_boxGeometry(): any
	local pad = self.textPadding or 0
	local ix, iy, iw, ih = self.ax + pad, self.ay + pad, self.aw - 2 * pad, self.ah - 2 * pad
	local layout = self:_textLayout(if self.multiline then math.max(iw, 1) else nil)
	local free = ih - layout.height
	local voff = 0
	if free > 0 then
		if self.valign == "middle" then
			voff = free / 2
		elseif self.valign == "bottom" then
			voff = free
		end
	end
	return { ix = ix, iy = iy, iw = iw, ih = ih, layout = layout, W = math.max(iw, layout.width + 2), voff = voff }
end

function Widget:_cps(): { number }
	return textlib.codepoints(tostring(self.text or ""))
end

function Widget:_selRange(): (number?, number?)
	return math.min(self.caret, self.selAnchor), math.max(self.caret, self.selAnchor)
end

function Widget:_moveCaret(c: number, extend: boolean, keepGoal: boolean?)
	self.caret = c
	if not extend then
		self.selAnchor = c
	end
	if not keepGoal then
		self._goalX = nil
	end
	self._follow = true
	self._blinkT = self.gui.time
end

function Widget:_setText(cps: { number }, caret: number)
	self.text = textlib.fromCodepoints(cps)
	self.caret, self.selAnchor = caret, caret
	self._goalX = nil
	self._follow = true
	self._blinkT = self.gui.time
	if self.onChanged then
		self.onChanged(self, self.text)
	end
end

-- Replaces characters (a, b] with `ins` and puts the caret after the inserted text.
function Widget:_replaceRange(cps: { number }, a: number, b: number, ins: { number })
	local out = table.create(#cps - (b - a) + #ins)
	table.move(cps, 1, a, 1, out)
	table.move(ins, 1, #ins, a + 1, out)
	table.move(cps, b + 1, #cps, a + #ins + 1, out)
	self:_setText(out, a + #ins)
end

function Widget:_insert(str: string)
	if not self.editable then
		return
	end
	local clean: { number } = {}
	for _, cp in textlib.codepoints(str) do
		local keep: number? = cp
		if cp == 13 or cp == 127 then
			keep = nil
		elseif cp == 10 and not self.multiline then
			keep = 32
		elseif cp < 32 and cp ~= 10 and cp ~= 9 then
			keep = nil
		end
		if keep and self.filter and not self.filter(utf8.char(keep)) then
			keep = nil
		end
		if keep then
			table.insert(clean, keep)
		end
	end
	local cps = self:_cps()
	local n = #cps
	local c, an = math.clamp(self.caret, 0, n), math.clamp(self.selAnchor, 0, n)
	local a, b = math.min(c, an), math.max(c, an)
	if self.maxLength then
		local room = math.max(0, self.maxLength - (n - (b - a)))
		for i = #clean, room + 1, -1 do
			clean[i] = nil
		end
	end
	if #clean == 0 and a == b then
		return
	end
	self:_replaceRange(cps, a, b, clean)
end

function Widget:_onKey(key: number, mods: number)
	local gui = self.gui
	local shift = bit32.btest(mods, 1)
	local cmd = bit32.btest(mods, 2) or bit32.btest(mods, 8) -- Ctrl or Super/Cmd
	local byWord = bit32.btest(mods, 2) or bit32.btest(mods, 4) -- Ctrl or Alt
	local cps = self:_cps()
	local n = #cps
	self.caret, self.selAnchor = math.clamp(self.caret, 0, n), math.clamp(self.selAnchor, 0, n)
	local a, b = self:_selRange()
	local editable = self.editable

	if key == KEY.Escape then
		gui:_setFocus(nil)
	elseif cmd and key == KEY.A then
		self.selAnchor = 0
		self:_moveCaret(n, true)
	elseif cmd and (key == KEY.C or key == KEY.X) then
		if a ~= b then
			gui.window:setClipboard(textlib.fromCodepoints(cps, a + 1, b))
			if key == KEY.X and editable then
				self:_replaceRange(cps, a, b, {})
			end
		end
	elseif cmd and key == KEY.V then
		if editable then
			local clip = gui.window:getClipboard()
			if clip and clip ~= "" then
				self:_insert(clip)
			end
		end
	elseif key == KEY.Backspace and editable then
		if a ~= b then
			self:_replaceRange(cps, a, b, {})
		elseif self.caret > 0 then
			self:_replaceRange(cps, if byWord then wordLeft(cps, self.caret) else self.caret - 1, self.caret, {})
		end
	elseif key == KEY.Delete and editable then
		if a ~= b then
			self:_replaceRange(cps, a, b, {})
		elseif self.caret < n then
			self:_replaceRange(cps, self.caret, if byWord then wordRight(cps, self.caret) else self.caret + 1, {})
		end
	elseif key == KEY.Left then
		if a ~= b and not shift then
			self:_moveCaret(a, false)
		else
			self:_moveCaret(if byWord then wordLeft(cps, self.caret) else math.max(0, self.caret - 1), shift)
		end
	elseif key == KEY.Right then
		if a ~= b and not shift then
			self:_moveCaret(b, false)
		else
			self:_moveCaret(if byWord then wordRight(cps, self.caret) else math.min(n, self.caret + 1), shift)
		end
	elseif key == KEY.Home or key == KEY.End then
		local target
		if cmd then
			target = if key == KEY.Home then 0 else n
		else
			local layout = self:_boxGeometry().layout
			local _cx, _cy, li = gui.text:caretPosition(layout, self.caret)
			local first, last = gui.text:lineBounds(layout, li)
			target = if key == KEY.Home then first else last
		end
		self:_moveCaret(target, shift)
	elseif (key == KEY.Up or key == KEY.Down) and self.multiline then
		local layout = self:_boxGeometry().layout
		local x, _, li = gui.text:caretPosition(layout, self.caret)
		self._goalX = self._goalX or x
		local target
		if key == KEY.Up then
			target = if li <= 1 then 0 else gui.text:caretOnLine(layout, li - 1, self._goalX)
		else
			target = if li >= #layout.lines then n else gui.text:caretOnLine(layout, li + 1, self._goalX)
		end
		self:_moveCaret(target, shift, true)
	elseif key == KEY.Enter or key == KEY.KpEnter then
		if self.multiline and editable then
			self:_insert("\n")
		elseif self.onSubmit then
			self.onSubmit(self, self.text)
		end
	end
end

-- Caret index under a window position.
function Widget:_pointToCaret(mx: number, my: number): number
	local g = self:_boxGeometry()
	local layout = g.layout
	local ly = my - (g.iy - self._sy) - g.voff
	local li = math.clamp(math.floor(ly / layout.lineHeight) + 1, 1, #layout.lines)
	local hoff = self.gui.text.alignOffset(layout.lines[li].width, g.W, self.align)
	return self.gui.text:caretOnLine(layout, li, mx - (g.ix - self._sx) - hoff)
end

function Widget:_drawTextBox(r: any)
	local gui = self.gui
	local g = self:_boxGeometry()
	if g.iw <= 0 or g.ih <= 0 then
		return
	end
	local layout, engine = g.layout, gui.text
	local focused = gui.focus == self
	local n = layout.n
	self.caret, self.selAnchor = math.clamp(self.caret, 0, n), math.clamp(self.selAnchor, 0, n)

	local maxSX = if self.multiline then 0 else math.max(0, layout.width + 2 - g.iw)
	local maxSY = if self.multiline then math.max(0, layout.height - g.ih) else 0
	self._maxSY = maxSY
	if focused and self._follow then -- keep the caret visible after it moved
		self._follow = false
		local cx, cy = engine:caretPosition(layout, self.caret)
		if self.multiline then
			if cy + layout.lineHeight - self._sy > g.ih then
				self._sy = cy + layout.lineHeight - g.ih
			end
			if cy - self._sy < 0 then
				self._sy = cy
			end
		else
			if cx - self._sx > g.iw - 2 then
				self._sx = cx - g.iw + 2
			end
			if cx - self._sx < 0 then
				self._sx = cx
			end
		end
	end
	self._sx, self._sy = math.clamp(self._sx, 0, maxSX), math.clamp(self._sy, 0, maxSY)

	local ox, oy = g.ix - self._sx, g.iy - self._sy + g.voff
	r:pushClip(g.ix, g.iy, g.iw, g.ih)

	if focused and self.selAnchor ~= self.caret then
		local sc = self.selectionColor
		for _, rc in
			engine:selectionRects(layout, math.min(self.caret, self.selAnchor), math.max(self.caret, self.selAnchor))
		do
			local hoff = engine.alignOffset(layout.lines[rc[5]].width, g.W, self.align)
			r:quad(ox + hoff + rc[1], oy + rc[2], rc[3], rc[4], sc[1], sc[2], sc[3], sc[4] or 1)
		end
	end

	if n > 0 then
		engine:draw(
			r,
			layout,
			ox,
			oy,
			g.W,
			layout.height,
			self:_textRGBA(self.textColor),
			self.align,
			"top",
			self:_smoothText()
		)
	elseif self.placeholder and self.placeholder ~= "" then
		local pl = self:_textLayout(if self.multiline then math.max(g.iw, 1) else nil, self.placeholder)
		engine:draw(
			r,
			pl,
			g.ix,
			oy,
			g.iw,
			pl.height,
			self:_textRGBA(self.placeholderColor),
			self.align,
			"top",
			self:_smoothText()
		)
	end

	if focused and self.editable and (gui.time - (self._blinkT or 0)) % 1.06 < 0.53 then
		local cx, cy, li = engine:caretPosition(layout, self.caret)
		local hoff = engine.alignOffset(layout.lines[li].width, g.W, self.align)
		local cc = self.caretColor
		if cc == nil then
			cc = self:_textRGBA(self.textColor)
		end
		r:quad(
			math.floor(ox + hoff + cx),
			oy + cy,
			math.max(1, math.floor(layout.size / 14 + 0.5)),
			layout.lineHeight,
			cc[1],
			cc[2],
			cc[3],
			cc[4] or 1
		)
	end
	r:popClip()
end

function Widget:focus()
	if self.gui then
		self.gui:_setFocus(self)
	else
		self._wantFocus = true
	end
end

function Widget:blur()
	self._wantFocus = nil
	if self.gui and self.gui.focus == self then
		self.gui:_setFocus(nil)
	end
end

function Widget:isFocused(): boolean
	return self.gui ~= nil and self.gui.focus == self
end

-- Replaces the content without firing onChanged; the caret moves to the end.
function Widget:setText(str: string)
	self.text = tostring(str)
	local n = #self:_cps()
	self.caret, self.selAnchor = n, n
	self._follow = true
end

function Widget:selectAll()
	self.selAnchor = 0
	self.caret = #self:_cps()
	self._follow = true
end

local function rawChildSize(c: any, parent: any, forcedW: number?): (number?, number?)
	if c.autoSize then
		return c:_resolveSize(parent, forcedW)
	end
	return udim(c.size, parent.aw, parent.ah)
end

-- effects.aspectRatio = { value = width / height, type = "fitWithinMaxSize" | "scaleWithParentSize", dominantAxis = "width" | "height" }
-- (or just the number). Works like Roblox's UIAspectRatioConstraint; w, h are the size the widget would have without it.
--   fitWithinMaxSize (default):  the largest box with that ratio that fits inside w x h.
--   scaleWithParentSize:         the dominant axis keeps the size from `size` (it follows the parent when that size uses scale)
--                                and the other axis is derived from it, so the widget may grow beyond w x h on the other axis.
local function applyAspectRatio(ar: any, w: number, h: number): (number, number)
	local value, kind, axis = ar, "fitwithinmaxsize", "width"
	if type(ar) == "table" then
		value = ar.value
		if ar.type ~= nil then
			kind = normalizeName(ar.type)
		end
		if ar.dominantAxis ~= nil then
			axis = normalizeName(ar.dominantAxis)
		end
	end
	if type(value) ~= "number" or not (value > 0) then
		error("ui: effects.aspectRatio.value must be a number greater than 0 (width / height)", 0)
	end
	if kind ~= "fitwithinmaxsize" and kind ~= "scalewithparentsize" then
		error(
			`ui: effects.aspectRatio.type must be "fitWithinMaxSize" or "scaleWithParentSize" (got "{tostring(ar.type)}")`,
			0
		)
	end
	if axis ~= "width" and axis ~= "height" then
		error(`ui: effects.aspectRatio.dominantAxis must be "width" or "height" (got "{tostring(ar.dominantAxis)}")`, 0)
	end
	if kind == "fitwithinmaxsize" then
		if w / value <= h then
			return w, w / value
		end
		return h * value, h
	end
	if axis == "width" then
		return w, w / value
	end
	return h * value, h
end

-- every kind of effect a widget can carry (`effects` prop); later effects slot in here
local function applyEffects(c: any, w: number, h: number): (number, number)
	local fx = c.effects
	if fx == nil then
		return w, h
	end
	if fx.aspectRatio ~= nil then
		w, h = applyAspectRatio(fx.aspectRatio, w, h)
	end
	return w, h
end

local function childSize(c: any, parent: any, forcedW: number?): (number?, number?)
	local w, h = rawChildSize(c, parent, forcedW)
	return applyEffects(c, w, h)
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

-- layout.horizontalAlignment ("Left" | "Center" | "Right") / layout.verticalAlignment ("Top" | "Center" | "Bottom") -> 0 / 0.5 / 1
local function alignFraction(value: any, horizontal: boolean): number
	if value == nil then
		return 0
	end
	local key = string.lower(tostring(value))
	if key == "center" or key == "middle" then
		return 0.5
	elseif horizontal and key == "left" or not horizontal and key == "top" then
		return 0
	elseif horizontal and key == "right" or not horizontal and key == "bottom" then
		return 1
	end
	error(
		if horizontal
			then `ui: layout.horizontalAlignment must be "Left", "Center" or "Right" (got "{tostring(value)}")`
			else `ui: layout.verticalAlignment must be "Top", "Center" or "Bottom" (got "{tostring(value)}")`,
		0
	)
end

-- effects.listLayout.horizontalFlex / verticalFlex: how the free space along the flow direction is shared (UIFlexAlignment)
local FLEX: { [string]: string } =
	{ none = "none", fill = "fill", spacebetween = "between", spacearound = "around", spaceevenly = "evenly" }
-- effects.listLayout.itemLineAlignment: where each item sits across the flow direction (UIListLayout.ItemLineAlignment)
local ITEM_LINE: { [string]: any } = { automatic = false, start = 0, center = 0.5, ["end"] = 1, stretch = "stretch" }

-- UDim-style value: a number (pixels) or { scale, offset }
local function udimValue(v: any, base: number): number
	if v == nil then
		return 0
	elseif type(v) == "number" then
		return v
	end
	return (v[1] or 0) * base + (v[2] or 0)
end

-- effects.padding (UIPadding): a number (all four sides, pixels) or { left, right, top, bottom }, each a number or { scale, offset }.
-- left / right scale with the widget's width, top / bottom with its height.
local function paddingSides(p: any, W: number, H: number): (number, number, number, number)
	if type(p) == "number" then
		return p, p, p, p
	elseif type(p) ~= "table" then
		error("ui: effects.padding must be a number or a table { left, right, top, bottom }", 0)
	end
	return udimValue(p.left, W), udimValue(p.right, W), udimValue(p.top, H), udimValue(p.bottom, H)
end

-- Normalised list layout of a widget, or nil when it has none. `effects.listLayout` (Roblox UIListLayout) wins; the older `layout`
-- table is still understood (its `padding` is the inner padding, its `gap` the spacing).
--   cfg = { horizontal, gap (UDim value), inset (only the older `layout` form has one), wrap, ha, va, stretch, cross (0 / 0.5 / 1 | nil), flex, sort }
local function listConfig(w: any): any
	local le = if w.effects then w.effects.listLayout else nil
	if le == true then
		le = {}
	end
	if le then
		local dir = if le.fillDirection ~= nil then le.fillDirection else le.direction
		local dirName = if dir == nil then "vertical" else normalizeName(dir)
		if dirName ~= "vertical" and dirName ~= "horizontal" then
			error(`ui: effects.listLayout.fillDirection must be "Vertical" or "Horizontal" (got "{tostring(dir)}")`, 0)
		end
		local horizontal = dirName == "horizontal"

		local line = false
		if le.itemLineAlignment ~= nil then
			line = ITEM_LINE[normalizeName(le.itemLineAlignment)]
			if line == nil then
				error(
					`ui: effects.listLayout.itemLineAlignment must be "Automatic", "Start", "Center", "End" or "Stretch" (got "{tostring(
						le.itemLineAlignment
					)}")`,
					0
				)
			end
		end

		local function flexOf(value: any, prop: string): string
			if value == nil then
				return "none"
			end
			local f = FLEX[normalizeName(value)]
			if f == nil then
				error(
					`ui: effects.listLayout.{prop} must be "None", "Fill", "SpaceBetween", "SpaceAround" or "SpaceEvenly" (got "{tostring(
						value
					)}")`,
					0
				)
			end
			return f
		end
		local flexH, flexV = flexOf(le.horizontalFlex, "horizontalFlex"), flexOf(le.verticalFlex, "verticalFlex")
		-- along the flow direction every mode applies; across it only "Fill" does (= every item as wide / tall as the inner area)
		local flex = if horizontal then flexH else flexV
		local crossFlex = if horizontal then flexV else flexH

		-- sortOrder: "LayoutOrder" (default; ties keep insertion order) | "Name" | function(a, b) -> boolean (a before b)
		local sort = le.sortOrder
		if sort ~= nil and type(sort) ~= "function" then
			local key = normalizeName(sort)
			if key ~= "layoutorder" and key ~= "name" then
				error(
					`ui: effects.listLayout.sortOrder must be "LayoutOrder", "Name" or a function (got "{tostring(sort)}")`,
					0
				)
			end
			sort = key
		end

		local wrapValue = if le.wraps ~= nil then le.wraps else le.wrap
		return {
			horizontal = horizontal,
			gap = le.padding,
			inset = 0,
			wrap = wrapValue == true,
			ha = alignFraction(le.horizontalAlignment, true),
			va = alignFraction(le.verticalAlignment, false),
			stretch = line == "stretch" or crossFlex == "fill",
			cross = if type(line) == "number" then line else nil,
			flex = flex,
			sort = sort or "layoutorder",
		}
	end

	local old = w.layout
	if old then
		return {
			horizontal = old.direction ~= nil and normalizeName(old.direction) == "horizontal",
			gap = old.gap,
			inset = old.padding or 0,
			wrap = old.wrap == true,
			ha = alignFraction(old.horizontalAlignment, true),
			va = alignFraction(old.verticalAlignment, false),
			stretch = old.stretch == true,
			cross = nil,
			flex = "none",
			sort = false,
		}
	end
	return nil
end

-- children in layout order (cfg.sort: "layoutorder" | "name" | function | false); ties keep insertion order
local function orderedChildren(kids: { any }, sort: any): { any }
	if not sort then
		return kids
	end
	if sort == "layoutorder" then
		local first = kids[1] and kids[1].LayoutOrder or 0
		local differs = false
		for _, c in kids do
			if (c.LayoutOrder or 0) ~= first then
				differs = true
				break
			end
		end
		if not differs then
			return kids
		end
	end
	local list = {}
	for i, c in kids do
		list[i] = { c = c, i = i }
	end
	table.sort(list, function(a, b)
		local ca, cb = a.c, b.c
		if sort == "layoutorder" then
			local oa, ob = ca.LayoutOrder or 0, cb.LayoutOrder or 0
			if oa ~= ob then
				return oa < ob
			end
		elseif sort == "name" then
			local na, nb = tostring(ca.name or ""), tostring(cb.name or "")
			if na ~= nb then
				return na < nb
			end
		else
			if sort(ca, cb) then
				return true
			elseif sort(cb, ca) then
				return false
			end
		end
		return a.i < b.i
	end)
	local out = table.create(#list)
	for i, e in list do
		out[i] = e.c
	end
	return out
end

-- Lays out the children inside a W x H box whose origin is (ox, oy) and returns their extent (including layout
-- padding). With apply = false nothing is written (used to measure autoSize content). autoW/autoH say that the
-- axis is being measured, so stretch must not use it; limitW is the width at which wrapping rows break.
function Widget:_flowInner(
	W: number,
	H: number,
	limitW: number,
	ox: number,
	oy: number,
	apply: boolean,
	autoW: boolean,
	autoH: boolean
): (number?, number?)
	local scrolling = self.kind == "ScrollingFrame"
	local proxy = { aw = W, ah = H }
	local extentX, extentY = 0, 0
	local cfg = listConfig(self)

	if cfg then
		local pad = cfg.inset
		local horizontal = cfg.horizontal
		local gap = udimValue(cfg.gap, if horizontal then W else H)
		local wrap = cfg.wrap and horizontal
		local barSpace = if scrolling then BAR_W + 2 else 0
		local ha, va = cfg.ha, cfg.va
		local crossFrac = cfg.cross or (if horizontal then va else ha)
		local flex = cfg.flex
		local innerW, innerH = W - 2 * pad - barSpace, H - 2 * pad
		-- with flex "Fill" the scale part of an item's size along the flow direction is a share of the free space, not a size:
		-- while measuring and breaking rows it counts as 0 (the parent proxy has no extent along that axis)
		-- (only when that axis has a real size: an autoSize axis cannot have free space)
		local fillActive = flex == "fill" and not (if horizontal then autoW else autoH)
		local fillProxy = if fillActive then (if horizontal then { aw = 0, ah = H } else { aw = W, ah = 0 }) else nil

		-- 1. size every item and group the items into lines (one line, or several rows when wrapping)
		--    item = { c, w, h (final size), rw, rh (size before aspectRatio), weight, line, index }
		local lines = { { main = 0, cross = 0, count = 0, weight = 0, items = {} } } -- main / cross: extent along / across the flow
		for _, c in orderedChildren(self.children, cfg.sort) do
			if c.visible then
				c.gui = self.gui
				local forcedW = nil
				if cfg.stretch and not wrap and not horizontal and not autoW then
					forcedW = W - 2 * pad - barSpace
				end
				local weight = 0 -- flex "Fill": the scale part of the size along the flow direction
				if fillProxy then
					local size = c.size
					local auto = c.autoSize
						and string.find(tostring(c.autoSize), if horizontal then "x" else "y", 1, true)
					if not auto and type(size) == "table" and #size >= 4 then
						weight = math.max(0, if horizontal then size[1] else size[3])
					end
				end
				local rw, rh = rawChildSize(c, if weight > 0 then fillProxy else proxy, forcedW)
				if forcedW then
					rw = forcedW
				end
				if cfg.stretch and not wrap and horizontal and not autoH then
					rh = H - 2 * pad
				end
				local w, h = rw, rh
				if weight == 0 then
					w, h = applyEffects(c, rw, rh) -- an item that gets a share of the free space is sized in step 2
				end

				local line = lines[#lines]
				local pos = if line.count > 0 then line.main + gap else 0
				if wrap and line.count > 0 and pad + pos + w > limitW - pad - barSpace then
					line = { main = 0, cross = 0, count = 0, weight = 0, items = {} }
					table.insert(lines, line)
					pos = 0
				end
				line.main = pos + (if horizontal then w else h)
				line.cross = math.max(line.cross, if horizontal then h else w)
				line.count += 1
				line.weight += weight
				table.insert(
					line.items,
					{ c = c, w = w, h = h, rw = rw, rh = rh, weight = weight, line = line, index = line.count }
				)
			end
		end

		-- 2. flex "Fill": hand the free space of each line to its items (by scale weight, or equally when none has a scale part), then let
		--    aspectRatio act on the new size. An item whose ratio makes it end up with a different size along the flow direction than the share
		--    it was offered is frozen at that size and the space it did not use (or needs more of) is shared again among the other items, until
		--    nothing changes - so the other items always fill what is left, with no gap.
		if fillActive then
			local mainInner = if horizontal then innerW else innerH
			for _, line in lines do
				local equal = line.weight == 0
				local flexible = {}
				local fixedMain = gap * math.max(0, line.count - 1) -- gaps + items that do not take part
				for _, it in line.items do
					if equal or it.weight > 0 then
						it.share = if equal then 1 else it.weight
						it.frozen = false
						table.insert(flexible, it)
					else
						fixedMain += if horizontal then it.w else it.h
					end
				end
				for _round = 1, #flexible + 1 do
					local sumShare, taken = 0, 0
					for _, it in flexible do
						if it.frozen then
							taken += if horizontal then it.w else it.h
						else
							sumShare += it.share
							taken += if horizontal then it.rw else it.rh -- the offset part of the size
						end
					end
					if sumShare == 0 then
						break
					end
					local free = math.max(0, mainInner - fixedMain - taken)
					local changed = false
					for _, it in flexible do
						if not it.frozen then
							local offered = (if horizontal then it.rw else it.rh) + free * it.share / sumShare
							local w, h = it.rw, it.rh
							if horizontal then
								w = offered
							else
								h = offered
							end
							it.w, it.h = applyEffects(it.c, w, h)
							if math.abs((if horizontal then it.w else it.h) - offered) > 0.01 then
								it.frozen = true
								changed = true
							end
						end
					end
					if not changed then
						break
					end
				end
				local main, cross = 0, 0
				for i, it in line.items do
					main += (if horizontal then it.w else it.h) + (if i > 1 then gap else 0)
					cross = math.max(cross, if horizontal then it.h else it.w)
				end
				line.main, line.cross = main, cross
			end
		end

		-- 3. positions inside the padded box (alignment is added afterwards) and the extent
		local crossStart = pad
		for _, line in lines do
			local run = pad
			for _, it in line.items do
				if horizontal then
					it.x, it.y = run, crossStart
					run += it.w + gap
				else
					it.x, it.y = pad, run
					run += it.h + gap
				end
				extentX, extentY = math.max(extentX, it.x + it.w), math.max(extentY, it.y + it.h)
			end
			crossStart += line.cross + gap
		end

		if apply then
			-- wrapped rows are aligned as one block too (along the other axis)
			local blockDY = if wrap then math.max(0, innerH - (extentY - pad)) * va else 0
			for _, line in lines do
				local mainFree = math.max(0, (if horizontal then innerW else innerH) - line.main)
				for _, it in line.items do
					local w, h, index = it.w, it.h, it.index
					local mainOffset
					if flex == "none" or flex == "fill" then
						mainOffset = mainFree * (if horizontal then ha else va) -- after "Fill" only what aspectRatio left over
					else
						local n = line.count
						if flex == "between" then
							mainOffset = if n > 1 then mainFree / (n - 1) * (index - 1) else 0
						elseif flex == "around" then
							mainOffset = mainFree / n * (index - 0.5)
						else -- "evenly"
							mainOffset = mainFree / (n + 1) * index
						end
					end
					local dx, dy = 0, 0
					if horizontal then
						dx = mainOffset
						dy = math.max(0, (if wrap then line.cross else innerH) - h) * crossFrac + blockDY
					else
						dy = mainOffset
						dx = math.max(0, innerW - w) * crossFrac
					end
					it.c.aw, it.c.ah = w, h
					it.c.ax, it.c.ay = ox + it.x + math.floor(dx + 0.5), oy + it.y + math.floor(dy + 0.5)
				end
			end
		end
		extentX += pad
		extentY += pad
	else
		for _, c in self.children do
			if c.visible then
				c.gui = self.gui
				local w, h = childSize(c, proxy)
				local px, py = udim(c.position, W, H)
				local rx, ry = px - c.anchor[1] * w, py - c.anchor[2] * h
				if apply then
					c.aw, c.ah, c.ax, c.ay = w, h, ox + rx, oy + ry
				end
				extentX, extentY = math.max(extentX, rx + w), math.max(extentY, ry + h)
			end
		end
	end
	return extentX, extentY
end

-- effects.padding shrinks the box the children are laid out in; the returned extent includes the padding on both sides
-- (so autoSize hugs children + padding, and a ScrollingFrame's content includes the bottom padding).
function Widget:_flow(
	W: number,
	H: number,
	limitW: number,
	ox: number,
	oy: number,
	apply: boolean,
	autoW: boolean,
	autoH: boolean
): (number?, number?)
	local fx = self.effects
	local pad = if fx then fx.padding else nil
	if pad == nil then
		return self:_flowInner(W, H, limitW, ox, oy, apply, autoW, autoH)
	end
	local pl, pr, pt, pb = paddingSides(pad, W, H)
	local ex, ey = self:_flowInner(
		math.max(0, W - pl - pr),
		math.max(0, H - pt - pb),
		math.max(0, limitW - pl - pr),
		ox + pl,
		oy + pt,
		apply,
		autoW,
		autoH
	)
	return ex + pl + pr, ey + pt + pb
end

function Widget:_layoutChildren()
	local scrolling = self.kind == "ScrollingFrame"
	if scrolling then
		self.scrollY = math.clamp(self.scrollY, 0, math.max(0, self.contentH - self.ah))
	end
	local ox, oy = self.ax, self.ay - (if scrolling then self.scrollY else 0)
	local extentX, extentY = self:_flow(self.aw, self.ah, self.aw, ox, oy, true, false, false)

	if scrolling then
		self.contentW, self.contentH = extentX, extentY
	end
	for _, c in self.children do
		if c.visible then
			c.gui = self.gui
			if c._wantFocus then
				c._wantFocus = nil
				self.gui:_setFocus(c)
			end
			c:_layoutChildren()
		end
	end
end

--------------------------------------------------------------------------
-- Hit testing
--------------------------------------------------------------------------

local function inside(w: any, x: number, y: number): boolean
	return x >= w.ax and y >= w.ay and x < w.ax + w.aw and y < w.ay + w.ah
end

-- (hit testing follows the render order; see GUI:_pick)

--------------------------------------------------------------------------
-- Matrices (column-major, flat 16-arrays, index = col * 4 + row + 1)
--------------------------------------------------------------------------

local function mul(a: { number }, b: { number }): { number }
	local r = table.create(16, 0)
	for c = 0, 3 do
		for row = 0, 3 do
			local s = 0
			for k = 0, 3 do
				s += a[k * 4 + row + 1] * b[c * 4 + k + 1]
			end
			r[c * 4 + row + 1] = s
		end
	end
	return r
end

local function rotY(t: number): { number }
	local c, s = math.cos(t), math.sin(t)
	return { c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1 }
end

local function rotX(t: number): { number }
	local c, s = math.cos(t), math.sin(t)
	return { 1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1 }
end

local function translate(x: number, y: number, z: number): { number }
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end

local function scale(s: number): { number }
	return { s, 0, 0, 0, 0, s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1 }
end

-- Right-handed, depth 0..1, Y flipped for Vulkan clip space.
local function perspective(fovY: number, aspect: number, near: number, far: number): { number }
	local f = 1 / math.tan(fovY / 2)
	return {
		f / aspect,
		0,
		0,
		0,
		0,
		-f,
		0,
		0,
		0,
		0,
		far / (near - far),
		-1,
		0,
		0,
		(far * near) / (near - far),
		0,
	}
end

local LIGHT_VIEW = { 0.35, 0.6, 0.72 } -- towards the light, in view space (camera-fixed)
do
	local l = math.sqrt(LIGHT_VIEW[1] ^ 2 + LIGHT_VIEW[2] ^ 2 + LIGHT_VIEW[3] ^ 2)
	for i = 1, 3 do
		LIGHT_VIEW[i] /= l
	end
end

local function modelMatrices(view: any): ({ number }?, { number }?)
	local model = view.model
	local aspect = math.max(view.aw / math.max(view.ah, 1), 0.01)
	local half = math.atan(math.tan(view.fov / 2) * math.min(1, aspect))
	local dist = 1.15 / math.sin(half) / view.zoom

	local rot = mul(rotX(view.pitch), rotY(view.yaw))
	local m = mul(rot, mul(scale(1 / model.radius), translate(-model.center[1], -model.center[2], -model.center[3])))
	local proj = perspective(view.fov, aspect, 0.05, dist + 4)
	local mvp = mul(proj, mul(translate(0, 0, -dist), m))

	-- light direction in object space: R^T * L  (rot columns are at 1..3, 5..7, 9..11)
	local light = {}
	for i = 0, 2 do
		light[i + 1] = rot[i * 4 + 1] * LIGHT_VIEW[1] + rot[i * 4 + 2] * LIGHT_VIEW[2] + rot[i * 4 + 3] * LIGHT_VIEW[3]
	end
	return mvp, light
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function scrollbarGeometry(w: any): (number?, number?, number?, number?)
	local maxScroll = w.contentH - w.ah
	if maxScroll <= 0 or w.ah <= 0 then
		return nil
	end
	local trackX = w.ax + w.aw - BAR_W - 1
	local thumbH = math.max(24, w.ah * w.ah / w.contentH)
	local thumbY = w.ay + (w.scrollY / maxScroll) * (w.ah - thumbH)
	return trackX, thumbY, thumbH, maxScroll
end

-- highlight = { fillColor = {r,g,b}, fillTransparency = 0..1, outlineColor = {r,g,b}, outlineTransparency = 0..1, outlineThickness = px,
--               depthMode = "Occluded" | "AlwaysOnTop" }
-- (all optional; defaults: red fill at 0.5, white outline at 0, 2 px, "Occluded"). A transparency that is set overrides the colour's own alpha. false / nil = no highlight.
local function normalizeHighlight(h: any): any
	if not h then
		return nil
	end
	local fc, oc = h.fillColor or { 1, 0, 0 }, h.outlineColor or { 1, 1, 1 }
	local mode = normalizeName(h.depthMode or "Occluded")
	local onTop
	if mode == "occluded" then
		onTop = false
	elseif mode == "alwaysontop" then
		onTop = true
	else
		error(`ui: unknown highlight depthMode "{h.depthMode}" (use "Occluded" or "AlwaysOnTop")`, 0)
	end
	-- a transparency that is set overrides the colour's alpha; otherwise the colour's alpha is used (fill default: half transparent)
	local fa = if h.fillTransparency ~= nil
		then 1 - math.clamp(h.fillTransparency, 0, 1)
		elseif fc[4] ~= nil then fc[4]
		else 0.5
	local oa = if h.outlineTransparency ~= nil then 1 - math.clamp(h.outlineTransparency, 0, 1) else (oc[4] or 1)
	return {
		fill = { fc[1], fc[2], fc[3], fa },
		outline = { oc[1], oc[2], oc[3], oa },
		thickness = math.max(h.outlineThickness or 2, 0),
		onTop = onTop,
	}
end

-- Background, image, model and text of this widget (children are drawn separately, in z order).
function Widget:_drawBody(r: any, dt: number)
	local x, y, w, h = self.ax, self.ay, self.aw, self.ah
	local c = self.color
	local gui = self.gui

	if self.kind == "Image" then
		local bg = self.backgroundColor
		if bg then
			r:quad(x, y, w, h, bg[1], bg[2], bg[3], self:_bgAlpha(bg))
		end
		local tex = self._svgTex or self:_resolveTex(self.texture)
		if tex then
			local qx, qy, qw, qh, u0, v0, u1, v1 = x, y, w, h, 0, 0, 1, 1
			local ta, ba = tex.width / tex.height, w / math.max(h, 1)
			if self.fit == "contain" then
				if ta > ba then
					qh = w / ta
				else
					qw = h * ta
				end
				qx, qy = x + (w - qw) / 2, y + (h - qh) / 2
			elseif self.fit == "cover" then
				if ta > ba then
					local f = ba / ta
					u0, u1 = (1 - f) / 2, 1 - (1 - f) / 2
				else
					local f = ta / ba
					v0, v1 = (1 - f) / 2, 1 - (1 - f) / 2
				end
			end
			r:quad(qx, qy, qw, qh, c[1], c[2], c[3], self:_imageAlpha(c), tex, u0, v0, u1, v1, self:_interp())
		end
	else
		local col = c
		if self.kind == "Button" then
			if self.disabled then
				col = self.disabledColor
			elseif gui and gui.pressed == self and gui.hovered == self then
				col = self.pressedColor
			elseif gui and gui.hovered == self then
				col = self.hoverColor
			end
		end
		r:quad(x, y, w, h, col[1], col[2], col[3], self:_bgAlpha(col))
	end

	local icon = if self.kind == "Button" then (self._svgTex or self:_resolveTex(self.image)) else nil
	if icon then
		local s = math.min(w, h) * (self.imageScale or 0.6)
		local iw, ih = s, s
		local ta = icon.width / icon.height
		if ta > 1 then
			ih = s / ta
		elseif ta < 1 then
			iw = s * ta
		end
		local t = self.imageTint or { 1, 1, 1, 1 }
		r:quad(
			x + (w - iw) / 2,
			y + (h - ih) / 2,
			iw,
			ih,
			t[1],
			t[2],
			t[3],
			t[4] or 1,
			icon,
			nil,
			nil,
			nil,
			nil,
			self:_interp()
		)
	end

	if self.kind == "ModelView" and self.model then
		if not (gui and gui.dragModel == self) then
			self.yaw += (self.autoRotate or 0) * dt
		end
		local mvp, light = modelMatrices(self)
		local mc = self.modelColor
		r:drawModel(
			self.model,
			x,
			y,
			w,
			h,
			mvp,
			light,
			{ mc[1], mc[2], mc[3], self:_imageAlpha(mc) },
			self:_resolveTex(self.texture),
			self.doubleSided,
			self:_interp(),
			methodName(self.modelTransparencyMethod, "modelTransparencyMethod"),
			normalizeHighlight(self.highlight)
		)
	end

	if self.kind == "TextBox" then
		self:_drawTextBox(r)
	elseif self.text ~= nil and self.text ~= "" then
		self:_drawText(r)
	end
end

-- Scrollbar and border; drawn after the body (and, with ZIndexBehavior "Sibling", after the children).
function Widget:_drawOverlay(r: any)
	local x, y, w, h = self.ax, self.ay, self.aw, self.ah
	local gui = self.gui

	if self.kind == "ScrollingFrame" then
		local tx, ty, th = scrollbarGeometry(self)
		if tx then
			local tc, hc = self.scrollbarColor, self.thumbColor
			r:quad(tx, y, BAR_W, h, tc[1], tc[2], tc[3], tc[4] or 1)
			r:quad(tx, ty, BAR_W, th, hc[1], hc[2], hc[3], hc[4] or 1)
		end
	end

	local b = self.border
	if self.kind == "TextBox" and gui and gui.focus == self then
		b = { width = (b and b.width) or 2, color = self.focusColor }
	end
	if b and b.width and b.width > 0 then
		local bc, bw = b.color or { 1, 1, 1, 0.3 }, b.width
		local ba = bc[4] or 1
		r:quad(x, y, w, bw, bc[1], bc[2], bc[3], ba)
		r:quad(x, y + h - bw, w, bw, bc[1], bc[2], bc[3], ba)
		r:quad(x, y + bw, bw, h - 2 * bw, bc[1], bc[2], bc[3], ba)
		r:quad(x + w - bw, y + bw, bw, h - 2 * bw, bc[1], bc[2], bc[3], ba)
	end
end

--------------------------------------------------------------------------
-- GUI (input + update + draw)
--------------------------------------------------------------------------

local GUI = {}
GUI.__index = GUI

function ui.new(window: any, renderer: any): any
	local gui: any = setmetatable({
		window = window,
		renderer = renderer,
		mx = -1,
		my = -1,
		dt = 0,
		time = 0,
		root = create("Frame", { color = { 0, 0, 0, 0 }, ZIndexBehavior = "Sibling" }),
		text = textlib.new(renderer),
		_svgDocs = {},
		_svgLive = {},
		_svgEpoch = 0,
		_textures = {},
	}, GUI)
	gui.root.gui = gui

	local function toPixels(x: number, y: number): (number?, number?)
		local ww = window:getSize()
		local fw = window:getFramebufferSize()
		local s = if ww > 0 then fw / ww else 1
		return x * s, y * s
	end

	local lastX, lastY = 0, 0

	window:connect("cursorPos", function(_, x, y)
		gui.mx, gui.my = toPixels(x, y)
		local dx, dy = gui.mx - lastX, gui.my - lastY
		lastX, lastY = gui.mx, gui.my
		local dm = gui.dragModel
		if dm then
			dm.yaw += dx * 0.01
			dm.pitch = math.clamp(dm.pitch + dy * 0.01, -1.5, 1.5)
		end
		local dtx = gui.dragText
		if dtx then
			dtx:_moveCaret(dtx:_pointToCaret(gui.mx, gui.my), true)
		end
		local ds = gui.dragScroll
		if ds then
			local w = ds.widget
			local _tx, _ty, thumbH, maxScroll = scrollbarGeometry(w)
			if maxScroll then
				local travel = w.ah - thumbH
				if travel > 0 then
					w:setScroll(ds.startScroll + (gui.my - ds.startY) / travel * maxScroll)
				end
			end
		end
	end)

	window:connect("mouseButton", function(_, button, action, mods)
		if button ~= 0 then
			return
		end
		if action == 1 then -- press
			local target = gui:_pick(gui.mx, gui.my)
			gui.pressed = target
			if target and target.kind == "TextBox" and target.editable then
				gui:_setFocus(target)
				target:_moveCaret(target:_pointToCaret(gui.mx, gui.my), bit32.btest(mods or 0, 1))
				gui.dragText = target
			elseif gui.focus then
				gui:_setFocus(nil)
			end
			if target then
				if target.kind == "ModelView" then
					gui.dragModel = target
				elseif target.kind == "ScrollingFrame" then
					local tx, ty, th, maxScroll = scrollbarGeometry(target)
					if tx and gui.mx >= tx then
						if gui.my >= ty and gui.my <= ty + th then
							gui.dragScroll = { widget = target, startY = gui.my, startScroll = target.scrollY }
						else -- click on track: jump
							local travel = target.ah - th
							if travel > 0 then
								target:setScroll((gui.my - target.ay - th / 2) / travel * maxScroll)
							end
						end
					end
				end
				if target.onPress and not target.disabled then
					target.onPress(target)
				end
			end
		else -- release
			local p = gui.pressed
			gui.pressed, gui.dragModel, gui.dragScroll, gui.dragText = nil, nil, nil, nil
			if p then
				if p.onRelease and not p.disabled then
					p.onRelease(p)
				end
				if p.kind == "Button" and not p.disabled and p.onClick and gui:_pick(gui.mx, gui.my) == p then
					p.onClick(p)
				end
			end
		end
	end)

	window:connect("scroll", function(_, _dx, dy)
		local w = gui:_pick(gui.mx, gui.my)
		while w do
			if w.kind == "ModelView" and w.zoomable then
				w.zoom = math.clamp(w.zoom * (1 + dy * 0.1), 0.3, 4)
				return
			elseif w.kind == "TextBox" and w.multiline and (w._maxSY or 0) > 0 then
				w._sy = math.clamp(w._sy - dy * 48, 0, w._maxSY)
				return
			elseif w.kind == "ScrollingFrame" and w.contentH > w.ah then
				w:setScroll(w.scrollY - dy * w.scrollSpeed)
				return
			end
			w = w.parent
		end
	end)

	window:connect("char", function(_, cp)
		local f = gui.focus
		if f and f.editable then
			f:_insert(utf8.char(cp))
		end
	end)

	window:connect("key", function(_, key, _scancode, action, mods)
		local f = gui.focus
		if f and action ~= 0 then
			f:_onKey(key, mods)
		end
	end)

	return gui
end

-- A font reference is a path to a .ttf/.otf file or a font.luau object.
function GUI:_resolveFont(f: any): any
	if type(f) == "string" then
		return fontlib.loadFile(f)
	end
	return f
end

-- Sets the font used by every widget that has no `font` of its own (path or font object).
function GUI:setDefaultFont(f: any)
	self.defaultFont = self:_resolveFont(f)
end

-- Moves keyboard focus (nil clears it); fires onBlur / onFocus.
function GUI:_setFocus(w: any?)
	if self.focus == w then
		return
	end
	local old = self.focus
	self.focus = w
	if old then
		old.selAnchor = old.caret
		if old.onBlur then
			old.onBlur(old)
		end
	end
	if w then
		w._follow = true
		w._goalX = nil
		w._blinkT = self.time
		if w.onFocus then
			w.onFocus(w)
		end
	end
end

local function reachable(w: any, root: any): boolean
	local cur = w
	while cur do
		if not cur.visible then
			return false
		end
		if cur == root then
			return true
		end
		cur = cur.parent
	end
	return false
end

local function intersectRects(a: { number }, x: number, y: number, w: number, h: number): { number }
	local x0, y0 = math.max(a[1], x), math.max(a[2], y)
	local x1, y1 = math.min(a[1] + a[3], x + w), math.min(a[2] + a[4], y + h)
	return { x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0) }
end

-- Children in drawing order for ZIndexBehavior "Sibling": ascending ZIndex, ties keep insertion order.
local function childrenByZ(w: any): { any }
	local kids = w.children
	local n = #kids
	if n < 2 then
		return kids
	end
	local first = kids[1].ZIndex or 0
	local uniform = true
	for i = 2, n do
		if (kids[i].ZIndex or 0) ~= first then
			uniform = false
			break
		end
	end
	if uniform then
		return kids
	end
	local order = {}
	for i, c in kids do
		order[i] = { c, c.ZIndex or 0, i }
	end
	table.sort(order, function(p, q)
		if p[2] ~= q[2] then
			return p[2] < q[2]
		end
		return p[3] < q[3]
	end)
	local out = {}
	for i, e in order do
		out[i] = e[1]
	end
	return out
end

--[[
	Recomputes the render order (also used for hit testing) and every widget's effective clip rectangle.

	ZIndexBehavior controls how a widget's descendants are ordered. Set it on the root (applies to everything) or on any
	widget (applies to that widget's subtree); a widget without one inherits from its parent, the root defaults to "Sibling".
		"Sibling"  ZIndex orders a widget relative to its siblings; a widget and all its descendants stay together and
		           children always draw above their parent.
		"Global"   ZIndex orders all widgets of the subtree against each other, overriding the order implied by the
		           hierarchy; ties fall back to depth (deeper = on top), then sibling order. A child with a lower ZIndex
		           than its parent draws *behind* it.
	A widget whose ZIndexBehavior differs from the one it would inherit forms its own block: the block is placed among
	its siblings by the widget's ZIndex and its inside is ordered by its own behavior.
]]
function GUI:_buildOrder()
	local root = self.root
	local bodies: { any } = {} -- widgets, bottom to top (hit testing)
	local drawW: { any } = {} -- draw list: widget ...
	local drawP: { number } = {} -- ... and phase (1 = body, 2 = overlay)

	local function behaviorOf(w: any, inherited: string): string
		local b = w.ZIndexBehavior
		if b == nil then
			return inherited
		end
		if b ~= "Sibling" and b ~= "Global" then
			error(`ui: ZIndexBehavior must be "Sibling" or "Global" (got {tostring(b)})`, 0)
		end
		return b
	end
	local function pushBody(w: any)
		table.insert(bodies, w)
		table.insert(drawW, w)
		table.insert(drawP, 1)
	end
	local function pushOverlay(w: any)
		table.insert(drawW, w)
		table.insert(drawP, 2)
	end
	local function childClipFor(w: any, clip: { number }): { number }
		if w.clip or w.kind == "ScrollingFrame" then
			return intersectRects(clip, w.ax, w.ay, w.aw, w.ah)
		end
		return clip
	end
	local function culled(parent: any, c: any): boolean -- clipping parents skip children entirely outside them
		return (parent.clip or parent.kind == "ScrollingFrame")
			and not (
				c.ax < parent.ax + parent.aw
				and c.ax + c.aw > parent.ax
				and c.ay < parent.ay + parent.ah
				and c.ay + c.ah > parent.ay
			)
	end

	local emitBlock: (w: any, clip: { number }, behavior: string) -> ()

	-- `behavior` is the (already resolved) behavior that governs w's descendants.
	function emitBlock(w: any, clip: { number }, behavior: string)
		w._clip = clip
		if behavior == "Sibling" then
			pushBody(w)
			local childClip = childClipFor(w, clip)
			for _, c in childrenByZ(w) do
				if c.visible and not culled(w, c) then
					emitBlock(c, childClip, behaviorOf(c, behavior))
				end
			end
			pushOverlay(w)
			return
		end

		-- "Global": flatten the subtree, then sort by (ZIndex, depth, sibling order)
		local items: { { any } } = {}
		local seq = 0
		local function collect(d: any, dClip: { number }, depth: number)
			d._clip = dClip
			seq += 1
			table.insert(items, { d, d.ZIndex or 0, depth, seq, false, dClip })
			local childClip = childClipFor(d, dClip)
			for _, c in d.children do
				if c.visible and not culled(d, c) then
					local cb = behaviorOf(c, "Global")
					if cb ~= "Global" then -- nested context: placed as one block at its own ZIndex/depth
						seq += 1
						table.insert(items, { c, c.ZIndex or 0, depth + 1, seq, true, childClip })
					else
						collect(c, childClip, depth + 1)
					end
				end
			end
		end
		collect(w, clip, 0)
		table.sort(items, function(p, q)
			if p[2] ~= q[2] then
				return p[2] < q[2]
			end
			if p[3] ~= q[3] then
				return p[3] < q[3]
			end
			return p[4] < q[4]
		end)
		for _, it in items do
			if it[5] then
				emitBlock(it[1], it[6], behaviorOf(it[1], "Global"))
			else
				pushBody(it[1])
				pushOverlay(it[1])
			end
		end
	end

	emitBlock(root, { 0, 0, root.aw, root.ah }, behaviorOf(root, "Sibling"))
	self._bodies, self._drawW, self._drawP = bodies, drawW, drawP
end

-- Topmost interactive widget under a window position (respects render order and clipping).
function GUI:_pick(x: number, y: number): any?
	local bodies = self._bodies
	if not bodies then
		return nil
	end
	for i = #bodies, 1, -1 do
		local w = bodies[i]
		if w.interactive and inside(w, x, y) then
			local c = w._clip
			if x >= c[1] and y >= c[2] and x < c[1] + c[3] and y < c[2] + c[4] then
				return w
			end
		end
	end
	return nil
end

-- Loads (once) the PNG / SVG file at `path` as a texture; false after a failure (reported once)
function GUI:_pathTexture(path: string): any?
	local cache = self._textures
	local tex = cache[path]
	if tex == nil then
		local ok, result = pcall(function()
			if string.find(path, "<", 1, true) then
				return self.renderer:loadImage(path) -- SVG markup
			end
			return self.renderer:loadImage(zune.fs.readFileSync(path, true))
		end)
		if ok then
			tex = result
		else
			tex = false
			self:_svgWarn(`ui: could not load image "{path}": {tostring(result)}`)
		end
		cache[path] = tex
	end
	return tex or nil
end

-- Destroys the textures loaded from file paths so the files are read again the next time they are used.
function GUI:clearImageCache()
	for path, tex in self._textures do
		if tex then
			tex:destroy()
		end
		self._textures[path] = nil
	end
end

function GUI:_svgWarn(message: string)
	local out = rawget(_G, "warn") or print
	out(message)
end

-- SVG source (markup, file path or parsed document) -> parsed document (cached); nil when it cannot be read
function GUI:_svgDoc(src: any): any?
	if type(src) == "table" then
		return src
	end
	if type(src) ~= "string" then
		return nil
	end
	local cache = self._svgDocs
	local doc = cache[src]
	if doc == nil then
		local ok, result = pcall(function()
			local markup = src
			if not string.find(src, "<", 1, true) then
				markup = zune.fs.readFileSync(src)
			end
			return imagelib.libs.svg.parse(markup)
		end)
		if ok then
			doc = result
		else
			doc = false
			self:_svgWarn("ui: svg: " .. tostring(result))
		end
		cache[src] = doc
	end
	return doc or nil
end

-- Forgets parsed SVG files / markup (so changed files are read again) and redraws every SVG widget.
function GUI:clearSvgCache()
	table.clear(self._svgDocs)
	self._svgEpoch += 1
end

-- frees the textures of SVG widgets that were removed from the tree or lost their `svg`
function GUI:_svgSweep()
	local root = self.root
	for w in self._svgLive do
		local cur = w
		while cur.parent do
			cur = cur.parent
		end
		if cur ~= root or w:_svgSource() == nil then
			w:_svgRelease()
			self._svgLive[w] = nil
		end
	end
end

function GUI:update(dt: number)
	self.dt = dt
	self.time += dt
	if self.focus and not reachable(self.focus, self.root) then
		self:_setFocus(nil) -- the focused widget was removed or hidden
	end
	local root = self.root
	root.ax, root.ay = 0, 0
	root.aw, root.ah = self.renderer:getSize()
	root.gui = self
	root:_layoutChildren()
	self:_buildOrder()

	local bodies = self._bodies
	for i = 1, #bodies do
		local w = bodies[i]
		if w._svgTex ~= nil or w.svg ~= nil or type(w.texture) == "string" or type(w.image) == "string" then
			w:_svgSync(self)
		end
	end
	self:_svgSweep()

	local hovered = self:_pick(self.mx, self.my)
	if hovered ~= self.hovered then
		self.hovered = hovered
		if hovered and hovered.onHover then
			hovered.onHover(hovered)
		end
	end
end

function GUI:draw()
	local r, dt = self.renderer, self.dt
	local drawW, drawP = self._drawW, self._drawP
	if not drawW then
		return
	end
	for i = 1, #drawW do
		local w = drawW[i]
		r:setClipRect(w._clip)
		r:setQuadMethod(methodName(w.transparencyMethod, "transparencyMethod"))
		if drawP[i] == 1 then
			w:_drawBody(r, dt)
		else
			w:_drawOverlay(r)
		end
	end
end

--------------------------------------------------------------------------
-- App helper: window + renderer + gui + main loop
--------------------------------------------------------------------------

local App = {}
App.__index = App

export type AppOptions = {
	width: number?,
	height: number?,
	title: string?,
	resizable: boolean?,
	glfwPath: string?,
	renderer: any?,
	font: any?, -- default font: path to a .ttf/.otf file (or a font object)
	-- shaders: "folder"                                  folder with ui.vert ui.frag model.vert model.frag model_dither.frag
	--          { libraryPath = "shaderc_shared.dll",     where the shaderc library is (optional, searched automatically otherwise)
	--            shaders = "folder" | { modelFrag = "my/water.frag", ... } }   (optional; default: "shaders" beside renderer.luau)
	shaders: any?,
	ZIndexBehavior: string?, -- "Sibling" (default) or "Global"; can be changed later via app.root.ZIndexBehavior
}

function ui.createApp(opts: AppOptions?): any
	local o: AppOptions = opts or {}
	glfw.init(o.glfwPath)
	local window, err = glfw.createWindow(o.width or 960, o.height or 600, o.title or "zune-vkui", {
		noApi = true,
		resizable = o.resizable,
	})
	if not window then
		glfw.terminate()
		error(err)
	end
	-- the shaders option is handed to the renderer as is (it sets up the shader loader itself)
	local rendererOptions: { [string]: any } = {}
	if o.renderer then
		for k, v in o.renderer do
			rendererOptions[k] = v
		end
	end
	if o.shaders ~= nil then
		rendererOptions.shaders = o.shaders
	end
	local ok, renderer = pcall(Renderer.new, glfw, window, rendererOptions)
	if not ok then
		window:destroy()
		glfw.terminate()
		error(renderer, 0)
	end
	local fake = setmetatable({}, {
		__index = function(tbl, key)
			if key == "UIFW" then
				return ui
			end
			return renderer[key]
		end,
	})
	local gui = ui.new(window, fake)
	if o.ZIndexBehavior then
		gui.root.ZIndexBehavior = o.ZIndexBehavior
	end
	if o.font then
		local okFont, fontErr = pcall(gui.setDefaultFont, gui, o.font)
		if not okFont then
			fake:destroy()
			window:destroy()
			glfw.terminate()
			error(fontErr, 0)
		end
	end
	return setmetatable({ glfw = glfw, window = window, renderer = fake, gui = gui, root = gui.root }, App)
end

-- step(dt) runs once per frame before the UI is laid out; use it to mutate widgets.
-- By default each frame yields to Zune's scheduler with zune.task.wait() so timers/network keep running;
-- pass { yield = false } to disable or { yield = fn } to use your own.
function App:run(step: ((dt: number) -> ())?, opts: { yield: any? }?)
	local yieldFn = if opts and opts.yield ~= nil then opts.yield else zune.task.wait
	local last = glfw.getTime()
	while not self.window:shouldClose() do
		glfw.pollEvents()
		local now = glfw.getTime()
		local dt = now - last
		last = now
		if step then
			step(dt)
		end
		if self.renderer:beginFrame() then
			self.gui:update(dt)
			self.gui:draw()
			self.renderer:endFrame()
		else
			glfw.waitEvents(0.05) -- minimized or swapchain being rebuilt
		end
		if yieldFn then
			yieldFn()
		end
	end
end

function App:destroy()
	self.renderer:destroy()
	self.window:destroy()
	glfw.terminate()
end

return ui
