--!nonstrict
--[[
	svg.luau - SVG parser and anti-aliased software rasterizer (pure Luau, no dependencies besides xml.luau / svgpath.luau / svgstyle.luau)

	local doc = svg.parse(source)                              -- source: SVG markup (string or buffer); errors are thrown
	local w, h = svg.size(doc)                                 -- intrinsic size in pixels (width/height attributes, else the viewBox)
	local w, h, rgba = svg.render(doc, 256, 256, options?)     -- RGBA8 buffer, non-premultiplied, top row first (same as image.decode)
	local w, h, rgba = svg.rasterize(source | doc, width?, height?, options?)
	                       -- only one of width/height: the other follows the aspect ratio; neither: intrinsic size * options.scale
	svg.isSVG(data)                                            -- does this string / buffer look like SVG markup
	svg.warnings(doc)                                          -- list of unsupported features met while rendering

	options:
	  color                 value of `currentColor` (default black): { r, g, b, a } 0..1, or a CSS colour string
	  background            { r, g, b, a } 0..1 painted behind the drawing (default transparent)
	  preserveAspectRatio   overrides the document's, e.g. "none" to stretch, "xMinYMin slice" (default: the document's, normally "xMidYMid meet")
	  scale                 rasterize(): multiplier of the intrinsic size when no width/height is given
	  bleed                 passes of colour bleeding into fully transparent pixels (default 2) so linear/cubic texture filtering
	                        does not darken the edges of the picture; 0 disables

	Supported
	  elements       svg (nested too), g, a, switch, defs, symbol, use, rect (rx/ry), circle, ellipse, line, polyline, polygon, path
	                 (M L H V C S Q T A Z, absolute and relative), linearGradient, radialGradient (focal point, spreadMethod,
	                 gradientUnits/gradientTransform, href inheritance), clipPath (units, nested clip-path, use), mask (luminance),
	                 style (CSS: tag / .class / #id / compound / descendant / child selectors, @-rules skipped)
	  presentation   fill, fill-opacity, fill-rule, stroke, stroke-width, stroke-opacity, stroke-linecap, stroke-linejoin,
	                 stroke-miterlimit, stroke-dasharray, stroke-dashoffset, opacity, display, visibility, color/currentColor,
	                 stop-color, stop-opacity, clip-path, clip-rule, mask, font-size (for em units), transform, `style` attributes
	  colours        #rgb #rgba #rrggbb #rrggbbaa rgb() rgba() hsl() hsla() named colours
	  lengths        px pt pc mm cm in em ex %
	Not supported (skipped, listed by svg.warnings): text, image, filter, pattern, marker, foreignObject, animation, non-scaling-stroke,
	  clipping to a nested <svg> viewport.
]]

local xml = require("@self/xml")
local P = require("@self/svgpath")
local St = require("@self/svgstyle")

local svg = {}

local abs, floor, ceil, sqrt, min, max = math.abs, math.floor, math.ceil, math.sqrt, math.min, math.max
local rf, wf = buffer.readf32, buffer.writef32

local PRESENTATION = {
	["fill"] = true,
	["fill-opacity"] = true,
	["fill-rule"] = true,
	["stroke"] = true,
	["stroke-width"] = true,
	["stroke-opacity"] = true,
	["stroke-linecap"] = true,
	["stroke-linejoin"] = true,
	["stroke-miterlimit"] = true,
	["stroke-dasharray"] = true,
	["stroke-dashoffset"] = true,
	["opacity"] = true,
	["display"] = true,
	["visibility"] = true,
	["color"] = true,
	["stop-color"] = true,
	["stop-opacity"] = true,
	["clip-path"] = true,
	["clip-rule"] = true,
	["mask"] = true,
	["font-size"] = true,
}
local SHAPES = { rect = true, circle = true, ellipse = true, line = true, polyline = true, polygon = true, path = true }
local CONTAINERS = { g = true, a = true, svg = true, switch = true }
local NONRENDERING = {
	["#text"] = true,
	defs = true,
	clipPath = true,
	mask = true,
	linearGradient = true,
	radialGradient = true,
	pattern = true,
	style = true,
	title = true,
	desc = true,
	metadata = true,
	symbol = true,
	marker = true,
	filter = true,
	script = true,
	stop = true,
	font = true,
	["font-face"] = true,
}
local UNSUPPORTED = {
	text = "<text> (convert text to paths)",
	image = "<image>",
	foreignObject = "<foreignObject>",
	animate = "animation",
	animateTransform = "animation",
	set = "animation",
	animateMotion = "animation",
}

local EMPTY = {}

--------------------------------------------------------------------------
-- document
--------------------------------------------------------------------------

local function prepare(doc, root)
	local cssTexts = {}
	local function walk(n)
		if n.tag ~= "#text" then
			local id = n.attrs.id
			if id and doc.ids[id] == nil then
				doc.ids[id] = n
			end
			if n.tag == "style" then
				local ty = n.attrs.type
				if ty == nil or ty == "" or ty == "text/css" then
					for _, c in n.children do
						if c.tag == "#text" then
							cssTexts[#cssTexts + 1] = c.text
						end
					end
				end
			end
		end
		for _, c in n.children do
			walk(c)
		end
	end
	walk(root)

	local rules = {}
	for _, text in cssTexts do
		St.parseCSS(text, rules)
	end
	table.sort(rules, function(a, b)
		if a.spec ~= b.spec then
			return a.spec < b.spec
		end
		return a.order < b.order
	end)

	local function props(n)
		if n.tag ~= "#text" then
			local p = {}
			local a = n.attrs
			for k in PRESENTATION do
				if a[k] ~= nil then
					p[k] = St.trim(a[k])
				end
			end
			for _, rule in rules do
				if St.matches(n, rule.sel) then
					for k, v in rule.decls do
						if PRESENTATION[k] then
							p[k] = v
						end
					end
				end
			end
			if a.style then
				for k, v in St.parseDecls(a.style) do
					if PRESENTATION[k] then
						p[k] = v
					end
				end
			end
			n.props = p
		end
		for _, c in n.children do
			props(c)
		end
	end
	props(root)
end

function svg.isSVG(data: any): boolean
	local head
	if type(data) == "buffer" then
		head = buffer.readstring(data, 0, min(buffer.len(data), 4096))
	elseif type(data) == "string" then
		head = string.sub(data, 1, 4096)
	else
		return false
	end
	return string.find(head, "<svg", 1, true) ~= nil
end

function svg.parse(source: any): any
	if type(source) == "buffer" then
		source = buffer.tostring(source)
	end
	if type(source) ~= "string" then
		error("svg.parse: expected SVG markup (string or buffer)", 2)
	end
	if string.sub(source, 1, 3) == "\239\187\191" then
		source = string.sub(source, 4) -- UTF-8 BOM
	end
	local root = xml.parse(source)
	local node
	for _, c in root.children do
		if c.tag == "svg" then
			node = c
			break
		end
	end
	if not node then
		error("svg: no <svg> element found", 2)
	end
	local doc = { root = node, ids = {}, warningSet = {}, warningList = {} }
	prepare(doc, root)

	local a = node.attrs
	local vb = P.parseViewBox(a.viewBox)
	local w = P.parseLength(a.width, nil, 16)
	local h = P.parseLength(a.height, nil, 16)
	if w and w <= 0 then
		w = nil
	end
	if h and h <= 0 then
		h = nil
	end
	if vb then
		if w and not h then
			h = w * vb.h / vb.w
		elseif h and not w then
			w = h * vb.w / vb.h
		elseif not w and not h then
			w, h = vb.w, vb.h
		end
	else
		w, h = w or 300, h or 150
		vb = { x = 0, y = 0, w = w, h = h }
	end
	doc.width, doc.height, doc.viewBox = w, h, vb
	doc.par = a.preserveAspectRatio or "xMidYMid meet"
	return doc
end

function svg.size(doc: any): (number, number)
	return doc.width, doc.height
end

function svg.warnings(doc: any): { string }
	return table.clone(doc.warningList)
end

local function warn(ctx, message: string)
	local doc = ctx.doc
	if not doc.warningSet[message] then
		doc.warningSet[message] = true
		table.insert(doc.warningList, message)
	end
end

--------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------

local function clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

local function parseOpacity(v: any): number?
	if type(v) ~= "string" then
		return nil
	end
	local pct = string.match(v, "^%s*([-+]?[%d%.]+)%%%s*$")
	if pct then
		return clamp01(tonumber(pct) :: number / 100)
	end
	local n = tonumber(v)
	if n == nil then
		return nil
	end
	return clamp01(n)
end

local function len(ctx, v: any, axis: string?): number?
	if v == nil then
		return nil
	end
	local vp = ctx.vp
	local base
	if axis == "x" then
		base = vp.w
	elseif axis == "y" then
		base = vp.h
	else
		base = sqrt((vp.w * vp.w + vp.h * vp.h) / 2)
	end
	return P.parseLength(v, base, 16)
end

local function nodeTransform(node)
	local t = node._tf
	if t == nil then
		t = P.parseTransform(node.attrs.transform) or false
		node._tf = t
	end
	return t or nil
end

local function hrefId(node): string?
	local h = node.attrs.href
	if h then
		return string.match(h, "^%s*#(.+)$")
	end
	return nil
end

local function parseUrlRef(v: any): string?
	if type(v) ~= "string" then
		return nil
	end
	return string.match(v, "^url%(%s*[\"']?#([^%)\"'%s]+)[\"']?%s*%)")
end

local function transformBox(t, x0, y0, x1, y1)
	if not t then
		return x0, y0, x1, y1
	end
	local nx0, ny0, nx1, ny1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } } do
		local x = t[1] * c[1] + t[3] * c[2] + t[5]
		local y = t[2] * c[1] + t[4] * c[2] + t[6]
		nx0, ny0, nx1, ny1 = min(nx0, x), min(ny0, y), max(nx1, x), max(ny1, y)
	end
	return nx0, ny0, nx1, ny1
end

--------------------------------------------------------------------------
-- shapes
--------------------------------------------------------------------------

local function shapePath(ctx, node)
	local cached = node._path
	if cached ~= nil then
		return cached or nil
	end
	local attrs = node.attrs
	local tag = node.tag
	local path = nil

	local function L(name: string, axis: string): number
		return len(ctx, attrs[name], axis) or 0
	end
	if tag == "rect" then
		local w, h = L("width", "x"), L("height", "y")
		if w > 0 and h > 0 then
			local rx, ry = len(ctx, attrs.rx, "x"), len(ctx, attrs.ry, "y")
			if rx == nil and ry == nil then
				rx, ry = 0, 0
			elseif rx == nil then
				rx = ry
			elseif ry == nil then
				ry = rx
			end
			rx, ry = min(max(rx, 0), w / 2), min(max(ry, 0), h / 2)
			path = P.rectPath(L("x", "x"), L("y", "y"), w, h, rx, ry)
		end
	elseif tag == "circle" then
		local r = L("r", "d")
		if r > 0 then
			path = P.ellipsePath(L("cx", "x"), L("cy", "y"), r, r)
		end
	elseif tag == "ellipse" then
		local rx, ry = len(ctx, attrs.rx, "x"), len(ctx, attrs.ry, "y")
		if rx == nil then
			rx = ry
		end
		if ry == nil then
			ry = rx
		end
		if rx and ry and rx > 0 and ry > 0 then
			path = P.ellipsePath(L("cx", "x"), L("cy", "y"), rx, ry)
		end
	elseif tag == "line" then
		path = { { "M", L("x1", "x"), L("y1", "y") }, { "L", L("x2", "x"), L("y2", "y") } }
	elseif tag == "polyline" or tag == "polygon" then
		path = P.polyPath(attrs.points or "", tag == "polygon")
		if #path < 2 then
			path = nil
		end
	elseif tag == "path" then
		path = P.parsePathData(attrs.d or "")
		if #path < 2 then
			path = nil
		end
	end
	node._path = path or false
	return path
end

-- bounding box of a node in its own local user space (before its `transform`), fill geometry only
local function nodeBBox(ctx, node, depth: number?)
	depth = depth or 0
	if depth > 12 then
		return nil, nil, nil, nil
	end
	local tag = node.tag
	if SHAPES[tag] then
		local path = shapePath(ctx, node)
		if not path then
			return nil, nil, nil, nil
		end
		return P.bounds(P.flatten(path, 0.05))
	elseif CONTAINERS[tag] then
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		local any = false
		for _, c in node.children do
			if not NONRENDERING[c.tag] and c.props.display ~= "none" then
				local a, b, cc, d = nodeBBox(ctx, c, (depth :: number) + 1)
				if a then
					a, b, cc, d = transformBox(nodeTransform(c), a, b, cc, d)
					x0, y0, x1, y1 = min(x0, a), min(y0, b), max(x1, cc), max(y1, d)
					any = true
				end
			end
		end
		if any then
			return x0, y0, x1, y1
		end
	elseif tag == "use" then
		local id = hrefId(node)
		local target = id and ctx.doc.ids[id]
		if target and target.tag ~= "symbol" then
			local a, b, cc, d = nodeBBox(ctx, target, (depth :: number) + 1)
			if a then
				a, b, cc, d = transformBox(nodeTransform(target), a, b, cc, d)
				local x, y = len(ctx, node.attrs.x, "x") or 0, len(ctx, node.attrs.y, "y") or 0
				return a + x, b + y, cc + x, d + y
			end
		end
	end
	return nil, nil, nil, nil
end

--------------------------------------------------------------------------
-- style
--------------------------------------------------------------------------

local parsePaint
function parsePaint(v: string)
	v = St.trim(v) :: string
	local lower = string.lower(v)
	if lower == "none" then
		return false
	elseif lower == "currentcolor" then
		return { kind = "current" }
	elseif lower == "inherit" then
		return nil
	end
	local id, rest = string.match(v, "^url%(%s*[\"']?#([^%)\"'%s]+)[\"']?%s*%)%s*(.*)$")
	if id then
		local fallback = nil
		if rest ~= "" then
			fallback = parsePaint(rest)
		end
		return { kind = "url", id = id, fallback = fallback }
	end
	local c = St.parseColor(v, nil)
	if c then
		return { kind = "color", c = c }
	end
	return nil
end

local function defaultStyle(ctx)
	return {
		fill = { kind = "color", c = { 0, 0, 0, 1 } },
		fillOpacity = 1,
		fillRule = "nonzero",
		stroke = false,
		strokeOpacity = 1,
		strokeWidth = 1,
		linecap = "butt",
		linejoin = "miter",
		miterlimit = 4,
		dash = nil,
		dashoffset = 0,
		visibility = "visible",
		color = ctx.color,
		fontSize = 16,
		clipRule = "nonzero",
	}
end

local function computeStyle(ctx, parent, node)
	local p = node.props or EMPTY
	if next(p) == nil then
		return parent
	end
	local s = table.clone(parent)
	local v = p["font-size"]
	if v then
		local l = P.parseLength(v, parent.fontSize, parent.fontSize)
		if l and l > 0 then
			s.fontSize = l
		end
	end
	v = p.color
	if v then
		local c = St.parseColor(v, parent.color)
		if c then
			s.color = c
		end
	end
	v = p.fill
	if v then
		local paint = parsePaint(v)
		if paint ~= nil then
			s.fill = paint
		end
	end
	v = p.stroke
	if v then
		local paint = parsePaint(v)
		if paint ~= nil then
			s.stroke = paint
		end
	end
	v = p["fill-opacity"]
	if v then
		s.fillOpacity = parseOpacity(v) or s.fillOpacity
	end
	v = p["stroke-opacity"]
	if v then
		s.strokeOpacity = parseOpacity(v) or s.strokeOpacity
	end
	v = p["fill-rule"]
	if v == "evenodd" or v == "nonzero" then
		s.fillRule = v
	end
	v = p["clip-rule"]
	if v == "evenodd" or v == "nonzero" then
		s.clipRule = v
	end
	v = p["stroke-width"]
	if v then
		local l = len(ctx, v, "d")
		if l and l >= 0 then
			s.strokeWidth = l
		end
	end
	v = p["stroke-linecap"]
	if v == "butt" or v == "round" or v == "square" then
		s.linecap = v
	end
	v = p["stroke-linejoin"]
	if v == "miter" or v == "round" or v == "bevel" then
		s.linejoin = v
	elseif v == "miter-clip" or v == "arcs" then
		s.linejoin = "miter"
	end
	v = p["stroke-miterlimit"]
	if v then
		local n = tonumber(v)
		if n and n >= 1 then
			s.miterlimit = n
		end
	end
	v = p["stroke-dasharray"]
	if v then
		if string.lower(St.trim(v) :: string) == "none" then
			s.dash = nil
		else
			local arr, ok = {}, true
			for tok in string.gmatch(v, "[^%s,]+") do
				local l = len(ctx, tok, "d")
				if l == nil or l < 0 then
					ok = false
					break
				end
				arr[#arr + 1] = l
			end
			if ok and #arr > 0 then
				if #arr % 2 == 1 then
					local n = #arr
					for i = 1, n do
						arr[n + i] = arr[i]
					end
				end
				local total = 0
				for _, l in arr do
					total += l
				end
				s.dash = if total > 0 then arr else nil
			end
		end
	end
	v = p["stroke-dashoffset"]
	if v then
		s.dashoffset = len(ctx, v, "d") or s.dashoffset
	end
	v = p.visibility
	if v == "visible" or v == "hidden" or v == "collapse" then
		s.visibility = v
	end
	return s
end

--------------------------------------------------------------------------
-- layers (premultiplied RGBA, f32) and the scanline coverage rasterizer
--------------------------------------------------------------------------

local function newLayer(W: number, H: number)
	return { data = buffer.create(W * H * 16), x0 = W, y0 = H, x1 = 0, y1 = 0 }
end

local function pushLayer(ctx)
	local l = newLayer(ctx.W, ctx.H)
	l.prev = ctx.layer
	ctx.layer = l
	return l
end

local function popLayer(ctx)
	local l = ctx.layer
	ctx.layer = l.prev
	l.prev = nil
	return l
end

local function markDirty(layer, x0: number, y0: number, x1: number, y1: number)
	if x0 < layer.x0 then
		layer.x0 = x0
	end
	if y0 < layer.y0 then
		layer.y0 = y0
	end
	if x1 > layer.x1 then
		layer.x1 = x1
	end
	if y1 > layer.y1 then
		layer.y1 = y1
	end
end

-- src drawn over the current layer with the given opacity
local function compositeLayer(ctx, src, opacity: number)
	local dst = ctx.layer
	if src.x0 >= src.x1 or src.y0 >= src.y1 or opacity <= 0 then
		return
	end
	local W = ctx.W
	local sd, dd = src.data, dst.data
	for y = src.y0, src.y1 - 1 do
		for x = src.x0, src.x1 - 1 do
			local o = (y * W + x) * 16
			local sa = rf(sd, o + 12) * opacity
			if sa > 0 then
				local ia = 1 - sa
				wf(dd, o, rf(sd, o) * opacity + rf(dd, o) * ia)
				wf(dd, o + 4, rf(sd, o + 4) * opacity + rf(dd, o + 4) * ia)
				wf(dd, o + 8, rf(sd, o + 8) * opacity + rf(dd, o + 8) * ia)
				wf(dd, o + 12, sa + rf(dd, o + 12) * ia)
			end
		end
	end
	markDirty(dst, src.x0, src.y0, src.x1, src.y1)
end

-- layer *= mask (mask alpha, or its luminance)
local function applyMask(ctx, layer, mask, luminance: boolean)
	local W = ctx.W
	local ld, md = layer.data, mask.data
	for y = layer.y0, layer.y1 - 1 do
		for x = layer.x0, layer.x1 - 1 do
			local o = (y * W + x) * 16
			local m
			if luminance then
				m = 0.2125 * rf(md, o) + 0.7154 * rf(md, o + 4) + 0.0721 * rf(md, o + 8)
			else
				m = rf(md, o + 12)
			end
			if m >= 1 then
				-- unchanged
			elseif m <= 0 then
				wf(ld, o, 0)
				wf(ld, o + 4, 0)
				wf(ld, o + 8, 0)
				wf(ld, o + 12, 0)
			else
				wf(ld, o, rf(ld, o) * m)
				wf(ld, o + 4, rf(ld, o + 4) * m)
				wf(ld, o + 8, rf(ld, o + 8) * m)
				wf(ld, o + 12, rf(ld, o + 12) * m)
			end
		end
	end
end

-- polys: list of flat { x1, y1, x2, y2, ... } in device pixels, each implicitly closed.
-- paint: { solid = true, r, g, b, a } (premultiplied) or { fn = function(x, y) -> r, g, b, a (premultiplied) }
local function fillPolys(ctx, polys, rule: string, paint)
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, pts in polys do
		for i = 1, #pts, 2 do
			local x, y = pts[i], pts[i + 1]
			if x < minx then
				minx = x
			end
			if x > maxx then
				maxx = x
			end
			if y < miny then
				miny = y
			end
			if y > maxy then
				maxy = y
			end
		end
	end
	if minx ~= minx or maxx ~= maxx or miny ~= miny or maxy ~= maxy or minx == math.huge then
		return
	end
	local W, H = ctx.W, ctx.H
	local x0, y0 = max(0, floor(minx)), max(0, floor(miny))
	local x1, y1 = min(W, ceil(maxx)), min(H, ceil(maxy))
	if x1 <= x0 or y1 <= y0 then
		return
	end
	local bw, bh = x1 - x0, y1 - y0
	local stride = bw + 2
	local need = stride * bh * 4
	local acc = ctx.scratch
	if acc == nil or buffer.len(acc) < need then
		acc = buffer.create(need + need // 2)
		ctx.scratch = acc
	else
		buffer.fill(acc, 0, 0, need)
	end

	-- adds the signed area of an edge (inside [0,bw] x [0,bh], y0 < y1) to the accumulation buffer
	local function emit(ax: number, ay: number, bx: number, by: number, dir: number)
		if by <= ay then
			return
		end
		local dxdy = (bx - ax) / (by - ay)
		local x = ax
		local yStart = floor(ay)
		local yEnd = ceil(by)
		for y = yStart, yEnd - 1 do
			local row = y * stride
			local dy = min(y + 1, by) - max(y, ay)
			local xnext = x + dxdy * dy
			if xnext < 0 then
				xnext = 0
			elseif xnext > bw then
				xnext = bw
			end
			local d = dy * dir
			local xa, xb = x, xnext
			if xa > xb then
				xa, xb = xb, xa
			end
			local xaf = floor(xa)
			local xbc = ceil(xb)
			if xbc <= xaf + 1 then
				local xmf = 0.5 * (x + xnext) - xaf
				local o = (row + xaf) * 4
				wf(acc, o, rf(acc, o) + d - d * xmf)
				wf(acc, o + 4, rf(acc, o + 4) + d * xmf)
			else
				local s = 1 / (xb - xa)
				local x0f = xa - xaf
				local a0 = 0.5 * s * (1 - x0f) * (1 - x0f)
				local x1f = xb - xbc + 1
				local am = 0.5 * s * x1f * x1f
				local o = (row + xaf) * 4
				wf(acc, o, rf(acc, o) + d * a0)
				if xbc == xaf + 2 then
					wf(acc, o + 4, rf(acc, o + 4) + d * (1 - a0 - am))
				else
					local a1 = s * (1.5 - x0f)
					wf(acc, o + 4, rf(acc, o + 4) + d * (a1 - a0))
					for xi = xaf + 2, xbc - 2 do
						local oi = (row + xi) * 4
						wf(acc, oi, rf(acc, oi) + d * s)
					end
					local a2 = a1 + (xbc - xaf - 3) * s
					local o2 = (row + xbc - 1) * 4
					wf(acc, o2, rf(acc, o2) + d * (1 - a2 - am))
				end
				local o3 = (row + xbc) * 4
				wf(acc, o3, rf(acc, o3) + d * am)
			end
			x = xnext
		end
	end

	local function addEdge(ax: number, ay: number, bx: number, by: number)
		if ay == by then
			return
		end
		local dir = 1
		if ay > by then
			ax, ay, bx, by = bx, by, ax, ay
			dir = -1
		end
		if by <= 0 or ay >= bh then
			return
		end
		local dxdy = (bx - ax) / (by - ay)
		if ay < 0 then
			ax = ax - ay * dxdy
			ay = 0
		end
		if by > bh then
			bx = ax + (bh - ay) * dxdy
			by = bh
		end
		if ax >= 0 and ax <= bw and bx >= 0 and bx <= bw then
			emit(ax, ay, bx, by, dir)
			return
		end
		if ax <= 0 and bx <= 0 then
			emit(0, ay, 0, by, dir)
			return
		end
		if ax >= bw and bx >= bw then
			emit(bw, ay, bw, by, dir)
			return
		end
		-- crosses x = 0 and/or x = bw: split there, outside parts become vertical edges on the border
		local dx = bx - ax
		local t1, t2 = (0 - ax) / dx, (bw - ax) / dx
		local lo, hi = min(t1, t2), max(t1, t2)
		local ts = { 0 }
		if lo > 0 and lo < 1 then
			ts[#ts + 1] = lo
		end
		if hi > 0 and hi < 1 then
			ts[#ts + 1] = hi
		end
		ts[#ts + 1] = 1
		for i = 1, #ts - 1 do
			local u, v = ts[i], ts[i + 1]
			local px, py = ax + dx * u, ay + (by - ay) * u
			local qx, qy = ax + dx * v, ay + (by - ay) * v
			emit(math.clamp(px, 0, bw), py, math.clamp(qx, 0, bw), qy, dir)
		end
	end

	for _, pts in polys do
		local n = #pts
		if n >= 6 then
			local px, py = pts[n - 1] - x0, pts[n] - y0
			for i = 1, n, 2 do
				local x, y = pts[i] - x0, pts[i + 1] - y0
				addEdge(px, py, x, y)
				px, py = x, y
			end
		end
	end

	local layer = ctx.layer
	markDirty(layer, x0, y0, x1, y1)
	local data = layer.data
	local solid = paint.solid
	local pr, pg, pb, pa = paint.r, paint.g, paint.b, paint.a
	local fn = paint.fn
	local evenodd = (rule == "evenodd")
	for y = 0, bh - 1 do
		local row = y * stride
		local py = y0 + y
		local sum = 0
		for x = 0, bw - 1 do
			sum += rf(acc, (row + x) * 4)
			local c = abs(sum)
			if evenodd then
				c = c % 2
				if c > 1 then
					c = 2 - c
				end
			elseif c > 1 then
				c = 1
			end
			if c > 0.003 then
				local sr, sg, sb, sa
				if solid then
					sr, sg, sb, sa = pr * c, pg * c, pb * c, pa * c
				else
					sr, sg, sb, sa = fn(x0 + x + 0.5, py + 0.5)
					sr, sg, sb, sa = sr * c, sg * c, sb * c, sa * c
				end
				if sa > 0 then
					local o = (py * W + x0 + x) * 16
					local ia = 1 - sa
					wf(data, o, sr + rf(data, o) * ia)
					wf(data, o + 4, sg + rf(data, o + 4) * ia)
					wf(data, o + 8, sb + rf(data, o + 8) * ia)
					wf(data, o + 12, sa + rf(data, o + 12) * ia)
				end
			end
		end
	end
end

-- user-space flat points -> device space; `normalize` makes every polygon wind the same way (needed for strokes)
local function transformPts(pts, m, normalize: boolean?)
	local a, b, c, d, e, f = m[1], m[2], m[3], m[4], m[5], m[6]
	local out = {}
	for i = 1, #pts, 2 do
		local x, y = pts[i], pts[i + 1]
		out[i] = a * x + c * y + e
		out[i + 1] = b * x + d * y + f
	end
	if normalize then
		local n = #out
		local area = 0
		if n >= 6 then
			local px, py = out[n - 1], out[n]
			for i = 1, n, 2 do
				local x, y = out[i], out[i + 1]
				area += px * y - x * py
				px, py = x, y
			end
		end
		if area < 0 then
			local rev = {}
			for i = n - 1, 1, -2 do
				rev[#rev + 1] = out[i]
				rev[#rev + 1] = out[i + 1]
			end
			return rev
		end
	end
	return out
end

local WHITE = { solid = true, r = 1, g = 1, b = 1, a = 1 }

--------------------------------------------------------------------------
-- paint: colours and gradients
--------------------------------------------------------------------------

local function solidPaint(c, alpha: number)
	local a = c[4] * alpha
	if a <= 0 then
		return nil
	end
	return { solid = true, r = c[1] * a, g = c[2] * a, b = c[3] * a, a = a }
end

local function nextGradient(ctx, node)
	local id = hrefId(node)
	local n = id and ctx.doc.ids[id] or nil
	if n and n.tag ~= "linearGradient" and n.tag ~= "radialGradient" then
		return nil
	end
	return n
end

local function gradAttr(ctx, node, name: string): string?
	local n, guard = node, 0
	while n and guard < 16 do
		local v = n.attrs[name]
		if v ~= nil then
			return v
		end
		n = nextGradient(ctx, n)
		guard += 1
	end
	return nil
end

local function gradStops(ctx, node)
	local n, guard = node, 0
	while n and guard < 16 do
		local stops = {}
		for _, c in n.children do
			if c.tag == "stop" then
				stops[#stops + 1] = c
			end
		end
		if #stops > 0 then
			return stops
		end
		n = nextGradient(ctx, n)
		guard += 1
	end
	return {}
end

-- returns a paint, or false when nothing should be drawn
local function buildGradient(ctx, node, st, getBounds, m, alpha: number)
	local stopNodes = gradStops(ctx, node)
	if #stopNodes == 0 then
		return false
	end
	local list, last = {}, 0
	for _, s in stopNodes do
		local off = clamp01(P.parseLength(s.attrs.offset or "0", 1, 16) or 0)
		if off < last then
			off = last
		end
		last = off
		local props = s.props or EMPTY
		local c = St.parseColor(props["stop-color"] or "black", st.color) or { 0, 0, 0, 1 }
		local a = c[4] * (parseOpacity(props["stop-opacity"]) or 1)
		list[#list + 1] = { off, c[1] * a, c[2] * a, c[3] * a, a }
	end
	local lastStop = list[#list]
	local function lastPaint()
		return {
			solid = true,
			r = lastStop[2] * alpha,
			g = lastStop[3] * alpha,
			b = lastStop[4] * alpha,
			a = lastStop[5] * alpha,
		}
	end
	if #list == 1 then
		return lastPaint()
	end

	local obb = gradAttr(ctx, node, "gradientUnits") ~= "userSpaceOnUse"
	local gm = m
	if obb then
		local bx0, by0, bx1, by1 = getBounds()
		if not bx0 or bx1 - bx0 <= 0 or by1 - by0 <= 0 then
			return false
		end
		gm = P.mul(gm, { bx1 - bx0, 0, 0, by1 - by0, bx0, by0 })
	end
	local gt = P.parseTransform(gradAttr(ctx, node, "gradientTransform"))
	if gt then
		gm = P.mul(gm, gt)
	end
	local inv = P.invert(gm)
	if not inv then
		return false
	end

	local function coord(name: string, default: string, axis: string): number
		local base
		if obb then
			base = 1
		elseif axis == "x" then
			base = ctx.vp.w
		elseif axis == "y" then
			base = ctx.vp.h
		else
			base = sqrt((ctx.vp.w * ctx.vp.w + ctx.vp.h * ctx.vp.h) / 2)
		end
		return P.parseLength(gradAttr(ctx, node, name) or default, base, 16) or P.parseLength(default, base, 16)
	end

	-- 256-entry premultiplied colour table
	local lut = {}
	local si = 1
	for i = 0, 255 do
		local t = i / 255
		while si < #list and list[si + 1][1] <= t do
			si += 1
		end
		local a, b = list[si], list[si + 1]
		local r, g, bl, al
		if t <= list[1][1] or not b then
			local s = if t <= list[1][1] then list[1] else a
			r, g, bl, al = s[2], s[3], s[4], s[5]
		else
			local span = b[1] - a[1]
			local u = if span > 0 then (t - a[1]) / span else 1
			r, g, bl, al =
				a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u, a[5] + (b[5] - a[5]) * u
		end
		lut[i * 4 + 1], lut[i * 4 + 2], lut[i * 4 + 3], lut[i * 4 + 4] = r, g, bl, al
	end
	local spread = gradAttr(ctx, node, "spreadMethod")
	local function sample(t: number)
		if t ~= t then
			t = 0
		end
		if spread == "reflect" then
			t = t % 2
			if t > 1 then
				t = 2 - t
			end
		elseif spread == "repeat" then
			t = t - floor(t)
		elseif t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
		local i = floor(t * 255 + 0.5) * 4
		return lut[i + 1] * alpha, lut[i + 2] * alpha, lut[i + 3] * alpha, lut[i + 4] * alpha
	end

	local i1, i2, i3, i4, i5, i6 = inv[1], inv[2], inv[3], inv[4], inv[5], inv[6]

	if node.tag == "linearGradient" then
		local x1, y1 = coord("x1", "0%", "x"), coord("y1", "0%", "y")
		local x2, y2 = coord("x2", "100%", "x"), coord("y2", "0%", "y")
		local dx, dy = x2 - x1, y2 - y1
		local dd = dx * dx + dy * dy
		if dd == 0 then
			return lastPaint()
		end
		return {
			fn = function(px: number, py: number)
				local gx = i1 * px + i3 * py + i5
				local gy = i2 * px + i4 * py + i6
				return sample(((gx - x1) * dx + (gy - y1) * dy) / dd)
			end,
		}
	end

	local cx, cy, r = coord("cx", "50%", "x"), coord("cy", "50%", "y"), coord("r", "50%", "d")
	if r <= 0 then
		return lastPaint()
	end
	local fx = if gradAttr(ctx, node, "fx") ~= nil then coord("fx", "50%", "x") else cx
	local fy = if gradAttr(ctx, node, "fy") ~= nil then coord("fy", "50%", "y") else cy
	local fr = max(0, coord("fr", "0%", "d"))
	if fr == 0 then
		-- keep the focal point inside the circle
		local fdx, fdy = fx - cx, fy - cy
		local dist = sqrt(fdx * fdx + fdy * fdy)
		if dist > r * 0.999 then
			local k = r * 0.999 / dist
			fx, fy = cx + fdx * k, cy + fdy * k
		end
	end
	local dx, dy, dr = cx - fx, cy - fy, r - fr
	local aa = dx * dx + dy * dy - dr * dr
	return {
		fn = function(px: number, py: number)
			local gx = i1 * px + i3 * py + i5 - fx
			local gy = i2 * px + i4 * py + i6 - fy
			local b = gx * dx + gy * dy + fr * dr
			local c = gx * gx + gy * gy - fr * fr
			local t
			if abs(aa) < 1e-9 then
				if abs(b) < 1e-12 then
					return 0, 0, 0, 0
				end
				t = c / (2 * b)
			else
				local disc = b * b - aa * c
				if disc < 0 then
					return 0, 0, 0, 0
				end
				local sq = sqrt(disc)
				local t1, t2 = (b + sq) / aa, (b - sq) / aa
				if t1 < t2 then
					t1, t2 = t2, t1
				end
				if fr + t1 * dr >= 0 then
					t = t1
				elseif fr + t2 * dr >= 0 then
					t = t2
				else
					return 0, 0, 0, 0
				end
			end
			return sample(t)
		end,
	}
end

local function resolvePaint(ctx, paint, st, getBounds, m, alpha: number)
	if not paint or alpha <= 0 then
		return nil
	end
	local kind = paint.kind
	if kind == "color" then
		return solidPaint(paint.c, alpha)
	elseif kind == "current" then
		return solidPaint(st.color, alpha)
	end
	local node = ctx.doc.ids[paint.id]
	if node and (node.tag == "linearGradient" or node.tag == "radialGradient") then
		return buildGradient(ctx, node, st, getBounds, m, alpha) or nil
	elseif node and node.tag == "pattern" then
		warn(ctx, "<pattern> paint")
	end
	local fb = paint.fallback
	if fb == nil or fb == false then
		return nil
	end
	if fb.kind == "url" then
		return nil
	end
	return resolvePaint(ctx, fb, st, getBounds, m, alpha)
end

--------------------------------------------------------------------------
-- clip paths and masks
--------------------------------------------------------------------------

local function drawClipChild(ctx, child, cm)
	local tag = child.tag
	if tag == "#text" then
		return
	end
	local props = child.props or EMPTY
	if props.display == "none" then
		return
	end
	local m = cm
	local t = nodeTransform(child)
	if t then
		m = P.mul(m, t)
	end
	local target = child
	if tag == "use" then
		local id = hrefId(child)
		target = id and ctx.doc.ids[id]
		if not target or not SHAPES[target.tag] then
			return
		end
		m = P.mul(m, { 1, 0, 0, 1, len(ctx, child.attrs.x, "x") or 0, len(ctx, child.attrs.y, "y") or 0 })
		local t2 = nodeTransform(target)
		if t2 then
			m = P.mul(m, t2)
		end
		props = target.props or EMPTY
	elseif not SHAPES[tag] then
		return
	end
	if props.visibility == "hidden" then
		return
	end
	local path = shapePath(ctx, target)
	if not path then
		return
	end
	local scale = P.matrixScale(m)
	if scale <= 0 or scale ~= scale then
		return
	end
	local polys = {}
	for _, sub in P.flatten(path, 0.05 / scale) do
		polys[#polys + 1] = transformPts(sub.pts, m)
	end
	fillPolys(ctx, polys, if props["clip-rule"] == "evenodd" then "evenodd" else "nonzero", WHITE)
end

local function buildClipLayer(ctx, cnode, m, getBBox)
	local cm = m
	local ct = nodeTransform(cnode)
	if ct then
		cm = P.mul(cm, ct)
	end
	if cnode.attrs.clipPathUnits == "objectBoundingBox" then
		local x0, y0, x1, y1 = getBBox()
		if not x0 or x1 - x0 <= 0 or y1 - y0 <= 0 then
			return newLayer(ctx.W, ctx.H) -- nothing to clip against: clips everything
		end
		cm = P.mul(cm, { x1 - x0, 0, 0, y1 - y0, x0, y0 })
	end
	local layer = pushLayer(ctx)
	for _, child in cnode.children do
		drawClipChild(ctx, child, cm)
	end
	popLayer(ctx)
	local nested = parseUrlRef((cnode.props or EMPTY)["clip-path"])
	if nested and ctx.depth < 16 then
		local n2 = ctx.doc.ids[nested]
		if n2 and n2.tag == "clipPath" and n2 ~= cnode then
			ctx.depth += 1
			local l2 = buildClipLayer(ctx, n2, m, getBBox)
			ctx.depth -= 1
			applyMask(ctx, layer, l2, false)
		end
	end
	return layer
end

local renderNode

local function buildMaskLayer(ctx, mnode, st, m, getBBox)
	local a = mnode.attrs
	local obbRegion = a.maskUnits ~= "userSpaceOnUse"
	local bx0, by0, bx1, by1 = getBBox()
	local needBox = obbRegion or a.maskContentUnits == "objectBoundingBox"
	if needBox and (not bx0 or bx1 - bx0 <= 0 or by1 - by0 <= 0) then
		return newLayer(ctx.W, ctx.H)
	end

	-- content
	local cm = m
	if a.maskContentUnits == "objectBoundingBox" then
		cm = P.mul(cm, { bx1 - bx0, 0, 0, by1 - by0, bx0, by0 })
	end
	local layer = pushLayer(ctx)
	local mst = computeStyle(ctx, st, mnode)
	for _, c in mnode.children do
		renderNode(ctx, c, mst, cm)
	end
	popLayer(ctx)

	-- region
	local rx, ry, rw, rh
	if obbRegion then
		local function frac(v: string?, default: number): number
			return P.parseLength(v or "", 1, 16) or default
		end
		rx = bx0 + frac(a.x, -0.1) * (bx1 - bx0)
		ry = by0 + frac(a.y, -0.1) * (by1 - by0)
		rw = frac(a.width, 1.2) * (bx1 - bx0)
		rh = frac(a.height, 1.2) * (by1 - by0)
	else
		rx = len(ctx, a.x or "-10%", "x") or 0
		ry = len(ctx, a.y or "-10%", "y") or 0
		rw = len(ctx, a.width or "120%", "x") or 0
		rh = len(ctx, a.height or "120%", "y") or 0
	end
	local region = pushLayer(ctx)
	fillPolys(ctx, {
		transformPts({ rx, ry, rx + rw, ry, rx + rw, ry + rh, rx, ry + rh }, m),
	}, "nonzero", WHITE)
	popLayer(ctx)
	applyMask(ctx, layer, region, false)
	return layer
end

--------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------

local function drawShape(ctx, node, st, m, opacity: number)
	if st.visibility ~= "visible" then
		return
	end
	local path = shapePath(ctx, node)
	if not path then
		return
	end
	local scale = P.matrixScale(m)
	if scale <= 0 or scale ~= scale then
		return
	end
	local tol = 0.05 / scale
	local subs = P.flatten(path, tol)
	if #subs == 0 then
		return
	end
	local bounds = nil
	local function getBounds()
		if bounds == nil then
			local x0, y0, x1, y1 = P.bounds(subs)
			bounds = { x0, y0, x1, y1 }
		end
		return bounds[1], bounds[2], bounds[3], bounds[4]
	end

	if st.fill and node.tag ~= "line" then
		local paint = resolvePaint(ctx, st.fill, st, getBounds, m, st.fillOpacity * opacity)
		if paint then
			local polys = {}
			for _, sub in subs do
				if #sub.pts >= 6 then
					polys[#polys + 1] = transformPts(sub.pts, m)
				end
			end
			fillPolys(ctx, polys, st.fillRule, paint)
		end
	end

	local sw = st.strokeWidth
	if st.stroke and sw > 0 then
		local paint = resolvePaint(ctx, st.stroke, st, getBounds, m, st.strokeOpacity * opacity)
		if paint then
			local hw = sw / 2
			local arcStep = math.clamp(2 * math.acos(1 - min(0.1 / (hw * scale), 1)), 0.05, math.pi / 3)
			local list = subs
			if st.dash then
				list = P.dash(subs, st.dash, st.dashoffset)
			end
			local shapes = P.stroke(list, hw, st.linecap, st.linejoin, st.miterlimit, arcStep)
			local polys = {}
			for _, pts in shapes do
				polys[#polys + 1] = transformPts(pts, m, true)
			end
			fillPolys(ctx, polys, "nonzero", paint)
		end
	end
end

local function drawChildren(ctx, node, st, m)
	for _, c in node.children do
		renderNode(ctx, c, st, m)
	end
end

local function drawNestedSvg(ctx, node, st, m)
	local a = node.attrs
	local x, y = len(ctx, a.x, "x") or 0, len(ctx, a.y, "y") or 0
	local w = len(ctx, a.width, "x") or ctx.vp.w
	local h = len(ctx, a.height, "y") or ctx.vp.h
	local vb = P.parseViewBox(a.viewBox)
	local m2 = P.mul(m, { 1, 0, 0, 1, x, y })
	local oldvp = ctx.vp
	if vb then
		m2 = P.mul(m2, P.viewBoxMatrix(vb, w, h, a.preserveAspectRatio))
		ctx.vp = { w = vb.w, h = vb.h }
	else
		ctx.vp = { w = w, h = h }
	end
	drawChildren(ctx, node, st, m2)
	ctx.vp = oldvp
end

local function drawUse(ctx, node, st, m)
	local id = hrefId(node)
	local target = id and ctx.doc.ids[id]
	if not target or ctx.depth >= 24 then
		return
	end
	local m2 = P.mul(m, { 1, 0, 0, 1, len(ctx, node.attrs.x, "x") or 0, len(ctx, node.attrs.y, "y") or 0 })
	ctx.depth += 1
	if target.tag == "symbol" then
		local w = len(ctx, node.attrs.width, "x") or len(ctx, target.attrs.width, "x") or ctx.vp.w
		local h = len(ctx, node.attrs.height, "y") or len(ctx, target.attrs.height, "y") or ctx.vp.h
		local vb = P.parseViewBox(target.attrs.viewBox)
		local oldvp = ctx.vp
		if vb then
			m2 = P.mul(m2, P.viewBoxMatrix(vb, w, h, target.attrs.preserveAspectRatio))
			ctx.vp = { w = vb.w, h = vb.h }
		end
		drawChildren(ctx, target, computeStyle(ctx, st, target), m2)
		ctx.vp = oldvp
	else
		renderNode(ctx, target, st, m2)
	end
	ctx.depth -= 1
end

function renderNode(ctx, node, pstyle, ctm)
	local tag = node.tag
	if NONRENDERING[tag] then
		return
	end
	local isShape = SHAPES[tag]
	if not (isShape or CONTAINERS[tag] or tag == "use") then
		if UNSUPPORTED[tag] then
			warn(ctx, UNSUPPORTED[tag] .. " is not supported")
		end
		return
	end
	local props = node.props or EMPTY
	if props.display == "none" then
		return
	end
	local st = computeStyle(ctx, pstyle, node)
	local t = nodeTransform(node)
	local m = if t then P.mul(ctm, t) else ctm

	local opacity = parseOpacity(props.opacity) or 1
	local clipId = parseUrlRef(props["clip-path"])
	local maskId = parseUrlRef(props.mask)
	local clipNode = clipId and ctx.doc.ids[clipId]
	if clipNode and clipNode.tag ~= "clipPath" then
		clipNode = nil
	end
	local maskNode = maskId and ctx.doc.ids[maskId]
	if maskNode and maskNode.tag ~= "mask" then
		maskNode = nil
	end
	if props["clip-path"] and not clipNode and string.find(props["clip-path"], "^%a+%(") and not clipId then
		warn(ctx, "clip-path shape functions")
	end

	local needLayer = clipNode ~= nil
		or maskNode ~= nil
		or (opacity < 1 and (not isShape or (st.fill and st.stroke and st.strokeWidth > 0)))
	local fold = 1
	if needLayer then
		pushLayer(ctx)
	else
		fold = opacity
	end

	if isShape then
		drawShape(ctx, node, st, m, fold)
	elseif tag == "use" then
		drawUse(ctx, node, st, m)
	elseif tag == "svg" then
		if node == ctx.doc.root then
			drawChildren(ctx, node, st, m)
		else
			drawNestedSvg(ctx, node, st, m)
		end
	elseif tag == "switch" then
		for _, c in node.children do
			if not NONRENDERING[c.tag] and c.attrs.requiredExtensions == nil then
				local lang = c.attrs.systemLanguage
				if lang == nil or string.find(lang, "^%s*en") then
					renderNode(ctx, c, st, m)
					break
				end
			end
		end
	else
		drawChildren(ctx, node, st, m)
	end

	if needLayer then
		local layer = popLayer(ctx)
		local bbox = nil
		local function getBBox()
			if bbox == nil then
				local a, b, c, d = nodeBBox(ctx, node)
				bbox = { a, b, c, d }
			end
			return bbox[1], bbox[2], bbox[3], bbox[4]
		end
		if clipNode then
			applyMask(ctx, layer, buildClipLayer(ctx, clipNode, m, getBBox), false)
		end
		if maskNode then
			applyMask(ctx, layer, buildMaskLayer(ctx, maskNode, st, m, getBBox), true)
		end
		compositeLayer(ctx, layer, opacity)
	end
end

--------------------------------------------------------------------------
-- output
--------------------------------------------------------------------------

local function toRGBA(layer, W: number, H: number): buffer
	local out = buffer.create(W * H * 4)
	local data = layer.data
	for y = layer.y0, layer.y1 - 1 do
		for x = layer.x0, layer.x1 - 1 do
			local o = (y * W + x) * 16
			local a = rf(data, o + 12)
			if a > 0.0005 then
				local k = 255 / a
				local q = (y * W + x) * 4
				buffer.writeu8(out, q, min(255, floor(rf(data, o) * k + 0.5)))
				buffer.writeu8(out, q + 1, min(255, floor(rf(data, o + 4) * k + 0.5)))
				buffer.writeu8(out, q + 2, min(255, floor(rf(data, o + 8) * k + 0.5)))
				buffer.writeu8(out, q + 3, min(255, floor(a * 255 + 0.5)))
			end
		end
	end
	return out
end

-- Copies the colour of neighbouring pixels into fully transparent ones (their alpha stays 0), so texture filtering that mixes
-- texels does not blend in black at the edges.
local function bleed(rgba: buffer, W: number, H: number, passes: number)
	local count = W * H
	local has = buffer.create(count)
	local missing = 0
	for i = 0, count - 1 do
		if buffer.readu8(rgba, i * 4 + 3) > 0 then
			buffer.writeu8(has, i, 1)
		else
			missing += 1
		end
	end
	if missing == 0 or missing == count then
		return
	end
	for _ = 1, passes do
		local nh = buffer.create(count)
		buffer.copy(nh, 0, has, 0, count)
		local changed = false
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local i = y * W + x
				if buffer.readu8(has, i) == 0 then
					local r, g, b, n = 0, 0, 0, 0
					for k = 1, 4 do
						local nx = x + (if k == 1 then -1 elseif k == 2 then 1 else 0)
						local ny = y + (if k == 3 then -1 elseif k == 4 then 1 else 0)
						if nx >= 0 and nx < W and ny >= 0 and ny < H then
							local j = ny * W + nx
							if buffer.readu8(has, j) == 1 then
								r += buffer.readu8(rgba, j * 4)
								g += buffer.readu8(rgba, j * 4 + 1)
								b += buffer.readu8(rgba, j * 4 + 2)
								n += 1
							end
						end
					end
					if n > 0 then
						buffer.writeu8(rgba, i * 4, floor(r / n + 0.5))
						buffer.writeu8(rgba, i * 4 + 1, floor(g / n + 0.5))
						buffer.writeu8(rgba, i * 4 + 2, floor(b / n + 0.5))
						buffer.writeu8(nh, i, 1)
						changed = true
					end
				end
			end
		end
		has = nh
		if not changed then
			break
		end
	end
end

local MAX_SIDE = 8192

function svg.render(doc: any, width: number, height: number, options: any?): (number?, number?, buffer?)
	options = options or {}
	local W, H = floor(width + 0.5), floor(height + 0.5)
	if not (W >= 1 and H >= 1) then
		error(`svg.render: invalid size {tostring(width)}x{tostring(height)}`, 2)
	end
	if W > MAX_SIDE or H > MAX_SIDE or W * H > 64 * 1024 * 1024 then
		error(`svg.render: {W}x{H} is too large`, 2)
	end

	local color = options.color
	if type(color) == "string" then
		color = St.parseColor(color, nil)
	end
	local ctx = {
		doc = doc,
		W = W,
		H = H,
		depth = 0,
		scratch = nil,
		color = color or { 0, 0, 0, 1 },
		vp = { w = doc.viewBox.w, h = doc.viewBox.h },
	}
	ctx.layer = newLayer(W, H)

	local bg = options.background
	if bg then
		local a = bg[4] or 1
		local data = ctx.layer.data
		for i = 0, W * H - 1 do
			wf(data, i * 16, bg[1] * a)
			wf(data, i * 16 + 4, bg[2] * a)
			wf(data, i * 16 + 8, bg[3] * a)
			wf(data, i * 16 + 12, a)
		end
		markDirty(ctx.layer, 0, 0, W, H)
	end

	local base = P.viewBoxMatrix(doc.viewBox, W, H, options.preserveAspectRatio or doc.par)
	renderNode(ctx, doc.root, defaultStyle(ctx), base)

	local rgba = toRGBA(ctx.layer, W, H)
	local passes = options.bleed
	if passes == nil then
		passes = 2
	end
	if passes > 0 then
		bleed(rgba, W, H, passes)
	end
	return W, H, rgba
end

function svg.rasterize(source: any, width: number?, height: number?, options: any?): (number?, number?, buffer?)
	local doc = if type(source) == "table" then source else svg.parse(source)
	local iw, ih = doc.width, doc.height
	local w, h = width, height
	if w and not h then
		h = w * ih / iw
	elseif h and not w then
		w = h * iw / ih
	elseif not w and not h then
		local scale = (options and options.scale) or 1
		w, h = iw * scale, ih * scale
	end
	return svg.render(doc, math.max(1, w), math.max(1, h), options)
end

return svg
