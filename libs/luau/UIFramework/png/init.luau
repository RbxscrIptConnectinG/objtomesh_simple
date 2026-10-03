--[[
	png.luau - small PNG decoder (non-interlaced; 8/16-bit grey, grey+alpha, RGB, RGBA; 8-bit palette)

	local width, height, rgba = png.decode(fileContents)  -- rgba: buffer, width*height*4 bytes

	Uses zune.serde.zlib.decompress for the IDAT stream.
	Interlaced (Adam7) and <8-bit images are rejected with a clear error.
]]

local png = {}

local SIGNATURE = { 137, 80, 78, 71, 13, 10, 26, 10 }

local function be32(b: buffer, offset: number): number
	return buffer.readu8(b, offset) * 16777216
		+ buffer.readu8(b, offset + 1) * 65536
		+ buffer.readu8(b, offset + 2) * 256
		+ buffer.readu8(b, offset + 3)
end

function png.decode(data: string | buffer): (number, number, buffer)
	local b: buffer = if type(data) == "string" then buffer.fromstring(data) else data
	local len = buffer.len(b)
	if len < 33 then
		error("png: file too small")
	end
	for i = 1, 8 do
		if buffer.readu8(b, i - 1) ~= SIGNATURE[i] then
			error("png: bad signature")
		end
	end

	local width, height, depth, ctype, interlace = 0, 0, 0, 0, 0
	local palette: buffer? = nil
	local trns: buffer? = nil
	local idatParts: { { number } } = {}
	local idatTotal = 0

	local pos = 8
	while pos + 8 <= len do
		local size = be32(b, pos)
		local ctypeName = buffer.readstring(b, pos + 4, 4)
		local body = pos + 8
		if ctypeName == "IHDR" then
			width, height = be32(b, body), be32(b, body + 4)
			depth, ctype = buffer.readu8(b, body + 8), buffer.readu8(b, body + 9)
			interlace = buffer.readu8(b, body + 12)
		elseif ctypeName == "PLTE" then
			palette = buffer.create(size)
			buffer.copy(palette :: buffer, 0, b, body, size)
		elseif ctypeName == "tRNS" then
			trns = buffer.create(size)
			buffer.copy(trns :: buffer, 0, b, body, size)
		elseif ctypeName == "IDAT" then
			table.insert(idatParts, { body, size })
			idatTotal += size
		elseif ctypeName == "IEND" then
			break
		end
		pos = body + size + 4 -- skip CRC
	end

	if width == 0 or height == 0 then
		error("png: missing IHDR")
	end
	if interlace ~= 0 then
		error("png: interlaced images are not supported")
	end
	local channels = ({ [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 })[ctype]
	if not channels then
		error("png: unsupported colour type " .. ctype)
	end
	if not (depth == 8 or (depth == 16 and ctype ~= 3)) then
		error("png: unsupported bit depth " .. depth .. " (need 8, or 16 for non-palette)")
	end
	if ctype == 3 and not palette then
		error("png: palette image without PLTE")
	end

	local compressed = buffer.create(idatTotal)
	local at = 0
	for _, part in idatParts do
		buffer.copy(compressed, at, b, part[1], part[2])
		at += part[2]
	end
	local zlib = zune.serde and zune.serde.zlib
	if not zlib then
		error("png: zune.serde.zlib is unavailable; decode the image yourself and call renderer:createTexture(w, h, rgba)")
	end
	local raw: buffer = zlib.decompress(compressed)

	local bps = depth // 8 -- bytes per sample
	local bpp = channels * bps -- bytes per pixel
	local rowBytes = width * bpp
	if buffer.len(raw) < (rowBytes + 1) * height then
		error("png: truncated image data")
	end

	-- reverse scanline filters into `pix`
	local pix = buffer.create(rowBytes * height)
	for y = 0, height - 1 do
		local src = y * (rowBytes + 1)
		local filter = buffer.readu8(raw, src)
		local row = y * rowBytes
		for x = 0, rowBytes - 1 do
			local cur = buffer.readu8(raw, src + 1 + x)
			local a = if x >= bpp then buffer.readu8(pix, row + x - bpp) else 0
			local up = if y > 0 then buffer.readu8(pix, row + x - rowBytes) else 0
			local v: number
			if filter == 0 then
				v = cur
			elseif filter == 1 then
				v = cur + a
			elseif filter == 2 then
				v = cur + up
			elseif filter == 3 then
				v = cur + (a + up) // 2
			elseif filter == 4 then
				local c = if (x >= bpp and y > 0) then buffer.readu8(pix, row + x - rowBytes - bpp) else 0
				local p = a + up - c
				local pa, pb, pc = math.abs(p - a), math.abs(p - up), math.abs(p - c)
				local pr = if pa <= pb and pa <= pc then a elseif pb <= pc then up else c
				v = cur + pr
			else
				error("png: bad filter type " .. filter)
			end
			buffer.writeu8(pix, row + x, v % 256)
		end
	end

	-- convert to RGBA8 (16-bit samples keep their high byte)
	local out = buffer.create(width * height * 4)
	for y = 0, height - 1 do
		local row = y * rowBytes
		for x = 0, width - 1 do
			local p = row + x * bpp
			local o = (y * width + x) * 4
			local r, g, bl, al
			if ctype == 6 then
				r, g, bl, al = buffer.readu8(pix, p), buffer.readu8(pix, p + bps), buffer.readu8(pix, p + 2 * bps), buffer.readu8(pix, p + 3 * bps)
			elseif ctype == 2 then
				r, g, bl, al = buffer.readu8(pix, p), buffer.readu8(pix, p + bps), buffer.readu8(pix, p + 2 * bps), 255
			elseif ctype == 0 then
				r = buffer.readu8(pix, p)
				g, bl, al = r, r, 255
			elseif ctype == 4 then
				r = buffer.readu8(pix, p)
				g, bl, al = r, r, buffer.readu8(pix, p + bps)
			else -- palette
				local idx = buffer.readu8(pix, p)
				r, g, bl = buffer.readu8(palette :: buffer, idx * 3), buffer.readu8(palette :: buffer, idx * 3 + 1), buffer.readu8(palette :: buffer, idx * 3 + 2)
				al = if trns and idx < buffer.len(trns :: buffer) then buffer.readu8(trns :: buffer, idx) else 255
			end
			buffer.writeu8(out, o, r)
			buffer.writeu8(out, o + 1, g)
			buffer.writeu8(out, o + 2, bl)
			buffer.writeu8(out, o + 3, al)
		end
	end

	return width, height, out
end

return png
