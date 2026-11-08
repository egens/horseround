--[[
	Поезд в пустыне, праздники, три ИИ-игрока, привидения и олени
	(перенос js/train.js, js/holidays.js, js/ai.js, js/creatures.js). Всё общее для всех игроков.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Genetics = require(Shared.Genetics)

local S = {}
local G, Entities, Herds
local rand, hypot = Util.rand, Util.hypot

function S.init(g, ents, herds) G, Entities, Herds = g, ents, herds end

--[[ ================= поезд ================= ]]
local Train = {}
S.Train = Train
local PERIOD, CATCH, FIRST = 30 * 60, 60, 4 * 60
local RAIL, ST = World.RAIL, World.STATION
Train.STOP_X = ST.x + ST.w / 2
local tr = nil
local trainT = FIRST
local warned = false

local function release()
	local n = 6 + math.random(0, 2)
	local herd = Herds.HERDS.train
	herd.x, herd.tx, herd.y, herd.ty, herd.t = Train.STOP_X, Train.STOP_X, RAIL.y - 520, RAIL.y - 520, 4
	for i = 0, n - 1 do
		local h = Herds.makeWild(Train.STOP_X - 260 + i * 70, RAIL.y - 70, "train")
		h.temper = math.min(h.temper, 0.55)
		h.angle = -math.pi / 2
		h.slot = { x = (i - n / 2) * 70, y = -60 + math.random() * 120 }
		Herds.add(h)
	end
	G.toastAll("🐎 Из поезда выбежали красивые лошади! Лови — у тебя одна минута!", "good")
	G.sfx(nil, "fanfare")
end
local function recall()
	local left = Util.count(Herds.wild, function(w) return w.home == "train" end)
	Herds.removeIf(function(w) return w.home == "train" end)
	G.toastAll(left > 0 and ("🚂 Лошади забежали обратно в поезд (" .. left .. "), и он уехал. Следующий — через 30 минут") or "🚂 Поезд уехал. Следующий — через 30 минут")
end
function Train.update(dt)
	if not tr then
		trainT -= dt
		if trainT <= 60 and not warned then
			warned = true
			G.toastAll("🚂 Через минуту в пустыню приедет поезд с лошадьми! Станция — на железной дороге")
		end
		if trainT <= 0 then
			trainT = PERIOD
			warned = false
			tr = { x = RAIL.x1 - 700, v = 420, state = "in", t = 0 }
			G.toastAll("🚂 Ту-ту! По пустыне едет поезд с красивыми лошадьми! Спеши к станции", "good")
			G.sfx(nil, "train")
		end
		return
	end
	tr.t += dt
	if tr.state == "in" then
		local d = Train.STOP_X - tr.x
		tr.v = math.min(420, math.max(30, d * 0.5))
		tr.x += tr.v * dt
		if d < 3 then
			tr.x, tr.v, tr.state, tr.t = Train.STOP_X, 0, "stop", 0
			release()
		end
	elseif tr.state == "stop" then
		if tr.t >= CATCH then
			recall()
			tr.state, tr.t = "out", 0
			G.sfx(nil, "train")
		end
	else
		tr.v = math.min(460, tr.v + 110 * dt)
		tr.x += tr.v * dt
		if tr.x > RAIL.x2 + 1200 then tr = nil end
	end
end
function Train.hud()
	if tr and tr.state == "stop" then return { catchLeft = math.max(0, CATCH - tr.t) } end
	if tr then return { moving = true } end
	return { next = trainT }
end
function Train.state() return tr end
function Train.near(p) return math.abs(p.y - RAIL.y) < 1600 and p.x > RAIL.x1 - 400 and p.x < RAIL.x2 + 400 end
function Train.come() trainT = 1 end

--[[ ================= праздники ================= ]]
local Holidays = {}
S.Holidays = Holidays
local H_PERIOD, H_LEN, H_FIRST = 60 * 60, 8 * 60, 3 * 60
Holidays.KINDS = {
	halloween = { name = "Хэллоуин", icon = "🎃", toast = "🎃 Хэллоуин! В поле прибежали страшные лошади с тыквами, летучими мышами и привидениями!" },
	newyear = { name = "Новый год", icon = "🎄", toast = "🎄 Новый год! В поле — лошади-ёлочки с игрушками и светящиеся лошади разных цветов!" },
	easter = { name = "Пасха", icon = "🥚", toast = "🥚 Пасха! В поле — розовые лошади с разноцветными яичками, полосочками и точечками!" },
}
local holidayT = H_FIRST
local holidayNow = nil
local function spawnHoliday(k)
	local herd = Herds.HERDS.holiday
	local F = herd.area
	herd.x, herd.tx, herd.y, herd.ty = F.x + F.w / 2, F.x + F.w / 2, F.y + F.h / 2, F.y + F.h / 2
	Herds.removeIf(function(w) return w.home == "holiday" end)
	for i = 0, 5 do
		local h = Herds.makeWild(herd.x + (math.random() - 0.5) * 400, herd.y + (math.random() - 0.5) * 300, "holiday")
		local v = k == "newyear" and (i % 2 == 1 and "newyearglow" or "newyear") or k
		h.magic = Horses.resolveMagic({ holiday = v })
		h._ph = nil
		h.temper = math.min(h.temper, 0.5)
		Herds.add(h)
	end
end
function Holidays.start(k)
	k = k or Util.pick({ "halloween", "newyear", "easter" })
	holidayNow = { k = k, t = H_LEN }
	holidayT = H_PERIOD
	spawnHoliday(k)
	G.toastAll(Holidays.KINDS[k].toast, "good")
	G.sfx(nil, "fanfare")
end
local function endHoliday()
	local k = holidayNow.k
	holidayNow = nil
	Herds.removeIf(function(w) return w.home == "holiday" end)
	G.toastAll(Holidays.KINDS[k].icon .. " Праздник «" .. Holidays.KINDS[k].name .. "» закончился. Следующий — через час!")
end
function Holidays.update(dt)
	if holidayNow then
		holidayNow.t -= dt
		if holidayNow.t <= 0 then endHoliday() end
	else
		holidayT -= dt
		if holidayT <= 0 then Holidays.start() end
	end
end
function Holidays.current() return holidayNow and holidayNow.k or nil end
function Holidays.hud()
	if holidayNow then
		local K = Holidays.KINDS[holidayNow.k]
		return { k = holidayNow.k, name = K.name, icon = K.icon, left = holidayNow.t }
	end
	return { next = holidayT }
end

--[[ ================= три ИИ-игрока ================= ]]
local AI = {}
S.AI = AI
local DEFS = {
	{ name = "Ника", look = { pad = "#f06595", helmet = "#5f3dc4", shirt = "#f06595", saddleStyle = "crystal", saddleColor = "#e64980", bridleStyle = "crystal", bridleColor = "#7048e8" }, breed = "arab", skill = 0.75 },
	{ name = "Тимур", look = { pad = "#4dabf7", helmet = "#1c7ed6", shirt = "#4dabf7", saddleStyle = "classic", saddleColor = "#5b3a1e", bridleStyle = "classic", bridleColor = "#2b1a10" }, breed = "akhal", skill = 0.6 },
	{ name = "Соня", look = { pad = "#ffd43b", helmet = "#e67700", shirt = "#69db7c", saddleStyle = "plant", saddleColor = "#2b8a3e", bridleStyle = "plant", bridleColor = "#5c940d" }, breed = "andalusian", skill = 0.5 },
}
local bots = {}
local aiToastT = 0

local function pickRoad(b)
	local R = World.ROADS
	local opts = {}
	for k, r in ipairs(R) do
		local a, z = r[1], r[#r]
		if hypot(a[1] - b.x, a[2] - b.y) < 450 then table.insert(opts, { k, 1 }) end
		if hypot(z[1] - b.x, z[2] - b.y) < 450 then table.insert(opts, { k, -1 }) end
	end
	if #opts > 0 then
		local o = Util.pick(opts)
		b.road, b.rdir = R[o[1]], o[2]
		b.ri = o[2] > 0 and 1 or #R[o[1]]
		return
	end
	local best, bd = nil, 1e9
	for _, r in ipairs(R) do
		for j, q in ipairs(r) do
			local d = hypot(q[1] - b.x, q[2] - b.y)
			if d < bd then bd = d; best = { r, j } end
		end
	end
	b.road, b.ri, b.rdir = best[1], best[2], math.random() < 0.5 and 1 or -1
end

function AI.init()
	local starts = { World.START, { x = World.VILLAGE.x + 600, y = World.VILLAGE.y + 400 }, { x = World.FARMLAND.x + 800, y = World.FARMLAND.y + 200 } }
	for i, d in ipairs(DEFS) do
		local h = Horses.create({ breed = d.breed, age = 7, sex = i % 2 == 0 and "m" or "f" })
		h.state = "ai"
		local st = starts[i]
		h.x, h.y, h.angle, h.spd = st.x, st.y, 0, 0
		local b = { i = i, name = d.name, look = d.look, skill = d.skill, h = h, x = st.x, y = st.y, angle = 0, spd = 0,
			road = nil, ri = 1, rdir = 1, chase = nil, cd = rand(20, 40), stuckT = 0, lastX = st.x, lastY = st.y, gait = 1,
			stat = { caught = 0, money = 200, best = "" } }
		pickRoad(b)
		table.insert(bots, b)
		Entities.add("rider", h, function()
			return { horse = Horses.look(h), rider = { shirt = d.look.shirt, helmet = d.look.helmet, pad = d.look.pad,
				saddleStyle = d.look.saddleStyle, saddleColor = d.look.saddleColor, bridleStyle = d.look.bridleStyle, bridleColor = d.look.bridleColor }, name = "🤖 " .. d.name }
		end, function() return Horses.lookKey(h) end, "🤖 " .. d.name)
	end
end

local function moveTo(b, tx, ty, sp, dt)
	local dx, dy = tx - b.x, ty - b.y
	local d = hypot(dx, dy)
	if d < 1 then b.spd = 0; return d end
	local v = math.min(sp, d / dt)
	b.x += dx / d * v * dt
	b.y += dy / d * v * dt
	b.spd = v
	b.angle = Util.lerpAngle(b.angle, math.atan2(dy, dx), math.min(1, dt * 6))
	World.collide(b, 18)
	return d
end

local function catchHorse(b, w)
	Herds.remove(w)
	b.stat.caught += 1
	b.stat.money += math.floor(Horses.price(w) * 0.6 + 0.5)
	b.stat.best = Genetics.BREEDS[w.breed].name
	b.cd = rand(70, 120)
	local who = b.i == 2 and "поймал" or "поймала"
	local his = b.i == 2 and "него" or "неё"
	local msg = "🤖 " .. b.name .. " " .. who .. " лошадь: " .. string.lower(Genetics.BREEDS[w.breed].name) .. ", " .. Horses.pheno(w).name .. "! Всего у " .. his .. ": " .. b.stat.caught
	local loud = aiToastT <= 0
	if loud then aiToastT = 25 end
	G.toastAll(msg, "", function(s) return loud or hypot(s.p.x - b.x, s.p.y - b.y) < 1500 end)
end

function AI.update(dt)
	aiToastT -= dt
	local trs = Train.state()
	for _, b in ipairs(bots) do
		b.cd -= dt
		local toTrain = trs and trs.state == "stop" and hypot(b.x - Train.STOP_X, b.y - RAIL.y) < 9000
		if not b.chase and (b.cd <= 0 or toTrain) then
			local best, bd = nil, toTrain and 2500 or 520
			for _, w in ipairs(Herds.wild) do
				local skip = (w.fly or 0) > 0 or w.lassoBy or (w.home and (string.sub(w.home, 1, 1) == "i" or string.sub(w.home, 1, 3) == "sky"))
				if not skip then
					local d = hypot(w.x - b.x, w.y - b.y)
					if d < bd then bd = d; best = w end
				end
			end
			if best then b.chase = best; b.chaseT = 0 end
		end
		if b.chase then
			local w = b.chase
			b.chaseT += dt
			if not table.find(Herds.wild, w) or b.chaseT > 25 or w.lassoBy then
				b.chase = nil
				b.cd = rand(20, 40)
				pickRoad(b)
			else
				local d = moveTo(b, w.x, w.y, 240 + b.skill * 40, dt)
				if d < 70 then
					if math.random() < 0.45 + b.skill * 0.4 then catchHorse(b, w) else w.flee = 2; b.cd = rand(8, 15) end
					b.chase = nil
					pickRoad(b)
				end
			end
		elseif toTrain then
			moveTo(b, Train.STOP_X + (b.i - 2) * 120, RAIL.y - 300, 260, dt)
		else
			local q = b.road[b.ri]
			local d = moveTo(b, q[1], q[2], b.gait == 1 and 160 or 80, dt)
			if d < 30 then
				b.ri += b.rdir
				if b.ri < 1 or b.ri > #b.road then pickRoad(b) end
				if math.random() < 0.15 then b.gait = b.gait == 1 and 0 or 1 end
			end
		end
		b.stuckT += dt
		if b.stuckT > 3 then
			if hypot(b.x - b.lastX, b.y - b.lastY) < 25 then
				b.chase = nil
				local best, bd = nil, 1e9
				for _, r in ipairs(World.ROADS) do
					for _, q in ipairs(r) do
						local dd = hypot(q[1] - b.x, q[2] - b.y)
						if dd < bd and dd > 60 then bd = dd; best = q end
					end
				end
				if best then b.x, b.y = best[1], best[2] end
				pickRoad(b)
			end
			b.stuckT, b.lastX, b.lastY = 0, b.x, b.y
		end
		local h = b.h
		h.x, h.y, h.angle, h.spd = b.x, b.y, b.angle, b.spd
	end
end
function AI.hud()
	return Util.map(bots, function(b)
		return { name = b.name, caught = b.stat.caught, money = b.stat.money, best = b.stat.best, where = World.REGION_NAMES[World.regionAt(b.x, b.y)] or "" }
	end)
end

--[[ ================= привидения и олени ================= ]]
local Creatures = {}
S.Creatures = Creatures
local ghosts, deer, deerHerds = {}, {}, {}
local BOO = { "👻 Бу-у-у! Привидение пролетело сквозь тебя!", "👻 Уууу! Ой, как щекотно и холодно!", "👻 Бу! Привидение засмеялось и улетело.", "👻 Хи-хи! Привидение спряталось в стене." }
local function ghostSpot()
	local C = World.CAVE
	return { x = rand(C.x + 150, C.x + C.w - 150), y = rand(C.y + 150, C.y + C.h - 150) }
end
local function deerSpot(H)
	local A = H.area
	for _ = 1, 40 do
		local x, y = rand(A.x + 150, A.x + A.w - 150), rand(A.y + 150, A.y + A.h - 150)
		if World.regionAt(x, y) == H.reg and not World.blocked(x, y, 30) then return { x = x, y = y } end
	end
	return { x = A.x + A.w / 2, y = A.y + A.h / 2 }
end

function Creatures.init()
	local homes = {
		{ area = World.STEPPE, reg = "steppe" }, { area = World.STEPPE, reg = "steppe" }, { area = World.FOXWOOD, reg = "foxwood" },
		{ area = World.FOREST[1], reg = "forest" }, { area = World.FOREST[1], reg = "forest" }, { area = World.LAKELAND, reg = "lake" }, { area = World.GROTTO, reg = "grotto" },
	}
	for _, H in ipairs(homes) do
		local c = deerSpot(H)
		local herd = Util.assign({ x = c.x, y = c.y, tx = c.x, ty = c.y, t = rand(5, 15), panic = 0 }, H)
		table.insert(deerHerds, herd)
		local n = 3 + math.random(0, 2)
		for i = 0, n - 1 do
			local a = { herd = herd, x = c.x + rand(-80, 80), y = c.y + rand(-60, 60), angle = rand(0, 6.28), spd = 0, buck = i == 0,
				slot = { x = rand(-90, 90), y = rand(-70, 70) }, flee = 0, fawn = i > 2 and math.random() < 0.5, graze = rand(0, 4), seed = math.random(0, 999999) }
			table.insert(deer, a)
			Entities.add("deer", a, function() return { buck = a.buck, fawn = a.fawn, seed = a.seed } end)
		end
	end
	for i = 0, 6 do
		local p = ghostSpot()
		local g = { x = p.x, y = p.y, tx = p.x, ty = p.y, t = rand(0, 6), fade = 1, cd = 0, hidden = 0, angle = 0, spd = 30,
			kind = i % 3 == 0 and "horse" or "sheet", seed = math.random(0, 999999) }
		table.insert(ghosts, g)
		Entities.add("ghost", g, function() return { kind = g.kind, seed = g.seed } end)
	end
end

function Creatures.update(dt)
	local players = G.each()
	for _, H in ipairs(deerHerds) do
		H.t -= dt
		H.panic = math.max(0, H.panic - dt)
		if H.t <= 0 then
			local q = deerSpot(H)
			H.tx, H.ty, H.t = q.x, q.y, rand(15, 30)
		end
		local d = hypot(H.tx - H.x, H.ty - H.y)
		local sp = H.panic > 0 and 200 or 25
		if d > 5 then
			H.x += (H.tx - H.x) / d * sp * dt
			H.y += (H.ty - H.y) / d * sp * dt
		end
	end
	for _, a in ipairs(deer) do
		local H = a.herd
		local p, dp = G.nearestPlayer(a.x, a.y, 260)
		if p and a.flee <= 0 then
			a.flee = rand(1.5, 2.5)
			if H.panic <= 0 then
				local ax, ay = H.x - p.p.x, H.y - p.p.y
				local al = hypot(ax, ay)
				if al == 0 then al = 1 end
				H.tx, H.ty, H.t = H.x + ax / al * 700, H.y + ay / al * 700, rand(8, 12)
			end
			H.panic = 2.5
		end
		local tx, ty, sp
		if a.flee > 0 then
			a.flee -= dt
			local src = p and p.p or { x = a.x - 1, y = a.y }
			local ax, ay = a.x - src.x, a.y - src.y
			local al = hypot(ax, ay)
			if al == 0 then al = 1 end
			tx, ty, sp = a.x + ax / al * 100, a.y + ay / al * 100, 230
		else
			tx, ty = H.x + a.slot.x, H.y + a.slot.y
			local gd = hypot(tx - a.x, ty - a.y)
			sp = gd > 60 and (H.panic > 0 and 200 or gd > 200 and 120 or 45) or 0
			if sp == 0 then
				a.graze -= dt
				if a.graze <= 0 then
					a.graze = rand(3, 8)
					a.slot.x += rand(-30, 30)
					a.slot.y += rand(-30, 30)
				end
			end
		end
		local dx, dy = tx - a.x, ty - a.y
		local dd = hypot(dx, dy)
		local v = dd > 2 and math.min(sp, dd / dt) or 0
		if v > 0 then
			a.x += dx / dd * v * dt
			a.y += dy / dd * v * dt
			a.angle = Util.lerpAngle(a.angle, math.atan2(dy, dx), math.min(1, dt * 6))
		end
		a.spd = v
		-- иногда щиплет траву
		a.act = (v <= 3 and math.sin(G.time * 0.4 + a.seed) > 0.3) and { k = "graze", t = 1, d = 100 } or nil
		World.collide(a, 14)
	end
	for _, g in ipairs(ghosts) do
		g.t += dt
		g.cd = math.max(0, g.cd - dt)
		if g.hidden > 0 then
			g.hidden -= dt
			if g.hidden <= 0 then
				local q = ghostSpot()
				g.x, g.y, g.fade = q.x, q.y, 0
			end
			g.z = -50
		else
			g.z = 0
			g.fade = math.min(1, g.fade + dt * 0.8)
			local target, d = nil, 1e9
			for _, s in ipairs(players) do
				if World.inRect(s.p.x, s.p.y, World.CAVE, 100) then
					local dd = hypot(s.p.x - g.x, s.p.y - g.y)
					if dd < d then d = dd; target = s end
				end
			end
			local tx, ty, sp = g.tx, g.ty, 30
			if target and d < 220 and g.cd <= 0 then
				tx, ty, sp = target.p.x, target.p.y, 75
			elseif hypot(g.tx - g.x, g.ty - g.y) < 20 or math.random() < dt * 0.1 then
				local q = ghostSpot()
				g.tx, g.ty = q.x, q.y
			end
			local dx, dy = tx - g.x, ty - g.y
			local l = hypot(dx, dy)
			if l == 0 then l = 1 end
			g.x += dx / l * sp * dt
			g.y += dy / l * sp * dt
			g.angle = math.atan2(dy, dx)
			g.spd = sp
			if target and d < 38 and g.cd <= 0 then
				g.cd = 6
				g.hidden = rand(4, 8)
				local root = G.root(target)
				if root then
					local ax, ay = target.p.x - g.x, target.p.y - g.y
					local al = hypot(ax, ay)
					if al == 0 then al = 1 end
					root:ApplyImpulse(Vector3.new(ax / al, 0.3, ay / al) * root.AssemblyMass * 26)
				end
				G.toast(target, Util.pick(BOO))
				G.stat(target, "ghosts")
				G.sfx(target, "boo")
			end
		end
	end
end

return S
