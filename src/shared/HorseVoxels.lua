--[[
	Воксельные модели (перенос части js/voxel.js): лошадь по кубикам — корпус, голова, уши,
	ноги, хвост, крылья, упряжь, а также жители. Здесь только «какой кубик какого цвета»;
	собирает из кубиков детали Roblox клиентский HorseBuilder.
	Ключ кубика — "x|y|z", значение — цвет '#rrggbb'. Размер кубика — V стадов.
]]
local Util = require(script.Parent.Util)
local Genetics = require(script.Parent.Genetics)
local Horses = require(script.Parent.Horses)
local Items = require(script.Parent.Items)
local mix = Util.mix

local HV = {}
HV.V = 0.45

local function key3(x, y, z) return x .. "|" .. y .. "|" .. z end
HV.key3 = key3
function HV.parse(k)
	local a, b, c = string.match(k, "^(-?%d+)|(-?%d+)|(-?%d+)$")
	return tonumber(a), tonumber(b), tonumber(c)
end

local WHITE = "#f6f3ec"
local BONE, BONE2 = "#ece6d6", "#cfc6b0"
local FIRE = { "#ff3d00", "#ff6d00", "#ff9100", "#ffc400", "#ffea00" }
local ICE = { "#a5f3fc", "#cffafe", "#67e8f9", "#e0f2fe", "#bae6fd" }
local RAINBOW7 = { "#ff6b6b", "#ff922b", "#ffd43b", "#51cf66", "#4dabf7", "#5c7cfa", "#cc5de8" }
local function at(arr, i) -- индекс с нуля, как в JS
	return arr[(i % #arr) + 1]
end
local function pastel(k)
	return Util.hslHex(((k % 1) + 1) % 1, 0.75, 0.8)
end

-- цвет гривы/хвоста
local function hairColor(h, ph, B, i, mag)
	if h.maneDye then
		local d = Items.DYES[h.maneDye]
		if d then
			if d.color == "rainbow" then return at(Items.RAINBOW, i), false end
			return d.color, false
		end
	end
	local E = ph.elem and Horses.ELEMS[ph.elem]
	if E then
		if ph.elem == "crystal" then
			local t = ph.tint
			return at({ mix(t, "#ffffff", 0.55), t, mix(t, "#ffffff", 0.25) }, i), true
		end
		if E.maneCols then return at(E.maneCols, i * 3), not not E.maneGlow end
	end
	if ph.holiday == "halloween" then return (i % 3 == 0) and "#ff7b00" or "#1b1620", i % 3 == 0 end
	if ph.holiday == "newyear" then return (i % 4 == 0) and "#ffd43b" or (i % 4 == 2) and "#e03131" or "#1f5a2a", i % 2 == 0 end
	if ph.holiday == "newyearglow" then return mix(ph.body, "#ffffff", 0.45 + (i % 3) * 0.15), true end
	if ph.holiday == "easter" then return at({ "#ffc9de", "#fff3bf", "#d3f9d8", "#d0ebff", "#e5dbff" }, i), false end
	if ph.zebra then
		if i % 2 == 1 then return "#f4f1ea", false end
		return ph.zebra == "rainbow" and at(RAINBOW7, i // 2) or ph.zebra, false
	end
	if ph.glow then return (i % 2 == 1) and ph.glow or mix(ph.glow, "#ffffff", 0.4), true end
	if ph.fox then return (i % 3 == 0) and mix(ph.fox, "#ffffff", 0.3) or ph.fox, false end
	if ph.scales then return (i % 2 == 1) and mix(ph.scales, "#000000", 0.4) or mix(ph.scales, "#ffffff", 0.15), (mag.dragonEyes ~= nil) and i % 3 == 0 end
	if ph.coat == "rainbow" then return at(RAINBOW7, i), true end
	if ph.coat == "pearl" then return (i % 2 == 1) and "#fffaf2" or "#efe6d8", i % 4 == 0 end
	if mag.mane == "fire" then return at(FIRE, i * 7), true end
	if mag.mane == "ice" then return at(ICE, i * 5), true end
	if mag.skeleton then return "#9fe6a0", true end
	return B.fjordMane and "#efe4cf" or ph.mane, false
end

-- особые окрасы корпуса
local function specialCol(ph, h, x, y, z, part, rnd)
	if ph.holiday == "halloween" then return rnd() < 0.1 and "#4a3f52" or "#3b3242" end
	if ph.holiday == "newyear" then return at({ "#2f7a3a", "#24622f", "#3d8f47", "#1f5a2a", "#4f9e55" }, x * 7 + y * 3 + z * 5 + 99) end
	if ph.holiday == "newyearglow" then return rnd() < 0.3 and mix(ph.body, "#ffffff", 0.35) or ph.body end
	if ph.holiday == "easter" then
		if part == "barrel" and (y == 9 or y == 11) then return y == 9 and "#ffffff" or "#c5f6fa" end
		if rnd() < 0.12 then return at({ "#ffd43b", "#74c0fc", "#69db7c", "#cc5de8", "#ffffff" }, math.floor(rnd() * 5)) end
		return "#ffb3d1"
	end
	if ph.scales then
		local c = ph.scales
		if y <= 8 and part == "barrel" then return mix(c, "#ffffff", 0.35) end
		if (x + (y % 2) + 40) % 2 == 0 then return mix(c, "#ffffff", 0.18) end
		if (x + y + z + 60) % 3 == 0 then return mix(c, "#000000", 0.22) end
		return c
	end
	if ph.zebra then
		local xx = part == "head" and x * 1.4 or part == "neck" and x + y * 0.6 or x
		local band = math.floor((xx + math.sin(y * 0.7 + z * 0.3) * 1.3 + 40) / 1.5)
		if band % 2 == 1 then return "#f4f1ea" end
		return ph.zebra == "rainbow" and at(RAINBOW7, band // 2) or ph.zebra
	end
	if ph.glow then return rnd() < 0.15 and "#1d1a22" or "#141218" end
	if ph.fox then
		local white = (h.magic and h.magic.fox == "arctic") and "#ffffff" or "#f6f1e7"
		if (part == "barrel" and y <= 8) or (part == "neck" and x >= 9 and y <= 14) or (part == "barrel" and x >= 6 and y <= 10) then return white end
		if rnd() < 0.2 then return mix(ph.fox, "#000000", 0.12) end
		if rnd() < 0.15 then return mix(ph.fox, "#ffffff", 0.15) end
		return ph.fox
	end
	if ph.coat == "rainbow" then return pastel(x * 0.05 + y * 0.04 + z * 0.06) end
	if ph.coat == "pearl" then
		if rnd() < 0.2 then return "#fff8ee" end
		if rnd() < 0.2 then return "#e6dccb" end
		return "#efe6d8"
	end
	return nil
end

-- узор стихийной лошадки
local function elemColor(ph, x, y, z, part, rnd)
	local e = ph.elem
	if e == "ice" then
		if rnd() < 0.18 then return "#e7f5ff" end
		if y >= 12 or part == "head" then return "#a5d8ff" end
		return rnd() < 0.5 and "#74c0fc" or "#4dabf7"
	elseif e == "crystal" then
		local t = ph.tint
		local f = ((x + y * 2 + z * 3) % 3 + 3) % 3
		return f == 0 and mix(t, "#ffffff", 0.45) or f == 1 and t or mix(t, "#000000", 0.18)
	elseif e == "fire" then
		if y >= 12 then return rnd() < 0.5 and "#ffd43b" or "#fcc419" end
		if y >= 10 then return rnd() < 0.5 and "#ff922b" or "#fd7e14" end
		return rnd() < 0.5 and "#f03e3e" or "#e8590c"
	elseif e == "water" then
		local band = math.floor(y + math.sin(x * 0.7 + z) * 1.4)
		local k = ((band % 3) + 3) % 3
		if k == 0 then return "#1c7ed6" end
		if k == 1 then return "#74c0fc" end
		return rnd() < 0.5 and "#f1f8ff" or "#a5d8ff"
	elseif e == "rainbow" then
		return at(RAINBOW7, math.floor((x + 8) / 2.3))
	elseif e == "sun" then
		if y >= 12 then return "#ffe066" end
		if y >= 10 then return rnd() < 0.6 and "#fcc419" or "#ffd43b" end
		return rnd() < 0.5 and "#f59f00" or "#ff922b"
	elseif e == "sand" then
		if rnd() < 0.25 then return "#d4b67a" end
		if rnd() < 0.2 then return "#f4e4bc" end
		return "#e9d3a1"
	elseif e == "stone" then
		if y >= 12 and rnd() < 0.12 then return "#5c940d" end
		local b = math.abs((math.floor(x / 2) * 7 + math.floor(y / 2) * 13 + math.floor(z / 2) * 5) % 4)
		if (x + 64) % 4 == 0 and rnd() < 0.5 then return "#495057" end
		return ({ "#868e96", "#adb5bd", "#6c757d", "#909296" })[b + 1]
	elseif e == "mushroom" then
		if y >= 11 and part == "barrel" then
			return ((x + z + 40) % 3 == 0 and y == 12) and "#ffffff" or "#e03131"
		end
		return rnd() < 0.15 and "#e8d9b5" or "#f1e3c6"
	elseif e == "leaf" then
		local v = (x * 3 + y * 5 + z * 7 + 100) % 6
		if v == 0 then return "#2b8a3e" end
		if v == 1 then return "#8ce99a" end
		if rnd() < 0.06 then return "#fab005" end
		return rnd() < 0.5 and "#40c057" or "#37b24d"
	elseif e == "damp" then
		local sw = math.sin(x * 0.85 + z * 1.4) * math.cos(y * 1.2 - x * 0.35)
		if sw > 0.62 or (part == "head" and y == 16 and x == 11) then return "#f8f9fa" end
		return rnd() < 0.3 and "#3b4a59" or "#4a5a6a"
	end
	return ph.body
end

-- голова и шея — отдельная часть (кивает), уши — тоже
HV.HEAD_PIV = { 8, 12.5 }
HV.EAR_PIV = { 11, 17 }
local function isHeadCell(x, y) return (x >= 8 and y >= 12) or (x >= 7 and y >= 13) end

local function splitHead(src)
	local body, head = {}, {}
	for k, c in pairs(src) do
		local x, y = HV.parse(k)
		if isHeadCell(x, y) then head[k] = c else body[k] = c end
	end
	return body, head
end

-- кубики корпуса, головы и ушей
function HV.horseCells(h, ph, B)
	local rnd = Util.rng(h.seed)
	local mag = h.magic or {}
	local cells, glow, ears, earsGlow = {}, {}, {}, {}
	local function put(x, y, z, c) cells[key3(x, y, z)] = c end
	local function gl(x, y, z, c)
		local k = key3(x, y, z)
		cells[k] = nil
		glow[k] = c
	end
	local neck = { { 7, 11, 14, -2, 1 }, { 8, 12, 15, -1, 0 }, { 9, 13, 16, -1, 0 }, { 10, 14, 16, -1, 0 } }
	local function finish()
		local bc, hc = splitHead(cells)
		local bg, hg = splitHead(glow)
		return { cells = bc, glow = bg, headCells = hc, headGlow = hg, ears = ears, earsGlow = earsGlow }
	end
	if mag.skeleton then
		for x = -8, 7 do put(x, 12, -1, BONE); put(x, 12, 0, BONE) end
		for x = -4, 5, 2 do
			for y = 8, 11 do
				for z = -3, 2 do
					if z == -3 or z == 2 or y == 8 then put(x, y, z, y == 8 and BONE2 or BONE) end
				end
			end
		end
		for x = -8, -6 do for y = 10, 12 do for z = -3, 2 do put(x, y, z, BONE2) end end end
		for x = 5, 7 do for y = 9, 12 do for z = -2, 1 do
			if (x + y) % 2 == 1 then put(x, y, z, BONE) end
		end end end
		for _, n in ipairs(neck) do
			for y = n[2], n[3], 2 do put(n[1], y, -1, BONE); put(n[1], y, 0, BONE) end
		end
		for x = 11, 15 do for y = 14, 16 do for z = -1, 0 do
			if not (x >= 14 and y == 16) then put(x, y, z, BONE) end
		end end end
		put(12, 16, -2, "#111111"); put(12, 16, 1, "#111111")
		glow[key3(12, 16, -3)] = "#7dff8a"; glow[key3(12, 16, 2)] = "#7dff8a"
		ears[key3(11, 17, -1)] = BONE; ears[key3(11, 17, 1)] = BONE
		return finish()
	end
	local blobs = {}
	if ph.tob then
		for _ = 1, 3 + math.floor(rnd() * 2) do
			local bx = -7 + rnd() * 15
			local by = 8 + rnd() * 6
			local bz = -2 + rnd() * 4
			local br = 2.4 + rnd() * 2
			table.insert(blobs, { x = bx, y = by, z = bz, r = br })
		end
	end
	local spot = ph.greyLevel > 0.6 and "#3a3a3a" or mix(ph.body, "#000000", 0.2)
	local fullLeo = h.marks and h.marks.lp == "full"
	local function bodyCol(x, y, z, part, top)
		if ph.elem then return elemColor(ph, x, y, z, part, rnd) end
		local sp = specialCol(ph, h, x, y, z, part, rnd)
		if sp then return sp end
		for _, b in ipairs(blobs) do
			if (x - b.x) ^ 2 + ((y - b.y) * 0.8) ^ 2 + ((z - b.z) * 0.6) ^ 2 < b.r * b.r then return WHITE end
		end
		if ph.leo and fullLeo then return rnd() < 0.28 and spot or WHITE end
		if ph.leo and part == "barrel" and x <= 0 and y >= 9 then return rnd() < 0.2 and spot or WHITE end
		local c = ph.body
		if ph.stripe and top and z >= -1 and z <= 0 then c = ph.stripe end
		if ph.roan and part ~= "head" and rnd() < 0.35 then c = mix(c, "#ffffff", 0.45) end
		if ph.dapple and rnd() < 0.25 then c = mix(c, "#ffffff", 0.35) end
		return c
	end
	-- корпус
	for x = -8, 7 do for y = 7, 12 do for z = -3, 2 do
		local edges = ((x == -8 or x == 7) and 1 or 0) + ((y == 7 or y == 12) and 1 or 0) + ((z == -3 or z == 2) and 1 or 0)
		if edges < 2 then
			put(x, y, z, bodyCol(x, y, z, "barrel", y == 12 or (y == 11 and (z == -3 or z == 2))))
		end
	end end end
	-- шея
	for _, n in ipairs(neck) do
		for y = n[2], n[3] do for z = n[4], n[5] do put(n[1], y, z, bodyCol(n[1], y, z, "neck", false)) end end
	end
	-- голова и морда
	for x = 11, 13 do for y = 14, 16 do for z = -1, 0 do put(x, y, z, bodyCol(x, y, z, "head", false)) end end end
	local muzzle = (ph.pinkSkin or h.marks.face == 3) and "#d9a597" or mix(ph.body, "#000000", 0.35)
	if ph.fox or h.breed == "przewalski" then muzzle = "#efe4cf" end
	if ph.zebra then muzzle = "#2b2420" end
	if ph.holiday == "easter" then muzzle = "#ff8fab" end
	for x = 14, 15 do for y = 14, 15 do for z = -1, 0 do put(x, y, z, muzzle) end end end
	-- отметины на лбу
	if h.marks.face and h.marks.face > 0 and not ph.holiday and not ph.scales and not ph.glow and not ph.zebra then
		local len = h.marks.face == 1 and { 11, 11 } or { 11, 13 }
		for x = len[1], len[2] do for z = -1, 0 do put(x, 16, z, WHITE) end end
		if h.marks.face == 3 then
			for x = 11, 13 do for y = 14, 15 do put(x, y, -1, WHITE); put(x, y, 0, WHITE) end end
		end
	end
	put(12, 16, -2, "#1a1412"); put(12, 16, 1, "#1a1412") -- глаза
	local ear = ph.fox and ph.fox or ph.scales and mix(ph.scales, "#000000", 0.3) or mix(ph.body, "#000000", 0.2)
	ears[key3(11, 17, -1)] = ear; ears[key3(11, 17, 1)] = ear
	if ph.fox then ears[key3(11, 18, -1)] = "#1b1412"; ears[key3(11, 18, 1)] = "#1b1412" end
	if ph.zebra then ears[key3(11, 18, -1)] = "#1b1b1b"; ears[key3(11, 18, 1)] = "#1b1b1b" end
	-- грива: причёска и цвет
	local style = h.maneStyle or "normal"
	if B.przMane and style == "normal" then style = "mohawk" end
	local i = 0
	local function hair(x, y, z)
		local c, g = hairColor(h, ph, B, i, mag)
		i += 1
		if g then glow[key3(x, y, z)] = c else put(x, y, z, c) end
	end
	for _, n in ipairs(neck) do
		local x, y1 = n[1], n[3]
		if not (style == "short" and x == 7) then
			hair(x, y1 + 1, -1)
			if B.fjordMane and not h.maneDye and not mag.mane then put(x, y1 + 1, 0, "#2a211b") else hair(x, y1 + 1, 0) end
			if style == "mohawk" or (mag.mane and style == "normal") then
				hair(x, y1 + 2, -1); hair(x, y1 + 2, 0)
				if style == "mohawk" and not B.przMane then hair(x, y1 + 3, 0) end
			end
			local zz = 1 + (x == 7 and 1 or 0)
			if style == "long" or (B.longMane and style == "normal") then
				for y = y1 - 3, y1 do hair(x, y, zz) end
			end
			if style == "braids" and (x == 7 or x == 9) then
				for y = y1 - 3, y1 do hair(x, y, zz) end
				put(x, y1 - 4, zz, "#ff6fae")
			end
			if style == "bows" and (x == 8 or x == 10) then
				put(x, y1 + 2, -1, "#ff6fae"); put(x, y1 + 2, 0, "#ff6fae"); put(x, y1 + 2, -2, "#ff8fc7"); put(x, y1 + 2, 1, "#ff8fc7")
			end
		end
	end
	hair(11, 17, 0) -- чёлка
	if style == "bows" then put(11, 18, 0, "#ff6fae") end
	-- рог единорога
	if mag.horn then
		glow[key3(12, 17, -1)] = "#fff3bf"; glow[key3(12, 17, 0)] = "#fff3bf"
		glow[key3(12, 18, 0)] = "#ffe066"; glow[key3(13, 19, 0)] = "#ffd43b"; glow[key3(13, 20, 0)] = "#fff9db"
	end
	-- серые драконьи рога
	if mag.dhorns then
		for _, z in ipairs({ -2, 1 }) do
			for _, q in ipairs({ { 12, 17, "#9a9da3" }, { 11, 18, "#8d9096" }, { 10, 19, "#7c7f86" }, { 9, 19, "#6c6f75" }, { 8, 20, "#5c5f66" } }) do
				put(q[1], q[2], z, q[3])
			end
		end
	end
	if mag.dragonEyes then
		for _, z in ipairs({ -2, 1 }) do
			gl(12, 16, z, mag.dragonEyes); gl(13, 16, z, mix(mag.dragonEyes, "#ffffff", 0.4)); put(12, 15, z, "#2b0a1a")
		end
	end
	if ph.scales then
		for _, x in ipairs({ -7, -4, -1, 2, 5 }) do
			put(x, 13, -1, mix(ph.scales, "#000000", 0.4)); put(x, 13, 0, mix(ph.scales, "#000000", 0.4)); put(x, 14, 0, mix(ph.scales, "#ffffff", 0.2))
		end
	end
	-- украшения стихий на спине
	if ph.elem == "crystal" then
		local lt = mix(ph.tint, "#ffffff", 0.5)
		for _, x in ipairs({ -6, -2, 2 }) do
			glow[key3(x, 13, -1)] = lt; glow[key3(x, 14, -1)] = ph.tint; glow[key3(x + 1, 13, 0)] = lt
		end
	elseif ph.elem == "mushroom" then
		for _, q in ipairs({ { -5, -2, "#e03131" }, { -1, 1, "#f08c00" }, { 3, -1, "#e03131" } }) do
			local x, z, c = q[1], q[2], q[3]
			put(x, 13, z, "#f8f4ea")
			for dx = -1, 1 do for dz = -1, 1 do put(x + dx, 14, z + dz, c) end end
			put(x, 15, z, c); put(x + 1, 14, z + 1, "#ffffff")
		end
	elseif ph.elem == "leaf" then
		for _, q in ipairs({ { -6, 0 }, { -3, -2 }, { 0, 1 }, { 4, -1 } }) do
			put(q[1], 13, q[2], "#2f9e44"); put(q[1] + 1, 13, q[2], "#69db7c"); put(q[1], 14, q[2], "#51cf66")
		end
	elseif ph.elem == "sun" then
		for _, q in ipairs({ { 10, 18 }, { 12, 19 }, { 14, 18 } }) do glow[key3(q[1], q[2], -1)] = "#ffe066" end
	elseif ph.elem == "ice" then
		for _, x in ipairs({ -5, -1, 3 }) do glow[key3(x, 13, -1)] = "#e7f5ff" end
	end
	-- череп на голове и рёбра
	if mag.bones then
		for _, z in ipairs({ -3, 2 }) do
			for _, x in ipairs({ -4, -2, 0, 2, 4 }) do
				for y = 8, 11 do put(x, y, z, y == 8 and BONE2 or BONE) end
			end
		end
		for x = -7, 6 do put(x, 12, -1, BONE); put(x, 12, 0, BONE) end
		for _, z in ipairs({ -3, 2 }) do
			for y = 10, 11 do put(-7, y, z, BONE2); put(-6, y, z, BONE) end
		end
		for x = 11, 15 do for y = 14, 16 do for z = -2, 1 do
			if not (x >= 14 and y == 16) and (z == -2 or z == 1 or y == 16 or x == 15) then
				put(x, y, z, (x + y) % 3 ~= 0 and BONE or BONE2)
			end
		end end end
		for _, z in ipairs({ -2, 1 }) do put(12, 15, z, "#0d0d0d"); put(12, 16, z, "#0d0d0d"); put(13, 16, z, "#1a1a1a") end
		put(15, 15, -1, "#0d0d0d"); put(15, 15, 0, "#0d0d0d")
		for x = 13, 15 do
			for _, z in ipairs({ -2, 1 }) do put(x, 14, z, x % 2 == 1 and "#0d0d0d" or "#ffffff") end
		end
		ears[key3(11, 17, -1)] = BONE; ears[key3(11, 17, 1)] = BONE
	end
	-- светящиеся узоры
	if ph.glow then
		local ks = {}
		for k in pairs(cells) do table.insert(ks, k) end
		for _, k in ipairs(ks) do
			local x, y, z = HV.parse(k)
			if y >= 7 then
				local v = math.sin(x * 0.85 + math.sin(y * 0.9 + z * 0.5) * 1.8)
				if math.abs(v) < 0.22 or (y == 16 and x >= 11 and x <= 13) then gl(x, y, z, ph.glow) end
			end
		end
		gl(12, 16, -2, ph.glow); gl(12, 16, 1, ph.glow)
	end
	-- праздничные узоры
	if ph.holiday == "halloween" then
		for _, z in ipairs({ -3, 2 }) do
			for _, c in ipairs({ { -4, 9.5 }, { 3, 10 } }) do
				local cx, cy = c[1], c[2]
				for x = cx - 2, cx + 2 do for y = 8, 12 do
					local d = ((x - cx) / 2.4) ^ 2 + ((y - cy) / 2.1) ^ 2
					if d < 1 then put(x, y, z, d < 0.4 and "#ff922b" or "#f76707") end
				end end
				local ry = math.floor(cy + 0.5)
				gl(cx - 1, ry + 1, z, "#ffd43b"); gl(cx + 1, ry + 1, z, "#ffd43b")
				for x = cx - 1, cx + 1 do gl(x, ry - 1, z, "#ffd43b") end
				put(cx, 12, z, "#2b8a3e")
			end
			for _, b in ipairs({ { -1, 11 }, { 6, 9 } }) do
				for _, d in ipairs({ { 0, 0 }, { -1, 1 }, { 1, 1 }, { -2, 1 }, { 2, 1 }, { -3, 2 }, { 3, 2 } }) do put(b[1] + d[1], b[2] + d[2], z, "#0b0b0b") end
			end
			for y = 8, 10 do put(-7, y, z, "#ffffff"); put(-6, y, z, "#ffffff") end
			put(-7, 11, z, "#ffffff"); put(-6, 11, z, "#ffffff"); put(-7, 10, z, "#111111")
		end
		gl(12, 16, -2, "#ff7b00"); gl(12, 16, 1, "#ff7b00")
		for x = -3, 1 do for z = -3, 2 do
			if ((x + 1) / 2.4) ^ 2 + ((z + 0.5) / 2.6) ^ 2 < 1 then put(x, 12, z, (x + z) % 2 ~= 0 and "#f76707" or "#ff922b") end
		end end
		gl(-2, 12, -1, "#ffd43b"); gl(0, 12, -1, "#ffd43b")
		for x = -2, 0 do gl(x, 12, 1, "#ffd43b") end
		for x = -7, -5 do for z = -1, 0 do put(x, 12, z, "#ffffff") end end
		put(-6, 12, -1, "#111111")
		for _, q in ipairs({ { 4, -2 }, { 5, 1 } }) do
			for _, d in ipairs({ { 0, 0 }, { -1, -1 }, { 1, -1 }, { -2, -1 }, { 2, -1 } }) do put(q[1] + d[1], 12, q[2] + d[2], "#0b0b0b") end
		end
	elseif ph.holiday == "newyear" then
		local toys = { "#e03131", "#ffd43b", "#4dabf7", "#f8f9fa", "#cc5de8", "#ff922b" }
		local ks = {}
		for k in pairs(cells) do table.insert(ks, k) end
		for _, k in ipairs(ks) do
			local x, y, z = HV.parse(k)
			local surf = z == -3 or z == 2 or y == 12 or ((z == -2 or z == 1) and x >= 7)
			if surf then
				if (x * 5 + y * 3 + z * 7 + 300) % 11 == 0 then gl(x, y, z, at(toys, x + y + 30))
				elseif (x + y + 40) % 6 == 0 and y >= 9 then gl(x, y, z, "#ffe066") end
			end
		end
		gl(12, 17, -1, "#ffd43b"); gl(12, 18, -1, "#fff3bf")
	elseif ph.holiday == "newyearglow" then
		for k, c in pairs(cells) do glow[k] = c end
		for k in pairs(glow) do cells[k] = nil end
		for k, c in pairs(ears) do earsGlow[k] = c end
		for k in pairs(earsGlow) do ears[k] = nil end
	elseif ph.holiday == "easter" then
		local eggs = { { "#ffd43b", "#ff8fab" }, { "#74c0fc", "#ffffff" }, { "#69db7c", "#ffd43b" }, { "#cc5de8", "#fff3bf" } }
		local n = 0
		for _, z in ipairs({ -3, 2 }) do
			for _, c in ipairs({ { -5, 9.5 }, { -0.5, 10 }, { 4, 9.5 } }) do
				local cx, cy = c[1], c[2]
				local e = at(eggs, n + (h.seed % 4))
				n += 1
				for x = math.floor(cx - 1), math.ceil(cx + 1) do for y = 8, 12 do
					if ((x - cx) / 1.3) ^ 2 + ((y - cy) / 1.9) ^ 2 < 1 then put(x, y, z, y == math.floor(cy + 0.5) and e[2] or e[1]) end
				end end
			end
		end
		for _, q in ipairs({ { -5, -1, 0 }, { -1, 0, 1 }, { 3, -1, 2 } }) do
			local e = at(eggs, q[3] + (h.seed % 4))
			for x = q[1] - 1, q[1] + 1 do for z = q[2] - 1, q[2] + 1 do put(x, 12, z, x == q[1] and e[2] or e[1]) end end
		end
	end
	-- радужная и жемчужная шерсть переливается
	if ph.coat == "rainbow" or ph.coat == "pearl" then
		local ks = {}
		for k in pairs(cells) do table.insert(ks, k) end
		table.sort(ks)
		for _, k in ipairs(ks) do
			if rnd() < (ph.coat == "rainbow" and 0.28 or 0.12) then
				glow[k] = mix(cells[k], "#ffffff", 0.25)
				cells[k] = nil
			end
		end
	end
	return finish()
end

-- грязь и мокрая шерсть
local MUD = { "#5a3d22", "#6b4a2b", "#4a321c", "#7a5634" }
function HV.mudLevel(h) return math.min(4, math.floor((h.mud or 0) / 22)) end
function HV.wetLevel(h)
	local w = h.wet or 0
	return w > 60 and 2 or w > 22 and 1 or 0
end
function HV.wetten(map, wl)
	if wl == 0 or not map then return end
	for k, c in pairs(map) do map[k] = mix(c, "#0b1a2a", 0.13 * wl) end
end

-- нога i (0..3): передние 0,1, задние 2,3
function HV.legCells(h, ph, i)
	local cells, glow = {}, {}
	local mag = h.magic or {}
	local white = h.marks.legs[i + 1] or ph.tob
	local ml = HV.mudLevel(h)
	local rnd = Util.rng(h.seed + i * 31)
	local function muddy(c, y)
		if ml > 0 and y <= -7 + ml + 1 and (y < -7 + ml + 1 or rnd() < 0.6) then return MUD[math.floor(rnd() * #MUD) + 1] end
		return c
	end
	for y = -7, -1 do for x = -1, 0 do for z = -1, 0 do
		local skip = false
		if mag.skeleton then
			if (x == 0 and z == 0) or y == -4 or y == -7 then
				cells[key3(x, y, z)] = y == -7 and "#8d8476" or y == -4 and BONE2 or BONE
			end
			skip = true
		end
		if not skip then
			local c = y >= -2 and ph.body or ph.legs
			local g = false
			if ph.elem then
				local e = ph.elem
				if e == "rainbow" then c = at(RAINBOW7, i * 2 + (y + 7))
				elseif e == "crystal" or e == "stone" or e == "water" or e == "fire" or e == "leaf" or e == "damp" then c = elemColor(ph, x + i * 3, y + 7, z, "leg", rnd) end
				if e == "leaf" and y <= -3 then c = "#5c3d1e" end
				if y == -7 then c = e == "ice" and "#d0ebff" or e == "sun" and "#f08c00" or e == "crystal" and mix(ph.tint, "#000000", 0.35) or "#2b2420" end
			elseif ph.zebra then
				c = (y + 20) % 2 == 0 and (ph.zebra == "rainbow" and at(RAINBOW7, y + 7 + i) or ph.zebra) or "#f4f1ea"
				if y == -7 then c = "#2b2420" end
			elseif ph.fox then
				c = y <= -4 and (mag.fox == "arctic" and "#e9e4da" or "#2b2420") or ph.fox
				if y == -7 then c = "#1b1412" end
			elseif ph.scales then
				c = (y + x + z + 20) % 2 ~= 0 and mix(ph.scales, "#000000", 0.2) or ph.scales
				if y == -7 then c = "#3a3a3a" end
			elseif ph.glow then
				c = "#141218"
				if y == -3 or (y == -5 and (x + z) % 2 ~= 0) then g = true; c = ph.glow end
				if y == -7 then c = "#0b0a0d" end
			elseif ph.holiday then
				local Hd = ph.holiday
				if Hd == "halloween" then c = y == -3 and "#ff7b00" or "#2b2430"
				elseif Hd == "newyear" then c = y == -4 and "#e03131" or "#24622f"
				elseif Hd == "easter" then c = (y + 20) % 2 ~= 0 and "#ffffff" or "#ffb3d1"
				else c = ph.body end
				if Hd == "newyear" and y == -4 then g = true end
				if y == -7 then c = Hd == "easter" and "#f783ac" or "#2b2420" end
			elseif ph.coat == "rainbow" then
				c = pastel(i * 0.13 + y * 0.05)
				if y == -7 then c = "#cfc4e8" end
			else
				if ph.tob and y < -2 then c = WHITE
				elseif white and y <= -4 then c = WHITE end
				if ph.leo and h.marks.lp == "full" and y >= -3 and rnd() < 0.3 then c = mix(ph.body, "#000000", 0.2) end
				if y == -7 then c = "#2b2420" end
			end
			if y == -7 and h.shoes then c = "#b8bec7" end
			if g then glow[key3(x, y, z)] = muddy(c, y) else cells[key3(x, y, z)] = muddy(c, y) end
		end
	end end end
	return { cells = cells, glow = glow }
end

function HV.tailCells(h, ph, B)
	local cells, glow = {}, {}
	local mag = h.magic or {}
	if mag.fox and not mag.skeleton then
		local fur = ph.fox or "#d9661f"
		local tip = mag.fox == "arctic" and "#ffffff" or "#f6f1e7"
		local path = { { -1, 0 }, { -2, 0 }, { -3, -1 }, { -4, -1 }, { -5, -2 }, { -6, -2 }, { -7, -3 }, { -8, -3 }, { -9, -2 }, { -10, -1 } }
		for k0, p in ipairs(path) do
			local k = k0 - 1
			local rr = (k < 2 or k > 7) and 1 or 2
			for dy = -rr, rr do
				for z = -1 - (rr > 1 and 1 or 0), (rr > 1 and 1 or 0) do
					if math.abs(dy) + math.abs(z + 0.5) <= rr + 0.6 then
						cells[key3(p[1], p[2] + dy, z)] = k >= 8 and tip or ((k + dy + z) % 4 == 0 and mix(fur, "#000000", 0.12) or fur)
					end
				end
			end
		end
		return { cells = cells, glow = glow }
	end
	local pts = { { -1, -1 }, { -1, -2 }, { -2, -2 }, { -2, -3 }, { -2, -4 }, { -3, -4 }, { -3, -5 }, { -3, -6 }, { -3, -7 } }
	for i0, p in ipairs(pts) do
		local i = i0 - 1
		for _, z in ipairs({ -1, 0 }) do
			if mag.skeleton then
				if i % 2 == 0 and z == 0 then cells[key3(p[1], p[2], z)] = BONE end
			else
				local c, g = hairColor(h, ph, B, i * 2 + z + 1, mag)
				if g then glow[key3(p[1], p[2], z)] = c else cells[key3(p[1], p[2], z)] = c end
			end
		end
	end
	if ph.zebra and not h.maneDye then
		for _, z in ipairs({ -1, 0 }) do cells[key3(-3, -7, z)] = "#1b1b1b"; cells[key3(-3, -6, z)] = "#1b1b1b" end
	end
	return { cells = cells, glow = glow }
end

-- крылья: z — наружу от тела, x — вдоль тела
local function pickBy(h, arr, k) return at(arr, h.seed + (k or 0)) end
function HV.wingDef(wtype, h, ph)
	local cells = {}
	local function set(x, z, c) cells[key3(x, 0, z)] = c end
	if wtype == "raven" then
		local base = pickBy(h, { "#8d99ae", "#a68a64", "#6c8ebf", "#9c6ade", "#5fa8a0", "#c97b63", "#d4a373" })
		local light, dark = mix(base, "#ffffff", 0.35), mix(base, "#000000", 0.25)
		for z = 0, 10 do
			local len = 7 - math.floor(z * 0.35) + (z > 6 and 2 or 0)
			for x = -len, 1 do
				if not (z >= 7 and x < -3 and (x + z) % 2 ~= 0) then
					set(x, z, z < 3 and light or (x < -len + 2 and dark or base))
				end
			end
		end
		return { cells = cells, glass = false }
	end
	if wtype == "butterfly" then
		local pal = pickBy(h, { { "#ff8c1a", "#ffd166" }, { "#3a86ff", "#90e0ef" }, { "#ff7eb6", "#ffd6e8" }, { "#ffd60a", "#fff3b0" }, { "#9b5de5", "#f15bb5" } })
		local function inside(x, z)
			return ((x - 2.5) / 4) ^ 2 + ((z - 4.5) / 4.6) ^ 2 < 1 or ((x + 3.5) / 3.2) ^ 2 + ((z - 3) / 3.6) ^ 2 < 1
		end
		for x = -7, 7 do for z = 0, 9 do
			if inside(x, z) then
				local edge = not inside(x + 1, z) or not inside(x - 1, z) or not inside(x, z + 1) or not inside(x, z - 1)
				local c = edge and "#1b1b1b" or ((x + z) % 4 == 0 and mix(pal[1], "#000000", 0.25) or (z > 5 and pal[2] or pal[1]))
				if not edge and ((x == 3 and z == 6) or (x == 1 and z == 7) or (x == -3 and z == 4)) then c = "#ffffff" end
				set(x, z, c)
			end
		end end
		return { cells = cells, glass = false }
	end
	if wtype == "dragon" then
		local sc = h.magic and h.magic.scales
		local mem = sc and mix(sc, "#ffffff", 0.08) or pickBy(h, { "#8b1e3f", "#2d6a4f", "#5a189a", "#b5651d", "#264653" })
		local bone = sc and mix(sc, "#000000", 0.45) or "#3d2b1f"
		for z = 0, 11 do
			local minX = -math.floor(z * 0.75 + 0.5) - 1
			for x = minX, 1 do
				if not (x == minX and z % 3 == 1) then
					local isBone = x == 1 or (z > 2 and (x == math.floor(-z * 0.25 + 0.5) or x == math.floor(-z * 0.5 + 0.5)))
					set(x, z, isBone and bone or mix(mem, "#000000", (z % 3) * 0.06))
				end
			end
		end
		set(2, 11, bone); set(2, 10, bone)
		return { cells = cells, glass = false }
	end
	if wtype == "dragonfly" then
		local tint = pickBy(h, { "#bde0fe", "#caffbf", "#ffd6ff", "#fdffb6" })
		for z = 0, 10 do for x = 0, 2 do
			if not (z == 10 and x ~= 1) then set(x, z, z % 3 == 0 and "#adb5bd" or tint) end
		end end
		for z = 0, 9 do for x = -4, -2 do
			if not (z == 9 and x ~= -3) then set(x, z, z % 3 == 0 and "#adb5bd" or tint) end
		end end
		return { cells = cells, glass = true }
	end
	if wtype == "bee" then
		for x = -3, 2 do for z = 0, 5 do
			if ((x + 0.5) / 3) ^ 2 + ((z - 2.5) / 3) ^ 2 < 1 then set(x, z, z % 2 == 1 and "#e7f5ff" or "#f8f9fa") end
		end end
		return { cells = cells, glass = true }
	end
	-- пегас: перья веером
	local c1, c2 = mix(ph.body, "#ffffff", 0.65), mix(ph.body, "#ffffff", 0.85)
	for z = 0, 7 do
		local len = 6 - math.floor(z * 0.6)
		for x = -len, 1 do set(x, z, (x + z) % 3 ~= 0 and c1 or c2) end
	end
	return { cells = cells, glass = false }
end
HV.FLAP = {
	pegasus = { speed = 9, amp = 0.7, rest = -0.9 }, raven = { speed = 8, amp = 0.75, rest = -0.9 },
	butterfly = { speed = 5, amp = 0.9, rest = -1.2 }, dragon = { speed = 4.5, amp = 0.8, rest = -0.6 },
	dragonfly = { speed = 32, amp = 0.22, rest = -0.05 }, bee = { speed = 42, amp = 0.3, rest = -0.2 },
}

-- облачко под копытом
function HV.cloudCells()
	local cc = {}
	for cx = -2, 1 do for cz = -2, 1 do
		if math.abs(cx + 0.5) + math.abs(cz + 0.5) < 3 then cc[key3(cx, -9, cz)] = (cx + cz) % 2 ~= 0 and "#ffffff" or "#e7f5ff" end
	end end
	cc[key3(-1, -8, -1)] = "#ffffff"; cc[key3(0, -8, 0)] = "#ffffff"; cc[key3(-1, -8, 0)] = "#f1f3f5"
	return cc
end

-- упряжь: седло, вальтрап и уздечка собираются из настоящих деталей в HorseBuilder
-- (HB.addSaddle, HB.addBridle). Здесь — пустые кубики для совместимости.
-- R = { pad, saddleStyle, saddleColor, bridleStyle, bridleColor, boots }
function HV.tackCells(_R)
	return { cells = {}, glow = {} }
end

-- поза для действия лошади (act = { k, t, d, leg })
local function smooth(k)
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end
function HV.actPose(a)
	if not a then return nil end
	local V = HV.V
	local p = math.min(1, a.t / a.d)
	local tt = a.t
	local q = smooth(math.min(p / 0.18, (1 - p) / 0.18, 1))
	local e = math.sin(math.pi * p)
	local P = { k = a.k, px = 0, py = 0, pitch = 0, roll = 0, up = 0, yaw = 0, head = 0, headYaw = nil, ears = 0, legs = nil }
	local k = a.k
	if k == "rear" then
		P.px = -6 * V; P.pitch = 0.72 * q; P.head = 0.25 * q; P.ears = -0.2 * q
		P.legs = { 1.0 * q + math.sin(tt * 9) * 0.35 * q, 0.8 * q + math.sin(tt * 9 + 1.6) * 0.35 * q, -0.25 * q, -0.25 * q }
	elseif k == "kick" then
		P.px = 5 * V; P.pitch = -0.3 * e; P.head = -0.35 * e; P.ears = 1.0 * e
		P.legs = { 0.15 * e, 0.15 * e, -1.35 * e, -1.15 * e }
	elseif k == "graze" then
		P.px = 5 * V; P.pitch = -0.08 * q; P.head = -1.4 * q + math.sin(tt * 5) * 0.04 * q; P.headYaw = math.sin(tt * 0.6) * 0.25 * q
	elseif k == "roll" then
		P.py = 3 * V
		local r, kick = 0, 0
		if p < 0.18 then r = 1.45 * smooth(p / 0.18)
		elseif p > 0.82 then r = 1.45 * smooth((1 - p) / 0.18)
		else
			local w = (p - 0.18) / 0.64
			r = 1.45 + 0.95 * math.max(0, math.sin(w * math.pi * 3))
			kick = 1
		end
		P.roll = r
		local fold = math.min(1, r / 1.45)
		P.legs = { 0.9 * fold + math.sin(tt * 11) * 0.5 * kick, 0.7 * fold + math.sin(tt * 11 + 2) * 0.5 * kick, -0.8 * fold + math.sin(tt * 11 + 1) * 0.5 * kick, -0.6 * fold + math.sin(tt * 11 + 3) * 0.5 * kick }
		P.head = 0.3 * fold
	elseif k == "liftLeg" then
		P.legs = { 0, 0, 0, 0 }
		local leg = a.leg or 0
		P.legs[leg + 1] = (leg >= 2 and -0.9 or 1.15) * q
		P.head = -0.1 * q
	elseif k == "ears" then P.ears = 1.25 * q; P.head = -0.12 * q
	elseif k == "neigh" then P.head = 0.6 * q + math.sin(tt * 9) * 0.025 * q; P.ears = -0.25 * q; P.px = -6 * V; P.pitch = 0.08 * q
	elseif k == "lookUp" then P.head = 0.8 * q
	elseif k == "lookDown" then P.head = -0.8 * q
	elseif k == "bow" then P.px = 5 * V; P.pitch = -0.12 * q; P.head = -1.05 * q; P.legs = { 0.75 * q, -0.1 * q, 0, 0 }
	elseif k == "scratch" then P.head = -0.95 * q; P.headYaw = 0.5 * q; P.legs = { 0, 1.35 * q + math.sin(tt * 16) * 0.3 * q, 0, 0 }
	elseif k == "dance" then
		P.yaw = math.sin(tt * 2.2) * 0.45 * q; P.roll = math.sin(tt * 7) * 0.1 * q; P.up = math.abs(math.sin(tt * 7)) * 0.35 * q
		P.legs = {}
		for i = 0, 3 do P.legs[i + 1] = math.max(0, math.sin(tt * 7 + i * math.pi / 2)) * (i < 2 and 0.9 or -0.6) * q end
		P.head = math.sin(tt * 3.5) * 0.25 * q
	elseif k == "back" then P.head = 0.15 * q; P.ears = 0.4 * q
	elseif k == "play" then
		local s = math.abs(math.sin(tt * 6))
		P.up = s * 0.6 * q; P.yaw = math.sin(tt * 3) * 0.6 * q; P.head = math.sin(tt * 6) * 0.3 * q
		P.legs = { 0.6 * s * q, 0.6 * s * q, -0.4 * s * q, -0.4 * s * q }
	elseif k == "lie" then
		P.py = 3 * V; P.roll = 1.45; P.legs = { 0.9, 0.7, -0.8, -0.6 }; P.head = 0.25 + math.sin(tt * 2) * 0.1
	elseif k == "getup" then
		P.py = 3 * V
		local L = 7 * V
		if p < 0.25 then
			P.roll = 1.45; P.legs = { 0.9, 0.7, -0.8, -0.6 }; P.head = 0.2 + math.sin(tt * 3) * 0.15
		elseif p < 0.45 then
			local kk = smooth((p - 0.25) / 0.2)
			P.roll = 1.45 * (1 - kk); P.up = -L * 0.8 * kk; P.legs = { 0.9 + 0.7 * kk, 0.7 + 0.9 * kk, -0.8 - 0.8 * kk, -0.6 - 1 * kk }; P.head = 0.2 + 0.2 * kk
		elseif p < 0.7 then
			local kk = smooth((p - 0.45) / 0.25)
			local w = math.sin(tt * 18) * 0.05 * (1 - kk)
			P.px = -6 * V; P.pitch = 0.32 * kk + w; P.up = -L * 0.8 * (1 - kk * 0.5); P.legs = { 1.6 * (1 - kk), 1.6 * (1 - kk), -1.6, -1.6 }; P.head = 0.4 - 0.2 * kk
		else
			local kk = smooth((p - 0.7) / 0.3)
			local w = math.sin(tt * 14) * 0.06 * (1 - kk)
			P.px = -6 * V; P.pitch = 0.32 * (1 - kk) + w; P.up = -L * 0.4 * (1 - kk); P.legs = { 0, 0, -1.6 * (1 - kk), -1.6 * (1 - kk) }; P.head = 0.2 * (1 - kk); P.roll = w
		end
	end
	return P
end

return HV
