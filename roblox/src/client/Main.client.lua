--[[
	Лошадиная ферма — клиент (Roblox).
	Связывает всё: состояние от сервера, отрисовку существ и декораций, эффекты,
	интерфейс, мини-игры, управление и звуки.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Client = script.Parent
local State = require(Client.State)
local Render = require(Client.Render)
local Decor = require(Client.Decor)
local Effects = require(Client.Effects)
local Controls = require(Client.Controls)
local Sound = require(Client.Sound)
local Hud = require(Client.UI.Hud)
local Windows = require(Client.UI.Windows)
local Minigames = require(Client.UI.Minigames)

Net.init()
State.init()

Hud.init()
Hud.windows = Windows
Windows.build(Hud.gui)
Windows.controls = Controls
Minigames.init(Hud.gui)
Render.init()
Decor.init()
Effects.init()
Controls.init(Windows, Minigames)

Net.get("Toast").OnClientEvent:Connect(Hud.toast)
State.on("toast", Hud.toast)
Net.get("Sfx").OnClientEvent:Connect(function(name, a, b)
	if name == "neigh" and a and b then
		-- ржание слышно только рядом
		local ch = game:GetService("Players").LocalPlayer.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local World = require(Shared.World)
		if r then
			local x, y = World.fromStuds(r.Position)
			if math.sqrt((x - a) ^ 2 + (y - b) ^ 2) > 600 then return end
		end
	end
	if name == "boo" then
		-- привидение пролетело сквозь тебя — лёгкий толчок
		local ch = game:GetService("Players").LocalPlayer.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r then r.AssemblyLinearVelocity += r.CFrame.LookVector * -30 + Vector3.new(0, 15, 0) end
	end
	Sound.play(name, a)
end)
Net.get("Open").OnClientEvent:Connect(function(name, data)
	if name == "close" then
		Windows.close()
	else
		Windows.open(name, data)
	end
end)

-- сервер, привет: пришли постройки, грибы и профиль
Net.get("Act"):FireServer("hello")
