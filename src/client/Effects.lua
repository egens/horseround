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
	-- Драконьи скалы — мрачные: красноватая дымка, приглушённый тёплый свет
	local dragon = reg == "dragonrock"
	if dragon then tint = tint:Lerp(color("#ffc2a8"), 0.55) end
	cc.TintColor = cc.TintColor:Lerp(tint, math.min(1, dt * 2))
	cc.Saturation = reg == "tundra" and -0.1 or dragon and -0.15 or 0.05
	cc.Contrast = cc.Contrast + ((dragon and 0.18 or 0) - cc.Contrast) * math.min(1, dt * 2)
	atmosphere.Density = inCave and 0.45 or dragon and 0.46 or (reg == "deepforest" or reg == "foxwood") and 0.4 or 0.28
	atmosphere.Color = atmosphere.Color:Lerp(dragon and color("#7a3b2a") or color("#c7e3f5"), math.min(1, dt * 2))
	atmosphere.Decay = atmosphere.Decay:Lerp(dragon and color("#2b0f0a") or color("#8fb5d8"), math.min(1, dt * 2))
	if dragon and not inCave then Lighting.Brightness = night and 0.8 or 1.5 end
	Effects.region = reg
	Sound.region = reg
end

--[[ ---------- дождь, снег, праздники ---------- ]]
local weatherPart, rainEmitter, snowEmitter, holidayEmitter
local function setupWeather()
	weatherPart = part(Vector3.new(110, 1, 110), CFrame.new(0, 60, 0), "#ffffff", nil, 1)
	weatherPart.Name = "Weather"
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rainEmitter.Rate = 0
	rainEmitter.Lifetime = NumberRange.new(1.1, 1.5)
	rainEmitter.Speed = NumberRange.new(62, 72)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.SpreadAngle = Vector2.new(5, 5)
	-- длинные вытянутые капли: Squash > 0 вытягивает частицу вверх (раньше было < 0 — капли
	-- сплющивались в невидимые полоски, и дождя почти не было видно)
	rainEmitter.Size = NumberSequence.new(0.22)
	rainEmitter.Transparency = NumberSequence.new(0.15)
	rainEmitter.Brightness = 1.4
	rainEmitter.Color = ColorSequence.new(color("#e3ecf8"))
	rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rainEmitter.Squash = NumberSequence.new(3)
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
		-- в тундре снег идёт всегда, а в непогоду — метель
		rainEmitter.Rate = 0
		snowEmitter.Rate = 90 + 260 * wet
	elseif dry then
		rainEmitter.Rate, snowEmitter.Rate = 0, 0
	else
		snowEmitter.Rate = 0
		rainEmitter.Rate = 1100 * wet
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

-- Лужи стоят на постоянных местах (по сетке вокруг игрока), растут в дождь и высыхают после.
-- Где лужа высохла — вырастает свежая трава. Разноцветные лужи — только в Грибном королевстве.
local puddles = {}   -- [key] = { p, x, y, s, max }
local sprouts = {}   -- [key] = { m, t }
local puddleT = 0
local CELL = 130
local NOPUDDLE = { desert = true, cave = true, tundra = true, sea = true, grottocave = true, market = true, dragonrock = true }
local function hash(i, j, k)
	local v = math.sin(i * 12.9898 + j * 78.233 + (k or 0) * 37.719) * 43758.5453
	return v - math.floor(v)
end
local function sprout(key, x, y, magic)
	if sprouts[key] then return end
	local m = Instance.new("Model")
	m.Name = "FreshGrass"
	local gy = World.groundY(x, y)
	for i = 1, 9 do
		local a, d = hash(i, 3, x) * 6.28, hash(i, 5, y) * 1.6
		local h = 0.5 + hash(i, 7, x + y) * 0.9
		local b = part(Vector3.new(0.12, h, 0.3), CFrame.new(x * K + math.cos(a) * d, gy + h / 2 - 0.05, y * K + math.sin(a) * d) * CFrame.Angles(0, a, 0.2 + hash(i, 9, x) * 0.3),
			magic and "#f08ac4" or (i % 2 == 0 and "#6cc04a" or "#57a83b"), Enum.Material.Grass)
		b.Parent = m
	end
	if hash(1, 1, x * y) < 0.4 then
		local f = part(Vector3.new(0.3, 0.12, 0.3), CFrame.new(x * K + 0.5, gy + 0.7, y * K), magic and "#ffffff" or "#ffe066")
		f.Shape = Enum.PartType.Ball
		f.Parent = m
	end
	m.Parent = folder
	sprouts[key] = { m = m, t = 0 }
end
local function updatePuddles(dt)
	puddleT -= dt
	for key, sp in pairs(sprouts) do
		sp.t += dt
		if sp.t > 240 then
			sp.m:Destroy()
			sprouts[key] = nil
		end
	end
	if puddleT > 0 then return end
	puddleT = 0.4
	local level = State.world.puddle or 0
	local x, y = myPos()
	if not x or y > World.H then
		for k, q in pairs(puddles) do q.p:Destroy(); puddles[k] = nil end
		return
	end
	local grow = math.clamp(level * 1.25, 0, 1)
	local ci, cj = math.floor(x / CELL), math.floor(y / CELL)
	local R = 9
	local seen = {}
	for i = ci - R, ci + R do
		for j = cj - R, cj + R do
			if hash(i, j) < 0.16 then
				local key = i .. "|" .. j
				seen[key] = true
				local q = puddles[key]
				if not q and grow > 0.04 then
					local qx, qy = (i + 0.2 + hash(i, j, 1) * 0.6) * CELL, (j + 0.2 + hash(i, j, 2) * 0.6) * CELL
					local reg = World.regionAt(qx, qy)
					local hz = World.heightAt
					local flat = math.abs(hz(qx + 40, qy) - hz(qx - 40, qy)) < 0.6 and math.abs(hz(qx, qy + 40) - hz(qx, qy - 40)) < 0.6
					if not NOPUDDLE[reg] and string.sub(reg, 1, 3) ~= "sky" and flat and not World.blocked(qx, qy, 40) and not World.inRect(qx, qy, World.STABLE, 30) then
						local magic = reg == "mushroom"
						local p = part(Vector3.new(0.06, 1, 1), CFrame.new(qx * K, World.groundY(qx, qy) + 0.04, qy * K) * CFrame.Angles(0, hash(i, j, 3) * 3, math.pi / 2),
							magic and ({ "#ff8fab", "#ffd43b", "#74c0fc", "#b197fc" })[math.floor(hash(i, j, 4) * 4) + 1] or "#6f8fa8", Enum.Material.Glass, 0.25)
						p.Shape = Enum.PartType.Cylinder
						p.Reflectance = 0.6
						q = { p = p, x = qx, y = qy, s = 3 + hash(i, j, 5) * 5, max = 0, magic = magic }
						puddles[key] = q
					else
						puddles[key] = { dead = true }
					end
				end
				if q and not q.dead then
					q.max = math.max(q.max, grow)
					local s0 = q.s * grow
					if s0 < 0.3 then
						-- лужа высохла — на её месте свежая травка
						if q.max > 0.35 then sprout(key, q.x, q.y, q.magic) end
						q.p:Destroy()
						puddles[key] = nil
					else
						q.p.Size = Vector3.new(0.06, s0 * 2, s0 * 1.4)
					end
				elseif q and q.dead and grow <= 0.04 then
					puddles[key] = nil
				end
			end
		end
	end
	for key, q in pairs(puddles) do
		if not seen[key] then
			if q.p then q.p:Destroy() end
			puddles[key] = nil
		end
	end
	for key, sp in pairs(sprouts) do
		local px, py = World.fromStuds(sp.m:GetPivot().Position)
		if Util.hypot(px - x, py - y) > 2200 then
			sp.m:Destroy()
			sprouts[key] = nil
		end
	end
end

-- лошадь наступила в лужу? (для звука шлёпанья)
Sound.nearPuddle = function(pos)
	for _, q in pairs(puddles) do
		local p = q.p
		if p then
			local d = Vector3.new(p.Position.X - pos.X, 0, p.Position.Z - pos.Z).Magnitude
			if d < p.Size.Y * 0.5 + 1.5 then return true end
		end
	end
	return false
end

--[[ ---------- рыбы в озёрах и в море ---------- ]]
local fishes = {}
local fishT = 0
local FISH_COLS = { "#ff922b", "#adb5bd", "#ffd43b", "#74c0fc", "#e8590c", "#8ce99a", "#c0a080" }
local function makeFish(c, s)
	local m = Instance.new("Model")
	m.Name = "Fish"
	local body = part(Vector3.new(1.2 * s, 0.45 * s, 0.32 * s), CFrame.new(), c)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.Parent = m
	m.PrimaryPart = body
	local tail = Instance.new("WedgePart")
	tail.Anchored, tail.CanCollide, tail.CanQuery, tail.CanTouch, tail.CastShadow = true, false, false, false, false
	tail.Size = Vector3.new(0.08 * s, 0.55 * s, 0.45 * s)
	tail.Color = color(Util.mix(c, "#000000", 0.15))
	tail.CFrame = CFrame.new(-0.75 * s, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	tail.Parent = m
	local fin = part(Vector3.new(0.4 * s, 0.25 * s, 0.05 * s), CFrame.new(0, 0.25 * s, 0) * CFrame.Angles(0, 0, -0.3), Util.mix(c, "#000000", 0.2))
	fin.Parent = m
	for _, z in ipairs({ -1, 1 }) do
		local eye = part(Vector3.new(0.08 * s, 0.08 * s, 0.05 * s), CFrame.new(0.42 * s, 0.05 * s, z * 0.15 * s), "#111111")
		eye.Parent = m
	end
	m.Parent = folder
	return m
end
local function updateFish(dt, t)
	fishT -= dt
	if fishT <= 0 then
		fishT = 1
		local x, y = myPos()
		local want = {}
		if x and y <= World.H then
			for li, L in ipairs(World.LAKES) do
				if not L.lava and not L.ice and Util.hypot(L.x - x, L.y - y) < 2600 then
					local n = math.clamp(math.floor(L.rx * L.ry / 9000), 3, 10)
					for k = 1, n do want["L" .. li .. "_" .. k] = { lake = L, k = k } end
				end
			end
			local cx = World.coastX(y)
			if x > cx - 1800 then
				for k = 1, 16 do
					local ax = math.max(x, cx + 250) + (hash(k, 1) - 0.3) * 1600
					local ay = y + (hash(k, 2) - 0.5) * 2200
					if ax > World.coastX(ay) + 150 and not World.islandAt(ax, ay, -120) then want["S" .. k .. "_" .. math.floor(x / 1500) .. "_" .. math.floor(y / 1500)] = { sx = ax, sy = ay, k = k } end
				end
			end
		end
		for key, f in pairs(fishes) do
			if not want[key] then f.m:Destroy(); fishes[key] = nil end
		end
		for key, w in pairs(want) do
			if not fishes[key] then
				local seed = #key + w.k * 7
				local f = { m = makeFish(FISH_COLS[(seed % #FISH_COLS) + 1], 0.8 + hash(seed, 3) * 1.2), ph = hash(seed, 4) * 6.28, sp = 0.15 + hash(seed, 5) * 0.25, dir = hash(seed, 6) < 0.5 and 1 or -1 }
				if w.lake then
					local L = w.lake
					local a, d = hash(seed, 7) * 6.28, 0.15 + hash(seed, 8) * 0.35
					f.cx, f.cy = L.x + math.cos(a) * L.rx * d * 0.6, L.y + math.sin(a) * L.ry * d * 0.6
					f.rad = math.min(L.rx, L.ry) * (0.12 + hash(seed, 9) * 0.18)
					f.y = World.GROUND + World.LAKE_WATER - 0.9 - hash(seed, 10) * 1.6
				else
					f.cx, f.cy = w.sx, w.sy
					f.rad = 80 + hash(seed, 9) * 200
					f.y = World.GROUND - 3.2 - hash(seed, 10) * 5
				end
				fishes[key] = f
			end
		end
	end
	for _, f in pairs(fishes) do
		local a = f.ph + t * f.sp * f.dir
		local fx, fy = f.cx + math.cos(a) * f.rad, f.cy + math.sin(a) * f.rad
		local dx, dy = -math.sin(a) * f.dir, math.cos(a) * f.dir
		local wig = math.sin(t * 9 + f.ph) * 0.18
		f.m:PivotTo(CFrame.lookAt(Vector3.new(fx * K, f.y + math.sin(t * 1.3 + f.ph) * 0.15, fy * K), Vector3.new(fx * K + dx, f.y, fy * K + dy)) * CFrame.Angles(0, math.pi / 2 + wig, 0))
	end
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
	-- поезд большой, как настоящий: паровоз с котлом, будкой, трубой и большими колёсами,
	-- и четыре вагона с окнами, дверями и крышами
	trainModel = Instance.new("Model")
	trainModel.Name = "Train"
	local base = part(Vector3.new(1, 1, 1), CFrame.new(), "#ffffff", nil, 1)
	base.Parent = trainModel
	trainModel.PrimaryPart = base
	local MET = Enum.Material.Metal
	local function add(size, off, c, mat, shape)
		local p = part(size, typeof(off) == "CFrame" and off or CFrame.new(off), c, mat)
		if shape then p.Shape = shape end
		p.Parent = trainModel
		return p
	end
	local function wheel(x, z, r)
		add(Vector3.new(0.5, r * 2, r * 2), CFrame.new(x, r + 0.7, z) * CFrame.Angles(0, math.pi / 2, 0), "#2b2f33", MET, Enum.PartType.Cylinder)
		add(Vector3.new(0.55, r * 0.6, r * 0.6), CFrame.new(x, r + 0.7, z + (z > 0 and 0.05 or -0.05)) * CFrame.Angles(0, math.pi / 2, 0), "#c92a2a", MET, Enum.PartType.Cylinder)
	end
	-- паровоз
	add(Vector3.new(20, 1.2, 7.4), Vector3.new(0, 2.6, 0), "#212529", MET)
	add(Vector3.new(14, 5.4, 5.4), CFrame.new(3, 6, 0), "#c92a2a", MET, Enum.PartType.Cylinder)
	add(Vector3.new(0.6, 5.6, 5.6), CFrame.new(10.2, 6, 0), "#343a40", MET, Enum.PartType.Cylinder)
	for _, x in ipairs({ -1, 3, 7 }) do add(Vector3.new(0.5, 5.8, 5.8), CFrame.new(x, 6, 0), "#ffd43b", MET, Enum.PartType.Cylinder) end
	add(Vector3.new(1.8, 4.5, 1.8), CFrame.new(7.5, 10.5, 0) * CFrame.Angles(0, 0, math.pi / 2), "#212529", MET, Enum.PartType.Cylinder)
	add(Vector3.new(0.6, 2.8, 2.8), CFrame.new(7.5, 12.9, 0) * CFrame.Angles(0, 0, math.pi / 2), "#212529", MET, Enum.PartType.Cylinder)
	add(Vector3.new(1.6, 1.6, 1.6), Vector3.new(2, 9.3, 0), "#ffd43b", MET, Enum.PartType.Ball)
	add(Vector3.new(0.8, 0.8, 0.4), Vector3.new(10.6, 6.5, 0), "#fff3bf", Enum.Material.Neon)
	-- будка машиниста
	add(Vector3.new(6, 8, 7.4), Vector3.new(-6, 7.2, 0), "#212529", MET)
	add(Vector3.new(7, 0.5, 8.2), Vector3.new(-6, 11.4, 0), "#495057", MET)
	for _, z in ipairs({ -3.75, 3.75 }) do add(Vector3.new(2.6, 2.4, 0.15), Vector3.new(-5.4, 8.6, z), "#a5d8ff", Enum.Material.Glass) end
	-- метельник (решётка спереди)
	local cc0 = Instance.new("WedgePart")
	cc0.Anchored, cc0.CanCollide, cc0.CanQuery = true, false, false
	cc0.Size = Vector3.new(6.4, 2.2, 2.6)
	cc0.Color, cc0.Material = color("#868e96"), MET
	cc0.CFrame = CFrame.new(11.3, 1.9, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	cc0.Parent = trainModel
	for _, x in ipairs({ -6, -1.5, 3, 7.5 }) do
		for _, z in ipairs({ -2.5, 2.5 }) do wheel(x, z, x < 0 and 1.6 or 2.2) end
	end
	add(Vector3.new(14, 0.3, 0.3), Vector3.new(0.5, 2.5, 3.85), "#adb5bd", MET)
	add(Vector3.new(14, 0.3, 0.3), Vector3.new(0.5, 2.5, -3.85), "#adb5bd", MET)
	-- тендер
	add(Vector3.new(9, 5, 7.2), Vector3.new(-15, 4.6, 0), "#343a40", MET)
	add(Vector3.new(8, 1, 6.4), Vector3.new(-15, 7.4, 0), "#111111", Enum.Material.Slate)
	for _, x in ipairs({ -17.5, -12.5 }) do for _, z in ipairs({ -2.5, 2.5 }) do wheel(x, z, 1.4) end end
	-- вагоны
	for i = 1, 4 do
		local x = -21 - i * 21 + 2
		local c = i % 2 == 0 and "#2b8a3e" or "#1c7ed6"
		add(Vector3.new(19, 1, 7.6), Vector3.new(x, 2.4, 0), "#212529", MET)
		add(Vector3.new(19, 7, 7.6), Vector3.new(x, 6.4, 0), c, MET)
		add(Vector3.new(19.6, 0.6, 8.2), Vector3.new(x, 10.2, 0), "#495057", MET)
		add(Vector3.new(17, 0.8, 5), Vector3.new(x, 10.8, 0), "#6c757d", MET)
		add(Vector3.new(19.05, 0.5, 7.65), Vector3.new(x, 4.2, 0), "#ffd43b", MET)
		for w = -3, 3 do
			if w ~= 0 then
				for _, z in ipairs({ -3.82, 3.82 }) do add(Vector3.new(1.9, 2.2, 0.12), Vector3.new(x + w * 2.5, 7.2, z), "#fff3bf", Enum.Material.Neon) end
			end
		end
		for _, z in ipairs({ -3.84, 3.84 }) do add(Vector3.new(2, 5.2, 0.14), Vector3.new(x, 6.1, z), "#5c3d1e", Enum.Material.WoodPlanks) end
		for _, wx in ipairs({ -6.5, -4.5, 4.5, 6.5 }) do for _, z in ipairs({ -2.5, 2.5 }) do wheel(x + wx, z, 1.3) end end
		add(Vector3.new(2, 0.5, 0.5), Vector3.new(x + 10.5, 2.4, 0), "#343a40", MET)
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 10
	smoke.Lifetime = NumberRange.new(2.5, 4)
	smoke.Speed = NumberRange.new(4, 7)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Size = NumberSequence.new(1.6, 6)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Color = ColorSequence.new(color("#adb5bd"))
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	local chimney = part(Vector3.new(1, 1, 1), CFrame.new(7.5, 13.3, 0), "#ffffff", nil, 1)
	chimney.Parent = trainModel
	smoke.Parent = chimney
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
	-- золотая подкова как настоящая: дуга с «пятками», желобок с дырочками для гвоздей, блестящее золото
	shoeModel = Instance.new("Model")
	shoeModel.Name = "GoldShoe"
	local center = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(), "#ffffff", nil, 1)
	center.Parent = shoeModel
	shoeModel.PrimaryPart = center
	local GOLD = "#f2c230"
	local R, W = 0.8, 0.38
	local n = 11
	local a0, a1 = -math.pi * 0.05, math.pi * 1.05
	for i = 0, n - 1 do
		local a = a0 + (a1 - a0) * (i + 0.5) / n
		-- кусочек дуги: X — поперёк дуги, Y — вдоль дуги, Z — толщина подковы
		local seg = part(Vector3.new(W, (a1 - a0) * R / n + 0.06, 0.2), CFrame.new(math.cos(a) * R, math.sin(a) * R, 0) * CFrame.Angles(0, 0, a), GOLD, Enum.Material.Metal)
		seg.Reflectance = 0.35
		seg.Parent = shoeModel
		-- желобок и дырочки для гвоздей
		local groove = part(Vector3.new(0.06, (a1 - a0) * R / n + 0.02, 0.22), seg.CFrame * CFrame.new(0, 0, 0.02), "#c99a17", Enum.Material.Metal)
		groove.Parent = shoeModel
		if i % 2 == 1 and i > 0 and i < n - 1 then
			local hole = part(Vector3.new(0.09, 0.09, 0.23), seg.CFrame * CFrame.new(0, 0, 0.01), "#3b2a10")
			hole.Parent = shoeModel
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local heel = part(Vector3.new(W * 1.1, 0.25, 0.26), CFrame.new(sx * R, -0.05, 0), GOLD, Enum.Material.Metal)
		heel.Reflectance = 0.35
		heel.Parent = shoeModel
	end
	local l = Instance.new("PointLight")
	l.Color = color("#ffe066")
	l.Range = 12
	l.Brightness = 1.4
	l.Parent = center
	local sp = Instance.new("ParticleEmitter")
	sp.Rate = 6
	sp.Lifetime = NumberRange.new(0.6, 1.2)
	sp.Speed = NumberRange.new(0.5, 1.5)
	sp.SpreadAngle = Vector2.new(180, 180)
	sp.LightEmission = 1
	sp.Size = NumberSequence.new(0.25, 0)
	sp.Color = ColorSequence.new(color("#fff3bf"))
	sp.Parent = center
end
local function updateShoe(t)
	local s = State.world.shoe
	if not s then
		shoeModel.Parent = nil
		return
	end
	shoeModel.Parent = folder
	-- подкова стоит «на пятках» и медленно поворачивается
	shoeModel:PivotTo(CFrame.new(s.x * K, World.groundY(s.x, s.y) + 0.35 + math.sin(t * 3) * 0.12, s.y * K) * CFrame.Angles(0, t * 1.5, 0))
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
	marker.Transparency = 0.35
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
	if arrow.Parent ~= folder then arrow.Parent = folder end
end
-- указатели не мигают: родителя меняем только когда нужно (раньше их убирали и возвращали каждый кадр),
-- и кружок поднят над землёй, чтобы не «дрался» с песком (z-fighting)
local markRay = RaycastParams.new()
markRay.FilterType = Enum.RaycastFilterType.Include
markRay.FilterDescendantsInstances = { workspace.Terrain }
local function surface(x, y)
	local g = World.groundY(x, y)
	local hit = workspace:Raycast(Vector3.new(x * K, g + 6, y * K), Vector3.new(0, -14, 0), markRay)
	return hit and hit.Position.Y or g
end
local function setParent(o, p) if o.Parent ~= p then o.Parent = p end end
local function updateMarkers(t)
	local showArrow, showMarker = false, false
	local function arrowTo2(tx, ty)
		showArrow = true
		arrowTo(tx, ty, t)
	end
	local function finish()
		if not showArrow then setParent(arrow, nil) end
		if not showMarker then setParent(marker, nil) end
	end
	local r = State.race
	if r and r.gates then
		local g = r.gates[math.min(r.next or 1, #r.gates)]
		if g then arrowTo2(g.x, g.y) end
		for i, m in ipairs(gateModels) do
			local done = i < (r.next or 1)
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("BasePart") then p.Transparency = done and 0.8 or (i == r.next and 0 or 0.4) end
			end
		end
		return finish()
	end
	local c = State.course
	if not c then return finish() end
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
		local sy = surface(tx, ty)
		marker.CFrame = CFrame.new(tx * K, sy + 0.35, ty * K) * CFrame.Angles(0, 0, math.pi / 2)
		marker.Size = Vector3.new(0.12, 7 + math.sin(t * 3) * 0.3, 7 + math.sin(t * 3) * 0.3)
		showMarker = true
		setParent(marker, folder)
		arrowTo2(tx, ty)
	end
	finish()
end

-- клетчатый флаг у старта скачек колышется на ветру
local flagCells
local function updateFlag(t)
	if flagCells == nil then
		flagCells = false
		task.spawn(function()
			local w = workspace:WaitForChild("World", 60)
			local farm = w and w:WaitForChild("Farm", 60)
			local f = farm and farm:WaitForChild("RaceFlag", 60)
			if not f then return end
			task.wait(1)
			local list = {}
			for _, p in ipairs(f:GetChildren()) do
				if p.Name == "FlagCell" then table.insert(list, { p = p, cf = p.CFrame, i = p:GetAttribute("I") or 0, j = p:GetAttribute("J") or 0 }) end
			end
			flagCells = list
		end)
		return
	end
	if not flagCells or #flagCells == 0 then return end
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - flagCells[1].cf.Position).Magnitude > 220 then return end
	for _, c in ipairs(flagCells) do
		local k = (c.i + 1) / 8
		local z = math.sin(t * 4.5 - c.i * 0.9 + c.j * 0.2) * 0.32 * k
		local dz = math.cos(t * 4.5 - c.i * 0.9 + c.j * 0.2) * 0.45 * k
		c.p.CFrame = c.cf * CFrame.new(0, -k * k * 0.12, z) * CFrame.Angles(0, dz, 0)
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
		updateFish(dt, t)
		updateFlag(t)
		updateFloats(dt)
		updateTrain(dt)
		updateShoe(t)
		updateMarkers(t)
	end)
end
Effects.float = addFloat

return Effects
