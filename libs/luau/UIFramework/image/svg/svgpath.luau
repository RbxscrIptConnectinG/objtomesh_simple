--!nonstrict
--[[
	svgpath.luau - the geometry half of the SVG renderer (used by svg.luau)

	* numbers / lengths / transforms / viewBox helpers
	* path data -> absolute commands { {"M",x,y}, {"L",x,y}, {"C",x1,y1,x2,y2,x,y}, {"Z"} }  (H V S Q T A are converted)
	* shape builders (rect, ellipse, polyline), curve flattening, bounds
	* dashing and stroking (a stroke becomes a set of polygons that are filled with the non-zero rule)

	A flattened path is a list of sub-paths: { pts = { x1, y1, x2, y2, ... }, closed = boolean, hadSeg = boolean }
	Matrices are { a, b, c, d, e, f }:  x' = a*x + c*y + e,  y' = b*x + d*y + f
]]

local P = {}

local abs, floor, ceil, sqrt, min, max = math.abs, math.floor, math.ceil, math.sqrt, math.min, math.max
local sin, cos, tan, atan2, acos, rad, pi = math.sin, math.cos, math.tan, math.atan2, math.acos, math.rad, math.pi

--------------------------------------------------------------------------
-- numbers
--------------------------------------------------------------------------

-- Reads a number at `pos`; returns (value, nextPos) or nil.
local function scanNumber(s: string, pos: number): (number?, number?)
	local _, e = string.find(s, "^[-+]?%d*%.?%d*", pos)
	if not e or e < pos then
		return nil, nil
	end
	local mantissa = string.sub(s, pos, e)
	if not string.find(mantissa, "%d") then
		return nil, nil
	end
	local _, e2 = string.find(s, "^[eE][-+]?%d+", e + 1)
	if e2 then
		e = e2
	end
	local text = string.sub(s, pos, e)
	if string.sub(text, 1, 1) == "+" then
		text = string.sub(text, 2)
	end
	local v = tonumber(text)
	if v == nil then
		return nil, nil
	end
	return v, e + 1
end
P.scanNumber = scanNumber

function P.parseNumberList(s: string): { number }
	local out, pos = {}, 1
	while true do
		local _, ws = string.find(s, "^[%s,]*", pos)
		pos = ws + 1
		local v, np = scanNumber(s, pos)
		if not v then
			break
		end
		out[#out + 1] = v
		pos = np
	end
	return out
end

local UNITS = { px = 1, pt = 4 / 3, pc = 16, mm = 96 / 25.4, cm = 96 / 2.54, ["in"] = 96 }

-- "12", "12px", "50%", "2em" ... -> number in user units (percentBase: what 100% means; nil = percentages are invalid)
function P.parseLength(s: any, percentBase: number?, fontSize: number?): number?
	if type(s) ~= "string" then
		return nil
	end
	s = string.match(s, "^%s*(.-)%s*$")
	local v, np = scanNumber(s, 1)
	if v == nil then
		return nil
	end
	local unit = string.lower(string.sub(s, np))
	if unit == "" or unit == "px" then
		return v
	elseif unit == "%" then
		if percentBase then
			return v / 100 * percentBase
		end
		return nil
	elseif unit == "em" then
		return v * (fontSize or 16)
	elseif unit == "ex" then
		return v * (fontSize or 16) / 2
	elseif UNITS[unit] then
		return v * UNITS[unit]
	end
	return nil
end

--------------------------------------------------------------------------
-- matrices
--------------------------------------------------------------------------

P.IDENTITY = { 1, 0, 0, 1, 0, 0 }

-- m * n (n is applied first)
local function mmul(m, n)
	return {
		m[1] * n[1] + m[3] * n[2], m[2] * n[1] + m[4] * n[2],
		m[1] * n[3] + m[3] * n[4], m[2] * n[3] + m[4] * n[4],
		m[1] * n[5] + m[3] * n[6] + m[5], m[2] * n[5] + m[4] * n[6] + m[6],
	}
end
P.mul = mmul

function P.invert(m)
	local det = m[1] * m[4] - m[2] * m[3]
	if abs(det) < 1e-14 or det ~= det then
		return nil
	end
	local id = 1 / det
	return {
		m[4] * id, -m[2] * id, -m[3] * id, m[1] * id,
		(m[3] * m[6] - m[4] * m[5]) * id, (m[2] * m[5] - m[1] * m[6]) * id,
	}
end

-- largest axis scale of the matrix (used to pick flattening tolerances)
function P.matrixScale(m): number
	return max(sqrt(m[1] * m[1] + m[2] * m[2]), sqrt(m[3] * m[3] + m[4] * m[4]))
end

-- "translate(10 20) rotate(45)" -> matrix (nil when the attribute is empty)
function P.parseTransform(str: string?)
	if str == nil or str == "" then
		return nil
	end
	local m = P.IDENTITY
	for name, args in string.gmatch(str, "(%a+)%s*%(([^%)]*)%)") do
		local n = P.parseNumberList(args)
		local t
		if name == "matrix" then
			if #n >= 6 then
				t = { n[1], n[2], n[3], n[4], n[5], n[6] }
			end
		elseif name == "translate" then
			t = { 1, 0, 0, 1, n[1] or 0, n[2] or 0 }
		elseif name == "scale" then
			local sx = n[1] or 1
			t = { sx, 0, 0, n[2] or sx, 0, 0 }
		elseif name == "rotate" then
			local a = rad(n[1] or 0)
			local c, s = cos(a), sin(a)
			t = { c, s, -s, c, 0, 0 }
			if n[2] then
				local cx, cy = n[2], n[3] or 0
				t = mmul({ 1, 0, 0, 1, cx, cy }, mmul(t, { 1, 0, 0, 1, -cx, -cy }))
			end
		elseif name == "skewX" then
			t = { 1, 0, tan(rad(n[1] or 0)), 1, 0, 0 }
		elseif name == "skewY" then
			t = { 1, tan(rad(n[1] or 0)), 0, 1, 0, 0 }
		end
		if t then
			m = mmul(m, t)
		end
	end
	return m
end

function P.parseViewBox(s: any)
	if type(s) ~= "string" then
		return nil
	end
	local n = P.parseNumberList(s)
	if #n < 4 or n[3] <= 0 or n[4] <= 0 then
		return nil
	end
	return { x = n[1], y = n[2], w = n[3], h = n[4] }
end

-- viewBox -> viewport of size w x h, honouring preserveAspectRatio ("xMidYMid meet", "none", "xMinYMax slice", ...)
function P.viewBoxMatrix(vb, w: number, h: number, par: string?)
	local align, slice = "xMidYMid", false
	if par then
		local a, ms = string.match(par, "^%s*defer%s+(%S+)%s*(%S*)")
		if not a then
			a, ms = string.match(par, "^%s*(%S+)%s*(%S*)")
		end
		if a then
			align = a
			slice = (ms == "slice")
		end
	end
	local sx, sy = w / vb.w, h / vb.h
	if align == "none" then
		return { sx, 0, 0, sy, -vb.x * sx, -vb.y * sy }
	end
	local s = if slice then max(sx, sy) else min(sx, sy)
	local ex, ey = w - vb.w * s, h - vb.h * s
	local ox, oy = 0, 0
	if string.find(align, "xMid", 1, true) then
		ox = ex / 2
	elseif string.find(align, "xMax", 1, true) then
		ox = ex
	end
	if string.find(align, "YMid", 1, true) then
		oy = ey / 2
	elseif string.find(align, "YMax", 1, true) then
		oy = ey
	end
	return { s, 0, 0, s, -vb.x * s + ox, -vb.y * s + oy }
end

--------------------------------------------------------------------------
-- path data
--------------------------------------------------------------------------

-- Appends cubic segments for an SVG elliptical arc to `out`.
local function arcToCubics(out, x1, y1, rx, ry, phiDeg, fa, fs, x2, y2)
	if x1 == x2 and y1 == y2 then
		return
	end
	rx, ry = abs(rx), abs(ry)
	if rx == 0 or ry == 0 then
		out[#out + 1] = { "L", x2, y2 }
		return
	end
	local phi = rad(phiDeg)
	local cp, sp = cos(phi), sin(phi)
	local dx2, dy2 = (x1 - x2) / 2, (y1 - y2) / 2
	local x1p = cp * dx2 + sp * dy2
	local y1p = -sp * dx2 + cp * dy2
	local lam = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
	if lam > 1 then
		local s = sqrt(lam)
		rx *= s
		ry *= s
	end
	local rx2, ry2 = rx * rx, ry * ry
	local num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
	local den = rx2 * y1p * y1p + ry2 * x1p * x1p
	local coef = 0
	if den > 0 then
		coef = sqrt(max(0, num / den))
	end
	if fa == fs then
		coef = -coef
	end
	local cxp = coef * rx * y1p / ry
	local cyp = -coef * ry * x1p / rx
	local cx = cp * cxp - sp * cyp + (x1 + x2) / 2
	local cy = sp * cxp + cp * cyp + (y1 + y2) / 2
	local ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
	local vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
	local th1 = atan2(uy, ux)
	local dth = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	if fs == 0 and dth > 0 then
		dth -= 2 * pi
	elseif fs == 1 and dth < 0 then
		dth += 2 * pi
	end
	local n = max(1, ceil(abs(dth) / (pi / 2) - 1e-9))
	local delta = dth / n
	local t = 4 / 3 * tan(delta / 4)
	for i = 0, n - 1 do
		local a1 = th1 + i * delta
		local a2 = a1 + delta
		local c1, s1, c2, s2 = cos(a1), sin(a1), cos(a2), sin(a2)
		local function pt(px, py)
			return cp * rx * px - sp * ry * py + cx, sp * rx * px + cp * ry * py + cy
		end
		local q1x, q1y = pt(c1 - t * s1, s1 + t * c1)
		local q2x, q2y = pt(c2 + t * s2, s2 - t * c2)
		local q3x, q3y = pt(c2, s2)
		if i == n - 1 then
			q3x, q3y = x2, y2
		end
		out[#out + 1] = { "C", q1x, q1y, q2x, q2y, q3x, q3y }
	end
end

-- Parses the `d` attribute. Like browsers, it renders everything before the first error.
function P.parsePathData(d: string): { any }
	local cmds = {}
	local len = #d
	local pos = 1
	local cx, cy, sx, sy = 0, 0, 0, 0
	local cmd = nil
	local prevKind = nil -- "C" after C/S, "Q" after Q/T
	local lcx, lcy = 0, 0 -- last control point
	local needMove = false
	local started = false

	local function skip()
		local _, e = string.find(d, "^[%s,]*", pos)
		pos = e + 1
	end
	local function number(): number?
		skip()
		local v, np = scanNumber(d, pos)
		if v == nil then
			return nil
		end
		pos = np
		return v
	end
	local function flag(): number?
		skip()
		local c = string.sub(d, pos, pos)
		if c == "0" or c == "1" then
			pos += 1
			return tonumber(c)
		end
		return nil
	end
	local function read(n: number): { number }?
		local t = {}
		for i = 1, n do
			local v = number()
			if v == nil then
				return nil
			end
			t[i] = v
		end
		return t
	end
	local function ensureMove()
		if needMove then
			cmds[#cmds + 1] = { "M", sx, sy }
			needMove = false
		end
	end

	while true do
		skip()
		if pos > len then
			break
		end
		local c = string.sub(d, pos, pos)
		if string.find(c, "^[MmLlHhVvCcSsQqTtAaZz]$") then
			cmd = c
			pos += 1
			if not started and c ~= "M" and c ~= "m" then
				break
			end
		elseif cmd == nil or cmd == "Z" or cmd == "z" then
			break
		end

		local up = string.upper(cmd)
		local rel = (cmd ~= up) and started
		local ox, oy = 0, 0
		if rel then
			ox, oy = cx, cy
		end

		if up == "Z" then
			cmds[#cmds + 1] = { "Z" }
			cx, cy = sx, sy
			needMove = true
			prevKind = nil
		elseif up == "M" then
			local a = read(2)
			if not a then
				break
			end
			cx, cy = a[1] + ox, a[2] + oy
			sx, sy = cx, cy
			cmds[#cmds + 1] = { "M", cx, cy }
			started = true
			needMove = false
			prevKind = nil
			cmd = if cmd == "m" then "l" else "L"
		elseif up == "L" then
			local a = read(2)
			if not a then
				break
			end
			ensureMove()
			cx, cy = a[1] + ox, a[2] + oy
			cmds[#cmds + 1] = { "L", cx, cy }
			prevKind = nil
		elseif up == "H" then
			local x = number()
			if x == nil then
				break
			end
			ensureMove()
			cx = x + ox
			cmds[#cmds + 1] = { "L", cx, cy }
			prevKind = nil
		elseif up == "V" then
			local y = number()
			if y == nil then
				break
			end
			ensureMove()
			cy = y + oy
			cmds[#cmds + 1] = { "L", cx, cy }
			prevKind = nil
		elseif up == "C" then
			local a = read(6)
			if not a then
				break
			end
			ensureMove()
			local x1, y1, x2, y2, x, y = a[1] + ox, a[2] + oy, a[3] + ox, a[4] + oy, a[5] + ox, a[6] + oy
			cmds[#cmds + 1] = { "C", x1, y1, x2, y2, x, y }
			lcx, lcy = x2, y2
			cx, cy = x, y
			prevKind = "C"
		elseif up == "S" then
			local a = read(4)
			if not a then
				break
			end
			ensureMove()
			local x1, y1 = cx, cy
			if prevKind == "C" then
				x1, y1 = 2 * cx - lcx, 2 * cy - lcy
			end
			local x2, y2, x, y = a[1] + ox, a[2] + oy, a[3] + ox, a[4] + oy
			cmds[#cmds + 1] = { "C", x1, y1, x2, y2, x, y }
			lcx, lcy = x2, y2
			cx, cy = x, y
			prevKind = "C"
		elseif up == "Q" then
			local a = read(4)
			if not a then
				break
			end
			ensureMove()
			local qx, qy, x, y = a[1] + ox, a[2] + oy, a[3] + ox, a[4] + oy
			cmds[#cmds + 1] = {
				"C", cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy), x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), x, y,
			}
			lcx, lcy = qx, qy
			cx, cy = x, y
			prevKind = "Q"
		elseif up == "T" then
			local a = read(2)
			if not a then
				break
			end
			ensureMove()
			local qx, qy = cx, cy
			if prevKind == "Q" then
				qx, qy = 2 * cx - lcx, 2 * cy - lcy
			end
			local x, y = a[1] + ox, a[2] + oy
			cmds[#cmds + 1] = {
				"C", cx + 2 / 3 * (qx - cx), cy + 2 / 3 * (qy - cy), x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), x, y,
			}
			lcx, lcy = qx, qy
			cx, cy = x, y
			prevKind = "Q"
		elseif up == "A" then
			local rx, ry, rot = number(), number(), number()
			local fa = if rot ~= nil then flag() else nil
			local fs = if fa ~= nil then flag() else nil
			local x = if fs ~= nil then number() else nil
			local y = if x ~= nil then number() else nil
			if y == nil then
				break
			end
			ensureMove()
			local nx, ny = x + ox, y + oy
			arcToCubics(cmds, cx, cy, rx, ry, rot, fa, fs, nx, ny)
			cx, cy = nx, ny
			prevKind = nil
		end
	end
	return cmds
end

--------------------------------------------------------------------------
-- shapes
--------------------------------------------------------------------------

local K = 0.5522847498307936

function P.rectPath(x: number, y: number, w: number, h: number, rx: number, ry: number)
	if rx <= 0 or ry <= 0 then
		return {
			{ "M", x, y }, { "L", x + w, y }, { "L", x + w, y + h }, { "L", x, y + h }, { "Z" },
		}
	end
	local kx, ky = K * rx, K * ry
	return {
		{ "M", x + rx, y },
		{ "L", x + w - rx, y },
		{ "C", x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry },
		{ "L", x + w, y + h - ry },
		{ "C", x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h },
		{ "L", x + rx, y + h },
		{ "C", x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry },
		{ "L", x, y + ry },
		{ "C", x, y + ry - ky, x + rx - kx, y, x + rx, y },
		{ "Z" },
	}
end

function P.ellipsePath(cx: number, cy: number, rx: number, ry: number)
	local kx, ky = K * rx, K * ry
	return {
		{ "M", cx + rx, cy },
		{ "C", cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry },
		{ "C", cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy },
		{ "C", cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry },
		{ "C", cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy },
		{ "Z" },
	}
end

function P.polyPath(points: string, close: boolean)
	local n = P.parseNumberList(points)
	local cmds = {}
	for i = 1, #n - 1, 2 do
		cmds[#cmds + 1] = { if i == 1 then "M" else "L", n[i], n[i + 1] }
	end
	if close and #cmds > 0 then
		cmds[#cmds + 1] = { "Z" }
	end
	return cmds
end

--------------------------------------------------------------------------
-- flattening
--------------------------------------------------------------------------

-- Path commands -> sub-paths of straight segments; `tol` is the largest allowed distance from the curve (in path units).
function P.flatten(cmds, tol: number)
	local subs = {}
	local cur = nil
	local cx, cy = 0, 0
	local sx, sy = 0, 0
	for _, c in cmds do
		local t = c[1]
		if t == "M" then
			cur = { pts = { c[2], c[3] }, closed = false, hadSeg = false }
			subs[#subs + 1] = cur
			cx, cy = c[2], c[3]
			sx, sy = cx, cy
		elseif t == "L" then
			if cur then
				local p = cur.pts
				p[#p + 1] = c[2]
				p[#p + 1] = c[3]
				cur.hadSeg = true
			end
			cx, cy = c[2], c[3]
		elseif t == "C" then
			local x1, y1, x2, y2, x3, y3 = c[2], c[3], c[4], c[5], c[6], c[7]
			if cur then
				local d1x, d1y = cx - 2 * x1 + x2, cy - 2 * y1 + y2
				local d2x, d2y = x1 - 2 * x2 + x3, y1 - 2 * y2 + y3
				local dd = max(sqrt(d1x * d1x + d1y * d1y), sqrt(d2x * d2x + d2y * d2y))
				local n = ceil(sqrt(0.75 * dd / tol))
				if n ~= n or n < 1 then
					n = 1
				elseif n > 128 then
					n = 128
				end
				local p = cur.pts
				for i = 1, n do
					local u = i / n
					local mu = 1 - u
					local b0, b1, b2, b3 = mu * mu * mu, 3 * mu * mu * u, 3 * mu * u * u, u * u * u
					p[#p + 1] = b0 * cx + b1 * x1 + b2 * x2 + b3 * x3
					p[#p + 1] = b0 * cy + b1 * y1 + b2 * y2 + b3 * y3
				end
				cur.hadSeg = true
			end
			cx, cy = x3, y3
		elseif t == "Z" then
			if cur then
				cur.closed = true
			end
			cur = nil
			cx, cy = sx, sy
		end
	end
	return subs
end

function P.bounds(subs): (number?, number?, number?, number?)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, s in subs do
		local p = s.pts
		for i = 1, #p, 2 do
			local x, y = p[i], p[i + 1]
			if x < x0 then x0 = x end
			if x > x1 then x1 = x end
			if y < y0 then y0 = y end
			if y > y1 then y1 = y end
		end
	end
	if x0 > x1 then
		return nil, nil, nil, nil
	end
	return x0, y0, x1, y1
end

--------------------------------------------------------------------------
-- dashing
--------------------------------------------------------------------------

function P.dash(subs, arr: { number }, offset: number)
	local n = #arr
	local total = 0
	for i = 1, n do
		total += arr[i]
	end
	if total <= 0 then
		return subs
	end
	-- refuse absurd dash counts
	local length = 0
	for _, s in subs do
		local p = s.pts
		for i = 3, #p, 2 do
			length += sqrt((p[i] - p[i - 2]) ^ 2 + (p[i + 1] - p[i - 1]) ^ 2)
		end
	end
	if length / total * n > 100000 then
		return subs
	end

	local out = {}
	for _, s in subs do
		local p = s.pts
		local pts = table.clone(p)
		if s.closed and #p >= 4 then
			pts[#pts + 1] = p[1]
			pts[#pts + 1] = p[2]
		end
		if #pts >= 4 then
			local idx, on = 1, true
			local off = offset % total
			while off >= arr[idx] do
				off -= arr[idx]
				idx = idx % n + 1
				on = not on
			end
			local remain = arr[idx] - off
			local px, py = pts[1], pts[2]
			local cur = if on then { pts = { px, py }, closed = false, hadSeg = false } else nil
			for i = 3, #pts, 2 do
				local ax, ay, bx, by = pts[i - 2], pts[i - 1], pts[i], pts[i + 1]
				local dx, dy = bx - ax, by - ay
				local segLen = sqrt(dx * dx + dy * dy)
				local pos = 0
				px, py = ax, ay
				if segLen > 1e-12 then
					while true do
						if remain > 1e-12 then
							local avail = segLen - pos
							if avail <= 1e-12 then
								break
							end
							local step = min(remain, avail)
							pos += step
							remain -= step
							local u = pos / segLen
							px, py = ax + dx * u, ay + dy * u
							if on then
								local q = cur.pts
								q[#q + 1] = px
								q[#q + 1] = py
								cur.hadSeg = true
							end
						end
						if remain <= 1e-12 then
							if on and cur then
								cur.hadSeg = true
								out[#out + 1] = cur
								cur = nil
							end
							idx = idx % n + 1
							on = not on
							remain = arr[idx]
							if on then
								cur = { pts = { px, py }, closed = false, hadSeg = false }
							end
						end
					end
				end
			end
			if on and cur and #cur.pts >= 2 then
				out[#out + 1] = cur
			end
		end
	end
	return out
end

--------------------------------------------------------------------------
-- stroking
--------------------------------------------------------------------------

-- Turns sub-paths into polygons ({ x1, y1, x2, y2, ... } each) that together cover the stroke.
-- hw: half the stroke width; cap: "butt" | "round" | "square"; join: "miter" | "round" | "bevel"; arcStep: radians per round segment.
function P.stroke(subs, hw: number, cap: string, join: string, miterlimit: number, arcStep: number)
	local polys = {}

	local function circle(cx, cy)
		local steps = max(8, ceil(2 * pi / arcStep))
		local pts = {}
		for i = 0, steps - 1 do
			local a = 2 * pi * i / steps
			pts[#pts + 1] = cx + hw * cos(a)
			pts[#pts + 1] = cy + hw * sin(a)
		end
		polys[#polys + 1] = pts
	end

	local function addJoin(vx, vy, d0x, d0y, d1x, d1y)
		local cross = d0x * d1y - d0y * d1x
		local dot = d0x * d1x + d0y * d1y
		if abs(cross) < 1e-9 and dot > 0 then
			return
		end
		local s = if cross > 0 then -1 else 1 -- the outer side of the turn
		local n0x, n0y = -d0y * s * hw, d0x * s * hw
		local n1x, n1y = -d1y * s * hw, d1x * s * hw
		local ax, ay = vx + n0x, vy + n0y
		local bx, by = vx + n1x, vy + n1y
		if join == "round" then
			local a0 = atan2(n0y, n0x)
			local delta = atan2(n1y, n1x) - a0
			while delta > pi do
				delta -= 2 * pi
			end
			while delta <= -pi do
				delta += 2 * pi
			end
			local steps = max(1, ceil(abs(delta) / arcStep))
			local pts = { vx, vy, ax, ay }
			for i = 1, steps do
				local a = a0 + delta * i / steps
				pts[#pts + 1] = vx + hw * cos(a)
				pts[#pts + 1] = vy + hw * sin(a)
			end
			polys[#polys + 1] = pts
			return
		end
		if join == "miter" then
			local cosHalf = sqrt(max(0, (1 + dot) / 2))
			if cosHalf > 1e-6 and 1 / cosHalf <= miterlimit then
				local k = 1 / (1 + dot)
				polys[#polys + 1] = { vx, vy, ax, ay, vx + (n0x + n1x) * k, vy + (n0y + n1y) * k, bx, by }
				return
			end
		end
		polys[#polys + 1] = { vx, vy, ax, ay, bx, by }
	end

	local function addCap(px, py, dx, dy, atEnd: boolean)
		if cap == "butt" then
			return
		end
		local nx, ny = -dy * hw, dx * hw
		local f = if atEnd then 1 else -1 -- direction the cap bulges, along d
		if cap == "square" then
			local ex, ey = dx * hw * f, dy * hw * f
			polys[#polys + 1] = { px + nx, py + ny, px + nx + ex, py + ny + ey, px - nx + ex, py - ny + ey, px - nx, py - ny }
		else
			local steps = max(4, ceil(pi / arcStep))
			local a0 = atan2(ny, nx)
			local pts = {}
			for i = 0, steps do
				local a = a0 + (if atEnd then -pi else pi) * i / steps
				pts[#pts + 1] = px + hw * cos(a)
				pts[#pts + 1] = py + hw * sin(a)
			end
			polys[#polys + 1] = pts
		end
	end

	for _, sub in subs do
		local p = sub.pts
		local xs, ys, k = {}, {}, 0
		for i = 1, #p, 2 do
			local x, y = p[i], p[i + 1]
			if k == 0 or abs(x - xs[k]) > 1e-9 or abs(y - ys[k]) > 1e-9 then
				k += 1
				xs[k], ys[k] = x, y
			end
		end
		local closed = sub.closed
		if closed and k > 1 and abs(xs[k] - xs[1]) <= 1e-9 and abs(ys[k] - ys[1]) <= 1e-9 then
			k -= 1
		end

		if k == 1 then
			if closed or sub.hadSeg then
				if cap == "round" then
					circle(xs[1], ys[1])
				elseif cap == "square" then
					local x, y = xs[1], ys[1]
					polys[#polys + 1] = { x - hw, y - hw, x + hw, y - hw, x + hw, y + hw, x - hw, y + hw }
				end
			end
		elseif k >= 2 then
			local nseg = if closed then k else k - 1
			local ux, uy = {}, {}
			for i = 1, nseg do
				local j = i % k + 1
				local dx, dy = xs[j] - xs[i], ys[j] - ys[i]
				local l = sqrt(dx * dx + dy * dy)
				ux[i], uy[i] = dx / l, dy / l
				local nx, ny = -uy[i] * hw, ux[i] * hw
				polys[#polys + 1] = {
					xs[i] + nx, ys[i] + ny, xs[j] + nx, ys[j] + ny, xs[j] - nx, ys[j] - ny, xs[i] - nx, ys[i] - ny,
				}
			end
			if closed then
				for i = 1, k do
					local a = (i - 2) % k + 1
					addJoin(xs[i], ys[i], ux[a], uy[a], ux[i], uy[i])
				end
			else
				for i = 2, k - 1 do
					addJoin(xs[i], ys[i], ux[i - 1], uy[i - 1], ux[i], uy[i])
				end
				addCap(xs[1], ys[1], ux[1], uy[1], false)
				addCap(xs[k], ys[k], ux[nseg], uy[nseg], true)
			end
		end
	end
	return polys
end

return P
