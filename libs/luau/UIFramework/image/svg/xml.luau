--!nonstrict
--[[
	xml.luau - a small, forgiving XML parser (enough for SVG)

	local root = xml.parse(source)
	-- root = { tag = "#document", attrs = {}, children = { node, ... } }
	-- node = { tag = "rect", attrs = { x = "1", ... }, children = { ... }, parent = node }
	-- text node = { tag = "#text", text = "...", attrs = {}, children = {} }   (only kept when it contains non-blank characters)

	* namespace prefixes on tags are dropped ("svg:rect" -> "rect"); `xlink:href` is also available as `href`
	* comments, processing instructions and DOCTYPE (including an internal subset) are skipped; CDATA becomes a text node
	* the five predefined entities and numeric character references are decoded
	* malformed input raises an error that names the position
]]

local xml = {}

local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function decode(s: string): string
	if not string.find(s, "&", 1, true) then
		return s
	end
	return (string.gsub(s, "&(#?%w+);", function(e)
		if string.sub(e, 1, 1) == "#" then
			local code
			local second = string.sub(e, 2, 2)
			if second == "x" or second == "X" then
				code = tonumber(string.sub(e, 3), 16)
			else
				code = tonumber(string.sub(e, 2))
			end
			if code and code > 0 and code <= 0x10FFFF then
				local ok, ch = pcall(utf8.char, code)
				if ok then
					return ch
				end
			end
			return nil
		end
		return ENTITIES[e]
	end))
end
xml.decode = decode

local function lineOf(src: string, pos: number): number
	local line = 1
	for _ in string.gmatch(string.sub(src, 1, pos), "\n") do
		line += 1
	end
	return line
end

function xml.parse(src: string): any
	local len = #src
	local pos = 1
	local root = { tag = "#document", attrs = {}, children = {} }
	local stack = { root }
	local top = root

	local function fail(message: string, at: number)
		error(`xml: {message} (line {lineOf(src, at)})`, 0)
	end

	while pos <= len do
		local lt = string.find(src, "<", pos, true)
		if not lt then
			break
		end
		if lt > pos and top ~= root then
			local text = string.sub(src, pos, lt - 1)
			if string.find(text, "%S") then
				table.insert(top.children, { tag = "#text", text = decode(text), attrs = {}, children = {} })
			end
		end
		pos = lt

		if string.sub(src, pos, pos + 3) == "<!--" then
			local e = string.find(src, "-->", pos + 4, true)
			if not e then
				fail("unterminated comment", pos)
			end
			pos = e + 3
		elseif string.sub(src, pos, pos + 8) == "<![CDATA[" then
			local e = string.find(src, "]]>", pos + 9, true)
			if not e then
				fail("unterminated CDATA section", pos)
			end
			if top ~= root then
				table.insert(top.children, { tag = "#text", text = string.sub(src, pos + 9, e - 1), attrs = {}, children = {} })
			end
			pos = e + 3
		elseif string.sub(src, pos, pos + 1) == "<?" then
			local e = string.find(src, "?>", pos + 2, true)
			pos = (e or len) + 2
		elseif string.sub(src, pos, pos + 1) == "<!" then
			-- DOCTYPE and friends; an internal subset [ ... ] may contain '>' characters
			local brackets = 0
			local i = pos + 2
			while i <= len do
				local ch = string.sub(src, i, i)
				if ch == "[" then
					brackets += 1
				elseif ch == "]" then
					brackets -= 1
				elseif ch == ">" and brackets <= 0 then
					break
				end
				i += 1
			end
			pos = i + 1
		elseif string.sub(src, pos, pos + 1) == "</" then
			local name, after = string.match(src, "^</%s*([%w_:%.%-]+)%s*>()", pos)
			if not name then
				fail("malformed closing tag", pos)
			end
			name = (string.gsub(name, "^[%w_%-%.]+:", ""))
			-- close the nearest open element with this name (stray closing tags are ignored)
			for i = #stack, 2, -1 do
				if stack[i].tag == name then
					for _ = #stack, i, -1 do
						table.remove(stack)
					end
					top = stack[#stack]
					break
				end
			end
			pos = after
		else
			local name, p = string.match(src, "^<([%w_:%.%-]+)()", pos)
			if not name then
				fail("malformed tag", pos)
			end
			name = (string.gsub(name, "^[%w_%-%.]+:", ""))
			local attrs = {}
			local selfClose = false
			while true do
				local _, ws = string.find(src, "^%s*", p)
				p = ws + 1
				local c = string.sub(src, p, p)
				if c == ">" then
					p += 1
					break
				elseif c == "/" then
					if string.sub(src, p + 1, p + 1) == ">" then
						selfClose = true
						p += 2
						break
					end
					p += 1
				elseif c == "" then
					fail(`unexpected end of input inside <{name}>`, pos)
				else
					local attrName, ap = string.match(src, "^([%w_:%.%-]+)()", p)
					if not attrName then
						fail(`malformed attribute in <{name}>`, p)
					end
					p = ap
					local _, ws2 = string.find(src, "^%s*", p)
					p = ws2 + 1
					if string.sub(src, p, p) == "=" then
						p += 1
						local _, ws3 = string.find(src, "^%s*", p)
						p = ws3 + 1
						local q = string.sub(src, p, p)
						if q == '"' or q == "'" then
							local e = string.find(src, q, p + 1, true)
							if not e then
								fail(`unterminated attribute value in <{name}>`, p)
							end
							attrs[attrName] = decode(string.sub(src, p + 1, e - 1))
							p = e + 1
						else
							local v, vp = string.match(src, "^([^%s>/]+)()", p)
							if not v then
								fail(`missing attribute value in <{name}>`, p)
							end
							attrs[attrName] = decode(v)
							p = vp
						end
					else
						attrs[attrName] = ""
					end
				end
			end
			if attrs["xlink:href"] ~= nil and attrs.href == nil then
				attrs.href = attrs["xlink:href"]
			end
			local node = { tag = name, attrs = attrs, children = {}, parent = top }
			table.insert(top.children, node)
			if not selfClose then
				table.insert(stack, node)
				top = node
			end
			pos = p
		end
	end
	return root
end

return xml
