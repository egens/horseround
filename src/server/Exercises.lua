--[[
	Упражнения (перенос из js/game.js): кавалетти, выездка (два теста), конкур.
	У каждого игрока своё упражнение (sess.ex), манеж и конкурное поле общие.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Items = require(Shared.Items)

local Ex = {}
local G
local clamp, hypot = Util.clamp, Util.hypot

Ex.JUMP_HEIGHTS = { 60, 80, 100, 120 }
Ex.JUMP_NORM = 75
function Ex.comfortHeight(h)
	return math.floor((50 + Horses.skill(h, "jump") * 0.7) / 5 + 0.5) * 5
end

function Ex.init(g) G = g end

function Ex.inArena(p)
	local A = World.ARENA
	return World.inRect(p.x, p.y, { x = A.x + 4, y = A.y + 4, w = A.w - 8, h = A.h - 8 })
end
function Ex.inJumpField(p)
	local J = World.JUMPF
	return World.inRect(p.x, p.y, { x = J.x + 4, y = J.y + 4, w = J.w - 8, h = J.h - 8 })
end

local function course(sess, data)
	if sess.player.Parent then G.R.Course:FireClient(sess.player, data) end
end

function Ex.start(sess, kind)
	local m = G.mounted(sess)
	if not m then return end
	G.R.Open:FireClient(sess.player, "close")
	if sess.race then return G.toast(sess, "Сначала закончи скачки") end
	if m.energy < 15 then return G.toast(sess, m.name .. " слишком " .. Horses.v(m, "устала", "устал") .. ". Дай отдохнуть или покорми овсом.", "warn") end
	if kind == "cav" then
		local poles = {}
		for _, x in ipairs(World.CAV.poles) do table.insert(poles, { x = x, state = nil }) end
		sess.ex = { type = "cav", lift = 0, cd = 0, started = false, outT = 0, prevX = sess.p.x, poles = poles }
		G.toast(sess, "Кавалетти: заезжай на жерди слева РЫСЬЮ и жми «Ноги выше!» прямо перед каждой жердью")
		course(sess, { type = "cav" })
	else
		local test = Items.TESTS[kind]
		if not test then return end
		sess.ex = { type = "dres", test = test, testKey = kind, i = 1, segT = 0, ok = 0, haltT = 0, arrive = nil, marks = {}, targetLetter = test.steps[1].to }
		G.toast(sess, "Выездка: " .. test.name .. ". Следуй указаниям и держи нужный аллюр!")
		course(sess, { type = "dres", letter = test.steps[1].to })
	end
end

function Ex.startJumping(sess, height)
	local m = G.mounted(sess)
	if not m then return end
	height = tonumber(height)
	if not table.find(Ex.JUMP_HEIGHTS, height) then return end
	G.R.Open:FireClient(sess.player, "close")
	if sess.race then return G.toast(sess, "Сначала закончи скачки") end
	if m.energy < 20 then return G.toast(sess, m.name .. " " .. Horses.v(m, "устала", "устал") .. ". Дай отдохнуть или покорми овсом.", "warn") end
	local jumps = {}
	for i = 1, #World.COURSE do jumps[i] = false end
	sess.ex = { type = "jump", height = height, i = 1, faults = 0, refusals = 0, t = 0, air = 0, cd = 0, takeoff = 0, prevAlong = -1e9, jumps = jumps }
	G.toast(sess, "Конкур " .. height .. " см: проходи препятствия по порядку ГАЛОПОМ, жми «Прыжок!» (Пробел) прямо перед жердями")
	course(sess, { type = "jump", i = 1, height = height })
end

function Ex.cancel(sess, msg)
	if not sess.ex then return end
	sess.ex = nil
	course(sess, nil)
	if msg then G.toast(sess, msg, "warn") end
end

--[[ ---------- кавалетти ---------- ]]
function Ex.liftLegs(sess)
	local ex = sess.ex
	if not ex then return end
	if ex.type == "jump" then return Ex.jumpPress(sess) end
	if ex.type ~= "cav" or ex.cd > 0 then return end
	local p = sess.p
	local nextPole
	for _, s in ipairs(ex.poles) do
		if not s.state and s.x > p.x then nextPole = s; break end
	end
	ex.cd = 0.3
	if nextPole and nextPole.x - p.x > 80 then
		G.float("Рано!", p.x, p.y - 40, "#b07800")
		ex.cd = 0.55
		return
	end
	ex.lift = 0.42
	G.R.Course:FireClient(sess.player, { type = "cav", lift = true })
end

local function updateCav(sess, dt)
	local ex, p, C, m = sess.ex, sess.p, World.CAV, G.mounted(sess)
	local inLane = p.y > C.y1 - 15 and p.y < C.y2 + 15
	ex.lift -= dt
	ex.cd -= dt
	for _, pole in ipairs(ex.poles) do
		if not pole.state and inLane and ex.prevX < pole.x and p.x >= pole.x then
			ex.started = true
			if p.gait ~= 1 then
				pole.state = "hit"
				G.float(p.gait == 2 and "Слишком быстро!" or "Нужна рысь!", pole.x, C.y1 - 10, "#c92a2a")
				G.sfx(sess, "thud")
			elseif ex.lift > 0 then
				pole.state = "ok"
				G.float("Чисто!", pole.x, C.y1 - 10, "#1b8a3a")
				G.sfx(sess, "tick")
			else
				pole.state = "hit"
				G.float("Стук!", pole.x, C.y1 - 10, "#c92a2a")
				G.sfx(sess, "thud")
			end
		end
	end
	ex.prevX = p.x
	if ex.started then
		ex.outT = inLane and 0 or ex.outT + dt
		local all = true
		for _, s in ipairs(ex.poles) do
			if not s.state then all = false end
		end
		if all or ex.outT > 1 or p.x < C.poles[1] - 120 then
			local clean = Util.count(ex.poles, function(s) return s.state == "ok" end)
			local money = clean * 8 + (clean == 5 and 20 or 0)
			sess.P.money += money
			Horses.addTrain(m, "jump", clean * 0.8)
			m.energy = clamp(m.energy - 6, 0, 100)
			m.mood = clamp(m.mood + 3, 0, 100)
			local medal = clean == 5 and "gold" or clean == 4 and "silver" or clean == 3 and "bronze" or nil
			if clean == 5 then G.stat(sess, "cavClean") end
			if medal then G.stat(sess, medal) end
			sess.ex = nil
			course(sess, nil)
			G.open(sess, "result", { title = "Кавалетти", clean = clean, total = 5, money = money, medal = medal, extra = "Прыжки: " .. Horses.skill(m, "jump") })
			G.sfx(sess, medal and "fanfare" or "tick")
			G.dirty(sess)
		end
	end
end

--[[ ---------- выездка ---------- ]]
local function finishDres(sess)
	local ex, m = sess.ex, G.mounted(sess)
	local marks = ex.marks
	local sum = 0
	for _, x in ipairs(marks) do sum += x.mark end
	local pct = #marks > 0 and (sum / (#marks * 10)) * 100 or 0
	local money = math.floor(pct / 2 + 0.5)
	sess.P.money += money
	Horses.addTrain(m, "dressage", pct / 20)
	m.energy = clamp(m.energy - 8, 0, 100)
	local medal = pct >= 70 and "gold" or pct >= 60 and "silver" or pct >= 50 and "bronze" or nil
	if pct >= 60 then G.stat(sess, "dres60") end
	if medal then G.stat(sess, medal) end
	local name = ex.test.name
	sess.ex = nil
	course(sess, nil)
	G.open(sess, "dressageResult", { name = name, marks = marks, pct = pct, money = money, medal = medal, skill = Horses.skill(m, "dressage") })
	G.sfx(sess, medal and "fanfare" or "tick")
	G.dirty(sess)
end

local function updateDres(sess, dt)
	local ex, p, m = sess.ex, sess.p, G.mounted(sess)
	local st = ex.test.steps[ex.i]
	local tp = World.letterTarget(st.to)
	local d = hypot(p.x - tp.x, p.y - tp.y)
	ex.targetLetter = st.to
	ex.segT += dt
	local function nextStep(mark)
		if mark ~= nil then table.insert(ex.marks, { text = st.text, mark = math.floor(mark * 2 + 0.5) / 2 }) end
		ex.i += 1
		ex.segT, ex.ok, ex.haltT, ex.arrive = 0, 0, 0, nil
		G.sfx(sess, "tick")
		if ex.i > #ex.test.steps then return finishDres(sess) end
		course(sess, { type = "dres", letter = ex.test.steps[ex.i].to })
	end
	if st.halt then
		if d < 45 then
			if ex.arrive == nil then ex.arrive = ex.segT end
			ex.haltT = p.spd < 12 and ex.haltT + dt or 0
			if ex.haltT >= 1.5 then return nextStep(clamp(10 - math.max(0, ex.segT - ex.arrive - 1.5) * 1.5, 3, 10)) end
		end
		if ex.segT > 25 then nextStep(0) end
		return
	end
	if st.gait ~= nil and p.spd > 15 and p.gait == st.gait then ex.ok += dt end
	if d < 40 then
		if st.gait == nil then return nextStep(nil) end
		local ratio = ex.ok / math.max(0.1, ex.segT)
		return nextStep(clamp(ratio * 8 + (Horses.skill(m, "dressage") / 100) * 2, 0, 10))
	end
	if ex.segT > 30 then
		if st.gait == nil then nextStep(nil) else nextStep(0) end
	end
end

--[[ ---------- конкур ---------- ]]
function Ex.jumpPress(sess)
	local ex = sess.ex
	if not ex or ex.type ~= "jump" or ex.air > 0 or ex.cd > 0 then return end
	local p = sess.p
	if p.spd < 30 then return end
	local o = World.COURSE[ex.i]
	local dx, dy = math.cos(o.a), math.sin(o.a)
	ex.takeoff = -((p.x - o.x) * dx + (p.y - o.y) * dy)
	ex.air = 0.6
	ex.cd = 0.8
	G.sfx(sess, "whoosh")
	G.R.Course:FireClient(sess.player, { type = "jump", i = ex.i, height = ex.height, jump = true })
end

local function finishJump(sess, eliminated)
	local ex, m = sess.ex, G.mounted(sess)
	local over = math.max(0, math.ceil((ex.t - Ex.JUMP_NORM) / 4))
	local faults = ex.faults + over
	local clean = Util.count(ex.jumps, function(j) return j == "ok" end)
	local base = ({ [60] = 30, [80] = 50, [100] = 80, [120] = 120 })[ex.height]
	local money, medal = 0, nil
	if not eliminated then
		money = math.floor(base * (faults == 0 and 1 or faults <= 4 and 0.6 or faults <= 8 and 0.35 or 0.15) + 0.5)
		medal = faults == 0 and "gold" or faults <= 4 and "silver" or faults <= 8 and "bronze" or nil
		if medal then G.stat(sess, medal) end
	end
	sess.P.money += money
	Horses.addTrain(m, "jump", clean * 0.5 * (ex.height / 80))
	m.energy = clamp(m.energy - 15, 0, 100)
	if not eliminated then
		G.stat(sess, "jumpRounds")
		if faults == 0 and ex.height >= 80 then G.stat(sess, "jump80") end
	end
	local res = { height = ex.height, t = ex.t, norm = Ex.JUMP_NORM, over = over, faults = faults, clean = clean, total = #World.COURSE,
		eliminated = eliminated, money = money, medal = medal, skill = Horses.skill(m, "jump") }
	sess.ex = nil
	course(sess, nil)
	G.open(sess, "jumpResult", res)
	G.sfx(sess, medal and "fanfare" or "tick")
	G.dirty(sess)
end

local function updateJump(sess, dt)
	local ex, p, m = sess.ex, sess.p, G.mounted(sess)
	ex.t += dt
	ex.air = math.max(0, ex.air - dt)
	ex.cd = math.max(0, ex.cd - dt)
	local o = World.COURSE[ex.i]
	local dx, dy = math.cos(o.a), math.sin(o.a)
	local along = (p.x - o.x) * dx + (p.y - o.y) * dy
	local lat = math.abs(-(p.x - o.x) * dy + (p.y - o.y) * dx)
	local crossed = ex.prevAlong < 0 and along >= 0 and lat < o.half + 12
	ex.prevAlong = along
	if not crossed then return end
	local st
	if p.gait == 0 or p.spd < 40 then
		ex.refusals += 1
		ex.faults += 4
		G.teleport(sess, p.x - dx * 90, p.y - dy * 90)
		ex.prevAlong = -90
		G.float("Отказ! +4", o.x, o.y - 50, "#c92a2a")
		G.sfx(sess, "fail")
		if ex.refusals >= 3 then return finishJump(sess, true) end
		return
	end
	if ex.air > 0 then
		local chance = 0.96 - math.max(0, ex.height - Ex.comfortHeight(m)) * 0.025
		if p.gait == 1 and ex.height > 60 then chance -= 0.3 end
		local tk = ex.takeoff
		if tk < 15 or tk > 110 then chance -= 0.25 end
		if m.mood < 30 then chance -= 0.1 end
		if sess.P.tack.boots then chance += 0.03 end
		chance = clamp(chance, 0.05, 0.98)
		st = math.random() < chance and "ok" or "hit"
	else
		st = "hit"
	end
	ex.jumps[ex.i] = st
	if st == "ok" then
		G.float("Чисто!", o.x, o.y - 50, "#1b8a3a")
		G.sfx(sess, "tick")
	else
		ex.faults += 4
		G.float(ex.air > 0 and "Повал! +4" or "Не прыгнула! +4", o.x, o.y - 50, "#c92a2a")
		G.sfx(sess, "thud")
	end
	ex.i += 1
	ex.prevAlong = -1e9
	if ex.i > #World.COURSE then return finishJump(sess, false) end
	course(sess, { type = "jump", i = ex.i, height = ex.height })
end

function Ex.update(sess, dt)
	local ex = sess.ex
	if not ex then return end
	if not G.mounted(sess) then
		Ex.cancel(sess)
		return
	end
	local inArea = ex.type == "jump" and Ex.inJumpField(sess.p) or (ex.type ~= "jump" and Ex.inArena(sess.p))
	if not inArea then
		return Ex.cancel(sess, ex.type == "jump" and "Ты выехала с конкурного поля — маршрут прерван" or "Ты выехала из манежа — упражнение прервано")
	end
	if ex.type == "cav" then updateCav(sess, dt)
	elseif ex.type == "jump" then updateJump(sess, dt)
	else updateDres(sess, dt) end
end

-- строка упражнения для HUD
function Ex.hud(sess)
	local ex, p = sess.ex, sess.p
	if not ex then return nil end
	if ex.type == "jump" then
		local o = World.COURSE[math.min(ex.i, #World.COURSE)]
		local good = p.gait == 2 or (ex.height <= 60 and p.gait == 1)
		return {
			title = "Конкур " .. ex.height .. " см",
			line = "Препятствие №" .. o.n .. " (" .. o.name .. ") · штраф: " .. ex.faults .. " · время " .. math.floor(ex.t) .. "/" .. Ex.JUMP_NORM .. " с",
			hint = good and "Галоп ✔ Жми «Прыжок!» (Пробел) прямо перед жердями" or "Переходи на ГАЛОП (клавиша 3)",
			ok = good, lift = true, liftLabel = "⤴ Прыжок!", letter = tostring(o.n),
		}
	end
	if ex.type == "cav" then
		local clean = Util.count(ex.poles, function(s) return s.state == "ok" end)
		local done = Util.count(ex.poles, function(s) return s.state ~= nil end)
		return {
			title = "Кавалетти", line = "Жерди: " .. done .. "/5 · чисто: " .. clean,
			hint = p.gait == 1 and "Рысь ✔ Жми «Ноги выше!» (Пробел) перед жердью" or "Переходи на РЫСЬ (клавиша 2)",
			ok = p.gait == 1, lift = true, liftLabel = "⤴ Ноги выше!",
		}
	end
	local st = ex.test.steps[ex.i]
	if not st then return nil end
	local need = st.halt and "Стоп" or (st.gait == nil and "любой" or Items.GAITS[st.gait + 1])
	local ok
	if st.halt then ok = p.spd < 12 else ok = st.gait == nil or (p.gait == st.gait and p.spd > 15) end
	return {
		title = "Выездка: " .. ex.test.name,
		line = ex.i .. "/" .. #ex.test.steps .. ": " .. st.text,
		hint = "Буква " .. st.to .. " · аллюр: " .. need .. (st.halt and " (остановись на 2 сек.)" or ""),
		ok = ok, letter = st.to,
	}
end

return Ex
