--[[
	Репликация «сущностей»: дикие и свои лошади на поводу/в леваде, зайчики, олени, привидения,
	соперники на скачках. Сервер считает их движение (как в JS), а клиенты рисуют
	модели и плавно двигают их. Каждому игроку отправляются только те, что рядом.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Util = require(Shared.Util)

local Entities = {}
local G
local list = {}          -- [id] = e
local nextId = 0
local RADIUS = 5200      -- пикселей карты (≈ 520 стадов)
local ACT_CODE = {}
for i, k in ipairs(Items.ACT_CODES) do ACT_CODE[k] = i end

function Entities.init(g) G = g end

-- kind: 'horse' | 'rider' | 'bunny' | 'deer' | 'ghost'
-- src — таблица с x, y, angle, spd, act, fly, z; lookFn() — внешность, keyFn() — ключ внешности
function Entities.add(kind, src, lookFn, keyFn, label)
	nextId += 1
	local e = { id = nextId, kind = kind, src = src, lookFn = lookFn, keyFn = keyFn, label = label, key = keyFn and keyFn() or "" }
	list[e.id] = e
	src._ent = e
	return e
end
function Entities.remove(e)
	if not e then return end
	list[e.id] = nil
	if e.src and e.src._ent == e then e.src._ent = nil end
	e.dead = true
	for _, s in ipairs(G.each()) do
		if s.known[e.id] then
			s.known[e.id] = nil
			s.despawn = s.despawn or {}
			table.insert(s.despawn, e.id)
		end
	end
end
function Entities.removeSrc(src)
	if src and src._ent then Entities.remove(src._ent) end
end
function Entities.setLabel(e, label)
	if e and e.label ~= label then
		e.label = label
		e.key = "" -- переслать внешность
	end
end
function Entities.forget(sess)
	sess.known = {}
end

local function spawnData(e)
	return { id = e.id, kind = e.kind, look = e.lookFn and e.lookFn() or {}, label = e.label, leadBy = e.leadBy }
end

local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function stateOf(e, now)
	local s = e.src
	local act = s.act
	local code, start, d, leg = 0, 0, 0, 0
	if act and act.k then
		code = ACT_CODE[act.k] or 0
		start = now - (act.t or 0)
		d = act.d or 1
		leg = act.leg or 0
	end
	return { e.id, r1(s.x), r1(s.y), r1(s.angle or 0), r1(s.spd or 0), r1(s.fly or 0), code, start, d, leg, r1(s.z or 0) }
end

local acc, lookAcc = 0, 0
function Entities.tick(dt)
	acc += dt
	lookAcc += dt
	if acc < 0.1 then return end
	acc = 0
	local checkLooks = lookAcc >= 1
	if checkLooks then lookAcc = 0 end
	-- внешность поменялась?
	local changedLooks = {}
	if checkLooks then
		for _, e in pairs(list) do
			if e.keyFn then
				local k = e.keyFn()
				if k ~= e.key then
					e.key = k
					changedLooks[e.id] = true
				end
			elseif e.key == "" then
				e.key = "-"
				changedLooks[e.id] = true
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	for _, sess in ipairs(G.each()) do
		local px, py = sess.p.x, sess.p.y
		local spawn, states, looks = {}, {}, {}
		local seen = {}
		for id, e in pairs(list) do
			local s = e.src
			if not e.hideFor or not e.hideFor[sess] then
				if math.abs(s.x - px) < RADIUS and math.abs(s.y - py) < RADIUS then
					seen[id] = true
					if not sess.known[id] then
						sess.known[id] = true
						table.insert(spawn, spawnData(e))
					elseif changedLooks[id] then
						table.insert(looks, spawnData(e))
					end
					table.insert(states, stateOf(e, now))
				end
			end
		end
		local gone = sess.despawn or {}
		sess.despawn = nil
		for id in pairs(sess.known) do
			if not seen[id] then
				sess.known[id] = nil
				table.insert(gone, id)
			end
		end
		local pl = sess.player
		if pl.Parent then
			if #gone > 0 then G.R.EntityDespawn:FireClient(pl, gone) end
			if #spawn > 0 then G.R.EntitySpawn:FireClient(pl, spawn) end
			if #looks > 0 then G.R.EntityLook:FireClient(pl, looks) end
			if #states > 0 then G.R.EntityState:FireClient(pl, states) end
		end
	end
end

-- стандартная лошадь как сущность
-- leadBy — UserId игрока, который ведёт лошадь на верёвке (клиент рисует верёвку от руки к шее)
function Entities.addHorse(h, label, leadBy)
	local Horses = G.Horses
	local e = Entities.add("horse", h, function() return Horses.look(h) end, function() return Horses.lookKey(h) end, label)
	e.leadBy = leadBy
	return e
end

Entities.list = list
Entities.Util = Util
return Entities
