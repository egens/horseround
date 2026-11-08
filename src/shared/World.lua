--[[
	Карта мира (перенос js/world.js): где что стоит и что непроходимо.
	Все координаты — в «пикселях карты», как в JS-версии. В Roblox: 1 пиксель = 0.1 стада
	(World.K), ось X карты = X Roblox, ось Y карты = Z Roblox.
	Город в середине, биомы — вокруг. Границы биомов, острова и озёра неровные (шум и гармоники).
]]
local Util = require(script.Parent.Util)
local rng, hypot = Util.rng, Util.hypot

local World = {}
local K = 0.1
World.K = K
World.SKY_Y = 160 -- высота небесных островов в стадах

local OX, OY = 3200, 3200
local W, H = 17600, 12800
World.OX, World.OY, World.W, World.H = OX, OY, W, H
local function sh(o)
	o.x += OX
	o.y += OY
	return o
end
local function shp(p) return { p[1] + OX, p[2] + OY } end

--[[ ---------- шум и неровные формы ---------- ]]
-- плавный шум от 0 до 1 на встроенном math.noise (третья координата — «зерно»)
local function vnoise(x, y, s)
	return math.clamp(math.noise(x, y, s * 7.31 + 0.5) + 0.5, 0, 1)
end
World.vnoise = vnoise
local function warp(x, y)
	return x + (vnoise(x / 1500, y / 1500, 1) - 0.5) * 820 + (vnoise(x / 480, y / 480, 3) - 0.5) * 260,
		y + (vnoise(x / 1500, y / 1500, 2) - 0.5) * 820 + (vnoise(x / 480, y / 480, 4) - 0.5) * 260
end
World.warp = warp
local function harmonics(seed, amp)
	amp = amp or 1
	local r = rng(seed * 7919 + 13)
	local out = {}
	for _, ka in ipairs({ { 2, 0.1 }, { 3, 0.08 }, { 4, 0.05 }, { 5, 0.04 }, { 7, 0.025 }, { 9, 0.015 } }) do
		local a = ka[2] * amp * (0.6 + r() * 0.8)
		table.insert(out, { k = ka[1], a = a, p = r() * math.pi * 2 })
	end
	return out
end
local function shapeR(B, a)
	local s = 1
	for _, q in ipairs(B.H) do s += q.a * math.sin(q.k * a + q.p) end
	return math.max(B.minR or 0.82, s)
end
World.shapeR = shapeR
local function blobInfo(B, x, y)
	local nx, ny = (x - B.x) / B.rx, (y - B.y) / B.ry
	local d, a = hypot(nx, ny), math.atan2(ny, nx)
	local unit = hypot(B.rx * math.cos(a), B.ry * math.sin(a))
	if unit == 0 then unit = 1 end
	return { d = d, a = a, R = shapeR(B, a), unit = unit, nx = nx, ny = ny }
end
World.blobInfo = blobInfo
local function inBlob(B, x, y, m)
	local q = blobInfo(B, x, y)
	return q.d < q.R + (m or 0) / q.unit
end
World.inBlob = inBlob
local function blobPoint(B, a, off)
	off = off or 0
	local R = shapeR(B, a)
	local ux, uy = math.cos(a), math.sin(a)
	local unit = hypot(B.rx * ux, B.ry * uy)
	if unit == 0 then unit = 1 end
	local k = R + off / unit
	return { x = B.x + B.rx * ux * k, y = B.y + B.ry * uy * k }
end
World.blobPoint = blobPoint
function World.blobPoly(B, off, n)
	n = n or 72
	local pts = {}
	for i = 0, n - 1 do table.insert(pts, blobPoint(B, i / n * math.pi * 2, off)) end
	return pts
end
local function blobPush(B, e, r, inside)
	local q = blobInfo(B, e.x, e.y)
	if q.d < 1e-6 then
		if not inside then e.x = B.x + B.rx * (q.R + r / B.rx) * 1.001 end
		return
	end
	local lim = inside and (q.R - r / q.unit) or (q.R + r / q.unit)
	if inside then
		if q.d <= lim then return end
	else
		if q.d >= lim then return end
	end
	local k = lim / q.d * (inside and 0.999 or 1.001)
	e.x = B.x + (e.x - B.x) * k
	e.y = B.y + (e.y - B.y) * k
end
World.blobPush = blobPush

local function inRect(x, y, r, m)
	m = m or 0
	return x >= r.x - m and x <= r.x + r.w + m and y >= r.y - m and y <= r.y + r.h + m
end
World.inRect = inRect

--[[ ---------- ферма ---------- ]]
-- Конюшня: 2 ряда по 10 денников, проход посередине, ворота слева и справа
local STALL_W, STALL_H, AISLE = 72, 120, 80
World.STALL_W, World.STALL_H = STALL_W, STALL_H
local STABLE = sh({ x = 120, y = 140, w = 740, h = 10 + STALL_H + AISLE + STALL_H + 10 })
World.STABLE = STABLE
World.AISLE_Y1 = STABLE.y + 10 + STALL_H
World.AISLE_Y2 = World.AISLE_Y1 + AISLE
-- i от 0 до 19 (как в JS)
function World.stallRect(i)
	local row = i < 10 and 0 or 1
	local col = i % 10
	return { x = STABLE.x + 10 + col * STALL_W, y = row == 1 and World.AISLE_Y2 or STABLE.y + 10, w = STALL_W, h = STALL_H, row = row }
end
function World.stallSpot(i)
	local r = World.stallRect(i)
	return { x = r.x + r.w / 2, y = r.y + r.h / 2 + (r.row == 1 and 2 or -2), angle = r.row == 1 and -math.pi / 2 or math.pi / 2 }
end

-- Манеж 20×40 с буквами для выездки
local ARENA = sh({ x = 140, y = 640, w = 820, h = 410 })
World.ARENA = ARENA
local A_CX, A_CY = ARENA.x + ARENA.w / 2, ARENA.y + ARENA.h / 2
World.GATE_A = { y1 = A_CY - 55, y2 = A_CY + 55 }
World.LETTERS = {
	A = { x = ARENA.x, y = A_CY, side = "left" },
	C = { x = ARENA.x + ARENA.w, y = A_CY, side = "right" },
	K = { x = ARENA.x + ARENA.w * 0.15, y = ARENA.y, side = "top" },
	E = { x = A_CX, y = ARENA.y, side = "top" },
	H = { x = ARENA.x + ARENA.w * 0.85, y = ARENA.y, side = "top" },
	F = { x = ARENA.x + ARENA.w * 0.15, y = ARENA.y + ARENA.h, side = "bottom" },
	B = { x = A_CX, y = ARENA.y + ARENA.h, side = "bottom" },
	M = { x = ARENA.x + ARENA.w * 0.85, y = ARENA.y + ARENA.h, side = "bottom" },
	X = { x = A_CX, y = A_CY, side = "center" },
}
function World.letterTarget(L)
	local p, inset = World.LETTERS[L], 34
	if p.side == "left" then return { x = p.x + inset, y = p.y } end
	if p.side == "right" then return { x = p.x - inset, y = p.y } end
	if p.side == "top" then return { x = p.x, y = p.y + inset } end
	if p.side == "bottom" then return { x = p.x, y = p.y - inset } end
	return { x = p.x, y = p.y }
end

-- Кавалетти: жерди поперёк дорожки, ехать слева направо
World.CAV = { y1 = ARENA.y + ARENA.h - 150, y2 = ARENA.y + ARENA.h - 70, poles = {} }
for i = 0, 4 do table.insert(World.CAV.poles, ARENA.x + 300 + i * 92) end

-- Левада
local PADDOCK = sh({ x = 1000, y = 110, w = 540, h = 420 })
World.PADDOCK = PADDOCK
World.PADDOCK_GATE = { x1 = PADDOCK.x + 210, x2 = PADDOCK.x + 320 }

-- Повозки
World.SELL = sh({ x = 1190, y = 700, w = 130, h = 66, name = "Продажа лошадей" })
World.SHOP = sh({ x = 1190, y = 900, w = 130, h = 66, name = "Корм и амуниция" })

-- Конкурное поле: 8 препятствий
local JUMPF = sh({ x = 140, y = 1170, w = 1360, h = 620 })
World.JUMPF = JUMPF
World.JUMPF_GATE = { x1 = JUMPF.x + 70, x2 = JUMPF.x + 190 }
World.COURSE = {}
for i, o in ipairs({
	{ fx = 0.17, fy = 0.80, a = 0, type = "cross", name = "крестовина" },
	{ fx = 0.40, fy = 0.80, a = 0, type = "vertical", name = "вертикаль" },
	{ fx = 0.64, fy = 0.80, a = 0, type = "oxer", name = "оксер" },
	{ fx = 0.90, fy = 0.50, a = -math.pi / 2, type = "wall", name = "стенка" },
	{ fx = 0.66, fy = 0.20, a = math.pi, type = "vertical", name = "вертикаль" },
	{ fx = 0.42, fy = 0.20, a = math.pi, type = "oxer", name = "оксер" },
	{ fx = 0.40, fy = 0.52, a = 0, type = "vertical", name = "вертикаль" },
	{ fx = 0.66, fy = 0.52, a = 0, type = "triple", name = "тройник" },
}) do
	o.n = i
	o.x = JUMPF.x + o.fx * JUMPF.w
	o.y = JUMPF.y + o.fy * JUMPF.h
	o.half = 46
	World.COURSE[i] = o
end

-- Фонари
World.LAMPS = {}
for _, p in ipairs({ { 100, 250 }, { 900, 250 }, { 900, 400 }, { 130, 625 }, { 975, 625 }, { 130, 1065 }, { 975, 1065 },
	{ 1180, 560 }, { 1360, 560 }, { 1350, 690 }, { 1350, 890 }, { 120, 1150 }, { 1520, 1150 }, { 120, 1810 }, { 1520, 1810 } }) do
	table.insert(World.LAMPS, sh({ x = p[1], y = p[2] }))
end

-- Большое поле с табуном
World.FIELD = sh({ x = 1760, y = 100, w = 1940, h = 2200 })
World.START = sh({ x = 1840, y = 560 })

--[[ ---------- город и биомы вокруг ---------- ]]
World.LAKELAND = sh({ x = 3800, y = 100, w = 2400, h = 2500 })
World.FARMLAND = sh({ x = 150, y = 2500, w = 1600, h = 900 })
World.VILLAGE = sh({ x = 1900, y = 2500, w = 1700, h = 900 })
World.FOREST = { sh({ x = 0, y = 3500, w = 6200, h = 2900 }), sh({ x = 3800, y = 2650, w = 2400, h = 850 }) }
World.MUSHROOM = sh({ x = 6300, y = 2900, w = 3300, h = 3500 })
World.MOUNTAIN = sh({ x = 6300, y = 0, w = 3300, h = 2800 })
World.CAVE = sh({ x = 6600, y = 350, w = 2700, h = 2100 })
World.CAVE_GATE = { y1 = 1300 + OY, y2 = 1500 + OY }
World.CHEST = sh({ x = 9050, y = 650 })
World.CAVE_INNER_WALLS = {
	sh({ x = 7350, y = 350, w = 120, h = 1350 }),
	sh({ x = 8250, y = 1150, w = 120, h = 1300 }),
	sh({ x = 7350, y = 2050, w = 500, h = 110 }),
}
local MOUNTAIN, CAVE, CAVE_GATE = World.MOUNTAIN, World.CAVE, World.CAVE_GATE

World.DESERT = { x = 0, y = 6500 + OY, w = 4300 + OX, h = 3100 }
World.DEEPFOREST = sh({ x = 4300, y = 6500, w = 2300, h = 3100 })
World.TUNDRA = sh({ x = 6600, y = 6500, w = 3000, h = 3100 })

World.GROTTO = { x = 0, y = 0, w = 4400, h = 3400 }
World.FOXWOOD = { x = 4400, y = 0, w = 5000, h = 3200 }
World.DRAGONROCK = { x = 9400, y = 0, w = 3500, h = 3200 }
World.STEPPE = { x = 0, y = 3400, w = 3200, h = 6300 }

local TOWN = { x = 1875 + OX, y = 1725 + OY, rx = 2300, ry = 2130, H = harmonics(5, 0.7), minR = 0.97 }
World.TOWN = TOWN
local function inTown(x, y)
	if not inRect(x, y, { x = OX - 400, y = OY - 400, w = 3750 + 800, h = 3450 + 800 }) then return false end
	local nx, ny = (x - TOWN.x) / TOWN.rx, (y - TOWN.y) / TOWN.ry
	local d = (math.abs(nx) ^ 6 + math.abs(ny) ^ 6) ^ (1 / 6)
	return d < shapeR(TOWN, math.atan2(ny, nx))
end
World.inTown = inTown

-- восток: море с неровным берегом и острова
local SEA = { x = 9700 + OX, y = 0, w = W - 9700 - OX, h = H }
World.SEA = SEA
local function coastX(y)
	return SEA.x + vnoise(y / 1100, 0.5, 7) * 330 + vnoise(y / 330, 0.5, 8) * 110
end
World.coastX = coastX
World.ISLANDS = {
	sh({ id = "i1", name = "Остров бабочек", x = 11300, y = 2000, rx = 950, ry = 760, breeds = { "butterflyhorse", "beehorse", "dragonflyhorse", "haflinger", "arab" } }),
	sh({ id = "i2", name = "Драконий остров", x = 12900, y = 4900, rx = 920, ry = 800, breeds = { "dragonhorse", "scalehorse", "scalehorse", "ravenhorse", "friesian" } }),
	sh({ id = "i3", name = "Остров ветров", x = 11300, y = 7700, rx = 1000, ry = 760, breeds = { "ravenhorse", "dragonflyhorse", "pegasus", "paint", "appaloosa" } }),
	sh({ id = "i4", name = "Костяной остров", x = 12650, y = -1150, rx = 980, ry = 800, bone = true, breeds = { "bonehorse", "bonehorse", "bonehorse", "bonehorse", "skeleton" } }),
}
for k, I in ipairs(World.ISLANDS) do
	I.H = harmonics(31 + (k - 1) * 11, 1.1)
	I.minR = 0.95
	I.stable = { x = I.x - 480, y = I.y - 430, w = 340, h = 150 }
	I.pasture = { x = I.x + 60, y = I.y - 460, w = 400, h = 300 }
	I.gate = { x1 = I.pasture.x + 150, x2 = I.pasture.x + 250 }
	I.pen = { x = I.x - 260, y = I.y + 260, r = 170 }
	I.pier = { x = blobPoint(I, math.pi).x + 70, y = I.y }
	I.area = { x = I.x - I.rx + 150, y = I.y - I.ry + 150, w = I.rx * 2 - 300, h = I.ry * 2 - 300 }
end
World.PIER = { x = coastX(4700 + OY) - 140, y = 4700 + OY, name = "Пристань" }

-- Рынок в деревне
World.MARKET = sh({ x = 2860, y = 3020, w = 640, h = 360 })
World.MARKET_STALLS = {}
for i, st in ipairs({
	{ id = "horses", name = "🐎 Конский торговец", roof = "#d63a3a" },
	{ id = "trainer", name = "💪 Тренер", roof = "#2e86de" },
	{ id = "swap", name = "🔁 Обменщик", roof = "#8e44ad" },
	{ id = "mine", name = "🏷️ Моя стойка", roof = "#f39c12" },
}) do
	st.x = World.MARKET.x + 30 + (i - 1) * 155
	st.y = World.MARKET.y + 40
	st.w, st.h = 120, 36
	World.MARKET_STALLS[i] = st
end
function World.stallFront(st)
	return { x = st.x + st.w / 2, y = st.y + st.h + 55 }
end

-- Портал в глубине пещеры — на небесные острова
World.PORTAL = sh({ x = 8900, y = 2050, r = 55 })

--[[ ---------- небесные острова ---------- ]]
World.SKY = sh({ x = 600, y = 10000, w = 8600, h = 2500 })
World.TOTAL_H = World.SKY.y + World.SKY.h + 200
World.SKY_ISLANDS = {
	sh({ id = "sky1", name = "Облачный остров", x = 4800, y = 11150, rx = 1100, ry = 640 }),
	sh({ id = "sky2", name = "Радужный остров", x = 2150, y = 10850, rx = 720, ry = 480 }),
	sh({ id = "sky3", name = "Солнечный остров", x = 7450, y = 10850, rx = 720, ry = 480 }),
	sh({ id = "sky4", name = "Лиановый островок", x = 3300, y = 12050, rx = 430, ry = 300 }),
	sh({ id = "sky5", name = "Звёздный островок", x = 6350, y = 12080, rx = 430, ry = 300 }),
}
for k, I in ipairs(World.SKY_ISLANDS) do
	I.H = harmonics(101 + (k - 1) * 17, 1)
	I.minR = 0.93
	I.area = { x = I.x - I.rx + 140, y = I.y - I.ry + 120, w = I.rx * 2 - 280, h = I.ry * 2 - 240 }
end
local BRIDGE_W = 42
World.BRIDGE_W = BRIDGE_W
World.SKY_BRIDGES = {}
for _, b in ipairs({ { 3720, 11000, 2850, 10900 }, { 5880, 11000, 6750, 10900 }, { 4150, 11650, 3550, 11850 }, { 5450, 11650, 6100, 11880 } }) do
	table.insert(World.SKY_BRIDGES, { b[1] + OX, b[2] + OY, b[3] + OX, b[4] + OY })
end
World.SKY_PORTAL = sh({ x = 4800, y = 10900, r = 55 })
local function skyIslandAt(x, y, m)
	for _, I in ipairs(World.SKY_ISLANDS) do
		if inBlob(I, x, y, -(m or 0)) then return I end
	end
	return nil
end
World.skyIslandAt = skyIslandAt
local function segPoint(x, y, b)
	local ax, ay, bx, by = b[1], b[2], b[3], b[4]
	local dx, dy = bx - ax, by - ay
	local L2 = dx * dx + dy * dy
	local t = math.clamp(((x - ax) * dx + (y - ay) * dy) / L2, 0, 1)
	return { x = ax + dx * t, y = ay + dy * t }
end
World.segPoint = segPoint
local function onBridge(x, y, m)
	m = m or 0
	for _, b in ipairs(World.SKY_BRIDGES) do
		local q = segPoint(x, y, b)
		if hypot(q.x - x, q.y - y) < BRIDGE_W - m then return true end
	end
	return false
end
World.onBridge = onBridge
function World.inSkyZone(y) return y > H end
local function skyWalkable(x, y, m)
	return skyIslandAt(x, y, m) ~= nil or onBridge(x, y, m)
end
World.skyWalkable = skyWalkable
local function islandAt(x, y, m)
	if x < SEA.x - 200 then return nil end
	for _, I in ipairs(World.ISLANDS) do
		if inBlob(I, x, y, -(m or 0)) then return I end
	end
	return nil
end
World.islandAt = islandAt
function World.inSea(x, y, m)
	m = m or 0
	return x > coastX(y) - m and not islandAt(x, y, m)
end

-- озёра
World.LAKES = {}
for _, L in ipairs({
	{ x = 2780, y = 1650, rx = 210, ry = 130, name = "Пруд" },
	{ x = 4950, y = 1150, rx = 620, ry = 360, name = "Большое озеро" },
	{ x = 4300, y = 2150, rx = 250, ry = 160 },
	{ x = 2900, y = 4900, rx = 360, ry = 230, name = "Лесное озеро" },
	{ x = 8000, y = 5200, rx = 260, ry = 180, magic = true, name = "Волшебный пруд" },
	{ x = 2100, y = 8000, rx = 260, ry = 170, name = "Оазис" },
	{ x = 8100, y = 8300, rx = 380, ry = 230, ice = true, name = "Ледяное озеро" },
}) do
	table.insert(World.LAKES, sh(L))
end
for _, L in ipairs({
	{ x = 1400, y = 5600, rx = 340, ry = 210, name = "Степное озеро" },
	{ x = 6900, y = 1500, rx = 300, ry = 200, name = "Лисье озеро" },
	{ x = 10500, y = 1700, rx = 260, ry = 170, lava = true, name = "Лавовое озеро" },
	{ x = 11800, y = 800, rx = 190, ry = 130, lava = true, name = "Лавовое озеро" },
}) do
	table.insert(World.LAKES, L)
end
for k, L in ipairs(World.LAKES) do
	L.H = harmonics(200 + (k - 1) * 7, 1.3)
	L.minR = 0.8
end
World.POND = World.LAKES[1]
World.OASIS = World.LAKES[6]

-- маленькие пещерки
World.GROTTOS = {}
for i, g in ipairs({
	{ x = 900, y = 950, r = 270, door = 0.4 }, { x = 2350, y = 650, r = 240, door = 1.9 }, { x = 3650, y = 1250, r = 260, door = 2.6 },
	{ x = 1150, y = 2450, r = 250, door = -0.8 }, { x = 2750, y = 2350, r = 280, door = -1.6 },
}) do
	g.id = "grotto" .. (i - 1)
	g.name = "Пещерка"
	World.GROTTOS[i] = g
end
local function inGrotto(x, y, m)
	m = m or 0
	for _, g in ipairs(World.GROTTOS) do
		if hypot(x - g.x, y - g.y) < g.r - m then return g end
	end
	return nil
end
World.inGrotto = inGrotto

-- железная дорога и станция
World.RAIL = { y = 10450, x1 = 120, x2 = 7380 }
World.STATION = { x = 3900, y = World.RAIL.y - 150, w = 520, h = 90 }
local RAIL, STATION = World.RAIL, World.STATION

-- дороги (ломаные)
World.ROADS = {}
for _, r in ipairs({
	{ { 860, 310 }, { 940, 310 }, { 940, 600 }, { 1275, 600 }, { 1275, 540 } },
	{ { 1275, 600 }, { 1650, 600 }, { 1800, 560 } },
	{ { 120, 310 }, { 70, 310 }, { 70, 850 }, { 140, 850 } },
	{ { 70, 850 }, { 70, 1120 }, { 270, 1120 }, { 270, 1180 } },
	{ { 1110, 600 }, { 1110, 1000 } },
	{ { 960, 850 }, { 1110, 850 } },
	{ { 1110, 1000 }, { 1600, 1100 }, { 1700, 2200 }, { 1800, 2600 }, { 2400, 2850 }, { 3400, 2900 } },
	{ { 800, 1900 }, { 900, 2450 }, { 1500, 2700 }, { 1800, 2600 } },
	{ { 3700, 1500 }, { 4300, 1750 }, { 5600, 1720 }, { 6000, 1420 }, { 6650, 1400 } },
	{ { 2600, 2900 }, { 2600, 3700 }, { 3500, 4200 }, { 4800, 4300 }, { 6000, 4100 }, { 6700, 3900 }, { 7600, 4100 }, { 8300, 4600 } },
	{ { 1600, 3500 }, { 1700, 3300 }, { 1800, 2600 } },
	{ { 2600, 3700 }, { 2300, 5000 }, { 2100, 6400 }, { 2100, 7700 } },
	{ { 4800, 4300 }, { 5300, 6000 }, { 5400, 7600 } },
	{ { 6000, 4100 }, { 7000, 6200 }, { 7700, 7200 }, { 7900, 8000 } },
	{ { 8300, 4600 }, { 9000, 4700 }, { 9560, 4700 } },
}) do
	table.insert(World.ROADS, Util.map(r, shp))
end
for _, r in ipairs({
	{ { OX + 70, OY + 310 }, { 2900, 2900 }, { 2400, 2300 } },
	{ { OX + 1000, OY + 110 }, { 5600, 2400 }, { 6400, 1400 }, { 7400, 900 } },
	{ { OX + 3700, OY + 1500 }, { 9000, 3000 }, { 10200, 2600 }, { 11200, 2200 } },
	{ { OX + 150, OY + 2950 }, { 2400, 5200 }, { 1700, 6600 }, { 1300, 8600 } },
	{ { OX + 2100, OY + 7700 }, { 5300, RAIL.y - 60 }, { STATION.x + STATION.w / 2, RAIL.y - 100 } },
}) do
	table.insert(World.ROADS, r)
end
World.ROADS[15][3] = { World.PIER.x + 60, World.PIER.y }

-- дома деревни и лесная сторожка
World.HOUSES = {}
for _, hh in ipairs({
	{ x = 2150, y = 2640, w = 200, h = 150, name = "Кузница", roof = "#5f5f5f", wall = "#9a8f80" },
	{ x = 2750, y = 2620, w = 200, h = 150, name = "Салон «Грива»", roof = "#c2255c", wall = "#f8e1ea" },
	{ x = 3150, y = 2700, w = 180, h = 140, roof = "#8c3b2a", wall = "#e9d8b5" },
	{ x = 2420, y = 3080, w = 180, h = 140, roof = "#2f6f8f", wall = "#efe4cf" },
	{ x = 1430, y = 2560, w = 180, h = 140, name = "Дом бабушки Гали", roof = "#a33a2a", wall = "#f1e3c6" },
	{ x = 1480, y = 3380, w = 180, h = 130, name = "Сторожка лесника", roof = "#3b5e2b", wall = "#8a5a32" },
}) do
	table.insert(World.HOUSES, sh(hh))
end
World.WELL = sh({ x = 2620, y = 2880, r = 26 })
World.BOARD = sh({ x = 2720, y = 2980 })
World.SQUARE = sh({ x = 2650, y = 2920, rx = 330, ry = 190 })
local HOUSES, WELL = World.HOUSES, World.WELL

function World.rng(seed) return rng(seed) end

local function lakeAt(x, y, m)
	m = m or 0
	for _, L in ipairs(World.LAKES) do
		if math.abs(x - L.x) <= L.rx * 1.4 + m and math.abs(y - L.y) <= L.ry * 1.4 + m then
			if inBlob(L, x, y, m) then return L end
		end
	end
	return nil
end
World.lakeAt = lakeAt
local function inPond(x, y, m) return lakeAt(x, y, m) ~= nil end
World.inPond = inPond

local function distToRoad(x, y)
	local best = 1e9
	for _, r in ipairs(World.ROADS) do
		for i = 1, #r - 1 do
			local ax, ay, bx, by = r[i][1], r[i][2], r[i + 1][1], r[i + 1][2]
			local dx, dy = bx - ax, by - ay
			local L2 = dx * dx + dy * dy
			if L2 == 0 then L2 = 1 end
			local t = math.clamp(((x - ax) * dx + (y - ay) * dy) / L2, 0, 1)
			best = math.min(best, hypot(ax + dx * t - x, ay + dy * t - y))
		end
	end
	return best
end
World.distToRoad = distToRoad

local OUTER = {
	{ "desert", World.DESERT }, { "deepforest", World.DEEPFOREST }, { "tundra", World.TUNDRA }, { "mushroom", World.MUSHROOM },
	{ "forest", World.FOREST[1] }, { "forest", World.FOREST[2] }, { "lake", World.LAKELAND }, { "mountain", MOUNTAIN },
	{ "grotto", World.GROTTO }, { "foxwood", World.FOXWOOD }, { "dragonrock", World.DRAGONROCK }, { "steppe", World.STEPPE },
}
local function biomeAt(x, y)
	local wx, wy = warp(x, y)
	for _, o in ipairs(OUTER) do
		if inRect(wx, wy, o[2]) then return o[1] end
	end
	return "farm"
end
World.biomeAt = biomeAt
local function regionAt(x, y)
	if y > H then
		local SI = skyIslandAt(x, y)
		return SI and SI.id or "sky"
	end
	if inRect(x, y, World.MARKET) then return "market" end
	if x > SEA.x - 300 then
		local I = islandAt(x, y)
		if I then return I.id end
		if x > coastX(y) then return "sea" end
	end
	if inRect(x, y, CAVE) then return "cave" end
	if inRect(x, y, MOUNTAIN) then return "mountain" end
	if inTown(x, y) then
		if inRect(x, y, World.VILLAGE) then return "village" end
		if inRect(x, y, World.FARMLAND) then return "farmland" end
		if inRect(x, y, World.FIELD) then return "field" end
		return "farm"
	end
	if x < World.GROTTO.x + World.GROTTO.w + 400 and y < World.GROTTO.y + World.GROTTO.h + 400 and inGrotto(x, y) then return "grottocave" end
	return biomeAt(x, y)
end
World.regionAt = regionAt
function World.inForest(x, y) return regionAt(x, y) == "forest" end

World.REGION_NAMES = {
	farm = "Ферма", field = "Большое поле", lake = "Озёрный край", forest = "Лес", village = "Деревня",
	farmland = "Поля и огороды", mushroom = "Грибное королевство", mountain = "Горы", cave = "Пещера",
	desert = "Пустыня", deepforest = "Дремучий лес", tundra = "Тундра", sea = "Море",
	grotto = "Пещерные холмы", grottocave = "Пещерка", foxwood = "Лисий лес", dragonrock = "Драконьи скалы", steppe = "Степь",
	market = "Рынок", sky = "Небо",
}
for _, I in ipairs(World.ISLANDS) do World.REGION_NAMES[I.id] = I.name end
for _, I in ipairs(World.SKY_ISLANDS) do World.REGION_NAMES[I.id] = I.name end

--[[ ---------- деревья, грибы, камни, цветы, кости (детерминированно) ---------- ]]
-- kind: oak, birch, pine, spruce, amanita, boletus, glowshroom, cliff, rock, palm, cactus, mesa, drybush…
-- soft = true — сквозь это можно пройти
World.TREES, World.FLOWERS, World.SHROOMS, World.CRYSTALS, World.VINES = {}, {}, {}, {}, {}
local TREES, FLOWERS, SHROOMS, CRYSTALS, VINES = World.TREES, World.FLOWERS, World.SHROOMS, World.CRYSTALS, World.VINES
local function houseBusy(x, y, m)
	for _, hh in ipairs(HOUSES) do
		if inRect(x, y, hh, m) then return true end
	end
	return hypot(x - WELL.x, y - WELL.y) < m + 30
end
local function railBusy(x, y, m)
	m = m or 0
	return (math.abs(y - RAIL.y) < 110 + m and x > RAIL.x1 - 100 and x < RAIL.x2 + 100) or inRect(x, y, STATION, 120 + m)
end
local function grottoBusy(x, y, m)
	m = m or 0
	for _, g in ipairs(World.GROTTOS) do
		if hypot(x - g.x, y - g.y) < g.r + 90 + m then return true end
	end
	return false
end

do
	local r = rng(42)
	local function seedOf() return math.floor(r() * 1e6) end
	local START, FIELD = World.START, World.FIELD
	local function busy(x, y)
		return hypot(x - START.x, y - START.y) < 280 or inRect(x, y, STABLE, 60) or inRect(x, y, JUMPF, 70)
			or (x < OX + 300 and y > OY + 820 and y < OY + 1200) or inRect(x, y, ARENA, 70) or inRect(x, y, PADDOCK, 60)
			or inRect(x, y, World.SELL, 90) or inRect(x, y, World.SHOP, 90) or inPond(x, y, 70)
			or (x > OX + 860 and x < OX + 1000 and y > OY + 260 and y < OY + 640)
			or (x > OX + 900 and x < OX + 1850 and y > OY + 540 and y < OY + 660)
			or (x > OX + 1060 and x < OX + 1170 and y > OY + 560 and y < OY + 1060)
	end
	local tries = 0
	while #TREES < 46 and tries < 3000 do
		tries += 1
		local inField = r() < 0.6
		local x = inField and (FIELD.x + 60 + r() * (FIELD.w - 120)) or (OX + 40 + r() * 1640)
		local y = inField and (FIELD.y + 60 + r() * (FIELD.h - 120)) or (OY + 1120 + r() * 1220)
		local ok = not busy(x, y)
		if ok and inField and hypot(x - (FIELD.x + FIELD.w / 2), y - (FIELD.y + FIELD.h / 2)) < 420 then ok = false end
		if ok and Util.some(TREES, function(t) return hypot(t.x - x, t.y - y) < 120 end) then ok = false end
		if ok and distToRoad(x, y) < 50 then ok = false end
		if ok then
			table.insert(TREES, { x = x, y = y, r = 32 + r() * 22, kind = r() < 0.3 and "birch" or "oak", s = seedOf(), cr = 9 })
		end
	end

	-- сетка занятости
	local occ = {}
	local function okey(x, y) return math.floor(x / 100) .. "|" .. math.floor(y / 100) end
	local function free(x, y, d)
		local gx, gy = math.floor(x / 100), math.floor(y / 100)
		local k = math.ceil(d / 100)
		for i = -k, k do
			for j = -k, k do
				local cell = occ[(gx + i) .. "|" .. (gy + j)]
				if cell then
					for _, t in ipairs(cell) do
						if hypot(t.x - x, t.y - y) < d then return false end
					end
				end
			end
		end
		return true
	end
	local function addOcc(t)
		local k = okey(t.x, t.y)
		occ[k] = occ[k] or {}
		table.insert(occ[k], t)
	end
	local function add(t)
		table.insert(TREES, t)
		addOcc(t)
	end
	for _, t in ipairs(TREES) do addOcc(t) end
	local function blockedBig(x, y, m)
		m = m or 60
		return inPond(x, y, m) or distToRoad(x, y) < 70 or houseBusy(x, y, m) or inTown(x, y) or inRect(x, y, MOUNTAIN, 40) or railBusy(x, y) or grottoBusy(x, y)
	end
	local pad = 560
	local function sampleIn(rect, id, n, fn)
		for _ = 1, n do
			local x = rect.x - pad + r() * (rect.w + pad * 2)
			local y = rect.y - pad + r() * (rect.h + pad * 2)
			if not (x < 30 or y < 30 or x > W - 30 or y > H - 30) and regionAt(x, y) == id then fn(x, y) end
		end
	end
	local function gridIn(rect, id, step, jit, fn)
		local x = rect.x - pad
		while x < rect.x + rect.w + pad do
			local y = rect.y - pad
			while y < rect.y + rect.h + pad do
				local px, py = x + (r() - 0.5) * jit, y + (r() - 0.5) * jit
				if not (px < 30 or py < 30 or px > W - 30 or py > H - 30) and regionAt(px, py) == id then fn(px, py) end
				y += step
			end
			x += step
		end
	end

	-- озёрный край: редкие деревья
	sampleIn(World.LAKELAND, "lake", 520, function(x, y)
		if blockedBig(x, y) or not free(x, y, 150) then return end
		local rr = 30 + r() * 24
		local kind = r() < 0.45 and "birch" or (r() < 0.5 and "pine" or "oak")
		add({ x = x, y = y, r = rr, kind = kind, s = seedOf(), cr = 9 })
	end)
	-- лес: густо, с полянами
	local clearings = {}
	for _ = 1, 14 do
		local cx = OX + r() * 6200
		local cy = OY + 3500 + r() * 2900
		table.insert(clearings, { x = cx, y = cy, r = 160 + r() * 200 })
	end
	for _, f in ipairs(World.FOREST) do
		gridIn(f, "forest", 108, 80, function(px, py)
			if r() < 0.12 then return end
			if blockedBig(px, py) or Util.some(clearings, function(c) return hypot(c.x - px, c.y - py) < c.r end) or not free(px, py, 80) then return end
			local k = r()
			local rr = 30 + r() * 26
			add({ x = px, y = py, r = rr, kind = k < 0.4 and "pine" or (k < 0.65 and "birch" or "oak"), s = seedOf(), cr = 10 })
		end)
	end
	-- грибное королевство
	gridIn(World.MUSHROOM, "mushroom", 160, 110, function(px, py)
		if r() < 0.35 then return end
		if blockedBig(px, py) or not free(px, py, 110) then return end
		local k = r()
		if k < 0.62 then
			local rr = 34 + r() * 26
			add({ x = px, y = py, r = rr, kind = "spruce", s = seedOf(), cr = 12 })
		else
			local rr = 35 + r() * 30
			add({ x = px, y = py, r = rr, kind = k < 0.78 and "amanita" or (k < 0.9 and "boletus" or "glowshroom"), s = seedOf(), cr = 16 })
		end
	end)
	-- маленькие грибы
	local function shroomAt(area, id, n, types)
		sampleIn(area, id, n, function(x, y)
			if inPond(x, y, 10) or houseBusy(x, y, 20) then return end
			local tp = types[math.floor(r() * #types) + 1]
			table.insert(SHROOMS, { x = x, y = y, type = tp, s = r() })
		end)
	end
	shroomAt(World.MUSHROOM, "mushroom", 640, { "white", "chanterelle", "amanita", "glow", "glow", "violet" })
	shroomAt(World.FOREST[1], "forest", 330, { "white", "chanterelle", "chanterelle", "amanita" })
	shroomAt(World.FOXWOOD, "foxwood", 260, { "white", "chanterelle", "amanita", "amanita" })
	for i, m in ipairs(SHROOMS) do m.id = i end

	-- горы: валуны у подножия
	for _ = 1, 260 do
		local side = math.floor(r() * 4)
		local M = MOUNTAIN
		local t, out = r(), 20 + r() * 260
		local x = side == 0 and M.x + t * M.w or side == 1 and M.x + M.w + out or side == 2 and M.x + t * M.w or M.x - out
		local y = side == 0 and M.y - out or side == 1 and M.y + t * M.h or side == 2 and M.y + M.h + out or M.y + t * M.h
		local skip = side == 3 and y > CAVE_GATE.y1 - 160 and y < CAVE_GATE.y2 + 160
		if not skip and not inPond(x, y, 40) and distToRoad(x, y) >= 60 and free(x, y, 90) then
			add({ x = x, y = y, r = 50 + r() * 70, kind = "cliff", s = seedOf(), cr = 34 })
		end
	end
	-- пещера: валуны и кристаллы
	for _ = 1, 70 do
		local x = CAVE.x + 100 + r() * (CAVE.w - 200)
		local y = CAVE.y + 100 + r() * (CAVE.h - 200)
		local skip = hypot(x - World.CHEST.x, y - World.CHEST.y) < 200 or hypot(x - World.PORTAL.x, y - World.PORTAL.y) < 260
			or (math.abs(y - (CAVE_GATE.y1 + CAVE_GATE.y2) / 2) < 120 and x < CAVE.x + 400)
		if not skip and not Util.some(World.CAVE_INNER_WALLS, function(w) return inRect(x, y, w, 60) end) and free(x, y, 160) then
			add({ x = x, y = y, r = 30 + r() * 40, kind = "rock", s = seedOf(), cr = 26 })
		end
	end
	local crystalCols = { "#6ee7ff", "#c77dff", "#7dffb0", "#ff8fd8" }
	for _ = 1, 120 do
		local x = CAVE.x + 40 + r() * (CAVE.w - 80)
		local y = CAVE.y + 40 + r() * (CAVE.h - 80)
		if not Util.some(World.CAVE_INNER_WALLS, function(w) return inRect(x, y, w, 10) end) then
			local c = crystalCols[math.floor(r() * 4) + 1]
			local hh = 0.8 + r() * 1.6
			table.insert(CRYSTALS, { x = x, y = y, c = c, h = hh, s = seedOf() })
		end
	end

	-- пустыня
	local function desertBusy(x, y, m)
		m = m or 60
		return inPond(x, y, m) or distToRoad(x, y) < 70 or railBusy(x, y)
	end
	sampleIn(World.DESERT, "desert", 2600, function(x, y)
		if desertBusy(x, y) or not free(x, y, 170) then return end
		local nearOasis = hypot(x - World.OASIS.x, y - World.OASIS.y) < 520
		local k = r()
		if nearOasis then add({ x = x, y = y, r = 34 + r() * 16, kind = "palm", s = seedOf(), cr = 9 })
		elseif k < 0.55 then add({ x = x, y = y, r = 18 + r() * 14, kind = "cactus", s = seedOf(), cr = 10 })
		elseif k < 0.75 then add({ x = x, y = y, r = 50 + r() * 60, kind = "mesa", s = seedOf(), cr = 34 })
		elseif k < 0.85 then add({ x = x, y = y, r = 16 + r() * 10, kind = "drybush", s = seedOf(), cr = 6 }) end
	end)
	-- дремучий лес
	gridIn(World.DEEPFOREST, "deepforest", 82, 50, function(px, py)
		if r() < 0.08 or desertBusy(px, py, 40) or not free(px, py, 66) then return end
		local k = r()
		local rr = 36 + r() * 26
		add({ x = px, y = py, r = rr, kind = k < 0.45 and "spruce" or (k < 0.75 and "pine" or "oak"), s = seedOf(), cr = 11, dark = true })
	end)
	-- тундра
	sampleIn(World.TUNDRA, "tundra", 2200, function(x, y)
		if desertBusy(x, y) or not free(x, y, 150) then return end
		local k = r()
		if k < 0.5 then add({ x = x, y = y, r = 30 + r() * 22, kind = "snowspruce", s = seedOf(), cr = 11 })
		elseif k < 0.85 then add({ x = x, y = y, r = 45 + r() * 70, kind = "snowrock", s = seedOf(), cr = 30 }) end
	end)
	-- Пещерные холмы
	sampleIn(World.GROTTO, "grotto", 1300, function(x, y)
		if blockedBig(x, y) or not free(x, y, 160) then return end
		local k = r()
		if k < 0.3 then add({ x = x, y = y, r = 90 + r() * 110, kind = "hill", s = seedOf(), cr = 40 })
		elseif k < 0.6 then add({ x = x, y = y, r = 30 + r() * 40, kind = "rock", s = seedOf(), cr = 24 })
		elseif k < 0.8 then
			local rr = 30 + r() * 20
			add({ x = x, y = y, r = rr, kind = r() < 0.5 and "birch" or "pine", s = seedOf(), cr = 9 })
		else add({ x = x, y = y, r = 18 + r() * 10, kind = "bush", s = seedOf(), cr = 8 }) end
	end)
	-- кольца пещерок
	for _, g in ipairs(World.GROTTOS) do
		local n = math.floor(g.r * 2 * math.pi / 70 + 0.5)
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			local da = math.abs(((a - g.door) % (math.pi * 2) + math.pi * 3) % (math.pi * 2) - math.pi)
			if da >= 0.32 then
				add({ x = g.x + math.cos(a) * g.r, y = g.y + math.sin(a) * g.r, r = 44 + r() * 14, kind = "cavewall", s = seedOf(), cr = 40 })
			end
		end
		for _ = 1, 14 do
			local a, d = r() * math.pi * 2, r() * (g.r - 70)
			local c = crystalCols[math.floor(r() * 4) + 1]
			local hh = 0.6 + r() * 1.2
			table.insert(CRYSTALS, { x = g.x + math.cos(a) * d, y = g.y + math.sin(a) * d, c = c, h = hh, s = seedOf() })
		end
	end
	-- Лисий лес
	local FOX = World.FOXWOOD
	local foxClear = {}
	for _ = 1, 12 do
		local cx = FOX.x + r() * FOX.w
		local cy = FOX.y + r() * FOX.h
		table.insert(foxClear, { x = cx, y = cy, r = 150 + r() * 160 })
	end
	gridIn(FOX, "foxwood", 88, 60, function(px, py)
		if r() < 0.06 or blockedBig(px, py, 40) or Util.some(foxClear, function(c) return hypot(c.x - px, c.y - py) < c.r end) or not free(px, py, 70) then return end
		local k = r()
		local rr = 34 + r() * 28
		local kind = k < 0.35 and "spruce" or k < 0.6 and "pine" or k < 0.8 and "oak" or k < 0.93 and "birch" or "bush"
		add({ x = px, y = py, r = rr, kind = kind, s = seedOf(), cr = k < 0.93 and 11 or 8, dark = k < 0.6 })
	end)
	-- Драконьи скалы
	sampleIn(World.DRAGONROCK, "dragonrock", 1500, function(x, y)
		if blockedBig(x, y) or not free(x, y, 170) then return end
		local k = r()
		if k < 0.45 then add({ x = x, y = y, r = 45 + r() * 70, kind = "spire", s = seedOf(), cr = 30 })
		elseif k < 0.65 then add({ x = x, y = y, r = 26 + r() * 14, kind = "deadtree", s = seedOf(), cr = 9 })
		elseif k < 0.75 then add({ x = x, y = y, r = 60 + r() * 50, kind = "bigbone", s = seedOf(), cr = 0, soft = true })
		elseif k < 0.9 then add({ x = x, y = y, r = 30 + r() * 30, kind = "basalt", s = seedOf(), cr = 22 }) end
	end)
	-- Степь
	sampleIn(World.STEPPE, "steppe", 2600, function(x, y)
		if blockedBig(x, y, 30) or not free(x, y, 120) then return end
		local k = r()
		if k < 0.62 then add({ x = x, y = y, r = 16 + r() * 14, kind = "grass", s = seedOf(), cr = 0, soft = true })
		elseif k < 0.72 then
			local rr = 30 + r() * 24
			add({ x = x, y = y, r = rr, kind = r() < 0.6 and "oak" or "birch", s = seedOf(), cr = 9 })
		elseif k < 0.82 then add({ x = x, y = y, r = 26 + r() * 30, kind = "rock", s = seedOf(), cr = 18 })
		else add({ x = x, y = y, r = 16 + r() * 10, kind = "bush", s = seedOf(), cr = 7 }) end
	end)
	-- острова
	for _, I in ipairs(World.ISLANDS) do
		for _ = 1, 300 do
			local a = r() * math.pi * 2
			local d = math.sqrt(r()) * 0.9 * shapeR(I, a)
			local x, y = I.x + math.cos(a) * I.rx * d, I.y + math.sin(a) * I.ry * d
			local skip = inRect(x, y, I.stable, 80) or inRect(x, y, I.pasture, 70) or hypot(x - I.pen.x, y - I.pen.y) < I.pen.r + 70 or hypot(x - I.pier.x, y - I.pier.y) < 220
			if not skip and hypot(x - I.x, y - I.y) >= 260 and free(x, y, I.bone and 120 or 170) then
				local k = r()
				if I.bone then
					if k < 0.3 then add({ x = x, y = y, r = 70 + r() * 70, kind = "bigbone", s = seedOf(), cr = 0, soft = true })
					elseif k < 0.45 then add({ x = x, y = y, r = 60 + r() * 40, kind = "bigskull", s = seedOf(), cr = 36 })
					elseif k < 0.85 then add({ x = x, y = y, r = 12 + r() * 10, kind = "smallbone", s = seedOf(), cr = 0, soft = true })
					else add({ x = x, y = y, r = 26 + r() * 14, kind = "deadtree", s = seedOf(), cr = 9 }) end
				else
					local rr = 30 + r() * 20
					add({ x = x, y = y, r = rr, kind = (d > 0.7 and k < 0.6) and "palm" or (k < 0.5 and "oak" or "birch"), s = seedOf(), cr = 9 })
				end
			end
		end
	end
	-- небесные острова
	for _, I in ipairs(World.SKY_ISLANDS) do
		for _ = 1, 90 do
			local a = r() * math.pi * 2
			local d = 0.25 + math.sqrt(r()) * 0.6
			local x, y = I.x + math.cos(a) * I.rx * d, I.y + math.sin(a) * I.ry * d
			if hypot(x - World.SKY_PORTAL.x, y - World.SKY_PORTAL.y) >= 220 and not onBridge(x, y, -120) and free(x, y, 190) then
				local rr = 32 + r() * 22
				local kind = r() < 0.5 and "vinetree" or (r() < 0.5 and "birch" or "oak")
				add({ x = x, y = y, r = rr, kind = kind, s = seedOf(), cr = 9, sky = true })
			end
		end
		local n = math.floor((I.rx + I.ry) / 28 + 0.5)
		for k = 0, n - 1 do
			local p = blobPoint(I, k / n * math.pi * 2 + r() * 0.1, -12)
			table.insert(VINES, { x = p.x, y = p.y, len = 3 + r() * 14, s = r() })
		end
	end
	for _, b in ipairs(World.SKY_BRIDGES) do
		local t = 0.1
		while t < 0.95 do
			table.insert(VINES, { x = b[1] + (b[3] - b[1]) * t, y = b[2] + (b[4] - b[2]) * t + BRIDGE_W, len = 2 + r() * 6, s = r() })
			t += 0.12
		end
	end
	local cols = { "#ffffff", "#ffe066", "#ff8fab", "#c77dff", "#ffd6a5", "#f94144" }
	for _, I in ipairs(World.SKY_ISLANDS) do
		for _ = 1, 260 do
			local a = r() * math.pi * 2
			local d = math.sqrt(r()) * 0.92 * shapeR(I, a)
			local c = cols[math.floor(r() * #cols) + 1]
			table.insert(FLOWERS, { x = I.x + math.cos(a) * I.rx * d, y = I.y + math.sin(a) * I.ry * d, c = c, s = 1.5 + r() * 2, sky = true })
		end
	end
	local NOFLOWER = { mountain = true, cave = true, desert = true, tundra = true, sea = true, dragonrock = true, i4 = true, grottocave = true }
	for _ = 1, 14000 do
		local x, y = r() * W, r() * H
		if not busy(x, y) and not houseBusy(x, y, 10) and not NOFLOWER[regionAt(x, y)] then
			local c = cols[math.floor(r() * #cols) + 1]
			table.insert(FLOWERS, { x = x, y = y, c = c, s = 1.5 + r() * 2 })
		end
	end
end

--[[ ---------- непроходимые прямоугольники ---------- ]]
World.SOLIDS = {}
local SOLIDS = World.SOLIDS
World.CAVE_WALLS = {
	{ x = MOUNTAIN.x, y = MOUNTAIN.y, w = MOUNTAIN.w, h = CAVE.y - MOUNTAIN.y },
	{ x = MOUNTAIN.x, y = CAVE.y + CAVE.h, w = MOUNTAIN.w, h = MOUNTAIN.y + MOUNTAIN.h - CAVE.y - CAVE.h },
	{ x = MOUNTAIN.x, y = CAVE.y, w = CAVE.x - MOUNTAIN.x, h = CAVE_GATE.y1 - CAVE.y },
	{ x = MOUNTAIN.x, y = CAVE_GATE.y2, w = CAVE.x - MOUNTAIN.x, h = CAVE.y + CAVE.h - CAVE_GATE.y2 },
	{ x = CAVE.x + CAVE.w, y = CAVE.y, w = MOUNTAIN.x + MOUNTAIN.w - CAVE.x - CAVE.w, h = CAVE.h },
}
do
	local function push(s, kind)
		s.kind = kind
		table.insert(SOLIDS, s)
	end
	local t = 10
	local S = STABLE
	local A1, A2 = World.AISLE_Y1, World.AISLE_Y2
	push({ x = S.x, y = S.y, w = S.w, h = t }, "stable")
	push({ x = S.x, y = S.y + S.h - t, w = S.w, h = t }, "stable")
	push({ x = S.x, y = S.y, w = t, h = A1 - S.y }, "stable")
	push({ x = S.x, y = A2, w = t, h = S.y + S.h - A2 }, "stable")
	push({ x = S.x + S.w - t, y = S.y, w = t, h = A1 - S.y }, "stable")
	push({ x = S.x + S.w - t, y = A2, w = t, h = S.y + S.h - A2 }, "stable")
	local A, f = ARENA, 8
	local GA = World.GATE_A
	push({ x = A.x - f / 2, y = A.y - f / 2, w = A.w + f, h = f }, "fence")
	push({ x = A.x - f / 2, y = A.y + A.h - f / 2, w = A.w + f, h = f }, "fence")
	push({ x = A.x + A.w - f / 2, y = A.y, w = f, h = A.h }, "fence")
	push({ x = A.x - f / 2, y = A.y, w = f, h = GA.y1 - A.y }, "fence")
	push({ x = A.x - f / 2, y = GA.y2, w = f, h = A.y + A.h - GA.y2 }, "fence")
	local P, PG = PADDOCK, World.PADDOCK_GATE
	push({ x = P.x - f / 2, y = P.y - f / 2, w = P.w + f, h = f }, "fence")
	push({ x = P.x - f / 2, y = P.y, w = f, h = P.h }, "fence")
	push({ x = P.x + P.w - f / 2, y = P.y, w = f, h = P.h }, "fence")
	push({ x = P.x - f / 2, y = P.y + P.h - f / 2, w = PG.x1 - P.x + f / 2, h = f }, "fence")
	push({ x = PG.x2, y = P.y + P.h - f / 2, w = P.x + P.w - PG.x2 + f / 2, h = f }, "fence")
	local J, JG = JUMPF, World.JUMPF_GATE
	push({ x = J.x - f / 2, y = J.y - f / 2, w = JG.x1 - J.x + f / 2, h = f }, "fence")
	push({ x = JG.x2, y = J.y - f / 2, w = J.x + J.w - JG.x2 + f / 2, h = f }, "fence")
	push({ x = J.x - f / 2, y = J.y, w = f, h = J.h }, "fence")
	push({ x = J.x + J.w - f / 2, y = J.y, w = f, h = J.h }, "fence")
	push({ x = J.x - f / 2, y = J.y + J.h - f / 2, w = J.w + f, h = f }, "fence")
	push({ x = World.SELL.x, y = World.SELL.y, w = World.SELL.w, h = World.SELL.h }, "cart")
	push({ x = World.SHOP.x, y = World.SHOP.y, w = World.SHOP.w, h = World.SHOP.h }, "cart")
	for _, w in ipairs(World.CAVE_WALLS) do push({ x = w.x, y = w.y, w = w.w, h = w.h, rock = true }, "rock") end
	for _, w in ipairs(World.CAVE_INNER_WALLS) do push({ x = w.x, y = w.y, w = w.w, h = w.h, rock = true }, "rock") end
	for _, hh in ipairs(HOUSES) do push({ x = hh.x, y = hh.y, w = hh.w, h = hh.h }, "house") end
	for _, st in ipairs(World.MARKET_STALLS) do push({ x = st.x, y = st.y, w = st.w, h = st.h }, "stall") end
	push({ x = STATION.x + 30, y = STATION.y - 60, w = 160, h = 70 }, "station")
	for _, I in ipairs(World.ISLANDS) do
		local st, t2 = I.stable, 10
		push({ x = st.x, y = st.y, w = st.w, h = t2 }, "stable")
		push({ x = st.x, y = st.y, w = t2, h = st.h }, "stable")
		push({ x = st.x + st.w - t2, y = st.y, w = t2, h = st.h }, "stable")
		local P2 = I.pasture
		push({ x = P2.x - f / 2, y = P2.y - f / 2, w = P2.w + f, h = f }, "fence")
		push({ x = P2.x - f / 2, y = P2.y, w = f, h = P2.h }, "fence")
		push({ x = P2.x + P2.w - f / 2, y = P2.y, w = f, h = P2.h }, "fence")
		push({ x = P2.x - f / 2, y = P2.y + P2.h - f / 2, w = I.gate.x1 - P2.x + f / 2, h = f }, "fence")
		push({ x = I.gate.x2, y = P2.y + P2.h - f / 2, w = P2.x + P2.w - I.gate.x2 + f / 2, h = f }, "fence")
		for k = 0, 23 do
			local a = k / 24 * math.pi * 2
			if math.abs(a - math.pi * 1.5) >= 0.3 then
				push({ x = I.pen.x + math.cos(a) * I.pen.r - 9, y = I.pen.y + math.sin(a) * I.pen.r - 9, w = 18, h = 18, pen = true }, "post")
			end
		end
	end
end

-- сетка для быстрых столкновений с деревьями
local GRID = 200
local treeGrid = {}
for _, t in ipairs(TREES) do
	if not t.soft then
		local k = math.floor(t.x / GRID) .. "|" .. math.floor(t.y / GRID)
		treeGrid[k] = treeGrid[k] or {}
		table.insert(treeGrid[k], t)
	end
end
local function treesNear(x, y)
	local gx, gy = math.floor(x / GRID), math.floor(y / GRID)
	local out = {}
	for i = -1, 1 do
		for j = -1, 1 do
			local a = treeGrid[(gx + i) .. "|" .. (gy + j)]
			if a then
				for _, t in ipairs(a) do table.insert(out, t) end
			end
		end
	end
	return out
end
World.treesNear = treesNear

local function pushOutRect(e, r, s)
	local cx = math.max(s.x, math.min(e.x, s.x + s.w))
	local cy = math.max(s.y, math.min(e.y, s.y + s.h))
	local dx, dy = e.x - cx, e.y - cy
	local d2 = dx * dx + dy * dy
	if d2 >= r * r then return end
	if d2 == 0 then
		local opts = { { e.x - s.x, -1, 0 }, { s.x + s.w - e.x, 1, 0 }, { e.y - s.y, 0, -1 }, { s.y + s.h - e.y, 0, 1 } }
		table.sort(opts, function(a, b) return a[1] < b[1] end)
		e.x += opts[1][2] * (opts[1][1] + r)
		e.y += opts[1][3] * (opts[1][1] + r)
	else
		local d = math.sqrt(d2)
		e.x = cx + (dx / d) * r
		e.y = cy + (dy / d) * r
	end
end

-- вытолкнуть круг (x, y, r) из препятствий (для лошадей и существ на сервере)
function World.collide(e, r)
	for _, s in ipairs(SOLIDS) do pushOutRect(e, r, s) end
	for _, t in ipairs(treesNear(e.x, e.y)) do
		local dx, dy = e.x - t.x, e.y - t.y
		local d = hypot(dx, dy)
		local rr = r + (t.cr or 9)
		if d < rr and d > 0 then
			e.x = t.x + (dx / d) * rr
			e.y = t.y + (dy / d) * rr
		end
	end
	local L = lakeAt(e.x, e.y, r)
	if L then blobPush(L, e, r, false) end
	if e.x > SEA.x - r - 50 and e.y <= H then
		local cx = coastX(e.y)
		if e.x > cx - r then
			local best, bd = nil, 1e9
			for _, I in ipairs(World.ISLANDS) do
				local q = blobInfo(I, e.x, e.y)
				local dd = q.d / q.R
				if dd < bd then bd = dd; best = I end
			end
			if best and bd < 1.6 then blobPush(best, e, r, true)
			else e.x = math.min(e.x, cx - r) end
		end
	end
	if e.y > H - r then
		if not skyWalkable(e.x, e.y, r * 0.5) then
			local best, bd = nil, 1e9
			for _, I in ipairs(World.SKY_ISLANDS) do
				local q = { x = e.x, y = e.y }
				blobPush(I, q, r * 0.6, true)
				local dd = hypot(q.x - e.x, q.y - e.y)
				if dd < bd then bd = dd; best = q end
			end
			for _, b in ipairs(World.SKY_BRIDGES) do
				local q = segPoint(e.x, e.y, b)
				local dd = hypot(q.x - e.x, q.y - e.y)
				local lim = BRIDGE_W - r * 0.5 - 1
				local p = dd > lim and { x = q.x + (e.x - q.x) / dd * lim, y = q.y + (e.y - q.y) / dd * lim } or { x = e.x, y = e.y }
				local pd = hypot(p.x - e.x, p.y - e.y)
				if pd < bd then bd = pd; best = p end
			end
			if bd < 320 then
				e.x, e.y = best.x, best.y
			else
				e.y = H - r
			end
		end
		e.x = math.clamp(e.x, r, W - r)
		e.y = math.min(World.TOTAL_H - r, e.y)
		return
	end
	local dw = hypot(e.x - WELL.x, e.y - WELL.y)
	if dw < WELL.r + r and dw > 0 then
		e.x = WELL.x + (e.x - WELL.x) / dw * (WELL.r + r)
		e.y = WELL.y + (e.y - WELL.y) / dw * (WELL.r + r)
	end
	e.x = math.clamp(e.x, r, W - r)
	e.y = math.clamp(e.y, r, H - r)
end

-- можно ли здесь стоять (для приземления и стройки)
function World.blocked(x, y, r)
	r = r or 14
	if y > H - r and not skyWalkable(x, y, r) then return true end
	if inPond(x, y, r) or World.inSea(x, y, r) then return true end
	local bx, by, bw, bh = x - r, y - r, 2 * r, 2 * r
	local function hit(s)
		return bx < s.x + s.w and bx + bw > s.x and by < s.y + s.h and by + bh > s.y
	end
	for _, s in ipairs(SOLIDS) do
		if hit(s) then return true end
	end
	for _, t in ipairs(treesNear(x, y)) do
		if hypot(t.x - x, t.y - y) < r + (t.cr or 9) then return true end
	end
	return false
end

-- пиксели карты ↔ стады Roblox
function World.toStuds(x, y, h)
	return Vector3.new(x * K, h or 0, y * K)
end
function World.fromStuds(v)
	return v.X / K, v.Z / K
end
-- высота земли в стадах (небо — выше)
-- настоящая высота поверхности рельефа: сервер замеряет её лучом после постройки
-- и кладёт в атрибут workspace.GroundY, клиенты читают оттуда (см. World.syncGround)
World.GROUND = 0
function World.syncGround()
	local v = workspace:GetAttribute("GroundY")
	if type(v) == "number" then World.GROUND = v end
	return World.GROUND
end
function World.groundY(x, y)
	if y > H then return World.SKY_Y + World.GROUND end
	return World.GROUND
end

return World
