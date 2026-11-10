--[[
	Действия игрока из меню и кнопок (перенос объекта act из js/game.js).
	Клиент шлёт Act(имя, аргументы), сервер проверяет и выполняет.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Items = require(Shared.Items)
local Stalls = require(Shared.Stalls)

local Actions = {}
local G, Herds, Riding, Profiles
local clamp, rand, hypot = Util.clamp, Util.rand, Util.hypot

function Actions.init(g, herds, riding, profiles)
	G, Herds, Riding, Profiles = g, herds, riding, profiles
end

-- цена у торговца: пойманная без приручения — дешевле, на ярмарке — дороже
function Actions.sellPrice(h, wildOne)
	local p = Horses.price(h) * G.modules.Events.priceMul()
	if wildOne then p *= 0.85 end
	return math.floor(p / 5 + 0.5) * 5
end
-- денник доступен откуда угодно: кормить, чистить, выпускать в леваду, скрещивать и т. д. можно из любого места
local function atFarm(sess) return true end
local function nearSell(sess)
	return hypot(sess.p.x - (World.SELL.x + World.SELL.w / 2), sess.p.y - (World.SELL.y + World.SELL.h / 2)) < 170
end
local function nearShop(sess)
	return hypot(sess.p.x - (World.SHOP.x + World.SHOP.w / 2), sess.p.y - (World.SHOP.y + World.SHOP.h / 2)) < 200
end
local function nearLola(sess)
	local Q = require(Shared.QuestData)
	local n = Q.npcById("lola")
	return n and hypot(sess.p.x - n.x, sess.p.y - n.y) < 160
end
Actions.nearSell = nearSell

local A = {}
Actions.A = A

function A.paddock(sess, h)
	if not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if h.state == "market" then return G.toast(sess, h.name .. " стоит на рынке") end
	if h.state == "paddock" then
		h.state = "stall"
		G.toast(sess, h.name .. " " .. Horses.v(h, "вернулась", "вернулся") .. " в денник")
	elseif h.state == "stall" then
		local Pd = Stalls.paddockFor(h)
		h.state = "paddock"
		h.x, h.y, h.wander = rand(Pd.x + 60, Pd.x + Pd.w - 60), rand(Pd.y + 60, Pd.y + Pd.h - 60), nil
		G.toast(sess, "🌿 " .. h.name .. " гуляет в леваде")
	end
end

function A.feed(sess, h, item)
	local P = sess.P
	local f = Items.FOOD[item]
	if not f then return end
	if h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if not ((P.inv[item] or 0) > 0) then return G.toast(sess, "Нет: " .. f.name .. ". Купи в повозке.", "warn") end
	if f.foalOnly and h.age >= 3 then return G.toast(sess, "Молоко из бутылочки — для жеребят. Взрослым лучше сено и овёс", "warn") end
	if item == "milk" then
		G.float("🍼 Ням-ням!", h.x, h.y - 30, "#e64980")
		G.stat(sess, "milkFed")
		h.mood = clamp(h.mood + 5, 0, 100)
	end
	if h.hunger >= 99 and not f.bait and item ~= "sugar" then return G.toast(sess, h.name .. " " .. Horses.v(h, "сыта", "сыт")) end
	P.inv[item] -= 1
	h.hunger = clamp(h.hunger + f.hunger, 0, 100)
	h.energy = clamp(h.energy + f.energy, 0, 100)
	h.mood = clamp(h.mood + f.mood, 0, 100)
	G.sfx(sess, "tick")
end

function A.brush(sess, h)
	if h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if not sess.P.tack.brush then return G.toast(sess, "Нужна щётка — купи в повозке", "warn") end
	if (h.mud or 0) > 20 then G.toast(sess, "🖌️ Ноги у лошади по кличке " .. h.name .. " снова чистые!") end
	h.clean, h.mud = 100, 0
	h.mood = clamp(h.mood + 8, 0, 100)
	G.sfx(sess, "tick")
end

function A.trick(sess, h, k)
	if not h or not Items.ACTS[k] then return end
	local ridden = h.state == "ridden"
	if not ridden and h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if ridden and k == "roll" then return G.toast(sess, "Чтобы лошадь повалялась, сначала слезь с неё", "warn") end
	if h.state == "market" then return G.toast(sess, h.name .. " стоит на рынке") end
	G.R.Open:FireClient(sess.player, "close")
	if ridden then Riding.mountAct(sess, k) else Herds.startAct(h, k) end
	if k == "roll" and (h.mud or 0) < 30 then h.mud = math.min(100, (h.mud or 0) + 15) end
	h.mood = clamp(h.mood + 2, 0, 100)
	G.stat(sess, "tricks")
	if k == "dance" then G.stat(sess, "dances") end
end

function A.walk(sess, h)
	if h.state == "walk" then
		h.state = "stall"
		G.toast(sess, "🏠 " .. h.name .. " " .. Horses.v(h, "вернулась", "вернулся") .. " в денник")
		G.R.Open:FireClient(sess.player, "close")
		return
	end
	if not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if Horses.canRide(h) then return G.toast(sess, h.name .. " уже " .. Horses.v(h, "взрослая", "взрослый") .. " — на " .. Horses.v(h, "ней", "нём") .. " можно ездить верхом") end
	if G.mounted(sess) then return G.toast(sess, "Сначала слезь с лошади") end
	if h.state == "market" then return G.toast(sess, h.name .. " стоит на рынке") end
	for _, o in ipairs(sess.P.horses) do
		if o.state == "walk" then o.state = "stall" end
	end
	h.state = "walk"
	h.x, h.y = sess.p.x - 50, sess.p.y + 30
	G.R.Open:FireClient(sess.player, "close")
	G.toast(sess, "🐴 Гуляем с жеребёнком по кличке " .. h.name .. "! Он идёт за тобой. Вернуть в денник — кнопка внизу", "good")
end
function A.stopWalk(sess)
	local h = Util.find(sess.P.horses, function(o) return o.state == "walk" end)
	if h then A.walk(sess, h) end
end

function A.pet(sess, h)
	if h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне") end
	h.mood = clamp(h.mood + 10, 0, 100)
	G.float("💕", h.x, h.y - 30, "#e64980")
	if not h.act then Herds.startAct(h, math.random() < 0.5 and "lookUp" or "ears", true) end
	G.stat(sess, "petted")
	G.sfx(sess, "tick")
end
function A.play(sess, h)
	if h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне") end
	if h.energy < 10 then return G.toast(sess, h.name .. " " .. Horses.v(h, "устала", "устал") .. " — пусть отдохнёт", "warn") end
	G.R.Open:FireClient(sess.player, "close")
	h.mood = clamp(h.mood + 15, 0, 100)
	h.energy = clamp(h.energy - 8, 0, 100)
	Herds.startAct(h, math.random() < 0.6 and "play" or "dance")
	G.float("🎾 Играем!", h.x, h.y - 30, "#1c7ed6")
	G.stat(sess, "foalPlay")
end

function A.birth(sess, h)
	h = h or Util.find(sess.P.horses, function(o) return o.preg and o.preg.ready end)
	if not h or not h.preg or not h.preg.ready then return end
	local P = sess.P
	local st = Stalls.free(P, "main")
	if st < 0 then return G.toast(sess, "Нет свободного денника для жеребёнка — освободи место!", "warn") end
	local f = Horses.foal(h, h.preg.father, G.takenNames(sess), Profiles.nextHorseId(P))
	f.state, f.stall, f.hunger, f.mood = "stall", st, 90, 90
	table.insert(P.horses, f)
	P.stats.foals = (P.stats.foals or 0) + 1
	if Horses.isMagic(f) then G.stat(sess, "magicFoals") end
	h.preg = nil
	G.R.Open:FireClient(sess.player, "close")
	G.R.Birth:FireClient(sess.player, { mare = h.id, foal = f.id })
	G.sfx(sess, "fanfare")
end

-- уход в виде мини-игр: проверка перед началом
function A.care(sess, h, kind)
	local P = sess.P
	if h.state ~= "walk" and not atFarm(sess) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if kind == "brush" and not P.tack.brush then return G.toast(sess, "Нужна щётка — купи в повозке «Корм и амуниция»", "warn") end
	if kind == "shoe" and not ((P.inv.horseshoes or 0) > 0) then return G.toast(sess, "Нужны новые подковы — купи в повозке «Корм и амуниция»", "warn") end
	if kind == "shoe" and h.age < 2 then return G.toast(sess, "Жеребятам подковы не нужны — копытца ещё мягкие", "warn") end
	if kind == "milk" then
		if h.age >= 3 then return G.toast(sess, "Молоко из бутылочки — для жеребят. Взрослым лучше сено и овёс", "warn") end
		if not ((P.inv.milk or 0) > 0) then return G.toast(sess, "Нет бутылочки молока — купи в повозке «Корм и амуниция»", "warn") end
	end
	if kind ~= "brush" and kind ~= "wash" and kind ~= "shoe" and kind ~= "milk" then return end
	sess.care = { id = h.id, kind = kind, t = G.time }
	G.R.Open:FireClient(sess.player, "close")
	G.R.Care:FireClient(sess.player, { kind = kind, id = h.id })
end
function A.careDone(sess, h, kind, score)
	local c = sess.care
	if not c or c.id ~= h.id or c.kind ~= kind then return end
	sess.care = nil
	-- мини-игра не может закончиться мгновенно
	if G.time - c.t < 2 then return end
	score = clamp(tonumber(score) or 0, 0, 1)
	local P = sess.P
	if kind == "brush" then
		h.clean = 100
		h.mood = clamp(h.mood + 6 + score * 6, 0, 100)
		G.toast(sess, "🖌️ " .. h.name .. " " .. Horses.v(h, "расчёсана", "расчёсан") .. " и блестит!", "good")
		G.stat(sess, "brushed")
	elseif kind == "wash" then
		h.clean, h.mud, h.wet = 100, 0, 100
		h.mood = clamp(h.mood + 8 + score * 6, 0, 100)
		G.toast(sess, "🛁 " .. h.name .. " " .. Horses.v(h, "чистенькая и мокрая", "чистенький и мокрый") .. " — скоро высохнет!", "good")
		G.stat(sess, "washed")
	elseif kind == "milk" then
		-- мини-игра «напоить из бутылочки» пройдена — жеребёнок выпил молоко
		if not ((P.inv.milk or 0) > 0) then return end
		local f = Items.FOOD.milk
		P.inv.milk -= 1
		h.hunger = clamp(h.hunger + f.hunger, 0, 100)
		h.energy = clamp(h.energy + f.energy, 0, 100)
		h.mood = clamp(h.mood + f.mood + 5 + score * 5, 0, 100)
		G.float("🍼 Ням-ням!", h.x, h.y - 30, "#e64980")
		G.stat(sess, "milkFed")
		G.toast(sess, "🍼 " .. h.name .. " " .. Horses.v(h, "выпила", "выпил") .. " всю бутылочку и довольно фыркает!", "good")
	elseif kind == "shoe" then
		if not ((P.inv.horseshoes or 0) > 0) then return end
		P.inv.horseshoes -= 1
		h.shoes = true
		h.mood = clamp(h.mood + 4, 0, 100)
		Horses.addTrain(h, "speed", 1 + score * 2)
		Horses.addTrain(h, "jump", 1 + score * 2)
		G.toast(sess, "🔧 " .. h.name .. " в новых подковах! Скорость и прыжки чуть выше", "good")
		G.stat(sess, "shod")
	end
	G.sfx(sess, "fanfare")
	if h.state == "ridden" then Riding.publishMount(sess) end
end

function A.rename(sess, h, n)
	if type(n) ~= "string" then return end
	n = string.gsub(n, "^%s+", "")
	n = string.gsub(n, "%s+$", "")
	if #n == 0 then return end
	local filtered = n
	local ok, res = pcall(function()
		local TextService = game:GetService("TextService")
		local r = TextService:FilterStringAsync(n, sess.player.UserId)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and res then filtered = res end
	h.name = utf8.len(filtered) and utf8.len(filtered) > 20 and string.sub(filtered, 1, utf8.offset(filtered, 21) - 1) or filtered
	if h.state == "ridden" then Riding.publishMount(sess) end
end

function A.breed(sess, mare, stallion)
	local P = sess.P
	if not atFarm(sess) then return G.toast(sess, "Подойди к конюшне") end
	if not mare or not stallion or mare.sex ~= "f" or stallion.sex ~= "m" then return end
	if not Horses.isAdult(mare) or not Horses.isAdult(stallion) then return G.toast(sess, "Обе лошади должны быть взрослыми", "warn") end
	if mare.preg then return G.toast(sess, mare.name .. " уже ждёт жеребёнка") end
	local cost = Horses.breedCost(mare, stallion)
	if P.money < cost then return G.toast(sess, "Нужно " .. cost .. " монет на ветеринара", "warn") end
	P.money -= cost
	mare.preg = {
		t = 150,
		father = { name = stallion.name, g = Util.copy(stallion.g), base = Util.copy(stallion.base), breed = stallion.breed, size = stallion.size,
			temper = stallion.temper, marks = Util.copy(stallion.marks), magic = stallion.magic and Util.copy(stallion.magic) or nil, coat = stallion.coat },
	}
	G.R.Open:FireClient(sess.player, "close")
	G.toast(sess, "💕 " .. mare.name .. " и " .. stallion.name .. " ждут жеребёнка! Он родится через 2,5 минуты.", "good")
	G.sfx(sess, "fanfare")
end

function A.sell(sess, id, isLed)
	local P = sess.P
	if not nearSell(sess) then return G.toast(sess, "Подойди к повозке «Продажа лошадей»") end
	if isLed then
		local h = sess.led
		if not h then return end
		local price = Actions.sellPrice(h, true)
		P.money += price
		G.modules.Entities.removeSrc(h)
		sess.led = nil
		P.stats.sold = (P.stats.sold or 0) + 1
		G.toast(sess, "Продано: " .. h.name .. " за " .. price .. " 💰", "good")
		G.sfx(sess, "coin")
		return
	end
	local h = G.byId(sess, id)
	if not h then return end
	if h.state == "walk" then return G.toast(sess, "Сначала верни жеребёнка в денник") end
	if h.state == "ridden" then return G.toast(sess, "Сначала слезь с лошади") end
	if h.state == "market" then return G.toast(sess, "Сначала сними лошадь с продажи у своей стойки") end
	local price = Actions.sellPrice(h, false)
	P.money += price
	G.modules.Entities.removeSrc(h)
	Util.removeValue(P.horses, h)
	P.stats.sold = (P.stats.sold or 0) + 1
	G.toast(sess, "Продано: " .. h.name .. " за " .. price .. " 💰", "good")
	G.sfx(sess, "coin")
end

function A.buyFood(sess, item, n)
	local P = sess.P
	local f = Items.FOOD[item]
	n = math.floor(tonumber(n) or 0)
	if not f or (n ~= 1 and n ~= 5) then return end
	if not nearShop(sess) then return G.toast(sess, "Подойди к повозке «Корм и амуниция»") end
	local cost = f.price * n
	if P.money < cost then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= cost
	P.inv[item] = (P.inv[item] or 0) + n
	G.sfx(sess, "coin")
end

-- цены на вещи в повозке (сервер не верит цене от клиента)
local function shopPrice(sess, key)
	if key == "horseshoes" then return 25 end
	for _, d in pairs(Items.DYES) do
		if d.item == key then
			if nearLola(sess) then return d.price end
			return math.floor(d.price * 1.2 + 0.5)
		end
	end
	return nil
end
function A.buyItem(sess, key, n)
	local P = sess.P
	n = math.floor(tonumber(n) or 0)
	if n < 1 or n > 5 then return end
	local price = shopPrice(sess, key)
	if not price then return end
	if not nearShop(sess) and not nearLola(sess) then return G.toast(sess, "Подойди к повозке «Корм и амуниция»") end
	if P.money < price * n then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= price * n
	P.inv[key] = (P.inv[key] or 0) + n
	G.sfx(sess, "coin")
end
function A.sellItem(sess, key, n)
	local P = sess.P
	local it = Items.ITEMS[key]
	n = math.floor(tonumber(n) or 0)
	if not it or it.sell <= 0 or n < 1 or not ((P.inv[key] or 0) >= n) then return end
	if not nearSell(sess) then return G.toast(sess, "Подойди к повозке «Продажа лошадей»") end
	P.inv[key] -= n
	P.money += it.sell * n
	G.sfx(sess, "coin")
end

function A.buyTack(sess, item)
	local P = sess.P
	local t = Items.TACK[item]
	if not t or P.tack[item] then return end
	if not nearShop(sess) then return G.toast(sess, "Подойди к повозке «Корм и амуниция»") end
	if P.money < t.price then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= t.price
	P.tack[item] = t.colors and Items.COLORS[item == "boots" and 8 or item == "helmet" and 7 or 1] or true
	G.sfx(sess, "coin")
	G.toast(sess, "Куплено: " .. t.name .. "!", "good")
	if G.mounted(sess) then Riding.publishMount(sess); Riding.applyLook(sess) end
end
function A.setColor(sess, item, color)
	local t = Items.TACK[item]
	if not t or not t.colors or not sess.P.tack[item] or not table.find(Items.COLORS, color) then return end
	sess.P.tack[item] = color
	if G.mounted(sess) then Riding.publishMount(sess); Riding.applyLook(sess) end
end
function A.setShirt(sess, color)
	if not table.find(Items.SHIRTS, color) then return end
	sess.P.shirt = color
	Riding.applyLook(sess)
end
function A.buyStyle(sess, kind, style)
	local P = sess.P
	local st = Items.TACK_STYLES[style]
	if not st or (kind ~= "saddle" and kind ~= "bridle") then return end
	local own = P.tack[kind .. "Styles"]
	if not P.tack[kind] then return G.toast(sess, kind == "saddle" and "Сначала купи обычное седло" or "Сначала купи обычную уздечку", "warn") end
	if own[style] then
		P.tack[kind .. "Style"] = style
	else
		if not nearShop(sess) then return G.toast(sess, "Подойди к повозке «Корм и амуниция»") end
		local price = st[kind]
		if P.money < price then return G.toast(sess, "Не хватает монет", "warn") end
		P.money -= price
		own[style] = true
		P.tack[kind .. "Style"] = style
		G.toast(sess, "Куплено: " .. string.lower(st.name) .. " " .. (kind == "saddle" and "седло" or "оголовье") .. "!", "good")
		G.sfx(sess, "coin")
	end
	if G.mounted(sess) then Riding.publishMount(sess) end
end
function A.setTackColor(sess, kind, color)
	if (kind ~= "saddle" and kind ~= "bridle") or not table.find(Items.LEATHER, color) then return end
	sess.P.tack[kind .. "Color"] = color
	G.sfx(sess, "tick")
	if G.mounted(sess) then Riding.publishMount(sess) end
end

function A.toggleDetector(sess)
	if not sess.P.tack.detector then return G.toast(sess, "Металлоискатель продаётся в повозке «Корм и амуниция»") end
	sess.p.detector = not sess.p.detector
	G.toast(sess, sess.p.detector and "📡 Металлоискатель включён. Чем чаще пищит — тем ближе клад!" or "📡 Металлоискатель выключен")
end

function A.setManeStyle(sess, h, style)
	if not h or not Items.MANE_STYLES[style] or h.maneStyle == style then return end
	h.maneStyle = style
	if style ~= "normal" then G.stat(sess, "maneStyled") end
	G.sfx(sess, "tick")
	if h.state == "ridden" then Riding.publishMount(sess) end
end
function A.dyeMane(sess, h, dye)
	if not h then return end
	if not dye or dye == "" then
		h.maneDye = nil
		G.sfx(sess, "tick")
	else
		local d = Items.DYES[dye]
		if not d then return end
		local P = sess.P
		if not ((P.inv[d.item] or 0) > 0) then return G.toast(sess, "Нет краски: " .. d.name .. ". Купи у Лолы или в повозке", "warn") end
		P.inv[d.item] -= 1
		h.maneDye = dye
		G.stat(sess, "maneDyed")
		G.toast(sess, "🎨 Грива стала: " .. string.lower(d.name) .. "!", "good")
		G.sfx(sess, "coin")
	end
	if h.state == "ridden" then Riding.publishMount(sess) end
end

function A.reset(sess)
	-- начать заново: всё с нуля
	Riding.dismount(sess, true)
	G.modules.Owned.removeAll(sess)
	if sess.led then sess.led = nil end
	G.modules.Exercises.cancel(sess)
	local seen = sess.P.seenHelp
	sess.P = Profiles.new()
	sess.P.seenHelp = seen
	G.modules.Market.reset(sess)
	G.R.Open:FireClient(sess.player, "close")
	G.toast(sess, "Новая игра! Поймай свою первую лошадь в поле →")
end

--[[ ---------- разбор команд от клиента ---------- ]]
local function horseArg(sess, id)
	id = tonumber(id)
	if not id then return nil end
	return G.byId(sess, id)
end

function Actions.handle(sess, name, a, b, c)
	if type(name) ~= "string" then return end
	local P = sess.P
	local M = G.modules
	local h
	if name == "interact" then
		local pr = sess.promptObj
		if pr and pr.fn then pr.fn() end
	elseif name == "lasso" then
		local target = nil
		if a then target = Herds.byEntity(tonumber(a)) end
		if target and hypot(target.x - sess.p.x, target.y - sess.p.y) > Herds.LASSO_RANGE then target = nil end
		Herds.startLasso(sess, target or Herds.nearestCatchable(sess))
	elseif name == "lassoThrow" then
		Herds.resolveLasso(sess, a)
	elseif name == "release" then
		M.Owned.releaseLed(sess)
	elseif name == "setGait" then
		Riding.setGait(sess, a)
	elseif name == "sprint" then
		sess.p.sprint = a == true
	elseif name == "dismount" then
		Riding.dismount(sess)
	elseif name == "fly" then
		Riding.toggleFly(sess)
	elseif name == "neigh" then
		if G.mounted(sess) then Riding.mountAct(sess, "neigh") end
	elseif name == "lift" then
		M.Exercises.liftLegs(sess)
	elseif name == "cancelEx" then
		M.Exercises.cancel(sess, "Упражнение прервано")
		M.Events.leaveRace(sess, "Скачки прерваны")
	elseif name == "detector" then
		A.toggleDetector(sess)
	elseif name == "train" then
		if M.Exercises.inArena(sess.p) then M.Exercises.start(sess, a) end
	elseif name == "jump" then
		if M.Exercises.inJumpField(sess.p) then M.Exercises.startJumping(sess, a) end
	elseif name == "raceGo" then
		M.Events.startRace(sess)
	elseif name == "raceNew" then
		M.Events.prepareRace(sess)
	elseif name == "sail" then
		Riding.sail(sess, a)
	elseif name == "mount" then
		h = horseArg(sess, a)
		if h then Riding.mount(sess, h) end
	elseif name == "paddock" then
		h = horseArg(sess, a)
		if h then A.paddock(sess, h) end
	elseif name == "feed" then
		h = horseArg(sess, a)
		if h then A.feed(sess, h, b) end
	elseif name == "brush" then
		h = horseArg(sess, a)
		if h then A.brush(sess, h) end
	elseif name == "trick" then
		h = horseArg(sess, a)
		if h then A.trick(sess, h, b) end
	elseif name == "walk" then
		h = horseArg(sess, a)
		if h then A.walk(sess, h) end
	elseif name == "stopWalk" then
		A.stopWalk(sess)
	elseif name == "pet" then
		h = horseArg(sess, a) or Util.find(P.horses, function(o) return o.state == "walk" end)
		if h then A.pet(sess, h) end
	elseif name == "play" then
		h = horseArg(sess, a) or Util.find(P.horses, function(o) return o.state == "walk" end)
		if h then A.play(sess, h) end
	elseif name == "birth" then
		A.birth(sess, horseArg(sess, a))
	elseif name == "care" then
		h = horseArg(sess, a)
		if h then A.care(sess, h, b) end
	elseif name == "careDone" then
		h = horseArg(sess, a)
		if h then A.careDone(sess, h, b, c) end
	elseif name == "rename" then
		h = horseArg(sess, a)
		if h then A.rename(sess, h, b) end
	elseif name == "breed" then
		A.breed(sess, horseArg(sess, a), horseArg(sess, b))
	elseif name == "sell" then
		A.sell(sess, tonumber(a), b == true)
	elseif name == "buyFood" then
		A.buyFood(sess, a, b)
	elseif name == "buyItem" then
		A.buyItem(sess, a, b)
	elseif name == "sellItem" then
		A.sellItem(sess, a, b)
	elseif name == "buyTack" then
		A.buyTack(sess, a)
	elseif name == "color" then
		A.setColor(sess, a, b)
	elseif name == "shirt" then
		A.setShirt(sess, a)
	elseif name == "tackStyle" then
		A.buyStyle(sess, a, b)
	elseif name == "tackColor" then
		A.setTackColor(sess, a, b)
	elseif name == "maneStyle" then
		A.setManeStyle(sess, horseArg(sess, a), b)
	elseif name == "maneDye" then
		A.dyeMane(sess, horseArg(sess, a), b)
	elseif name == "qAccept" then
		M.Quests.accept(sess, a)
	elseif name == "qTurnIn" then
		M.Quests.turnIn(sess, a)
	elseif name == "boardAccept" then
		M.Quests.boardAccept(sess)
	elseif name == "boardTurnIn" then
		M.Quests.boardTurnIn(sess)
	elseif name == "mkBuy" then
		M.Market.buy(sess, tonumber(a))
	elseif name == "mkHaggle" then
		M.Market.haggle(sess, tonumber(a), b)
	elseif name == "mkTrain" then
		M.Market.train(sess, horseArg(sess, a), b)
	elseif name == "mkSpa" then
		M.Market.spa(sess, horseArg(sess, a))
	elseif name == "mkSwap" then
		M.Market.swapHorse(sess, tonumber(a), tonumber(b))
	elseif name == "mkSwapItem" then
		M.Market.swapItems(sess, a)
	elseif name == "mkList" then
		M.Market.listHorse(sess, horseArg(sess, a))
	elseif name == "mkUnlist" then
		if b == "horse" then M.Market.unlistHorse(sess, horseArg(sess, a)) else M.Market.unlistItem(sess, a) end
	elseif name == "mkPrice" then
		if b == "horse" then M.Market.setHorsePrice(sess, horseArg(sess, a), tonumber(c)) else M.Market.setItemPrice(sess, a, tonumber(c)) end
	elseif name == "mkListItem" then
		M.Market.listItem(sess, a, b)
	elseif name == "mkOffer" then
		M.Market.answerOffer(sess, a == true)
	elseif name == "mkBuyPlayer" then
		M.Market.buyFromPlayer(sess, tonumber(a), tonumber(b))
	elseif name == "seenHelp" then
		P.seenHelp = true
	elseif name == "reset" then
		A.reset(sess)
	elseif name == "npcTip" then
		G.R.Toast:FireClient(sess.player, "💡 " .. M.Quests.tip(a), "")
		return
	end
	G.dirty(sess)
end

return Actions
