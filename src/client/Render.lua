--[[
	Отрисовка движущихся существ: лошади (дикие, на верёвке, в леваде, на прогулке),
	соперники на скачках, зайчики, олени, привидения, лошади под седлом у всех игроков,
	а также свои лошади в денниках и на рынке (их видит только хозяин — у каждого свои денники).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Horses = require(Shared.Horses)
local Stalls = require(Shared.Stalls)
local Net = require(Shared.Net)
local Genetics = require(Shared.Genetics)

local Client = script.Parent
local HB = require(Client.HorseBuilder)
local State = require(Client.State)

local Render = {}
local K = World.K
local player = Players.LocalPlayer
local folder
local ents = {}         -- [id] = e
local buildQueue = {}
local mounts = {}       -- [Player] = { key, e, phase }
local own = {}          -- [key] = e (свои лошади в денниках и на рынке)

local function serverNow() return workspace:GetServerTimeNow() end

local function addLabel(model, text, h, color)
	if not text or text == "" then return end
	local anchor = model.PrimaryPart
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(220, 24)
	bb.StudsOffset = Vector3.new(0, h or 9, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBold
	t.TextSize = 15
	t.TextColor3 = Util.color(color or "#1c4f8a")
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = Color3.new(1, 1, 1)
	t.Parent = bb
end

-- маленькая надпись с породой над лошадью: видна только вблизи и не мешает
function Render.breedLabel(b, text, s)
	local anchor = b.model.PrimaryPart
	local bb = Instance.new("BillboardGui")
	bb.Name = "Breed"
	bb.Size = UDim2.new(0, 160, 0, 18)
	bb.StudsOffset = Vector3.new(0, 8.6 * (s or 1), 0)
	bb.MaxDistance = 48
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBold
	t.TextSize = 13
	t.TextColor3 = Util.color("#3b2a1a")
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = Color3.new(1, 1, 1)
	t.Parent = bb
end

--[[ ---------- капли дождя и снег на лошадях ---------- ]]
-- в дождь с лошади отскакивают маленькие капли, в тундре на неё падает и ложится снег
local function weatherFx(b)
	if b.wfx or not b.content then return b.wfx end
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Drops"
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.25, 0.5)
	pe.Speed = NumberRange.new(2, 4)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, -30, 0)
	pe.Size = NumberSequence.new(0.09)
	pe.Transparency = NumberSequence.new(0.2, 0.8)
	pe.Color = ColorSequence.new(Util.color("#dbe9f7"))
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	local holder = Instance.new("Attachment")
	holder.Name = "WeatherAtt"
	local V = b.V or 0.45
	holder.Position = Vector3.new(0, 13 * V, 0)
	holder.Parent = b.content
	pe.Parent = holder
	-- снег на спине: тонкий белый слой (виден только в тундре)
	local cap = Instance.new("Part")
	cap.Name = "SnowCap"
	cap.Size = Vector3.new(15 * V, 0.12, 5.2 * V)
	cap.Color = Color3.new(1, 1, 1)
	cap.Material = Enum.Material.Snow
	cap.CanCollide, cap.CanTouch, cap.CanQuery, cap.Massless, cap.Anchored = false, false, false, true, false
	cap.CastShadow = false
	cap.Transparency = 1
	cap.CFrame = b.content.CFrame * CFrame.new(-0.5 * V, 13.06 * V, -0.5 * V)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = b.content, cap
	w.Parent = cap
	cap.Parent = b.model
	b.wfx = { pe = pe, cap = cap, snow = 0 }
	return b.wfx
end
local function updateWeatherFx(b, x, y, dt)
	local fx = weatherFx(b)
	if not fx then return end
	fx.t = (fx.t or 0) - dt
	if fx.t > 0 then return end
	fx.t = 0.5
	local wet = State.world.wet or 0
	local reg = y <= World.H and World.regionAt(x, y) or "sky"
	local dry = reg == "desert" or reg == "cave" or reg == "grottocave" or string.sub(reg, 1, 3) == "sky" or World.inRect(x, y, World.STABLE)
	local tundra = reg == "tundra"
	if tundra then
		fx.pe.Rate = 4 + wet * 10
		fx.pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
		fx.pe.Speed = NumberRange.new(0.3, 0.8)
		fx.pe.Acceleration = Vector3.new(0, -2, 0)
		fx.pe.Lifetime = NumberRange.new(1, 2)
		fx.pe.Size = NumberSequence.new(0.14)
		fx.snow = math.min(1, fx.snow + 0.04)
	else
		fx.pe.Rate = (wet > 0.05 and not dry) and (25 * wet) or 0
		fx.pe.Color = ColorSequence.new(Util.color("#dbe9f7"))
		fx.pe.Speed = NumberRange.new(2, 4)
		fx.pe.Acceleration = Vector3.new(0, -30, 0)
		fx.pe.Lifetime = NumberRange.new(0.25, 0.5)
		fx.pe.Size = NumberSequence.new(0.09)
		fx.snow = math.max(0, fx.snow - 0.02)
	end
	fx.cap.Transparency = 1 - fx.snow * 0.9
end
Render.updateWeatherFx = updateWeatherFx

--[[ ---------- вода: лошадь плывёт ---------- ]]
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { workspace.Terrain }
waterParams.IgnoreWater = false
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { workspace.Terrain }
floorParams.IgnoreWater = true
-- поверхность воды и дно под точкой (в стадах) или nil, если воды нет
function Render.waterAt(pos)
	local from = pos + Vector3.new(0, 6, 0)
	local hit = workspace:Raycast(from, Vector3.new(0, -26, 0), waterParams)
	if not hit or hit.Material ~= Enum.Material.Water then return nil end
	local fl = workspace:Raycast(hit.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, -40, 0), floorParams)
	return hit.Position.Y, fl and fl.Position.Y or (hit.Position.Y - 40)
end

--[[ ---------- простые модели: зайчик, олень, привидение ---------- ]]
local function simplePart(model, size, cf, c, material, transparency)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = Util.color(c)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	if transparency then p.Transparency = transparency end
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = model.PrimaryPart
	w.Part1 = p
	w.Parent = p
	return p
end
local function baseModel(name)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Parent = m
	m.PrimaryPart = root
	return m
end
local function buildBunny(look)
	local m = baseModel("Bunny")
	simplePart(m, Vector3.new(1.1, 0.8, 0.8), CFrame.new(0, 0.45, 0), look.color)
	simplePart(m, Vector3.new(0.6, 0.55, 0.6), CFrame.new(0.6, 0.85, 0), look.color)
	simplePart(m, Vector3.new(0.15, 0.6, 0.15), CFrame.new(0.55, 1.3, -0.15), look.color)
	simplePart(m, Vector3.new(0.15, 0.6, 0.15), CFrame.new(0.55, 1.3, 0.15), look.color)
	simplePart(m, Vector3.new(0.3, 0.3, 0.3), CFrame.new(-0.6, 0.6, 0), look.belly or "#ffffff")
	return { model = m, root = m.PrimaryPart, kind = "bunny" }
end
-- олень как настоящий: округлое тело, длинная шея, голова с ушами и носом, тонкие ноги на суставах,
-- белое «зеркальце» и хвостик, белые пятна на спине (у оленят и пятнистых оленей), рога у самцов.
-- Ноги, шея и хвост — на суставах (Motor6D): олень ходит, бежит прыжками и щиплет траву.
local function deerPart(m, parent, size, cf, c, round)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = Util.color(c)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = m
	if round then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = parent
	w.Part1 = p
	w.Parent = p
	return p
end
local function joint(m, parent, name, at)
	local piv = Instance.new("Part")
	piv.Name = name
	piv.Size = Vector3.new(0.1, 0.1, 0.1)
	piv.Transparency = 1
	piv.CanCollide, piv.CanTouch, piv.CanQuery, piv.Massless, piv.Anchored = false, false, false, true, false
	piv.CFrame = parent.CFrame * CFrame.new(at)
	piv.Parent = m
	local mo = Instance.new("Motor6D")
	mo.Part0 = parent
	mo.Part1 = piv
	mo.C0 = CFrame.new(at)
	mo.Parent = piv
	return piv, mo
end
local function buildDeer(look)
	local m = baseModel("Deer")
	local root = m.PrimaryPart
	local s = look.fawn and 0.65 or 1
	local rnd = Util.rng((look.seed or 1) + 3)
	local body = look.fawn and "#c08552" or (rnd() < 0.5 and "#a0673a" or "#b0743f")
	local light, dark = "#f1e2c6", Util.mix(body, "#000000", 0.25)
	local spotted = look.fawn or rnd() < 0.6
	local torso, torsoM = joint(m, root, "Torso", Vector3.new(0, 3.5 * s, 0))
	local function tp(size, pos, c, round) return deerPart(m, torso, size * s, torso.CFrame * CFrame.new(pos * s), c, round) end
	tp(Vector3.new(3.6, 1.55, 1.35), Vector3.new(0, 0, 0), body, true)
	tp(Vector3.new(1.5, 1.45, 1.3), Vector3.new(1.2, 0.1, 0), body, true)
	tp(Vector3.new(1.6, 1.45, 1.3), Vector3.new(-1.25, 0.05, 0), body, true)
	tp(Vector3.new(2.6, 0.5, 1.0), Vector3.new(0, -0.55, 0), light, true) -- светлое брюхо
	tp(Vector3.new(0.5, 0.9, 0.9), Vector3.new(-1.95, 0.0, 0), "#fbf6ec", true) -- «зеркальце»
	if spotted then
		for i = 1, 14 do
			local x = -1.5 + rnd() * 3.0
			local z = (rnd() < 0.5 and -1 or 1) * (0.25 + rnd() * 0.35)
			tp(Vector3.new(0.22, 0.12, 0.22), Vector3.new(x, 0.72 - math.abs(z) * 0.5, z), "#fbf6ec", true)
		end
	end
	-- шея и голова
	local neck, neckM = joint(m, torso, "Neck", Vector3.new(1.5 * s, 0.4 * s, 0))
	local function np(size, pos, c, round) return deerPart(m, neck, size * s, neck.CFrame * CFrame.new(pos * s), c, round) end
	np(Vector3.new(0.75, 2.0, 0.7), Vector3.new(0.35, 0.9, 0), body, true)
	np(Vector3.new(0.5, 1.4, 0.45), Vector3.new(0.55, 0.8, 0), light, true)
	np(Vector3.new(1.05, 0.7, 0.68), Vector3.new(0.75, 1.95, 0), body, true)
	np(Vector3.new(0.75, 0.48, 0.46), Vector3.new(1.32, 1.8, 0), Util.mix(body, "#ffffff", 0.12), true)
	np(Vector3.new(0.16, 0.18, 0.28), Vector3.new(1.66, 1.82, 0), "#1a1412", true)
	for _, z in ipairs({ -0.33, 0.33 }) do
		np(Vector3.new(0.18, 0.18, 0.06), Vector3.new(0.95, 2.08, z), "#1a1412", true)
		np(Vector3.new(0.06, 0.06, 0.07), Vector3.new(1.0, 2.12, z * 1.05), "#ffffff")
		np(Vector3.new(0.16, 0.6, 0.34), Vector3.new(0.55, 2.45, z * 1.5), body, true)
		np(Vector3.new(0.1, 0.4, 0.22), Vector3.new(0.57, 2.45, z * 1.52), "#e8c9a0", true)
	end
	if look.buck then
		for _, z in ipairs({ -1, 1 }) do
			local base = Vector3.new(0.7, 2.35, z * 0.25)
			np(Vector3.new(0.14, 1.3, 0.14), base + Vector3.new(-0.1, 0.6, z * 0.15), "#d9c6a5")
			np(Vector3.new(0.12, 0.7, 0.12), base + Vector3.new(0.15, 0.9, z * 0.25), "#d9c6a5")
			np(Vector3.new(0.11, 0.8, 0.11), base + Vector3.new(-0.35, 1.25, z * 0.35), "#d9c6a5")
			np(Vector3.new(0.1, 0.6, 0.1), base + Vector3.new(0.05, 1.45, z * 0.4), "#d9c6a5")
		end
	end
	-- хвост
	local tail, tailM = joint(m, torso, "Tail", Vector3.new(-2.05 * s, 0.35 * s, 0))
	deerPart(m, tail, Vector3.new(0.35, 0.6, 0.3) * s, tail.CFrame * CFrame.new(-0.12 * s, 0.1 * s, 0), body, true)
	-- ноги: бедро (на суставе) и голень с копытцем (на втором суставе)
	local legs = {}
	for i, q in ipairs({ { 1.3, -0.42 }, { 1.3, 0.42 }, { -1.35, -0.42 }, { -1.35, 0.42 } }) do
		local front = i <= 2
		local hip, hipM = joint(m, torso, "Leg" .. i, Vector3.new(q[1] * s, -0.25 * s, q[2] * s))
		deerPart(m, hip, Vector3.new(front and 0.42 or 0.6, 1.6, 0.36) * s, hip.CFrame * CFrame.new(0, -0.7 * s, 0), body, true)
		local knee, kneeM = joint(m, hip, "Knee" .. i, Vector3.new(0, -1.4 * s, 0))
		deerPart(m, knee, Vector3.new(0.2, 1.75, 0.2) * s, knee.CFrame * CFrame.new(0, -0.85 * s, 0), Util.mix(body, "#ffffff", 0.1))
		deerPart(m, knee, Vector3.new(0.26, 0.26, 0.24) * s, knee.CFrame * CFrame.new(0.02 * s, -1.75 * s, 0), "#2b2420")
		legs[i] = { m = hipM, k = kneeM, front = front, pos = Vector3.new(q[1] * s, -0.25 * s, q[2] * s) }
	end
	return { model = m, root = root, kind = "deer", torsoM = torsoM, neckM = neckM, tailM = tailM, legs = legs, s = s, phase = rnd() * 6, dark = dark }
end
-- поза оленя: шаг, рысь или галоп прыжками (передние и задние ноги парами), голова вниз, когда щиплет траву
local function poseDeer(b, e, pos, dt, t)
	local s = b.s
	local spd = e.spd or 0
	local run = spd > 150
	local moving = spd > 8
	local freq = run and 2.3 or (moving and math.clamp(spd / 70, 0.6, 1.8) or 0)
	b.phase = (b.phase + dt * freq) % 1
	local u = b.phase
	local up, pitch = 0, 0
	local graze = e.act and e.act.k == "graze" and not moving
	for i, l in ipairs(b.legs) do
		local r, k = 0, 0
		if run then
			-- прыжок: передние вместе, задние вместе, между толчками олень в воздухе
			local off = l.front and 0.5 or 0
			local v = math.sin((u + off + (i % 2) * 0.05) * math.pi * 2)
			r = v * (l.front and 0.75 or 0.85)
			k = (l.front and -1 or 1) * math.max(0, -v) * 0.9
		elseif moving then
			local off = ({ 0.25, 0.75, 0, 0.5 })[i]
			local v = math.sin((u + off) * math.pi * 2)
			r = v * 0.38
			k = (l.front and -1 or 1) * math.max(0, v) * 0.6
		end
		l.m.C0 = CFrame.new(l.pos) * CFrame.Angles(0, 0, r)
		l.k.C0 = CFrame.new(0, -1.4 * s, 0) * CFrame.Angles(0, 0, k)
	end
	if run then
		up = math.max(0, math.sin(u * math.pi * 2)) * 1.1 * s
		pitch = math.cos(u * math.pi * 2) * 0.12
	elseif moving then
		up = math.abs(math.sin(u * math.pi * 4)) * 0.08 * s
	end
	b.headA = b.headA or 0
	local wantHead = graze and -1.25 or (run and -0.25 or 0) + math.sin(t * 0.7 + (e.id or 0)) * 0.08
	b.headA += (wantHead - b.headA) * math.min(1, dt * 4)
	b.neckM.C0 = CFrame.new(1.5 * s, 0.4 * s, 0) * CFrame.Angles(0, graze and math.sin(t * 0.5) * 0.2 or 0, b.headA)
	b.tailM.C0 = CFrame.new(-2.05 * s, 0.35 * s, 0) * CFrame.Angles(0, math.sin(t * 6) * 0.25, run and 0.9 or 0.2 + math.sin(t * 2.3) * 0.1)
	b.torsoM.C0 = CFrame.new(0, 3.5 * s + up, 0) * CFrame.Angles(0, 0, pitch)
	b.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, -e.angle, 0)
end
local function buildGhost(look)
	if look.kind == "horse" then
		local e = HB.build({ id = 0, breed = "skeleton", sex = "f", g = { E = { true, true }, A = { true, true }, Cr = { false, false }, D = { false, false }, G = { false, false }, TO = { false, false }, LP = { false, false }, Rn = { false, false }, Z = { false, false }, F = { true, true } },
			marks = { face = 0, legs = { false, false, false, false } }, magic = nil, seed = look.seed or 1, size = 1, age = 6, maneStyle = "normal" })
		for _, d in ipairs(e.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.Material = Enum.Material.ForceField
				d.Color = Util.color("#dbe4ff")
				d.Transparency = 0.2
			end
		end
		e.kind = "ghost"
		return e
	end
	local m = baseModel("Ghost")
	simplePart(m, Vector3.new(2.2, 3.4, 2.2), CFrame.new(0, 3.4, 0), "#f1f3f5", Enum.Material.ForceField, 0.1)
	simplePart(m, Vector3.new(1.8, 1.6, 1.8), CFrame.new(0, 5.6, 0), "#f8f9fa", Enum.Material.ForceField, 0.1)
	simplePart(m, Vector3.new(0.3, 0.4, 0.2), CFrame.new(0.9, 5.8, -0.4), "#111111")
	simplePart(m, Vector3.new(0.3, 0.4, 0.2), CFrame.new(0.9, 5.8, 0.4), "#111111")
	local l = Instance.new("PointLight")
	l.Color = Util.color("#bac8ff")
	l.Range = 12
	l.Parent = m.PrimaryPart
	return { model = m, root = m.PrimaryPart, kind = "ghost" }
end

--[[ ---------- сущности от сервера ---------- ]]
local ACT_NAMES = Items.ACT_CODES

local function buildEntity(e)
	local d = e.data
	local built
	if d.kind == "horse" then
		built = HB.build(d.look)
	elseif d.kind == "rider" then
		built = HB.build(d.look.horse, { tack = d.look.rider })
		HB.addRider(built, d.look.rider)
	elseif d.kind == "bunny" then
		built = buildBunny(d.look)
	elseif d.kind == "deer" then
		built = buildDeer(d.look)
	elseif d.kind == "ghost" then
		built = buildGhost(d.look)
	end
	if not built then return end
	if e.built then e.built.model:Destroy() end
	e.built = built
	-- лошадь на верёвке: петля на шее и тонкая верёвка до руки игрока
	if d.kind == "horse" and d.leadBy then
		local ok, att = pcall(HB.addCollar, built)
		if ok and att then
			att.Axis = Vector3.new(0, -1, 0)
			local beam = Instance.new("Beam")
			beam.Attachment0 = att
			beam.Width0, beam.Width1 = 0.09, 0.09
			beam.FaceCamera = true
			beam.Segments = 12
			beam.CurveSize0 = 1.4
			beam.Color = ColorSequence.new(Util.color("#c9a66b"))
			beam.LightInfluence = 1
			beam.Transparency = NumberSequence.new(0)
			beam.Enabled = false
			beam.Parent = built.model
			built.rope = beam
			built.leadBy = d.leadBy
		end
	end
	built.model:SetAttribute("EntityId", e.id)
	built.model:SetAttribute("EntityKind", d.kind)
	addLabel(built.model, d.label, d.kind == "rider" and 13 or 8.5, d.kind == "rider" and "#5f3dc4" or "#1c4f8a")
	-- над дикой лошадью видно, какой она породы (вблизи), — не нужно открывать карточку
	if d.kind == "horse" and not d.label and d.look and d.look.breed then
		local B = Genetics.BREEDS[d.look.breed]
		if B then Render.breedLabel(built, B.name, (d.look.size or 1) * (d.look.age and d.look.age < 3 and 0.75 or 1)) end
	end
	built.model.Parent = folder
end

local function onSpawn(list)
	for _, d in ipairs(list) do
		local e = ents[d.id]
		if not e then
			e = { id = d.id, data = d, pos = nil, angle = 0, spd = 0, phase = math.random() * 6, fly = 0, z = 0 }
			ents[d.id] = e
		else
			e.data = d
		end
		table.insert(buildQueue, e)
	end
end
local function onDespawn(ids)
	for _, id in ipairs(ids) do
		local e = ents[id]
		if e then
			if e.built then e.built.model:Destroy() end
			e.dead = true
			ents[id] = nil
		end
	end
end
local function onState(list)
	for _, s in ipairs(list) do
		local e = ents[s[1]]
		if e then
			e.tx, e.ty, e.ta, e.tspd, e.tfly = s[2], s[3], s[4], s[5], s[6]
			local code = s[7]
			if code > 0 then
				e.act = { k = ACT_NAMES[code], start = s[8], d = s[9], leg = s[10] }
			else
				e.act = nil
			end
			e.tz = s[11]
			if not e.pos then
				e.px, e.py, e.angle, e.fly, e.z = e.tx, e.ty, e.ta, e.tfly, e.tz
				e.pos = true
			end
		end
	end
end

--[[ ---------- рельеф под ногами ---------- ]]
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }
rayParams.IgnoreWater = true
-- настоящая поверхность Terrain под точкой карты (карта высот даёт её с точностью до вокселя)
function Render.surfaceY(x, y, guess)
	if y > World.H then return guess end
	local hit = workspace:Raycast(Vector3.new(x * K, guess + 5, y * K), Vector3.new(0, -12, 0), rayParams)
	if hit then return hit.Position.Y end
	return guess
end
-- наклон корпуса по склону вдоль направления движения (нос вверх на подъёме)
function Render.slopeLerp(cur, x, y, angle, dt, fly)
	local want = 0
	if (fly or 0) < 0.5 and y <= World.H then
		local ca, sa = math.cos(angle), math.sin(angle)
		local h1 = World.heightAt(x + ca * 45, y + sa * 45)
		local h0 = World.heightAt(x - ca * 45, y - sa * 45)
		want = math.clamp(math.atan2(h1 - h0, 9), -0.45, 0.45)
	end
	cur = cur or want
	return cur + (want - cur) * math.min(1, dt * 6)
end

--[[ ---------- лошади под седлом у игроков ---------- ]]
-- слезла с лошади — вернуть сустав корпуса на место
local function resetRiderJoint(char)
	if not char then return end
	for _, name in ipairs({ "Root", "RootJoint" }) do
		local j = char:FindFirstChild(name, true)
		if j and j:IsA("Motor6D") then
			local b = j:GetAttribute("BaseC0")
			if typeof(b) == "CFrame" then j.C0 = b end
		end
	end
end
local function updateMount(pl, dt, t)
	local char = pl.Character
	local rec = mounts[pl]
	local v = char and char:FindFirstChild("Mount")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not v or v.Value == "" or not hrp or not hum then
		if rec then
			rec.e.model:Destroy()
			mounts[pl] = nil
			resetRiderJoint(char)
		end
		return
	end
	if not rec or rec.json ~= v.Value then
		local ok, data = pcall(function() return HttpService:JSONDecode(v.Value) end)
		if not ok then return end
		if rec then rec.e.model:Destroy() end
		local e = HB.build(data.look, { tack = data.tack })
		e.model.Name = "Mount"
		e.model.Parent = folder
		rec = { json = v.Value, e = e, phase = 0 }
		mounts[pl] = rec
	end
	local hip = hum.HipHeight + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0)
	local ground = hrp.Position - Vector3.new(0, hrp.Size.Y / 2 + hip, 0)
	local lv = hrp.CFrame.LookVector
	local vel = hrp.AssemblyLinearVelocity
	-- скорость по физике дёргается от кадра к кадру — сглаживаем, иначе лошадь трясёт головой
	rec.spd = (rec.spd or 0) + (Vector3.new(vel.X, 0, vel.Z).Magnitude / K - (rec.spd or 0)) * math.min(1, dt * 5)
	local spd = rec.spd
	rec.phase += dt * (3 + spd * 0.045) * (spd > 4 and 1 or 0)
	local act = nil
	local a = char:GetAttribute("MountAct")
	if type(a) == "string" and a ~= "" then
		local k, start, d, leg = string.match(a, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
		if k then
			local tt = serverNow() - tonumber(start)
			if tt < tonumber(d) then act = { k = k, t = tt, d = tonumber(d), leg = tonumber(leg) } end
		end
	end
	local flying = char:GetAttribute("Flying") == true
	local lift = 0
	if pl == player then lift = Render.riderLift or 0 end
	local mx, my = World.fromStuds(hrp.Position)
	local ang = math.atan2(lv.Z, lv.X)
	-- плывёт? (глубокая вода под лошадью) — тогда лошадь гребёт ногами, а всадник сидит в седле
	rec.wT = (rec.wT or 0) - dt
	if rec.wT <= 0 then
		rec.wT = 0.2
		local wy, fy = nil, nil
		if not flying then wy, fy = Render.waterAt(hrp.Position) end
		rec.swim = wy ~= nil and (wy - fy) > 13 * rec.e.V - 1.2 and hrp.Position.Y < wy + 14 * rec.e.V
		rec.waterY = wy
	end
	local swim = rec.swim and not flying
	-- в прыжке (не в полёте и не в воде) лошадь поджимает ноги
	local air = not flying and not swim and hum.FloorMaterial == Enum.Material.Air and math.abs(vel.Y) > 2
	rec.air = (rec.air or 0) + ((air and 1 or 0) - (rec.air or 0)) * math.min(1, dt * 10)
	if rec.air > 0.05 then lift = math.max(lift, 0.55 * rec.air) end
	rec.slope = Render.slopeLerp(rec.slope, mx, my, ang, dt, (flying or swim) and 1 or 0)
	local gait = char:GetAttribute("Gait")
	local basePos = ground - Vector3.new(0, lift * 2.6 * rec.e.s, 0)
	HB.pose(rec.e, { pos = basePos, angle = ang, spd = spd, phase = rec.phase, fly = flying and 1 or 0, flyH = 0,
		lift = lift, act = act, t = t, slope = rec.slope, gait = type(gait) == "number" and gait or nil, swim = swim and 1 or 0 })
	updateWeatherFx(rec.e, mx, my, dt)
	-- всадник двигается вместе с лошадью: на дыбах, в прыжке, на рыси (подпрыгивает), на склоне.
	-- Сдвиг седла относительно спокойной позы переносим на сустав корпуса персонажа.
	local joint = rec.joint
	if not joint or joint.Parent == nil then
		joint = nil
		local lt = char:FindFirstChild("LowerTorso")
		if lt then joint = lt:FindFirstChild("Root") end
		if not joint and hrp then joint = hrp:FindFirstChild("RootJoint") end
		if joint and joint:IsA("Motor6D") then
			rec.joint = joint
			rec.jointC0 = joint:GetAttribute("BaseC0") or joint.C0
			if not joint:GetAttribute("BaseC0") then joint:SetAttribute("BaseC0", joint.C0) end
		else
			joint = nil
		end
	end
	if joint then
		local e = rec.e
		local seat = CFrame.new(-1.2 * e.V, 13.6 * e.V, 0)
		local rest = CFrame.new(ground) * CFrame.Angles(0, -ang, 0) * seat
		local now = e.root.CFrame * e.contentM.C0 * seat
		local D = now * rest:Inverse()
		local hcf = hrp.CFrame
		joint.C0 = (hcf:Inverse() * D * hcf) * rec.jointC0
	end
end

--[[ ---------- свои лошади в денниках и на рынке ---------- ]]
local function syncOwn(P)
	if not P then return end
	local want = {}
	for _, h in ipairs(P.horses) do
		if h.state == "stall" or h.state == "market" then want["h" .. h.id] = h end
	end
	if type(P.market) == "table" then
		for i, h in ipairs(P.market.stock or {}) do
			h._stock = i
			want["s" .. h.id] = h
		end
	end
	for key, e in pairs(own) do
		local h = want[key]
		if not h or e.lookKey ~= Horses.lookKey(h) .. (h.maneDye or "") .. h.maneStyle then
			e.built.model:Destroy()
			own[key] = nil
		end
	end
	for key, h in pairs(want) do
		local e = own[key]
		if not e then
			local built = HB.build(Horses.look(h))
			built.model.Parent = folder
			e = { built = built, lookKey = Horses.lookKey(h) .. (h.maneDye or "") .. h.maneStyle }
			own[key] = e
			if h.state == "market" then addLabel(built.model, h.name .. " · " .. tostring(h.ask) .. " 💰", 8, "#b35c00")
			elseif h.state == "shop" then addLabel(built.model, h.name .. " · " .. tostring(h.ask) .. " 💰", 8, "#c92a2a")
			else addLabel(built.model, h.name, 7, "#3b2a1a") end
		end
		e.h = h
	end
end

local function poseOwn(t, P)
	for key, e in pairs(own) do
		local h = e.h
		local sp
		if h.state == "market" then sp = Stalls.marketSpot(P, h)
		elseif h.state == "shop" then sp = Stalls.stockSpot(h._stock or 1)
		else sp = Stalls.spot(P, h.stall) end
		local act = nil
		if h.act and h.act._recv then
			local tt = h.act.t + (os.clock() - h.act._recv)
			if tt < h.act.d then act = { k = h.act.k, t = tt, d = h.act.d, leg = h.act.leg } end
		end
		HB.pose(e.built, { pos = World.toStuds(sp.x, sp.y, World.groundY(sp.x, sp.y)), angle = sp.angle, spd = 0, phase = 0, act = act, t = t,
			headTurn = math.sin(t * 0.5 + (h.seed % 100)) * 0.35 })
	end
end

--[[ ---------- кадр ---------- ]]
local t0 = os.clock()
function Render.update(dt)
	local t = os.clock() - t0
	-- построить новые модели (не больше двух за кадр)
	for _ = 1, 2 do
		local e = table.remove(buildQueue, 1)
		if not e then break end
		if not e.dead then buildEntity(e) end
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, e in pairs(ents) do
		local b = e.built
		if b and e.pos then
			local k = math.min(1, dt * 8)
			e.px += (e.tx - e.px) * k
			e.py += (e.ty - e.py) * k
			e.angle = Util.lerpAngle(e.angle, e.ta, k)
			e.spd += ((e.tspd or 0) - e.spd) * math.min(1, dt * 4)
			e.fly += ((e.tfly or 0) - e.fly) * k
			e.z += ((e.tz or 0) - e.z) * math.min(1, dt * 15)
			e.phase += dt * (3 + e.spd * 0.045) * (e.spd > 4 and 1 or 0)
			local gy = World.groundY(e.px, e.py)
			local far = (Vector3.new(e.px * K, gy, e.py * K) - camPos).Magnitude > 260
			if not far then gy = Render.surfaceY(e.px, e.py, gy) end
			e.gy = e.gy and (e.gy + (gy - e.gy) * math.min(1, dt * 12)) or gy
			gy = e.gy
			local pos = Vector3.new(e.px * K, gy + e.z * K, e.py * K)
			-- лошади в маленьких пещерках видны только тем, кто сам у пещерки (иначе светятся издалека)
			e.gT = (e.gT or 0) - dt
			if e.gT <= 0 then
				e.gT = 0.5 + math.random() * 0.3
				e.grotto = e.py <= World.H and World.inGrotto(e.px, e.py, -20) or nil
			end
			local hidden = false
			if e.grotto then
				local g = e.grotto
				hidden = Util.hypot(camPos.X / K - g.x, camPos.Z / K - g.y) > g.r + 160
			end
			if e.data.kind == "ghost" then
				hidden = hidden or (e.tz or 0) < 0
				pos = Vector3.new(e.px * K, gy + math.sin(t * 2 + e.id) * 0.5 + 0.6, e.py * K)
			end
			local wantParent = (not hidden) and folder or nil
			if b.model.Parent ~= wantParent then b.model.Parent = wantParent end
			if b.kind == "deer" then
				if not hidden and (not far or (math.floor(t * 10) % 2 == 0)) then poseDeer(b, e, pos, dt, t) end
			elseif b.kind == "bunny" or (b.kind == "ghost" and not b.legs) then
				local hop = 0
				local headDown = (e.act and e.act.k == "graze") and -0.25 or 0
				b.root.CFrame = CFrame.new(pos + Vector3.new(0, hop, 0)) * CFrame.Angles(0, -e.angle, headDown)
			elseif not hidden and (not far or (math.floor(t * 10) % 2 == 0)) then
				local act = nil
				if e.act then
					local tt = serverNow() - e.act.start
					if tt < e.act.d then act = { k = e.act.k, t = tt, d = e.act.d, leg = e.act.leg } end
				end
				e.slope = Render.slopeLerp(e.slope, e.px, e.py, e.angle, dt, e.fly)
				HB.pose(b, { pos = pos, angle = e.angle, spd = e.spd, phase = e.phase, fly = e.fly, flyH = 9, act = act, t = t, slope = e.slope })
				if not far and e.data.kind ~= "ghost" then updateWeatherFx(b, e.px, e.py, dt) end
			end
		end
	end
	-- верёвки от руки игрока к лошади
	for _, e in pairs(ents) do
		local b = e.built
		if b and b.rope then
			local pl = Players:GetPlayerByUserId(b.leadBy)
			local ch = pl and pl.Character
			local hand = ch and (ch:FindFirstChild("RightGripAttachment", true) or ch:FindFirstChild("RootAttachment", true))
			if hand ~= b.rope.Attachment1 then b.rope.Attachment1 = hand end
			b.rope.Enabled = hand ~= nil
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do updateMount(pl, dt, t) end
	for pl, rec in pairs(mounts) do
		if not pl.Parent then
			rec.e.model:Destroy()
			mounts[pl] = nil
		end
	end
	if State.P then poseOwn(t, State.P) end
end

-- сущность по детали (клик мышкой по дикой лошади)
function Render.entityOf(part)
	local m = part
	while m and m ~= folder do
		if m:IsA("Model") and m:GetAttribute("EntityId") then return m:GetAttribute("EntityId"), m:GetAttribute("EntityKind") end
		m = m.Parent
	end
	return nil
end
function Render.entityPos(id)
	local e = ents[id]
	if e and e.pos then return e.px, e.py end
	return nil
end
function Render.folder() return folder end
-- лошадь под седлом у игрока (для плавания в Controls)
function Render.mountRec(pl) return mounts[pl] end

function Render.init()
	folder = Instance.new("Folder")
	folder.Name = "Creatures"
	folder.Parent = workspace
	Net.get("EntitySpawn").OnClientEvent:Connect(onSpawn)
	Net.get("EntityDespawn").OnClientEvent:Connect(onDespawn)
	Net.get("EntityState").OnClientEvent:Connect(onState)
	Net.get("EntityLook").OnClientEvent:Connect(onSpawn)
	State.on("profile", syncOwn)
	RunService.RenderStepped:Connect(function(dt) Render.update(math.min(dt, 0.1)) end)
end

return Render
