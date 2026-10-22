--[[
	font.luau - TrueType (.ttf) and OpenType (.otf) font parser + glyph rasterizer

	local f = font.loadFile("fonts/Inter-Regular.ttf")     -- cached by path
	local f = font.parse(bufferWithFontBytes)
	f:glyphIndex(0x41)            -- code point -> glyph id (0 = .notdef)
	f:advance(glyph)              -- advance width in font units
	f:scaledMetrics(16)           -- ascent, descent (negative), lineGap in pixels for a 16px em
	f:rasterize(glyph, 16)        -- { left, top, width, height, data = A8 coverage buffer } or nil for empty glyphs

	Supported: sfnt containers with TrueType outlines (glyf: simple + composite glyphs) and CFF outlines
	(Type 2 charstrings incl. subroutines, CID-keyed fonts); cmap formats 0, 4, 6, 12.
	Not supported: .ttc collections, WOFF/WOFF2, kerning/GSUB/GPOS shaping, colour glyphs, variable-font instances
	(the default instance is used), CFF2.
	Validated against fontTools outlines on ~17k glyphs; the rasterizer is an exact-area scanline accumulator.
]]

local font = {}

local Font = {}
Font.__index = Font

export type Bitmap = { left: number, top: number, width: number, height: number, data: buffer }

--------------------------------------------------------------------------
-- Binary helpers (big-endian)
--------------------------------------------------------------------------

local function u16(b: buffer, o: number): number
	return buffer.readu8(b, o) * 256 + buffer.readu8(b, o + 1)
end

local function i16(b: buffer, o: number): number
	local v = u16(b, o)
	return if v >= 32768 then v - 65536 else v
end

local function u32(b: buffer, o: number): number
	return buffer.readu8(b, o) * 16777216
		+ buffer.readu8(b, o + 1) * 65536
		+ buffer.readu8(b, o + 2) * 256
		+ buffer.readu8(b, o + 3)
end

local function i32(b: buffer, o: number): number
	local v = u32(b, o)
	return if v >= 2147483648 then v - 4294967296 else v
end

local function uN(b: buffer, o: number, n: number): number
	local v = 0
	for i = 0, n - 1 do
		v = v * 256 + buffer.readu8(b, o + i)
	end
	return v
end

--------------------------------------------------------------------------
-- CFF helpers
--------------------------------------------------------------------------

-- Returns ranges ({start, end} absolute offsets, end exclusive) and the offset after the INDEX.
local function cffIndex(b: buffer, off: number): ({ { number } }?, number?)
	local count = u16(b, off)
	if count == 0 then
		return {}, off + 2
	end
	local osz = buffer.readu8(b, off + 2)
	local offs = {}
	for i = 0, count do
		offs[i + 1] = uN(b, off + 3 + i * osz, osz)
	end
	local base = off + 3 + (count + 1) * osz - 1
	local ranges = {}
	for i = 1, count do
		ranges[i] = { base + offs[i], base + offs[i + 1] }
	end
	return ranges, base + offs[count + 1]
end

-- Operators are keys (escaped ops are 1200 + b1); values are operand arrays.
local function cffDict(b: buffer, start: number, finish: number): { [number]: { number } }
	local d: { [number]: { number } } = {}
	local ops: { number } = {}
	local i = start
	while i < finish do
		local b0 = buffer.readu8(b, i)
		if b0 <= 21 then
			local op = b0
			if b0 == 12 then
				op = 1200 + buffer.readu8(b, i + 1)
				i += 2
			else
				i += 1
			end
			d[op] = ops
			ops = {}
		elseif b0 == 28 then
			table.insert(ops, i16(b, i + 1))
			i += 3
		elseif b0 == 29 then
			table.insert(ops, i32(b, i + 1))
			i += 5
		elseif b0 == 30 then
			i += 1
			local s = ""
			local done = false
			while not done and i < finish do
				local byte = buffer.readu8(b, i)
				i += 1
				for k = 1, 2 do
					local nib = if k == 1 then byte // 16 else byte % 16
					if nib <= 9 then
						s ..= tostring(nib)
					elseif nib == 10 then
						s ..= "."
					elseif nib == 11 then
						s ..= "E"
					elseif nib == 12 then
						s ..= "E-"
					elseif nib == 14 then
						s ..= "-"
					elseif nib == 15 then
						done = true
						break
					end
				end
			end
			table.insert(ops, tonumber(s) or 0)
		elseif b0 >= 32 and b0 <= 246 then
			table.insert(ops, b0 - 139)
			i += 1
		elseif b0 >= 247 and b0 <= 250 then
			table.insert(ops, (b0 - 247) * 256 + buffer.readu8(b, i + 1) + 108)
			i += 2
		elseif b0 >= 251 and b0 <= 254 then
			table.insert(ops, -(b0 - 251) * 256 - buffer.readu8(b, i + 1) - 108)
			i += 2
		else
			i += 1
		end
	end
	return d
end

local function subrBias(n: number): number
	return if n < 1240 then 107 elseif n < 33900 then 1131 else 32768
end

--------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------

function font.parse(data: buffer): any
	local b = data
	if buffer.len(b) < 12 then
		error("font: file too small")
	end
	local sig = u32(b, 0)
	if sig == 0x74746366 then
		error("font: .ttc collections are not supported")
	end
	if sig ~= 0x00010000 and sig ~= 0x74727565 and sig ~= 0x4F54544F then
		error("font: not a TrueType/OpenType font (WOFF/WOFF2 are not supported)")
	end

	local self: any = setmetatable({ b = b, tables = {}, outlineCache = {}, cpCache = {} }, Font)
	local n = u16(b, 4)
	for i = 0, n - 1 do
		local o = 12 + i * 16
		self.tables[buffer.readstring(b, o, 4)] = { u32(b, o + 8), u32(b, o + 12) }
	end
	for _, req in { "head", "maxp", "hhea", "hmtx", "cmap" } do
		if not self.tables[req] then
			error("font: missing required table '" .. req .. "'")
		end
	end

	local head = self.tables.head[1]
	self.unitsPerEm = u16(b, head + 18)
	self.locFormat = i16(b, head + 50)
	self.numGlyphs = u16(b, self.tables.maxp[1] + 4)
	local hhea = self.tables.hhea[1]
	self.ascent, self.descent, self.lineGap = i16(b, hhea + 4), i16(b, hhea + 6), i16(b, hhea + 8)
	self.numHMetrics = u16(b, hhea + 34)
	self.hmtx = self.tables.hmtx[1]

	if self.tables.glyf and self.tables.loca then
		self.kind = "ttf"
		self.glyf, self.loca = self.tables.glyf[1], self.tables.loca[1]
	elseif self.tables["CFF "] then
		self.kind = "cff"
		self:_initCFF()
	else
		error("font: no usable outlines (need a 'glyf' or 'CFF ' table)")
	end

	-- pick the best cmap subtable
	local base = self.tables.cmap[1]
	local count = u16(b, base + 2)
	local best, bestScore = nil, -1
	for i = 0, count - 1 do
		local pid, eid = u16(b, base + 4 + i * 8), u16(b, base + 6 + i * 8)
		local off = base + u32(b, base + 8 + i * 8)
		local fmt = u16(b, off)
		local score = -1
		if fmt == 4 or fmt == 12 or fmt == 6 or fmt == 0 then
			if pid == 3 and eid == 10 then
				score = 40
			elseif pid == 0 and (eid == 4 or eid == 6) then
				score = 35
			elseif pid == 3 and eid == 1 then
				score = 30
			elseif pid == 0 then
				score = 20
			elseif pid == 3 and eid == 0 then
				score = 5
			end
			if score >= 0 and fmt == 12 then
				score += 1
			end
		end
		if score > bestScore then
			best, bestScore = off, score
		end
	end
	if not best then
		error("font: no usable cmap subtable")
	end
	self.cmapOff, self.cmapFormat = best, u16(b, best)
	return self
end

local cache: { [string]: any } = {}

function font.loadFile(path: string): any
	local hit = cache[path]
	if hit then
		return hit
	end
	local ok, data = pcall(zune.fs.readFileSync, path, true)
	if not ok then
		error("font: cannot read '" .. path .. "': " .. tostring(data), 2)
	end
	local ok2, f = pcall(font.parse, data)
	if not ok2 then
		error("font: '" .. path .. "': " .. tostring(f), 2)
	end
	f.path = path
	cache[path] = f
	return f
end

--------------------------------------------------------------------------
-- Metrics and character mapping
--------------------------------------------------------------------------

function Font:advance(g: number): number
	local i = math.min(g, self.numHMetrics - 1)
	return u16(self.b, self.hmtx + i * 4)
end

function Font:scaledMetrics(size: number): (number?, number?, number?)
	local s = size / self.unitsPerEm
	return self.ascent * s, self.descent * s, self.lineGap * s
end

function Font:glyphIndex(cp: number): number
	local hit = self.cpCache[cp]
	if hit then
		return hit
	end
	local b, o, f = self.b, self.cmapOff, self.cmapFormat
	local result = 0
	if f == 0 then
		if cp < 256 then
			result = buffer.readu8(b, o + 6 + cp)
		end
	elseif f == 6 then
		local first, cnt = u16(b, o + 6), u16(b, o + 8)
		if cp >= first and cp < first + cnt then
			result = u16(b, o + 10 + (cp - first) * 2)
		end
	elseif f == 4 then
		if cp <= 0xFFFF then
			local sc = u16(b, o + 6) // 2
			local endO = o + 14
			local startO = endO + sc * 2 + 2
			local deltaO = startO + sc * 2
			local rangeO = deltaO + sc * 2
			for i = 0, sc - 1 do
				if cp <= u16(b, endO + i * 2) then
					local start = u16(b, startO + i * 2)
					if cp >= start then
						local delta, ro = u16(b, deltaO + i * 2), u16(b, rangeO + i * 2)
						if ro == 0 then
							result = (cp + delta) % 65536
						else
							local g = u16(b, rangeO + i * 2 + ro + (cp - start) * 2)
							result = if g == 0 then 0 else (g + delta) % 65536
						end
					end
					break
				end
			end
		end
	elseif f == 12 then
		local lo, hi = 0, u32(b, o + 12) - 1
		while lo <= hi do
			local mid = (lo + hi) // 2
			local go = o + 16 + mid * 12
			local s, e = u32(b, go), u32(b, go + 4)
			if cp < s then
				hi = mid - 1
			elseif cp > e then
				lo = mid + 1
			else
				result = u32(b, go + 8) + (cp - s)
				break
			end
		end
	end
	self.cpCache[cp] = result
	return result
end

--------------------------------------------------------------------------
-- TrueType outlines
--------------------------------------------------------------------------

-- Returns a list of contours; each contour is a list of {x, y, on}
function Font:_ttfPoints(g: number, depth: number): { { { any } } }
	local b = self.b
	if g < 0 or g >= self.numGlyphs then
		return {}
	end
	local s, e
	if self.locFormat == 0 then
		s, e = u16(b, self.loca + g * 2) * 2, u16(b, self.loca + g * 2 + 2) * 2
	else
		s, e = u32(b, self.loca + g * 4), u32(b, self.loca + g * 4 + 4)
	end
	if e <= s then
		return {}
	end
	local o = self.glyf + s
	local nc = i16(b, o)
	o += 10

	if nc >= 0 then
		local ends = {}
		for i = 1, nc do
			ends[i] = u16(b, o + (i - 1) * 2)
		end
		o += nc * 2
		o += 2 + u16(b, o) -- skip instructions
		local npts = if nc > 0 then ends[nc] + 1 else 0

		local flags: { number } = {}
		while #flags < npts do
			local fl = buffer.readu8(b, o)
			o += 1
			table.insert(flags, fl)
			if bit32.btest(fl, 8) then
				local r = buffer.readu8(b, o)
				o += 1
				for _ = 1, r do
					table.insert(flags, fl)
				end
			end
		end

		local xs, ys = {}, {}
		local v = 0
		for i = 1, npts do
			local fl = flags[i]
			if bit32.btest(fl, 2) then
				local d = buffer.readu8(b, o)
				o += 1
				v += if bit32.btest(fl, 16) then d else -d
			elseif not bit32.btest(fl, 16) then
				v += i16(b, o)
				o += 2
			end
			xs[i] = v
		end
		v = 0
		for i = 1, npts do
			local fl = flags[i]
			if bit32.btest(fl, 4) then
				local d = buffer.readu8(b, o)
				o += 1
				v += if bit32.btest(fl, 32) then d else -d
			elseif not bit32.btest(fl, 32) then
				v += i16(b, o)
				o += 2
			end
			ys[i] = v
		end

		local out = {}
		local st = 1
		for _, endPt in ends do
			local c = {}
			for i = st, endPt + 1 do
				table.insert(c, { xs[i], ys[i], bit32.btest(flags[i], 1) })
			end
			table.insert(out, c)
			st = endPt + 2
		end
		return out
	end

	-- composite glyph
	if depth > 6 then
		return {}
	end
	local out = {}
	while true do
		local fl, gi = u16(b, o), u16(b, o + 2)
		o += 4
		local a1, a2
		if bit32.btest(fl, 1) then
			a1, a2 = i16(b, o), i16(b, o + 2)
			o += 4
		else
			a1, a2 = buffer.readu8(b, o), buffer.readu8(b, o + 1)
			o += 2
			if bit32.btest(fl, 2) then
				if a1 >= 128 then
					a1 -= 256
				end
				if a2 >= 128 then
					a2 -= 256
				end
			end
		end
		local xx, yy, xy, yx = 1, 1, 0, 0
		if bit32.btest(fl, 8) then
			xx = i16(b, o) / 16384
			yy = xx
			o += 2
		elseif bit32.btest(fl, 0x40) then
			xx, yy = i16(b, o) / 16384, i16(b, o + 2) / 16384
			o += 4
		elseif bit32.btest(fl, 0x80) then
			xx, yx, xy, yy = i16(b, o) / 16384, i16(b, o + 2) / 16384, i16(b, o + 4) / 16384, i16(b, o + 6) / 16384
			o += 8
		end
		local dx, dy = 0, 0
		if bit32.btest(fl, 2) then
			dx, dy = a1, a2
		end
		for _, contour in self:_ttfPoints(gi, depth + 1) do
			local c = {}
			for _, p in contour do
				table.insert(c, { xx * p[1] + xy * p[2] + dx, yx * p[1] + yy * p[2] + dy, p[3] })
			end
			table.insert(out, c)
		end
		if not bit32.btest(fl, 0x20) then
			break
		end
	end
	return out
end

-- Contour = { sx, sy, cmds }, cmd = {"L", x, y} | {"Q", cx, cy, x, y} | {"C", x1, y1, x2, y2, x, y}
function Font:_ttfOutline(g: number): { any }
	local result = {}
	for _, pts in self:_ttfPoints(g, 0) do
		local n = #pts
		if n >= 2 then
			local first = nil
			for i, p in pts do
				if p[3] then
					first = i
					break
				end
			end
			local sx, sy
			local order = {}
			if first == nil then
				sx, sy = (pts[1][1] + pts[2][1]) / 2, (pts[1][2] + pts[2][2]) / 2
				for i = 2, n do
					table.insert(order, pts[i])
				end
				table.insert(order, pts[1])
			else
				sx, sy = pts[first][1], pts[first][2]
				for i = first + 1, n do
					table.insert(order, pts[i])
				end
				for i = 1, first - 1 do
					table.insert(order, pts[i])
				end
			end
			table.insert(order, { sx, sy, true })

			local cmds = {}
			local cx, cy = nil, nil
			for _, p in order do
				local x, y, on = p[1], p[2], p[3]
				if on then
					if cx == nil then
						table.insert(cmds, { "L", x, y })
					else
						table.insert(cmds, { "Q", cx, cy, x, y })
						cx, cy = nil, nil
					end
				else
					if cx ~= nil then
						table.insert(cmds, { "Q", cx, cy, (cx + x) / 2, (cy + y) / 2 })
					end
					cx, cy = x, y
				end
			end
			table.insert(result, { sx = sx, sy = sy, cmds = cmds })
		end
	end
	return result
end

--------------------------------------------------------------------------
-- CFF outlines
--------------------------------------------------------------------------

function Font:_initCFF()
	local b = self.b
	local base = self.tables["CFF "][1]
	local hdrSize = buffer.readu8(b, base + 2)
	local _, p = cffIndex(b, base + hdrSize) -- Name INDEX
	local tops
	tops, p = cffIndex(b, p)
	_, p = cffIndex(b, p) -- String INDEX
	self.gsubrs = cffIndex(b, p)
	if #tops == 0 then
		error("font: CFF has no Top DICT")
	end
	local top = cffDict(b, tops[1][1], tops[1][2])
	if not top[17] then
		error("font: CFF has no CharStrings (CFF2 is not supported)")
	end
	self.charstrings = cffIndex(b, base + top[17][1])

	local function readPrivate(d: { [number]: { number } }): any
		if not d[18] then
			return { subrs = {} }
		end
		local size, off = d[18][1], d[18][2]
		local pd = cffDict(b, base + off, base + off + size)
		local subrs: { { number } } = {}
		if pd[19] then
			subrs = cffIndex(b, base + off + pd[19][1]) or {}
		end
		return { subrs = subrs }
	end

	self.privs = {}
	self.fdSelect = nil
	if top[1236] then -- CID-keyed: FDArray / FDSelect
		local fda = cffIndex(b, base + top[1236][1])
		for _, r in fda do
			table.insert(self.privs, readPrivate(cffDict(b, r[1], r[2])))
		end
		local fo = base + top[1237][1]
		local fmt = buffer.readu8(b, fo)
		local ng = #self.charstrings
		local sel = {}
		if fmt == 0 then
			for i = 1, ng do
				sel[i] = buffer.readu8(b, fo + i)
			end
		elseif fmt == 3 then
			local nr = u16(b, fo + 1)
			local q = fo + 3
			for _ = 1, nr do
				local first, fd, nxt = u16(b, q), buffer.readu8(b, q + 2), u16(b, q + 3)
				for g = first, nxt - 1 do
					sel[g + 1] = fd
				end
				q += 3
			end
		end
		self.fdSelect = sel
	else
		table.insert(self.privs, readPrivate(top))
	end
end

function Font:_cffOutline(g: number): { any }
	local b = self.b
	if g < 0 or g >= #self.charstrings then
		return {}
	end
	local fd = if self.fdSelect then (self.fdSelect[g + 1] or 0) else 0
	local lsubrs = (self.privs[fd + 1] or self.privs[1]).subrs
	local gsubrs = self.gsubrs
	local lbias, gbias = subrBias(#lsubrs), subrBias(#gsubrs)

	local contours = {}
	local cur: any = nil
	local x, y = 0, 0
	local stack: { number } = {}
	local nhints = 0
	local done = false

	local function close()
		if cur ~= nil then
			table.insert(contours, cur)
			cur = nil
		end
	end
	local function moveTo(dx: number, dy: number)
		close()
		x += dx
		y += dy
		cur = { sx = x, sy = y, cmds = {} }
	end
	local function lineTo(dx: number, dy: number)
		if cur == nil then
			cur = { sx = x, sy = y, cmds = {} }
		end
		x += dx
		y += dy
		table.insert(cur.cmds, { "L", x, y })
	end
	local function curveTo(a: number, bb: number, c: number, d: number, e: number, f: number)
		if cur == nil then
			cur = { sx = x, sy = y, cmds = {} }
		end
		local x1, y1 = x + a, y + bb
		local x2, y2 = x1 + c, y1 + d
		x, y = x2 + e, y2 + f
		table.insert(cur.cmds, { "C", x1, y1, x2, y2, x, y })
	end

	local function run(start: number, finish: number, depth: number)
		local i = start
		while i < finish and not done do
			local b0 = buffer.readu8(b, i)
			i += 1
			if b0 >= 32 or b0 == 28 then
				local v
				if b0 == 28 then
					v = i16(b, i)
					i += 2
				elseif b0 <= 246 then
					v = b0 - 139
				elseif b0 <= 250 then
					v = (b0 - 247) * 256 + buffer.readu8(b, i) + 108
					i += 1
				elseif b0 <= 254 then
					v = -(b0 - 251) * 256 - buffer.readu8(b, i) - 108
					i += 1
				else
					v = i32(b, i) / 65536
					i += 4
				end
				table.insert(stack, v)
			elseif b0 == 1 or b0 == 3 or b0 == 18 or b0 == 23 then -- stems
				if #stack % 2 == 1 then
					table.remove(stack, 1)
				end
				nhints += #stack // 2
				table.clear(stack)
			elseif b0 == 19 or b0 == 20 then -- hintmask / cntrmask
				if #stack % 2 == 1 then
					table.remove(stack, 1)
				end
				nhints += #stack // 2
				table.clear(stack)
				i += (nhints + 7) // 8
			elseif b0 == 21 then -- rmoveto
				moveTo(stack[#stack - 1], stack[#stack])
				table.clear(stack)
			elseif b0 == 22 then -- hmoveto
				moveTo(stack[#stack], 0)
				table.clear(stack)
			elseif b0 == 4 then -- vmoveto
				moveTo(0, stack[#stack])
				table.clear(stack)
			elseif b0 == 5 then -- rlineto
				for k = 1, #stack - 1, 2 do
					lineTo(stack[k], stack[k + 1])
				end
				table.clear(stack)
			elseif b0 == 6 or b0 == 7 then -- hlineto / vlineto
				local h = b0 == 6
				for _, v in stack do
					if h then
						lineTo(v, 0)
					else
						lineTo(0, v)
					end
					h = not h
				end
				table.clear(stack)
			elseif b0 == 8 then -- rrcurveto
				for k = 1, #stack - 5, 6 do
					curveTo(stack[k], stack[k + 1], stack[k + 2], stack[k + 3], stack[k + 4], stack[k + 5])
				end
				table.clear(stack)
			elseif b0 == 24 then -- rcurveline
				local k = 1
				while #stack - k + 1 >= 8 do
					curveTo(stack[k], stack[k + 1], stack[k + 2], stack[k + 3], stack[k + 4], stack[k + 5])
					k += 6
				end
				lineTo(stack[k], stack[k + 1])
				table.clear(stack)
			elseif b0 == 25 then -- rlinecurve
				local k = 1
				while #stack - k + 1 >= 8 do
					lineTo(stack[k], stack[k + 1])
					k += 2
				end
				curveTo(stack[k], stack[k + 1], stack[k + 2], stack[k + 3], stack[k + 4], stack[k + 5])
				table.clear(stack)
			elseif b0 == 26 then -- vvcurveto
				local k, dx1 = 1, 0
				if #stack % 2 == 1 then
					dx1 = stack[1]
					k = 2
				end
				while k + 3 <= #stack do
					curveTo(dx1, stack[k], stack[k + 1], stack[k + 2], 0, stack[k + 3])
					dx1 = 0
					k += 4
				end
				table.clear(stack)
			elseif b0 == 27 then -- hhcurveto
				local k, dy1 = 1, 0
				if #stack % 2 == 1 then
					dy1 = stack[1]
					k = 2
				end
				while k + 3 <= #stack do
					curveTo(stack[k], dy1, stack[k + 1], stack[k + 2], stack[k + 3], 0)
					dy1 = 0
					k += 4
				end
				table.clear(stack)
			elseif b0 == 30 or b0 == 31 then -- vhcurveto / hvcurveto
				local horiz = b0 == 31
				local k = 1
				while k + 3 <= #stack do
					local last = (#stack - k + 1 == 5)
					if horiz then
						curveTo(stack[k], 0, stack[k + 1], stack[k + 2], if last then stack[k + 4] else 0, stack[k + 3])
					else
						curveTo(0, stack[k], stack[k + 1], stack[k + 2], stack[k + 3], if last then stack[k + 4] else 0)
					end
					horiz = not horiz
					k += 4
				end
				table.clear(stack)
			elseif b0 == 10 or b0 == 29 then -- callsubr / callgsubr
				local idx = table.remove(stack) :: number
				local arr, bias = if b0 == 10 then lsubrs else gsubrs, if b0 == 10 then lbias else gbias
				local sub = arr[idx + bias + 1]
				if sub and depth < 10 then
					run(sub[1], sub[2], depth + 1)
				end
			elseif b0 == 11 then -- return
				return
			elseif b0 == 14 then -- endchar
				close()
				done = true
				return
			elseif b0 == 12 then
				local b1 = buffer.readu8(b, i)
				i += 1
				if b1 == 34 then -- hflex
					curveTo(stack[1], 0, stack[2], stack[3], stack[4], 0)
					curveTo(stack[5], 0, stack[6], -stack[3], stack[7], 0)
				elseif b1 == 35 then -- flex
					curveTo(stack[1], stack[2], stack[3], stack[4], stack[5], stack[6])
					curveTo(stack[7], stack[8], stack[9], stack[10], stack[11], stack[12])
				elseif b1 == 36 then -- hflex1
					curveTo(stack[1], stack[2], stack[3], stack[4], stack[5], 0)
					curveTo(stack[6], 0, stack[7], stack[8], stack[9], -(stack[2] + stack[4] + stack[8]))
				elseif b1 == 37 then -- flex1
					local sdx = stack[1] + stack[3] + stack[5] + stack[7] + stack[9]
					local sdy = stack[2] + stack[4] + stack[6] + stack[8] + stack[10]
					local dx6, dy6
					if math.abs(sdx) > math.abs(sdy) then
						dx6, dy6 = stack[11], -sdy
					else
						dx6, dy6 = -sdx, stack[11]
					end
					curveTo(stack[1], stack[2], stack[3], stack[4], stack[5], stack[6])
					curveTo(stack[7], stack[8], stack[9], stack[10], dx6, dy6)
				else
					error("font: unsupported CFF charstring operator 12 " .. b1)
				end
				table.clear(stack)
			else
				table.clear(stack)
			end
		end
	end

	local cs = self.charstrings[g + 1]
	run(cs[1], cs[2], 0)
	close()
	return contours
end

-- Outline in font units, y up (cached).
function Font:outline(g: number): { any }
	local hit = self.outlineCache[g]
	if hit then
		return hit
	end
	local o = if self.kind == "ttf" then self:_ttfOutline(g) else self:_cffOutline(g)
	self.outlineCache[g] = o
	return o
end

--------------------------------------------------------------------------
-- Flattening and rasterization
--------------------------------------------------------------------------

local TOLERANCE = 0.05

local function flatten(contours: { any }, scale: number): { { number } }
	local polys = {}
	for _, c in contours do
		local pts = { c.sx * scale, c.sy * scale } -- flat x,y,x,y...
		local px, py = pts[1], pts[2]
		for _, cmd in c.cmds do
			local kind = cmd[1]
			if kind == "L" then
				px, py = cmd[2] * scale, cmd[3] * scale
				table.insert(pts, px)
				table.insert(pts, py)
			elseif kind == "Q" then
				local cx, cy, ex, ey = cmd[2] * scale, cmd[3] * scale, cmd[4] * scale, cmd[5] * scale
				local d = 0.25 * math.sqrt((px - 2 * cx + ex) ^ 2 + (py - 2 * cy + ey) ^ 2)
				local n = math.clamp(math.ceil(math.sqrt(d / TOLERANCE)), 1, 32)
				for k = 1, n do
					local t = k / n
					local u = 1 - t
					table.insert(pts, u * u * px + 2 * u * t * cx + t * t * ex)
					table.insert(pts, u * u * py + 2 * u * t * cy + t * t * ey)
				end
				px, py = ex, ey
			else
				local x1, y1, x2, y2, ex, ey =
					cmd[2] * scale, cmd[3] * scale, cmd[4] * scale, cmd[5] * scale, cmd[6] * scale, cmd[7] * scale
				local d1 = math.sqrt((px - 2 * x1 + x2) ^ 2 + (py - 2 * y1 + y2) ^ 2)
				local d2 = math.sqrt((x1 - 2 * x2 + ex) ^ 2 + (y1 - 2 * y2 + ey) ^ 2)
				local n = math.clamp(math.ceil(math.sqrt(0.75 * math.max(d1, d2) / TOLERANCE)), 1, 32)
				for k = 1, n do
					local t = k / n
					local u = 1 - t
					table.insert(pts, u * u * u * px + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * ex)
					table.insert(pts, u * u * u * py + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * ey)
				end
				px, py = ex, ey
			end
		end
		if #pts >= 6 then
			table.insert(polys, pts)
		end
	end
	return polys
end

-- Renders glyph `g` at `size` pixels per em. Returns nil for empty glyphs (e.g. space).
-- The bitmap has 1px of padding; the pen position is the origin: draw at (penX + left, baselineY - top).
function Font:rasterize(g: number, size: number): Bitmap?
	local contours = self:outline(g)
	if #contours == 0 then
		return nil
	end
	local polys = flatten(contours, size / self.unitsPerEm)
	if #polys == 0 then
		return nil
	end

	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, pts in polys do
		for i = 1, #pts, 2 do
			minX, maxX = math.min(minX, pts[i]), math.max(maxX, pts[i])
			minY, maxY = math.min(minY, pts[i + 1]), math.max(maxY, pts[i + 1])
		end
	end
	local x0, y1 = math.floor(minX) - 1, math.ceil(maxY) + 1
	local x1, y0 = math.ceil(maxX) + 1, math.floor(minY) - 1
	local w, h = x1 - x0, y1 - y0
	if w <= 0 or h <= 0 or w * h > 4194304 then
		return nil
	end
	local stride = w + 2
	local acc = table.create(stride * h + 4, 0)

	local function line(ax: number, ay: number, bx: number, by: number)
		if ay == by then
			return
		end
		local dir, px0, py0, px1, py1
		if ay < by then
			dir, px0, py0, px1, py1 = 1, ax, ay, bx, by
		else
			dir, px0, py0, px1, py1 = -1, bx, by, ax, ay
		end
		local dxdy = (px1 - px0) / (py1 - py0)
		local x = px0
		local ystart = math.max(0, math.floor(py0))
		if py0 < 0 then
			x -= py0 * dxdy
		end
		for yy = ystart, math.min(h, math.ceil(py1)) - 1 do
			local ls = yy * stride + 1
			local dy = math.min(yy + 1, py1) - math.max(yy, py0)
			local xn = x + dxdy * dy
			local d = dir * dy
			local xa, xb = x, xn
			if xn < x then
				xa, xb = xn, x
			end
			local xaf = math.floor(xa)
			local xai = xaf
			local xbc = math.ceil(xb)
			local xbi = xbc
			if xbi <= xai + 1 then
				local xmf = 0.5 * (x + xn) - xaf
				acc[ls + xai] += d - d * xmf
				acc[ls + xai + 1] += d * xmf
			else
				local s = 1 / (xb - xa)
				local x0f = xa - xaf
				local a0 = 0.5 * s * (1 - x0f) * (1 - x0f)
				local x1f = xb - xbc + 1
				local am = 0.5 * s * x1f * x1f
				acc[ls + xai] += d * a0
				if xbi == xai + 2 then
					acc[ls + xai + 1] += d * (1 - a0 - am)
				else
					local a1 = s * (1.5 - x0f)
					acc[ls + xai + 1] += d * (a1 - a0)
					for xi = xai + 2, xbi - 2 do
						acc[ls + xi] += d * s
					end
					local a2 = a1 + (xbi - xai - 3) * s
					acc[ls + xbi - 1] += d * (1 - a2 - am)
				end
				acc[ls + xbi] += d * am
			end
			x = xn
		end
	end

	for _, pts in polys do
		local n = #pts // 2
		for i = 0, n - 1 do
			local j = (i + 1) % n
			line(pts[i * 2 + 1] - x0, y1 - pts[i * 2 + 2], pts[j * 2 + 1] - x0, y1 - pts[j * 2 + 2])
		end
	end

	local out = buffer.create(w * h)
	for yy = 0, h - 1 do
		local s = 0
		local rowAcc = yy * stride + 1
		local rowOut = yy * w
		for xx = 0, w - 1 do
			s += acc[rowAcc + xx]
			local v = math.abs(s)
			if v > 1 then
				v = 1
			end
			buffer.writeu8(out, rowOut + xx, math.floor(v * 255 + 0.5))
		end
	end
	return { left = x0, top = y1, width = w, height = h, data = out }
end

return font
