--[[
	image.luau - PNG image importer

	local w, h, rgba = image.decode(bytes, options?)       -- PNG or SVG file contents (string or buffer)
	local w, h, rgba = image.decodeFile("textures/brick.png", options?)
	local levels = image.mipChain(rgba, w, h)              -- { {width=, height=, data=}, ... } level 0 = the input

	PNG (all colour types / bit depths, interlaced or not - see png.luau) and SVG (see svg.luau) are supported. An SVG is rasterized at its
	intrinsic size; `options` = { width =, height =, scale =, color =, background =, preserveAspectRatio =, bleed = } picks another size or
	look (they are the svg.rasterize options; PNG ignores them).
	Output is RGBA8 (non-premultiplied) in a buffer, top row first.
	Errors are thrown with a message that names the problem (use pcall when importing user files).
]]

local png = require("@self/png")
local svg = require("@self/svg")

local image = {}

image.libs = {
	png = png,
	svg = svg,
}

function image.isPNG(data: string | buffer): boolean
	local b: buffer = if type(data) == "string" then buffer.fromstring(data) else data
	return buffer.len(b) >= 8 and buffer.readu8(b, 0) == 137 and buffer.readstring(b, 1, 3) == "PNG"
end

function image.isSVG(data: string | buffer): boolean
	return svg.isSVG(data)
end

function image.decode(data: string | buffer, options: { [string]: any }?): (number?, number?, buffer?)
	if image.isPNG(data) then
		return png.decode(data)
	end
	if svg.isSVG(data) then
		return svg.rasterize(data, options and options.width, options and options.height, options)
	end
	error("image: only PNG and SVG files are supported")
end

function image.extension(path: string): string?
	local ext = string.match(path, "%.([%w]+)$")
	return if ext then string.lower(ext) else nil
end

function image.basename(path: string): string
	return string.match(path, "([^/\\]+)$") or path
end

function image.decodeFile(path: string, options: { [string]: any }?): (number?, number?, buffer?)
	return image.decode(zune.fs.readFileSync(path, true), options)
end

-- In-place vertical flip.
function image.flipY(rgba: buffer, width: number, height: number)
	local rowBytes = width * 4
	local tmp = buffer.create(rowBytes)
	for y = 0, height // 2 - 1 do
		local a, bb = y * rowBytes, (height - 1 - y) * rowBytes
		buffer.copy(tmp, 0, rgba, a, rowBytes)
		buffer.copy(rgba, a, rgba, bb, rowBytes)
		buffer.copy(rgba, bb, tmp, 0, rowBytes)
	end
end

-- Box-filtered mip chain (alpha-weighted so transparent texels do not darken the edges).
-- Returns { { width, height, data } ... } with level 0 being the input buffer itself.
function image.mipChain(rgba: buffer, width: number, height: number): { { [string]: any } }
	local levels = { { width = width, height = height, data = rgba } }
	local cw, ch, cur = width, height, rgba
	while cw > 1 or ch > 1 do
		local nw, nh = math.max(1, cw // 2), math.max(1, ch // 2)
		local nxt = buffer.create(nw * nh * 4)
		for y = 0, nh - 1 do
			local y0, y1 = math.min(2 * y, ch - 1), math.min(2 * y + 1, ch - 1)
			for x = 0, nw - 1 do
				local x0, x1 = math.min(2 * x, cw - 1), math.min(2 * x + 1, cw - 1)
				local sa, sr, sg, sb = 0, 0, 0, 0
				local ur, ug, ub = 0, 0, 0
				for i = 1, 4 do
					local sx = if i % 2 == 1 then x0 else x1
					local sy = if i <= 2 then y0 else y1
					local o = (sy * cw + sx) * 4
					local r, g, bl, a =
						buffer.readu8(cur, o),
						buffer.readu8(cur, o + 1),
						buffer.readu8(cur, o + 2),
						buffer.readu8(cur, o + 3)
					sa += a
					sr += r * a
					sg += g * a
					sb += bl * a
					ur += r
					ug += g
					ub += bl
				end
				local o = (y * nw + x) * 4
				if sa > 0 then
					buffer.writeu8(nxt, o, math.floor(sr / sa + 0.5))
					buffer.writeu8(nxt, o + 1, math.floor(sg / sa + 0.5))
					buffer.writeu8(nxt, o + 2, math.floor(sb / sa + 0.5))
				else
					buffer.writeu8(nxt, o, (ur + 2) // 4)
					buffer.writeu8(nxt, o + 1, (ug + 2) // 4)
					buffer.writeu8(nxt, o + 2, (ub + 2) // 4)
				end
				buffer.writeu8(nxt, o + 3, (sa + 2) // 4)
			end
		end
		table.insert(levels, { width = nw, height = nh, data = nxt })
		cw, ch, cur = nw, nh, nxt
	end
	return levels
end

return image
