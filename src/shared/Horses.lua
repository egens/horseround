--[[
	Лошади: создание, возраст, навыки, цена (перенос js/horses.js).
	Лошадь — обычная таблица, её можно сохранять в DataStore как есть
	(поля, начинающиеся с «_», — служебные и не сохраняются).
]]
local Util = require(script.Parent.Util)
local Genetics = require(script.Parent.Genetics)
local mix = Util.mix
local rand, clamp, pick = Util.rand, Util.clamp, Util.pick

local Horses = {}

local F_NAMES = { "Звёздочка", "Ласточка", "Ромашка", "Изюминка", "Буря", "Вьюга", "Снежинка", "Карамель",
	"Корица", "Ириска", "Луна", "Белла", "Милка", "Зорька", "Искра", "Плюшка", "Багира", "Фиалка",
	"Метелица", "Ягодка", "Жемчужина", "Принцесса", "Радуга", "Лаванда", "Ночка", "Пуговка", "Маруся", "Вишенка" }
local M_NAMES = { "Гром", "Ветер", "Буран", "Орлик", "Изумруд", "Каштан", "Уголёк", "Мустанг", "Смерч",
	"Огонёк", "Пряник", "Барон", "Граф", "Алмаз", "Тайфун", "Атлас", "Цезарь", "Дымок", "Кузнечик",
	"Рубин", "Сокол", "Шторм", "Янтарь", "Зефир", "Самсон", "Вихрь", "Персик", "Бархат" }
Horses.SKILLS = { speed = "Скорость", jump = "Прыжки", dressage = "Выездка", stamina = "Выносливость" }
Horses.SKILL_ORDER = { "speed", "jump", "dressage", "stamina" }
local FACE = { [0] = "", "звёздочка", "проточина", "лысина" }

local CRYSTAL_TINTS = {
	{ "#4dabf7", "синяя" }, { "#ff6b6b", "красная" }, { "#ffd43b", "жёлтая" }, { "#51cf66", "зелёная" },
	{ "#ff922b", "оранжевая" }, { "#cc5de8", "фиолетовая" }, { "#f783ac", "розовая" }, { "#3bc9db", "бирюзовая" },
}
Horses.ELEMS = {
	ice = { word = "ледяная", icon = "🧊", body = "#74c0fc", mane = "#e7f5ff", legs = "#4dabf7", maneCols = { "#a5f3fc", "#cffafe", "#67e8f9", "#e0f2fe", "#bae6fd" }, maneGlow = true },
	crystal = { word = "кристальная", icon = "💎", body = "#4dabf7", mane = "#d0ebff", legs = "#339af0", maneGlow = true },
	fire = { word = "огненная", icon = "🔥", body = "#f76707", mane = "#ffd43b", legs = "#c92a2a", maneCols = { "#ff3d00", "#ff6d00", "#ff9100", "#ffc400", "#ffea00" }, maneGlow = true },
	water = { word = "водяная", icon = "💧", body = "#339af0", mane = "#e7f5ff", legs = "#1c7ed6", maneCols = { "#ffffff", "#d0ebff", "#a5d8ff", "#74c0fc", "#e7f5ff" }, maneGlow = true },
	rainbow = { word = "радужная", icon = "🌈", body = "#ffd43b", mane = "#cc5de8", legs = "#4dabf7", maneCols = { "#ff6b6b", "#ff922b", "#ffd43b", "#51cf66", "#4dabf7", "#5c7cfa", "#cc5de8" }, maneGlow = true },
	sun = { word = "солнечная", icon = "☀️", body = "#fcc419", mane = "#fff3bf", legs = "#f08c00", maneCols = { "#fff3bf", "#ffe066", "#ffc078", "#ffa94d", "#ffd43b" }, maneGlow = true },
	sand = { word = "песочная", icon = "🏜️", body = "#e9d3a1", mane = "#c9a66b", legs = "#d4b67a", maneCols = { "#c9a66b", "#b08d57", "#dcc394" } },
	stone = { word = "каменная", icon = "⛰️", body = "#868e96", mane = "#495057", legs = "#6c757d", maneCols = { "#495057", "#343a40", "#5c940d" } },
	mushroom = { word = "грибная", icon = "🍄", body = "#f1e3c6", mane = "#e03131", legs = "#e8d9b5", maneCols = { "#e03131", "#c92a2a", "#ffffff", "#e03131" } },
	leaf = { word = "лиственная", icon = "🍃", body = "#40c057", mane = "#2b8a3e", legs = "#5c3d1e", maneCols = { "#2b8a3e", "#37b24d", "#69db7c", "#fab005", "#2f9e44" } },
	damp = { word = "сырая", icon = "💦", body = "#4a5a6a", mane = "#e9ecef", legs = "#3b4754", maneCols = { "#f1f3f5", "#dee2e6", "#ced4da" } },
}
local function colorWord(list, c)
	for _, t in ipairs(list) do
		if t[1] == c then return t[2] end
	end
	return "переливчатая"
end
function Horses.crystalTint()
	return pick(CRYSTAL_TINTS)[1]
end
local function tintName(c) return colorWord(CRYSTAL_TINTS, c) end

local function elemLook(h)
	local k = h.magic and h.magic.elem
	local E = k and Horses.ELEMS[k]
	if not E then return nil end
	if k == "crystal" then
		local t = h.magic.tint or "#4dabf7"
		return { elem = k, tint = t, name = "кристальная (" .. tintName(t) .. ")", body = t, mane = mix(t, "#ffffff", 0.6), legs = mix(t, "#000000", 0.15) }
	end
	return { elem = k, name = k == "damp" and "сырая с белыми узорами" or E.word, body = E.body, mane = E.mane, legs = E.legs }
end

local SCALES = { { "#2f9e44", "зелёная" }, { "#1c7ed6", "синяя" }, { "#c92a2a", "красная" }, { "#7048e8", "фиолетовая" }, { "#e67700", "оранжевая" },
	{ "#0ca678", "изумрудная" }, { "#495057", "тёмно-серая" }, { "#f2b705", "золотая" }, { "#ae3ec9", "сиреневая" }, { "#1098ad", "бирюзовая" } }
Horses.ZEBRA = {
	brown = { c = "#6b4423", word = "коричневые" }, gold = { c = "#e8a400", word = "золотые" }, beige = { c = "#cdb48a", word = "бежевые" },
	black = { c = "#1b1b1b", word = "чёрные" }, grey = { c = "#7d7d7d", word = "серые" }, rainbow = { c = "rainbow", word = "радужные" },
}
local GLOWS = { { "#39ff14", "зелёные" }, { "#00e5ff", "голубые" }, { "#ff2bd6", "розовые" }, { "#ffea00", "жёлтые" }, { "#b026ff", "фиолетовые" }, { "#ff6a00", "оранжевые" }, { "#ff1744", "красные" } }
Horses.FOXES = {
	red = { c = "#d9661f", word = "рыжая" }, fire = { c = "#b8460e", word = "огненно-рыжая" }, silverblack = { c = "#3b3030", word = "чёрно-бурая" },
	silver = { c = "#a8a9ad", word = "серебристая" }, arctic = { c = "#f1eee6", word = "белая, как песец" }, sand = { c = "#c98b4a", word = "песочная" },
}
Horses.HOLIDAYS = {
	halloween = { word = "хэллоуинская: тыквы, летучие мыши и привидения", icon = "🎃", body = "#2d2433", mane = "#ff7b00", legs = "#1b1620" },
	newyear = { word = "новогодняя ёлочка с игрушками", icon = "🎄", body = "#2f7a3a", mane = "#1f5a2a", legs = "#24622f" },
	newyearglow = { word = "новогодняя светящаяся", icon = "✨", body = "#74c0fc", mane = "#ffffff", legs = "#4dabf7" },
	easter = { word = "пасхальная: яички, полосочки и точечки", icon = "🥚", body = "#ffb3d1", mane = "#ffffff", legs = "#f783ac" },
}
Horses.GLOW_NY = { "#ff6b6b", "#ffd43b", "#69db7c", "#4dabf7", "#cc5de8", "#ff922b", "#f783ac" }
local COATS = {
	rainbow = { name = "радужная (переливается)", body = "#e9dcff", mane = "#ffffff", legs = "#d0bfff", rarity = 3 },
	pearl = { name = "жемчужная", body = "#efe6d8", mane = "#f8f3ea", legs = "#e2d6c3", rarity = 1.6 },
}

-- «random» в описании породы → конкретный цвет или вид
function Horses.resolveMagic(m)
	if not m then return m end
	if m.scales == "random" then m.scales = pick(SCALES)[1] end
	if m.zebra == "random" then m.zebra = Util.pickKey(Horses.ZEBRA) end
	if m.glow == "random" then m.glow = pick(GLOWS)[1] end
	if m.fox == "random" then m.fox = Util.pickKey(Horses.FOXES) end
	if m.holiday == "random" then m.holiday = Util.pickKey(Horses.HOLIDAYS) end
	if m.holiday == "newyearglow" and not m.tint then m.tint = pick(Horses.GLOW_NY) end
	return m
end

local function magicLook(h)
	local m = h.magic or {}
	if m.holiday and Horses.HOLIDAYS[m.holiday] then
		local D = Horses.HOLIDAYS[m.holiday]
		if m.holiday == "newyearglow" then
			local t = m.tint or "#74c0fc"
			return { name = D.word, body = t, mane = mix(t, "#ffffff", 0.6), legs = mix(t, "#000000", 0.15), holiday = m.holiday }
		end
		return { name = D.word, body = D.body, mane = D.mane, legs = D.legs, holiday = m.holiday }
	end
	if m.scales then
		local c = m.scales
		return { name = m.dragonEyes and "розовая чешуя, драконьи глаза" or ("чешуйчатая, " .. colorWord(SCALES, c)), body = c, mane = mix(c, "#000000", 0.35), legs = mix(c, "#000000", 0.25), scales = c }
	end
	if m.zebra and Horses.ZEBRA[m.zebra] then
		local Z = Horses.ZEBRA[m.zebra]
		return { name = "зебра: " .. Z.word .. " полоски", body = "#f4f1ea", mane = Z.c == "rainbow" and "#cc5de8" or Z.c, legs = "#f4f1ea", zebra = Z.c }
	end
	if m.glow then
		return { name = "чёрная, светятся " .. colorWord(GLOWS, m.glow) .. " узоры", body = "#141218", mane = "#0d0c10", legs = "#0d0c10", glow = m.glow }
	end
	if m.fox and Horses.FOXES[m.fox] then
		local F = Horses.FOXES[m.fox]
		return { name = "лисья, " .. F.word, body = F.c, mane = F.c, legs = m.fox == "arctic" and "#d6d0c4" or "#2b2420", fox = F.c }
	end
	if h.coat and COATS[h.coat] then
		local C = COATS[h.coat]
		return { name = C.name, body = C.body, mane = C.mane, legs = C.legs, coat = h.coat, rarityMul = C.rarity }
	end
	return nil
end

local nextWildId = 10000000
function Horses.newWildId()
	nextWildId += 1
	return nextWildId
end

function Horses.randomName(sex, taken)
	taken = taken or {}
	local takenSet = {}
	for _, n in ipairs(taken) do takenSet[n] = true end
	local src = sex == "f" and F_NAMES or M_NAMES
	local list = Util.filter(src, function(n) return not takenSet[n] end)
	if #list > 0 then return pick(list) end
	return pick(src) .. " " .. math.floor(rand(2, 99))
end

local function randomMarks()
	local r = math.random()
	return {
		face = r < 0.4 and 0 or r < 0.65 and 1 or r < 0.88 and 2 or 3,
		legs = { math.random() < 0.18, math.random() < 0.18, math.random() < 0.18, math.random() < 0.18 },
	}
end

local function inheritMarks(a, b)
	local src = math.random() < 0.5 and a or b
	local legs = {}
	for i = 1, 4 do
		if math.random() < 0.75 then legs[i] = src.legs[i] else legs[i] = math.random() < 0.2 end
	end
	return {
		face = math.random() < 0.7 and src.face or math.random(0, 3),
		legs = legs,
		lp = (math.random() < 0.5 and a or b).lp or "blanket",
	}
end

function Horses.create(o)
	local breed = o.breed or "mix"
	local B = Genetics.BREEDS[breed] or Genetics.BREEDS.mix
	local sex = o.sex or (math.random() < 0.5 and "f" or "m")
	local coat = o.coat
	if o.coat == nil and B.coats then
		for _, k in ipairs(Util.keys(B.coats)) do
			if not coat and math.random() < B.coats[k] then coat = k end
		end
	end
	local marks = o.marks or randomMarks()
	if not o.marks and B.marksMaresOnly and sex == "m" then marks = { face = 0, legs = { false, false, false, false } } end
	if not o.marks then marks.lp = math.random() < 0.5 and "full" or "blanket" end
	local g = o.g or Genetics.randomGenotype(breed)
	if not o.g and B.alwaysSpots and not g.LP[1] and not g.LP[2] then g.LP[1] = true end
	local base = o.base or {
		speed = math.floor(rand(B.stats.speed[1], B.stats.speed[2]) + 0.5),
		jump = math.floor(rand(B.stats.jump[1], B.stats.jump[2]) + 0.5),
		dressage = math.floor(rand(B.stats.dressage[1], B.stats.dressage[2]) + 0.5),
		stamina = math.floor(rand(B.stats.stamina[1], B.stats.stamina[2]) + 0.5),
	}
	local magic
	if o.magic ~= nil then
		magic = o.magic or nil
	elseif B.magic then
		magic = Util.copy(B.magic)
		if magic.elem == "crystal" then magic.tint = Horses.crystalTint() end
		Horses.resolveMagic(magic)
	end
	return {
		id = o.id or Horses.newWildId(),
		name = o.name or Horses.randomName(sex, o.taken),
		sex = sex, breed = breed,
		g = g, base = base, coat = coat,
		train = { speed = 0, jump = 0, dressage = 0, stamina = 0 },
		age = o.age or rand(3, 12),
		size = o.size or B.size * rand(0.95, 1.05),
		temper = o.temper or clamp(B.temper + rand(-0.15, 0.15), 0.05, 0.95),
		marks = marks,
		hunger = 80, energy = 100, mood = 70, clean = 80,
		preg = nil,
		magic = magic,
		mud = 0, wet = 0,
		maneStyle = o.maneStyle or "normal", maneDye = o.maneDye,
		state = "wild", stall = -1,
		x = 0, y = 0, angle = 0, vx = 0, vy = 0, spd = 0, phase = math.random() * 6, headTurn = 0,
		seed = math.random(0, 999999999),
	}
end

-- волшебные черты передаются жеребёнку с вероятностью 50% от каждого родителя
local function wingType(w)
	if w == true then return "pegasus" end
	return w
end
Horses.wingType = wingType

local function inheritMagic(a, b)
	a = a or {}
	b = b or {}
	local m = {}
	local any = false
	local function set(k, v) m[k] = v; any = true end
	for _, k in ipairs({ "horn", "skeleton" }) do
		local n = (a[k] and 1 or 0) + (b[k] and 1 or 0)
		if n > 0 and math.random() < (n == 2 and 0.75 or 0.5) then set(k, true) end
	end
	local wings = {}
	if a.wings then table.insert(wings, wingType(a.wings)) end
	if b.wings then table.insert(wings, wingType(b.wings)) end
	if #wings > 0 and math.random() < (#wings == 2 and 0.75 or 0.5) then set("wings", pick(wings)) end
	local manes = {}
	if a.mane then table.insert(manes, a.mane) end
	if b.mane then table.insert(manes, b.mane) end
	if #manes > 0 and math.random() < (#manes == 2 and 0.75 or 0.5) then set("mane", pick(manes)) end
	local elems = {}
	if a.elem then table.insert(elems, a) end
	if b.elem then table.insert(elems, b) end
	if #elems > 0 and math.random() < (#elems == 2 and 0.75 or 0.5) then
		local src = pick(elems)
		set("elem", src.elem)
		if src.elem == "crystal" then set("tint", src.tint or Horses.crystalTint()) end
	end
	local clouds = (a.cloud and 1 or 0) + (b.cloud and 1 or 0)
	if clouds > 0 and math.random() < (clouds == 2 and 0.75 or 0.5) then set("cloud", true) end
	for _, k in ipairs({ "bones", "dhorns" }) do
		if (a[k] or b[k]) and math.random() < ((a[k] and b[k]) and 0.75 or 0.5) then set(k, true) end
	end
	for _, k in ipairs({ "scales", "zebra", "glow", "fox", "holiday" }) do
		local src = {}
		if a[k] then table.insert(src, a) end
		if b[k] then table.insert(src, b) end
		if #src > 0 and math.random() < (#src == 2 and 0.75 or 0.5) then
			local q = pick(src)
			set(k, q[k])
			if k == "scales" and q.dragonEyes then set("dragonEyes", q.dragonEyes) end
			if k == "holiday" and q.tint then set("tint", q.tint) end
		end
	end
	return any and m or nil
end

function Horses.foal(mother, father, taken, id)
	local sex = math.random() < 0.5 and "f" or "m"
	local base = {}
	for k in pairs(Horses.SKILLS) do
		base[k] = math.floor(clamp((mother.base[k] + father.base[k]) / 2 + rand(-6, 8), 10, 100) + 0.5)
	end
	local coats = {}
	if mother.coat then table.insert(coats, mother.coat) end
	if father.coat then table.insert(coats, father.coat) end
	local coat = false
	if #coats > 0 and math.random() < 0.5 then coat = pick(coats) end
	local magic = inheritMagic(mother.magic, father.magic)
	local h = Horses.create({
		id = id,
		breed = mother.breed == father.breed and mother.breed or "mix",
		sex = sex, base = base, taken = taken,
		g = Genetics.inherit(mother.g, father.g),
		age = 0,
		size = ((mother.size + father.size) / 2) * rand(0.96, 1.04),
		temper = clamp((mother.temper + father.temper) / 2 + rand(-0.1, 0.1), 0.05, 0.95),
		marks = inheritMarks(mother.marks, father.marks),
		magic = magic or false,
		coat = coat,
	})
	if h.coat == false then h.coat = nil end
	return h
end

Horses.WING_NAMES = {
	pegasus = "крылья пегаса 🕊️", butterfly = "крылья бабочки 🦋", dragon = "крылья дракона 🐉",
	raven = "крылья ворона 🐦", dragonfly = "крылья стрекозы", bee = "крылья пчёлки 🐝",
}
function Horses.magicText(h)
	local m = h.magic
	if not m then return "" end
	local p = {}
	if m.wings then table.insert(p, Horses.WING_NAMES[wingType(m.wings)] or "крылья") end
	if m.horn then table.insert(p, "рог 🦄") end
	if m.mane == "fire" then table.insert(p, "огненная грива 🔥") end
	if m.mane == "ice" then table.insert(p, "ледяная грива ❄️") end
	if m.skeleton then table.insert(p, "скелет 💀") end
	if m.elem and Horses.ELEMS[m.elem] then
		local E = Horses.ELEMS[m.elem]
		table.insert(p, (m.elem == "crystal" and ("кристальная, " .. tintName(m.tint)) or E.word) .. " " .. E.icon)
	end
	if m.cloud then table.insert(p, "летает на облачках ☁️") end
	if m.bones then table.insert(p, "череп на голове и рёбра 💀") end
	if m.scales then table.insert(p, m.dragonEyes and "розовая драконья чешуя и драконьи глаза 🐉💗" or "драконья чешуя 🐲") end
	if m.dhorns then table.insert(p, "серые драконьи рога") end
	if m.zebra then table.insert(p, "полоски зебры: " .. (Horses.ZEBRA[m.zebra] and Horses.ZEBRA[m.zebra].word or "") .. " 🦓") end
	if m.glow then table.insert(p, "светящиеся узоры: " .. colorWord(GLOWS, m.glow) .. " ✨") end
	if m.fox then table.insert(p, "лисий мех и лисий хвост 🦊") end
	if m.holiday and Horses.HOLIDAYS[m.holiday] then
		table.insert(p, Horses.HOLIDAYS[m.holiday].word .. " " .. Horses.HOLIDAYS[m.holiday].icon)
	end
	return table.concat(p, ", ")
end
function Horses.isMagic(h)
	local m = h.magic
	return m ~= nil and not not (m.wings or m.horn or m.mane or m.elem or m.cloud or m.scales or m.glow or m.fox or m.holiday or m.bones)
end
-- летать умеют лошади с крыльями и облачные лошадки
function Horses.canFly(h)
	return h ~= nil and h.magic ~= nil and not not (h.magic.wings or h.magic.cloud)
end

-- фенотип с учётом волшебства (кешируется по возрасту)
function Horses.pheno(h)
	local key = math.floor(h.age * 8)
	if not h._ph or h._phKey ~= key then
		local ph = Genetics.phenotype(h.g, h.age)
		local el = elemLook(h) or magicLook(h)
		if el then
			local rarity = ph.rarity * (el.rarityMul or 1)
			ph = Util.assign({}, ph, el, { stripe = false, roan = false, tob = false, leo = false, dapple = false, greyLevel = 0, pinkSkin = false, rarity = rarity })
			if ph.stripe == false then ph.stripe = nil end
		end
		h._ph = ph
		h._phKey = key
	end
	return h._ph
end

function Horses.isAdult(h) return h.age >= 3 end
Horses.RIDE_AGE = 5
function Horses.canRide(h) return h.age >= Horses.RIDE_AGE end
function Horses.sizeOf(h)
	return h.size * (h.age < 3 and (0.55 + 0.45 * (h.age / 3)) or 1)
end
function Horses.skill(h, k)
	return math.min(100, math.floor(h.base[k] + h.train[k] + 0.5))
end
function Horses.addTrain(h, k, v)
	h.train[k] = math.max(0, math.min(100 - h.base[k], h.train[k] + v))
end

function Horses.ageText(h)
	if h.age < 1 then
		local m = math.max(0, math.floor(h.age * 12))
		if m == 0 then return "новорождённый" end
		return m .. " " .. Util.plural(m, "месяц", "месяца", "месяцев")
	end
	local y = math.floor(h.age)
	return y .. " " .. Util.plural(y, "год", "года", "лет")
end
function Horses.sexText(h)
	if h.age < 3 then return h.sex == "f" and "кобылка" or "жеребчик" end
	return h.sex == "f" and "кобыла" or "жеребец"
end
function Horses.marksText(h)
	local parts = {}
	if h.marks.face and h.marks.face > 0 then table.insert(parts, FACE[h.marks.face]) end
	local n = 0
	for i = 1, 4 do
		if h.marks.legs[i] then n += 1 end
	end
	if n > 0 and not Horses.pheno(h).tob then
		table.insert(parts, n .. " " .. Util.plural(n, "белая нога", "белые ноги", "белых ног"))
	end
	return #parts > 0 and table.concat(parts, ", ") or "без отметин"
end

function Horses.price(h)
	local avg = 0
	for k in pairs(Horses.SKILLS) do avg += Horses.skill(h, k) end
	avg /= 4
	local p = 100 + avg * 4
	p *= Horses.pheno(h).rarity
	if h.age < 1 then p *= 0.5
	elseif h.age < 3 then p *= 0.75
	elseif h.age > 16 then p *= 0.6 end
	p *= 0.85 + h.mood / 600 + h.clean / 1200
	if h.preg then p *= 1.3 end
	local m = h.magic
	if m then
		local function f(cond, v) return cond and v or 1 end
		p *= f(m.wings, 2) * f(m.horn, 2) * f(m.mane, 1.6) * f(m.skeleton, 1.8) * f(m.elem, 1.7) * f(m.cloud, 2)
			* f(m.bones, 1.8) * f(m.scales, 1.5) * f(m.dragonEyes, 3) * f(m.zebra, 1.4) * f(m.glow, 1.9) * f(m.fox, 1.7) * f(m.holiday, 2)
	end
	if h.shoes then p *= 1.05 end
	if (h.mud or 0) > 40 then p *= 0.95 end
	return math.max(20, math.floor(p / 5 + 0.5) * 5)
end

-- глагол в нужном роде: v(h, 'устала', 'устал')
function Horses.v(h, fem, masc)
	return h.sex == "f" and fem or masc
end

function Horses.temperText(h)
	if h.temper < 0.35 then return "спокойный 😌" end
	if h.temper < 0.6 then return "обычный 🙂" end
	return "горячий 🔥"
end

-- то, что нужно клиенту, чтобы нарисовать лошадь (без навыков и прочего)
function Horses.look(h)
	return {
		id = h.id, breed = h.breed, sex = h.sex, g = h.g, marks = h.marks, magic = h.magic, coat = h.coat,
		maneStyle = h.maneStyle, maneDye = h.maneDye, seed = h.seed, size = h.size, age = h.age, shoes = h.shoes,
		mud = h.mud or 0, wet = h.wet or 0, name = h.name,
	}
end
-- ключ внешности: если поменялся — модель надо пересобрать
function Horses.lookKey(h)
	local mudL = math.min(4, math.floor((h.mud or 0) / 22))
	local wet = h.wet or 0
	local wetL = wet > 60 and 2 or wet > 22 and 1 or 0
	return table.concat({ math.floor(h.age * 8), h.maneStyle or "", h.maneDye or "", h.coat or "", h.shoes and 1 or 0, mudL, wetL,
		h.magic and (h.magic.wings and tostring(h.magic.wings) or "") .. (h.magic.holiday or "") or "" }, "|")
end

-- убрать служебные поля перед сохранением
function Horses.clean(h)
	local r = {}
	for k, v in pairs(h) do
		if type(k) ~= "string" or string.sub(k, 1, 1) ~= "_" then r[k] = v end
	end
	return r
end

return Horses
