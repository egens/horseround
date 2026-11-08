--[[
	Стройка и огород, металлоискатель и клады, сбор грибов, сундук графа (перенос js/farm.js).
	Постройки каждого игрока хранятся в его профиле, но стоят в общем мире и видны всем.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Stalls = require(Shared.Stalls)

local Farm = {}
local G
local rand, hypot = Util.rand, Util.hypot
local B = Items.BUILDS

local spots = {}              -- где зарыты клады (общие)
local picked = {}             -- сорванные грибы: id → когда вырастут
local pickedDirty = true
local buildsDirty = true

function Farm.init(g)
	G = g
	while #spots < 14 do table.insert(spots, Farm.newSpot()) end
end

--[[ ================= постройки ================= ]]
-- все постройки онлайн-игроков
local function allBuilds()
	local out = {}
	for _, s in ipairs(G.each()) do
		for _, b in ipairs(s.P.builds) do table.insert(out, { b = b, sess = s }) end
	end
	return out
end
function Farm.syncSolids()
	local list = World.BUILD_SOLIDS
	table.clear(list)
	for _, it in ipairs(allBuilds()) do
		local b = it.b
		if b.type == "stable5" then
			for _, w in ipairs(Stalls.stableWalls(b)) do table.insert(list, w) end
		elseif B[b.type] and B[b.type].solid then
			table.insert(list, Stalls.rectOf(b))
		end
	end
	buildsDirty = true
end
function Farm.markDirty() buildsDirty = true end

local function NO_BUILD()
	local list = { World.STABLE, World.ARENA, World.JUMPF, World.PADDOCK, World.MOUNTAIN, World.SELL, World.SHOP, World.MARKET }
	for _, I in ipairs(World.ISLANDS) do
		table.insert(list, I.stable)
		table.insert(list, I.pasture)
		table.insert(list, { x = I.pen.x - I.pen.r, y = I.pen.y - I.pen.r, w = I.pen.r * 2, h = I.pen.r * 2 })
		table.insert(list, { x = I.pier.x - 240, y = I.pier.y - 80, w = 360, h = 160 })
	end
	table.insert(list, { x = World.PIER.x - 80, y = World.PIER.y - 80, w = 360, h = 160 })
	table.insert(list, { x = World.START.x - 150, y = World.START.y - 150, w = 300, h = 300 })
	return list
end
local noBuild = nil

function Farm.canPlace(sess, btype, x, y, rot)
	noBuild = noBuild or NO_BUILD()
	local w, h = Stalls.dims(btype, rot)
	local r = { x = x - w / 2, y = y - h / 2, w = w, h = h }
	if r.x < 20 or r.y < 20 or r.x + r.w > World.W - 20 or r.y + r.h > World.H - 20 then return false end
	local function over(a, q, m)
		m = m or 0
		return a.x < q.x + q.w + m and a.x + a.w + m > q.x and a.y < q.y + q.h + m and a.y + a.h + m > q.y
	end
	for _, q in ipairs(noBuild) do
		if over(r, q, 20) then return false end
	end
	for _, it in ipairs(allBuilds()) do
		if over(r, Stalls.rectOf(it.b), 4) then return false end
	end
	for i = 0, math.ceil(r.w / 150) do
		for j = 0, math.ceil(r.h / 150) do
			for _, t in ipairs(World.treesNear(r.x + i * 150, r.y + j * 150)) do
				if World.inRect(t.x, t.y, r, (t.cr or 9) + 4) then return false end
			end
		end
	end
	for i = 0, 4 do
		for j = 0, 4 do
			if World.blocked(r.x + r.w * i / 4, r.y + r.h * j / 4, 6) then return false end
		end
	end
	-- не ставить на игроков
	for _, s in ipairs(G.each()) do
		if btype ~= "bed" and btype ~= "flowerbed" and btype ~= "stable5" and math.abs(s.p.x - x) < w / 2 + 12 and math.abs(s.p.y - y) < h / 2 + 12 then return false end
	end
	return true
end

function Farm.build(sess, btype, x, y, rot)
	local P = sess.P
	local d = B[btype]
	if not d then return end
	x, y = math.floor((tonumber(x) or 0) / 10 + 0.5) * 10, math.floor((tonumber(y) or 0) / 10 + 0.5) * 10
	rot = rot == 1 and 1 or 0
	if hypot(x - sess.p.x, y - sess.p.y) > 900 then return G.toast(sess, "Слишком далеко — подойди ближе", "warn") end
	if not Farm.canPlace(sess, btype, x, y, rot) then
		G.toast(sess, "Сюда поставить нельзя", "warn")
		G.sfx(sess, "fail")
		return
	end
	if P.money < d.price then return G.toast(sess, "Не хватает монет", "warn") end
	P.money -= d.price
	P.buildId = (P.buildId or 0) + 1
	local b = { id = P.buildId, type = btype, x = x, y = y, rot = rot }
	if btype == "bed" then b.crop, b.grow, b.wet = false, 0, 0 end
	if btype == "tree" then b.t = 60 end
	table.insert(P.builds, b)
	Farm.syncSolids()
	G.stat(sess, "built_total")
	if btype == "bed" then G.stat(sess, "built_bed") end
	G.float("🔨 " .. d.name, b.x, b.y - 30, "#1b8a3a")
	G.sfx(sess, "coin")
	G.dirty(sess)
end

function Farm.remove(sess, x, y)
	local P = sess.P
	local b = Util.find(P.builds, function(q) return World.inRect(x, y, Stalls.rectOf(q), 6) end)
	if not b then return G.toast(sess, "Здесь нет твоей постройки") end
	if b.type == "stable5" then
		local idx = table.find(Stalls.stables5(P), b) or 1
		local from = 20 + (idx - 1) * 5
		if Util.some(P.horses, function(h) return h.stall >= from and h.stall < from + 5 end) then
			return G.toast(sess, "В этой конюшне живут лошади — сначала продай их или освободи денники", "warn")
		end
	end
	Util.removeValue(P.builds, b)
	local back = math.floor(B[b.type].price / 2)
	P.money += back
	Farm.syncSolids()
	G.toast(sess, B[b.type].name .. " убрана, +" .. back .. " 💰")
	G.sfx(sess, "tick")
	G.dirty(sess)
end

--[[ ================= огород ================= ]]
function Farm.nearestBuild(sess, types, r)
	local p = sess.p
	local best, bd = nil, r or 60
	for _, b in ipairs(sess.P.builds) do
		if table.find(types, b.type) then
			local rr = Stalls.rectOf(b)
			local dx = math.max(rr.x - p.x, 0, p.x - rr.x - rr.w)
			local dy = math.max(rr.y - p.y, 0, p.y - rr.y - rr.h)
			local d = hypot(dx, dy)
			if d < bd then bd = d; best = b end
		end
	end
	return best
end
local function bedById(sess, id)
	return Util.find(sess.P.builds, function(b) return b.id == id and b.type == "bed" end)
end
function Farm.plant(sess, id, crop)
	local b = bedById(sess, id)
	local c = Items.CROPS[crop]
	local P = sess.P
	if not b or not c or b.crop then return end
	if not ((P.inv[c.seed] or 0) > 0) then return G.toast(sess, "Нет: " .. Items.name(c.seed) .. ". Купи в повозке «Корм и амуниция»", "warn") end
	P.inv[c.seed] -= 1
	b.crop, b.grow, b.wet = crop, 0, math.max(b.wet or 0, 0)
	G.stat(sess, "planted")
	G.sfx(sess, "tick")
	buildsDirty = true
	G.dirty(sess)
end
function Farm.water(sess, id)
	local b = bedById(sess, id)
	if not b then return end
	b.wet = 90
	G.float("💧", b.x, b.y - 20, "#1c7ed6")
	G.sfx(sess, "tick")
	buildsDirty = true
	G.dirty(sess)
end
function Farm.harvest(sess, id)
	local b = bedById(sess, id)
	if not b or not b.crop or b.grow < 1 then return end
	local c, P = Items.CROPS[b.crop], sess.P
	local item, n = c.yield[1], c.yield[2]
	P.inv[item] = (P.inv[item] or 0) + n
	G.stat(sess, "harvest_total")
	G.stat(sess, "harvest_" .. b.crop)
	G.float(Items.icon(item) .. " +" .. n, b.x, b.y - 30, "#1b8a3a")
	G.toast(sess, "🧺 Урожай: " .. Items.name(item) .. " ×" .. n, "good")
	b.crop, b.grow = false, 0
	G.sfx(sess, "coin")
	buildsDirty = true
	G.dirty(sess)
end

local growAcc = 0
local function updateBuilds(dt)
	growAcc += dt
	if growAcc < 1 then return end
	dt = growAcc
	growAcc = 0
	local raining = G.modules.Events.raining()
	for _, s in ipairs(G.each()) do
		local wells = Util.filter(s.P.builds, function(b) return b.type == "well" end)
		for _, b in ipairs(s.P.builds) do
			if b.type == "bed" and b.crop then
				if raining or Util.some(wells, function(w) return hypot(w.x - b.x, w.y - b.y) < 240 end) then b.wet = math.max(b.wet, 60) end
				if b.wet > 0 and b.grow < 1 then
					local before = b.grow
					b.grow = math.min(1, b.grow + dt / Items.CROPS[b.crop].time)
					-- стадия роста поменялась — перерисовать
					local function stage(g) return g >= 1 and 3 or g >= 0.6 and 2 or g >= 0.25 and 1 or 0 end
					if stage(before) ~= stage(b.grow) then buildsDirty = true end
				end
				local wasWet = b.wet > 0
				b.wet = math.max(0, b.wet - dt)
				if wasWet ~= (b.wet > 0) then buildsDirty = true end
			end
			if b.type == "tree" then
				local was = (b.t or 0) > 0
				b.t = math.max(0, (b.t or 0) - dt)
				if was ~= (b.t > 0) then buildsDirty = true end
			end
		end
	end
end

--[[ ================= клады ================= ]]
function Farm.newSpot()
	local areas = {
		{ World.FIELD, 3 }, { World.LAKELAND, 3 }, { World.FOREST[1], 4 }, { World.FARMLAND, 1 }, { World.VILLAGE, 1 },
		{ World.MUSHROOM, 3 }, { World.CAVE, 2 }, { World.DESERT, 3 }, { World.TUNDRA, 3 }, { World.DEEPFOREST, 1 },
	}
	for _, I in ipairs(World.ISLANDS) do table.insert(areas, { I.area, 1 }) end
	for _ = 1, 80 do
		local area = Util.weighted(areas)
		local x, y = rand(area.x + 60, area.x + area.w - 60), rand(area.y + 60, area.y + area.h - 60)
		if not World.blocked(x, y, 20) then return { x = x, y = y, cave = area == World.CAVE } end
	end
	return { x = World.FIELD.x + 700, y = World.FIELD.y + 1100 }
end

local function updateDetector(sess, dt)
	local P, p = sess.P, sess.p
	sess.nearSpot = nil
	sess.signal = 0
	if not P.tack.detector or not p.detector then return end
	local targets = table.clone(spots)
	if P.bigTreasure then table.insert(targets, { x = P.bigTreasure.x, y = P.bigTreasure.y, big = true }) end
	local bd = 450
	for _, s in ipairs(targets) do
		local d = hypot(s.x - p.x, s.y - p.y)
		if d < bd then bd = d; sess.nearSpot = s end
	end
	if not sess.nearSpot then return end
	sess.signal = 1 - bd / 450
	sess.beepT = (sess.beepT or 0) - dt
	if sess.beepT <= 0 then
		sess.beepT = 1.3 - sess.signal * 1.15
		G.R.Sfx:FireClient(sess.player, "beep", 400 + sess.signal * 900)
	end
end
local function canDig(sess)
	local n = sess.nearSpot
	return n ~= nil and hypot(n.x - sess.p.x, n.y - sess.p.y) < 45
end
function Farm.give(sess, item, n)
	local P = sess.P
	if item == "money" then
		P.money += n
		return n .. " 💰"
	end
	P.inv[item] = (P.inv[item] or 0) + n
	G.dirty(sess)
	return Items.icon(item) .. " " .. Items.name(item) .. (n > 1 and (" ×" .. n) or "")
end
local give = Farm.give

function Farm.dig(sess)
	local P, s = sess.P, sess.nearSpot
	if not s or not canDig(sess) then return end
	if s.big then
		P.bigTreasure = false
		give(sess, "money", 250); give(sess, "dye_rainbow", 1); give(sess, "brooch", 1)
		G.toast(sess, "🗝️ Ты нашла большой клад по карте! 250 монет, радужная краска и брошь!", "good")
		G.sfx(sess, "fanfare")
	else
		local real = Util.find(spots, function(q) return q.x == s.x and q.y == s.y end)
		if not real then return end
		Util.removeValue(spots, real)
		task.delay(20, function() table.insert(spots, Farm.newSpot()) end)
		local r = math.random() + (s.cave and 0.15 or 0)
		local text
		if r < 0.33 then
			local c = math.floor(rand(15, 50) + 0.5)
			give(sess, "money", c)
			text = c .. " монет 💰"
		elseif r < 0.48 then text = give(sess, "oldShoe", 1)
		elseif r < 0.58 then text = give(sess, "oldCoin", 1)
		elseif r < 0.65 then text = give(sess, "spoon", 1)
		elseif r < 0.71 then text = give(sess, "bell", 1)
		elseif r < 0.78 then text = give(sess, Util.pick({ "seed_carrot", "seed_pumpkin", "seed_sunflower", "seed_oats" }), 3)
		elseif r < 0.85 then text = give(sess, Util.pick({ "dye_pink", "dye_blue", "dye_purple", "dye_mint" }), 1)
		elseif r < 0.9 then text = give(sess, "brooch", 1)
		elseif r < 0.94 then text = give(sess, "seed_magic", 1)
		elseif r < 0.98 or P.bigTreasure then text = give(sess, "goldShoe", 1)
		else
			local q = nil
			for _ = 1, 50 do
				local c = Farm.newSpot()
				if hypot(c.x - sess.p.x, c.y - sess.p.y) > 1500 then q = c; break end
			end
			q = q or Farm.newSpot()
			P.bigTreasure = { x = q.x, y = q.y }
			text = give(sess, "map", 1) .. " — на миникарте появился крестик ✖"
		end
		G.toast(sess, "⛏️ Клад! Ты нашла: " .. text, "good")
		G.sfx(sess, "coin")
	end
	G.stat(sess, "treasures")
	G.float("⛏️", s.x, s.y - 20, "#b07800")
	sess.nearSpot = nil
	G.dirty(sess)
end

--[[ ================= грибы ================= ]]
local shroomAcc = 0
local function updateShrooms(dt)
	shroomAcc += dt
	if shroomAcc < 0.2 then return end
	shroomAcc = 0
	local t = G.time
	for id, at in pairs(picked) do
		if t > at then
			picked[id] = nil
			pickedDirty = true
		end
	end
	for _, sess in ipairs(G.each()) do
		local p = sess.p
		if not sess.p.mountId and not p.fly and p.y <= World.H then
			for _, m in ipairs(World.SHROOMS) do
				if math.abs(m.x - p.x) <= 22 and math.abs(m.y - p.y) <= 22 and not picked[m.id] then
					if m.type == "amanita" then
						if t > (sess.toadWarnT or 0) then
							sess.toadWarnT = t + 8
							G.toast(sess, "🍄 Это мухомор — он ядовитый, его не собираем!")
						end
					else
						picked[m.id] = t + 300
						pickedDirty = true
						local item = (m.type == "glow" or m.type == "violet") and "glowshroom" or "mushroom"
						sess.P.inv[item] = (sess.P.inv[item] or 0) + 1
						G.stat(sess, "mushrooms")
						G.float(Items.icon(item) .. " +1", m.x, m.y - 20, "#1b8a3a")
						G.sfx(sess, "tick")
					end
				end
			end
		end
	end
end
function Farm.pickedList()
	local out = {}
	for id in pairs(picked) do table.insert(out, id) end
	return out
end
function Farm.takePickedDirty()
	local d = pickedDirty
	pickedDirty = false
	return d
end

--[[ ================= сундук графа ================= ]]
local function openChest(sess)
	local P = sess.P
	P.flags.chest_opened = true
	give(sess, "money", 200); give(sess, "crown", 1); give(sess, "goldShoe", 1)
	G.toast(sess, "🧰 Сундук графа! Внутри 200 монет, корона и золотая подкова!", "good")
	G.sfx(sess, "fanfare")
	G.dirty(sess)
end

--[[ ================= подсказки ================= ]]
function Farm.prompt(sess)
	local P, p = sess.P, sess.p
	if canDig(sess) then return { label = "⛏️ Копать клад", fn = function() Farm.dig(sess) end } end
	if not P.flags.chest_opened and hypot(p.x - World.CHEST.x, p.y - World.CHEST.y) < 90 then
		return { label = "🧰 Открыть сундук", fn = function() openChest(sess) end }
	end
	local bed = Farm.nearestBuild(sess, { "bed" }, 40)
	if bed then
		local label = bed.crop and (bed.grow >= 1 and "🧺 Собрать урожай" or "🌱 Грядка") or "🌱 Посадить"
		return { label = label, fn = function()
			if bed.crop and bed.grow >= 1 then Farm.harvest(sess, bed.id) else G.open(sess, "bed", { id = bed.id }) end
		end }
	end
	local tr = Farm.nearestBuild(sess, { "tree" }, 40)
	if tr and (tr.t or 0) <= 0 then
		return { label = "🍎 Собрать яблоки", fn = function()
			tr.t = 180
			give(sess, "apple", 3)
			G.float("🍎 +3", tr.x, tr.y - 30, "#1b8a3a")
			G.sfx(sess, "coin")
			buildsDirty = true
		end }
	end
	local hs = Farm.nearestBuild(sess, { "haystack" }, 40)
	if hs and not hs.used then
		return { label = "🌾 Взять сено", fn = function()
			hs.used = true
			give(sess, "hay", 5)
			G.float("🌾 +5", hs.x, hs.y - 30, "#1b8a3a")
			G.sfx(sess, "coin")
			buildsDirty = true
		end }
	end
	return nil
end

function Farm.update(dt)
	updateBuilds(dt)
	for _, s in ipairs(G.each()) do updateDetector(s, dt) end
	updateShrooms(dt)
end

function Farm.canDig(sess) return canDig(sess) end
function Farm.bunnyHomes()
	local out = {}
	for _, it in ipairs(allBuilds()) do
		if it.b.type == "bunnyhouse" then table.insert(out, it.b) end
	end
	return out
end

-- постройки для отрисовки у всех клиентов
function Farm.takeBuildsDirty()
	local d = buildsDirty
	buildsDirty = false
	return d
end
function Farm.buildsSnapshot()
	local out = {}
	for _, it in ipairs(allBuilds()) do
		local b = it.b
		table.insert(out, {
			owner = it.sess.player.UserId, ownerName = G.playerName(it.sess), id = b.id, type = b.type, x = b.x, y = b.y, rot = b.rot or 0,
			crop = b.crop or nil, grow = b.grow, wet = b.wet, t = b.t, used = b.used,
		})
	end
	return out
end

return Farm
