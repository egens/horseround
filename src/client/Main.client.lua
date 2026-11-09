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
local Glow = require(Client.Glow)
local Hud = require(Client.UI.Hud)
local Windows = require(Client.UI.Windows)
local Minigames = require(Client.UI.Minigames)

Net.init()
State.init()

-- дождаться, пока сервер замерит высоту земли (после постройки рельефа)
local World = require(Shared.World)
local waitStart = os.clock()
while workspace:GetAttribute("GroundY") == nil and os.clock() - waitStart < 60 do task.wait(0.2) end
if workspace:GetAttribute("GroundY") == nil then warn("[HorseFarm] сервер не прислал высоту земли — считаем её нулевой") end
World.syncGround()
-- высота могла прийти позже — подхватить
workspace:GetAttributeChangedSignal("GroundY"):Connect(World.syncGround)

Hud.init()
Hud.windows = Windows
Windows.build(Hud.gui)
Minigames.init(Hud.gui)
Render.init()
Decor.init()
Effects.init()
Glow.init()
Controls.init(Windows, Minigames, Hud)

Net.get("Toast").OnClientEvent:Connect(Hud.toast)
State.on("toast", Hud.toast)
Sound.init()
Net.get("Sfx").OnClientEvent:Connect(function(name, a, b)
	if name == "neigh" then
		-- ржание слышно только рядом, и чем дальше — тем тише
		local vol = 1
		if a and b then
			local ch = game:GetService("Players").LocalPlayer.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if r then
				local x, y = World.fromStuds(r.Position)
				local d = math.sqrt((x - a) ^ 2 + (y - b) ^ 2)
				if d > 600 then return end
				vol = math.clamp(1 - d / 700, 0.25, 1)
			end
		end
		Sound.play("neigh", nil, vol)
		return
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

-- сервер, привет: пришли грибы и профиль
Net.get("Act"):FireServer("hello")
