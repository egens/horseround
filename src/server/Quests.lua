--[[
	Задания на сервере: взять, сдать, доска заданий, посещения мест (перенос js/quests.js).
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Q = require(Shared.QuestData)

local Quests = {}
local G

function Quests.init(g) G = g end

local function giveReward(sess, r)
	for k, v in pairs(r) do G.modules.Farm.give(sess, k, v) end
end

function Quests.accept(sess, id)
	local q = Q.byId(id)
	local P = sess.P
	if not q or P.quests[id] then return end
	local c = Q.current(P, q.npc)
	if not c or c.q.id ~= id then return end
	P.quests[id] = { state = "active", base = q.goal.stat and (P.stats[q.goal.stat] or 0) or 0 }
	G.toast(sess, "📜 Новое задание: " .. q.title, "good")
	G.sfx(sess, "tick")
	G.dirty(sess)
end

function Quests.turnIn(sess, id)
	local q = Q.byId(id)
	local P = sess.P
	local st = q and P.quests[id]
	if not st or st.state ~= "active" or not Q.complete(P, q, st) then return end
	if q.goal.item then P.inv[q.goal.item] -= q.goal.n end
	st.state = "done"
	giveReward(sess, q.reward)
	G.stat(sess, "questsDone")
	G.toast(sess, "🎉 Задание «" .. q.title .. "» выполнено! Награда: " .. Q.rewardText(q.reward), "good")
	G.sfx(sess, "fanfare")
	G.dirty(sess)
end

local function boardState(P)
	if not P.board then P.board = { i = math.random(1, #Q.BOARD) } end
	return P.board
end
function Quests.boardAccept(sess)
	local P = sess.P
	local b = boardState(P)
	if b.base ~= nil then return end
	local q = Q.BOARD[b.i]
	b.base = q.goal.stat and (P.stats[q.goal.stat] or 0) or 0
	G.toast(sess, "📜 Задание с доски: " .. q.title, "good")
	G.dirty(sess)
end
function Quests.boardTurnIn(sess)
	local P = sess.P
	local b = boardState(P)
	local q = Q.BOARD[b.i]
	if b.base == nil or not Q.complete(P, q, { base = b.base }) then return end
	giveReward(sess, q.reward)
	G.stat(sess, "questsDone")
	G.toast(sess, "🎉 Задание с доски выполнено! +" .. Q.rewardText(q.reward), "good")
	G.sfx(sess, "fanfare")
	local n = b.i
	while n == b.i do n = math.random(1, #Q.BOARD) end
	b.i, b.base = n, nil
	G.dirty(sess)
end

-- посещения мест
function Quests.updateVisits(sess)
	local P, p = sess.P, sess.p
	local f = P.flags
	local reg = World.regionAt(p.x, p.y)
	local function visit(k, msg)
		if not f[k] then
			f[k] = true
			if msg then G.toast(sess, msg, "good") end
			G.dirty(sess)
		end
	end
	if reg == "forest" then visit("visit_forest") end
	if reg == "village" then visit("visit_village", "🏘️ Ты пришла в деревню! Здесь живут кузнец, стилистка и есть доска заданий.") end
	if reg == "mushroom" then visit("visit_mushroom", "🍄 Грибное королевство! Здесь живут волшебные лошадки.") end
	if reg == "cave" then visit("visit_cave", "🦇 Ты в пещере. Здесь темно... и кто-то бродит.") end
	if reg == "lake" then visit("visit_lake") end
	if p.x > World.OX + 5450 and math.abs(p.y - World.OY - 1150) < 600 and reg == "lake" then visit("visit_lake_east", "🌊 Восточный берег Большого озера!") end
	if reg == "desert" then visit("visit_desert", "🏜️ Пустыня! Здесь бегают зебры, а раз в 30 минут к станции приезжает поезд с лошадьми.") end
	if reg == "tundra" then visit("visit_tundra", "❄️ Тундра! Здесь живут мохнатые якутские лошади.") end
	if reg == "deepforest" then visit("visit_deepforest", "🌲 Дремучий лес. Здесь темно даже днём.") end
	if Util.hypot(p.x - World.OASIS.x, p.y - World.OASIS.y) < 520 then visit("visit_oasis", "🌴 Оазис! Вода и пальмы посреди песков.") end
	if reg == "grotto" then visit("visit_grotto", "⛰️ Пещерные холмы! В маленьких пещерках живут лошади со светящимися узорами.") end
	if reg == "foxwood" then visit("visit_foxwood", "🦊 Лисий лес — густой и тёмный. Здесь живут лисьи лошади!") end
	if reg == "dragonrock" then visit("visit_dragonrock", "🐲 Драконьи скалы! Чешуйчатые лошади с драконьими крыльями.") end
	if reg == "steppe" then visit("visit_steppe", "🌾 Степь! Здесь бегают дикие лошади Пржевальского и олени.") end
	local I = World.islandAt(p.x, p.y)
	if I and not f["visit_" .. I.id] then
		visit("visit_" .. I.id, "🏝️ " .. I.name .. "! Здесь конюшня, пастбище, манеж и 5 диких лошадей.")
		G.stat(sess, "islandsVisited")
	end
end

function Quests.nearNpc(sess, r)
	local p = sess.p
	local best, bd = nil, r or 80
	for _, n in ipairs(Q.NPCS) do
		local d = Util.hypot(n.x - p.x, n.y - p.y)
		if d < bd then bd = d; best = n end
	end
	return best
end

function Quests.prompt(sess)
	local n = Quests.nearNpc(sess)
	if n then return { label = "💬 " .. n.name, fn = function() G.open(sess, "npc", { id = n.id, line = Util.pick(n.hello) }) end } end
	local p = sess.p
	if Util.hypot(World.BOARD.x - p.x, World.BOARD.y - p.y) < 70 then
		return { label = "📋 Доска заданий", fn = function()
			boardState(sess.P)
			G.dirty(sess)
			G.open(sess, "board", {})
		end }
	end
	return nil
end

function Quests.tip(npcId)
	local n = Q.npcById(npcId)
	return n and Util.pick(n.tips) or ""
end

return Quests
