--[[
	Денники и постройки — общие для сервера и клиента.
	Денники: 0–19 — главная конюшня, 20+ — маленькие конюшни игрока, 1000+ — конюшни на островах (по 5).
]]
local World = require(script.Parent.World)
local Items = require(script.Parent.Items)

local Stalls = {}
Stalls.ISLAND_STALL = 1000

function Stalls.dims(btype, rot)
	local d = Items.BUILDS[btype]
	if rot == 1 then return d.h, d.w end
	return d.w, d.h
end
function Stalls.rectOf(b)
	local w, h = Stalls.dims(b.type, b.rot)
	return { x = b.x - w / 2, y = b.y - h / 2, w = w, h = h }
end
-- стены маленькой конюшни: сзади и по бокам, спереди открыто
function Stalls.stableWalls(b)
	local r, t = Stalls.rectOf(b), 10
	return { { x = r.x, y = r.y, w = r.w, h = t }, { x = r.x, y = r.y, w = t, h = r.h }, { x = r.x + r.w - t, y = r.y, w = t, h = r.h } }
end

function Stalls.stables5(P)
	local list = {}
	for _, b in ipairs(P.builds) do
		if b.type == "stable5" then table.insert(list, b) end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end
function Stalls.maxStalls(P) return 20 + #Stalls.stables5(P) * 5 end
function Stalls.totalStalls(P) return Stalls.maxStalls(P) + #World.ISLANDS * 5 end

function Stalls.islandOfStall(i)
	if i >= Stalls.ISLAND_STALL then return World.ISLANDS[math.floor((i - Stalls.ISLAND_STALL) / 5) + 1] end
	return nil
end
function Stalls.label(i)
	local I = Stalls.islandOfStall(i)
	if I then return I.name .. ", денник №" .. ((i - Stalls.ISLAND_STALL) % 5 + 1) end
	return "№" .. (i + 1)
end
function Stalls.extraSpot(P, i)
	local st = Stalls.stables5(P)[math.floor((i - 20) / 5) + 1]
	if not st then return nil end
	local r, k = Stalls.rectOf(st), (i - 20) % 5
	if st.rot == 1 then return { x = r.x + 75, y = r.y + 34 + k * 68, angle = 0 } end
	return { x = r.x + 34 + k * 68, y = r.y + 72, angle = math.pi / 2 }
end
function Stalls.spot(P, i)
	local I = Stalls.islandOfStall(i)
	if I then
		local k = (i - Stalls.ISLAND_STALL) % 5
		return { x = I.stable.x + 34 + k * 68, y = I.stable.y + 72, angle = math.pi / 2 }
	end
	if i < 20 then return World.stallSpot(i) end
	return Stalls.extraSpot(P, i) or World.stallSpot(0)
end
function Stalls.horseIn(P, i)
	for _, h in ipairs(P.horses) do
		if h.stall == i then return h end
	end
	return nil
end
function Stalls.free(P, where)
	local used = {}
	for _, h in ipairs(P.horses) do used[h.stall] = true end
	if where and where ~= "main" then
		local k
		for idx, I in ipairs(World.ISLANDS) do
			if I.id == where then k = idx - 1 end
		end
		if not k then return -1 end
		for i = 0, 4 do
			local s = Stalls.ISLAND_STALL + k * 5 + i
			if not used[s] then return s end
		end
		return -1
	end
	for i = 0, Stalls.maxStalls(P) - 1 do
		if not used[i] then return i end
	end
	return -1
end
function Stalls.groups(P)
	local main = {}
	for i = 0, Stalls.maxStalls(P) - 1 do table.insert(main, i) end
	local out = { { title = "Ферма", list = main } }
	for k, I in ipairs(World.ISLANDS) do
		local l = {}
		for j = 0, 4 do table.insert(l, Stalls.ISLAND_STALL + (k - 1) * 5 + j) end
		table.insert(out, { title = "🏝️ " .. I.name, list = l })
	end
	return out
end
-- остров, у конюшни или пастбища которого стоит игрок
function Stalls.islandStableHere(x, y)
	for _, I in ipairs(World.ISLANDS) do
		if World.inRect(x, y, I.stable, 70) or World.inRect(x, y, I.pasture, 60) then return I end
	end
	return nil
end
function Stalls.paddockFor(h)
	local I = Stalls.islandOfStall(h.stall)
	return I and I.pasture or World.PADDOCK
end
function Stalls.nearSmallStable(P, x, y)
	for _, b in ipairs(Stalls.stables5(P)) do
		if World.inRect(x, y, Stalls.rectOf(b), 60) then return true end
	end
	return false
end
function Stalls.atFarm(P, x, y)
	return World.inRect(x, y, World.STABLE, 40) or World.inRect(x, y, World.PADDOCK, 50) or Stalls.nearSmallStable(P, x, y) or Stalls.islandStableHere(x, y) ~= nil
end

-- место выставленной на рынке лошади игрока
function Stalls.marketSpot(P, h)
	local i = 0
	for _, x in ipairs(P.horses) do
		if x.state == "market" then
			if x == h or x.id == h.id then break end
			i += 1
		end
	end
	return { x = World.MARKET.x + 480 + i * 62, y = World.MARKET.y + 255, angle = math.pi / 2 }
end
function Stalls.stockSpot(i)
	return { x = World.MARKET.x + 70 + (i - 1) * 82, y = World.MARKET.y + 250, angle = math.pi / 2 }
end

return Stalls
