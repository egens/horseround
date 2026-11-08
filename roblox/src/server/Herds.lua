--[[
	Дикие табуны (перенос части js/game.js): пасутся, бегают табуном, убегают от ближайшего игрока,
	спят ночью; острова меняют лошадей каждые 5 минут; лассо.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Genetics = require(Shared.Genetics)
local Items = require(Shared.Items)

local Herds = {}
local G, Entities
local rand, clamp, hypot = Util.rand, Util.clamp, Util.hypot

local wild = {}
Herds.wild = wild
local LASSO_RANGE = 170
Herds.LASSO_RANGE = LASSO_RANGE

-- табуны: обычные лошади в поле, волшебные в Грибном королевстве и другие
local function inset(r, m) return { x = r.x + m, y = r.y + m, w = r.w - m * 2, h = r.h - m * 2 } end
local HERDS = {
	field = { area = World.FIELD, count = 9, sleeps = true, name = "в поле" },
	magic = { area = inset(World.MUSHROOM, 150), count = 9, sleeps = true, name = "в Грибном королевстве" },
	portal = { area = { x = World.PORTAL.x - 450, y = World.PORTAL.y - 380, w = 800, h = 700 }, count = 3, sleeps = false, name = "у портала" },
	forest = { area = { x = World.OX + 1900, y = World.OY + 4100, w = 2300, h = 1700 }, count = 6, sleeps = true, name = "в лесу" },
	cave = { area = inset(World.CAVE, 100), count = 4, sleeps = false, name = "в пещере" },
	desert = { area = inset(World.DESERT, 200), count = 6, sleeps = true, name = "в пустыне" },
	tundra = { area = inset(World.TUNDRA, 200), count = 6, sleeps = true, name = "в тундре" },
	steppe = { area = inset(World.STEPPE, 300), count = 7, sleeps = true, name = "в степи" },
	foxwood = { area = inset(World.FOXWOOD, 300), count = 6, sleeps = true, name = "в Лисьем лесу" },
	deepforest = { area = inset(World.DEEPFOREST, 250), count = 5, sleeps = true, name = "в Дремучем лесу" },
	dragonrock = { area = inset(World.DRAGONROCK, 300), count = 5, sleeps = false, name = "на Драконьих скалах" },
}
for _, g in ipairs(World.GROTTOS) do
	HERDS[g.id] = { area = { x = g.x - g.r * 0.55, y = g.y - g.r * 0.55, w = g.r * 1.1, h = g.r * 1.1 }, count = 2, sleeps = false, name = "в пещерке", grotto = true }
end
HERDS.train = { area = { x = World.STATION.x - 900, y = World.RAIL.y - 1100, w = 2300, h = 1000 }, count = 0, sleeps = false, name = "у станции", special = true }
HERDS.holiday = { area = inset(World.FIELD, 200), count = 0, sleeps = false, name = "на празднике", special = true }
for _, I in ipairs(World.ISLANDS) do
	HERDS[I.id] = { area = I.area, count = 5, sleeps = true, name = "на острове «" .. I.name .. "»", island = I }
end
for i = 1, 3 do
	local I = World.SKY_ISLANDS[i]
	HERDS[I.id] = { area = I.area, count = I.id == "sky1" and 6 or 4, sleeps = false, name = "на острове «" .. I.name .. "»", sky = true }
end
for k, H in pairs(HERDS) do
	H.id = k
	H.x, H.y, H.tx, H.ty, H.t, H.panic, H.respawnT = 0, 0, 0, 0, 0, 0, 0
end
Herds.HERDS = HERDS
local ISLAND_REFRESH = 300
local islandT = ISLAND_REFRESH
function Herds.islandTimeLeft() return islandT end

local HOME_BREEDS = {
	desert = { "akhal", "arab", "sandhorse", "zebra", "zebra", "zebra", "zebra" },
	steppe = { "przewalski", "przewalski", "przewalski", "przewalski", "fedorov", "haflinger", "orlov" },
	foxwood = { "foxhorse", "foxhorse", "foxhorse", "foxhorse", "trakehner", "fedorov" },
	deepforest = { "foxhorse", "foxhorse", "foxhorse", "friesian", "damphorse" },
	dragonrock = { "scalehorse", "scalehorse", "scalehorse", "scalehorse", "dragonhorse" },
	train = { "arab", "andalusian", "appaloosa", "friesian", "akhal", "fedorov", "zebra", "unicorn", "pegasus", "rainbowhorse", "crystalhorse", "foxhorse" },
	holiday = { "holidayhorse" },
	tundra = { "yakut", "yakut", "yakut", "yakut", "fjord", "icehorse" },
	portal = { "skeleton", "skeleton", "skeleton", "stonehorse" },
	forest = { "leafhorse", "leafhorse", "damphorse", "damphorse", "trakehner", "orlov" },
	sky1 = { "cloudhorse", "cloudhorse", "pegasus", "rainbowhorse", "sunhorse", "ravenhorse", "arab" },
	sky2 = { "rainbowhorse", "crystalhorse", "butterflyhorse", "cloudhorse", "waterhorse" },
	sky3 = { "sunhorse", "dragonhorse", "cloudhorse", "crystalhorse", "firehorse" },
}

function Herds.init(g, ents)
	G, Entities = g, ents
end

function Herds.randomPoint(margin, area)
	local F = area or World.FIELD
	margin = math.min(margin or 150, F.w * 0.3, F.h * 0.3)
	for _ = 1, 60 do
		local x, y = rand(F.x + margin, F.x + F.w - margin), rand(F.y + margin, F.y + F.h - margin)
		if not World.inPond(x, y, 150) and not World.blocked(x, y, 40) then return { x = x, y = y } end
	end
	return { x = F.x + F.w / 2, y = F.y + F.h / 2 }
end

local function pickBreed(home)
	if HERDS[home] and HERDS[home].grotto then return "glowhorse" end
	if home == "magic" and not Util.some(wild, function(w) return w.breed == "pinkdragon" end)
		and math.random() < ((G.modules.Events and G.modules.Events.magicRain()) and 0.12 or 0.025) then
		return "pinkdragon"
	end
	if HOME_BREEDS[home] then return Util.pick(HOME_BREEDS[home]) end
	if HERDS[home] and HERDS[home].island then return Util.pick(HERDS[home].island.breeds) end
	local entries = {}
	for _, k in ipairs(Genetics.BREED_ORDER) do
		local b = Genetics.BREEDS[k]
		if home == "field" then
			if b.weight > 0 then table.insert(entries, { k, b.weight }) end
		elseif b.home == home and (b.hw or 0) > 0 then
			table.insert(entries, { k, b.hw })
		end
	end
	if #entries == 0 then return "mix" end
	return Util.weighted(entries)
end

function Herds.makeWild(x, y, home)
	home = home or "field"
	local isFoal = math.random() < (home == "cave" and 0.05 or 0.12)
	local taken = {}
	for _, w in ipairs(wild) do table.insert(taken, w.name) end
	local h = Horses.create({ breed = pickBreed(home), age = isFoal and rand(0.3, 1.5) or rand(3, 13), taken = taken })
	if home == "magic" and math.random() < 0.15 then
		h.magic = Util.assign({}, h.magic, math.random() < 0.5 and { horn = true } or { wings = true })
	end
	if HERDS[home] and HERDS[home].sky and not Horses.canFly(h) then
		h.magic = Util.assign({}, h.magic, math.random() < 0.7 and { wings = math.random() < 0.7 and "pegasus" or "butterfly" } or { cloud = true })
	end
	h.x, h.y, h.angle = x, y, rand(0, 6.28)
	h.slot = { x = rand(-150, 150), y = rand(-110, 110) }
	h.flee, h.grazeT, h.home = 0, rand(0, 5), home
	h.fly = 0
	return h
end

function Herds.add(h)
	table.insert(wild, h)
	Entities.addHorse(h)
end
function Herds.remove(h)
	Util.removeValue(wild, h)
	Entities.removeSrc(h)
end
function Herds.removeIf(pred)
	for i = #wild, 1, -1 do
		local w = wild[i]
		if pred(w) then
			table.remove(wild, i)
			Entities.removeSrc(w)
		end
	end
end

function Herds.spawnAll()
	for _, H in pairs(HERDS) do
		local c = Herds.randomPoint(400, H.area)
		H.x, H.tx, H.y, H.ty = c.x, c.x, c.y, c.y
		for _ = 1, H.count do
			local q = { x = c.x + rand(-150, 150), y = c.y + rand(-120, 120) }
			World.collide(q, 20)
			Herds.add(Herds.makeWild(q.x, q.y, H.id))
		end
	end
end

-- движение к цели с разгоном (как moveToward в JS)
function Herds.moveToward(h, tx, ty, speed, dt, accel)
	accel = accel or 3
	local dx, dy = tx - h.x, ty - h.y
	local d = hypot(dx, dy)
	local want = d > 1 and speed or 0
	local vx, vy = d > 1 and (dx / d) * want or 0, d > 1 and (dy / d) * want or 0
	local k = math.min(1, dt * accel)
	h.vx = (h.vx or 0) + (vx - (h.vx or 0)) * k
	h.vy = (h.vy or 0) + (vy - (h.vy or 0)) * k
	h.x += h.vx * dt
	h.y += h.vy * dt
	h.spd = hypot(h.vx, h.vy)
	if h.spd > 6 then h.angle = Util.lerpAngle(h.angle or 0, math.atan2(h.vy, h.vx), math.min(1, dt * 5)) end
end

--[[ ---------- действия лошадей ---------- ]]
function Herds.startAct(h, k, quiet)
	if not h then return end
	local A = Items.ACTS[k]
	local d = A and A.d or (k == "play" and 3 or 2)
	h.act = { k = k, t = 0, d = d * (0.85 + math.random() * 0.3), leg = math.random(0, 3) }
	if k == "neigh" and not quiet then
		G.float("Иго-го! 🐴", h.x, h.y - 30, "#7a4a22")
		G.R.Sfx:FireAllClients("neigh", h.x, h.y)
	end
end
function Herds.tickAct(h, dt, canBack)
	if not h.act then return end
	h.act.t += dt
	if h.act.k == "back" and canBack then
		h.x -= math.cos(h.angle) * 38 * dt
		h.y -= math.sin(h.angle) * 38 * dt
		World.collide(h, 18)
	end
	if h.act.t >= h.act.d then h.act = nil end
end
local IDLE = { { "graze", 6 }, { "lookUp", 1 }, { "ears", 1 }, { "liftLeg", 1 }, { "neigh", 0.5 }, { "roll", 0.35 }, { "kick", 0.45 }, { "scratch", 0.6 }, { "lookDown", 0.7 }, { "dance", 0.12 }, { "bow", 0.3 } }
Herds.IDLE = IDLE
function Herds.idleAct(h, dt, rate, lst)
	if h.act or math.random() > dt * (rate or 0.1) then return end
	local k = Util.weighted(lst or IDLE)
	local _, d = G.nearestPlayer(h.x, h.y, 450)
	Herds.startAct(h, k, d >= 450)
end

--[[ ---------- табуны ---------- ]]
local function sleepyHerd(herd) return herd.sleeps and G.isNight() and herd.panic <= 0 end

function Herds.update(dt)
	local t = G.time
	-- игроки рядом (для испуга)
	local players = G.each()
	for _, herd in pairs(HERDS) do
		local F = herd.area
		herd.t -= dt
		herd.panic = math.max(0, herd.panic - dt)
		if herd.t <= 0 then
			local q = Herds.randomPoint(300, F)
			herd.tx, herd.ty, herd.t = q.x, q.y, rand(14, 26)
		end
		local sleepy = sleepyHerd(herd)
		local hs = herd.panic > 0 and 120 or sleepy and 0 or 20
		local hd = hypot(herd.tx - herd.x, herd.ty - herd.y)
		if hd > 5 then
			herd.x += ((herd.tx - herd.x) / hd) * hs * dt
			herd.y += ((herd.ty - herd.y) / hd) * hs * dt
		end
		local members = {}
		for _, w in ipairs(wild) do
			if (w.home or "field") == herd.id then table.insert(members, w) end
		end
		for _, w in ipairs(members) do
			if w.lassoBy then
				-- пока в неё бросают лассо — стоит
				w.spd, w.vx, w.vy = 0, 0, 0
			else
				-- ближайший игрок
				local p, d = nil, 1e9
				for _, s in ipairs(players) do
					local dd = hypot(w.x - s.p.x, w.y - s.p.y)
					if dd < d then d = dd; p = s end
				end
				if p then
					local pp = p.p
					local m = pp.mountId ~= nil
					local fleeR = 70 + w.temper * 170
					if sleepy then fleeR *= 0.6 end
					if m and pp.gait == 2 then fleeR *= 1.2 end
					if m and pp.gait == 0 then fleeR *= 0.8 end
					if pp.fly then fleeR *= 0.7 end
					if d < fleeR and w.flee <= 0 then
						w.flee = rand(1.4, 2.2)
						w.act = nil
						if herd.panic <= 0 then
							local ax, ay = herd.x - pp.x, herd.y - pp.y
							local al = hypot(ax, ay)
							if al == 0 then al = 1 end
							herd.tx = clamp(herd.x + (ax / al) * 600, F.x + 250, math.max(F.x + 250, F.x + F.w - 250))
							herd.ty = clamp(herd.y + (ay / al) * 600, F.y + 250, math.max(F.y + 250, F.y + F.h - 250))
							herd.t = rand(8, 14)
						end
						herd.panic = 2.5
					end
				end
				local tx, ty, sp
				if w.flee > 0 and p then
					w.flee -= dt
					local ax, ay = w.x - p.p.x, w.y - p.p.y
					local al = hypot(ax, ay)
					if al == 0 then al = 1 end
					tx = w.x + (ax / al) * 100 + (herd.x - w.x) * 0.15
					ty = w.y + (ay / al) * 100 + (herd.y - w.y) * 0.15
					sp = (170 + Horses.skill(w, "speed") * 0.8) * (w.age < 3 and 0.8 or 1)
					w.headTurn = 0
				else
					if w.flee > 0 then w.flee -= dt end
					local gx, gy = herd.x + w.slot.x, herd.y + w.slot.y
					local gd = hypot(gx - w.x, gy - w.y)
					if gd > 60 then
						tx, ty = gx, gy
						sp = herd.panic > 0 and 190 or gd > 300 and 150 or gd > 150 and 80 or 40
						w.headTurn = 0
					else
						w.grazeT -= dt
						if w.grazeT <= 0 then
							w.grazeT = rand(3, 8)
							w.slot.x += rand(-30, 30)
							w.slot.y += rand(-30, 30)
						end
						tx, ty, sp = w.x, w.y, 0
						w.headTurn = math.sin(t * 0.8 + w.seed) * 0.35
						if (w.fly or 0) <= 0 then Herds.idleAct(w, dt, 0.11) end
					end
				end
				if w.x < F.x + 40 then tx = math.max(tx, F.x + 120) end
				if w.x > F.x + F.w - 40 then tx = math.min(tx, F.x + F.w - 120) end
				if w.y < F.y + 40 then ty = math.max(ty, F.y + 120) end
				if w.y > F.y + F.h - 40 then ty = math.min(ty, F.y + F.h - 120) end
				-- пегасы взлетают, когда убегают; на небесных островах крылатые летают и просто так
				local wings = w.magic and w.magic.wings
				if herd.sky and wings then
					if w.airT == nil then w.airT = rand(2, 12); w.airLen = rand(4, 9) end
					w.airT -= dt
					if w.airT < -w.airLen then w.airT = rand(6, 16); w.airLen = rand(4, 9) end
				end
				local wantFly = wings and (w.flee > 0 or (herd.sky and w.airT < 0))
				w.fly = wantFly and math.min(1, (w.fly or 0) + dt * 2) or math.max(0, (w.fly or 0) - dt)
				if w.fly > 0 and herd.sky and w.flee <= 0 and sp < 60 then
					sp = 90
					tx = w.x + math.cos(t * 0.4 + w.seed) * 120
					ty = w.y + math.sin(t * 0.3 + w.seed) * 120
				end
				if w.act and w.flee <= 0 then tx, ty, sp = w.x, w.y, 0 end
				Herds.tickAct(w, dt, true)
				Herds.moveToward(w, tx, ty, sp, dt, w.flee > 0 and 4 or 2)
				for _, o in ipairs(members) do
					if o ~= w then
						local dx, dy = w.x - o.x, w.y - o.y
						local dd = hypot(dx, dy)
						if dd < 48 and dd > 0.1 then
							w.x += (dx / dd) * (48 - dd) * 0.5
							w.y += (dy / dd) * (48 - dd) * 0.5
						end
					end
				end
				if w.fly <= 0 then World.collide(w, 18) end
				w.x = clamp(w.x, F.x - 60, F.x + F.w + 60)
				w.y = clamp(w.y, F.y - 60, F.y + F.h + 60)
			end
		end
		-- новые лошади приходят взамен пойманных
		if #members < herd.count and not herd.island and not herd.sky and not herd.special then
			herd.respawnT -= dt
			if herd.respawnT <= 0 then
				herd.respawnT = rand(8, 16)
				local q = Herds.randomPoint(200, F)
				local nw = Herds.makeWild(q.x, q.y, herd.id)
				Herds.add(nw)
				if herd.id == "field" then
					G.toastAll("🐎 В поле прибежала новая лошадь!", "", function(s) return World.inRect(s.p.x, s.p.y, World.FIELD, 1500) end)
				end
				if nw.breed == "pinkdragon" then
					G.toastAll("💗🐉 В Грибном королевстве появился РОЗОВЫЙ ДРАКОН! Больше таких нигде нет!", "good")
				end
			end
		end
	end
	-- острова: лошади меняются каждые 5 минут
	islandT -= dt
	if islandT <= 0 then
		islandT = ISLAND_REFRESH
		for _, I in ipairs(World.ISLANDS) do
			Herds.removeIf(function(w) return w.home == I.id end)
			local H = HERDS[I.id]
			local c = Herds.randomPoint(200, I.area)
			H.x, H.tx, H.y, H.ty = c.x, c.x, c.y, c.y
			for _ = 1, H.count do
				local q = Herds.randomPoint(120, I.area)
				Herds.add(Herds.makeWild(q.x, q.y, I.id))
			end
		end
		for i = 1, 3 do
			local I = World.SKY_ISLANDS[i]
			local H = HERDS[I.id]
			local n = Util.count(wild, function(w) return w.home == I.id end)
			for _ = n + 1, H.count do
				local q = Herds.randomPoint(120, I.area)
				Herds.add(Herds.makeWild(q.x, q.y, I.id))
			end
		end
		G.toastAll("🏝️ На островах появились новые дикие лошади!", "good")
	end
end

-- радужный дождь в волшебном биоме: иногда прилетает розовый дракон
function Herds.pinkDragonRain()
	if Util.some(wild, function(w) return w.breed == "pinkdragon" end) then return end
	local H = HERDS.magic
	local q = Herds.randomPoint(300, H.area)
	local old = Util.find(wild, function(w) return w.home == "magic" end)
	if old then Herds.remove(old) end
	local d = Horses.create({ breed = "pinkdragon", age = rand(4, 9) })
	d.x, d.y, d.home, d.slot, d.flee, d.grazeT, d.fly, d.angle = q.x, q.y, "magic", { x = 0, y = 0 }, 0, 1, 0, 0
	Herds.add(d)
	G.toastAll("🌈 В Грибном королевстве пошёл радужный дождь… Говорят, там появился розовый дракон! 💗🐉", "good")
end

--[[ ---------- лассо ---------- ]]
function Herds.nearestCatchable(sess)
	if sess.led or sess.ex or sess.lasso then return nil end
	local best, bd = nil, LASSO_RANGE
	for _, w in ipairs(wild) do
		if not w.lassoBy then
			local d = hypot(w.x - sess.p.x, w.y - sess.p.y)
			if d < bd then bd = d; best = w end
		end
	end
	return best
end

function Herds.startLasso(sess, w)
	local P = sess.P
	if sess.led then G.toast(sess, "Сначала отведи пойманную лошадь в конюшню"); return end
	if not w or (sess.lassoCd or 0) > 0 or sess.lasso or w.lassoBy then return end
	if hypot(w.x - sess.p.x, w.y - sess.p.y) > LASSO_RANGE + 40 then return end
	local zone = 0.24 * (P.tack.goodLasso and 1.5 or 1) * (1.25 - w.temper * 0.6)
	local bait = nil
	if (P.inv.carrot or 0) > 0 then bait = "carrot"
	elseif (P.inv.apple or 0) > 0 then bait = "apple" end
	if bait then
		zone *= 1.3
		P.inv[bait] -= 1
		G.dirty(sess)
	end
	if sess.p.mountId then zone *= 1.1 end
	zone = clamp(zone, 0.08, 0.6)
	local l = {
		w = w, zone = zone, bait = bait,
		center = rand(zone / 2 + 0.04, 1 - zone / 2 - 0.04),
		speed = 0.55 + w.temper * 1.0,
		start = workspace:GetServerTimeNow(),
	}
	sess.lasso = l
	w.lassoBy = sess
	local ph = Horses.pheno(w)
	G.R.Lasso:FireClient(sess.player, {
		who = w.name .. " — " .. string.lower(Genetics.BREEDS[w.breed].name) .. ", " .. ph.name .. ", " .. Horses.sexText(w),
		temper = w.temper < 0.35 and "Нрав: спокойная 😌" or w.temper < 0.6 and "Нрав: обычная 🙂" or "Нрав: горячая 🔥",
		bait = bait and (bait == "carrot" and "🥕 Морковка помогает!" or "🍎 Яблоко помогает!") or "",
		zone = zone, center = l.center, speed = l.speed, start = l.start,
	})
	G.sfx(sess, "whoosh")
end

-- положение стрелки: «пила» 0 → 1 → 0
local function needleAt(l, now)
	local s = (now - l.start) * l.speed
	local m = s % 2
	return m <= 1 and m or 2 - m
end

function Herds.resolveLasso(sess, clientPos)
	local l = sess.lasso
	if not l then return end
	sess.lasso = nil
	local w = l.w
	w.lassoBy = nil
	local pos = needleAt(l, workspace:GetServerTimeNow())
	-- клиент видит стрелку с небольшой задержкой: верим ему, если он близко к правде
	if type(clientPos) == "number" and math.abs(clientPos - pos) < 0.2 + l.speed * 0.25 then pos = clientPos end
	local ok = math.abs(pos - l.center) <= l.zone / 2 and table.find(wild, w) ~= nil
	G.R.Lasso:FireClient(sess.player, { close = true, ok = ok })
	local P = sess.P
	if ok then
		Herds.remove(w)
		w.state = "led"
		w.flee = 0
		w.lassoBy = nil
		w.fly = 0
		sess.led = w
		G.modules.Owned.attachLed(sess, w)
		P.stats.caught = (P.stats.caught or 0) + 1
		if Horses.isMagic(w) then G.stat(sess, "magicCaught") end
		if w.magic and w.magic.wings then G.stat(sess, "wing_" .. Horses.wingType(w.magic.wings)) end
		if w.magic and (Horses.wingType(w.magic.wings) == "bee" or Horses.wingType(w.magic.wings) == "dragonfly") then G.stat(sess, "wingSmall") end
		if w.home == "desert" or w.home == "tundra" then G.stat(sess, "caught_" .. w.home) end
		if w.breed == "pinkdragon" then G.stat(sess, "pinkDragon") end
		if w.home == "train" then G.stat(sess, "trainCaught") end
		if w.magic and w.magic.holiday then G.stat(sess, "holidayCaught") end
		if HERDS[w.home] and HERDS[w.home].island then G.stat(sess, "caught_island") end
		if w.magic and w.magic.skeleton then G.stat(sess, "skeletonCaught") end
		local ph = Horses.pheno(w)
		G.toast(sess, "🎉 Поймала! " .. w.name .. ": " .. string.lower(Genetics.BREEDS[w.breed].name) .. ", " .. ph.name .. ". Веди в конюшню!", "good")
		G.sfx(sess, "fanfare")
		G.dirty(sess)
	else
		w.flee = 2.5
		local herd = HERDS[w.home or "field"]
		if herd then herd.panic = 3 end
		sess.lassoCd = 1.2
		G.toast(sess, l.bait and "Мимо! Лошадь съела угощение и убежала 🥕" or "Мимо! Лошадь убежала. Попробуй ещё!", "warn")
		G.sfx(sess, "fail")
	end
end

-- игрок ушёл посреди лассо
function Herds.cancelLasso(sess)
	if sess.lasso then
		sess.lasso.w.lassoBy = nil
		sess.lasso = nil
	end
end

function Herds.findById(id)
	for _, w in ipairs(wild) do
		if w.id == id then return w end
	end
	return nil
end
-- дикая лошадь по id сущности (клик мышкой по лошади)
function Herds.byEntity(eid)
	for _, w in ipairs(wild) do
		if w._ent and w._ent.id == eid then return w end
	end
	return nil
end

return Herds
