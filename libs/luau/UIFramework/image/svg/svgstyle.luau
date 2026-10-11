--!nonstrict
--[[
	svgstyle.luau - colours and the small CSS subset SVG files use (used by svg.luau)

	parseColor(text, currentColor?) -> { r, g, b, a } (0..1) or nil
	      #rgb #rgba #rrggbb #rrggbbaa, rgb()/rgba() (numbers or %, comma or space syntax, "/ alpha"), hsl()/hsla(),
	      the CSS named colours, "transparent", "currentColor" (-> currentColor argument)
	parseDecls("fill: red; stroke: none") -> { fill = "red", stroke = "none" }
	parseCSS(text, rules)     collects { sel = compiled selector, spec = specificity, decls = {...}, order = n } into `rules`
	                          (selectors: *, tag, .class, #id and compounds of those, with descendant ( ) and child (>) combinators;
	                           rules with pseudo-classes / attribute selectors and all @-rules are skipped)
	matches(node, selector)   does an xml node match a compiled selector
]]

local S = {}

local function trim(s: string): string?
	return (string.match(s, "^%s*(.-)%s*$"))
end
S.trim = trim

--------------------------------------------------------------------------
-- colours
--------------------------------------------------------------------------

local NAMED: { [string]: string } = {}
for name, hex in
	string.gmatch(
		"aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 black 000000 "
			.. "blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 "
			.. "chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff darkblue 00008b "
			.. "darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b "
			.. "darkmagenta 8b008b darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a "
			.. "darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f darkturquoise 00ced1 "
			.. "darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff "
			.. "firebrick b22222 floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff "
			.. "gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f grey 808080 honeydew f0fff0 "
			.. "hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 "
			.. "lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6 lightcoral f08080 lightcyan e0ffff "
			.. "lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 "
			.. "lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 "
			.. "lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 "
			.. "mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 "
			.. "mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585 "
			.. "midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 navajowhite ffdead navy 000080 "
			.. "oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa "
			.. "palegreen 98fb98 paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f "
			.. "pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f "
			.. "royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee "
			.. "sienna a0522d silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa "
			.. "springgreen 00ff7f steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 "
			.. "violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32",
		"(%a+) (%x+)"
	)
do
	NAMED[name] = hex
end

local function clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

local function hue(p: number, q: number, t: number): number
	if t < 0 then
		t += 1
	elseif t > 1 then
		t -= 1
	end
	if t < 1 / 6 then
		return p + (q - p) * 6 * t
	elseif t < 1 / 2 then
		return q
	elseif t < 2 / 3 then
		return p + (q - p) * (2 / 3 - t) * 6
	end
	return p
end

-- component of rgb(): "128" -> 128/255, "50%" -> 0.5
local function rgbComponent(t: string): number?
	local pct = string.match(t, "^([-+]?[%d%.]+)%%$")
	if pct then
		return clamp01(tonumber(pct) :: number / 100)
	end
	local v = tonumber(t)
	if v == nil then
		return nil
	end
	return clamp01(v / 255)
end

local function alphaComponent(t: string?): number?
	if t == nil then
		return 1
	end
	local pct = string.match(t, "^([-+]?[%d%.]+)%%$")
	if pct then
		return clamp01(tonumber(pct) :: number / 100)
	end
	local v = tonumber(t)
	if v == nil then
		return nil
	end
	return clamp01(v)
end

function S.parseColor(text: any, current: { number }?): { number }?
	if type(text) ~= "string" then
		return nil
	end
	local s = string.lower(trim(text) :: string)
	if s == "" then
		return nil
	end
	if string.sub(s, 1, 1) == "#" then
		local hex = string.sub(s, 2)
		if not string.find(hex, "^%x+$") then
			return nil
		end
		local n = #hex
		if n == 3 or n == 4 then
			local function h(i: number): number
				local d = string.sub(hex, i, i)
				return tonumber(d .. d, 16) :: number / 255
			end
			return { h(1), h(2), h(3), if n == 4 then h(4) else 1 }
		elseif n == 6 or n == 8 then
			local function h(i: number): number
				return tonumber(string.sub(hex, i, i + 1), 16) :: number / 255
			end
			return { h(1), h(3), h(5), if n == 8 then h(7) else 1 }
		end
		return nil
	end
	if s == "transparent" then
		return { 0, 0, 0, 0 }
	end
	if s == "currentcolor" then
		return current
	end
	local fn, args = string.match(s, "^(%a+)%(([^%)]*)%)$")
	if fn then
		local tokens = {}
		for t in string.gmatch(args, "[^%s,/]+") do
			tokens[#tokens + 1] = t
		end
		if fn == "rgb" or fn == "rgba" then
			if #tokens < 3 then
				return nil
			end
			local r, g, b = rgbComponent(tokens[1]), rgbComponent(tokens[2]), rgbComponent(tokens[3])
			local a = alphaComponent(tokens[4])
			if r and g and b and a then
				return { r, g, b, a }
			end
			return nil
		elseif fn == "hsl" or fn == "hsla" then
			if #tokens < 3 then
				return nil
			end
			local hv = tonumber((string.gsub(tokens[1], "deg$", "")))
			if hv == nil then
				local turns = string.match(tokens[1], "^([-+]?[%d%.]+)turn$")
				if turns then
					hv = tonumber(turns) :: number * 360
				end
			end
			local sv = tonumber((string.match(tokens[2], "^([-+]?[%d%.]+)%%?$")))
			local lv = tonumber((string.match(tokens[3], "^([-+]?[%d%.]+)%%?$")))
			local a = alphaComponent(tokens[4])
			if hv == nil or sv == nil or lv == nil or a == nil then
				return nil
			end
			sv, lv = clamp01(sv / 100), clamp01(lv / 100)
			local h = (hv % 360) / 360
			local q = if lv < 0.5 then lv * (1 + sv) else lv + sv - lv * sv
			local p = 2 * lv - q
			return { hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3), a }
		end
		return nil
	end
	local hex = NAMED[s]
	if hex then
		return {
			tonumber(string.sub(hex, 1, 2), 16) :: number / 255,
			tonumber(string.sub(hex, 3, 4), 16) :: number / 255,
			tonumber(string.sub(hex, 5, 6), 16) :: number / 255,
			1,
		}
	end
	return nil
end

--------------------------------------------------------------------------
-- CSS
--------------------------------------------------------------------------

function S.parseDecls(body: string): { [string]: string }
	local out = {}
	for name, value in string.gmatch(body, "([%w%-]+)%s*:%s*([^;]+)") do
		value = trim((string.gsub(value, "!%s*important", "")))
		if value ~= "" then
			out[string.lower(name)] = value
		end
	end
	return out
end

-- "svg > g.icon #a" -> { { comp = {...}, comb = nil }, { comp = {...}, comb = ">" }, ... }, specificity
local function compileSelector(text: string): ({ any }?, number)
	if string.find(text, "[:%[%+~]") then
		return nil, 0
	end
	text = (string.gsub(text, "%s*>%s*", " > "))
	local chain = {}
	local spec = 0
	local comb = nil
	for token in string.gmatch(text, "%S+") do
		if token == ">" then
			comb = ">"
		else
			local comp = { classes = {} }
			local rest = token
			if string.sub(rest, 1, 1) == "*" then
				rest = string.sub(rest, 2)
			else
				local tag = string.match(rest, "^([%w_%-]+)")
				if tag then
					comp.tag = tag
					spec += 1
					rest = string.sub(rest, #tag + 1)
				end
			end
			while rest ~= "" do
				local kind, name = string.match(rest, "^([%.#])([%w_%-]+)")
				if not kind then
					return nil, 0
				end
				if kind == "." then
					table.insert(comp.classes, name)
					spec += 100
				else
					comp.id = name
					spec += 10000
				end
				rest = string.sub(rest, #name + 2)
			end
			table.insert(chain, { comp = comp, comb = if #chain > 0 then (comb or " ") else nil })
			comb = nil
		end
	end
	if #chain == 0 then
		return nil, 0
	end
	return chain, spec
end

local function classSet(node): { [string]: boolean }
	local set = node._classes
	if not set then
		set = {}
		local c = node.attrs.class
		if c then
			for name in string.gmatch(c, "%S+") do
				set[name] = true
			end
		end
		node._classes = set
	end
	return set
end

local function matchCompound(node, comp): boolean
	if comp.tag and node.tag ~= comp.tag then
		return false
	end
	if comp.id and node.attrs.id ~= comp.id then
		return false
	end
	if #comp.classes > 0 then
		local set = classSet(node)
		for _, name in comp.classes do
			if not set[name] then
				return false
			end
		end
	end
	return true
end

local function matchChain(node, chain, i: number): boolean
	if not matchCompound(node, chain[i].comp) then
		return false
	end
	if i == 1 then
		return true
	end
	local p = node.parent
	if chain[i].comb == ">" then
		return p ~= nil and p.tag ~= "#document" and matchChain(p, chain, i - 1)
	end
	while p and p.tag ~= "#document" do
		if matchChain(p, chain, i - 1) then
			return true
		end
		p = p.parent
	end
	return false
end

function S.matches(node, selector): boolean
	return matchChain(node, selector, #selector)
end

function S.parseCSS(text: string, rules: { any })
	text = string.gsub(text, "/%*.-%*/", "")
	text = string.gsub(text, "@[%w%-]+[^{;]*;", "") -- @import, @charset
	local pos = 1
	while true do
		local open = string.find(text, "{", pos, true)
		if not open then
			break
		end
		local selText = trim(string.sub(text, pos, open - 1))
		local depth, i = 1, open + 1
		while i <= #text and depth > 0 do
			local ch = string.sub(text, i, i)
			if ch == "{" then
				depth += 1
			elseif ch == "}" then
				depth -= 1
			end
			i += 1
		end
		local body = string.sub(text, open + 1, i - 2)
		pos = i
		if string.sub(selText, 1, 1) ~= "@" then
			local decls = S.parseDecls(body)
			for sel in string.gmatch(selText, "[^,]+") do
				local chain, spec = compileSelector(trim(sel) :: string)
				if chain then
					table.insert(rules, { sel = chain, spec = spec, decls = decls, order = #rules })
				end
			end
		end
	end
end

return S
