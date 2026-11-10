--[[
	Жители (NPC), разговоры и задания (перенос js/quests.js).
	Функции прогресса работают с профилем игрока (P = сохранение).
]]
local World = require(script.Parent.World)
local Items = require(script.Parent.Items)

local Q = {}
local OX, OY = World.OX, World.OY

Q.NPCS = {
	{ id = "galya", name = "Бабушка Галя", x = OX + 1520, y = OY + 2740, role = "любит лошадей", house = "Дом бабушки Гали",
		look = { shirt = "#c2255c", pants = "#5c3d2e", hair = "#d0d0d0", hat = "scarf", hatColor = "#f08c00" },
		hello = { "Здравствуй, внученька! Лошадки — это радость.", "Морковка для лошадки — лучшее угощение!", "Чистая лошадка — весёлая лошадка." },
		tips = { "Щётку и подковы продают в повозке «Корм и амуниция».", "Тыквы иногда находят в земле с металлоискателем." } },
	{ id = "misha", name = "Тренер Дядя Миша", x = OX + 1235, y = OY + 578, role = "тренер", -- у калитки левады, а не в заборе
		look = { shirt = "#1c7ed6", pants = "#e9e0cc", hair = "#5a3d2b", hat = "cap", hatColor = "#212529", beard = true },
		hello = { "Пятки вниз, спина прямая!", "Хорошая всадница сначала заботится о лошади.", "Тренируйся каждый день — и будет результат." },
		tips = { "В манеже — выездка и кавалетти, ниже — конкурное поле.", "Скачки начинаются у клетчатого столба у входа в поле." } },
	{ id = "petr", name = "Кузнец Пётр", x = OX + 2250, y = OY + 2830, role = "кузнец", house = "Кузница",
		look = { shirt = "#495057", pants = "#343a40", hair = "#2b2b2b", hat = "none", apron = "#6b4423", beard = true },
		hello = { "Подковать лошадку? Это я мигом!", "В земле много старых подков — я их собираю.", "Металлоискатель пищит всё чаще, когда клад близко." },
		tips = { "Металлоискатель продаётся в повозке «Корм и амуниция». Включай его кнопкой 📡 или клавишей M.", "Когда сигнал на максимуме — копай!" } },
	{ id = "vanya", name = "Лесник Ваня", x = OX + 1600, y = OY + 3560, role = "лесник", house = "Сторожка лесника",
		look = { shirt = "#2b8a3e", pants = "#5c4033", hair = "#a0522d", hat = "hat", hatColor = "#5c7a3a" },
		hello = { "В лесу тихо... слышишь, как шуршат зайчики?", "Грибы собирай пешком — с лошади не дотянешься.", "Мухоморы не трогай, они ядовитые!" },
		tips = { "За лесом на востоке есть Грибное королевство. Говорят, там живут волшебные лошадки!" } },
	{ id = "lira", name = "Фея Лира", x = OX + 6750, y = OY + 3250, role = "фея", fairy = true,
		look = { shirt = "#e599f7", pants = "#d0bfff", hair = "#ffd43b", hat = "crown", hatColor = "#fff3bf" },
		hello = { "Добро пожаловать в Грибное королевство! ✨", "Мои лошадки умеют летать, а у кого-то грива горит огнём!", "Пегасы пугливые — подкрадывайся тихо." },
		tips = { "На пегасе можно взлететь: кнопка 🕊️ или клавиша V.", "Волшебные черты передаются жеребятам.", "Волшебное семечко вырастит цветок с волшебной пыльцой." } },
	{ id = "graf", name = "Призрак графа Ветрова", x = OX + 7000, y = OY + 900, role = "привидение", ghost = true,
		look = { shirt = "#dbe4ff", pants = "#dbe4ff", hair = "#ffffff", hat = "tophat", hatColor = "#c5d0f5" },
		hello = { "Уууу... Не бойся, я добрый призрак.", "Сто лет я ищу свой сундук... Он где-то в глубине пещеры.", "Мои лошадки-скелеты гуляют здесь. Они совсем не злые!" },
		tips = { "Пещера идёт змейкой: сначала на север, потом на юг, потом снова на север.", "Привидения пугают, но ничего плохого не делают." } },
	{ id = "lola", name = "Стилистка Лола", x = OX + 2850, y = OY + 2800, role = "стилист", shop = true, house = "Салон «Грива»",
		look = { shirt = "#f783ac", pants = "#212529", hair = "#9775fa", hat = "none" },
		hello = { "Какая грива! Давай сделаем ей причёску?", "Косички, бантики, ирокез — что пожелаешь!", "Радужная грива — самая модная в этом сезоне!" },
		tips = { "Причёску можно поменять в конюшне: открой лошадь и нажми «💇 Грива».", "Краски для гривы есть у меня и в повозке." } },
	{ id = "olya", name = "Рыбачка Оля", x = OX + 4250, y = OY + 1150, role = "рыбачка",
		look = { shirt = "#ffa94d", pants = "#1864ab", hair = "#e8590c", hat = "hat", hatColor = "#fab005" },
		hello = { "Тише... рыба клюёт!", "Большое озеро — самое красивое место на свете.", "За озером горы, а в горах — пещера." },
		tips = { "Вход в пещеру — с западной стороны гор, по дороге от озера." } },
	{ id = "marina", name = "Капитан Марина", x = World.PIER.x - 130, y = World.PIER.y + 100, role = "капитан лодки",
		look = { shirt = "#ffffff", pants = "#1864ab", hair = "#f08c00", hat = "cap", hatColor = "#1c3d6e" },
		hello = { "Свистать всех наверх! Куда поплывём?", "На островах живут лошади с самыми удивительными крыльями!", "Каждые пять минут на островах появляются новые дикие лошадки." },
		tips = { "Лодка у причала: подойди и нажми «⛵ Лодка».", "На каждом острове есть своя конюшня — можно оставить там лошадь.", "Драконьи лошади очень горячие — лови их верхом." } },
	{ id = "zara", name = "Караванщица Зара", x = OX + 1850, y = OY + 7250, role = "караванщица",
		look = { shirt = "#f4a261", pants = "#e9c46a", hair = "#2b2b2b", hat = "scarf", hatColor = "#e76f51" },
		hello = { "В пустыне днём жарко, а ночью звёзды ярче всего!", "Ахалтекинцы — потомки древних коней пустыни. Их шерсть блестит золотом.", "У оазиса растут пальмы — там можно передохнуть." },
		tips = { "Оазис — в самом сердце пустыни, иди по дороге на юг от леса.", "Арабские лошади очень выносливые." } },
	{ id = "aita", name = "Северянка Айта", x = OX + 7400, y = OY + 6950, role = "жительница тундры",
		look = { shirt = "#4361ee", pants = "#ffffff", hair = "#1b1b1b", hat = "hat", hatColor = "#e63946" },
		hello = { "Брр! В тундре всегда снег, но якутские лошадки не мёрзнут.", "У якутских лошадей густая шерсть и длинная грива — настоящие шубки!", "Ледяное озеро замёрзло, по льду ходить нельзя." },
		tips = { "Скалы со снегом высокие — обходи их.", "Ледяные лошадки иногда забредают сюда из Грибного королевства." } },
}

-- жители у своих домов стоят перед дверью (дома стоят у дороги и смотрят на неё)
-- цвет точки на большой карте у каждого жителя свой
local DOT = { galya = "#f783ac", misha = "#ffd43b", petr = "#868e96", vanya = "#40c057", lira = "#cc5de8", graf = "#dbe4ff",
	lola = "#ff6b6b", olya = "#ff922b", marina = "#4dabf7", zara = "#e9c46a", aita = "#ffffff" }
local DOT_NAME = { galya = "розовая", misha = "жёлтая", petr = "серая", vanya = "зелёная", lira = "фиолетовая", graf = "голубая",
	lola = "красная", olya = "оранжевая", marina = "синяя", zara = "песочная", aita = "белая" }
for _, n in ipairs(Q.NPCS) do
	n.dot = DOT[n.id] or "#ffffff"
	n.dotName = DOT_NAME[n.id] or ""
	if n.house then
		local hh = World.houseByName(n.house)
		if hh then
			local x, y = World.houseFront(hh, 60)
			n.x, n.y = x, y
			local cx, cy = hh.x + hh.w / 2, hh.y + hh.h / 2
			n.face = math.atan2(cx - x, cy - y) -- угол поворота человечка: смотрит от двери на улицу
		end
	end
end

-- goal: { stat, n } — счётчик вырос на n; { flag } — флаг; { item, n } — отдать вещи; { islands } — побывать на островах
Q.QUESTS = {
	{ id = "m1", npc = "misha", title = "Первая лошадь", text = "Поймай в поле лошадь и приведи её в конюшню.", goal = { stat = "caught", n = 1 }, reward = { money = 40, carrot = 5 } },
	{ id = "m2", npc = "misha", title = "Выездка", text = "Проедь тест по выездке на 60% или больше.", goal = { stat = "dres60", n = 1 }, reward = { money = 60 } },
	{ id = "m3", npc = "misha", title = "Чистые жерди", text = "Пройди кавалетти без единой ошибки.", goal = { stat = "cavClean", n = 1 }, reward = { money = 60, oats = 5 } },
	{ id = "m4", npc = "misha", title = "Чистый конкур", text = "Пройди маршрут конкура 80 см или выше без штрафных очков.", goal = { stat = "jump80", n = 1 }, reward = { money = 100 } },
	{ id = "m5", npc = "misha", title = "Чемпионка", text = "Выиграй скачки.", goal = { stat = "wins", n = 1 }, reward = { money = 150, dye_gold = 1 } },

	{ id = "g1", npc = "galya", title = "Чистая лошадка", text = "Почисти лошадь щёткой.", goal = { stat = "brushed", n = 1 }, reward = { money = 30, carrot = 5 } },
	{ id = "g2", npc = "galya", title = "Банный день", text = "Помой лошадь.", goal = { stat = "washed", n = 1 }, reward = { money = 50, apple = 5 } },
	{ id = "g3", npc = "galya", title = "Новые подковки", text = "Подкуй лошадь.", goal = { stat = "shod", n = 1 }, reward = { money = 60, sugar = 5 } },
	{ id = "g4", npc = "galya", title = "Тыква к празднику", text = "Принеси мне тыкву — её можно найти в земле с металлоискателем.", goal = { item = "pumpkin", n = 1 }, reward = { money = 80, pollen = 1 } },

	{ id = "p1", npc = "petr", title = "Первый клад", text = "Найди клад металлоискателем.", goal = { stat = "treasures", n = 1 }, reward = { money = 40 } },
	{ id = "p2", npc = "petr", title = "Старые подковы", text = "Принеси мне 2 старые подковы.", goal = { item = "oldShoe", n = 2 }, reward = { money = 90, dye_blue = 1 } },
	{ id = "p3", npc = "petr", title = "Кладоискательница", text = "Найди ещё 5 кладов.", goal = { stat = "treasures", n = 5 }, reward = { money = 150 } },
	{ id = "p4", npc = "petr", title = "Золотая подкова", text = "Принеси золотую подкову — их находят в земле или в сундуке.", goal = { item = "goldShoe", n = 1 }, reward = { money = 300 } },

	{ id = "v1", npc = "vanya", title = "Прогулка по лесу", text = "Зайди в лес к югу от деревни.", goal = { flag = "visit_forest" }, reward = { money = 20 } },
	{ id = "v2", npc = "vanya", title = "Грибная корзинка", text = "Собери 8 грибов (пешком, мухоморы не бери!).", goal = { stat = "mushrooms", n = 8 }, reward = { money = 50, apple = 4 } },
	{ id = "v3", npc = "vanya", title = "Тайная тропа", text = "Найди Грибное королевство на востоке за лесом.", goal = { flag = "visit_mushroom" }, reward = { money = 60 } },
	{ id = "v4", npc = "vanya", title = "Друзья леса", text = "Поймай 3 зайчиков.", goal = { stat = "bunnies", n = 3 }, reward = { money = 60, sugar = 5 } },

	{ id = "f1", npc = "lira", title = "Волшебная лошадка", text = "Поймай волшебную лошадку: пегаса, единорога, огненную или ледяную.", goal = { stat = "magicCaught", n = 1 }, reward = { money = 100, dye_rainbow = 1 } },
	{ id = "f2", npc = "lira", title = "Небесная прогулка", text = "Пролети на пегасе 30 секунд.", goal = { stat = "flyTime", n = 30 }, reward = { money = 120, pollen = 1 } },
	{ id = "f3", npc = "lira", title = "Волшебный жеребёнок", text = "Вырасти жеребёнка с волшебными чертами.", goal = { stat = "magicFoals", n = 1 }, reward = { money = 200, dye_gold = 1 } },
	{ id = "f4", npc = "lira", title = "Пыльца для фей", text = "Принеси 2 щепотки волшебной пыльцы.", goal = { item = "pollen", n = 2 }, reward = { money = 150, dye_rainbow = 1 } },

	{ id = "c1", npc = "graf", title = "Сундук графа", text = "Найди мой сундук в самой глубине пещеры.", goal = { flag = "chest_opened" }, reward = { money = 100 } },
	{ id = "c2", npc = "graf", title = "Костяная лошадка", text = "Поймай лошадь-скелет.", goal = { stat = "skeletonCaught", n = 1 }, reward = { money = 150 } },

	{ id = "l1", npc = "lola", title = "Новая причёска", text = "Сделай лошади новую причёску (в конюшне — «💇 Грива»).", goal = { stat = "maneStyled", n = 1 }, reward = { money = 30, dye_pink = 1 } },
	{ id = "l2", npc = "lola", title = "Яркие краски", text = "Покрась гриву лошади краской.", goal = { stat = "maneDyed", n = 1 }, reward = { money = 50, dye_purple = 1 } },

	{ id = "o1", npc = "olya", title = "Большое озеро", text = "Объедь Большое озеро: побывай у его восточного берега.", goal = { flag = "visit_lake_east" }, reward = { money = 40 } },
	{ id = "s1", npc = "marina", title = "Морское путешествие", text = "Сплавай на лодке на любой остров.", goal = { islands = 1 }, reward = { money = 50 } },
	{ id = "s2", npc = "marina", title = "Все три острова", text = "Побывай на всех трёх островах.", goal = { islands = 3 }, reward = { money = 120, dye_blue = 1 } },
	{ id = "s3", npc = "marina", title = "Лошадь-бабочка", text = "Поймай лошадь с крыльями бабочки на Острове бабочек.", goal = { stat = "wing_butterfly", n = 1 }, reward = { money = 150, dye_pink = 1 } },
	{ id = "s4", npc = "marina", title = "Драконья лошадь", text = "Поймай драконью лошадь на Драконьем острове.", goal = { stat = "wing_dragon", n = 1 }, reward = { money = 200, dye_gold = 1 } },
	{ id = "s5", npc = "marina", title = "Стрекоза и пчёлка", text = "Поймай лошадь-стрекозу и лошадь-пчёлку.", goal = { stat = "wingSmall", n = 2 }, reward = { money = 180, dye_mint = 1 } },
	{ id = "s6", npc = "marina", title = "Крылья ворона", text = "Поймай лошадь с крыльями ворона.", goal = { stat = "wing_raven", n = 1 }, reward = { money = 160 } },

	{ id = "z1", npc = "zara", title = "Пески", text = "Дойди до пустыни на юге.", goal = { flag = "visit_desert" }, reward = { money = 40 } },
	{ id = "z2", npc = "zara", title = "Оазис", text = "Найди оазис с пальмами в сердце пустыни.", goal = { flag = "visit_oasis" }, reward = { money = 60, apple = 5 } },
	{ id = "z3", npc = "zara", title = "Конь пустыни", text = "Поймай ахалтекинца или арабскую лошадь в пустыне.", goal = { stat = "caught_desert", n = 1 }, reward = { money = 130 } },

	{ id = "a1", npc = "aita", title = "Северная гостья", text = "Доберись до тундры на юго-востоке.", goal = { flag = "visit_tundra" }, reward = { money = 40 } },
	{ id = "a2", npc = "aita", title = "Мохнатая лошадка", text = "Поймай якутскую лошадь в тундре.", goal = { stat = "caught_tundra", n = 1 }, reward = { money = 130, oats = 5 } },
	{ id = "a3", npc = "aita", title = "Сквозь чащу", text = "Пройди дремучий лес между пустыней и тундрой.", goal = { flag = "visit_deepforest" }, reward = { money = 50 } },

	{ id = "o2", npc = "olya", title = "Пещера в горах", text = "Найди вход в пещеру и загляни внутрь.", goal = { flag = "visit_cave" }, reward = { money = 60 } },
}

-- задания с доски в деревне — повторяются
Q.BOARD = {
	{ title = "Ловец лошадей", text = "Поймай 2 лошади.", goal = { stat = "caught", n = 2 }, reward = { money = 70 } },
	{ title = "Чистюля", text = "Почисти лошадей щёткой 3 раза.", goal = { stat = "brushed", n = 3 }, reward = { money = 60 } },
	{ title = "Охотник за кладами", text = "Найди 2 клада.", goal = { stat = "treasures", n = 2 }, reward = { money = 80 } },
	{ title = "Быстрые копыта", text = "Займи место на пьедестале в скачках (1–3).", goal = { stat = "podiums", n = 1 }, reward = { money = 80 } },
	{ title = "Грибник", text = "Собери 6 грибов.", goal = { stat = "mushrooms", n = 6 }, reward = { money = 50 } },
	{ title = "Зайкин друг", text = "Поймай 2 зайчиков.", goal = { stat = "bunnies", n = 2 }, reward = { money = 50 } },
	{ title = "Артистка", text = "Покажи верхом 3 трюка.", goal = { stat = "tricks", n = 3 }, reward = { money = 50 } },
	{ title = "Прыгунья", text = "Пройди любой маршрут конкура.", goal = { stat = "jumpRounds", n = 1 }, reward = { money = 60 } },
}

function Q.byId(id)
	for _, q in ipairs(Q.QUESTS) do
		if q.id == id then return q end
	end
	return nil
end
function Q.npcById(id)
	for _, n in ipairs(Q.NPCS) do
		if n.id == id then return n end
	end
	return nil
end

local function stat(P, k) return P.stats[k] or 0 end

function Q.progress(P, q, st)
	local g = q.goal
	if g.flag then return { cur = P.flags[g.flag] and 1 or 0, need = 1 } end
	if g.islands then
		local n = 0
		for _, I in ipairs(World.ISLANDS) do
			if P.flags["visit_" .. I.id] then n += 1 end
		end
		return { cur = math.min(g.islands, n), need = g.islands }
	end
	if g.item then return { cur = math.min(g.n, P.inv[g.item] or 0), need = g.n } end
	return { cur = math.max(0, math.min(g.n, math.floor(stat(P, g.stat) - ((st and st.base) or 0)))), need = g.n }
end
function Q.complete(P, q, st)
	local p = Q.progress(P, q, st)
	return p.cur >= p.need
end

-- следующее задание у персонажа: активное или первое невзятое
function Q.current(P, npcId)
	for _, q in ipairs(Q.QUESTS) do
		if q.npc == npcId then
			local st = P.quests[q.id]
			if not st then return { q = q, st = nil } end
			if st.state == "active" then return { q = q, st = st } end
		end
	end
	return nil
end
function Q.marker(P, npcId)
	local c = Q.current(P, npcId)
	if not c then return "" end
	if not c.st then return "❗" end
	return Q.complete(P, c.q, c.st) and "❓" or "…"
end

function Q.rewardText(r)
	local parts = {}
	if r.money then table.insert(parts, r.money .. " 💰") end
	for k, v in pairs(r) do
		if k ~= "money" then
			table.insert(parts, Items.icon(k) .. " " .. Items.name(k) .. (v > 1 and (" ×" .. v) or ""))
		end
	end
	return table.concat(parts, ", ")
end

function Q.boardQuest(P)
	local b = P.board
	if not b then return nil end
	return { q = Q.BOARD[b.i], st = b.base ~= nil and { base = b.base, state = "active" } or nil }
end

function Q.journal(P)
	local list = {}
	for _, q in ipairs(Q.QUESTS) do
		local st = P.quests[q.id]
		if st and st.state == "active" then
			local npc = Q.npcById(q.npc)
			table.insert(list, { q = q, st = st, npcName = npc and npc.name or "", p = Q.progress(P, q, st), done = Q.complete(P, q, st) })
		end
	end
	local b = Q.boardQuest(P)
	if b and b.st then
		table.insert(list, { q = b.q, st = b.st, npcName = "Доска заданий", p = Q.progress(P, b.q, b.st), done = Q.complete(P, b.q, b.st), board = true })
	end
	return list
end
function Q.doneCount(P)
	local n = 0
	for _, s in pairs(P.quests) do
		if s.state == "done" then n += 1 end
	end
	return n
end

return Q
