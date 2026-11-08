--[[
	Рынок в деревне (перенос js/market.js):
	 - Конский торговец: продаёт лошадей, с ним можно торговаться (у каждого игрока свой торговец);
	 - Тренер: за монеты прокачивает навыки;
	 - Обменщик: лошадь на лошадь с доплатой, вещи на вещи;
	 - Моя стойка: свои лошади и вещи по своей цене, покупатели-боты приходят сами и торгуются.
	 - Новое в мультиплеере: лошадей со стоек других игроков можно купить.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Items = require(Shared.Items)
local Stalls = require(Shared.Stalls)

local Market = {}
local G, Profiles
local rand, clamp, pick, round5, hypot = Util.rand, Util.clamp, Util.pick, Util.round5, Util.hypot

local STOCK_SIZE = 5
local REFRESH = 240
Market.MAX_LISTED_HORSES = 3
local BUYERS = { "Бабушка Нюра", "Фермер Коля", "Девочка Света", "Купец Савва", "Наездница Ира", "Дедушка Гоша", "Тётя Валя", "Мальчик Петя", "Цыганка Роза", "Граф Орлов" }
local STOCK_BREEDS = { "arab", "akhal", "orlov", "friesian", "haflinger", "appaloosa", "paint", "trakehner", "budyonny", "fjord", "shetland" }
local MAGIC_BREEDS = { "crystalhorse", "waterhorse", "sunhorse", "rainbowhorse", "mushroomhorse", "sandhorse", "stonehorse", "leafhorse", "damphorse", "icehorse", "firehorse", "pegasus", "unicorn", "cloudhorse" }

Market.SWAPS = {
	{ id = "s1", give = { mushroom = 5 }, get = { pollen = 1 } },
	{ id = "s2", give = { glowshroom = 3 }, get = { dye_rainbow = 1 } },
	{ id = "s3", give = { pumpkin = 2 }, get = { oats = 10 } },
	{ id = "s4", give = { carrot = 10 }, get = { dye_pink = 1 } },
	{ id = "s5", give = { oldCoin = 1, spoon = 1 }, get = { dye_gold = 1 } },
	{ id = "s6", give = { sunflower = 3 }, get = { apple = 10 } },
	{ id = "s7", give = { pollen = 2 }, get = { dye_purple = 1, dye_mint = 1 } },
	{ id = "s8", give = { oldShoe = 3 }, get = { sugar = 15 } },
}
local SAY_YES = { "Эх, уговорила! По рукам! 🤝", "Ладно-ладно, для тебя — так и быть!", "Хорошо торгуешься! Договорились.", "Ну что с тобой делать… Забирай!" }
local SAY_NO = { "Что ты! Себе в убыток не продам!", "Нет-нет, эта лошадка стоит дороже!", "Ха! Даже не проси.", "Маловато будет! Добавь монеток." }
local SAY_ANGRY = "Всё, больше не торгуюсь! Теперь цена выше 😤"

function Market.init(g, profiles) G, Profiles = g, profiles end

local function fresh()
	return { stock = {}, refreshT = 0, items = {}, offer = false, buyerT = rand(15, 30), say = "", log = {} }
end
function Market.M(sess)
	local P = sess.P
	if type(P.market) ~= "table" then P.market = fresh() end
	local m = P.market
	m.items = m.items or {}
	m.stock = m.stock or {}
	m.log = m.log or {}
	return m
end

local function restock(sess, silent)
	local m = Market.M(sess)
	local taken = G.takenNames(sess)
	m.stock = {}
	for i = 1, STOCK_SIZE do
		local magic = math.random() < (i == 1 and 0.9 or 0.3)
		local breed = magic and pick(MAGIC_BREEDS) or pick(STOCK_BREEDS)
		local names = table.clone(taken)
		for _, x in ipairs(m.stock) do table.insert(names, x.name) end
		local h = Horses.create({ id = Profiles.nextHorseId(sess.P), breed = breed, age = math.random() < 0.15 and rand(1, 2.5) or rand(3, 11), taken = names })
		h.state = "shop"
		h.ask = round5(Horses.price(h) * rand(1.2, 1.45))
		h.haggles = 3
		table.insert(m.stock, h)
	end
	m.refreshT = REFRESH
	if not silent then G.toast(sess, "🐎 Конский торговец на рынке привёз новых лошадей!") end
	G.dirty(sess)
end
function Market.setup(sess)
	local m = Market.M(sess)
	if #m.stock == 0 then restock(sess, true) end
end
function Market.reset(sess)
	sess.P.market = fresh()
	restock(sess, true)
end

local function findHorse(sess, id)
	return Util.find(Market.M(sess).stock, function(h) return h.id == id end)
end
Market.findHorse = findHorse

function Market.horseValue(h) return G.modules.Actions.sellPrice(h, false) end
function Market.itemValue(k)
	local it, f = Items.ITEMS[k], Items.FOOD[k]
	return math.max(1, (it and it.sell ~= 0 and it.sell) or (f and f.price * 0.7) or 1)
end
local function buyChance(ratio)
	if ratio <= 0.9 then return 0.85 end
	if ratio <= 1.1 then return 0.6 end
	if ratio <= 1.35 then return 0.35 end
	if ratio <= 1.6 then return 0.15 end
	if ratio <= 2 then return 0.05 end
	return 0.01
end
function Market.listings(sess)
	local m = Market.M(sess)
	local out = {}
	for _, h in ipairs(sess.P.horses) do
		if h.state == "market" then table.insert(out, { kind = "horse", id = h.id, price = h.ask, value = Market.horseValue(h), name = h.name }) end
	end
	for _, k in ipairs(Util.keys(m.items)) do
		local l = m.items[k]
		if l.n > 0 then
			table.insert(out, { kind = "item", key = k, price = l.price, value = Market.itemValue(k) * G.modules.Events.priceMul(), name = Items.name(k), n = l.n })
		end
	end
	return out
end

local function sold(sess, L, price, buyer)
	local m, P = Market.M(sess), sess.P
	if L.kind == "horse" then
		local h = Util.find(P.horses, function(x) return x.id == L.id end)
		if not h or h.state ~= "market" then return end
		Util.removeValue(P.horses, h)
		P.stats.sold = (P.stats.sold or 0) + 1
		local fem = string.sub(buyer, -2) == "а" or string.sub(buyer, -2) == "я"
		G.toast(sess, "💰 " .. buyer .. " " .. (fem and "купила" or "купил") .. " лошадь по кличке " .. h.name .. " за " .. price .. " 💰!", "good")
	else
		local l = m.items[L.key]
		if not l or l.n <= 0 then return end
		l.n -= 1
		if l.n <= 0 then m.items[L.key] = nil end
		G.toast(sess, "💰 " .. buyer .. ": «" .. Items.name(L.key) .. "» — продано за " .. price .. " 💰", "good")
	end
	P.money += price
	G.stat(sess, "marketSold")
	table.insert(m.log, 1, buyer .. ": " .. L.name .. " — " .. price .. " 💰")
	while #m.log > 6 do table.remove(m.log) end
	G.sfx(sess, "coin")
	G.dirty(sess)
end

local function buyerVisit(sess)
	local m = Market.M(sess)
	local all = Market.listings(sess)
	if #all == 0 or m.offer then return end
	local L = pick(all)
	local buyer = pick(BUYERS)
	local ratio = L.price / math.max(1, L.value)
	if math.random() < buyChance(ratio) then return sold(sess, L, L.price, buyer) end
	if ratio > 0.8 and math.random() < 0.55 then
		local offerPrice = round5(math.min(L.price * rand(0.75, 0.92), L.value * rand(1.0, 1.2)))
		if offerPrice >= L.price then return sold(sess, L, L.price, buyer) end
		m.offer = { kind = L.kind, id = L.id, key = L.key, price = offerPrice, buyer = buyer, t = 60, name = L.name }
		G.toast(sess, "🗣️ " .. buyer .. " хочет купить «" .. L.name .. "» за " .. offerPrice .. " 💰 (ты просишь " .. L.price .. "). Ответь у своей стойки на рынке!")
		G.sfx(sess, "tick")
		G.dirty(sess)
	end
end

function Market.update(sess, dt)
	local m = Market.M(sess)
	m.refreshT -= dt
	if m.refreshT <= 0 then restock(sess, false) end
	for _, h in ipairs(m.stock) do h.age += dt / 120 * 0.2 end
	if m.offer then
		m.offer.t -= dt
		if m.offer.t <= 0 then
			G.toast(sess, m.offer.buyer .. " не дождался ответа и ушёл")
			m.offer = false
			G.dirty(sess)
		end
	end
	m.buyerT -= dt
	if m.buyerT <= 0 then
		m.buyerT = rand(14, 28)
		buyerVisit(sess)
	end
end

function Market.answerOffer(sess, yes)
	local m = Market.M(sess)
	local o = m.offer
	if not o then return end
	m.offer = false
	G.dirty(sess)
	if not yes then return G.toast(sess, o.buyer .. " вздохнул и пошёл дальше") end
	sold(sess, o.kind == "horse" and { kind = "horse", id = o.id, name = o.name } or { kind = "item", key = o.key, name = o.name }, o.price, o.buyer)
end

function Market.listHorse(sess, h)
	if not h then return end
	if h.state == "ridden" then return G.toast(sess, "Сначала слезь с лошади") end
	if h.state ~= "stall" and h.state ~= "paddock" then return end
	if Util.count(sess.P.horses, function(x) return x.state == "market" end) >= Market.MAX_LISTED_HORSES then
		return G.toast(sess, "У стойки помещаются только " .. Market.MAX_LISTED_HORSES .. " лошади", "warn")
	end
	h.state = "market"
	h.ask = round5(Market.horseValue(h) * 1.2)
	G.toast(sess, "🏷️ " .. h.name .. " стоит у твоей стойки. Цена: " .. h.ask .. " 💰 — её можно поменять")
	G.sfx(sess, "tick")
	G.dirty(sess)
end
function Market.unlistHorse(sess, h)
	if not h or h.state ~= "market" then return end
	h.state = "stall"
	local m = Market.M(sess)
	if m.offer and m.offer.kind == "horse" and m.offer.id == h.id then m.offer = false end
	G.toast(sess, h.name .. " " .. Horses.v(h, "вернулась", "вернулся") .. " в конюшню")
	G.dirty(sess)
end
function Market.setHorsePrice(sess, h, k)
	if h and h.state == "market" and (k == 0.9 or k == 1.1) then
		h.ask = round5(h.ask * k)
		G.dirty(sess)
	end
end
function Market.listItem(sess, key, n)
	local P, m = sess.P, Market.M(sess)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 or not Items.ITEMS[key] or Items.ITEMS[key].sell <= 0 or not ((P.inv[key] or 0) >= n) then return end
	P.inv[key] -= n
	local l = m.items[key]
	if not l then
		l = { n = 0, price = math.max(2, math.floor(Market.itemValue(key) * 1.3 + 0.5)) }
		m.items[key] = l
	end
	l.n += n
	G.sfx(sess, "tick")
	G.dirty(sess)
end
function Market.unlistItem(sess, key)
	local P, m = sess.P, Market.M(sess)
	local l = m.items[key]
	if not l then return end
	P.inv[key] = (P.inv[key] or 0) + l.n
	m.items[key] = nil
	if m.offer and m.offer.key == key then m.offer = false end
	G.dirty(sess)
end
function Market.setItemPrice(sess, key, k)
	local l = Market.M(sess).items[key]
	if not l or (k ~= 0.9 and k ~= 1.1) then return end
	l.price = math.max(1, math.floor(l.price * k + 0.5) + (k > 1 and 1 or -1))
	G.dirty(sess)
end

--[[ ---------- торговец ---------- ]]
function Market.buy(sess, id)
	local m, P = Market.M(sess), sess.P
	local h = findHorse(sess, id)
	if not h then return end
	if P.money < h.ask then return G.toast(sess, "Не хватает монет", "warn") end
	local st = Stalls.free(P, "main")
	if st < 0 then return G.toast(sess, "В конюшне на ферме нет свободного денника", "warn") end
	P.money -= h.ask
	Util.removeValue(m.stock, h)
	h.state, h.stall = "stall", st
	h.ask, h.haggles = nil, nil
	table.insert(P.horses, h)
	G.stat(sess, "marketBought")
	m.say = "Отличный выбор! " .. h.name .. " уже едет к тебе в конюшню."
	G.toast(sess, "🐎 Куплено: " .. h.name .. "! Теперь живёт: " .. Stalls.label(st), "good")
	G.sfx(sess, "fanfare")
	G.dirty(sess)
end
function Market.haggle(sess, id, frac)
	local m = Market.M(sess)
	local h = findHorse(sess, id)
	frac = tonumber(frac)
	if not h or (h.haggles or 0) <= 0 or not (frac == 0.9 or frac == 0.8 or frac == 0.7) then return end
	local d = 1 - frac
	local mood = (sess.P.stats.marketBought or 0) > 0 and 0.05 or 0
	local chance = clamp(1.15 - d * 3 + mood, 0.05, 0.95)
	if math.random() < chance then
		h.ask = round5(h.ask * frac)
		h.haggles = 0
		m.say = pick(SAY_YES) .. " Отдам за " .. h.ask .. " 💰."
		G.stat(sess, "haggleWins")
		G.sfx(sess, "coin")
	else
		h.haggles -= 1
		if h.haggles <= 0 then
			h.ask = round5(h.ask * 1.05)
			m.say = SAY_ANGRY
		else
			m.say = pick(SAY_NO)
		end
		G.sfx(sess, "fail")
	end
	G.dirty(sess)
end

--[[ ---------- обменщик ---------- ]]
function Market.swapValue(h) return round5(Market.horseValue(h) * 0.9) end
function Market.swapHorse(sess, myId, theirId)
	local P, m = sess.P, Market.M(sess)
	local mine, theirs = G.byId(sess, myId), findHorse(sess, theirId)
	if not mine or not theirs then return end
	if mine.state ~= "stall" and mine.state ~= "paddock" then return G.toast(sess, "Сначала верни лошадь в денник") end
	local diff = theirs.ask - Market.swapValue(mine)
	if diff > 0 and P.money < diff then return G.toast(sess, "Нужна доплата " .. diff .. " 💰 — не хватает монет", "warn") end
	P.money -= diff
	local st = mine.stall
	Util.removeValue(P.horses, mine)
	local idx = table.find(m.stock, theirs)
	G.modules.Entities.removeSrc(mine)
	m.stock[idx] = mine
	mine.state, mine.ask, mine.haggles = "shop", round5(Market.horseValue(mine) * 1.3), 3
	theirs.state, theirs.stall = "stall", st
	theirs.ask, theirs.haggles = nil, nil
	table.insert(P.horses, theirs)
	G.stat(sess, "swaps")
	local extra = diff > 0 and (", доплата " .. diff .. " 💰") or diff < 0 and (", тебе доплатили " .. (-diff) .. " 💰") or ""
	G.toast(sess, "🔁 Обмен! " .. mine.name .. " → " .. theirs.name .. extra, "good")
	G.sfx(sess, "fanfare")
	G.dirty(sess)
end
function Market.canSwap(P, sw)
	for k, n in pairs(sw.give) do
		if (P.inv[k] or 0) < n then return false end
	end
	return true
end
function Market.swapItems(sess, id)
	local sw = Util.find(Market.SWAPS, function(x) return x.id == id end)
	local P = sess.P
	if not sw or not Market.canSwap(P, sw) then return G.toast(sess, "Не хватает вещей для обмена", "warn") end
	for k, n in pairs(sw.give) do P.inv[k] -= n end
	local parts = {}
	for k, n in pairs(sw.get) do
		P.inv[k] = (P.inv[k] or 0) + n
		table.insert(parts, Items.icon(k) .. " " .. Items.name(k) .. " ×" .. n)
	end
	G.stat(sess, "swaps")
	G.toast(sess, "🔁 Обменяно: " .. table.concat(parts, ", "), "good")
	G.sfx(sess, "coin")
	G.dirty(sess)
end

--[[ ---------- тренер ---------- ]]
local TRAIN_STEP = 3
function Market.trainPrice(h, k) return round5(20 + Horses.skill(h, k) * 1.6) end
function Market.train(sess, h, k)
	local P = sess.P
	if not h or not Horses.SKILLS[k] then return end
	if Horses.skill(h, k) >= 100 or h.base[k] + h.train[k] >= 100 then return G.toast(sess, "Этот навык уже максимальный!") end
	local price = Market.trainPrice(h, k)
	if P.money < price then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= price
	Horses.addTrain(h, k, TRAIN_STEP)
	h.energy = clamp(h.energy - 10, 0, 100)
	G.stat(sess, "marketTrain")
	G.toast(sess, "💪 " .. Horses.SKILLS[k] .. " у лошади по кличке " .. h.name .. ": " .. Horses.skill(h, k), "good")
	G.sfx(sess, "coin")
	G.dirty(sess)
end
function Market.spa(sess, h)
	local P, price = sess.P, 25
	if not h or P.money < price then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= price
	h.energy, h.mood, h.clean, h.mud = 100, clamp(h.mood + 25, 0, 100), 100, 0
	G.toast(sess, "🧖 " .. h.name .. ": массаж, мытьё и отдых — как новенькая!", "good")
	G.sfx(sess, "coin")
	G.dirty(sess)
end

--[[ ---------- стойки других игроков (мультиплеер) ---------- ]]
function Market.othersListings(sess)
	local out = {}
	for _, s in ipairs(G.each()) do
		if s ~= sess then
			for _, h in ipairs(s.P.horses) do
				if h.state == "market" then
					table.insert(out, { seller = s.player.UserId, sellerName = G.playerName(s), horse = Profiles.strip(h), price = h.ask })
				end
			end
		end
	end
	return out
end
function Market.buyFromPlayer(sess, sellerId, horseId)
	local seller = nil
	for _, s in ipairs(G.each()) do
		if s.player.UserId == sellerId then seller = s end
	end
	if not seller or seller == sess then return end
	local h = Util.find(seller.P.horses, function(x) return x.id == horseId and x.state == "market" end)
	if not h then return G.toast(sess, "Эту лошадь уже купили", "warn") end
	local P = sess.P
	if P.money < h.ask then return G.toast(sess, "Не хватает монет", "warn") end
	local st = Stalls.free(P, "main")
	if st < 0 then return G.toast(sess, "В конюшне на ферме нет свободного денника", "warn") end
	local price = h.ask
	P.money -= price
	seller.P.money += price
	Util.removeValue(seller.P.horses, h)
	local sm = Market.M(seller)
	if sm.offer and sm.offer.kind == "horse" and sm.offer.id == h.id then sm.offer = false end
	seller.P.stats.sold = (seller.P.stats.sold or 0) + 1
	G.stat(seller, "marketSold")
	table.insert(sm.log, 1, G.playerName(sess) .. ": " .. h.name .. " — " .. price .. " 💰")
	while #sm.log > 6 do table.remove(sm.log) end
	Profiles.adopt(P, h)
	h.state, h.stall, h.ask, h.haggles = "stall", st, nil, nil
	table.insert(P.horses, h)
	G.stat(sess, "marketBought")
	G.toast(sess, "🐎 Ты купила лошадь " .. h.name .. " у игрока " .. G.playerName(seller) .. " за " .. price .. " 💰! Живёт: " .. Stalls.label(st), "good")
	G.toast(seller, "💰 " .. G.playerName(sess) .. " купил(а) у тебя лошадь " .. h.name .. " за " .. price .. " 💰!", "good")
	G.sfx(sess, "fanfare")
	G.sfx(seller, "coin")
	G.dirty(sess)
	G.dirty(seller)
end

--[[ ---------- подсказка у прилавков ---------- ]]
function Market.stallHere(sess)
	local p = sess.p
	if not World.inRect(p.x, p.y, World.MARKET, 80) then return nil end
	local best, bd = nil, 110
	for _, st in ipairs(World.MARKET_STALLS) do
		local f = World.stallFront(st)
		local d = hypot(p.x - f.x, p.y - f.y)
		if d < bd then bd = d; best = st end
	end
	return best
end
function Market.prompt(sess)
	local st = Market.stallHere(sess)
	if not st then return nil end
	return { label = st.name, fn = function() G.open(sess, "market", { tab = st.id }) end }
end

return Market
