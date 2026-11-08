--[[
	Игрок и езда верхом: положение персонажа, сесть/слезть, аллюры, усталость лошади,
	полёт на крылатых и облачных лошадях, портал, круглый манеж на острове, лодка.
	Лошадь под седлом рисуют клиенты под персонажем: данные — в StringValue «Mount».
]]
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Stalls = require(Shared.Stalls)

local Riding = {}
local G, Herds
local clamp, hypot = Util.clamp, Util.hypot
local K = World.K
local SADDLE_H = 14 * 0.45 -- высота седла в стадах (у лошади размера 1)

function Riding.init(g, herds) G, Herds = g, herds end

function Riding.gaitSpeed(h, gait)
	local f = 0.75 + Horses.skill(h, "speed") / 200
	local v = ({ 75, 155, 250 })[gait + 1] * (gait == 2 and f or 0.9 + f * 0.1)
	if h.hunger < 15 then v *= 0.75 end
	if h.age < 3 then v *= 0.8 end
	return v
end

-- упряжь для отрисовки
function Riding.tackLook(P)
	local t = P.tack
	return {
		pad = t.pad or "#7a6a55", saddleStyle = t.saddleStyle or "classic", saddleColor = t.saddleColor or "#5b3a1e",
		bridleStyle = t.bridleStyle or "classic", bridleColor = t.bridleColor or "#2b1a10", boots = t.boots or nil,
	}
end

local function isR6(hum) return hum.RigType == Enum.HumanoidRigType.R6 end

function Riding.setupCharacter(sess, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	sess.baseHip = hum.HipHeight
	-- пешком скорость и прыжок задаёт клиент (Shift — бег, Пробел — прыжок), верхом — атрибуты RideSpeed/RideJump
	hum.UseJumpPower = false
	hum.JumpHeight = 7.2
	hum.WalkSpeed = 16
	char:SetAttribute("RideSpeed", 0)
	char:SetAttribute("RideJump", 0)
	char:SetAttribute("Gait", 0)
	char:SetAttribute("Flying", false)
	-- рубашка и шлем
	Riding.applyLook(sess)
end

-- цвет кофты и шлем на голове
function Riding.applyLook(sess)
	local char = sess.player.Character
	if not char then return end
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc then bc.TorsoColor3 = Util.color(sess.P.shirt or "#e05a8a") end
	local head = char:FindFirstChild("Head")
	local helmet = char:FindFirstChild("RiderHelmet")
	local want = G.mounted(sess) ~= nil and sess.P.tack.helmet
	if want and head then
		if not helmet then
			helmet = Instance.new("Part")
			helmet.Name = "RiderHelmet"
			helmet.Shape = Enum.PartType.Ball
			helmet.Size = Vector3.new(1.35, 1.35, 1.35)
			helmet.CanCollide = false
			helmet.CanQuery = false
			helmet.Massless = true
			helmet.Material = Enum.Material.SmoothPlastic
			local w = Instance.new("WeldConstraint")
			helmet.CFrame = head.CFrame * CFrame.new(0, 0.32, 0)
			w.Part0, w.Part1 = head, helmet
			w.Parent = helmet
			helmet.Parent = char
		end
		helmet.Color = Util.color(sess.P.tack.helmet)
	elseif helmet then
		helmet:Destroy()
	end
end

-- данные для клиента: какую лошадь рисовать под персонажем
function Riding.publishMount(sess)
	local char = sess.player.Character
	if not char then return end
	local m = G.mounted(sess)
	local v = char:FindFirstChild("Mount")
	if not m then
		if v then v:Destroy() end
		char:SetAttribute("MountAct", "")
		return
	end
	if not v then
		v = Instance.new("StringValue")
		v.Name = "Mount"
		v.Parent = char
	end
	local data = { look = Horses.look(m), tack = Riding.tackLook(sess.P), key = Horses.lookKey(m) }
	local json = HttpService:JSONEncode(data)
	if v.Value ~= json then v.Value = json end
	sess.mountKey = data.key
end

-- рост седла: HipHeight так, чтобы игрок сидел в седле
function Riding.applyHip(sess)
	local hum = G.humanoid(sess)
	if not hum or not sess.baseHip then return end
	local m = G.mounted(sess)
	if m then
		local s = Horses.sizeOf(m)
		hum.HipHeight = SADDLE_H * s - (isR6(hum) and 2 or 0) - 0.25
	else
		hum.HipHeight = sess.baseHip
	end
end

-- скорость верхом: сервер считает по аллюру, а клиент ставит её персонажу (атрибуты RideSpeed/RideJump)
function Riding.applySpeed(sess)
	local char = sess.player.Character
	local m = G.mounted(sess)
	local p = sess.p
	local v = 0
	if m and not m.act then v = Riding.gaitSpeed(m, p.gait) * (p.fly and 1.3 or 1) end
	if sess.race and sess.race.state == "countdown" then v = 0 end
	local want = math.floor(v * K * 100 + 0.5) / 100
	local jh = (m and sess.ex and sess.ex.type == "jump") and 4 or 0
	if char then
		if char:GetAttribute("RideSpeed") ~= want then char:SetAttribute("RideSpeed", want) end
		if char:GetAttribute("RideJump") ~= jh then char:SetAttribute("RideJump", jh) end
		if char:GetAttribute("Gait") ~= p.gait then char:SetAttribute("Gait", p.gait) end
		if char:GetAttribute("Flying") ~= (p.fly or false) then char:SetAttribute("Flying", p.fly or false) end
	end
end

-- положение игрока на карте
function Riding.syncPosition(sess, dt)
	local root = G.root(sess)
	local p = sess.p
	if not root then return end
	local x, y = World.fromStuds(root.Position)
	local ox, oy = p.x, p.y
	p.x, p.y = x, y
	local lv = root.CFrame.LookVector
	p.angle = math.atan2(lv.Z, lv.X)
	local vel = root.AssemblyLinearVelocity
	p.spd = math.sqrt(vel.X * vel.X + vel.Z * vel.Z) / K
	if sess.teleportT and sess.teleportT > 0 then
		sess.teleportT -= dt
	elseif dt > 0 then
		-- для упражнений: скорость по фактическому сдвигу
		local moved = hypot(x - ox, y - oy) / dt
		if moved < 2000 then p.spd = math.min(p.spd, moved + 30) end
	end
	p.alt = root.Position.Y
	-- упал с небесного острова — назад к порталу
	if y > World.H and root.Position.Y < World.SKY_Y - 60 and not p.fly then
		G.teleport(sess, World.SKY_PORTAL.x, World.SKY_PORTAL.y + 130)
		G.toast(sess, "☁️ Облачко подхватило тебя и вернуло на Облачный остров!")
	end
	if root.Position.Y < -60 and y <= World.H then
		G.teleport(sess, World.START.x - 400, World.START.y)
	end
end

function Riding.update(sess, dt)
	local p, m = sess.p, G.mounted(sess)
	if m and m.energy <= 0.5 and p.gait > 0 then
		p.gait = 0
		G.toast(sess, "😮‍💨 " .. m.name .. " " .. Horses.v(m, "устала", "устал") .. " — только шагом. Отдохните в конюшне.", "warn")
	end
	if p.fly and not Horses.canFly(m) then p.fly = false end
	if m then
		m.x, m.y, m.angle, m.spd = p.x, p.y, p.angle, p.spd
		if m.act then
			m.act.t += dt
			if m.act.t >= m.act.d then
				m.act = nil
				local char = sess.player.Character
				if char then char:SetAttribute("MountAct", "") end
			end
		end
		local moving = p.spd > 10
		local drain = ({ 0.12, 0.55, 1.5 })[p.gait + 1] * (1.4 - Horses.skill(m, "stamina") / 125)
		m.energy = clamp(m.energy - dt * (moving and drain or -0.4), 0, 100)
		if moving and p.gait > 0 then Horses.addTrain(m, "stamina", dt * 0.004) end
		if moving and p.gait == 2 then Horses.addTrain(m, "speed", dt * 0.005) end
		if p.fly then G.stat(sess, "flyTime", dt) end
		-- внешность лошади (грязь, мокрая шерсть) поменялась — обновить
		sess.mountCheckT = (sess.mountCheckT or 0) - dt
		if sess.mountCheckT <= 0 then
			sess.mountCheckT = 1
			if Horses.lookKey(m) ~= sess.mountKey then Riding.publishMount(sess) end
		end
	end
	Riding.applySpeed(sess)
end

--[[ ---------- сесть и слезть ---------- ]]
function Riding.mount(sess, h)
	local P, p = sess.P, sess.p
	if not Stalls.atFarm(P, p.x, p.y) then return G.toast(sess, "Подойди к конюшне или леваде") end
	if not P.tack.saddle or not P.tack.bridle then return G.toast(sess, "Нужны седло и уздечка — купи их в повозке «Корм и амуниция»", "warn") end
	if not Horses.canRide(h) then
		return G.toast(sess, "На жеребёнке можно ездить только с " .. Horses.RIDE_AGE .. " лет. " .. h.name .. " сейчас " .. Horses.ageText(h) .. " — гуляй с ним, корми и играй!", "warn")
	end
	if h.state == "walk" then h.state = "stall" end
	if h.energy < 5 then return G.toast(sess, h.name .. " " .. Horses.v(h, "устала", "устал") .. ". Пусть отдохнёт.", "warn") end
	if h.state == "market" then return G.toast(sess, h.name .. " стоит на рынке. Сначала сними с продажи у своей стойки", "warn") end
	if sess.led then return G.toast(sess, "Сначала отведи пойманную лошадь в конюшню", "warn") end
	local cur = G.mounted(sess)
	if cur then cur.state = "stall" end
	h.state = "ridden"
	h.act = nil
	p.mountId = h.id
	p.gait = 0
	p.fly = false
	if World.inRect(p.x, p.y, World.STABLE) then
		G.teleport(sess, World.STABLE.x + World.STABLE.w + 40, (World.AISLE_Y1 + World.AISLE_Y2) / 2)
	end
	h.x, h.y = p.x, p.y
	Riding.publishMount(sess)
	Riding.applyHip(sess)
	Riding.applyLook(sess)
	G.R.Open:FireClient(sess.player, "close")
	G.toast(sess, "🏇 Ты в седле! " .. h.name .. " ждёт команды. Аллюры: 1 — шаг, 2 — рысь, 3 — галоп")
	G.dirty(sess)
end

function Riding.dismount(sess, quiet)
	local m = G.mounted(sess)
	if not m then return end
	G.modules.Exercises.cancel(sess)
	G.modules.Events.leaveRace(sess, "Ты слезла с лошади — скачки прерваны")
	m.state = "stall"
	m.act = nil
	sess.p.mountId = nil
	sess.p.fly = false
	Riding.publishMount(sess)
	Riding.applyHip(sess)
	Riding.applyLook(sess)
	if not quiet then G.toast(sess, m.name .. " " .. Horses.v(m, "вернулась", "вернулся") .. ": " .. Stalls.label(m.stall)) end
	G.dirty(sess)
end

function Riding.setGait(sess, g)
	local m = G.mounted(sess)
	if not m then return end
	g = clamp(math.floor(tonumber(g) or 0), 0, 2)
	if g > 0 and m.energy <= 0.5 then return G.toast(sess, m.name .. " " .. Horses.v(m, "устала", "устал") .. " — только шагом", "warn") end
	sess.p.gait = g
end

-- трюк верхом: лошадь стоит на месте
function Riding.mountAct(sess, k)
	local m = G.mounted(sess)
	if not m then return end
	Herds.startAct(m, k)
	local char = sess.player.Character
	if char then
		char:SetAttribute("MountAct", string.format("%s|%f|%f|%d", m.act.k, workspace:GetServerTimeNow(), m.act.d, m.act.leg or 0))
	end
end

function Riding.toggleFly(sess)
	local p, m = sess.p, G.mounted(sess)
	if not Horses.canFly(m) then
		return G.toast(sess, "Летать умеют лошади с крыльями (пегасы, бабочки, драконы, вороны, стрекозы, пчёлки) и облачные лошадки")
	end
	if p.fly then
		if World.blocked(p.x, p.y, 20) then return G.toast(sess, "Здесь не приземлиться — найди ровное место", "warn") end
		p.fly = false
		G.toast(sess, "🕊️ " .. m.name .. " мягко " .. Horses.v(m, "приземлилась", "приземлился"))
	else
		if m.energy < 10 then return G.toast(sess, m.name .. " " .. Horses.v(m, "устала", "устал") .. " — сначала отдохните", "warn") end
		if sess.ex or sess.race then return G.toast(sess, "Во время упражнений и скачек летать нельзя") end
		p.fly = true
		p.gait = 2
		G.toast(sess, (m.magic and m.magic.wings) and "🕊️ Взлетаем! Пробел — выше, Ctrl/C — ниже. Небесные острова — высоко над облаками за южным краем земли. V — приземлиться"
			or "☁️ Облачка под копытами подняли вас в небо! Пробел — выше, Ctrl/C — ниже. Небесные острова — за южным краем земли. V — приземлиться")
		G.sfx(sess, "fanfare")
	end
	Riding.applySpeed(sess)
end

--[[ ---------- портал: пещера ↔ небесные острова ---------- ]]
function Riding.updatePortal(sess, dt)
	sess.portalCd = math.max(0, (sess.portalCd or 0) - dt)
	local p = sess.p
	if p.fly or sess.ex or sess.race or sess.portalCd > 0 then return end
	local P1, P2 = World.PORTAL, World.SKY_PORTAL
	local function inP(q)
		local inSky = q == P2
		if inSky ~= (p.y > World.H) then return false end
		return hypot(p.x - q.x, p.y - q.y) < q.r
	end
	local to
	if inP(P1) then to = { x = P2.x, y = P2.y + 130, msg = "🌀 Вжух! Портал перенёс тебя на небесные острова! Обратно — через портал на Облачном острове" }
	elseif inP(P2) then to = { x = P1.x - 150, y = P1.y + 40, msg = "🌀 Портал вернул тебя в пещеру" } end
	if not to then return end
	sess.portalCd = 3
	G.teleport(sess, to.x, to.y)
	if to.y > World.H then G.stat(sess, "skyVisits") end
	G.toast(sess, to.msg, "good")
	G.sfx(sess, "fanfare")
end

-- круглый манеж на острове: каталась кругами — выездка и скорость немного растут
function Riding.updatePen(sess, dt)
	local p, m = sess.p, G.mounted(sess)
	if not m or p.spd < 40 then return end
	local inPen = false
	for _, I in ipairs(World.ISLANDS) do
		if hypot(p.x - I.pen.x, p.y - I.pen.y) < I.pen.r then inPen = true end
	end
	if not inPen then return end
	sess.penT = (sess.penT or 0) + dt
	if sess.penT >= 8 then
		sess.penT = 0
		Horses.addTrain(m, "dressage", 0.6)
		Horses.addTrain(m, p.gait == 2 and "speed" or "stamina", 0.4)
		G.float("🎠 +тренировка", p.x, p.y - 30, "#1b8a3a")
		G.stat(sess, "penTime", 8)
	end
end

-- лодка
function Riding.sail(sess, to)
	if sess.ex or sess.race then return G.toast(sess, "Сначала закончи упражнение или скачки") end
	local p = sess.p
	local piers = { World.PIER }
	for _, I in ipairs(World.ISLANDS) do table.insert(piers, I.pier) end
	local near = Util.some(piers, function(q) return hypot(q.x - p.x, q.y - p.y) < 180 end)
	if not near then return G.toast(sess, "Подойди к причалу") end
	local dest
	if to == "main" then
		dest = { x = World.PIER.x - 90, y = World.PIER.y, name = "большую землю" }
	else
		local I = Util.find(World.ISLANDS, function(q) return q.id == to end)
		if not I then return end
		dest = { x = I.pier.x + 110, y = I.pier.y, name = "остров «" .. I.name .. "»" }
	end
	p.fly = false
	G.R.Open:FireClient(sess.player, "close")
	G.teleport(sess, dest.x, dest.y)
	G.toast(sess, "⛵ Лодка доплыла на " .. dest.name .. "!", "good")
	G.sfx(sess, "fanfare")
end

return Riding
