--[[
	Металлоискатель и клады, сбор грибов, сундук графа (перенос js/farm.js).
	Стройки и огорода больше нет: на общем сервере чужие постройки только мешали.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)

local Farm = {}
local G
local rand, hypot = Util.rand, Util.hypot

local spots = {}              -- где зарыты клады (общие)
local picked = {}             -- сорванные грибы: id → когда вырастут
local pickedDirty = true

function Farm.init(g)
	G = g
	while #spots < 14 do table.insert(spots, Farm.newSpot()) end
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
		elseif r < 0.78 then text = give(sess, Util.pick({ "carrot", "pumpkin", "sunflower", "apple" }), 2)
		elseif r < 0.85 then text = give(sess, Util.pick({ "dye_pink", "dye_blue", "dye_purple", "dye_mint" }), 1)
		elseif r < 0.9 then text = give(sess, "brooch", 1)
		elseif r < 0.94 then text = give(sess, "pollen", 1)
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
	return nil
end

function Farm.update(dt)
	for _, s in ipairs(G.each()) do updateDetector(s, dt) end
	updateShrooms(dt)
end

function Farm.canDig(sess) return canDig(sess) end
return Farm
