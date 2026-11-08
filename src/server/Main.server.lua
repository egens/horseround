--[[
	Лошадиная ферма — сервер (Roblox, мультиплеер).
	Запускает мир, принимает игроков, крутит игровой цикл (аналог frame() в js/game.js)
	и рассылает клиентам профиль, строку состояния и общее состояние мира.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local World = require(Shared.World)
local Util = require(Shared.Util)

local Server = script.Parent
local G = require(Server.Core)
local Profiles = require(Server.Profiles)
local Entities = require(Server.Entities)
local Herds = require(Server.Herds)
local Owned = require(Server.Owned)
local Riding = require(Server.Riding)
local Exercises = require(Server.Exercises)
local Events = require(Server.Events)
local Farm = require(Server.Farm)
local Market = require(Server.Market)
local Quests = require(Server.Quests)
local Specials = require(Server.Specials)
local Actions = require(Server.Actions)
local Hud = require(Server.Hud)
local WorldBuild = require(Server.WorldBuild)
local People = require(Server.People)

Players.CharacterAutoLoads = false
G.initRemotes()
G.modules = {
	Entities = Entities, Herds = Herds, Owned = Owned, Riding = Riding, Exercises = Exercises, Events = Events,
	Farm = Farm, Market = Market, Quests = Quests, Specials = Specials, Actions = Actions, Hud = Hud, Profiles = Profiles,
}
Entities.init(G)
Herds.init(G, Entities)
Owned.init(G, Entities, Herds, Profiles)
Riding.init(G, Herds)
Exercises.init(G)
Events.init(G, Entities, Herds)
Farm.init(G)
Market.init(G, Profiles)
Quests.init(G)
Specials.init(G, Entities, Herds)
Actions.init(G, Herds, Riding, Profiles)
Hud.init(G)

-- мир строится до появления персонажей
local worldReady = false
task.spawn(function()
	local t0 = os.clock()
	WorldBuild.build()
	People.build(WorldBuild.root)
	Herds.spawnAll()
	Specials.AI.init()
	Specials.Creatures.init()
	worldReady = true
	print(string.format("[HorseFarm] мир построен за %.1f с", os.clock() - t0))
	for _, s in pairs(G.sessions) do
		if s.player.Parent and not s.player.Character then s.player:LoadCharacter() end
	end
end)

--[[ ---------- игроки ---------- ]]
local function onCharacter(sess, char)
	Riding.setupCharacter(sess, char)
	sess.p.mountId = nil
	sess.p.fly = false
	for _, h in ipairs(sess.P.horses) do
		if h.state == "ridden" then h.state = "stall" end
	end
	Riding.publishMount(sess)
	-- вернуться туда, где игрок был
	task.defer(function()
		local pos = sess.P.pos
		if pos and type(pos.x) == "number" then
			local x, y = pos.x, pos.y
			if World.blocked(x, y, 16) or y > World.H then
				x, y = World.OX + 960, World.OY + 470
			end
			G.teleport(sess, x, y)
		end
	end)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			task.wait(3)
			if sess.player.Parent then sess.player:LoadCharacter() end
		end)
	end
end

local function onPlayerAdded(player)
	local P, ok = Profiles.load(player)
	local sess = {
		player = player, P = P, loadedOk = ok, ready = false,
		p = { x = World.OX + 960, y = World.OY + 470, angle = 0, gait = 0, spd = 0, mountId = nil, fly = false, detector = false },
		known = {}, dirty = true, hudCache = "", led = nil, ex = nil, lasso = nil, race = nil,
		lassoCd = 0, visitT = 0, saveT = 0,
	}
	G.sessions[player] = sess
	Market.setup(sess)
	sess.ready = true
	Farm.syncSolids()
	player.CharacterAdded:Connect(function(char) onCharacter(sess, char) end)
	if worldReady then player:LoadCharacter() end
	if not ok then
		G.toast(sess, "⚠️ Не получилось загрузить сохранение — играем без него. Прогресс сейчас не сохранится.", "warn")
	end
	G.toastAll("👋 " .. G.playerName(sess) .. " приехала на ферму!", "good", function(s) return s ~= sess end)
end

local function saveSession(sess)
	if not sess.loadedOk then return end
	sess.P.pos = { x = math.floor(sess.p.x), y = math.floor(sess.p.y) }
	Profiles.save(sess.player, sess.P)
end

local function onPlayerRemoving(player)
	local sess = G.sessions[player]
	if not sess then return end
	Herds.cancelLasso(sess)
	Events.leaveRace(sess)
	-- лошадь под седлом возвращается в денник, пойманная — убегает
	local m = G.mounted(sess)
	if m then m.state = "stall" end
	for _, h in ipairs(sess.P.horses) do
		if h.state == "walk" then h.state = "stall" end
	end
	if sess.led then
		Entities.removeSrc(sess.led)
		local h = sess.led
		sess.led = nil
		h.state = "wild"
		h.home = Herds.HERDS[h.home or "field"] and h.home or "field"
		h.slot = { x = 0, y = 0 }
		h.flee = 0
		Herds.add(h)
	end
	Owned.removeAll(sess)
	sess.ready = false
	G.sessions[player] = nil
	saveSession(sess)
	Farm.syncSolids()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, pl in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, pl) end

game:BindToClose(function()
	for _, sess in pairs(G.sessions) do saveSession(sess) end
	if RunService:IsStudio() then task.wait(1) end
end)

--[[ ---------- команды от клиента ---------- ]]
G.R.Act.OnServerEvent:Connect(function(player, name, a, b, c)
	local sess = G.sessions[player]
	if not sess or not worldReady then return end
	local ok, err = pcall(Actions.handle, sess, name, a, b, c)
	if not ok then warn("[Act] " .. tostring(name) .. ": " .. tostring(err)) end
end)

G.R.Query.OnServerInvoke = function(player, what, arg)
	local sess = G.sessions[player]
	if not sess then return nil end
	if what == "players" then
		local rows = {}
		for _, s in ipairs(G.each()) do
			table.insert(rows, { name = G.playerName(s), caught = s.P.stats.caught or 0, money = s.P.money, where = World.REGION_NAMES[World.regionAt(s.p.x, s.p.y)] or "", me = s == sess, human = true })
		end
		for _, b in ipairs(Specials.AI.hud()) do
			table.insert(rows, { name = b.name, caught = b.caught, money = b.money, where = b.where, me = false, human = false })
		end
		table.sort(rows, function(x, y) return x.caught > y.caught end)
		return { rows = rows, train = Specials.Train.hud(), holiday = Specials.Holidays.hud() }
	elseif what == "market" then
		return {
			others = Market.othersListings(sess),
			listings = Market.listings(sess),
			swapValues = (function()
				local t = {}
				for _, h in ipairs(sess.P.horses) do t[tostring(h.id)] = Market.swapValue(h) end
				return t
			end)(),
			horseValues = (function()
				local t = {}
				for _, h in ipairs(sess.P.horses) do t[tostring(h.id)] = Market.horseValue(h) end
				return t
			end)(),
			fair = Events.fair(),
		}
	elseif what == "prices" then
		local t = {}
		for _, h in ipairs(sess.P.horses) do t[tostring(h.id)] = Actions.sellPrice(h, false) end
		if sess.led then t.led = Actions.sellPrice(sess.led, true) end
		return { prices = t, fair = Events.fair(), nearSell = Actions.nearSell(sess), led = sess.led and Profiles.strip(sess.led) or nil }
	elseif what == "islandT" then
		return Herds.islandTimeLeft()
	end
	return nil
end

--[[ ---------- рассылка состояния ---------- ]]
local function sendProfile(sess)
	if not sess.player.Parent then return end
	sess.dirty = false
	G.R.Profile:FireClient(sess.player, Profiles.strip(sess.P))
end

local function sendHud(sess)
	local d = Hud.build(sess)
	local key = game:GetService("HttpService"):JSONEncode(d)
	if key ~= sess.hudCache then
		sess.hudCache = key
		G.R.Hud:FireClient(sess.player, d)
	end
end

local lastWorldKey = ""
local function worldState()
	local tr = Specials.Train.state()
	local ev = Events.state()
	return {
		clock = G.clock, raining = ev.raining, wet = ev.wet, puddle = ev.puddle, rainbow = ev.rainbow, fair = ev.fair,
		shoe = ev.shoe, bunnies = ev.bunnies, race = ev.race,
		train = tr and { x = tr.x, state = tr.state } or nil,
		holiday = Specials.Holidays.current(),
		herds = (function()
			local t = {}
			for k, H in pairs(Herds.HERDS) do t[k] = { math.floor(H.x), math.floor(H.y) } end
			return t
		end)(),
		players = (function()
			local t = {}
			for _, s in ipairs(G.each()) do table.insert(t, { id = s.player.UserId, x = math.floor(s.p.x), y = math.floor(s.p.y), name = G.playerName(s) }) end
			return t
		end)(),
	}
end

--[[ ---------- игровой цикл ---------- ]]
local acc = { hud = 0, profile = 0, world = 0, save = 0, slow = 0, picked = 0 }
RunService.Heartbeat:Connect(function(dt)
	if not worldReady then return end
	dt = math.min(dt, 0.1)
	G.time += dt
	G.updateClock(dt)
	local sessions = G.each()
	for _, sess in ipairs(sessions) do
		sess.lassoCd = math.max(0, (sess.lassoCd or 0) - dt)
		Riding.syncPosition(sess, dt)
		Riding.update(sess, dt)
	end
	Herds.update(dt)
	for _, sess in ipairs(sessions) do
		Owned.update(sess, dt)
		Market.update(sess, dt)
		Riding.updatePen(sess, dt)
		Riding.updatePortal(sess, dt)
		Exercises.update(sess, dt)
		sess.visitT -= dt
		if sess.visitT <= 0 then
			sess.visitT = 0.5
			Quests.updateVisits(sess)
		end
	end
	Events.update(dt)
	Farm.update(dt)
	Owned.updateMud(dt, Events.raining())
	Specials.Creatures.update(dt)
	Specials.Train.update(dt)
	Specials.Holidays.update(dt)
	Specials.AI.update(dt)
	-- розовый дракон в радужный дождь
	local raining = Events.raining()
	if raining and not G.wasRaining and math.random() < 0.35 then Herds.pinkDragonRain() end
	G.wasRaining = raining
	Entities.tick(dt)

	acc.hud += dt
	acc.profile += dt
	acc.world += dt
	acc.save += dt
	acc.slow += dt
	if acc.hud >= 0.2 then
		acc.hud = 0
		for _, sess in ipairs(sessions) do sendHud(sess) end
	end
	-- профиль: сразу после действий и раз в секунду (сытость, энергия…)
	local periodic = acc.profile >= 1
	if periodic then acc.profile = 0 end
	for _, sess in ipairs(sessions) do
		if sess.dirty or periodic then sendProfile(sess) end
	end
	if acc.world >= 0.5 then
		acc.world = 0
		local ws = worldState()
		G.R.WorldState:FireAllClients(ws)
		if Farm.takePickedDirty() then G.R.WorldState:FireAllClients({ picked = Farm.pickedList() }) end
		if Farm.takeBuildsDirty() then G.R.Builds:FireAllClients(Farm.buildsSnapshot()) end
	end
	if acc.slow >= 2 then
		acc.slow = 0
		WorldBuild.updateLamps(G.isNight())
	end
	if acc.save >= 60 then
		acc.save = 0
		for _, sess in ipairs(sessions) do task.spawn(saveSession, sess) end
	end
end)

-- новый клиент: прислать постройки и грибы
G.R.Act.OnServerEvent:Connect(function(player, name)
	if name == "hello" then
		local sess = G.sessions[player]
		if not sess then return end
		G.R.Builds:FireClient(player, Farm.buildsSnapshot())
		G.R.WorldState:FireClient(player, { picked = Farm.pickedList() })
		sendProfile(sess)
		sess.hudCache = ""
		if not sess.P.seenHelp then G.open(sess, "help", {}) end
	end
end)

print("[HorseFarm] сервер запущен")
