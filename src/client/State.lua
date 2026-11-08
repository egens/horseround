--[[
	Состояние на клиенте: профиль игрока, строка состояния (HUD), общее состояние мира,
	постройки, скачки. Модули подписываются на изменения.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local State = {
	P = nil,          -- профиль
	hud = nil,        -- строка состояния
	world = { clock = 480, picked = {} },
	builds = {},
	race = nil,
	course = nil,
	actT = 0,         -- когда отправили последнее действие
}
local listeners = {}

function State.on(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end
function State.emit(name, ...)
	for _, fn in ipairs(listeners[name] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then warn("[State] " .. name .. ": " .. tostring(err)) end
	end
end

local Act
function State.act(name, ...)
	State.actT = os.clock()
	Act:FireServer(name, ...)
end
local Query
function State.query(what, arg)
	local ok, res = pcall(function() return Query:InvokeServer(what, arg) end)
	return ok and res or nil
end

function State.byId(id)
	if not State.P then return nil end
	for _, h in ipairs(State.P.horses) do
		if h.id == id then return h end
	end
	return nil
end
function State.mounted()
	return State.hud and State.hud.mounted and State.byId(State.hud.mounted.id) or nil
end

function State.init()
	Act = Net.get("Act")
	Query = Net.get("Query")
	Net.get("Profile").OnClientEvent:Connect(function(P)
		local old = State.P
		-- сохранить кеш фенотипов и время действий
		if old then
			local byId = {}
			for _, h in ipairs(old.horses) do byId[h.id] = h end
			for _, h in ipairs(P.horses) do
				local o = byId[h.id]
				if o and o._ph and o._phKey == math.floor(h.age * 8) then
					h._ph, h._phKey = o._ph, o._phKey
				end
				if h.act then h.act._recv = os.clock() end
			end
		end
		State.P = P
		State.emit("profile", P)
	end)
	Net.get("Hud").OnClientEvent:Connect(function(d)
		State.hud = d
		State.emit("hud", d)
	end)
	Net.get("WorldState").OnClientEvent:Connect(function(ws)
		if ws.picked then
			local set = {}
			for _, id in ipairs(ws.picked) do set[id] = true end
			State.world.picked = set
			State.emit("picked", set)
		end
		if ws.clock then
			local picked = State.world.picked
			State.world = ws
			State.world.picked = picked
			State.emit("world", ws)
		end
	end)
	Net.get("Builds").OnClientEvent:Connect(function(list)
		State.builds = list
		State.emit("builds", list)
	end)
	Net.get("Race").OnClientEvent:Connect(function(r)
		if r == nil then
			State.race = nil
		elseif r.gates then
			State.race = r
		elseif State.race then
			for k, v in pairs(r) do State.race[k] = v end
		end
		State.emit("race", State.race)
	end)
	Net.get("Course").OnClientEvent:Connect(function(c)
		State.course = c
		State.emit("course", c)
	end)
end

return State
