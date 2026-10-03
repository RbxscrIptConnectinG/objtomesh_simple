--[[
	text.luau - text layout + glyph atlas on top of font.luau and renderer.luau

	local engine = text.new(renderer)
	local layout = engine:layout(fontObject, "Hello\nworld", 16, maxWidthOrNil, lineHeightMultiplier)
	engine:draw(renderer, layout, x, y, boxWidth, boxHeight, {r,g,b,a}, "left"|"center"|"right", "top"|"middle"|"bottom")

	* Glyphs are rasterized on demand (per font and pixel size) into 1024x1024 atlas pages and uploaded
	  once per frame, right before the frame is submitted.
	* Layout handles UTF-8, "\n", tabs and optional word wrapping (falls back to breaking inside a word).
	* No kerning / ligatures / bidi: every glyph advances by its hmtx width.
]]

local PAGE = 1024

local text = {}

local Engine = {}
Engine.__index = Engine

export type Entry = {
	tex: any,
	u0: number,
	v0: number,
	u1: number,
	v1: number,
	left: number,
	top: number,
	w: number,
	h: number,
}

function text.new(renderer: any): any
	local self: any = setmetatable({ renderer = renderer, pages = {}, glyphs = {} }, Engine)
	table.insert(renderer.preSubmit, function()
		self:flush()
	end)
	return self
end

function Engine:_newPage(): any
	local cpu = buffer.create(PAGE * PAGE * 4)
	local page = {
		tex = self.renderer:createTexture(PAGE, PAGE, cpu),
		cpu = cpu,
		x = 1,
		y = 1,
		rowH = 0,
		dirty = false,
		dx0 = PAGE,
		dy0 = PAGE,
		dx1 = 0,
		dy1 = 0,
	}
	table.insert(self.pages, page)
	return page
end

function Engine:_pack(w: number, h: number): (any?, number?, number?)
	if w + 2 > PAGE or h + 2 > PAGE then
		return nil, nil, nil
	end
	local page = self.pages[#self.pages] or self:_newPage()
	if page.x + w + 1 > PAGE then
		page.x = 1
		page.y += page.rowH + 1
		page.rowH = 0
	end
	if page.y + h + 1 > PAGE then
		page = self:_newPage()
	end
	local px, py = page.x, page.y
	page.x += w + 1
	page.rowH = math.max(page.rowH, h)
	return page, px, py
end

-- Returns the atlas entry for a glyph, or false if the glyph has no ink (e.g. space).
function Engine:getGlyph(fnt: any, g: number, size: number, antiAlias: boolean?): any
	local bySize = self.glyphs[fnt]
	if not bySize then
		bySize = {}
		self.glyphs[fnt] = bySize
	end
	local aa = antiAlias ~= false
	local key = if aa then size else -size -- aliased (1-bit) glyphs are cached separately
	local byGlyph = bySize[key]
	if not byGlyph then
		byGlyph = {}
		bySize[key] = byGlyph
	end
	local entry = byGlyph[g]
	if entry ~= nil then
		return entry
	end

	local bmp = fnt:rasterize(g, size)
	if not bmp then
		byGlyph[g] = false
		return false
	end
	local page, px, py = self:_pack(bmp.width, bmp.height)
	if not page then
		byGlyph[g] = false -- bigger than an atlas page
		return false
	end

	local w, h, data, cpu = bmp.width, bmp.height, bmp.data, page.cpu
	for row = 0, h - 1 do
		local dst = ((py + row) * PAGE + px) * 4
		local src = row * w
		for col = 0, w - 1 do
			local cov = buffer.readu8(data, src + col)
			if not aa then
				cov = if cov >= 128 then 255 else 0
			end
			buffer.writeu32(cpu, dst + col * 4, 0x00FFFFFF + cov * 16777216)
		end
	end
	page.dirty = true
	page.dx0, page.dy0 = math.min(page.dx0, px), math.min(page.dy0, py)
	page.dx1, page.dy1 = math.max(page.dx1, px + w), math.max(page.dy1, py + h)

	entry = {
		tex = page.tex,
		u0 = px / PAGE,
		v0 = py / PAGE,
		u1 = (px + w) / PAGE,
		v1 = (py + h) / PAGE,
		left = bmp.left,
		top = bmp.top,
		w = w,
		h = h,
	}
	byGlyph[g] = entry
	return entry
end

-- Uploads modified atlas regions (called automatically before each frame is submitted).
function Engine:flush()
	for _, page in self.pages do
		if page.dirty then
			local x0, y0, x1, y1 = page.dx0, page.dy0, page.dx1, page.dy1
			local dw, dh = x1 - x0, y1 - y0
			local tight = buffer.create(dw * dh * 4)
			for row = 0, dh - 1 do
				buffer.copy(tight, row * dw * 4, page.cpu, ((y0 + row) * PAGE + x0) * 4, dw * 4)
			end
			self.renderer:updateTexture(page.tex, x0, y0, dw, dh, tight)
			page.dirty = false
			page.dx0, page.dy0, page.dx1, page.dy1 = PAGE, PAGE, 0, 0
		end
	end
end

local function codepoints(str: string): { number }
	local ok, list = pcall(function()
		local t = {}
		for _, c in utf8.codes(str) do
			table.insert(t, c)
		end
		return t
	end)
	if ok then
		return list
	end
	local t = {} -- invalid UTF-8: treat bytes as Latin-1
	for i = 1, #str do
		t[i] = string.byte(str, i)
	end
	return t
end

function text.fromCodepoints(list: { number }, i: number?, j: number?): string
	local from, to = i or 1, j or #list
	local parts = {}
	local k = from
	while k <= to do
		local e = math.min(to, k + 3999)
		table.insert(parts, utf8.char(table.unpack(list, k, e)))
		k = e + 1
	end
	return table.concat(parts)
end

text.codepoints = codepoints

-- x offset of a line of width `lineWidth` inside a box of width `boxWidth`
local function alignOffset(lineWidth: number, boxWidth: number, align: string?): number
	if align == "center" then
		return (boxWidth - lineWidth) / 2
	elseif align == "right" then
		return boxWidth - lineWidth
	end
	return 0
end

Engine.alignOffset = alignOffset

--[[
	Returns {
		lines = { { glyphs = { item... }, width }... }, width, height, size, font, lineHeight, ascent, leading,
		n = number of code points, carets = { [caret + 1] = { lineIndex, x } }
	}
	Every code point produces exactly one item { x, i (1-based code point index), adv, g? (glyph, absent for
	newline/tab/CR), nl? }. A caret c (0..n) sits before code point c + 1; carets on a wrap boundary belong to the
	start of the following line. maxWidth (pixels) enables word wrapping; nil = no wrapping.
]]
function Engine:layout(fnt: any, str: string, size: number, maxWidth: number?, lineHeightMul: number?): any
	size = math.max(1, math.floor(size + 0.5))
	local scale = size / fnt.unitsPerEm
	local ascent, descent, gap = fnt:scaledMetrics(size)
	local natural = (ascent :: number) - (descent :: number) + (gap :: number)
	local lineHeight = natural * (lineHeightMul or 1)
	local spaceAdv = fnt:advance(fnt:glyphIndex(32)) * scale

	local cps = codepoints(str)
	local lines = {}
	local line = { glyphs = {}, width = 0 }
	local penX = 0
	local lastBreak: number? = nil

	local function endLine()
		table.insert(lines, line)
		line = { glyphs = {}, width = 0 }
		penX = 0
		lastBreak = nil
	end

	for idx, cp in cps do
		if cp == 10 then
			table.insert(line.glyphs, { x = penX, i = idx, adv = 0, nl = true })
			endLine()
		elseif cp == 13 then
			table.insert(line.glyphs, { x = penX, i = idx, adv = 0 })
		elseif cp == 9 then
			local adv = spaceAdv * 4
			table.insert(line.glyphs, { x = penX, i = idx, adv = adv })
			penX += adv
			line.width = penX
		else
			local g = fnt:glyphIndex(cp)
			local adv = fnt:advance(g) * scale
			if maxWidth and cp ~= 32 and #line.glyphs > 0 and penX + adv > maxWidth + 1e-6 then
				local brk = lastBreak
				if brk then
					local glyphs = line.glyphs
					local tailStart = penX
					if brk < #glyphs then
						tailStart = glyphs[brk + 1].x
					end
					local tail = {}
					for k = brk + 1, #glyphs do
						local it = glyphs[k]
						table.insert(tail, { g = it.g, x = it.x - tailStart, i = it.i, adv = it.adv, nl = it.nl })
					end
					local spaceX = glyphs[brk].x -- visual width: the kept trailing space is not counted
					for k = #glyphs, brk + 1, -1 do
						glyphs[k] = nil
					end
					line.width = spaceX
					table.insert(lines, line)
					line = { glyphs = tail, width = 0 }
					penX -= tailStart
					lastBreak = nil
				else
					line.width = penX
					endLine()
				end
			end
			table.insert(line.glyphs, { g = g, x = penX, i = idx, adv = adv })
			penX += adv
			line.width = penX
			if cp == 32 then
				lastBreak = #line.glyphs
			end
		end
	end
	table.insert(lines, line)

	local width = 0
	local carets = {}
	for li, l in lines do
		width = math.max(width, l.width)
		for _, it in l.glyphs do
			carets[it.i] = { li, it.x }
		end
	end
	local finalLine = lines[#lines]
	local lastItem = finalLine.glyphs[#finalLine.glyphs]
	carets[#cps + 1] = { #lines, if lastItem then lastItem.x + lastItem.adv else 0 }

	return {
		lines = lines,
		width = width,
		height = #lines * lineHeight,
		size = size,
		font = fnt,
		lineHeight = lineHeight,
		ascent = ascent,
		leading = (lineHeight - natural) / 2,
		n = #cps,
		carets = carets,
	}
end

-- Caret index (0..n) nearest to x on line `li` (x in layout space, before alignment).
function Engine:caretOnLine(layout: any, li: number, x: number): number
	local line = layout.lines[li]
	local items = line.glyphs
	if #items == 0 then
		return layout.n
	end
	local best, bestD = items[1].i - 1, math.huge
	for _, it in items do
		local d = math.abs(it.x - x)
		if d < bestD then
			best, bestD = it.i - 1, d
		end
	end
	if li == #layout.lines then -- the very end of the text is a valid caret on the final line
		local last = items[#items]
		if math.abs(last.x + last.adv - x) < bestD then
			best = last.i
		end
	end
	return best
end

-- (x, y, lineIndex) of caret `c` in layout space; y is the top of its line.
function Engine:caretPosition(layout: any, c: number): (number?, number?, number?)
	local e = layout.carets[math.clamp(c, 0, layout.n) + 1]
	return e[2], (e[1] - 1) * layout.lineHeight, e[1]
end

-- First and last caret index that are reachable on line `li` (used for Home / End).
function Engine:lineBounds(layout: any, li: number): (number?, number?)
	local items = layout.lines[li].glyphs
	if #items == 0 then
		return layout.n, layout.n
	end
	local first = items[1].i - 1
	local last = if li == #layout.lines then layout.n else items[#items].i - 1
	return first, last
end

-- Rectangles { x, y, w, h, lineIndex } covering the characters between carets a < b (layout space, before alignment).
function Engine:selectionRects(layout: any, a: number, b: number): { { number } }
	local rects = {}
	local nlWidth = math.max(4, layout.size * 0.3)
	for li, line in layout.lines do
		local x0, x1 = nil, nil
		for _, it in line.glyphs do
			if it.i > a and it.i <= b then
				local w = if it.nl then nlWidth else it.adv
				x0 = math.min(x0 or it.x, it.x)
				x1 = math.max(x1 or 0, it.x + w)
			end
		end
		if x0 then
			table.insert(rects, { x0, (li - 1) * layout.lineHeight, (x1 :: number) - x0, layout.lineHeight, li })
		end
	end
	return rects
end

-- Queues one textured quad per visible glyph.
function Engine:draw(
	r: any,
	layout: any,
	x: number,
	y: number,
	w: number,
	h: number,
	color: { number },
	align: string?,
	valign: string?,
	antiAlias: boolean?
)
	local oy = 0
	if valign == "middle" then
		oy = (h - layout.height) / 2
	elseif valign == "bottom" then
		oy = h - layout.height
	end
	local cr, cg, cb, ca = color[1], color[2], color[3], color[4] or 1
	local size, fnt = layout.size, layout.font
	for li, line in layout.lines do
		local ox = alignOffset(line.width, w, align)
		local baseline = math.floor(y + oy + (li - 1) * layout.lineHeight + layout.leading + layout.ascent + 0.5)
		local bx = x + ox
		for _, gl in line.glyphs do
			if gl.g then
				local e = self:getGlyph(fnt, gl.g, size, antiAlias)
				if e then
					r:quad(
						math.floor(bx + gl.x + 0.5) + e.left,
						baseline - e.top,
						e.w,
						e.h,
						cr,
						cg,
						cb,
						ca,
						e.tex,
						e.u0,
						e.v0,
						e.u1,
						e.v1
					)
				end
			end
		end
	end
end

return text
