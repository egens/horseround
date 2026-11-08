--[[
	Сохранения игроков в DataStore (аналог localStorage в JS-версии).
	Профиль P — то, что в JS называлось S: деньги, рюкзак, амуниция, лошади, задания, постройки…
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Horses = require(Shared.Horses)
local Util = require(Shared.Util)
local World = require(Shared.World)

-- цены построек и семян из старых сохранений: стройку и огород убрали, их стоимость возвращаем монетами
local OLD_BUILD_PRICE = {
	bed = 20, fence = 8, lamp = 35, flowerbed = 15, bench = 25, trough = 35, haystack = 20, tree = 30,
	bunnyhouse = 60, well = 80, windmill = 250, stable5 = 400,
}
local OLD_SEED_PRICE = { seed_carrot = 4, seed_oats = 5, seed_hay = 3, seed_pumpkin = 10, seed_sunflower = 7 }

local Profiles = {}
local STORE_NAME = "HorseFarm_v1"
local store = nil
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then store = res else warn("[Profiles] DataStore недоступен: " .. tostring(res)) end
end

function Profiles.new()
	local inv = {}
	for k in pairs(Items.ITEMS) do inv[k] = 0 end
	inv.hay, inv.carrot, inv.apple = 6, 3, 2
	return {
		money = 300,
		inv = inv,
		tack = {
			saddle = false, bridle = false, brush = false, goodLasso = false, detector = false, pad = false, helmet = false, boots = false,
			saddleStyles = { classic = true }, saddleStyle = "classic", saddleColor = "#5b3a1e",
			bridleStyles = { classic = true }, bridleStyle = "classic", bridleColor = "#2b1a10",
		},
		horses = {},
		shirt = "#e05a8a",
		pos = false,
		stats = { caught = 0, foals = 0, sold = 0, gold = 0, silver = 0, bronze = 0, bunnies = 0, races = 0, wins = 0 },
		nextId = 1,
		seenHelp = false,
		flags = {}, quests = {}, board = false, bigTreasure = false,
		market = false, version = 1,
	}
end

-- подставить недостающие поля (старые сохранения)
local function normalize(data)
	local fresh = Profiles.new()
	if type(data) ~= "table" or type(data.horses) ~= "table" then return fresh end
	local s = Util.assign(fresh, data)
	s.inv = Util.assign(Profiles.new().inv, data.inv)
	s.tack = Util.assign(Profiles.new().tack, data.tack)
	s.tack.saddleStyles = Util.assign({ classic = true }, s.tack.saddleStyles)
	s.tack.bridleStyles = Util.assign({ classic = true }, s.tack.bridleStyles)
	s.stats = Util.assign(Profiles.new().stats, data.stats)
	s.flags = data.flags or {}
	s.quests = data.quests or {}
	local maxId = s.nextId or 1
	for _, h in ipairs(s.horses) do
		if h.state == "ridden" or h.state == "led" or h.state == "walk" then h.state = "stall" end
		h.wet = h.wet or 0
		h.mud = h.mud or 0
		maxId = math.max(maxId, (h.id or 0) + 1)
	end
	if type(s.market) == "table" and type(s.market.stock) == "table" then
		for _, h in ipairs(s.market.stock) do maxId = math.max(maxId, (h.id or 0) + 1) end
	end
	s.nextId = maxId
	Profiles.migrateBuilds(s, data)
	return s
end

-- старое сохранение со стройкой и огородом: вернуть монеты, переселить лошадей из маленьких конюшен
function Profiles.migrateBuilds(s, data)
	local refund = 0
	if type(data.builds) == "table" then
		for _, b in ipairs(data.builds) do refund += OLD_BUILD_PRICE[b.type] or 0 end
	end
	for k, price in pairs(OLD_SEED_PRICE) do
		refund += (tonumber(data.inv and data.inv[k]) or 0) * price
	end
	-- волшебные семечки — в волшебную пыльцу (её раньше давал волшебный цветок)
	local magic = tonumber(data.inv and data.inv.seed_magic) or 0
	if magic > 0 then s.inv.pollen = (s.inv.pollen or 0) + magic end
	-- семян больше нет
	for k in pairs(s.inv) do
		if string.sub(k, 1, 5) == "seed_" then s.inv[k] = nil end
	end
	s.builds, s.buildId = nil, nil
	-- лошади из маленьких конюшен (денники 20–999) — в свободные денники главной конюшни или на острова
	local used = {}
	for _, h in ipairs(s.horses) do used[h.stall] = true end
	local free = {}
	for i = 0, 19 do
		if not used[i] then table.insert(free, i) end
	end
	for k = 0, #World.ISLANDS - 1 do
		for i = 0, 4 do
			local st = 1000 + k * 5 + i
			if not used[st] then table.insert(free, st) end
		end
	end
	local moved = 0
	for _, h in ipairs(s.horses) do
		if type(h.stall) == "number" and h.stall >= 20 and h.stall < 1000 and #free > 0 then
			h.stall = table.remove(free, 1)
			moved += 1
		end
	end
	if refund > 0 or moved > 0 or magic > 0 then
		s.money += refund
		s._migrated = { refund = refund, moved = moved }
	end
end

function Profiles.load(player)
	if not store then return Profiles.new(), true end
	local key = "u" .. player.UserId
	local data
	for attempt = 1, 3 do
		local ok, res = pcall(function() return store:GetAsync(key) end)
		if ok then
			data = res
			break
		end
		warn("[Profiles] не получилось загрузить " .. key .. ": " .. tostring(res))
		if attempt == 3 then return Profiles.new(), false end
		task.wait(1.5 * attempt)
	end
	if type(data) == "string" then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end)
		data = ok and decoded or nil
	end
	return normalize(data), true
end

-- копия без служебных полей (начинаются с «_») — годится и для сохранения, и для отправки клиенту
local function strip(v)
	if type(v) ~= "table" then return v end
	local r = {}
	for k, x in pairs(v) do
		if not (type(k) == "string" and string.sub(k, 1, 1) == "_") and type(x) ~= "function" then
			r[k] = strip(x)
		end
	end
	return r
end
Profiles.strip = strip

function Profiles.save(player, P)
	if not store or not P then return false end
	local key = "u" .. player.UserId
	local json = HttpService:JSONEncode(strip(P))
	local ok, err = pcall(function() store:SetAsync(key, json, { player.UserId }) end)
	if not ok then warn("[Profiles] не сохранилось " .. key .. ": " .. tostring(err)) end
	return ok
end

-- id для новой лошади игрока
function Profiles.nextHorseId(P)
	local id = P.nextId or 1
	P.nextId = id + 1
	return id
end

-- лошадь, которую игрок получил (поймал, купил, обменял): новый id в его профиле
function Profiles.adopt(P, h)
	h.id = Profiles.nextHorseId(P)
	h._ph = nil
	return h
end

Profiles.Horses = Horses
return Profiles
