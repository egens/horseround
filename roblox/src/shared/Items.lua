--[[
	Каталоги (перенос js/items.js и части js/game.js): вещи в рюкзаке, корм, амуниция,
	семена и урожай, постройки, причёски и краски, тесты выездки, действия лошадей.
]]
local Items = {}

-- всё, что лежит в рюкзаке; sell — цена у торговца, 0 — не продаётся
Items.ITEMS = {
	hay = { name = "Сено", icon = "🌾", sell = 2 },
	oats = { name = "Овёс", icon = "🥣", sell = 4 },
	carrot = { name = "Морковка", icon = "🥕", sell = 2 },
	apple = { name = "Яблоко", icon = "🍎", sell = 2 },
	sugar = { name = "Сахар", icon = "🍬", sell = 1 },
	pumpkin = { name = "Тыква", icon = "🎃", sell = 30 },
	sunflower = { name = "Подсолнух", icon = "🌻", sell = 18 },
	pollen = { name = "Волшебная пыльца", icon = "✨", sell = 40 },
	mushroom = { name = "Гриб", icon = "🍄", sell = 6 },
	glowshroom = { name = "Светящийся гриб", icon = "🔮", sell = 15 },
	seed_carrot = { name = "Семена моркови", icon = "🌱", sell = 0 },
	seed_oats = { name = "Семена овса", icon = "🌱", sell = 0 },
	seed_hay = { name = "Семена травы", icon = "🌱", sell = 0 },
	seed_pumpkin = { name = "Семена тыквы", icon = "🌱", sell = 0 },
	seed_sunflower = { name = "Семена подсолнуха", icon = "🌱", sell = 0 },
	seed_magic = { name = "Волшебное семечко", icon = "💫", sell = 0 },
	oldShoe = { name = "Старая подкова", icon = "🧲", sell = 20 },
	oldCoin = { name = "Старинная монета", icon = "🪙", sell = 40 },
	spoon = { name = "Серебряная ложка", icon = "🥄", sell = 30 },
	brooch = { name = "Брошь с камушком", icon = "💎", sell = 70 },
	bell = { name = "Колокольчик", icon = "🔔", sell = 25 },
	goldShoe = { name = "Золотая подкова", icon = "🏅", sell = 150 },
	crown = { name = "Корона графа", icon = "👑", sell = 300 },
	map = { name = "Карта сокровищ", icon = "🗺️", sell = 0 },
	milk = { name = "Бутылочка молока", icon = "🍼", sell = 2 },
	horseshoes = { name = "Новые подковы (4 шт.)", icon = "🔧", sell = 15 },
	dye_pink = { name = "Розовая краска для гривы", icon = "🩷", sell = 0 },
	dye_blue = { name = "Голубая краска для гривы", icon = "🩵", sell = 0 },
	dye_purple = { name = "Фиолетовая краска для гривы", icon = "💜", sell = 0 },
	dye_mint = { name = "Мятная краска для гривы", icon = "💚", sell = 0 },
	dye_gold = { name = "Золотая краска для гривы", icon = "💛", sell = 0 },
	dye_rainbow = { name = "Радужная краска для гривы", icon = "🌈", sell = 0 },
}
Items.ITEM_ORDER = { "hay", "oats", "carrot", "apple", "sugar", "milk", "pumpkin", "sunflower", "pollen", "mushroom", "glowshroom",
	"seed_carrot", "seed_oats", "seed_hay", "seed_pumpkin", "seed_sunflower", "seed_magic", "horseshoes",
	"oldShoe", "oldCoin", "spoon", "brooch", "bell", "goldShoe", "crown", "map",
	"dye_pink", "dye_blue", "dye_purple", "dye_mint", "dye_gold", "dye_rainbow" }

-- корм (цены в повозке)
Items.FOOD = {
	hay = { name = "Сено", icon = "🌾", price = 5, hunger = 25, energy = 5, mood = 2 },
	oats = { name = "Овёс", icon = "🥣", price = 9, hunger = 35, energy = 25, mood = 3 },
	carrot = { name = "Морковка", icon = "🥕", price = 3, hunger = 6, energy = 2, mood = 10, bait = true },
	apple = { name = "Яблоко", icon = "🍎", price = 3, hunger = 6, energy = 2, mood = 10, bait = true },
	sugar = { name = "Сахар", icon = "🍬", price = 2, hunger = 2, energy = 4, mood = 15 },
	milk = { name = "Молоко", icon = "🍼", price = 4, hunger = 30, energy = 10, mood = 15, foalOnly = true },
}
Items.FOOD_ORDER = { "hay", "oats", "carrot", "apple", "sugar", "milk" }

Items.COLORS = { "#c0392b", "#2e86de", "#e84393", "#8e44ad", "#27ae60", "#f39c12", "#222a3a", "#ffffff" }
Items.TACK = {
	saddle = { name = "Седло", icon = "🏇", price = 120, desc = "Без седла верхом не поедешь" },
	bridle = { name = "Уздечка", icon = "🪢", price = 60, desc = "Чтобы управлять лошадью" },
	brush = { name = "Щётка", icon = "🪮", price = 15, desc = "Чистая лошадь — довольная лошадь" },
	goodLasso = { name = "Ковбойское лассо", icon = "🤠", price = 90, desc = "Ловить лошадей намного легче" },
	pad = { name = "Вальтрап", icon = "🟥", price = 30, desc = "Цветная подкладка под седло", colors = true },
	helmet = { name = "Шлем", icon = "⛑️", price = 40, desc = "Безопасность прежде всего!", colors = true },
	boots = { name = "Ногавки", icon = "🧦", price = 35, desc = "Защищают ноги лошади", colors = true },
	detector = { name = "Металлоискатель", icon = "📡", price = 150, desc = "Пищит рядом с кладом. Включай клавишей M" },
}
Items.TACK_ORDER = { "saddle", "bridle", "brush", "goodLasso", "pad", "helmet", "boots", "detector" }

-- грядки: что сажаем, сколько растёт (секунды игры), что собираем
Items.CROPS = {
	carrot = { name = "Морковь", seed = "seed_carrot", time = 110, yield = { "carrot", 4 }, color = "#f76707", leaf = "#5c940d", seedPrice = 4 },
	oats = { name = "Овёс", seed = "seed_oats", time = 140, yield = { "oats", 4 }, color = "#e0c068", leaf = "#94a83a", seedPrice = 5 },
	hay = { name = "Луговая трава", seed = "seed_hay", time = 90, yield = { "hay", 5 }, color = "#8fbf4f", leaf = "#6b9a35", seedPrice = 3 },
	pumpkin = { name = "Тыква", seed = "seed_pumpkin", time = 200, yield = { "pumpkin", 1 }, color = "#f08c00", leaf = "#2f9e44", seedPrice = 10 },
	sunflower = { name = "Подсолнух", seed = "seed_sunflower", time = 160, yield = { "sunflower", 1 }, color = "#ffd43b", leaf = "#2b8a3e", seedPrice = 7 },
	magic = { name = "Волшебный цветок", seed = "seed_magic", time = 240, yield = { "pollen", 2 }, color = "#e599f7", leaf = "#3bc9db", seedPrice = 0 },
}
Items.CROP_ORDER = { "carrot", "oats", "hay", "pumpkin", "sunflower", "magic" }

-- постройки: размер в пикселях карты (1 px = 0.1 стада), цена, твёрдая ли
Items.BUILDS = {
	bed = { name = "Грядка", icon = "🟫", price = 20, w = 80, h = 44, solid = false, desc = "Сажай морковь, овёс, тыквы" },
	fence = { name = "Забор", icon = "🪵", price = 8, w = 90, h = 10, solid = true, desc = "Секция деревянного забора" },
	lamp = { name = "Фонарь", icon = "🏮", price = 35, w = 16, h = 16, solid = true, desc = "Светит ночью" },
	flowerbed = { name = "Клумба", icon = "🌷", price = 15, w = 60, h = 40, solid = false, desc = "Красиво!" },
	bench = { name = "Скамейка", icon = "🪑", price = 25, w = 70, h = 24, solid = true, desc = "Отдохнуть после скачек" },
	trough = { name = "Поилка", icon = "🚰", price = 35, w = 80, h = 28, solid = true, desc = "Лошади в леваде рядом веселее" },
	haystack = { name = "Стог сена", icon = "🌾", price = 20, w = 50, h = 50, solid = true, desc = "Даёт 5 сена" },
	tree = { name = "Яблонька", icon = "🌳", price = 30, w = 30, h = 30, solid = true, desc = "Раз в 3 минуты дарит яблоки" },
	bunnyhouse = { name = "Домик для зайчиков", icon = "🐰", price = 60, w = 50, h = 40, solid = true, desc = "Зайчики приходят чаще" },
	well = { name = "Колодец", icon = "🪣", price = 80, w = 50, h = 50, solid = true, desc = "Грядки рядом поливаются сами" },
	windmill = { name = "Мельница", icon = "🌬️", price = 250, w = 110, h = 110, solid = true, desc = "Большая и красивая" },
	stable5 = { name = "Маленькая конюшня", icon = "🏠", price = 400, w = 340, h = 150, solid = false, desc = "+5 денников для лошадей" },
}
Items.BUILD_ORDER = { "bed", "fence", "lamp", "flowerbed", "bench", "trough", "haystack", "tree", "bunnyhouse", "well", "windmill", "stable5" }

Items.MANE_STYLES = {
	normal = { name = "Обычная", icon = "🐴" },
	long = { name = "Длинная", icon = "💇" },
	short = { name = "Короткая", icon = "✂️" },
	braids = { name = "Косички", icon = "🎀" },
	mohawk = { name = "Ирокез", icon = "⚡" },
	bows = { name = "С бантиками", icon = "🎀" },
}
Items.MANE_ORDER = { "normal", "long", "short", "braids", "mohawk", "bows" }
Items.DYES = {
	pink = { name = "Розовая", color = "#ff8fc7", item = "dye_pink", price = 25 },
	blue = { name = "Голубая", color = "#74c0fc", item = "dye_blue", price = 25 },
	purple = { name = "Фиолетовая", color = "#b197fc", item = "dye_purple", price = 25 },
	mint = { name = "Мятная", color = "#8ce99a", item = "dye_mint", price = 25 },
	gold = { name = "Золотая", color = "#ffd43b", item = "dye_gold", price = 60 },
	rainbow = { name = "Радужная", color = "rainbow", item = "dye_rainbow", price = 100 },
}
Items.DYE_ORDER = { "pink", "blue", "purple", "mint", "gold", "rainbow" }
Items.RAINBOW = { "#ff6b6b", "#ffa94d", "#ffe066", "#69db7c", "#4dabf7", "#9775fa" }

-- сёдла и уздечки: стиль (украшения) и цвет кожи
Items.TACK_STYLES = {
	classic = { name = "Классическое", icon = "🐴", saddle = 0, bridle = 0, desc = "Простая кожа" },
	crystal = { name = "Кристальное", icon = "💎", saddle = 180, bridle = 110, desc = "Сверкающие кристаллики" },
	plant = { name = "Цветочное", icon = "🌿", saddle = 150, bridle = 90, desc = "Листья, лианы и цветы" },
	shell = { name = "Ракушечное", icon = "🐚", saddle = 160, bridle = 100, desc = "Оболочка из ракушек и жемчуга" },
}
Items.TACK_STYLE_ORDER = { "classic", "crystal", "plant", "shell" }
Items.LEATHER = { "#5b3a1e", "#2b2b2b", "#8a5a32", "#f1e3c6", "#c92a2a", "#1c7ed6", "#e64980", "#7048e8", "#2b8a3e", "#f59f00" }
Items.SHIRTS = { "#e05a8a", "#4dabf7", "#69db7c", "#ffa94d", "#9775fa", "#ffffff", "#343a40" }

Items.GAITS = { "Шаг", "Рысь", "Галоп" }

-- тесты выездки
Items.TESTS = {
	easy = {
		name = "Тест для начинающих", desc = "шаг и рысь",
		steps = {
			{ to = "A", text = "Подъедь к букве A — это старт" },
			{ to = "X", gait = 1, text = "Рысью по средней линии от A до X" },
			{ to = "X", halt = true, text = "Остановка в X — приветствие судьям" },
			{ to = "C", gait = 1, text = "Рысью до C" },
			{ to = "M", gait = 0, text = "Шагом до M" },
			{ to = "K", gait = 1, text = "Рысью по диагонали M — X — K" },
			{ to = "A", gait = 0, text = "Шагом до A" },
			{ to = "F", gait = 0, text = "Шагом до F" },
			{ to = "M", gait = 1, text = "Рысью по длинной стороне до M" },
			{ to = "C", gait = 0, text = "Шагом до C" },
			{ to = "X", gait = 1, text = "Рысью по средней линии до X" },
			{ to = "X", halt = true, text = "Остановка, приветствие!" },
		},
	},
	canter = {
		name = "Тест с галопом", desc = "шаг, рысь и галоп",
		steps = {
			{ to = "A", text = "Подъедь к букве A — это старт" },
			{ to = "X", gait = 1, text = "Рысью от A до X" },
			{ to = "X", halt = true, text = "Остановка в X — приветствие" },
			{ to = "C", gait = 1, text = "Рысью до C" },
			{ to = "H", gait = 1, text = "Рысью до H" },
			{ to = "K", gait = 2, text = "Галопом по длинной стороне до K" },
			{ to = "A", gait = 1, text = "Рысью до A" },
			{ to = "F", gait = 1, text = "Рысью до F" },
			{ to = "M", gait = 2, text = "Галопом до M" },
			{ to = "C", gait = 1, text = "Рысью до C" },
			{ to = "E", gait = 0, text = "Шагом до E" },
			{ to = "X", gait = 0, text = "Шагом до X" },
			{ to = "X", halt = true, text = "Остановка, приветствие!" },
		},
	},
}

-- действия лошадей: позы рисует клиент по act.k
Items.ACTS = {
	rear = { name = "Встать на дыбы", icon = "🐎", d = 2.4 },
	kick = { name = "Брыкнуть задними ногами", icon = "🦵", d = 1.3 },
	graze = { name = "Поесть травку", icon = "🌱", d = 5 },
	roll = { name = "Поваляться", icon = "🌀", d = 6 },
	liftLeg = { name = "Поднять ногу", icon = "🦶", d = 2.5 },
	ears = { name = "Прижать уши", icon = "👂", d = 2.5 },
	neigh = { name = "Заржать «Иго-го!»", icon = "📣", d = 1.8 },
	lookUp = { name = "Посмотреть вверх", icon = "⬆️", d = 2.5 },
	lookDown = { name = "Посмотреть вниз", icon = "⬇️", d = 2.5 },
	bow = { name = "Нагнуть голову", icon = "🙇", d = 2.6 },
	scratch = { name = "Почесать голову коленкой", icon = "🤭", d = 3 },
	back = { name = "Пойти задом", icon = "↩️", d = 2.6 },
	dance = { name = "Потанцевать на месте", icon = "💃", d = 4.5 },
}
Items.ACT_ORDER = { "rear", "kick", "graze", "roll", "liftLeg", "ears", "neigh", "lookUp", "lookDown", "bow", "scratch", "back", "dance" }
-- коды действий для передачи по сети
Items.ACT_CODES = { "rear", "kick", "graze", "roll", "liftLeg", "ears", "neigh", "lookUp", "lookDown", "bow", "scratch", "back", "dance", "play", "lie", "getup" }

Items.MEDALS = { gold = "🥇", silver = "🥈", bronze = "🥉" }

function Items.name(k)
	return Items.ITEMS[k] and Items.ITEMS[k].name or k
end
function Items.icon(k)
	return Items.ITEMS[k] and Items.ITEMS[k].icon or "•"
end

return Items
