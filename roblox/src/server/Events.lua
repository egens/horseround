--[[
	Случайные события (перенос js/events.js): дождь и радуга, зайчики, подкова на счастье,
	потерявшаяся лошадь, ярмарка, приглашение на скачки.
	Скачки: случайная трасса в большом поле, соперники-боты и другие игроки (мультиплеер!).
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Genetics = require(Shared.Genetics)

local Events = {}
local G, Entities, Herds
local rand, clamp, hypot, pick = Util.rand, Util.clamp, Util.hypot, Util.pick

local nextT = rand(35, 60)
local rain = nil
local wet, rainbowT, puddle = 0, 0, 0
local bunnies = {}
local shoe = nil
local fairT, invite = 0, 0
local race = nil
local raceId = 0

local START = World.START
local RIDERS = { "Маша", "Лиза", "Артём", "Даня", "Соня", "Вика", "Тимур", "Полина", "Ника", "Егор", "Алиса", "Миша" }
local SHIRTS = { "#4dabf7", "#ffa94d", "#69db7c", "#9775fa", "#ffd43b", "#f06595", "#20c997", "#e8590c" }
local HELMETS = { "#212529", "#1c7ed6", "#c92a2a", "#2b8a3e", "#5f3dc4", "#e67700" }

function Events.init(g, ents, herds) G, Entities, Herds = g, ents, herds end

function Events.raining() return rain ~= nil end
function Events.weather() return wet end
function Events.puddles() return puddle end
function Events.rainbow() return rainbowT end
function Events.priceMul() return fairT > 0 and 1.3 or 1 end
function Events.fair() return fairT > 0 end
function Events.invite() return invite end
function Events.shoe() return shoe end
-- в волшебном биоме кто-то стоит под радужным дождём
function Events.magicRain()
	if not rain then return false end
	for _, s in ipairs(G.each()) do
		if World.regionAt(s.p.x, s.p.y) == "mushroom" then return true end
	end
	return false
end

--[[ ================= расписание событий ================= ]]
local function anyoneCanRace()
	for _, s in ipairs(G.each()) do
		local P = s.P
		if P.tack.saddle and P.tack.bridle and Util.some(P.horses, function(h) return Horses.canRide(h) end) then return true end
	end
	return false
end
local function anyoneHasHorses()
	for _, s in ipairs(G.each()) do
		if #s.P.horses > 0 then return true end
	end
	return false
end

local function randomGrass(area, margin)
	for _ = 1, 60 do
		local x, y = rand(area.x + margin, area.x + area.w - margin), rand(area.y + margin, area.y + area.h - margin)
		local bad = World.inPond(x, y, 60)
		if not bad then
			for _, t in ipairs(World.treesNear(x, y)) do
				if hypot(t.x - x, t.y - y) < 40 then bad = true; break end
			end
		end
		if not bad then return { x = x, y = y } end
	end
	return nil
end

--[[ ================= зайчики ================= ]]
local BUNNY_COLORS = { { "#b08d6a", "#e9dcc8" }, { "#8a7f75", "#d9d2ca" }, { "#f1ede6", "#ffffff" }, { "#5e4b3c", "#cbb9a4" } }
local function spawnBunnies(n)
	local areas = { World.FIELD, { x = World.OX + 1000, y = World.OY + 1150, w = 650, h = 1150 }, World.LAKELAND, World.FOREST[1], World.FARMLAND, World.STEPPE }
	for _, hh in ipairs(G.modules.Farm.bunnyHomes()) do
		local a = { x = hh.x - 250, y = hh.y - 250, w = 500, h = 500 }
		table.insert(areas, a)
		table.insert(areas, a)
	end
	for _ = 1, n do
		local p = randomGrass(pick(areas), 60)
		if p then
			local c = pick(BUNNY_COLORS)
			local b = { x = p.x, y = p.y, angle = rand(0, 6.28), hop = 0, hopT = rand(0.5, 2), tx = p.x, ty = p.y, life = rand(80, 120),
				color = c[1], belly = c[2], state = "idle", fade = 1, z = 0, spd = 0 }
			table.insert(bunnies, b)
			Entities.add("bunny", b, function() return { color = b.color, belly = b.belly } end)
		end
	end
end

local function catchBunny(sess, b)
	local P = sess.P
	b.state = "gone"
	Entities.removeSrc(b)
	G.stat(sess, "bunnies")
	local r = math.random()
	local gift
	if r < 0.35 then P.inv.carrot = (P.inv.carrot or 0) + 2; gift = "2 морковки 🥕"
	elseif r < 0.6 then P.inv.apple = (P.inv.apple or 0) + 1; gift = "яблоко 🍎"
	elseif r < 0.85 then
		local c = math.floor(rand(8, 20) + 0.5)
		P.money += c
		gift = c .. " монет 🪙"
	else P.inv.sugar = (P.inv.sugar or 0) + 2; gift = "2 кусочка сахара 🍬" end
	G.float("🐰 +" .. gift, b.x, b.y - 20, "#1b8a3a")
	G.toast(sess, "🐰 Ты поймала зайчика! Он подарил тебе " .. gift .. " и ускакал.", "good")
	G.sfx(sess, "coin")
	G.dirty(sess)
end

local function updateBunnies(dt)
	local players = G.each()
	for _, b in ipairs(bunnies) do
		b.life -= dt
		if b.state == "gone" then
			b.fade -= dt * 1.5
		else
			if b.life <= 0 and b.state ~= "leaving" then b.state = "leaving" end
			local near, d = nil, 1e9
			for _, s in ipairs(players) do
				local dd = hypot(b.x - s.p.x, b.y - s.p.y)
				if dd < d then d = dd; near = s end
			end
			local m = near and near.p.mountId ~= nil
			local scared = near ~= nil and d < (m and 150 or 115)
			b.hopT -= dt
			if b.hopT <= 0 and b.hop <= 0 then
				local a
				if (scared or b.state == "leaving") and near then a = math.atan2(b.y - near.p.y, b.x - near.p.x) + rand(-0.6, 0.6)
				else a = b.angle + rand(-1.5, 1.5) end
				local len = scared and rand(60, 90) or rand(15, 40)
				b.tx, b.ty = b.x + math.cos(a) * len, b.y + math.sin(a) * len
				b.angle = a
				b.hop = 1
				b.hopT = scared and rand(0.05, 0.25) or rand(0.8, 2.5)
			end
			if b.hop > 0 then
				local sp = scared and 6.5 or 4
				b.hop = math.max(0, b.hop - dt * sp)
				local k = math.min(1, dt * sp * 1.6)
				b.x += (b.tx - b.x) * k
				b.y += (b.ty - b.y) * k
				b.z = math.sin((1 - b.hop) * math.pi) * 8
				b.spd = 60
				World.collide(b, 6)
			else
				b.z = 0
				b.spd = 0
			end
			if near and d < (m and 34 or 24) and b.state ~= "leaving" then catchBunny(near, b) end
			if b.state == "leaving" and d > 900 then
				b.state = "gone"
				Entities.removeSrc(b)
			end
		end
	end
	Util.removeIf(bunnies, function(b)
		local dead = b.fade <= 0 or b.life <= -40
		if dead then Entities.removeSrc(b) end
		return dead
	end)
end

local function start(kind)
	if kind == "rain" then
		rain = { t = rand(45, 90) }
		G.toastAll("🌧️ Пошёл дождь! Появляются лужи, лошади мокнут и пачкают ноги — все, кроме тех, что в конюшне.")
	elseif kind == "bunnies" then
		spawnBunnies(3 + math.random(0, 2))
		G.toastAll("🐰 На лугу появились зайчики! Поймай зайчика — он принесёт подарок.")
	elseif kind == "race" then
		invite = 150
		G.toastAll("🏁 Приглашение на скачки! Приз двойной — подъезжай к стартовому столбу у поля.", "good")
		G.sfx(nil, "fanfare")
	elseif kind == "shoe" then
		shoe = randomGrass(World.FIELD, 120) or { x = World.FIELD.x + 300, y = World.FIELD.y + 800 }
		shoe.t = 120
		G.toastAll("✨ Где-то в поле блестит подкова на счастье! Посмотри на миникарте.")
	elseif kind == "fair" then
		fairT = 90
		G.toastAll("🎪 Ярмарка! Полторы минуты торговец платит за лошадей на 30% больше.", "good")
	elseif kind == "lost" then
		local h = Herds.makeWild(World.FIELD.x - 60, World.FIELD.y + rand(600, 900))
		h.temper = 0.05
		h.lost = true
		h.slot = { x = rand(-150, 150), y = rand(-110, 110) }
		Herds.add(h)
		G.toastAll("🐴 У края поля бродит потерявшаяся лошадь по кличке " .. h.name .. ". Она совсем ручная!")
	end
end
Events.debugStart = start

local function fireRandom()
	local opts = {}
	if not rain then table.insert(opts, { "rain", 3 }) end
	if #bunnies < 3 then table.insert(opts, { "bunnies", 3 }) end
	if anyoneCanRace() and not race and invite <= 0 then table.insert(opts, { "race", 2 }) end
	if not shoe then table.insert(opts, { "shoe", 1.5 }) end
	if fairT <= 0 and anyoneHasHorses() then table.insert(opts, { "fair", 1 }) end
	table.insert(opts, { "lost", 1 })
	start(Util.weighted(opts))
end

--[[ ================= скачки ================= ]]
local function segClear(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local L = hypot(dx, dy)
	local s = 0
	while s <= L do
		if World.inPond(a.x + dx * s / L, a.y + dy * s / L, 70) then return false end
		s += 25
	end
	for _, t in ipairs(World.TREES) do
		if t.x > World.FIELD.x - 300 and t.x < World.FIELD.x + World.FIELD.w + 300 and t.y > World.FIELD.y - 300 and t.y < World.FIELD.y + World.FIELD.h + 300 then
			local tt = clamp(((t.x - a.x) * dx + (t.y - a.y) * dy) / (L * L), 0, 1)
			if hypot(a.x + dx * tt - t.x, a.y + dy * tt - t.y) < 50 then return false end
		end
	end
	return true
end

local function makeTrack()
	local F, m = World.FIELD, 170
	for _ = 1, 200 do
		local n = 6 + math.random(0, 3)
		local pts = { { x = START.x + 40, y = START.y } }
		local ang, ok = rand(-0.5, 0.9), true
		for _ = 1, n do
			if not ok then break end
			local placed = false
			for _ = 1, 30 do
				local a, len = ang + rand(-1.2, 1.2), rand(380, 700)
				local prev = pts[#pts]
				local q = { x = prev.x + math.cos(a) * len, y = prev.y + math.sin(a) * len }
				local good = not (q.x < F.x + m or q.x > F.x + F.w - m or q.y < F.y + m or q.y > F.y + F.h - m)
				if good and Util.some(pts, function(o) return hypot(o.x - q.x, o.y - q.y) < 260 end) then good = false end
				if good and not segClear(prev, q) then good = false end
				if good then
					table.insert(pts, q)
					ang = a
					placed = true
					break
				end
			end
			if not placed then ok = false end
		end
		if ok then
			local fin = { x = START.x + 60, y = START.y + 50 }
			if segClear(pts[#pts], fin) then
				table.insert(pts, fin)
				local gates = {}
				for i = 2, #pts do
					local g, prev = pts[i], pts[i - 1]
					table.insert(gates, { x = g.x, y = g.y, a = math.atan2(g.y - prev.y, g.x - prev.x), n = i - 1, finish = i == #pts })
				end
				return { start = pts[1], dir = math.atan2(pts[2].y - pts[1].y, pts[2].x - pts[1].x), gates = gates }
			end
		end
	end
	return nil
end

local function makeRivals(playerHorse, count)
	local riders = table.clone(RIDERS)
	for i = #riders, 2, -1 do
		local j = math.random(1, i)
		riders[i], riders[j] = riders[j], riders[i]
	end
	local breeds = { "akhal", "arab", "orlov", "trakehner", "budyonny", "paint", "appaloosa", "haflinger", "friesian" }
	local my = Horses.skill(playerHorse, "speed")
	local out = {}
	for i = 1, count do
		local h = Horses.create({ breed = pick(breeds), age = rand(5, 10) })
		h.base.speed = math.floor(clamp(my + rand(-12, 15), 35, 98) + 0.5)
		h.state = "rival"
		table.insert(out, {
			h = h, rider = riders[i],
			look = { pad = pick(SHIRTS), helmet = pick(HELMETS), shirt = pick(SHIRTS), boots = math.random() < 0.5 and "#ffffff" or nil },
			form = rand(0.9, 1.0), off = rand(-28, 28), i = 1, done = nil,
		})
	end
	return out
end

local function rivalCard(r)
	local ph = Horses.pheno(r.h)
	return { rider = r.rider, shirt = r.look.shirt, horse = r.h.name, breed = Genetics.BREEDS[r.h.breed].name, color = ph.name,
		speed = Horses.skill(r.h, "speed"), look = Horses.look(r.h) }
end

-- игрок у столба: показать трассу и соперников
function Events.prepareRace(sess)
	local m = G.mounted(sess)
	if not m then G.toast(sess, "Для скачек сядь на лошадь"); return end
	if race then G.toast(sess, "Скачки уже идут — подожди, пока закончатся", "warn"); return end
	local track = makeTrack()
	if not track then G.toast(sess, "Не получилось проложить трассу, попробуй ещё раз", "warn"); return end
	sess.pendingRace = { track = track, rivals = makeRivals(m, 3), bonus = invite > 0 and 2 or 1 }
	local cards = Util.map(sess.pendingRace.rivals, rivalCard)
	G.open(sess, "race", {
		gates = Util.map(track.gates, function(g) return { x = g.x, y = g.y, n = g.n, finish = g.finish } end),
		start = track.start, rivals = cards, bonus = sess.pendingRace.bonus,
		horse = m.name, speed = Horses.skill(m, "speed"), energy = math.floor(m.energy + 0.5),
		others = #G.each() > 1,
	})
end

local function riderEntity(r)
	return Entities.add("rider", r.h, function()
		return { horse = Horses.look(r.h), rider = { shirt = r.look.shirt, helmet = r.look.helmet, pad = r.look.pad }, name = r.rider }
	end, nil, r.rider)
end

local function slotPos(track, k)
	local perp = track.dir + math.pi / 2
	local row = math.floor(k / 4)
	local col = k % 4
	return {
		x = track.start.x - math.cos(track.dir) * (70 + row * 70) + math.cos(perp) * (col - 1.5) * 55,
		y = track.start.y - math.sin(track.dir) * (70 + row * 70) + math.sin(perp) * (col - 1.5) * 55,
	}
end

function Events.startRace(sess)
	local m = G.mounted(sess)
	local pend = sess.pendingRace
	if not pend or not m then return end
	if race then return G.toast(sess, "Скачки уже идут — подожди, пока закончатся", "warn") end
	G.R.Open:FireClient(sess.player, "close")
	sess.pendingRace = nil
	if invite > 0 then invite = 0 end
	raceId += 1
	local multi = #G.each() > 1
	race = { id = raceId, track = pend.track, rivals = pend.rivals, bonus = pend.bonus, state = multi and "lobby" or "countdown",
		t = 0, count = 3, lobby = 10, racers = {}, host = sess, finishOrder = {}, doneT = nil }
	Events.joinRace(sess, true)
	if multi then
		G.toastAll("🏁 " .. G.playerName(sess) .. " зовёт на скачки! Подъезжай верхом к стартовому столбу у поля — старт через 10 секунд.", "good",
			function(s) return s ~= sess end)
		G.toast(sess, "🏁 Ждём других игроков 10 секунд… Остальные могут присоединиться у столба.")
	else
		Events.beginCountdown()
	end
end

function Events.joinRace(sess, isHost)
	if not race or (race.state ~= "lobby" and not isHost) then return end
	if race.racers[sess] then return end
	local m = G.mounted(sess)
	if not m then return G.toast(sess, "Для скачек сядь на лошадь") end
	if sess.ex then G.modules.Exercises.cancel(sess) end
	local n = 0
	for _ in pairs(race.racers) do n += 1 end
	race.racers[sess] = { i = 1, myTime = nil, k = n }
	sess.race = race
	sess.p.fly = false
	G.modules.Riding.setGait(sess, 2)
	if not isHost then
		G.toast(sess, "🏁 Ты в забеге! Старт скоро.", "good")
		-- одним ботом меньше: живой соперник интереснее
		if #race.rivals > 1 then table.remove(race.rivals) end
	end
end

function Events.beginCountdown()
	race.state = "countdown"
	race.count = 3
	-- расставить всех по слотам
	local order = {}
	for s in pairs(race.racers) do table.insert(order, s) end
	local k = 0
	for _, r in ipairs(race.rivals) do
		local sp = slotPos(race.track, k)
		k += 1
		Util.assign(r.h, { x = sp.x, y = sp.y, angle = race.track.dir, vx = 0, vy = 0, spd = 0 })
		r.ent = riderEntity(r)
	end
	for _, s in ipairs(order) do
		local sp = slotPos(race.track, k)
		k += 1
		race.racers[s].slot = sp
		G.teleport(s, sp.x, sp.y)
		G.R.Race:FireClient(s.player, { gates = Util.map(race.track.gates, function(g) return { x = g.x, y = g.y, n = g.n, finish = g.finish } end), next = 1, dir = race.track.dir })
		G.toast(s, "🏁 На старт! Скачи галопом через ворота по порядку номеров. Жёлтая стрелка покажет дорогу.")
	end
end

local function endRace()
	if not race then return end
	for _, r in ipairs(race.rivals) do Entities.removeSrc(r.h) end
	for s in pairs(race.racers) do
		s.race = nil
		if s.player.Parent then G.R.Race:FireClient(s.player, nil) end
	end
	race = nil
end

function Events.leaveRace(sess, msg)
	if not race or not race.racers[sess] then return end
	race.racers[sess] = nil
	sess.race = nil
	if sess.player.Parent then G.R.Race:FireClient(sess.player, nil) end
	if msg then G.toast(sess, msg, "warn") end
	if next(race.racers) == nil then endRace() end
end
Events.cancelRace = Events.leaveRace

local function rivalSpeed(r)
	local base = 250 * (0.75 + Horses.skill(r.h, "speed") / 200)
	-- держатся рядом с лучшим игроком
	local best = 1
	for _, st in pairs(race.racers) do best = math.max(best, st.i) end
	local ahead = r.i - best
	local band = ahead >= 2 and 0.94 or ahead <= -1 and 1.08 or 1
	local tired = 1 - math.min(0.08, race.t / 900)
	return base * r.form * band * tired * (0.97 + math.sin(race.t * 0.7 + r.off) * 0.03)
end

local function progress(i, x, y)
	local T = race.track
	if i > #T.gates then return 1e9 end
	return i * 1e5 - hypot(T.gates[i].x - x, T.gates[i].y - y)
end
local function standings()
	local list = {}
	for _, r in ipairs(race.rivals) do
		table.insert(list, { name = r.rider, horse = r.h.name, done = r.done, score = r.done and (1e9 - r.done) or progress(r.i, r.h.x, r.h.y) })
	end
	for s, st in pairs(race.racers) do
		local m = G.mounted(s)
		table.insert(list, { name = G.playerName(s), horse = m and m.name or "", done = st.myTime, score = st.myTime and (1e9 - st.myTime) or progress(st.i, s.p.x, s.p.y), sess = s })
	end
	for s, st in pairs(race.finished or {}) do
		table.insert(list, { name = st.name, horse = st.horse, done = st.myTime, score = 1e9 - st.myTime, sess = s })
	end
	table.sort(list, function(a, b) return a.score > b.score end)
	return list
end

local function finishFor(sess)
	local st = race.racers[sess]
	local m = G.mounted(sess)
	st.myTime = race.t
	local table_ = standings()
	local place = 1
	for i, x in ipairs(table_) do
		if x.sess == sess then place = i end
	end
	local total = #table_
	local prizes = { 100, 50, 25, 5 }
	local prize = (prizes[math.min(place, 4)] or 5) * race.bonus
	local medal = ({ "gold", "silver", "bronze" })[place]
	local P = sess.P
	P.money += prize
	if medal then G.stat(sess, medal) end
	G.stat(sess, "races")
	if place == 1 then G.stat(sess, "wins") end
	if place <= 3 then G.stat(sess, "podiums") end
	if m then
		Horses.addTrain(m, "speed", 1 + math.max(0, 4 - place) * 0.8)
		Horses.addTrain(m, "stamina", 1)
		m.energy = clamp(m.energy - 20, 0, 100)
	end
	local rows = Util.map(table_, function(x) return { name = x.name, horse = x.horse, done = x.done, me = x.sess == sess } end)
	G.open(sess, "raceResult", { place = place, total = total, prize = prize, medal = medal, time = race.t, bonus = race.bonus, table = rows, gates = #race.track.gates })
	G.sfx(sess, place <= 3 and "fanfare" or "tick")
	G.dirty(sess)
	race.finished = race.finished or {}
	race.finished[sess] = { myTime = st.myTime, name = G.playerName(sess), horse = m and m.name or "" }
	race.racers[sess] = nil
	sess.race = nil
	G.R.Race:FireClient(sess.player, nil)
	if next(race.racers) == nil then race.doneT = 6 end
end

local function updateRace(dt)
	local T = race.track
	if race.state == "lobby" then
		race.lobby -= dt
		if race.lobby <= 0 then Events.beginCountdown() end
		return
	end
	if race.state == "countdown" then
		local before = math.ceil(race.count)
		race.count -= dt
		for s, st in pairs(race.racers) do
			if st.slot and hypot(s.p.x - st.slot.x, s.p.y - st.slot.y) > 40 then G.teleport(s, st.slot.x, st.slot.y) end
		end
		local now = math.ceil(race.count)
		if now ~= before and now > 0 then
			for s in pairs(race.racers) do
				G.float(tostring(now), s.p.x, s.p.y - 40, "#c92a2a")
				G.sfx(s, "tick")
			end
		end
		if race.count <= 0 then
			race.state = "run"
			for s in pairs(race.racers) do
				G.float("Марш!", s.p.x, s.p.y - 40, "#1b8a3a")
				G.sfx(s, "fanfare")
			end
		end
		return
	end
	if race.state ~= "run" then return end
	race.t += dt
	-- игроки проходят ворота
	for s, st in pairs(race.racers) do
		if not G.mounted(s) then
			Events.leaveRace(s, "Ты слезла с лошади — скачки прерваны")
			if not race then return end
		else
			local g = T.gates[st.i]
			if g and hypot(s.p.x - g.x, s.p.y - g.y) < 80 then
				st.i += 1
				G.sfx(s, "tick")
				if st.i > #T.gates then
					finishFor(s)
					if not race then return end
				else
					G.float("Ворота " .. g.n .. " ✔", g.x, g.y - 40, "#1b8a3a")
					G.R.Race:FireClient(s.player, { next = st.i })
				end
			end
		end
	end
	-- соперники
	local others = {}
	for _, r in ipairs(race.rivals) do table.insert(others, r.h) end
	for s in pairs(race.racers) do table.insert(others, s.p) end
	for _, r in ipairs(race.rivals) do
		local h = r.h
		if r.done then
			h.vx *= 0.96
			h.vy *= 0.96
			h.x += h.vx * dt
			h.y += h.vy * dt
			h.spd = hypot(h.vx, h.vy)
		else
			local tg = T.gates[r.i]
			local perp = tg.a + math.pi / 2
			local tx, ty = tg.x + math.cos(perp) * r.off, tg.y + math.sin(perp) * r.off
			local dx, dy = tx - h.x, ty - h.y
			local d = hypot(dx, dy)
			if d == 0 then d = 1 end
			local sp = rivalSpeed(r)
			local ax, ay = dx / d, dy / d
			for _, o in ipairs(others) do
				if o ~= h then
					local ox, oy = h.x - o.x, h.y - o.y
					local od = hypot(ox, oy)
					if od < 50 and od > 0.1 then
						ax += ox / od * 0.5
						ay += oy / od * 0.5
					end
				end
			end
			local al = hypot(ax, ay)
			if al == 0 then al = 1 end
			local k = math.min(1, dt * 3.5)
			h.vx += (ax / al * sp - h.vx) * k
			h.vy += (ay / al * sp - h.vy) * k
			h.x += h.vx * dt
			h.y += h.vy * dt
			World.collide(h, 18)
			h.spd = hypot(h.vx, h.vy)
			if h.spd > 6 then h.angle = Util.lerpAngle(h.angle, math.atan2(h.vy, h.vx), math.min(1, dt * 6)) end
			if d < 70 then
				r.i += 1
				if r.i > #T.gates then
					r.done = race.t
					table.insert(race.finishOrder, r)
				end
			end
		end
	end
	if race.doneT then
		race.doneT -= dt
		if race.doneT <= 0 then endRace() end
	end
	-- слишком долго — заканчиваем
	if race and race.t > 300 then
		for s in pairs(race.racers) do Events.leaveRace(s, "Скачки слишком затянулись — забег окончен") end
		if race then endRace() end
	end
end

--[[ ================= общий шаг ================= ]]
function Events.update(dt)
	nextT -= dt
	if nextT <= 0 then
		nextT = rand(60, 120)
		fireRandom()
	end
	if rain then
		rain.t -= dt
		wet = math.min(1, wet + dt * 0.25)
		puddle = math.min(1, puddle + dt * 0.06)
		for _, s in ipairs(G.each()) do
			for _, h in ipairs(s.P.horses) do
				if h.state == "paddock" then
					h.clean = math.max(0, h.clean - dt * 0.35)
					h.mood = math.max(0, h.mood - dt * 0.04)
				end
			end
		end
		if rain.t <= 0 then
			rain = nil
			if G.daylight() > 0.5 then
				rainbowT = 60
				G.toastAll("🌈 Дождь закончился — смотри, радуга! И в лужах она отражается", "good")
			else
				G.toastAll("Дождь закончился")
			end
		end
	else
		wet = math.max(0, wet - dt * 0.2)
		puddle = math.max(0, puddle - dt * 0.005)
	end
	rainbowT = math.max(0, rainbowT - dt)
	if fairT > 0 and fairT - dt <= 0 then G.toastAll("Ярмарка закончилась") end
	fairT = math.max(0, fairT - dt)
	if invite > 0 then
		invite -= dt
		if invite <= 0 then G.toastAll("Приглашение на скачки истекло — но скакать можно и просто так") end
	end
	if shoe then
		shoe.t -= dt
		local s = G.nearestPlayer(shoe.x, shoe.y, 40)
		if s then
			local c = math.floor(rand(30, 60) + 0.5)
			s.P.money += c
			G.float("🍀 +" .. c .. " 🪙", shoe.x, shoe.y - 20, "#1b8a3a")
			G.toast(s, "🍀 Подкова на счастье! +" .. c .. " монет", "good")
			G.sfx(s, "fanfare")
			G.dirty(s)
			shoe = nil
		elseif shoe.t <= 0 then
			shoe = nil
		end
	end
	updateBunnies(dt)
	if race then updateRace(dt) end
end

--[[ ================= подсказки ================= ]]
local function nearStart(sess) return hypot(sess.p.x - START.x, sess.p.y - START.y) < 130 end
function Events.prompt(sess)
	if sess.race or not nearStart(sess) then return nil end
	if race and race.state == "lobby" then
		if not G.mounted(sess) then return { label = "🏁 Скачки", fn = function() G.toast(sess, "Для скачек сядь на лошадь в конюшне") end } end
		return { label = "🏁 Присоединиться к скачкам", fn = function() Events.joinRace(sess) end }
	end
	if race then return { label = "🏁 Скачки идут…", fn = function() G.toast(sess, "Скачки уже идут — подожди, пока закончатся") end } end
	if not G.mounted(sess) then return { label = "🏁 Скачки", fn = function() G.toast(sess, "Для скачек сядь на лошадь в конюшне") end } end
	return { label = invite > 0 and "🏁 Скачки (приз ×2!)" or "🏁 Скачки", fn = function() Events.prepareRace(sess) end }
end

function Events.hud(sess)
	if not race or sess.race ~= race then return nil end
	local T = race.track
	local st = race.racers[sess]
	if not st then return nil end
	if race.state == "lobby" then
		local n = 0
		for _ in pairs(race.racers) do n += 1 end
		return { title = "🏁 Скачки", line = "Ждём игроков: " .. n .. " в забеге. Старт через " .. math.ceil(race.lobby) .. " с", hint = "Другие игроки могут присоединиться у столба", ok = true, letter = "⏳" }
	end
	if race.state == "countdown" then
		return { title = "🏁 Скачки", line = "Ворот: " .. #T.gates .. ". Старт через " .. math.ceil(race.count) .. "…", hint = "Приготовься! Галоп — клавиша 3", ok = true, letter = tostring(math.max(1, math.ceil(race.count))) }
	end
	local table_ = standings()
	local place = 1
	for i, x in ipairs(table_) do
		if x.sess == sess then place = i end
	end
	local g = T.gates[math.min(st.i, #T.gates)]
	return {
		title = race.bonus > 1 and "🏁 Скачки (приз ×2)" or "🏁 Скачки",
		line = "Ворота " .. st.i .. "/" .. #T.gates .. (g.finish and " — ФИНИШ" or "") .. " · место: " .. place .. " из " .. #table_ .. " · " .. string.format("%.1f", race.t) .. " с",
		hint = sess.p.gait == 2 and "Галоп ✔ Держись жёлтой стрелки" or "Быстрее! Переходи на ГАЛОП (клавиша 3)",
		ok = sess.p.gait == 2, letter = g.finish and "🏁" or tostring(g.n),
	}
end

-- для миникарты и клиента
function Events.state()
	local b = {}
	for _, x in ipairs(bunnies) do
		if x.state ~= "gone" then table.insert(b, { math.floor(x.x), math.floor(x.y) }) end
	end
	return {
		raining = rain ~= nil, wet = wet, puddle = puddle, rainbow = rainbowT, fair = fairT > 0, invite = invite,
		shoe = shoe and { x = shoe.x, y = shoe.y } or nil, bunnies = b,
		race = race and { state = race.state, rivals = Util.map(race.rivals, function(r) return { math.floor(r.h.x), math.floor(r.h.y) } end) } or nil,
	}
end
function Events.busy(sess) return sess.race ~= nil end

return Events
