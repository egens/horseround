--[[
	Эффекты на клиенте: свет (день, ночь, темнота в пещере), дождь и снег, радуга, лужи с отражением,
	праздничное настроение, летящие надписи, поезд, подкова на счастье,
	указатели упражнений (буква выездки, номер препятствия) и ворота скачек со стрелкой.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Net = require(Shared.Net)

local Client = script.Parent
local State = require(Client.State)
local Sound = require(Client.Sound)

local Effects = {}
local K = World.K
local player = Players.LocalPlayer
local color = Util.color
local folder

local function part(size, cf, c, material, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color(c)
	p.Material = material or Enum.Material.SmoothPlastic
	p.CastShadow = false
	if transparency then p.Transparency = transparency end
	p.Parent = folder
	return p
end

--[[ ---------- свет и атмосфера ---------- ]]
local atmosphere, cc
local function setupLighting()
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = color("#c7e3f5")
	atmosphere.Decay = color("#8fb5d8")
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
	cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
end

local function myPos()
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if not r then return nil end
	return World.fromStuds(r.Position)
end

local regionCache, regionT = "farm", 0
local function updateLight(dt)
	regionT -= dt
	local x, y = myPos()
	if x and regionT <= 0 then
		regionT = 0.3
		regionCache = World.regionAt(x, y)
	end
	local reg = regionCache
	local inCave = reg == "cave" or reg == "grottocave"
	local clock = Lighting.ClockTime
	local night = clock < 5 or clock > 21
	local dusk = (clock >= 5 and clock < 7) or (clock > 19 and clock <= 21)
	local amb = inCave and color("#2a2638") or night and color("#2c3550") or dusk and color("#8a7a80") or color("#a8a8a8")
	Lighting.Ambient = Lighting.Ambient:Lerp(amb, math.min(1, dt * 2))
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(inCave and color("#1e1a28") or night and color("#46506e") or color("#9aa3ad"), math.min(1, dt * 2))
	Lighting.Brightness = inCave and 0.6 or (night and 1 or 2.2)
	local wet = State.world.wet or 0
	local magic = reg == "mushroom"
	local tint = color("#ffffff")
	if wet > 0.01 and reg ~= "desert" and reg ~= "cave" and string.sub(reg, 1, 3) ~= "sky" and reg ~= "tundra" then
		tint = Color3.new(1, 1, 1):Lerp(magic and color("#d9c8f0") or color("#b9c6d6"), wet * 0.6)
	end
	if State.world.holiday == "halloween" and y and y <= World.H then tint = tint:Lerp(color("#c9b3d9"), 0.25) end
	cc.TintColor = cc.TintColor:Lerp(tint, math.min(1, dt * 2))
	cc.Saturation = reg == "tundra" and -0.1 or 0.05
	atmosphere.Density = inCave and 0.45 or (reg == "deepforest" or reg == "foxwood") and 0.4 or 0.28
	Effects.region = reg
	Sound.region = reg
end

--[[ ---------- дождь, снег, праздники ---------- ]]
local weatherPart, rainEmitter, snowEmitter, holidayEmitter
local function setupWeather()
	weatherPart = part(Vector3.new(80, 1, 80), CFrame.new(0, 60, 0), "#ffffff", nil, 1)
	weatherPart.Name = "Weather"
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rainEmitter.Rate = 0
	rainEmitter.Lifetime = NumberRange.new(1.2, 1.6)
	rainEmitter.Speed = NumberRange.new(60, 70)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.SpreadAngle = Vector2.new(4, 4)
	rainEmitter.Size = NumberSequence.new(0.15)
	rainEmitter.Transparency = NumberSequence.new(0.35)
	rainEmitter.Color = ColorSequence.new(color("#c8d7eb"))
	rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rainEmitter.Squash = NumberSequence.new(-2.5)
	rainEmitter.Parent = weatherPart
	snowEmitter = Instance.new("ParticleEmitter")
	snowEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snowEmitter.Rate = 0
	snowEmitter.Lifetime = NumberRange.new(5, 7)
	snowEmitter.Speed = NumberRange.new(8, 12)
	snowEmitter.EmissionDirection = Enum.NormalId.Bottom
	snowEmitter.SpreadAngle = Vector2.new(25, 25)
	snowEmitter.Size = NumberSequence.new(0.35)
	snowEmitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snowEmitter.Parent = weatherPart
	holidayEmitter = Instance.new("ParticleEmitter")
	holidayEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	holidayEmitter.Rate = 0
	holidayEmitter.Lifetime = NumberRange.new(5, 7)
	holidayEmitter.Speed = NumberRange.new(6, 10)
	holidayEmitter.EmissionDirection = Enum.NormalId.Bottom
	holidayEmitter.SpreadAngle = Vector2.new(30, 30)
	holidayEmitter.Size = NumberSequence.new(0.45)
	holidayEmitter.LightEmission = 0.6
	holidayEmitter.Parent = weatherPart
end
local function updateWeather()
	local cam = workspace.CurrentCamera
	if not cam then return end
	weatherPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 35, 0))
	local wet = State.world.wet or 0
	local reg = Effects.region or "farm"
	local dry = reg == "desert" or reg == "cave" or reg == "grottocave" or string.sub(reg, 1, 3) == "sky"
	local magic = reg == "mushroom"
	if reg == "tundra" then
		rainEmitter.Rate = 0
		snowEmitter.Rate = 220 * wet
	elseif dry then
		rainEmitter.Rate, snowEmitter.Rate = 0, 0
	else
		snowEmitter.Rate = 0
		rainEmitter.Rate = 600 * wet
		if magic then
			rainEmitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color("#ff6b6b")), ColorSequenceKeypoint.new(0.33, color("#ffd43b")),
				ColorSequenceKeypoint.new(0.66, color("#4dabf7")), ColorSequenceKeypoint.new(1, color("#cc5de8")),
			})
			rainEmitter.LightEmission = 0.6
		else
			rainEmitter.Color = ColorSequence.new(color("#c8d7eb"))
			rainEmitter.LightEmission = 0
		end
	end
	-- праздник: снежинки на Новый год, конфетти на Пасху, тёмные искры на Хэллоуин
	local hol = State.world.holiday
	local _, py = myPos()
	if hol and py and py <= World.H then
		holidayEmitter.Rate = hol == "newyear" and 90 or hol == "easter" and 40 or 12
		if hol == "newyear" then holidayEmitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
		elseif hol == "easter" then
			holidayEmitter.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color("#ff8fab")), ColorSequenceKeypoint.new(0.5, color("#69db7c")), ColorSequenceKeypoint.new(1, color("#74c0fc")) })
		else holidayEmitter.Color = ColorSequence.new(color("#ff7b00")) end
	else
		holidayEmitter.Rate = 0
	end
end

--[[ ---------- радуга и лужи ---------- ]]
local rainbowModel
local function buildRainbow()
	rainbowModel = Instance.new("Model")
	rainbowModel.Name = "Rainbow"
	local cols = { "#ff0000", "#ff8000", "#ffff00", "#00c000", "#0080ff", "#4b0082", "#8f00ff" }
	for i, c in ipairs(cols) do
		local R = 260 - (i - 1) * 6
		for k = 0, 23 do
			local a = k / 24 * math.pi
			local p = part(Vector3.new(6, 2 * math.pi * R / 48 + 1, 1), CFrame.new(math.cos(a) * R, math.sin(a) * R, 0) * CFrame.Angles(0, 0, a), c, Enum.Material.Neon, 1)
			p.Parent = rainbowModel
		end
	end
	local pp = part(Vector3.new(1, 1, 1), CFrame.new(), "#ffffff", nil, 1)
	pp.Parent = rainbowModel
	rainbowModel.PrimaryPart = pp
	rainbowModel.Parent = folder
end
local rainbowA = 0
local rainbowPlaced = nil
local function updateRainbow(dt)
	-- радуга стоит на месте в мире (место и направление выбирает сервер, одно на всех), камера её не двигает
	local at = State.world.rainbowAt
	local target = (State.world.rainbow or 0) > 0 and at and math.min(1, State.world.rainbow / 5) or 0
	local x, y = myPos()
	if not x or y > World.H then target = 0 end
	rainbowA += (target - rainbowA) * math.min(1, dt)
	if at and not (rainbowPlaced and rainbowPlaced.x == at.x and rainbowPlaced.y == at.y and rainbowPlaced.a == at.a) then
		rainbowPlaced = at
		-- центр арки чуть ниже земли, чтобы концы радуги уходили в землю
		local center = World.toStuds(at.x, at.y, World.GROUND - 40)
		local dir = Vector3.new(math.cos(at.a), 0, math.sin(at.a))
		-- арка повёрнута лицом к игрокам: они в стороне, обратной направлению dir
		rainbowModel:PivotTo(CFrame.lookAt(center, center + dir))
	end
	local tr = 1 - rainbowA * 0.55
	for _, p in ipairs(rainbowModel:GetChildren()) do
		if p ~= rainbowModel.PrimaryPart then p.Transparency = tr end
	end
end

local puddles = {}
local puddleT = 0
local function updatePuddles(dt)
	puddleT -= dt
	if puddleT > 0 then return end
	puddleT = 0.5
	local level = State.world.puddle or 0
	local x, y = myPos()
	local reg = Effects.region or "farm"
	local dry = reg == "desert" or reg == "cave" or reg == "tundra" or string.sub(reg, 1, 3) == "sky" or reg == "sea"
	if level < 0.05 or not x or dry then
		for _, p in ipairs(puddles) do p:Destroy() end
		table.clear(puddles)
		return
	end
	-- лужи вокруг игрока: если ушёл далеко — переложить
	local want = math.floor(18 * level)
	local magic = reg == "mushroom"
	for i = #puddles, 1, -1 do
		local p = puddles[i]
		local px, py = World.fromStuds(p.Position)
		if Util.hypot(px - x, py - y) > 1600 or i > want then
			p:Destroy()
			table.remove(puddles, i)
		end
	end
	local tries = 0
	while #puddles < want and tries < 20 do
		tries += 1
		local a, d = math.random() * math.pi * 2, 300 + math.random() * 1100
		local qx, qy = x + math.cos(a) * d, y + math.sin(a) * d
		local hz = World.heightAt
		local flat = math.abs(hz(qx + 40, qy) - hz(qx - 40, qy)) < 0.5 and math.abs(hz(qx, qy + 40) - hz(qx, qy - 40)) < 0.5
		if flat and not World.blocked(qx, qy, 40) then
			local s = 3 + math.random() * 5
			local p = part(Vector3.new(0.06, s * 2, s * 1.4), CFrame.new(qx * K, World.groundY(qx, qy) + 0.03, qy * K) * CFrame.Angles(0, math.random() * 3, math.pi / 2),
				magic and Util.pick({ "#ff8fab", "#ffd43b", "#74c0fc", "#b197fc" }) or "#6f8fa8", Enum.Material.Glass, 0.25)
			p.Shape = Enum.PartType.Cylinder
			p.Reflectance = 0.6
			table.insert(puddles, p)
		end
	end
end

-- лошадь наступила в лужу? (для звука шлёпанья)
Sound.nearPuddle = function(pos)
	for _, p in ipairs(puddles) do
		local d = Vector3.new(p.Position.X - pos.X, 0, p.Position.Z - pos.Z).Magnitude
		if d < p.Size.Y * 0.5 + 1.5 then return true end
	end
	return false
end

--[[ ---------- летящие надписи ---------- ]]
local floats = {}
local function addFloat(text, x, y, c)
	local px, py = myPos()
	if not px or Util.hypot(px - x, py - y) > 2500 then return end
	local anchor = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(x * K, World.groundY(x, y) + 9, y * K), "#ffffff", nil, 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 34)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = 22
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color(c or "#333333")
	t.TextStrokeColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.1
	t.Parent = bb
	table.insert(floats, { p = anchor, t = 0, label = t, y0 = anchor.Position.Y })
end
local function updateFloats(dt)
	for i = #floats, 1, -1 do
		local f = floats[i]
		f.t += dt
		f.p.Position = Vector3.new(f.p.Position.X, f.y0 + f.t * 3, f.p.Position.Z)
		f.label.TextTransparency = math.clamp(f.t / 1.4, 0, 1)
		f.label.TextStrokeTransparency = math.clamp(0.1 + f.t / 1.4, 0, 1)
		if f.t > 1.4 then
			f.p:Destroy()
			table.remove(floats, i)
		end
	end
end

--[[ ---------- поезд и подкова ---------- ]]
local trainModel, shoeModel
local function buildTrain()
	trainModel = Instance.new("Model")
	trainModel.Name = "Train"
	local base = part(Vector3.new(1, 1, 1), CFrame.new(), "#ffffff", nil, 1)
	base.Parent = trainModel
	trainModel.PrimaryPart = base
	-- паровоз
	local function add(size, off, c, mat)
		local p = part(size, CFrame.new(off), c, mat)
		p.Parent = trainModel
		return p
	end
	add(Vector3.new(12, 5, 5), Vector3.new(0, 3.5, 0), "#c92a2a", Enum.Material.Metal)
	add(Vector3.new(4, 7, 5), Vector3.new(-4, 4.5, 0), "#212529", Enum.Material.Metal)
	add(Vector3.new(1.4, 3, 1.4), Vector3.new(4, 7.5, 0), "#212529", Enum.Material.Metal)
	for i = 1, 4 do
		local x = -14 * i
		add(Vector3.new(12, 5.5, 5), Vector3.new(x, 3.8, 0), i % 2 == 0 and "#2b8a3e" or "#1c7ed6", Enum.Material.Metal)
		add(Vector3.new(12.4, 0.5, 5.4), Vector3.new(x, 6.8, 0), "#495057", Enum.Material.Metal)
		for _, s in ipairs({ -1, 1 }) do
			add(Vector3.new(1.6, 1.6, 0.2), Vector3.new(x + s * 3, 4.4, 2.55), "#ffe066", Enum.Material.Neon)
			add(Vector3.new(1.6, 1.6, 0.2), Vector3.new(x + s * 3, 4.4, -2.55), "#ffe066", Enum.Material.Neon)
		end
	end
	for i = 0, 4 do
		for _, s in ipairs({ -1, 1 }) do
			local p = add(Vector3.new(0.4, 2, 2), Vector3.new(-14 * i + 3, 1, s * 2.4), "#343a40", Enum.Material.Metal)
			p.Shape = Enum.PartType.Cylinder
			p.CFrame = CFrame.new(-14 * i + 3, 1, s * 2.4) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 8
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Size = NumberSequence.new(1, 4)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Color = ColorSequence.new(color("#adb5bd"))
	smoke.Parent = trainModel:GetChildren()[4]
	trainModel.Parent = nil
end
local trainX = nil
local function updateTrain(dt)
	local tr = State.world.train
	if not tr then
		trainModel.Parent = nil
		trainX = nil
		return
	end
	trainX = trainX and (trainX + (tr.x - trainX) * math.min(1, dt * 3)) or tr.x
	trainModel.Parent = folder
	trainModel:PivotTo(CFrame.new(trainX * K, World.GROUND, World.RAIL.y * K))
end
local function buildShoe()
	shoeModel = Instance.new("Model")
	local p = part(Vector3.new(1.4, 0.3, 1.4), CFrame.new(), "#ffd43b", Enum.Material.Neon)
	p.Parent = shoeModel
	local l = Instance.new("PointLight")
	l.Color = color("#ffe066")
	l.Range = 10
	l.Parent = p
	local s = Instance.new("Sparkles")
	s.SparkleColor = color("#fff3bf")
	s.Parent = p
	shoeModel.PrimaryPart = p
end
local function updateShoe(t)
	local s = State.world.shoe
	if not s then
		shoeModel.Parent = nil
		return
	end
	shoeModel.Parent = folder
	shoeModel:PivotTo(CFrame.new(s.x * K, World.groundY(s.x, s.y) + 0.6 + math.sin(t * 5) * 0.3, s.y * K) * CFrame.Angles(0, t * 2, 0))
end

--[[ ---------- указатели: упражнения и скачки ---------- ]]
local marker, arrow
local gateModels = {}
local function buildMarkers()
	marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Material = Enum.Material.Neon
	marker.Color = color("#ffd43b")
	marker.Transparency = 0.45
	marker.Size = Vector3.new(0.3, 9, 9)
	marker.CastShadow = false
	marker.Parent = nil
	arrow = Instance.new("Part")
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.Material = Enum.Material.Neon
	arrow.Color = color("#ffd400")
	arrow.Size = Vector3.new(0.5, 0.3, 3)
	arrow.CastShadow = false
	local tip = Instance.new("WedgePart")
	tip.Anchored = true
	tip.CanCollide = false
	tip.Material = Enum.Material.Neon
	tip.Color = color("#ffd400")
	tip.Size = Vector3.new(0.3, 1.6, 1.6)
	tip.Name = "Tip"
	tip.Parent = arrow
	arrow.Parent = nil
end
local function syncGates()
	for _, m in ipairs(gateModels) do m:Destroy() end
	table.clear(gateModels)
	local r = State.race
	if not r or not r.gates then return end
	for i, g in ipairs(r.gates) do
		local m = Instance.new("Model")
		local perp = Vector3.new(-math.sin(0), 0, math.cos(0))
		local prev = i > 1 and r.gates[i - 1] or nil
		local a = prev and math.atan2(g.y - prev.y, g.x - prev.x) or (r.dir or 0)
		perp = Vector3.new(-math.sin(a), 0, math.cos(a))
		local c = World.toStuds(g.x, g.y, World.groundY(g.x, g.y))
		for _, s in ipairs({ -1, 1 }) do
			local post = part(Vector3.new(0.6, 6, 0.6), CFrame.new(c + perp * 6 * s + Vector3.new(0, 3, 0)), g.finish and "#111111" or "#1c7ed6")
			post.Parent = m
		end
		local banner = part(Vector3.new(0.3, 1.4, 12.6), CFrame.lookAt(c + Vector3.new(0, 6.2, 0), c + Vector3.new(0, 6.2, 0) + perp) * CFrame.Angles(0, math.pi / 2, 0),
			g.finish and "#ffffff" or "#ffd43b", Enum.Material.Neon, 0.1)
		banner.Parent = m
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(120, 36)
		bb.StudsOffset = Vector3.new(0, 2, 0)
		bb.AlwaysOnTop = true
		bb.Parent = banner
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = g.finish and "🏁 ФИНИШ" or ("Ворота " .. g.n)
		tl.TextSize = 18
		tl.Font = Enum.Font.GothamBlack
		tl.TextColor3 = color("#b35c00")
		tl.TextStrokeTransparency = 0.2
		tl.TextStrokeColor3 = Color3.new(1, 1, 1)
		tl.Parent = bb
		m.Parent = folder
		gateModels[i] = m
	end
end
local function arrowTo(tx, ty, t)
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pos = hrp.Position
	local target = World.toStuds(tx, ty, pos.Y)
	local dir = target - pos
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1 then return end
	dir = dir.Unit
	local bob = math.sin(t * 5) * 0.4
	local base = pos + Vector3.new(0, 4.5, 0) + dir * (6 + bob)
	arrow.CFrame = CFrame.lookAt(base, base + dir)
	arrow.Tip.CFrame = arrow.CFrame * CFrame.new(0, 0, -2.2) * CFrame.Angles(0, math.pi / 2, math.pi / 2)
	arrow.Parent = folder
end
local function updateMarkers(t)
	arrow.Parent = nil
	marker.Parent = nil
	local r = State.race
	if r and r.gates then
		local g = r.gates[math.min(r.next or 1, #r.gates)]
		if g then arrowTo(g.x, g.y, t) end
		for i, m in ipairs(gateModels) do
			local done = i < (r.next or 1)
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("BasePart") then p.Transparency = done and 0.8 or (i == r.next and 0 or 0.4) end
			end
		end
		return
	end
	local c = State.course
	if not c then return end
	local tx, ty
	if c.type == "dres" and c.letter then
		local p = World.letterTarget(c.letter)
		tx, ty = p.x, p.y
	elseif c.type == "jump" and c.i then
		local o = World.COURSE[c.i]
		if o then tx, ty = o.x, o.y end
	elseif c.type == "cav" then
		tx, ty = World.CAV.poles[1] - 60, (World.CAV.y1 + World.CAV.y2) / 2
	end
	if tx then
		marker.CFrame = CFrame.new(tx * K, World.groundY(tx, ty) + 0.15 + math.sin(t * 6) * 0.05, ty * K) * CFrame.Angles(0, 0, math.pi / 2)
		marker.Size = Vector3.new(0.3, 7 + math.sin(t * 6) * 0.6, 7 + math.sin(t * 6) * 0.6)
		marker.Parent = folder
		arrowTo(tx, ty, t)
	end
end

function Effects.init()
	folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = workspace
	setupLighting()
	setupWeather()
	buildRainbow()
	buildTrain()
	buildShoe()
	buildMarkers()
	Net.get("Float").OnClientEvent:Connect(addFloat)
	State.on("race", syncGates)
	local t0 = os.clock()
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		updateLight(dt)
		updateWeather()
		updateRainbow(dt)
		updatePuddles(dt)
		updateFloats(dt)
		updateTrain(dt)
		updateShoe(t)
		updateMarkers(t)
	end)
end
Effects.float = addFloat

return Effects
