--[[
	Подсказки, кнопка «E» и строка состояния для каждого игрока
	(перенос computePrompt, hint и updateHud из js/game.js).
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Stalls = require(Shared.Stalls)
local Q = require(Shared.QuestData)

local Hud = {}
local G
local hypot = Util.hypot

function Hud.init(g) G = g end

local function near(p, W, r)
	return hypot(p.x - (W.x + W.w / 2), p.y - (W.y + W.h / 2)) < (r or 130)
end

function Hud.computePrompt(sess)
	local M = G.modules
	local p, P = sess.p, sess.P
	if sess.ex or sess.race then return nil end
	local fp = M.Farm.prompt(sess)
	if fp then return fp end
	local qp = M.Quests.prompt(sess)
	if qp then return qp end
	local mp = M.Market.prompt(sess)
	if mp then return mp end
	local piers = { World.PIER }
	for _, I in ipairs(World.ISLANDS) do table.insert(piers, I.pier) end
	if Util.some(piers, function(q) return hypot(q.x - p.x, q.y - p.y) < 130 end) then
		return { label = "⛵ Лодка", fn = function() G.open(sess, "boat", { islandT = M.Herds.islandTimeLeft() }) end }
	end
	if Stalls.islandStableHere(p.x, p.y) then return { label = "🐴 Мои лошади", fn = function() G.open(sess, "stable", { can = true }) end } end
	local ep = M.Events.prompt(sess)
	if ep then return ep end
	if World.inRect(p.x, p.y, World.STABLE, 30) or World.inRect(p.x, p.y, World.PADDOCK, 30) then
		return { label = "🐴 Мои лошади", fn = function() G.open(sess, "stable", { can = true }) end }
	end
	if near(p, World.SELL) then return { label = "💰 Продать лошадь", fn = function() G.open(sess, "sell", { fair = M.Events.fair() }) end } end
	if near(p, World.SHOP) then return { label = "🛒 Корм и амуниция", fn = function() G.open(sess, "shop", {}) end } end
	if M.Exercises.inArena(p) then
		if G.mounted(sess) then return { label = "🏆 Тренировка", fn = function() G.open(sess, "training", {}) end } end
		return { label = "🏆 Тренировка", fn = function() G.toast(sess, "Чтобы тренироваться, сядь на лошадь в конюшне") end }
	end
	if M.Exercises.inJumpField(p) then
		if G.mounted(sess) then return { label = "🏆 Конкур", fn = function() G.open(sess, "jumping", {}) end } end
		return { label = "🏆 Конкур", fn = function() G.toast(sess, "Для конкура сядь на лошадь в конюшне") end }
	end
	return nil
end

function Hud.hint(sess)
	local M = G.modules
	local p, P = sess.p, sess.P
	local tk = P.tack
	if #P.horses == 0 and not sess.led then return "Иди в поле на восток от фермы и поймай лошадь лассо (клавиша F или клик по лошади). Спокойных лошадей ловить легче!" end
	if sess.led then return "Веди лошадь по кличке " .. sess.led.name .. " в конюшню — она пойдёт за тобой" end
	if not tk.saddle or not tk.bridle then return "Купи седло и уздечку в повозке «Корм и амуниция», чтобы ездить верхом" end
	local m = G.mounted(sess)
	if not m then return "Открой конюшню (E) и сядь на лошадь. Тренируйся в манеже!" end
	if sess.ex or sess.race then return "" end
	if M.Exercises.inArena(p) then return "Нажми «Тренировка» (E): кавалетти или выездка" end
	if M.Exercises.inJumpField(p) then return "Нажми «Конкур» (E) и выбери высоту препятствий" end
	if p.fly then return "Ты летишь! Пробел — выше, Ctrl/C — ниже, V — приземлиться" end
	local reg = World.regionAt(p.x, p.y)
	if reg == "cave" then
		if hypot(p.x - World.PORTAL.x, p.y - World.PORTAL.y) < 700 then return "🌀 Впереди светится портал на небесные острова — войди в него!" end
		return "В пещере темно. Здесь бродят лошади-скелеты и привидения, где-то спрятан сундук графа, а в глубине светится портал"
	end
	if reg == "market" then return "Рынок: покупай и продавай лошадей, торгуйся, прокачивай навыки и меняйся вещами" end
	if p.y > World.H then return "Небесные острова! Здесь живут крылатые и облачные лошадки. Портал домой — в центре Облачного острова" end
	if reg == "mushroom" then return "Грибное королевство: здесь живут пегасы, единороги и стихийные лошадки. В дождь здесь радужные лужи — и может прилететь розовый дракон!" end
	local Train = M.Specials.Train
	local tr = Train.hud()
	if tr.catchLeft and Train.near(p) then return "🚂 Поезд у станции! Лови красивых лошадей — осталось " .. math.ceil(tr.catchLeft) .. " с" end
	if reg == "desert" then
		return tr.moving and "🚂 По рельсам едет поезд — спеши к станции!" or ("Пустыня: здесь бегают зебры. Поезд с лошадьми приедет к станции через " .. math.ceil((tr.next or 0) / 60) .. " мин")
	end
	if reg == "grotto" then return "Пещерные холмы: загляни в маленькие пещерки — там живут чёрные лошади со светящимися узорами" end
	if reg == "grottocave" then return "✨ Пещерка! Чёрные лошади светятся своими узорами, а за ними тянется сияние" end
	if reg == "foxwood" or reg == "deepforest" then return "Густой лес: здесь живут лисьи лошади с пушистыми хвостами. Олени тоже где-то рядом" end
	if reg == "dragonrock" then return "Драконьи скалы: здесь живут чешуйчатые лошади с драконьими крыльями и рогами. Осторожно, лава!" end
	if reg == "steppe" then return "Степь: дикие лошади Пржевальского, олени и высокая трава" end
	if reg == "i4" then return "Костяной остров: лошади с черепами и рёбрами, а вокруг — огромные кости" end
	if G.isNight() then return "Ночь: табуны спят — подкрасться к лошадям легче. Фонари освещают ферму" end
	if #Q.journal(P) == 0 then return "Поговори с жителями (💬) — у них есть задания. Список заданий — кнопка 📜" end
	return "Аллюры: 1 — шаг, 2 — рысь, 3 — галоп. Задания — кнопка 📜, карта — M"
end

function Hud.build(sess)
	local M = G.modules
	local P, p = sess.P, sess.p
	local m = G.mounted(sess)
	local pr = Hud.computePrompt(sess)
	sess.promptObj = pr
	local walk = Util.find(P.horses, function(o) return o.state == "walk" end)
	local birth = Util.find(P.horses, function(o) return o.preg and o.preg.ready end)
	local catchable = M.Herds.nearestCatchable(sess)
	return {
		money = P.money, count = #P.horses, max = Stalls.totalStalls(P),
		medals = { gold = P.stats.gold or 0, silver = P.stats.silver or 0, bronze = P.stats.bronze or 0 },
		hint = Hud.hint(sess),
		prompt = pr and pr.label or nil,
		canLasso = catchable ~= nil and not sess.lasso,
		mounted = m and { id = m.id, name = m.name, gait = p.gait, energy = math.floor(m.energy), wings = Horses.canFly(m), fly = p.fly or false } or nil,
		led = sess.led and sess.led.name or nil,
		exercise = M.Events.hud(sess) or M.Exercises.hud(sess),
		clock = G.clockText(),
		detector = P.tack.detector and { on = p.detector or false, signal = math.floor((sess.signal or 0) * 100) / 100 } or nil,
		quests = #Q.journal(P),
		region = World.REGION_NAMES[World.regionAt(p.x, p.y)] or "",
		walk = walk and walk.name or nil,
		birth = birth and birth.name or nil,
		train = M.Specials.Train.hud(), holiday = M.Specials.Holidays.hud(),
		bigTreasure = P.bigTreasure or nil,
		atFarm = Stalls.atFarm(P, p.x, p.y),
		nearSell = M.Actions.nearSell(sess),
		herdField = { x = M.Herds.HERDS.field.x, y = M.Herds.HERDS.field.y },
	}
end

return Hud
