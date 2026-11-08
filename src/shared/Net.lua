--[[
	Сетевые события между сервером и клиентами.
	Сервер создаёт их в ReplicatedStorage.Remotes, клиент ждёт и получает.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- сервер → клиент
Net.TO_CLIENT = {
	"Profile",       -- полный профиль игрока (деньги, лошади, рюкзак…)
	"Hud",           -- строка состояния: подсказка, кнопка «E», упражнение…
	"Toast",         -- всплывающее сообщение
	"Float",         -- летящая надпись над точкой мира
	"Sfx",           -- звук
	"Open",          -- открыть окно (имя, данные)
	"Lasso",         -- мини-игра с лассо
	"Care",          -- мини-игра ухода
	"Birth",         -- заставка рождения жеребёнка
	"EntitySpawn",   -- появились сущности (лошади, зайчики, олени…)
	"EntityDespawn", -- исчезли
	"EntityState",   -- координаты (пачкой)
	"EntityLook",    -- поменялась внешность
	"WorldState",    -- погода, время суток, поезд, праздник, грибы…
	"Race",          -- скачки: ворота, следующая цель
	"Course",        -- упражнение: куда ехать (буква, препятствие)
}
-- клиент → сервер
Net.TO_SERVER = {
	"Act",           -- действие (имя, аргументы)
}
-- клиент спрашивает — сервер отвечает
Net.FUNCTIONS = {
	"Query",
}

local folder
function Net.init()
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		for _, n in ipairs(Net.TO_CLIENT) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		for _, n in ipairs(Net.TO_SERVER) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		for _, n in ipairs(Net.FUNCTIONS) do
			local r = Instance.new("RemoteFunction")
			r.Name = n
			r.Parent = folder
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
end

function Net.get(name)
	if not folder then Net.init() end
	return folder:WaitForChild(name)
end

return Net
