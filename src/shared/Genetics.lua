--[[
	Генетика окрасов лошадей (перенос js/genetics.js).
	Упрощённая модель на реальных генах:
	  E  (Extension)  — есть ли чёрный пигмент: ee = рыжая
	  A  (Agouti)     — где чёрный пигмент: A_ = гнедая, aa = вороная
	  Cr (Cream)      — осветление: 1 копия = соловая / буланая / дымчатая, 2 копии = изабелловая
	  D  (Dun)        — саврасость: светлое тело и «ремень» вдоль спины
	  G  (Grey)       — поседение с возрастом
	  TO (Tobiano)    — пегость
	  LP (Leopard)    — чубарость
	  Rn (Roan)       — чалость
	  Z  (Silver)     — серебристость
	  F  (Flaxen)     — ff даёт светлую гриву у рыжих
]]
local Util = require(script.Parent.Util)
local mix = Util.mix

local Genetics = {}

Genetics.LOCI = { "E", "A", "Cr", "D", "G", "TO", "LP", "Rn", "Z", "F" }
local SYMBOLS = {
	E = { "E", "e" }, A = { "A", "a" }, Cr = { "Cr", "n" }, D = { "D", "nd" }, G = { "G", "g" },
	TO = { "TO", "n" }, LP = { "Lp", "n" }, Rn = { "Rn", "n" }, Z = { "Z", "n" }, F = { "F", "f" },
}
local DEFAULT_FREQ = { E = 0.6, A = 0.5, Cr = 0, D = 0, G = 0, TO = 0, LP = 0, Rn = 0, Z = 0, F = 0.9 }

-- freq — частота «вариантного» аллеля в породе; weight — как часто встречается в диком табуне
Genetics.BREEDS = {
	akhal = { name = "Ахалтекинская", weight = 1, size = 1.0, temper = 0.75, sheen = true,
		freq = { E = 0.65, A = 0.55, Cr = 0.3, G = 0.06 },
		stats = { speed = { 75, 95 }, jump = { 45, 70 }, dressage = { 50, 75 }, stamina = { 75, 95 } } },
	arab = { name = "Арабская", weight = 1.2, size = 0.92, temper = 0.7, coats = { rainbow = 0.03 },
		freq = { E = 0.6, A = 0.6, G = 0.45, Rn = 0.02, Cr = 0.12, LP = 0.06 },
		stats = { speed = { 70, 90 }, jump = { 40, 65 }, dressage = { 55, 75 }, stamina = { 85, 100 } } },
	orlov = { name = "Орловский рысак", weight = 1.2, size = 1.05, temper = 0.5,
		freq = { E = 0.85, A = 0.45, G = 0.45 },
		stats = { speed = { 70, 92 }, jump = { 40, 60 }, dressage = { 45, 70 }, stamina = { 70, 90 } } },
	friesian = { name = "Фризская", weight = 0.8, size = 1.1, temper = 0.3, feather = true, longMane = true, marksMaresOnly = true,
		freq = { E = 1, A = 0, G = 0.22, Cr = 0.18 },
		stats = { speed = { 50, 70 }, jump = { 40, 60 }, dressage = { 75, 95 }, stamina = { 60, 80 } } },
	haflinger = { name = "Хафлингер", weight = 1, size = 0.88, temper = 0.25,
		freq = { E = 0, A = 0.5, F = 0 },
		stats = { speed = { 45, 65 }, jump = { 45, 65 }, dressage = { 50, 70 }, stamina = { 70, 90 } } },
	appaloosa = { name = "Аппалуза", weight = 1, size = 0.97, temper = 0.5, alwaysSpots = true,
		freq = { E = 0.6, A = 0.5, Cr = 0.22, D = 0.1, G = 0.12, LP = 0.75, Rn = 0.04 },
		stats = { speed = { 60, 80 }, jump = { 50, 70 }, dressage = { 45, 70 }, stamina = { 70, 90 } } },
	paint = { name = "Пейнтхорс", weight = 1, size = 0.97, temper = 0.45,
		freq = { E = 0.55, A = 0.5, Cr = 0.08, D = 0.04, G = 0.03, TO = 0.5, Rn = 0.04 },
		stats = { speed = { 60, 82 }, jump = { 45, 70 }, dressage = { 45, 70 }, stamina = { 65, 85 } } },
	trakehner = { name = "Тракененская", weight = 1, size = 1.05, temper = 0.55,
		freq = { E = 0.75, A = 0.6, G = 0.1 },
		stats = { speed = { 60, 80 }, jump = { 70, 95 }, dressage = { 70, 92 }, stamina = { 60, 80 } } },
	budyonny = { name = "Будённовская", weight = 1, size = 1.03, temper = 0.5, sheen = true,
		freq = { E = 0.15, A = 0.6, F = 0.8 },
		stats = { speed = { 65, 85 }, jump = { 65, 88 }, dressage = { 55, 80 }, stamina = { 70, 90 } } },
	fjord = { name = "Норвежский фьорд", weight = 0.8, size = 0.85, temper = 0.2, fjordMane = true,
		freq = { E = 0.55, A = 0.8, Cr = 0.18, D = 1 },
		stats = { speed = { 40, 60 }, jump = { 40, 60 }, dressage = { 45, 65 }, stamina = { 75, 95 } } },
	shetland = { name = "Шетлендский пони", weight = 0.9, size = 0.62, temper = 0.45,
		freq = { E = 0.65, A = 0.5, Cr = 0.06, D = 0.04, G = 0.06, TO = 0.25, Rn = 0.06, Z = 0.2 },
		stats = { speed = { 30, 50 }, jump = { 40, 65 }, dressage = { 35, 55 }, stamina = { 60, 85 } } },
	przewalski = { name = "Лошадь Пржевальского", weight = 0, home = "steppe", hw = 1, size = 0.86, temper = 0.85, przMane = true,
		freq = { E = 1, A = 1, D = 1, F = 1 },
		stats = { speed = { 60, 82 }, jump = { 40, 62 }, dressage = { 30, 50 }, stamina = { 85, 100 } } },
	fedorov = { name = "Федоровская", weight = 0.9, size = 1.0, temper = 0.4,
		freq = { E = 0.15, A = 0.5, Cr = 0.35, G = 0.3, F = 0.5 },
		stats = { speed = { 60, 82 }, jump = { 55, 80 }, dressage = { 60, 85 }, stamina = { 65, 88 } } },
	andalusian = { name = "Андалузская", weight = 1, size = 1.02, temper = 0.45, longMane = true, coats = { pearl = 0.1 },
		freq = { E = 0.65, A = 0.3, G = 0.5, Cr = 0.12, LP = 0.08 },
		stats = { speed = { 58, 80 }, jump = { 55, 80 }, dressage = { 78, 98 }, stamina = { 65, 88 } } },
	-- волшебные породы
	pegasus = { name = "Пегас", weight = 0, home = "magic", hw = 1, size = 1.0, temper = 0.75, magic = { wings = "pegasus" },
		freq = { E = 0.5, A = 0.5, Cr = 0.2, G = 0.55 },
		stats = { speed = { 80, 98 }, jump = { 70, 95 }, dressage = { 60, 85 }, stamina = { 75, 95 } } },
	unicorn = { name = "Единорог", weight = 0, home = "magic", hw = 1, size = 1.0, temper = 0.7, magic = { horn = true }, sheen = true,
		freq = { E = 0.5, A = 0.5, Cr = 0.3, G = 0.7 },
		stats = { speed = { 70, 92 }, jump = { 60, 85 }, dressage = { 80, 98 }, stamina = { 75, 95 } } },
	firehorse = { name = "Огненная лошадка", weight = 0, home = "magic", hw = 1, size = 0.97, temper = 0.85, magic = { mane = "fire", elem = "fire" },
		freq = { E = 0.35, A = 0.4, F = 0.5 },
		stats = { speed = { 85, 99 }, jump = { 60, 85 }, dressage = { 50, 75 }, stamina = { 80, 98 } } },
	icehorse = { name = "Ледяная лошадка", weight = 0, home = "magic", hw = 1, size = 0.97, temper = 0.6, magic = { mane = "ice", elem = "ice" },
		freq = { E = 0.85, A = 0.2, G = 0.45, Z = 0.45, Cr = 0.15 },
		stats = { speed = { 70, 90 }, jump = { 65, 90 }, dressage = { 70, 92 }, stamina = { 85, 99 } } },
	crystalhorse = { name = "Кристальная лошадка", weight = 0, home = "magic", hw = 0.8, size = 0.95, temper = 0.6, magic = { elem = "crystal" }, sheen = true,
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 70, 92 }, jump = { 70, 95 }, dressage = { 75, 98 }, stamina = { 65, 88 } } },
	waterhorse = { name = "Водяная лошадка", weight = 0, home = "magic", hw = 0.7, size = 0.98, temper = 0.45, magic = { elem = "water" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 70, 90 }, jump = { 55, 80 }, dressage = { 75, 95 }, stamina = { 80, 99 } } },
	rainbowhorse = { name = "Радужная лошадка", weight = 0, home = "magic", hw = 0.5, size = 0.95, temper = 0.55, magic = { elem = "rainbow" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 75, 95 }, jump = { 70, 95 }, dressage = { 75, 95 }, stamina = { 70, 92 } } },
	sunhorse = { name = "Солнечная лошадка", weight = 0, home = "magic", hw = 0.7, size = 1.0, temper = 0.7, magic = { elem = "sun" },
		freq = { E = 0.3, A = 0.5 },
		stats = { speed = { 80, 98 }, jump = { 60, 85 }, dressage = { 60, 85 }, stamina = { 80, 98 } } },
	mushroomhorse = { name = "Грибная лошадка", weight = 0, home = "magic", hw = 0.9, size = 0.9, temper = 0.3, magic = { elem = "mushroom" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 50, 72 }, jump = { 55, 80 }, dressage = { 65, 88 }, stamina = { 75, 95 } } },
	sandhorse = { name = "Песочная лошадка", weight = 0, home = "desert", hw = 1, size = 0.95, temper = 0.6, magic = { elem = "sand" },
		freq = { E = 0.4, A = 0.6 },
		stats = { speed = { 75, 95 }, jump = { 55, 78 }, dressage = { 50, 75 }, stamina = { 85, 100 } } },
	stonehorse = { name = "Каменная лошадка", weight = 0, home = "cave", hw = 0.7, size = 1.08, temper = 0.25, magic = { elem = "stone" },
		freq = { E = 0.6, A = 0.4 },
		stats = { speed = { 40, 62 }, jump = { 45, 68 }, dressage = { 50, 72 }, stamina = { 90, 100 } } },
	leafhorse = { name = "Лиственная лошадка", weight = 0, home = "forest", hw = 1, size = 0.96, temper = 0.5, magic = { elem = "leaf" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 65, 88 }, jump = { 70, 92 }, dressage = { 60, 85 }, stamina = { 70, 90 } } },
	damphorse = { name = "Сырая лошадка", weight = 0, home = "forest", hw = 1, size = 0.97, temper = 0.35, magic = { elem = "damp" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 55, 78 }, jump = { 50, 75 }, dressage = { 70, 92 }, stamina = { 80, 98 } } },
	cloudhorse = { name = "Облачная лошадка", weight = 0, home = "sky", hw = 1, size = 0.93, temper = 0.55, magic = { cloud = true },
		freq = { E = 0.5, A = 0.5, G = 0.8, Cr = 0.2 },
		stats = { speed = { 75, 95 }, jump = { 70, 95 }, dressage = { 70, 92 }, stamina = { 70, 92 } } },
	skeleton = { name = "Лошадь-скелет", weight = 0, home = "cave", hw = 1, size = 1.0, temper = 0.55, magic = { skeleton = true },
		freq = {},
		stats = { speed = { 65, 88 }, jump = { 60, 85 }, dressage = { 45, 70 }, stamina = { 90, 100 } } },
	butterflyhorse = { name = "Лошадь-бабочка", weight = 0, home = "island", hw = 1, size = 0.9, temper = 0.55, magic = { wings = "butterfly" },
		freq = { E = 0.4, A = 0.5, Cr = 0.3, G = 0.3, TO = 0.25 },
		stats = { speed = { 65, 88 }, jump = { 60, 85 }, dressage = { 75, 95 }, stamina = { 60, 85 } } },
	dragonhorse = { name = "Драконья лошадь", weight = 0, home = "island", hw = 1, size = 1.1, temper = 0.85, magic = { wings = "dragon" },
		freq = { E = 0.8, A = 0.3, Z = 0.3 },
		stats = { speed = { 80, 99 }, jump = { 70, 92 }, dressage = { 50, 75 }, stamina = { 85, 100 } } },
	ravenhorse = { name = "Лошадь с крыльями ворона", weight = 0, home = "island", hw = 1, size = 1.0, temper = 0.7, magic = { wings = "raven" },
		freq = { E = 0.7, A = 0.5, G = 0.25, Rn = 0.2 },
		stats = { speed = { 78, 96 }, jump = { 70, 90 }, dressage = { 60, 85 }, stamina = { 75, 95 } } },
	dragonflyhorse = { name = "Лошадь-стрекоза", weight = 0, home = "island", hw = 1, size = 0.88, temper = 0.75, magic = { wings = "dragonfly" },
		freq = { E = 0.5, A = 0.4, D = 0.4, Cr = 0.15, Z = 0.2 },
		stats = { speed = { 85, 99 }, jump = { 60, 85 }, dressage = { 55, 80 }, stamina = { 60, 85 } } },
	beehorse = { name = "Лошадь-пчёлка", weight = 0, home = "island", hw = 1, size = 0.75, temper = 0.4, magic = { wings = "bee" },
		freq = { E = 0.25, A = 0.6, Cr = 0.45, F = 0.5 },
		stats = { speed = { 55, 78 }, jump = { 55, 80 }, dressage = { 60, 85 }, stamina = { 70, 92 } } },
	bonehorse = { name = "Костяная лошадь", weight = 0, home = "island", hw = 1, size = 1.02, temper = 0.6, magic = { bones = true },
		freq = { E = 0.7, A = 0.25, G = 0.1 },
		stats = { speed = { 70, 92 }, jump = { 65, 88 }, dressage = { 50, 75 }, stamina = { 85, 100 } } },
	scalehorse = { name = "Чешуйчатая драконья лошадь", weight = 0, home = "dragonrock", hw = 1, size = 1.08, temper = 0.8, magic = { wings = "dragon", scales = "random", dhorns = true },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 80, 99 }, jump = { 70, 95 }, dressage = { 50, 78 }, stamina = { 85, 100 } } },
	pinkdragon = { name = "Розовый дракон", weight = 0, home = "magic", hw = 0, size = 1.1, temper = 0.75, magic = { wings = "dragon", scales = "#ff8cc6", dhorns = true, dragonEyes = "#ff4fa3" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 88, 99 }, jump = { 85, 99 }, dressage = { 75, 95 }, stamina = { 88, 100 } } },
	zebra = { name = "Зебра", weight = 0, home = "desert", hw = 1, size = 0.92, temper = 0.8, przMane = true, magic = { zebra = "random" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 75, 95 }, jump = { 55, 78 }, dressage = { 35, 60 }, stamina = { 80, 98 } } },
	glowhorse = { name = "Светящаяся лошадь", weight = 0, home = "grotto", hw = 1, size = 0.98, temper = 0.6, magic = { glow = "random" },
		freq = { E = 1, A = 0 },
		stats = { speed = { 70, 92 }, jump = { 65, 90 }, dressage = { 65, 90 }, stamina = { 70, 92 } } },
	foxhorse = { name = "Лисья лошадь", weight = 0, home = "foxwood", hw = 1, size = 0.9, temper = 0.65, magic = { fox = "random" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 72, 94 }, jump = { 70, 92 }, dressage = { 55, 80 }, stamina = { 65, 88 } } },
	holidayhorse = { name = "Праздничная лошадь", weight = 0, home = "holiday", hw = 0, size = 0.98, temper = 0.4, magic = { holiday = "random" },
		freq = { E = 0.5, A = 0.5 },
		stats = { speed = { 65, 88 }, jump = { 65, 88 }, dressage = { 65, 88 }, stamina = { 65, 88 } } },
	yakut = { name = "Якутская", weight = 0, home = "tundra", hw = 1, size = 0.86, temper = 0.3, longMane = true, feather = true,
		freq = { E = 0.75, A = 0.6, D = 0.4, G = 0.4, Cr = 0.05 },
		stats = { speed = { 45, 65 }, jump = { 40, 60 }, dressage = { 40, 60 }, stamina = { 90, 100 } } },
	mix = { name = "Помесь", weight = 0, size = 1, temper = 0.5,
		freq = {},
		stats = { speed = { 45, 75 }, jump = { 45, 75 }, dressage = { 45, 75 }, stamina = { 45, 75 } } },
}
-- стабильный порядок пород (для взвешенного выбора)
Genetics.BREED_ORDER = { "akhal", "arab", "orlov", "friesian", "haflinger", "appaloosa", "paint", "trakehner", "budyonny", "fjord",
	"shetland", "przewalski", "fedorov", "andalusian", "pegasus", "unicorn", "firehorse", "icehorse", "crystalhorse", "waterhorse",
	"rainbowhorse", "sunhorse", "mushroomhorse", "sandhorse", "stonehorse", "leafhorse", "damphorse", "cloudhorse", "skeleton",
	"butterflyhorse", "dragonhorse", "ravenhorse", "dragonflyhorse", "beehorse", "bonehorse", "scalehorse", "pinkdragon", "zebra",
	"glowhorse", "foxhorse", "holidayhorse", "yakut", "mix" }

Genetics.mix = mix

-- генотип: g[locus] = { bool, bool }
function Genetics.randomGenotype(breed)
	local B = Genetics.BREEDS[breed] or Genetics.BREEDS.mix
	local g = {}
	for _, l in ipairs(Genetics.LOCI) do
		local f = B.freq[l]
		if f == nil then f = DEFAULT_FREQ[l] end
		g[l] = { math.random() < f, math.random() < f }
	end
	return g
end

-- каждый родитель передаёт жеребёнку один случайный аллель из пары
function Genetics.inherit(mother, father)
	local g = {}
	for _, l in ipairs(Genetics.LOCI) do
		g[l] = { mother[l][math.random(1, 2)], father[l][math.random(1, 2)] }
	end
	return g
end

local function has(g, l) return g[l][1] or g[l][2] end
local function cnt(g, l) return (g[l][1] and 1 or 0) + (g[l][2] and 1 or 0) end

-- текст вида «Ee aa Cr/n»
function Genetics.genotypeText(g)
	local parts = {}
	for _, l in ipairs(Genetics.LOCI) do
		local show
		if l == "E" or l == "A" then show = true
		elseif l == "F" then show = not (g.F[1] and g.F[2])
		else show = has(g, l) end
		if show then
			local s = SYMBOLS[l]
			local a1, a2 = g[l][1], g[l][2]
			if a2 and not a1 then a1, a2 = a2, a1 end
			local t1, t2 = a1 and s[1] or s[2], a2 and s[1] or s[2]
			if l == "E" or l == "A" or l == "G" or l == "F" then
				table.insert(parts, t1 .. t2)
			else
				table.insert(parts, t1 .. "/" .. t2)
			end
		end
	end
	return table.concat(parts, " ")
end

-- фенотип: как лошадь выглядит и как называется её окрас
function Genetics.phenotype(g, age)
	local base = (not has(g, "E")) and "ch" or (has(g, "A") and "bay" or "bl")
	local cr = cnt(g, "Cr")
	local dun = has(g, "D")
	local silver = has(g, "Z") and base ~= "ch" and cr < 2
	local flaxen = base == "ch" and not has(g, "F")
	local body, mane, legs, word
	local suffix, rarity, stripe, pinkSkin = "", 1, nil, false

	if cr == 2 then
		word = "изабелловая"
		body = base == "ch" and "#f3e9d2" or base == "bay" and "#eedcbc" or "#e6d8be"
		mane = base == "bay" and "#d9bb98" or base == "bl" and "#cdb89c" or "#f7f1e3"
		legs = base == "ch" and body or mix(body, mane, 0.6)
		rarity = 1.5
		pinkSkin = true
	elseif cr == 1 then
		if base == "ch" then word, body, mane, legs = "соловая", "#ddae55", "#f6eed8", "#ddae55"
		elseif base == "bay" then word, body, mane, legs = "буланая", "#d4aa68", "#231a14", "#2a1f18"
		else word, body, mane, legs = "дымчато-вороная", "#3f342c", "#1d1816", "#1d1816" end
		rarity = 1.3
	else
		if base == "ch" then word, body, mane, legs = "рыжая", "#a3532b", flaxen and "#efdcaa" or "#87401f", "#a3532b"
		elseif base == "bay" then word, body, mane, legs = "гнедая", "#7b4423", "#1e1611", "#1e1611"
		else word, body, mane, legs = "вороная", "#232020", "#151313", "#151313"; rarity = 1.1 end
	end

	if dun and cr < 2 then
		stripe = base == "ch" and "#7a3c1c" or "#2a211b"
		if cr == 0 then
			if base == "ch" then word, body, mane, legs = "рыже-саврасая", "#cc9562", flaxen and "#efdcaa" or "#8b4a26", "#a8703f"
			elseif base == "bay" then word, body, legs = "саврасая", "#c6a26b", "#2a211b"
			else word, body, legs = "мышастая", "#8b8174", "#2c2622"; rarity = 1.35 end
		else
			suffix = " с ремнём"
			body = mix(body, "#f2e2c0", 0.25)
		end
		rarity *= 1.15
	end

	if silver then
		if cr == 1 then
			word = base == "bl" and "серебристо-дымчатая" or "серебристо-буланая"
		else
			word = "серебристо-" .. word
		end
		if base == "bl" then
			body = mix(body, "#6e5240", 0.85)
			legs = mix(legs, "#5a4535", 0.7)
		else
			legs = mix(legs, "#6a4a35", 0.7)
		end
		mane = "#ece3d1"
		rarity *= 1.4
	end

	if flaxen and cr == 0 and not dun then
		suffix = " со светлой гривой"
		rarity *= 1.1
	end

	local greyLevel, dapple = 0, false
	if has(g, "G") then
		greyLevel = math.clamp((age - 0.5) / 4, 0, 1)
		body = mix(body, "#c9c9c7", greyLevel * 0.95)
		mane = mix(mane, "#e2e2e0", greyLevel)
		legs = mix(legs, "#a6a6a4", greyLevel * 0.9)
		dapple = greyLevel > 0.3 and greyLevel < 0.97
		if greyLevel >= 0.6 then
			word = "серая"
			suffix = greyLevel < 0.97 and " в яблоках" or ""
		else
			suffix ..= greyLevel > 0 and " (седеет)" or " (поседеет)"
		end
		rarity *= 1.05
	end

	local roan, tob, leo = has(g, "Rn"), has(g, "TO"), has(g, "LP")
	local patterns = {}
	if tob then table.insert(patterns, "пегая"); rarity *= 1.3 end
	if leo then table.insert(patterns, "чубарая"); rarity *= 1.5 end
	if roan then table.insert(patterns, "чалая"); rarity *= 1.2 end

	local name
	if #patterns > 0 then
		local w = word
		if string.sub(w, -4) == "ая" then w = string.sub(w, 1, -5) .. "о" end
		name = w .. "-" .. patterns[1]
		if #patterns > 1 then
			name ..= ", " .. table.concat(patterns, ", ", 2)
		end
		name ..= suffix
	else
		name = word .. suffix
	end

	return {
		name = name, body = body, mane = mane, legs = legs, stripe = stripe, roan = roan, tob = tob, leo = leo,
		greyLevel = greyLevel, dapple = dapple, pinkSkin = pinkSkin, rarity = rarity,
	}
end

-- вероятные окрасы жеребёнка (Монте-Карло)
function Genetics.predict(gm, gf, n)
	n = n or 800
	local counts, order = {}, {}
	for _ = 1, n do
		local name = Genetics.phenotype(Genetics.inherit(gm, gf), 6).name
		if not counts[name] then table.insert(order, name) end
		counts[name] = (counts[name] or 0) + 1
	end
	local list = {}
	for _, name in ipairs(order) do
		local pct = math.floor(counts[name] / n * 100 + 0.5)
		if pct > 0 then table.insert(list, { name = name, pct = pct }) end
	end
	table.sort(list, function(a, b) return a.pct > b.pct end)
	while #list > 7 do table.remove(list) end
	return list
end

return Genetics
