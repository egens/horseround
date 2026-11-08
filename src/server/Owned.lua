--[[
	Свои лошади игрока (перенос updateOwned/updateMud из js/game.js):
	возраст, сытость, настроение; левада, прогулка с жеребёнком, лошадь на верёвке,
	грязь на ногах и мокрая шерсть в дождь.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Stalls = require(Shared.Stalls)

local Owned = {}
local G, Entities, Herds, Profiles
local clamp, rand, hypot = Util.clamp, Util.rand, Util.hypot

function Owned.init(g, ents, herds, profiles)
	G, Entities, Herds, Profiles = g, ents, herds, profiles
end

local function label(sess, h, prefix)
	return (prefix or "") .. h.name .. " · " .. G.playerName(sess)
end

-- лошадь на верёвке после лассо
function Owned.attachLed(sess, h)
	h.vx, h.vy = 0, 0
	Entities.addHorse(h, label(sess, h, "➰ "))
end
function Owned.releaseLed(sess)
	local h = sess.led
	if not h then return end
	Entities.removeSrc(h)
	sess.led = nil
	h.state = "wild"
	h.flee = 2
	h.slot = { x = rand(-150, 150), y = rand(-110, 110) }
	if not Herds.HERDS[h.home or "field"] then h.home = "field" end
	Herds.add(h)
	G.toast(sess, h.name .. " " .. Horses.v(h, "убежала", "убежал") .. " обратно в поле")
	G.dirty(sess)
end

-- сущности для лошадей, которых видно всем: в леваде и на прогулке
function Owned.syncEntities(sess)
	for _, h in ipairs(sess.P.horses) do
		local want = h.state == "paddock" or h.state == "walk"
		if want and not h._ent then
			Entities.addHorse(h, label(sess, h, h.state == "walk" and "🐾 " or ""))
		elseif not want and h._ent then
			Entities.removeSrc(h)
		elseif want and h._ent then
			Entities.setLabel(h._ent, label(sess, h, h.state == "walk" and "🐾 " or ""))
		end
	end
end
function Owned.removeAll(sess)
	for _, h in ipairs(sess.P.horses) do Entities.removeSrc(h) end
	if sess.led then Entities.removeSrc(sess.led) end
end

local STALL_IDLE = { { "graze", 3 }, { "lookUp", 1 }, { "ears", 1 }, { "liftLeg", 1 }, { "neigh", 0.3 }, { "scratch", 0.6 }, { "lookDown", 1 } }
Owned.STALL_IDLE = STALL_IDLE

function Owned.update(sess, dt)
	local P, p = sess.P, sess.p
	local t = G.time
	for _, h in ipairs(P.horses) do
		local Pd = Stalls.paddockFor(h)
		h.age += dt / 120 -- 2 минуты = 1 год
		local inPaddock = h.state == "paddock"
		h.hunger = clamp(h.hunger - dt * (inPaddock and 0.03 or 0.07), 0, 100)
		h.clean = clamp(h.clean - dt * (inPaddock and 0.06 or 0.015), 0, 100)
		if h.state ~= "ridden" then h.energy = clamp(h.energy + dt * (inPaddock and 1.2 or 0.8), 0, 100) end
		local moodD = inPaddock and 0.4 or -0.03
		if h.hunger < 25 then moodD -= 0.15 end
		if h.clean < 25 then moodD -= 0.05 end
		h.mood = clamp(h.mood + dt * moodD, 0, 100)

		if h.state == "market" then
			local sp = Stalls.marketSpot(P, h)
			h.x, h.y, h.angle, h.spd = sp.x, sp.y, sp.angle, 0
		elseif h.state == "stall" then
			local sp = Stalls.spot(P, h.stall)
			h.x, h.y, h.angle, h.spd = sp.x, sp.y, sp.angle, 0
			Herds.idleAct(h, dt, 0.04, STALL_IDLE)
		elseif h.state == "walk" then
			-- жеребёнок гуляет с тобой — идёт следом
			local back = { x = p.x - math.cos(p.angle) * 60, y = p.y - math.sin(p.angle) * 60 }
			local d = hypot(h.x - back.x, h.y - back.y)
			if not h.act or h.act.k == "back" then
				Herds.moveToward(h, back.x, back.y, d > 20 and math.min(d * 3, 260) or 0, dt, 5)
			end
			World.collide(h, 14)
			if d > 900 then h.x, h.y = back.x, back.y end
			h.headTurn = h.spd < 5 and math.sin(t * 0.9 + h.seed) * 0.5 or 0
			h.mood = clamp(h.mood + dt * 0.5, 0, 100)
			if h.spd < 5 then Herds.idleAct(h, dt, 0.08) end
			G.stat(sess, "foalWalk", dt)
		elseif inPaddock then
			if not h.wander or hypot(h.x - h.wander.x, h.y - h.wander.y) < 10 or math.random() < dt * 0.05 then
				h.wander = math.random() < 0.5 and { x = h.x, y = h.y } or { x = rand(Pd.x + 50, Pd.x + Pd.w - 50), y = rand(Pd.y + 50, Pd.y + Pd.h - 50) }
			end
			if h.act then h.wander = { x = h.x, y = h.y } end
			Herds.moveToward(h, h.wander.x, h.wander.y, hypot(h.x - h.wander.x, h.y - h.wander.y) > 10 and 40 or 0, dt)
			if h.spd < 5 then Herds.idleAct(h, dt, 0.1) end
			h.x = clamp(h.x, Pd.x + 30, Pd.x + Pd.w - 30)
			h.y = clamp(h.y, Pd.y + 30, Pd.y + Pd.h - 30)
			h.headTurn = h.spd < 5 and math.sin(t * 0.7 + h.seed) * 0.4 or 0
		end
		if h.state ~= "ridden" then Herds.tickAct(h, dt, h.state ~= "stall") end
		-- жеребёнок готов родиться — ждём кнопку «Родить»
		if h.preg and not h.preg.ready then
			h.preg.t -= dt
			if h.preg.t <= 0 then
				h.preg.t = 0
				h.preg.ready = true
				G.toast(sess, "🍼 Жеребёнок у кобылы " .. h.name .. " готов родиться! Нажми кнопку «Родить жеребёнка»", "good")
				G.sfx(sess, "fanfare")
				G.dirty(sess)
			end
		end
	end

	-- пойманная лошадь идёт следом
	local led = sess.led
	if led then
		local back = { x = p.x - math.cos(p.angle) * 70, y = p.y - math.sin(p.angle) * 70 }
		local d = hypot(led.x - back.x, led.y - back.y)
		Herds.moveToward(led, back.x, back.y, d > 25 and math.min(d * 3, 300) or 0, dt, 5)
		led.headTurn = 0
		World.collide(led, 16)
		if d > 1200 then led.x, led.y = back.x, back.y end
		local isl = Stalls.islandStableHere(p.x, p.y)
		if not p.fly and (World.inRect(p.x, p.y, World.STABLE, 10) or Stalls.nearSmallStable(P, p.x, p.y) or (isl and World.inRect(p.x, p.y, isl.stable, 20))) then
			local st = Stalls.free(P, isl and isl.id or "main")
			if st >= 0 then
				Entities.removeSrc(led)
				Profiles.adopt(P, led)
				led.state, led.stall, led.flee, led.home = "stall", st, 0, nil
				led.slot, led.lassoBy = nil, nil
				table.insert(P.horses, led)
				G.toast(sess, "🏠 " .. led.name .. " теперь живёт: " .. Stalls.label(st) .. "!", "good")
				G.sfx(sess, "coin")
				sess.led = nil
				G.dirty(sess)
			elseif t > (sess.fullWarnT or 0) then
				sess.fullWarnT = t + 6
				G.toast(sess, "Конюшня полна! Продай лошадь у повозки или отпусти эту.", "warn")
			end
		end
	end
	Owned.syncEntities(sess)
end

--[[ ---------- грязь на ногах и мокрая шерсть ---------- ]]
local DRY = { cave = true, desert = true, tundra = true, sky = true }
local function dryRegion(x, y)
	return y > World.H or DRY[World.regionAt(x, y)] or false
end
local mudAcc = 0
function Owned.updateMud(dt, raining)
	mudAcc += dt
	if mudAcc < 0.5 then return end
	dt = mudAcc
	mudAcc = 0
	local function soil(h, k)
		if raining and not dryRegion(h.x, h.y) and not World.inRect(h.x, h.y, World.STABLE) then
			h.mud = math.min(100, (h.mud or 0) + dt * 2.2 * (k or 1))
		end
	end
	local function wetten(h)
		local under = raining and h.state ~= "stall" and not dryRegion(h.x, h.y) and not World.inRect(h.x, h.y, World.STABLE)
		if under then h.wet = math.min(100, (h.wet or 0) + dt * 5)
		else h.wet = math.max(0, (h.wet or 0) - dt * (h.state == "stall" and 2.2 or 1.1)) end
	end
	for _, sess in ipairs(G.each()) do
		local p = sess.p
		for _, h in ipairs(sess.P.horses) do
			if h.state == "ridden" then h.x, h.y = p.x, p.y end
			wetten(h)
			if h.state == "stall" then
				h.mud = math.max(0, (h.mud or 0) - dt * 0.05)
			else
				soil(h, h.state == "ridden" and 1 + p.gait * 0.5 or 1)
				if (h.mud or 0) > 30 then h.clean = math.max(0, h.clean - dt * 0.05) end
			end
		end
		if sess.led then wetten(sess.led); soil(sess.led) end
		local m = G.mounted(sess)
		if m and p.fly then m.mud = math.max(0, (m.mud or 0) - dt * 0.5) end
	end
	for _, w in ipairs(Herds.wild) do
		wetten(w)
		if raining then soil(w) else w.mud = math.max(0, (w.mud or 0) - dt * 0.4) end
	end
end

return Owned
