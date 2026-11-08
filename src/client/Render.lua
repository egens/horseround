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
local function buildDeer(look)
	local m = baseModel("Deer")
	local s = look.fawn and 0.65 or 1
	local body, light = look.fawn and "#c08552" or "#a0673a", "#e8d2b0"
	local function sp(size, pos, c) simplePart(m, size * s, CFrame.new(pos * s), c) end
	sp(Vector3.new(3.4, 1.5, 1.4), Vector3.new(0, 3.4, 0), body)
	sp(Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.7, 4.4, 0), body)
	sp(Vector3.new(1.3, 0.8, 0.8), Vector3.new(2.2, 5.3, 0), body)
	sp(Vector3.new(0.6, 0.4, 0.6), Vector3.new(0.0, 2.9, 0), light)
	for _, x in ipairs({ -1.3, 1.3 }) do
		for _, z in ipairs({ -0.45, 0.45 }) do sp(Vector3.new(0.35, 2.7, 0.35), Vector3.new(x, 1.35, z), "#6b4423") end
	end
	if look.buck then
		for _, z in ipairs({ -0.35, 0.35 }) do
			sp(Vector3.new(0.18, 1.4, 0.18), Vector3.new(2.0, 6.3, z), "#d9c6a5")
			sp(Vector3.new(0.6, 0.18, 0.18), Vector3.new(2.2, 6.6, z), "#d9c6a5")
		end
	end
	if look.fawn then
		for i = 1, 4 do sp(Vector3.new(0.25, 0.1, 0.25), Vector3.new(-1 + i * 0.5, 4.16, (i % 2) * 0.4 - 0.2), "#ffffff") end
	end
	return { model = m, root = m.PrimaryPart, kind = "deer" }
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
	built.model:SetAttribute("EntityId", e.id)
	built.model:SetAttribute("EntityKind", d.kind)
	addLabel(built.model, d.label, d.kind == "rider" and 13 or 8.5, d.kind == "rider" and "#5f3dc4" or "#1c4f8a")
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

--[[ ---------- лошади под седлом у игроков ---------- ]]
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
	local spd = Vector3.new(vel.X, 0, vel.Z).Magnitude / K
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
	HB.pose(rec.e, { pos = ground - Vector3.new(0, lift * 2.6 * rec.e.s, 0), angle = math.atan2(lv.Z, lv.X), spd = spd, phase = rec.phase, fly = flying and 1 or 0, flyH = 0,
		lift = lift, act = act, t = t })
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
			e.spd = e.tspd
			e.fly += ((e.tfly or 0) - e.fly) * k
			e.z += ((e.tz or 0) - e.z) * math.min(1, dt * 15)
			e.phase += dt * (3 + e.spd * 0.045) * (e.spd > 4 and 1 or 0)
			local gy = World.groundY(e.px, e.py)
			local pos = Vector3.new(e.px * K, gy + e.z * K, e.py * K)
			local far = (pos - camPos).Magnitude > 260
			if e.data.kind == "ghost" then
				local hidden = (e.tz or 0) < 0
				local want = folder
				if hidden then want = nil end
				if b.model.Parent ~= want then b.model.Parent = want end
				pos = Vector3.new(e.px * K, gy + math.sin(t * 2 + e.id) * 0.5 + 0.6, e.py * K)
			end
			if b.kind == "bunny" or b.kind == "deer" or (b.kind == "ghost" and not b.legs) then
				local hop = 0
				if b.kind == "deer" then hop = math.abs(math.sin(e.phase)) * 0.4 * math.min(1, e.spd / 120) end
				local headDown = (e.act and e.act.k == "graze") and -0.25 or 0
				b.root.CFrame = CFrame.new(pos + Vector3.new(0, hop, 0)) * CFrame.Angles(0, -e.angle, headDown)
			elseif not far or (math.floor(t * 10) % 2 == 0) then
				local act = nil
				if e.act then
					local tt = serverNow() - e.act.start
					if tt < e.act.d then act = { k = e.act.k, t = tt, d = e.act.d, leg = e.act.leg } end
				end
				HB.pose(b, { pos = pos, angle = e.angle, spd = e.spd, phase = e.phase, fly = e.fly, flyH = 9, act = act, t = t })
			end
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
