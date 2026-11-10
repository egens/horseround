--[[
	Окна (перенос модального окна из js/ui.js): конюшня, лошадь, скрещивание, трюки, игроки,
	повозки, лодка, рынок, рюкзак, тренировка, конкур, результаты, жители и задания,
	грива, скачки, справка.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Horses = require(Shared.Horses)
local Genetics = require(Shared.Genetics)
local Stalls = require(Shared.Stalls)
local Q = require(Shared.QuestData)
local BuildInfo = require(Shared.BuildInfo)

local Client = script.Parent.Parent
local State = require(Client.State)
local Kit = require(script.Parent.Kit)

local Win = {}
local make, C, color = Kit.make, Kit.C, Util.color
local esc = Kit.esc
local player = Players.LocalPlayer
local gui, modal, titleL, body
local current = nil
local views = {}
local lastRender = 0

local function act(...) State.act(...) end
local function open(name, data) Win.open(name, data) end

local function fairMul() return State.world.fair and 1.3 or 1 end
local function sellPrice(h, wildOne)
	local p = Horses.price(h) * fairMul()
	if wildOne then p *= 0.85 end
	return math.floor(p / 5 + 0.5) * 5
end
local function mmss(v) return math.floor(v / 60) .. " мин " .. math.floor(v % 60) .. " с" end

local function statusBadges(h)
	local b = {}
	if h.state == "paddock" then table.insert(b, "🌿 в леваде") end
	if h.state == "ridden" then table.insert(b, "🏇 верхом") end
	if h.preg and not h.preg.ready then table.insert(b, "🍼 ждёт жеребёнка (" .. math.ceil(math.max(0, h.preg.t)) .. " с)") end
	if h.age < 3 then table.insert(b, "🍼 малыш") end
	if h.hunger < 25 then table.insert(b, "😟 голодная") end
	if h.clean < 25 then table.insert(b, "🟫 грязная") end
	if (h.mud or 0) > 25 then table.insert(b, "🟤 ноги в грязи") end
	if (h.wet or 0) > 22 then table.insert(b, "💧 мокрая") end
	if h.preg and h.preg.ready then table.insert(b, "🍼 готова родить!") end
	if h.state == "walk" then table.insert(b, "🐾 гуляет с тобой") end
	if h.shoes then table.insert(b, "🔧 подкована") end
	if h.state == "market" then table.insert(b, "🏷️ на рынке (" .. tostring(h.ask) .. " 💰)") end
	return table.concat(b, " · ")
end

local function horseCard(B, h, extra, opts)
	local ph = Horses.pheno(h)
	local Br = Genetics.BREEDS[h.breed]
	local sk = {}
	for _, k in ipairs(Horses.SKILL_ORDER) do table.insert(sk, string.sub(Horses.SKILLS[k], 1, utf8.offset(Horses.SKILLS[k], 5) - 1) .. ". " .. Horses.skill(h, k)) end
	local lines = { Kit.sexIcon(h) .. " " .. esc(h.name), esc(ph.name), esc(Br.name) .. ", " .. Horses.ageText(h) }
	if h.magic then table.insert(lines, "<b>" .. esc(Horses.magicText(h)) .. "</b>") end
	if opts and opts.skills then table.insert(lines, table.concat(sk, " · ")) end
	return Kit.card(B, Horses.look(h), lines, extra, opts)
end

--[[ ================= конюшня ================= ]]
views.stable = function(B, d)
	local P = State.P
	local can = true -- денник доступен откуда угодно
	local total = 0
	for _, grp in ipairs(Stalls.groups(P)) do
		total += #grp.list
		local busy = Util.count(grp.list, function(i) return Stalls.horseIn(P, i) ~= nil end)
		if grp.title ~= "Ферма" and busy == 0 then
			Kit.h(B, esc(grp.title) .. ": 5 свободных денников")
		else
			Kit.h(B, esc(grp.title))
			local grid = Kit.grid(B)
			for _, i in ipairs(grp.list) do
				local num = grp.title == "Ферма" and i + 1 or (i - 1000) % 5 + 1
				local h = Stalls.horseIn(P, i)
				if not h then
					Kit.card(grid, nil, { "№" .. num, "свободный денник" }, nil, { width = 176 })
				else
					local ph = Horses.pheno(h)
					Kit.card(grid, Horses.look(h), { "№" .. num .. "  " .. Kit.sexIcon(h) .. " " .. esc(h.name), esc(ph.name), esc(Genetics.BREEDS[h.breed].name) .. ", " .. Horses.ageText(h), statusBadges(h) },
						function(card) Kit.bar(card, "Сытость", h.hunger) end,
						{ width = 176, onClick = function() open("horse", { id = h.id, can = can }) end })
				end
			end
		end
	end
	return "Конюшни — " .. #P.horses .. " из " .. total .. " денников"
end

--[[ ================= лошадь ================= ]]
views.horse = function(B, d)
	local P = State.P
	local h = State.byId(d.id)
	local can = true -- денник доступен откуда угодно
	Kit.button(Kit.row(B), "← Все лошади", function() open("stable", { can = can }) end, { color = "ghost" })
	if not h then
		Kit.text(B, "Этой лошади больше нет на ферме.")
		return "Лошадь"
	end
	local ph = Horses.pheno(h)
	local Br = Genetics.BREEDS[h.breed]
	local dis = not can
	local top = Kit.row(B, { gap = 12 })
	Kit.portrait(top, Horses.look(h), 300, 160)
	local info = Kit.col(top, { width = 0, widthOffset = 330 })
	Kit.text(info, Kit.sexIcon(h) .. " <b>" .. esc(h.name) .. "</b>", { size = 20 })
	local rr = Kit.row(info)
	local inp = Kit.input(rr, h.name, 20)
	Kit.button(rr, "✏️ Переименовать", function() act("rename", h.id, inp.Text) end, { small = true })
	local rows = {
		{ "Порода", esc(Br.name) }, { "Пол, возраст", Horses.sexText(h) .. ", " .. Horses.ageText(h) }, { "Окрас", "<b>" .. esc(ph.name) .. "</b>" },
		{ "Отметины", Horses.marksText(h) }, { "Гены окраса", "<font face=\"RobotoMono\">" .. Genetics.genotypeText(h.g) .. "</font>" }, { "Нрав", Horses.temperText(h) },
	}
	if h.magic then table.insert(rows, { "Волшебство", "<b>" .. esc(Horses.magicText(h)) .. "</b>" }) end
	table.insert(rows, { "Грива", Items.MANE_STYLES[h.maneStyle or "normal"].name .. (h.maneDye and (", " .. string.lower(Items.DYES[h.maneDye].name)) or "") })
	table.insert(rows, { "Денник", esc(Stalls.label(h.stall)) })
	table.insert(rows, { "Цена", sellPrice(h) .. " 💰" })
	for _, r in ipairs(rows) do Kit.text(info, "<font color=\"#7a6650\">" .. r[1] .. ":</font> " .. r[2], { size = 14 }) end
	local badges = statusBadges(h)
	if badges ~= "" then Kit.small(info, badges) end
	local cols = Kit.row(B, { gap = 16 })
	local c1 = Kit.col(cols, { width = 0.48 })
	Kit.h(c1, "Уход")
	Kit.bar(c1, "Сытость", h.hunger)
	Kit.bar(c1, "Энергия", h.energy)
	Kit.bar(c1, "Настроение", h.mood)
	Kit.bar(c1, "Чистота", h.clean)
	local c2 = Kit.col(cols, { width = 0.48 })
	Kit.h(c2, "Навыки")
	Kit.small(c2, "синий — от природы, жёлтый — тренировки")
	for _, k in ipairs(Horses.SKILL_ORDER) do Kit.skillBar(c2, h, k) end
	Kit.h(B, "Покормить")
	local fr = Kit.row(B)
	for _, k in ipairs(Items.FOOD_ORDER) do
		local f = Items.FOOD[k]
		if not f.foalOnly then
			Kit.button(fr, f.icon .. " " .. f.name .. " <font size=\"12\">×" .. (P.inv[k] or 0) .. "</font>", function() act("feed", h.id, k) end, { disabled = dis or (P.inv[k] or 0) == 0 })
		end
	end
	local young = not Horses.canRide(h)
	if h.preg and h.preg.ready then Kit.button(Kit.row(B), "🍼 Родить жеребёнка!", function() act("birth", h.id) end, { big = true, color = "pink", disabled = dis }) end
	Kit.h(B, "Действия")
	local ar = Kit.row(B)
	Kit.button(ar, "🏇 Сесть верхом", function() act("mount", h.id) end, { color = "green", disabled = dis or h.state == "ridden" or young })
	Kit.button(ar, h.state == "paddock" and "🏠 Вернуть в денник" or "🌿 Выпустить в леваду", function() act("paddock", h.id) end, { disabled = dis or h.state == "ridden" or h.state == "walk" })
	Kit.button(ar, "💕 Скрестить", function() open("breed", { id = h.id }) end, { color = "pink", disabled = dis or not (Horses.isAdult(h) and not (h.sex == "f" and h.preg)) })
	Kit.button(ar, "💇 Грива", function() open("mane", { id = h.id }) end, { disabled = dis })
	Kit.button(ar, "🎭 Трюки", function() open("tricks", { id = h.id }) end, { disabled = dis })
	Kit.button(ar, "🐴 Седло и уздечка", function() open("tack", { id = h.id }) end)
	Kit.h(B, "Уход (мини-игры)")
	local cr = Kit.row(B)
	Kit.button(cr, "🖌️ Расчесать", function() act("care", h.id, "brush") end, { disabled = dis })
	Kit.button(cr, "🛁 Помыть", function() act("care", h.id, "wash") end, { disabled = dis })
	Kit.button(cr, "🔧 Подковать <font size=\"12\">(подков: " .. (P.inv.horseshoes or 0) .. ")</font>", function() act("care", h.id, "shoe") end, { disabled = dis })
	Kit.button(cr, "⚡ Быстро почистить", function() act("brush", h.id) end, { small = true, color = "ghost", disabled = dis })
	if young then
		Kit.h(B, "🍼 Жеребёнок")
		local yr = Kit.row(B)
		Kit.button(yr, h.state == "walk" and "🏠 Закончить прогулку" or "🐾 Гулять", function() act("walk", h.id) end, { color = "green", disabled = dis })
		Kit.button(yr, "🍼 Напоить из бутылочки ×" .. (P.inv.milk or 0), function() act("care", h.id, "milk") end, { disabled = dis or (P.inv.milk or 0) == 0 })
		Kit.button(yr, "💕 Погладить", function() act("pet", h.id) end, { color = "pink", disabled = dis })
		Kit.button(yr, "🎾 Поиграть", function() act("play", h.id) end, { disabled = dis })
	end
	if not P.tack.saddle or not P.tack.bridle then Kit.note(B, "Чтобы ездить верхом, нужны седло и уздечка из повозки «Корм и амуниция».") end
	if young then Kit.note(B, "Ездить верхом можно только с " .. Horses.RIDE_AGE .. " лет, скрещивать — с 3 лет. Жеребята растут быстро: 1 год = 2 минуты. Пока можно гулять, поить молоком, гладить и играть.") end
	return h.name
end

--[[ ================= скрещивание ================= ]]
views.breed = function(B, d)
	local P = State.P
	local h = State.byId(d.id)
	if not h then return "Скрещивание" end
	local mare = h.sex == "f" and h or nil
	Kit.button(Kit.row(B), "← Назад", function() open("horse", { id = h.id, can = true }) end, { color = "ghost" })
	Kit.text(B, "Выбери " .. (mare and "жеребца" or "кобылу") .. " в пару (" .. (mare and "кобыла" or "жеребец") .. " — " .. esc(h.name) .. "). Окрас жеребёнка зависит от генов обоих родителей, а навыки — средние от родителей плюс немного удачи.")
	local partners = Util.filter(P.horses, function(x) return x.sex ~= h.sex and Horses.isAdult(x) and not (x.sex == "f" and x.preg) end)
	if #partners == 0 then Kit.note(B, "Нет подходящих " .. (mare and "жеребцов" or "кобыл") .. ": нужна взрослая лошадь (от 3 лет) другого пола. Поймай её в поле!") end
	local grid = Kit.grid(B)
	for _, p in ipairs(partners) do
		horseCard(grid, p, nil, { selected = p.id == d.partner, onClick = function() open("breed", { id = h.id, partner = p.id }) end })
	end
	local p = d.partner and State.byId(d.partner)
	if p then
		local m, f = mare or p, mare and p or h
		local pred = Genetics.predict(m.g, f.g)
		local breed = m.breed == f.breed and Genetics.BREEDS[m.breed].name or "Помесь"
		local box = Kit.col(B, { bg = color("#fff0f6") })
		Kit.h(box, "Каким может быть жеребёнок?")
		Kit.text(box, "Мама: <b>" .. esc(m.name) .. "</b> (" .. esc(Horses.pheno(m).name) .. ") · папа: <b>" .. esc(f.name) .. "</b> (" .. esc(Horses.pheno(f).name) .. ")")
		Kit.text(box, "Порода: <b>" .. esc(breed) .. "</b>")
		for _, x in ipairs(pred) do Kit.bar(box, x.name, x.pct, "#f783ac") end
		local cost = Horses.breedCost(m, f)
		Kit.small(box, "Ветеринар: " .. cost .. " 💰 (чем дороже и волшебнее родители, тем дороже). Жеребёнок родится через 2,5 минуты, если будет свободный денник.")
		Kit.button(Kit.row(box), "💕 Скрестить за " .. cost .. " 💰", function() act("breed", m.id, f.id) end, { color = "pink", big = true, disabled = P.money < cost })
	end
	return "Скрещивание: " .. h.name
end

--[[ ================= трюки ================= ]]
views.tricks = function(B, d)
	local h = State.byId(d.id)
	if not h then return "Трюки" end
	Kit.text(B, "Что сделать лошади по кличке <b>" .. esc(h.name) .. "</b>? " .. (h.state == "ridden" and "Верхом лошадь делает трюк на месте. N — заржать." or ""))
	local r = Kit.row(B)
	for _, k in ipairs(Items.ACT_ORDER) do
		local a = Items.ACTS[k]
		Kit.button(r, a.icon .. " " .. a.name, function() act("trick", h.id, k) end, { disabled = h.state == "ridden" and k == "roll" })
	end
	if h.state ~= "ridden" then Kit.button(Kit.row(B), "← Назад", function() open("horse", { id = h.id, can = true }) end, { color = "ghost" }) end
	return "🎭 Трюки: " .. h.name
end

--[[ ================= игроки ================= ]]
views.players = function(B, d)
	local res = d.res
	if not res then
		Kit.text(B, "Загрузка…")
		task.spawn(function()
			local r = State.query("players")
			if current and current.name == "players" then open("players", { res = r or { rows = {} } }) end
		end)
		return "👥 Игроки"
	end
	Kit.text(B, "Кто поймает больше лошадей? Здесь все игроки на сервере.")
	for i, r in ipairs(res.rows or {}) do
		Kit.text(B, i .. ". " .. (r.me and "⭐ " or "🧑 ") .. "<b>" .. esc(r.name) .. "</b> — поймано: " .. r.caught .. " · " .. r.money .. " 💰 · " .. esc(r.where or ""),
			{ bg = r.me and color("#fff3bf") or C.panel2, size = 15 })
	end
	local tr, hd = res.train or {}, res.holiday or {}
	Kit.h(B, "Скоро")
	Kit.text(B, "🚂 Поезд с лошадьми в пустыне: " .. (tr.catchLeft and "стоит у станции — лови!" or tr.moving and "едет!" or ("через " .. mmss(tr.next or 0))))
	Kit.text(B, "🎉 Праздник: " .. (hd.k and (hd.icon .. " " .. hd.name .. " — ещё " .. mmss(hd.left)) or ("через " .. mmss(hd.next or 0) .. " (Хэллоуин, Новый год или Пасха)")))
	Kit.button(Kit.row(B), "🔄 Обновить", function() open("players", {}) end, { small = true })
	return "👥 Игроки"
end

--[[ ================= повозка: корм и амуниция ================= ]]
local function dyeShop(B, k)
	local P = State.P
	for _, key in ipairs(Items.DYE_ORDER) do
		local dd = Items.DYES[key]
		local price = math.floor(dd.price * k + 0.5)
		Kit.item(B, dd.color == "rainbow" and "🌈" or "🎨", dd.name, price .. " 💰 · есть " .. (P.inv[dd.item] or 0), function(f)
			Kit.swatch(f, dd.color, false)
			Kit.button(f, "Купить", function() act("buyItem", dd.item, 1) end, { small = true })
		end)
	end
end
local function tackStyles(B)
	local t = State.P.tack
	for _, kv in ipairs({ { "saddle", "Сёдла" }, { "bridle", "Уздечки" } }) do
		local kind = kv[1]
		Kit.h(B, kv[2])
		if not t[kind] then
			Kit.small(B, "Сначала купи " .. (kind == "saddle" and "обычное седло" or "обычную уздечку") .. " в разделе «Амуниция» ниже.")
		else
			for _, key in ipairs(Items.TACK_STYLE_ORDER) do
				local st = Items.TACK_STYLES[key]
				local own, on = t[kind .. "Styles"][key], t[kind .. "Style"] == key
				Kit.item(B, st.icon, st.name, st.desc, function(f)
					Kit.button(f, on and "надето ✔" or own and "Надеть" or (st[kind] .. " 💰"), function() act("tackStyle", kind, key) end, { small = true, color = own and nil or "green", active = on })
				end)
			end
			Kit.small(B, "Цвет " .. (kind == "saddle" and "седла" or "уздечки") .. ":")
			local r = Kit.row(B)
			for _, c in ipairs(Items.LEATHER) do Kit.swatch(r, c, t[kind .. "Color"] == c, function() act("tackColor", kind, c) end) end
		end
	end
end
-- окно «Седло и уздечка»: стиль и цвет седла, уздечки, вальтрапа и ногавок — с примеркой на лошади
local function tackLook(t)
	return {
		pad = t.pad or "#7a6a55", saddleStyle = t.saddleStyle or "classic", saddleColor = t.saddleColor or "#5b3a1e",
		bridleStyle = t.bridleStyle or "classic", bridleColor = t.bridleColor or "#2b1a10", boots = t.boots or nil,
	}
end
views.tack = function(B, d)
	local P = State.P
	local t = P.tack
	local h = d.id and State.byId(d.id) or nil
	if not h then
		for _, q in ipairs(P.horses) do
			if q.state == "ridden" then h = q break end
		end
	end
	h = h or P.horses[1]
	if d.id then Kit.button(Kit.row(B), "← К лошади", function() open("horse", { id = d.id }) end, { color = "ghost" }) end
	if h then Kit.portrait(Kit.row(B), Horses.look(h), 420, 220, tackLook(t)) end
	if not t.saddle and not t.bridle then
		Kit.note(B, "Седло и уздечка продаются в повозке «Корм и амуниция». Купи их — и здесь можно будет выбрать цвета.")
	end
	for _, kv in ipairs({ { "saddle", "🏇 Седло" }, { "bridle", "➰ Уздечка" } }) do
		local kind = kv[1]
		if t[kind] then
			Kit.h(B, kv[2])
			Kit.small(B, "Цвет кожи:")
			local r = Kit.row(B)
			for _, c in ipairs(Items.LEATHER) do Kit.swatch(r, c, t[kind .. "Color"] == c, function() act("tackColor", kind, c) end) end
			local sr = Kit.row(B)
			for _, key in ipairs(Items.TACK_STYLE_ORDER) do
				local st = Items.TACK_STYLES[key]
				if t[kind .. "Styles"] and t[kind .. "Styles"][key] then
					local on = t[kind .. "Style"] == key
					Kit.button(sr, st.icon .. " " .. st.name .. (on and " ✔" or ""), function() act("tackStyle", kind, key) end, { small = true, active = on })
				end
			end
		end
	end
	for _, k in ipairs({ "pad", "boots" }) do
		if t[k] then
			Kit.h(B, Items.TACK[k].icon .. " " .. Items.TACK[k].name)
			local r = Kit.row(B)
			for _, c in ipairs(Items.COLORS) do Kit.swatch(r, c, t[k] == c, function() act("color", k, c) end) end
		end
	end
	Kit.small(B, "Новые стили сёдел и уздечек (кристальные, цветочные, ракушечные) покупаются в повозке «Корм и амуниция».")
	return "🐴 Седло и уздечка"
end

views.shop = function(B)
	local P = State.P
	Kit.text(B, "У тебя: <b>" .. P.money .. " 💰</b>")
	Kit.h(B, "Корм и лакомства")
	for _, k in ipairs(Items.FOOD_ORDER) do
		local f = Items.FOOD[k]
		Kit.item(B, f.icon, f.name, f.price .. " 💰 · есть " .. (P.inv[k] or 0) .. (f.bait and " · приманка для лассо" or ""), function(fr)
			Kit.button(fr, "+1", function() act("buyFood", k, 1) end, { small = true })
			Kit.button(fr, "+5", function() act("buyFood", k, 5) end, { small = true })
		end)
	end
	Kit.h(B, "Для ухода и жеребят")
	Kit.item(B, "🔧", "Новые подковы (4 шт.)", "25 💰 · есть " .. (P.inv.horseshoes or 0) .. " · подковать — мини-игра у лошади", function(f)
		Kit.button(f, "+1", function() act("buyItem", "horseshoes", 1) end, { small = true })
	end)
	Kit.h(B, "Краски для гривы")
	dyeShop(B, 1.2)
	tackStyles(B)
	Kit.h(B, "Амуниция")
	for _, k in ipairs(Items.TACK_ORDER) do
		local t = Items.TACK[k]
		local own = P.tack[k]
		Kit.item(B, t.icon, t.name, t.desc, function(f)
			if own and t.colors then
				for _, c in ipairs(Items.COLORS) do Kit.swatch(f, c, own == c, function() act("color", k, c) end) end
			end
			if not own then Kit.button(f, t.price .. " 💰", function() act("buyTack", k) end, { small = true, color = "green" })
			else Kit.text(f, "есть ✔", { width = 0, widthOffset = 60, color = color("#2b8a3e"), bold = true }) end
		end)
	end
	return "🛒 Повозка «Корм и амуниция»"
end

--[[ ================= лодка ================= ]]
views.boat = function(B, d)
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	local here = "farm"
	if r then here = World.regionAt(World.fromStuds(r.Position)) end
	local t = math.ceil((d.islandT or 300) / 60)
	Kit.text(B, "Куда плывём? На каждом острове есть конюшня на 5 денников, пастбище, круглый манеж и 5 диких лошадей. Лошади на островах меняются каждые 5 минут (следующая смена ≈ через " .. t .. " мин).")
	local dests = { { id = "main", name = "Большая земля (пристань у Грибного королевства)" } }
	for _, I in ipairs(World.ISLANDS) do table.insert(dests, { id = I.id, name = I.name }) end
	local onIsland = string.sub(here, 1, 1) == "i" and #here == 2
	for _, dd in ipairs(dests) do
		if dd.id ~= here and not (dd.id == "main" and not onIsland) then
			local I = Util.find(World.ISLANDS, function(q) return q.id == dd.id end)
			local kinds = "ферма, поля, лес, горы"
			if I then
				local seen, list = {}, {}
				for _, b in ipairs(I.breeds) do
					local n = Genetics.BREEDS[b].name
					if not seen[n] then seen[n] = true; table.insert(list, n) end
				end
				kinds = table.concat(list, ", ")
			end
			Kit.item(B, "⛵", dd.name, kinds, function(f) Kit.button(f, "Плыть", function() act("sail", dd.id) end, { color = "green" }) end)
		end
	end
	Kit.small(B, "Лошадь под седлом и пойманная на верёвке плывут вместе с тобой.")
	return "⛵ Лодка"
end

--[[ ================= повозка: продажа ================= ]]
views.sell = function(B, d)
	local P = State.P
	local res = d.res
	if not res then
		task.spawn(function()
			local r = State.query("prices")
			if current and current.name == "sell" then open("sell", { res = r or {} }) end
		end)
		Kit.text(B, "Загрузка…")
		return "💰 Повозка «Продажа лошадей»"
	end
	local near = res.nearSell
	if res.fair then Kit.note(B, "🎪 Сейчас ярмарка — цены на 30% выше!") end
	Kit.text(B, near and "Торговец купит твоих лошадей. Цена зависит от навыков, редкости окраса, возраста и ухода." or "Подойди к повозке «Продажа лошадей», чтобы продать.")
	local list = {}
	if res.led then table.insert(list, { h = res.led, led = true }) end
	for _, h in ipairs(P.horses) do
		if h.state ~= "ridden" then table.insert(list, { h = h }) end
	end
	if #list == 0 then Kit.text(B, "Пока нечего продавать.") end
	local grid = Kit.grid(B)
	for _, it in ipairs(list) do
		local h = it.h
		local price = it.led and (res.prices and res.prices.led) or (res.prices and res.prices[tostring(h.id)]) or sellPrice(h, it.led)
		horseCard(grid, h, function(card)
			if it.led then Kit.small(card, "(пойманная)") end
			Kit.button(card, "Продать за " .. price .. " 💰", function()
				act("sell", h.id, it.led == true)
				task.delay(0.4, function() if current and current.name == "sell" then open("sell", {}) end end)
			end, { small = true, color = "green", disabled = not near })
		end)
	end
	Kit.h(B, "Урожай, грибы и находки")
	local any = false
	for _, k in ipairs(Items.ITEM_ORDER) do
		local n = P.inv[k] or 0
		local it = Items.ITEMS[k]
		if n > 0 and it and it.sell >= 10 then
			any = true
			Kit.item(B, it.icon, it.name, it.sell .. " 💰 · есть " .. n, function(f)
				Kit.button(f, "Продать 1", function() act("sellItem", k, 1) end, { small = true, color = "green", disabled = not near })
				if n > 1 then Kit.button(f, "Все (" .. n * it.sell .. " 💰)", function() act("sellItem", k, n) end, { small = true, disabled = not near }) end
			end)
		end
	end
	if not any then Kit.small(B, "Тыквы, подсолнухи, грибы и клады тоже можно продать.") end
	return "💰 Повозка «Продажа лошадей»"
end

--[[ ================= рынок ================= ]]
local TABS = { { "horses", "🐎 Конский торговец" }, { "trainer", "💪 Тренер" }, { "swap", "🔁 Обменщик" }, { "mine", "🏷️ Моя стойка" }, { "others", "🧑 Стойки игроков" } }
views.market = function(B, d)
	local P = State.P
	local tab = d.tab or "horses"
	local tr = Kit.row(B)
	for _, t in ipairs(TABS) do
		Kit.button(tr, t[2], function() open("market", { tab = t[1] }) end, { small = true, active = t[1] == tab, color = t[1] == tab and nil or "ghost" })
	end
	Kit.text(B, "У тебя: <b>" .. P.money .. " 💰</b>")
	local m = type(P.market) == "table" and P.market or { stock = {}, items = {}, log = {} }
	if tab == "horses" then
		Kit.text(B, "Конский торговец Ахмед: «Лучшие лошади со всего света! Не нравится цена — торгуйся!» <font size=\"12\">Новые лошади ≈ через " .. math.ceil((m.refreshT or 0) / 60) .. " мин.</font>")
		if m.say and m.say ~= "" then Kit.note(B, "💬 " .. esc(m.say)) end
		local grid = Kit.grid(B)
		for _, h in ipairs(m.stock or {}) do
			horseCard(grid, h, function(card)
				Kit.text(card, "Цена: <b>" .. h.ask .. " 💰</b>", { size = 14 })
				Kit.button(card, "Купить", function() act("mkBuy", h.id) end, { small = true, color = "green", disabled = P.money < h.ask })
				if (h.haggles or 0) > 0 then
					local r = Kit.row(card)
					Kit.small(r, "Торг (" .. h.haggles .. "):")
					for _, f in ipairs({ 0.9, 0.8, 0.7 }) do
						Kit.button(r, "−" .. math.floor((1 - f) * 100 + 0.5) .. "%", function() act("mkHaggle", h.id, f) end, { small = true })
					end
				else
					Kit.small(card, "торг окончен")
				end
			end, { skills = true })
		end
		Kit.small(B, "Чем больше скидку просишь, тем реже торговец соглашается. Три отказа — и он поднимет цену!")
	elseif tab == "trainer" then
		Kit.text(B, "Тренер Олег: «За монетки подтяну любой навык твоей лошади. Чем навык выше — тем дороже занятие».")
		local list = Util.filter(P.horses, function(h) return Horses.isAdult(h) end)
		if #list == 0 then Kit.text(B, "Взрослых лошадей пока нет — тренировать некого.") end
		local h = d.pick and State.byId(d.pick)
		if not h then
			local grid = Kit.grid(B)
			for _, x in ipairs(list) do
				horseCard(grid, x, function(card) Kit.button(card, "💪 Тренировать", function() open("market", { tab = "trainer", pick = x.id }) end, { small = true, color = "green" }) end, { skills = true })
			end
		else
			Kit.button(Kit.row(B), "← Другая лошадь", function() open("market", { tab = "trainer" }) end, { small = true, color = "ghost" })
			local row = Kit.row(B, { gap = 12 })
			horseCard(row, h)
			local c = Kit.col(row, { width = 0, widthOffset = 380 })
			for _, k in ipairs(Horses.SKILL_ORDER) do
				Kit.skillBar(c, h, k)
				local max = Horses.skill(h, k) >= 100 or h.base[k] + h.train[k] >= 100
				local pr = Util.round5(20 + Horses.skill(h, k) * 1.6)
				Kit.button(c, max and "максимум" or ("+3 за " .. pr .. " 💰"), function() act("mkTrain", h.id, k) end, { small = true, color = max and nil or "green", disabled = max or P.money < pr })
			end
			Kit.h(c, "Отдых и уход")
			Kit.bar(c, "Энергия", h.energy)
			Kit.bar(c, "Настроение", h.mood)
			Kit.button(c, "🧖 Массаж и мытьё — 25 💰", function() act("mkSpa", h.id) end, { disabled = P.money < 25 })
		end
	elseif tab == "swap" then
		Kit.text(B, "Обменщица Фрося: «Меняю что угодно на что угодно! Лошадь на лошадь — с доплатой, вещи на вещи — честно».")
		Kit.h(B, "🔁 Лошадь на лошадь")
		local res = d.res
		if not res then
			task.spawn(function()
				local r = State.query("market")
				if current and current.name == "market" and current.data.tab == "swap" then
					local nd = table.clone(current.data)
					nd.res = r or {}
					open("market", nd)
				end
			end)
			Kit.text(B, "Загрузка…")
		else
			local mine = Util.filter(P.horses, function(h) return h.state == "stall" or h.state == "paddock" end)
			local sv = res.swapValues or {}
			if #mine == 0 then Kit.small(B, "Сначала заведи свою лошадь.")
			elseif not d.pick or not State.byId(d.pick) then
				Kit.small(B, "Выбери, какую свою лошадь отдаёшь:")
				local grid = Kit.grid(B)
				for _, h in ipairs(mine) do
					horseCard(grid, h, function(card)
						Kit.small(card, "Оценка: " .. tostring(sv[tostring(h.id)] or "?") .. " 💰")
						Kit.button(card, "Отдать", function()
							local nd = { tab = "swap", pick = h.id, res = res }
							open("market", nd)
						end, { small = true })
					end)
				end
			else
				local h = State.byId(d.pick)
				local val = sv[tostring(h.id)] or 0
				local r = Kit.row(B)
				Kit.text(r, "Отдаёшь: <b>" .. esc(h.name) .. "</b> (оценка " .. val .. " 💰).", { width = 0, widthOffset = 360 })
				Kit.button(r, "Выбрать другую", function() open("market", { tab = "swap", res = res }) end, { small = true, color = "ghost" })
				local grid = Kit.grid(B)
				for _, t in ipairs(m.stock or {}) do
					local diff = t.ask - val
					local txt = diff > 0 and ("доплатить " .. diff .. " 💰") or diff < 0 and ("тебе доплатят " .. (-diff) .. " 💰") or "без доплаты"
					horseCard(grid, t, function(card)
						Kit.button(card, "🔁 Обменять (" .. txt .. ")", function() act("mkSwap", h.id, t.id) end, { small = true, color = "green", disabled = diff > P.money })
					end)
				end
			end
		end
		Kit.h(B, "🔁 Вещи на вещи")
		local SWAPS = {
			{ id = "s1", give = { mushroom = 5 }, get = { pollen = 1 } }, { id = "s2", give = { glowshroom = 3 }, get = { dye_rainbow = 1 } },
			{ id = "s3", give = { pumpkin = 2 }, get = { oats = 10 } }, { id = "s4", give = { carrot = 10 }, get = { dye_pink = 1 } },
			{ id = "s5", give = { oldCoin = 1, spoon = 1 }, get = { dye_gold = 1 } }, { id = "s6", give = { sunflower = 3 }, get = { apple = 10 } },
			{ id = "s7", give = { pollen = 2 }, get = { dye_purple = 1, dye_mint = 1 } }, { id = "s8", give = { oldShoe = 3 }, get = { sugar = 15 } },
		}
		local function fmt(o)
			local parts = {}
			for _, k in ipairs(Util.keys(o)) do table.insert(parts, Items.icon(k) .. " " .. Items.name(k) .. " ×" .. o[k]) end
			return table.concat(parts, " + ")
		end
		for _, sw in ipairs(SWAPS) do
			local can, have = true, {}
			for _, k in ipairs(Util.keys(sw.give)) do
				if (P.inv[k] or 0) < sw.give[k] then can = false end
				table.insert(have, Items.icon(k) .. (P.inv[k] or 0))
			end
			Kit.item(B, "🔁", fmt(sw.give), "→ " .. fmt(sw.get) .. " · у тебя: " .. table.concat(have, " "), function(f)
				Kit.button(f, "Обменять", function() act("mkSwapItem", sw.id) end, { small = true, color = can and "green" or nil, disabled = not can })
			end)
		end
	elseif tab == "mine" then
		Kit.text(B, "Твоя стойка: выставь лошадей (до 3) и вещи по своей цене. Покупатели подходят сами, даже когда тебя нет рядом. Дорого — покупают редко, а иногда торгуются. Другие игроки тоже могут купить твоих лошадей!")
		local o = m.offer
		if type(o) == "table" then
			local box = Kit.col(B, { bg = C.note })
			Kit.text(box, "🗣️ <b>" .. esc(o.buyer) .. "</b> предлагает <b>" .. o.price .. " 💰</b> за «" .. esc(o.name) .. "» (ждёт ещё " .. math.ceil(o.t) .. " с)")
			local r = Kit.row(box)
			Kit.button(r, "🤝 Согласиться", function() act("mkOffer", true) end, { small = true, color = "green" })
			Kit.button(r, "Нет, дёшево", function() act("mkOffer", false) end, { small = true })
		end
		Kit.h(B, "На прилавке")
		local any = false
		for _, h in ipairs(P.horses) do
			if h.state == "market" then
				any = true
				local value = sellPrice(h)
				local ratio = h.ask / math.max(1, value)
				local tag = ratio <= 1.1 and "😀 купят быстро" or ratio <= 1.4 and "🙂 купят" or ratio <= 1.8 and "🤔 дороговато" or "😬 очень дорого"
				Kit.item(B, "🐴", esc(h.name), "цена " .. h.ask .. " 💰 · обычно ≈ " .. value .. " 💰 · " .. tag, function(f)
					Kit.button(f, "−10%", function() act("mkPrice", h.id, "horse", 0.9) end, { small = true })
					Kit.button(f, "+10%", function() act("mkPrice", h.id, "horse", 1.1) end, { small = true })
					Kit.button(f, "Снять", function() act("mkUnlist", h.id, "horse") end, { small = true, color = "ghost" })
				end)
			end
		end
		for _, k in ipairs(Util.keys(m.items or {})) do
			local l = m.items[k]
			if l.n > 0 then
				any = true
				local it = Items.ITEMS[k]
				local value = math.max(1, (it and it.sell ~= 0 and it.sell) or 1) * fairMul()
				local ratio = l.price / math.max(1, value)
				local tag = ratio <= 1.1 and "😀 купят быстро" or ratio <= 1.4 and "🙂 купят" or ratio <= 1.8 and "🤔 дороговато" or "😬 очень дорого"
				Kit.item(B, Items.icon(k), Items.name(k) .. (l.n > 1 and (" ×" .. l.n) or ""), "цена " .. l.price .. " 💰 за штуку · обычно ≈ " .. math.floor(value + 0.5) .. " 💰 · " .. tag, function(f)
					Kit.button(f, "−10%", function() act("mkPrice", k, "item", 0.9) end, { small = true })
					Kit.button(f, "+10%", function() act("mkPrice", k, "item", 1.1) end, { small = true })
					Kit.button(f, "Снять", function() act("mkUnlist", k, "item") end, { small = true, color = "ghost" })
				end)
			end
		end
		if not any then Kit.small(B, "Пока пусто.") end
		Kit.h(B, "Выставить лошадь")
		local can = Util.filter(P.horses, function(h) return h.state == "stall" or h.state == "paddock" end)
		if #can > 0 then
			local r = Kit.row(B)
			for _, h in ipairs(can) do
				Kit.button(r, Kit.sexIcon(h) .. " " .. esc(h.name) .. " <font size=\"12\">≈" .. sellPrice(h) .. " 💰</font>", function() act("mkList", h.id) end, { small = true })
			end
		else
			Kit.small(B, "Нет свободных лошадей.")
		end
		Kit.h(B, "Выставить вещи")
		local goods = false
		for _, k in ipairs(Items.ITEM_ORDER) do
			local n = P.inv[k] or 0
			local it = Items.ITEMS[k]
			if n > 0 and it and it.sell > 0 then
				goods = true
				Kit.item(B, it.icon, it.name, "есть " .. n .. " · обычно ≈ " .. it.sell .. " 💰", function(f)
					Kit.button(f, "+1", function() act("mkListItem", k, 1) end, { small = true })
					if n > 1 then Kit.button(f, "Все", function() act("mkListItem", k, n) end, { small = true }) end
				end)
			end
		end
		if not goods then Kit.small(B, "В рюкзаке нечего продавать.") end
		if m.log and #m.log > 0 then
			Kit.h(B, "Последние продажи")
			for _, x in ipairs(m.log) do Kit.small(B, "• " .. esc(x)) end
		end
	else
		Kit.text(B, "Лошади, которых другие игроки выставили на своих стойках. Деньги получит хозяйка лошади.")
		local res = d.res
		if not res then
			task.spawn(function()
				local r = State.query("market")
				if current and current.name == "market" and current.data.tab == "others" then open("market", { tab = "others", res = r or {} }) end
			end)
			Kit.text(B, "Загрузка…")
		else
			local list = res.others or {}
			if #list == 0 then Kit.small(B, "Сейчас никто ничего не продаёт.") end
			local grid = Kit.grid(B)
			for _, o in ipairs(list) do
				horseCard(grid, o.horse, function(card)
					Kit.small(card, "Продаёт: " .. esc(o.sellerName))
					Kit.text(card, "Цена: <b>" .. o.price .. " 💰</b>", { size = 14 })
					Kit.button(card, "Купить", function()
						act("mkBuyPlayer", o.seller, o.horse.id)
						task.delay(0.5, function() if current and current.name == "market" then open("market", { tab = "others" }) end end)
					end, { small = true, color = "green", disabled = P.money < o.price })
				end, { skills = true })
			end
			Kit.button(Kit.row(B), "🔄 Обновить", function() open("market", { tab = "others" }) end, { small = true })
		end
	end
	return "🎪 Рынок"
end

--[[ ================= рюкзак ================= ]]
views.inventory = function(B)
	local P = State.P
	local st = P.stats
	Kit.text(B, "Монеты: <b>" .. P.money .. " 💰</b>")
	Kit.h(B, "В рюкзаке")
	local r = Kit.row(B)
	local any = false
	for _, k in ipairs(Items.ITEM_ORDER) do
		if (P.inv[k] or 0) > 0 then
			any = true
			Kit.text(r, Items.icon(k) .. " " .. Items.name(k) .. ": " .. P.inv[k], { width = 0, widthOffset = 230, bg = C.panel2, size = 14 })
		end
	end
	if not any then Kit.small(r, "пусто") end
	Kit.h(B, "Амуниция")
	local tr = Kit.row(B)
	for _, k in ipairs(Items.TACK_ORDER) do
		if P.tack[k] then Kit.text(tr, Items.TACK[k].icon .. " " .. Items.TACK[k].name, { width = 0, widthOffset = 170, bg = C.panel2, size = 14 }) end
	end
	Kit.text(tr, "➰ Простое лассо", { width = 0, widthOffset = 170, bg = C.panel2, size = 14 })
	Kit.button(Kit.row(B), "🐴 Седло и уздечка — цвета", function() open("tack", {}) end, { small = true })
	Kit.h(B, "Моя кофта")
	local sr = Kit.row(B)
	for _, c in ipairs(Items.SHIRTS) do Kit.swatch(sr, c, P.shirt == c, function() act("shirt", c) end) end
	Kit.h(B, "Достижения")
	local ach = {
		"🤠 Поймано: " .. (st.caught or 0), "🐰 Зайчиков: " .. (st.bunnies or 0), "🏁 Скачек: " .. (st.races or 0) .. ", побед: " .. (st.wins or 0),
		"🍼 Жеребят: " .. (st.foals or 0), "💰 Продано: " .. (st.sold or 0), "🥇 " .. (st.gold or 0), "🥈 " .. (st.silver or 0), "🥉 " .. (st.bronze or 0),
		"⛏️ Кладов: " .. (st.treasures or 0), "🍄 Грибов: " .. (st.mushrooms or 0),
		"📜 Заданий: " .. (st.questsDone or 0), "👻 Привидений: " .. (st.ghosts or 0),
	}
	local ar = Kit.row(B)
	for _, a in ipairs(ach) do Kit.text(ar, a, { width = 0, widthOffset = 190, bg = C.panel2, size = 14 }) end
	return "🎒 Рюкзак"
end

--[[ ================= тренировка и конкур ================= ]]
local function cardButton(B, title, desc, fn)
	local f = make("TextButton", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel2, Text = "", AutoButtonColor = true, LayoutOrder = Kit.nextOrder(), Parent = B })
	Kit.corner(f, 10)
	Kit.pad(f, 8)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	Kit.text(f, "<b>" .. title .. "</b>", { size = 17 })
	Kit.text(f, desc, { size = 14, color = C.muted })
	f.Activated:Connect(fn)
	return f
end
views.training = function(B)
	local m = State.mounted()
	if not m then
		Kit.text(B, "Сначала сядь на лошадь.")
		return "Тренировка"
	end
	Kit.text(B, "Тренируешь: <b>" .. esc(m.name) .. "</b> · энергия " .. math.floor(m.energy) .. "%")
	Kit.skillBar(B, m, "jump")
	Kit.skillBar(B, m, "dressage")
	cardButton(B, "🚧 Кавалетти", "5 жердей на земле. Едь по ним <b>рысью</b> слева направо и прямо перед каждой жердью жми <b>«Ноги выше!»</b> (Пробел). Развивает прыжки.", function() act("train", "cav") end)
	cardButton(B, "🎠 Выездка: " .. Items.TESTS.easy.name, "Езди от буквы к букве нужным аллюром: шаг и рысь. Остановка в X — приветствие судьям.", function() act("train", "easy") end)
	cardButton(B, "🏆 Выездка: " .. Items.TESTS.canter.name, "Шаг, рысь и галоп. Сложнее, но и награда больше!", function() act("train", "canter") end)
	return "🏆 Тренировка в манеже"
end
views.jumping = function(B)
	local m = State.mounted()
	if not m then
		Kit.text(B, "Сначала сядь на лошадь.")
		return "Конкур"
	end
	local comfy = math.floor((50 + Horses.skill(m, "jump") * 0.7) / 5 + 0.5) * 5
	Kit.text(B, "Конкур — это прыжки через препятствия по порядку номеров. Едь <b>галопом</b>, проходи препятствия в сторону стрелки (красная стойка справа, белая — слева) и жми <b>«Прыжок!»</b> (Пробел) прямо перед жердями.")
	Kit.text(B, "За повал жерди — 4 штрафных очка, за отказ — тоже 4 (после трёх отказов — исключение). Норма времени — 75 секунд: за каждые начатые 4 секунды сверху — 1 штрафное очко.")
	Kit.text(B, "<b>" .. esc(m.name) .. "</b>: прыжки " .. Horses.skill(m, "jump") .. ", энергия " .. math.floor(m.energy) .. "%. Удобная высота — около <b>" .. comfy .. " см</b>.")
	for _, hgt in ipairs({ 60, 80, 100, 120 }) do
		local desc = (hgt <= comfy and "по силам ✔" or hgt - comfy <= 15 and "сложно, но можно" or "очень высоко!") .. (hgt == 60 and " · можно рысью" or "")
		cardButton(B, hgt .. " см", desc, function() act("jump", hgt) end)
	end
	return "🏆 Конкур"
end

local function resultBox(B, medal, big)
	Kit.text(B, medal and Items.MEDALS[medal] or "🙂", { size = 56, center = true })
	if big then Kit.text(B, big, { size = 26, bold = true, center = true }) end
end
views.jumpResult = function(B, r)
	resultBox(B, r.medal or (r.eliminated and nil), r.eliminated and "Исключение" or (r.faults .. " штр. оч."))
	if r.eliminated then Kit.text(B, "Три отказа — так бывает. Подъезжай к препятствию галопом и не останавливайся!", { center = true })
	else Kit.text(B, r.faults == 0 and "Чистый маршрут! Браво!" or r.faults <= 4 and "Почти идеально!" or "Хороший опыт — тренируйся ещё!", { center = true }) end
	Kit.text(B, "Чисто пройдено: <b>" .. r.clean .. " из " .. r.total .. "</b>", { center = true })
	Kit.text(B, "Время: <b>" .. string.format("%.1f", r.t) .. " с</b> (норма " .. r.norm .. " с" .. (r.over > 0 and (", +" .. r.over .. " за время") or "") .. ")", { center = true })
	Kit.text(B, "Награда: <b>" .. r.money .. " 💰</b> · Прыжки: " .. r.skill, { center = true })
	Kit.button(Kit.row(B, { center = true }), "Отлично!", function() Win.close() end, { big = true, color = "green" })
	return "Конкур " .. r.height .. " см: результат"
end
views.result = function(B, r)
	resultBox(B, r.medal)
	Kit.text(B, "Чисто пройдено жердей: <b>" .. r.clean .. " из " .. r.total .. "</b>", { center = true })
	Kit.text(B, r.clean == r.total and "Великолепно! Ни одной сбитой жерди!" or r.clean >= 3 and "Хорошо! Попробуй пройти все жерди чисто." or "Не сдавайся — держи рысь и жми вовремя.", { center = true })
	Kit.text(B, "Награда: <b>" .. r.money .. " 💰</b> · " .. r.extra, { center = true })
	Kit.button(Kit.row(B, { center = true }), "Отлично!", function() Win.close() end, { big = true, color = "green" })
	return r.title .. ": результат"
end
views.dressageResult = function(B, r)
	resultBox(B, r.medal, string.format("%.1f%%", r.pct))
	Kit.text(B, r.pct >= 70 and "Судьи в восторге!" or r.pct >= 60 and "Очень хорошая езда!" or r.pct >= 50 and "Неплохо! Следи за аллюрами." or "Тренируйся: держи нужный аллюр на каждом отрезке.", { center = true })
	for _, mk in ipairs(r.marks or {}) do Kit.text(B, esc(mk.text) .. " — <b>" .. mk.mark .. "</b>", { size = 14 }) end
	Kit.text(B, "Награда: <b>" .. r.money .. " 💰</b> · Выездка: " .. r.skill, { center = true })
	Kit.button(Kit.row(B, { center = true }), "Отлично!", function() Win.close() end, { big = true, color = "green" })
	return "Выездка: " .. r.name
end
views.raceResult = function(B, r)
	local names = { "первое", "второе", "третье", "четвёртое", "пятое", "шестое", "седьмое", "восьмое" }
	resultBox(B, r.medal, (names[r.place] or tostring(r.place)) .. " место!")
	Kit.text(B, r.place == 1 and "Победа! Ты обогнала всех!" or r.place <= 3 and "Отличный результат!" or "В следующий раз получится — тренируй скорость!", { center = true })
	for i, x in ipairs(r.table or {}) do
		Kit.text(B, i .. ". " .. (x.me and "<b>" or "") .. esc(x.name) .. " — " .. esc(x.horse) .. " — " .. (x.done and string.format("%.1f с", x.done) or "ещё скачет") .. (x.me and "</b>" or ""), { size = 15 })
	end
	Kit.text(B, "Время: <b>" .. string.format("%.1f", r.time) .. " с</b> · приз: <b>" .. r.prize .. " 💰</b>" .. (r.bonus > 1 and " (двойной!)" or ""), { center = true })
	Kit.button(Kit.row(B, { center = true }), "Ура!", function() Win.close() end, { big = true, color = "green" })
	return "🏁 Скачки: результат"
end

--[[ ================= жители и задания ================= ]]
local function questCard(B, q, st, actions)
	local box = Kit.col(B, { bg = C.panel2 })
	Kit.text(box, "<b>" .. esc(q.title) .. "</b>")
	Kit.text(box, esc(q.text), { size = 14 })
	if st then
		local p = Q.progress(State.P, q, st)
		Kit.bar(box, "Прогресс " .. math.floor(p.cur) .. "/" .. p.need, p.cur / p.need * 100, "#69db7c")
	end
	Kit.small(box, "Награда: " .. Q.rewardText(q.reward))
	if actions then actions(box) end
end
views.npc = function(B, d)
	local n = Q.npcById(d.id)
	if not n then return "Житель" end
	local P = State.P
	Kit.text(B, (n.ghost and "👻" or n.fairy and "🧚" or "👩") .. "  «" .. esc(d.line or n.hello[1]) .. "»", { size = 17, bg = C.note })
	local c = Q.current(P, n.id)
	if c and not c.st then
		Kit.h(B, "❗ У меня есть для тебя задание")
		questCard(B, c.q, nil, function(box) Kit.button(box, "Возьмусь!", function() act("qAccept", c.q.id) end, { color = "green" }) end)
	elseif c and c.st then
		local done = Q.complete(P, c.q, c.st)
		Kit.h(B, done and "❓ Задание выполнено?" or "Твоё задание")
		questCard(B, c.q, c.st, function(box)
			if done then Kit.button(box, "🎁 Сдать задание", function() act("qTurnIn", c.q.id) end, { color = "green" }) end
		end)
	else
		Kit.text(B, "Ты выполнила все мои задания — спасибо! 💛")
	end
	local r = Kit.row(B)
	Kit.button(r, "💡 Дай совет", function() act("npcTip", n.id) end)
	if n.shop then Kit.button(r, "🎨 Купить краску", function() open("lola", {}) end, { color = "pink" }) end
	Kit.button(r, "Пока!", function() Win.close() end, { color = "ghost" })
	return "💬 " .. n.name .. " — " .. n.role
end
views.lola = function(B)
	Kit.text(B, "У тебя: <b>" .. State.P.money .. " 💰</b>. У меня дешевле, чем в повозке!")
	dyeShop(B, 1)
	Kit.small(B, "Покрасить гриву: открой лошадь в конюшне → «💇 Грива».")
	Kit.button(Kit.row(B), "← Назад", function() open("npc", { id = "lola" }) end, { color = "ghost" })
	return "🎨 Краски для гривы у Лолы"
end
views.board = function(B)
	local P = State.P
	local b = Q.boardQuest(P)
	Kit.text(B, "Задания для всех жителей. Выполнишь одно — появится новое.")
	if not b then
		Kit.text(B, "Загрузка…")
	elseif not b.st then
		questCard(B, b.q, nil, function(box) Kit.button(box, "Возьмусь!", function() act("boardAccept") end, { color = "green" }) end)
	else
		local done = Q.complete(P, b.q, b.st)
		questCard(B, b.q, b.st, function(box)
			if done then Kit.button(box, "🎁 Получить награду", function() act("boardTurnIn") end, { color = "green" }) end
		end)
	end
	return "📋 Доска заданий"
end
views.quests = function(B)
	local P = State.P
	local list = Q.journal(P)
	if #list == 0 then Kit.text(B, "Пока нет заданий. Поговори с жителями: на ферме — тренер Дядя Миша, на полях — бабушка Галя, в деревне — кузнец, стилистка и доска заданий.") end
	for _, it in ipairs(list) do
		Kit.small(B, esc(it.npcName))
		questCard(B, it.q, it.st, function(box)
			if it.done then Kit.text(box, "✔ Готово — вернись и сдай задание", { color = color("#2b8a3e"), bold = true, size = 14 }) end
		end)
	end
	Kit.small(B, "Выполнено заданий: " .. Q.doneCount(P) .. " из " .. #Q.QUESTS .. ".")
	Kit.h(B, "Жители")
	local r = Kit.row(B)
	for _, n in ipairs(Q.NPCS) do Kit.text(r, Q.marker(P, n.id) .. " " .. esc(n.name), { width = 0, widthOffset = 200, bg = C.panel2, size = 14 }) end
	return "📜 Задания"
end

views.mane = function(B, d)
	local P = State.P
	local h = State.byId(d.id)
	if not h then return "Грива" end
	Kit.button(Kit.row(B), "← Назад", function() open("horse", { id = h.id, can = true }) end, { color = "ghost" })
	Kit.portrait(B, Horses.look(h), 300, 160)
	Kit.h(B, "Причёска — бесплатно")
	local r = Kit.row(B)
	for _, k in ipairs(Items.MANE_ORDER) do
		local ms = Items.MANE_STYLES[k]
		Kit.button(r, ms.icon .. " " .. ms.name, function() act("maneStyle", h.id, k) end, { active = h.maneStyle == k })
	end
	Kit.h(B, "Цвет гривы и хвоста")
	local r2 = Kit.row(B)
	Kit.button(r2, "🐴 Свой цвет", function() act("maneDye", h.id, "") end, { active = not h.maneDye })
	for _, k in ipairs(Items.DYE_ORDER) do
		local dd = Items.DYES[k]
		local n = P.inv[dd.item] or 0
		Kit.button(r2, (dd.color == "rainbow" and "🌈 " or "🎨 ") .. dd.name .. " ×" .. n, function() act("maneDye", h.id, k) end, { active = h.maneDye == k, disabled = n == 0 and h.maneDye ~= k })
	end
	Kit.small(B, "Краски покупают у стилистки Лолы в деревне или в повозке, а иногда находят в кладах. Одна краска — на одну покраску.")
	return "💇 Грива: " .. h.name
end

--[[ ================= скачки ================= ]]
views.race = function(B, info)
	if info.bonus and info.bonus > 1 then Kit.note(B, "🏁 Приглашение: призы сегодня двойные!") end
	Kit.text(B, "Трасса проложена по большому полю: <b>" .. #info.gates .. " ворот</b>, проходить по порядку, последние — финиш у старта. Скачи <b>галопом</b> и держись жёлтой стрелки.")
	-- карта трассы
	local F = World.FIELD
	local mapF = make("Frame", { Size = UDim2.fromOffset(300, 300 * F.h / (F.w + 260)), BackgroundColor3 = color("#9ccb6c"), LayoutOrder = Kit.nextOrder(), Parent = B })
	Kit.corner(mapF, 8)
	local kx = 300 / (F.w + 260)
	local function pos(x, y) return UDim2.fromOffset((x - F.x + 200) * kx, (y - F.y) * kx) end
	for _, g in ipairs(info.gates) do
		local dot = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos(g.x, g.y), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = g.finish and color("#111111") or C.blue,
			Text = g.finish and "F" or tostring(g.n), TextColor3 = C.white, Font = Kit.BOLD, TextSize = 11, Parent = mapF })
		Kit.corner(dot, 9)
	end
	local st = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos(info.start.x, info.start.y), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C.red, Parent = mapF })
	Kit.corner(st, 6)
	Kit.text(B, "Твоя лошадь: <b>" .. esc(info.horse) .. "</b> · скорость " .. info.speed .. " · энергия " .. info.energy .. "%")
	local b = info.bonus or 1
	Kit.text(B, "Призы: 🥇 " .. 100 * b .. " · 🥈 " .. 50 * b .. " · 🥉 " .. 25 * b .. " · 4-е место — " .. 5 * b .. " 💰")
	if info.others then Kit.note(B, "На сервере есть другие игроки: после «На старт!» у них будет 10 секунд, чтобы присоединиться к забегу у столба.") end
	local r = Kit.row(B)
	Kit.button(r, "🏁 На старт!", function() act("raceGo") end, { big = true, color = "green" })
	Kit.button(r, "🔀 Другая трасса", function() act("raceNew") end)
	Kit.h(B, "Соперники")
	local grid = Kit.grid(B)
	for _, rv in ipairs(info.rivals or {}) do
		Kit.card(grid, rv.look, { "<font color=\"" .. rv.shirt .. "\">●</font> " .. esc(rv.rider), "на лошади <b>" .. esc(rv.horse) .. "</b>", esc(rv.breed) .. ", " .. esc(rv.color), "скорость: " .. rv.speed })
	end
	return "🏁 Скачки"
end

--[[ ================= справка ================= ]]
views.help = function(B)
	Kit.text(B, "Ты — хозяйка лошадиной фермы! В большом поле к востоку от фермы бегает табун диких лошадей. Лови их, ухаживай, тренируй и разводи жеребят настоящих окрасов. Вместе с тобой на сервере играют другие игроки — можно скакать наперегонки и продавать друг другу лошадей.")
	Kit.h(B, "Управление")
	for _, s in ipairs({
		"<b>WASD / стрелки</b> или джойстик — идти, <b>Shift</b> — бежать, <b>Пробел</b> — прыгнуть; мышь — поворот камеры, колесо — приблизить",
		"<b>E</b> — открыть то, рядом с чем стоишь (конюшня, повозки, тренировка) — или большая зелёная кнопка",
		"<b>F</b> или <b>клик по лошади</b> — бросить лассо; верхом <b>Пробел</b>: на кавалетти — «ноги выше!», в конкуре — прыжок",
		"<b>1 / 2 / 3</b> — шаг / рысь / галоп, <b>Q / R</b> — медленнее / быстрее, <b>X</b> — слезть, <b>V</b> — взлететь на крылатой лошади",
		"В полёте: <b>Пробел</b> — выше, <b>Ctrl</b> или <b>C</b> — ниже",
		"<b>M</b> — большая карта, <b>J</b> — задания, <b>G</b> — металлоискатель, <b>T</b> — трюки верхом, <b>N</b> — заржать",
	}) do Kit.text(B, "• " .. s, { size = 15 }) end
	Kit.h(B, "Что можно делать")
	for _, s in ipairs({
		"🤠 <b>Ловить лошадей.</b> Подойди к лошади и брось лассо — останови стрелку в зелёной зоне. Спокойных лошадей ловить легче; горячие убегают. Морковка или яблоко в рюкзаке помогают.",
		"🏠 <b>Конюшня на 20 денников.</b> Приведи пойманную лошадь в конюшню. Корми, чисти, выпускай в леваду. У каждого игрока свои денники.",
		"🏇 <b>Ездить верхом</b> — нужны седло и уздечка.",
		"🚧 <b>Кавалетти</b> и 🎠 <b>выездка</b> в манеже, 🏆 <b>конкур</b> на конкурном поле — монеты, медали и лошадь становится лучше.",
		"💕 <b>Скрещивать</b> кобылу и жеребца. Окрас жеребёнка считается по настоящим генам: рыжая, гнедая, вороная, соловая, буланая, изабелловая, саврасая, мышастая, серая в яблоках, пегая, чубарая, чалая, серебристая…",
		"🏁 <b>Скачки</b>: подъезжай верхом к клетчатому столбу у входа в поле. Другие игроки могут присоединиться к забегу!",
		"🎲 <b>Случайные события</b>: дождь и радуга, зайчики с подарками, подкова на счастье, ярмарка, потерявшаяся лошадь, приглашения на скачки.",
		"🦄 <b>Волшебные лошадки</b> в Грибном королевстве, скелеты в пещере, крылатые — на островах в море, облачные — на небесных островах (портал в глубине пещеры).",
		"💬 <b>Жители</b> дают задания: ❗ — новое задание, ❓ — можно сдать.",
		"🗺️ <b>Большая карта</b> (M), 📡 <b>металлоискатель и клады</b>, 🎪 <b>рынок</b> с торгом, тренером, обменом и своей стойкой.",
		"🚂 <b>Поезд</b> раз в 30 минут, 🎃🎄🥚 <b>праздники</b> раз в час — успей вместе с другими игроками.",
		"🌙 <b>День и ночь</b>: сутки — 8 минут. Ночью табун спит, и подкрасться к лошадям легче.",
	}) do Kit.text(B, s, { size = 15 }) end
	Kit.text(B, "Игра сохраняется сама.")
	-- когда обновлялся сервер: время сборки из CI, иначе — время запуска сервера (по Москве, UTC+3)
	local t, what = BuildInfo.builtAt, "Сервер обновлён"
	if type(t) ~= "number" then t, what = workspace:GetAttribute("ServerStartedAt"), "Сервер запущен" end
	if type(t) == "number" then
		Kit.small(B, "🕒 " .. what .. ": " .. os.date("!%d.%m.%Y %H:%M", t + 3 * 3600) .. " (МСК)")
	end
	local r = Kit.row(B, { center = true })
	Kit.button(r, "Играть!", function()
		act("seenHelp")
		Win.close()
	end, { big = true, color = "green" })
	Kit.button(r, "Начать заново", function() open("confirmReset", {}) end, { small = true, color = "ghost" })
	return "🐴 Лошадиная ферма — как играть"
end
--[[ ================= индекс пород ================= ]]
local HOME_TEXT = {
	magic = "Грибное королевство", desert = "пустыня", steppe = "степь", foxwood = "Лисий лес", deepforest = "Дремучий лес",
	dragonrock = "Драконьи скалы и Драконий остров", tundra = "тундра", cave = "пещера", forest = "лес у Лесного озера",
	sky = "небесные острова", island = "острова в море", grotto = "маленькие пещерки", holiday = "праздники",
}
local function breedHome(k, B)
	if B.weight and B.weight > 0 then return "Большое поле" end
	if k == "bonehorse" then return "Костяной остров" end
	if k == "pinkdragon" then return "Грибное королевство (очень редко, чаще в радужный дождь)" end
	return HOME_TEXT[B.home or ""] or "где-то в мире"
end
local indexLooks = {}
views.index = function(B)
	local P = State.P
	local caught = P.caughtBreeds or {}
	local owned = {}
	for _, h in ipairs(P.horses) do owned[h.breed] = true end
	local list = {}
	for _, k in ipairs(Genetics.BREED_ORDER) do
		if k ~= "mix" then table.insert(list, k) end
	end
	local n = 0
	for _, k in ipairs(list) do if caught[k] or owned[k] then n += 1 end end
	Kit.text(B, "📖 Здесь все породы лошадей. Поймала: <b>" .. n .. " из " .. #list .. "</b>. Пойманные — с портретом, остальные пока под вопросом: внизу подсказка, где их искать.")
	local g = Kit.grid(B)
	for _, k in ipairs(list) do
		local Bd = Genetics.BREEDS[k]
		local got = caught[k] or owned[k]
		if got then
			indexLooks[k] = indexLooks[k] or Horses.look(Horses.create({ breed = k, age = 6 }))
			Kit.card(g, indexLooks[k], { "✅ " .. Bd.name, (caught[k] and ("поймано: " .. caught[k]) or "есть в конюшне") }, nil, { width = 150 })
		else
			local card = make("Frame", { Size = UDim2.fromOffset(150, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = color("#e9e3d6"), LayoutOrder = Kit.nextOrder(), Parent = g })
			Kit.corner(card, 10)
			Kit.pad(card, 6)
			make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = card })
			make("TextLabel", { Size = UDim2.new(1, 0, 0, 80), BackgroundColor3 = color("#cfc6b5"), Text = "❓", TextSize = 40, Font = Kit.BOLD, TextColor3 = color("#7a6f5d"), LayoutOrder = Kit.nextOrder(), Parent = card })
			Kit.text(card, Bd.name, { size = 14, bold = true, color = C.muted })
			Kit.text(card, "Где искать: " .. breedHome(k, Bd), { size = 12, color = C.muted })
		end
	end
	return "📖 Индекс лошадей"
end

views.confirmReset = function(B)
	Kit.text(B, "Точно начать заново? Все лошади, деньги и вещи пропадут.")
	local r = Kit.row(B)
	Kit.button(r, "Да, начать заново", function() act("reset") end, { color = "pink" })
	Kit.button(r, "Нет", function() open("help", {}) end, { color = "ghost" })
	return "Начать заново?"
end

--[[ ================= окно ================= ]]
local function clearBody()
	for _, c in ipairs(body:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
	end
end
local renderToken
function Win.render()
	if not current or not State.P then return end
	local v = views[current.name]
	if not v then return end
	local scroll = body.CanvasPosition
	clearBody()
	local ok, title = pcall(v, body, current.data or {})
	if not ok then
		warn("[Windows] " .. current.name .. ": " .. tostring(title))
		title = "Окно"
	end
	titleL.Text = title or ""
	body.CanvasPosition = scroll
	lastRender = os.clock()
	-- высоты рядов пересчитываются на следующем кадре — тогда и вернуть прокрутку, иначе окно прыгает наверх
	local token = {}
	renderToken = token
	task.spawn(function()
		RunService.RenderStepped:Wait()
		if renderToken == token then body.CanvasPosition = scroll end
	end)
end
function Win.open(name, data)
	if name == "close" then return Win.close() end
	if not views[name] then return end
	local same = current and current.name == name
	current = { name = name, data = data or {} }
	modal.Visible = true
	if not same then body.CanvasPosition = Vector2.zero end
	Win.render()
end
function Win.close()
	current = nil
	modal.Visible = false
end
function Win.isOpen() return current ~= nil end

function Win.build(parentGui)
	gui = parentGui
	local shade = make("TextButton", { Name = "Modal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 20, Parent = gui })
	shade.Activated:Connect(function() end)
	modal = shade
	local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.94, 0, 0.88, 0), BackgroundColor3 = C.panel, ZIndex = 21, Parent = shade })
	make("UISizeConstraint", { MaxSize = Vector2.new(820, 700), Parent = box })
	Kit.corner(box, 14)
	titleL = make("TextLabel", { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -60, 0, 34), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBlack, TextSize = 21, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 22, Parent = box })
	Kit.closeButton(box, Win.close, 34, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), ZIndex = 23 })
	body = make("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 1, -58), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 22, Parent = box,
	})
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	make("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = body })
	-- перерисовка после действий
	State.on("profile", function()
		if not current then return end
		if UserInputService:GetFocusedTextBox() then return end
		local recentAction = os.clock() - State.actT < 2.5
		-- без действий — не чаще раза в 10 секунд, чтобы карточки с портретами не мигали
		if recentAction or os.clock() - lastRender > 10 then Win.render() end
	end)
end

return Win
