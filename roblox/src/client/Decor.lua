--[[
	Декорации мира на клиенте: деревья, грибы, камни, кактусы, кости, цветы, кристаллы, лианы
	(списки детерминированно строит World — как в JS-версии). Рисуются кусками (чанками) вокруг камеры.
	А также жители (NPC), сундук графа и постройки всех игроков.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Stalls = require(Shared.Stalls)
local Q = require(Shared.QuestData)

local Client = script.Parent
local HB = require(Client.HorseBuilder)
local State = require(Client.State)

local Decor = {}
local K = World.K
local CHUNK = 64          -- стадов
local RADIUS = 250        -- стадов
local color = Util.color
local M = Enum.Material
local folder, chunkFolder, buildFolder
local chunks = {}         -- [key] = { items = {}, model = nil }
local queue = {}
local shroomParts = {}    -- [id] = part

local function P(model, size, cf, c, material, collide, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color(c)
	p.Material = material or M.SmoothPlastic
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if transparency then p.Transparency = transparency end
	if material == M.Neon then p.CastShadow = false end
	p.Parent = model
	return p
end
Decor.P = P

local function cyl(model, h, d, cf, c, material, collide)
	local p = P(model, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), c, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function ball(model, d, cf, c, material, collide)
	local p = P(model, Vector3.new(d, d, d), cf, c, material, collide)
	p.Shape = Enum.PartType.Ball
	return p
end

--[[ ---------- деревья и прочее по виду ---------- ]]
local function makeTree(m, t)
	local rnd = Util.rng(t.s or 1)
	local x, z = t.x * K, t.y * K
	local gy = t.sky and World.SKY_Y or 0
	local base = CFrame.new(x, gy, z)
	local r = (t.r or 30) * K
	local k = t.kind
	local dark = t.dark
	if k == "oak" or k == "birch" or k == "vinetree" then
		local th = r * 1.6 + rnd() * 2
		local trunk = k == "birch" and "#efe9de" or "#6b4423"
		P(m, Vector3.new(0.9, th, 0.9), base * CFrame.new(0, th / 2, 0), trunk, M.Wood, true)
		if k == "birch" then
			for i = 1, 3 do P(m, Vector3.new(0.95, 0.25, 0.95), base * CFrame.new(0, th * i / 4, 0), "#2b2b2b") end
		end
		local leaf = k == "birch" and "#8cc152" or (dark and "#2f6b2f" or "#4f8f3a")
		local cr = r * 1.2
		P(m, Vector3.new(cr * 1.6, cr * 1.1, cr * 1.6), base * CFrame.new(0, th + cr * 0.3, 0) * CFrame.Angles(0, rnd() * 3, 0), leaf, M.Grass)
		P(m, Vector3.new(cr * 1.1, cr * 0.9, cr * 1.1), base * CFrame.new((rnd() - 0.5) * cr, th + cr * 0.9, (rnd() - 0.5) * cr), Util.mix(leaf, "#ffffff", 0.08), M.Grass)
		if k == "vinetree" then
			for i = 1, 5 do
				local a = i / 5 * math.pi * 2
				P(m, Vector3.new(0.2, th * 0.8, 0.2), base * CFrame.new(math.cos(a) * cr * 0.7, th * 0.6, math.sin(a) * cr * 0.7), "#2f9e44", M.Grass)
			end
		end
	elseif k == "pine" or k == "spruce" or k == "snowspruce" then
		local th = r * 0.6
		P(m, Vector3.new(0.8, th + 1, 0.8), base * CFrame.new(0, th / 2, 0), "#5c3d1e", M.Wood, true)
		local leaf = k == "pine" and (dark and "#244d24" or "#2f6b2f") or (k == "snowspruce" and "#2d5a3d" or (dark and "#1e3d2c" or "#2b5d4a"))
		local w = r * 1.7
		for i = 0, 3 do
			local s = w * (1 - i * 0.22)
			local y = th + i * r * 0.55
			P(m, Vector3.new(s, r * 0.6, s), base * CFrame.new(0, y, 0) * CFrame.Angles(0, i * 0.4, 0), leaf, M.Grass)
			if k == "snowspruce" then P(m, Vector3.new(s * 0.9, 0.3, s * 0.9), base * CFrame.new(0, y + r * 0.31, 0) * CFrame.Angles(0, i * 0.4, 0), "#ffffff", M.Snow) end
		end
	elseif k == "amanita" or k == "boletus" or k == "glowshroom" then
		local sh = r * 1.2
		local stem = k == "boletus" and "#e8d9b5" or "#f8f4ea"
		cyl(m, sh, r * 0.5, base * CFrame.new(0, sh / 2, 0), stem, M.SmoothPlastic, true)
		local capC = k == "amanita" and "#e03131" or k == "boletus" and "#8b5a2b" or (rnd() < 0.5 and "#7df9ff" or "#c77dff")
		local cap = P(m, Vector3.new(r * 2, r * 0.7, r * 2), base * CFrame.new(0, sh + r * 0.3, 0), capC, k == "glowshroom" and M.Neon or M.SmoothPlastic)
		cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(r * 0.7, r * 2, r * 2)
		cap.CFrame = base * CFrame.new(0, sh + r * 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
		if k == "amanita" then
			for _ = 1, 6 do
				local a, d = rnd() * 6.28, rnd() * r * 0.8
				P(m, Vector3.new(0.6, 0.3, 0.6), base * CFrame.new(math.cos(a) * d, sh + r * 0.66, math.sin(a) * d), "#ffffff")
			end
		end
		if k == "glowshroom" and rnd() < 0.5 then
			local l = Instance.new("PointLight")
			l.Color = cap.Color
			l.Range = 14
			l.Brightness = 1
			l.Parent = cap
		end
	elseif k == "cliff" or k == "rock" or k == "snowrock" or k == "basalt" or k == "cavewall" then
		local h = k == "cliff" and r * 1.4 or k == "cavewall" and 9 + rnd() * 3 or r * (0.7 + rnd() * 0.5)
		local c = k == "basalt" and "#2b2626" or k == "cavewall" and "#5a5550" or (k == "cliff" and "#8a8580" or "#9a958f")
		P(m, Vector3.new(r * 1.7, h, r * 1.5), base * CFrame.new(0, h / 2 - 0.3, 0) * CFrame.Angles(0, rnd() * 3, 0), c, M.Rock, true)
		P(m, Vector3.new(r * 1.1, h * 0.5, r * 1.1), base * CFrame.new((rnd() - 0.5) * r, h * 0.85, (rnd() - 0.5) * r) * CFrame.Angles(0, rnd() * 3, 0), Util.mix(c, "#ffffff", 0.08), M.Rock, true)
		if k == "snowrock" then P(m, Vector3.new(r * 1.6, 0.5, r * 1.4), base * CFrame.new(0, h + 0.1, 0), "#ffffff", M.Snow) end
	elseif k == "palm" then
		local th = r * 2.2
		local tilt = CFrame.Angles((rnd() - 0.5) * 0.3, 0, (rnd() - 0.5) * 0.3)
		P(m, Vector3.new(0.8, th, 0.8), base * tilt * CFrame.new(0, th / 2, 0), "#a0764a", M.Wood, true)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			P(m, Vector3.new(r * 1.2, 0.25, 0.9), base * tilt * CFrame.new(0, th, 0) * CFrame.Angles(0, a, -0.35) * CFrame.new(r * 0.6, 0, 0), "#3a9d23", M.Grass)
		end
	elseif k == "cactus" then
		local h = r * 0.35 + 3
		P(m, Vector3.new(1, h, 1), base * CFrame.new(0, h / 2, 0), "#3a7d44", M.Grass, true)
		for _, s in ipairs({ -1, 1 }) do
			if rnd() < 0.7 then
				P(m, Vector3.new(1.2, 0.6, 0.6), base * CFrame.new(s * 0.9, h * 0.5, 0), "#3a7d44", M.Grass)
				P(m, Vector3.new(0.6, 1.6, 0.6), base * CFrame.new(s * 1.3, h * 0.5 + 0.8, 0), "#3a7d44", M.Grass)
			end
		end
	elseif k == "mesa" then
		local h = 4 + r * 0.25
		P(m, Vector3.new(r * 1.8, h, r * 1.6), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, rnd() * 3, 0), "#b5502e", M.Sandstone, true)
		P(m, Vector3.new(r * 1.4, 1.2, r * 1.2), base * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(0, rnd() * 3, 0), "#c86a3e", M.Sandstone, true)
	elseif k == "drybush" or k == "bush" then
		local c = k == "drybush" and "#8d6e3f" or "#3f7f35"
		ball(m, r * 0.9, base * CFrame.new(0, r * 0.35, 0), c, M.Grass, false)
	elseif k == "hill" then
		local h = 2 + r * 0.05
		local hp = P(m, Vector3.new(h * 2, r * 1.8, r * 1.8), base * CFrame.new(0, -h * 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), "#79a84a", M.Grass, true)
		hp.Shape = Enum.PartType.Cylinder
	elseif k == "spire" then
		local h = r * 1.6
		P(m, Vector3.new(r * 0.9, h, r * 0.9), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, rnd() * 3, 0), "#2b2626", M.Basalt, true)
		P(m, Vector3.new(r * 0.5, h * 0.4, r * 0.5), base * CFrame.new(0, h * 1.15, 0), "#2b2626", M.Basalt, true)
		P(m, Vector3.new(0.3, h * 0.7, 0.3), base * CFrame.new(r * 0.46, h * 0.45, 0), "#ff6a00", M.Neon)
	elseif k == "deadtree" then
		local th = r * 1.2 + 2
		P(m, Vector3.new(0.8, th, 0.8), base * CFrame.new(0, th / 2, 0), "#4a4440", M.Wood, true)
		for i = 1, 3 do
			P(m, Vector3.new(0.35, r * 0.8, 0.35), base * CFrame.new(0, th * (0.5 + i * 0.15), 0) * CFrame.Angles(0, i * 2.1, 0.8) * CFrame.new(0, r * 0.4, 0), "#4a4440", M.Wood)
		end
	elseif k == "bigbone" or k == "smallbone" then
		local L = r * (k == "bigbone" and 1.6 or 1)
		local d = k == "bigbone" and 1.4 or 0.35
		local cf = base * CFrame.new(0, d / 2, 0) * CFrame.Angles(0, rnd() * 3, 0)
		cyl(m, L, d, cf, "#ece6d6")
		ball(m, d * 1.8, cf * CFrame.new(L / 2, 0, 0), "#ece6d6")
		ball(m, d * 1.8, cf * CFrame.new(-L / 2, 0, 0), "#ece6d6")
	elseif k == "bigskull" then
		local s = r * 0.9
		P(m, Vector3.new(s * 1.4, s, s), base * CFrame.new(0, s / 2, 0), "#ece6d6", M.SmoothPlastic, true)
		P(m, Vector3.new(s * 0.6, s * 0.4, s * 0.8), base * CFrame.new(s * 0.9, s * 0.25, 0), "#cfc6b0", M.SmoothPlastic, true)
		for _, zz in ipairs({ -0.25, 0.25 }) do P(m, Vector3.new(0.2, s * 0.25, s * 0.25), base * CFrame.new(s * 0.71, s * 0.6, zz * s), "#111111") end
	elseif k == "grass" then
		for i = 1, 3 do
			P(m, Vector3.new(0.25, 1.4 + i * 0.3, 0.25), base * CFrame.new((rnd() - 0.5) * 1.5, 0.8, (rnd() - 0.5) * 1.5) * CFrame.Angles(rnd() * 0.4, 0, rnd() * 0.4), "#b5a642", M.Grass)
		end
	end
end

-- предметы, разложенные по чанкам
local function keyOf(x, z) return math.floor(x / CHUNK) .. "|" .. math.floor(z / CHUNK) end
local function addItem(kind, item, x, y)
	local key = keyOf(x * K, y * K)
	local c = chunks[key]
	if not c then
		c = { items = {} }
		chunks[key] = c
	end
	table.insert(c.items, { kind = kind, item = item })
end

local function buildItem(m, it)
	local o = it.item
	if it.kind == "tree" then
		makeTree(m, o)
	elseif it.kind == "flower" then
		local gy = o.sky and World.SKY_Y or 0
		local p = P(m, Vector3.new(0.35, 0.35, 0.35), CFrame.new(o.x * K, gy + 0.3, o.y * K), o.c)
		p.CastShadow = false
	elseif it.kind == "crystal" then
		local h = 1.2 + o.h * 1.2
		local p = P(m, Vector3.new(0.6, h, 0.6), CFrame.new(o.x * K, h / 2, o.y * K) * CFrame.Angles(0.2, (o.s or 0) % 6, 0.15), o.c, M.Neon)
		if (o.s or 0) % 4 == 0 then
			local l = Instance.new("PointLight")
			l.Color = p.Color
			l.Range = 12
			l.Brightness = 1.2
			l.Parent = p
		end
	elseif it.kind == "vine" then
		local L = o.len * 0.5
		P(m, Vector3.new(0.2, L, 0.2), CFrame.new(o.x * K, World.SKY_Y - L / 2, o.y * K), "#2f9e44", M.Grass)
	elseif it.kind == "shroom" then
		local cap = o.type == "amanita" and "#e03131" or o.type == "chanterelle" and "#f59f00" or o.type == "glow" and "#7df9ff" or o.type == "violet" and "#c77dff" or "#8b5a2b"
		local mdl = Instance.new("Model")
		mdl.Name = "Shroom"
		P(mdl, Vector3.new(0.25, 0.5, 0.25), CFrame.new(o.x * K, 0.25, o.y * K), "#f8f4ea")
		P(mdl, Vector3.new(0.7, 0.25, 0.7), CFrame.new(o.x * K, 0.55, o.y * K), cap, (o.type == "glow" or o.type == "violet") and M.Neon or M.SmoothPlastic)
		mdl.Parent = m
		it.model = mdl
		it.home = m
		shroomParts[o.id] = it
		if State.world.picked and State.world.picked[o.id] then mdl.Parent = nil end
	end
end

local function buildChunk(c)
	local m = Instance.new("Model")
	m.Name = "Chunk"
	for _, it in ipairs(c.items) do buildItem(m, it) end
	m.Parent = chunkFolder
	c.model = m
end
local function destroyChunk(c)
	if c.model then
		for _, it in ipairs(c.items) do
			if it.kind == "shroom" then
				shroomParts[it.item.id] = nil
				if it.model then it.model:Destroy() end
			end
		end
		c.model:Destroy()
		c.model = nil
	end
end

local lastCheck = 0
local function updateChunks()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local pos = cam.Focus.Position
	local cx, cz = math.floor(pos.X / CHUNK), math.floor(pos.Z / CHUNK)
	local n = math.ceil(RADIUS / CHUNK)
	local want = {}
	for i = -n, n do
		for j = -n, n do
			local key = (cx + i) .. "|" .. (cz + j)
			local c = chunks[key]
			if c then
				local dx = ((cx + i) + 0.5) * CHUNK - pos.X
				local dz = ((cz + j) + 0.5) * CHUNK - pos.Z
				if dx * dx + dz * dz < (RADIUS + CHUNK) ^ 2 then
					want[key] = true
					if not c.model and not c.queued then
						c.queued = true
						table.insert(queue, { c = c, d = dx * dx + dz * dz })
					end
				end
			end
		end
	end
	table.sort(queue, function(a, b) return a.d < b.d end)
	for key, c in pairs(chunks) do
		if c.model and not want[key] then destroyChunk(c) end
	end
end

local function processQueue()
	local t0 = os.clock()
	while #queue > 0 and os.clock() - t0 < 0.004 do
		local q = table.remove(queue, 1)
		q.c.queued = false
		if not q.c.model then buildChunk(q.c) end
	end
end

--[[ ---------- жители ---------- ]]
local npcs = {}
local function buildNpcs()
	local f = Instance.new("Folder")
	f.Name = "People"
	f.Parent = folder
	for _, n in ipairs(Q.NPCS) do
		local m = HB.buildPerson(n.look, { ghost = n.ghost, fairy = n.fairy })
		m.Name = n.name
		local pos = World.toStuds(n.x, n.y, World.groundY(n.x, n.y))
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0))
		m.Parent = f
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(240, 60)
		bb.StudsOffset = Vector3.new(0, 10, 0)
		bb.MaxDistance = 140
		bb.LightInfluence = 0
		bb.Parent = m.PrimaryPart
		local mk = Instance.new("TextLabel")
		mk.Size = UDim2.new(1, 0, 0.55, 0)
		mk.BackgroundTransparency = 1
		mk.Text = ""
		mk.TextScaled = true
		mk.Font = Enum.Font.GothamBlack
		mk.TextColor3 = color("#e67700")
		mk.TextStrokeTransparency = 0.2
		mk.Parent = bb
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, 0, 0.45, 0)
		nm.Position = UDim2.fromScale(0, 0.55)
		nm.BackgroundTransparency = 1
		nm.Text = n.name
		nm.TextSize = 15
		nm.Font = Enum.Font.GothamBold
		nm.TextColor3 = color(n.ghost and "#5c7cfa" or "#1c4f8a")
		nm.TextStrokeColor3 = Color3.new(1, 1, 1)
		nm.TextStrokeTransparency = 0.2
		nm.Parent = bb
		npcs[n.id] = { model = m, marker = mk, base = CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0), ghost = n.ghost }
	end
end
local function updateMarkers(P)
	for id, n in pairs(npcs) do
		local mk = Q.marker(P, id)
		n.marker.Text = (mk == "❗" or mk == "❓") and mk or ""
	end
end

-- сундук графа
local chest
local function buildChest()
	local m = Instance.new("Model")
	m.Name = "Chest"
	local c = World.CHEST
	local base = CFrame.new(c.x * K, 0, c.y * K)
	P(m, Vector3.new(3.4, 2, 2.2), base * CFrame.new(0, 1, 0), "#8a5a32", M.Wood, true)
	P(m, Vector3.new(3.5, 0.8, 2.3), base * CFrame.new(0, 2.3, 0), "#6b4423", M.Wood, true)
	P(m, Vector3.new(0.5, 0.6, 0.2), base * CFrame.new(0, 1.8, 1.15), "#ffd43b", M.Neon)
	local l = Instance.new("PointLight")
	l.Color = color("#ffd43b")
	l.Range = 14
	l.Parent = m:FindFirstChildWhichIsA("Part")
	m.Parent = folder
	chest = m
end

--[[ ---------- постройки игроков ---------- ]]
local builtModels = {}  -- [key] = { model, sig }
local function stage(b)
	if not b.crop then return -1 end
	local g = b.grow or 0
	return g >= 1 and 3 or g >= 0.6 and 2 or g >= 0.25 and 1 or 0
end
local function buildModel(b)
	local m = Instance.new("Model")
	m.Name = b.type
	local r = Stalls.rectOf(b)
	local cx, cz = (r.x + r.w / 2) * K, (r.y + r.h / 2) * K
	local w, d = r.w * K, r.h * K
	local base = CFrame.new(cx, 0, cz)
	local t = b.type
	local wood, dark = "#8a5a32", "#5c3d1e"
	if t == "bed" then
		P(m, Vector3.new(w, 0.5, d), base * CFrame.new(0, 0.25, 0), (b.wet or 0) > 0 and "#4a3524" or "#6b4a2b", M.Ground)
		local st = stage(b)
		if st >= 0 then
			local c = Items.CROPS[b.crop]
			local hgt = 0.4 + st * 0.5
			for i = 0, 3 do
				for j = 0, 1 do
					local px = -w / 2 + w * (i + 0.5) / 4
					local pz = -d / 2 + d * (j + 0.5) / 2
					P(m, Vector3.new(0.3, hgt, 0.3), base * CFrame.new(px, 0.5 + hgt / 2, pz), c.leaf, M.Grass)
					if st == 3 then
						local fruit = b.crop == "magic" and M.Neon or M.SmoothPlastic
						if b.crop == "pumpkin" then P(m, Vector3.new(1.2, 0.9, 1.2), base * CFrame.new(px, 0.9, pz), c.color, fruit)
						else P(m, Vector3.new(0.6, 0.5, 0.6), base * CFrame.new(px, 0.5 + hgt + 0.2, pz), c.color, fruit) end
					end
				end
			end
		end
	elseif t == "fence" then
		local long = w >= d
		local len = long and w or d
		local dir = long and base or base * CFrame.Angles(0, math.pi / 2, 0)
		for _, y in ipairs({ 1.4, 2.8 }) do P(m, Vector3.new(len, 0.35, 0.35), dir * CFrame.new(0, y, 0), wood, M.Wood, true) end
		for _, s in ipairs({ -1, 0, 1 }) do P(m, Vector3.new(0.5, 3.2, 0.5), dir * CFrame.new(s * len / 2, 1.6, 0), dark, M.Wood, true) end
	elseif t == "lamp" then
		P(m, Vector3.new(0.5, 7, 0.5), base * CFrame.new(0, 3.5, 0), "#2b2b2b", M.Metal, true)
		local bulb = P(m, Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 7.4, 0), "#ffe9a8")
		bulb.Name = "LampBulb"
		local l = Instance.new("PointLight")
		l.Range = 34
		l.Brightness = 2
		l.Color = color("#ffd88a")
		l.Parent = bulb
	elseif t == "flowerbed" then
		P(m, Vector3.new(w, 0.4, d), base * CFrame.new(0, 0.2, 0), "#6b4a2b", M.Ground)
		local rnd = Util.rng(b.id * 13)
		local cols = { "#ff8fab", "#ffd43b", "#c77dff", "#ffffff", "#ff6b6b" }
		for _ = 1, 14 do
			P(m, Vector3.new(0.45, 0.45, 0.45), base * CFrame.new((rnd() - 0.5) * (w - 0.6), 0.75, (rnd() - 0.5) * (d - 0.6)), cols[math.floor(rnd() * 5) + 1])
		end
	elseif t == "bench" then
		P(m, Vector3.new(w, 0.3, d), base * CFrame.new(0, 1.3, 0), wood, M.Wood, true)
		P(m, Vector3.new(w, 1.2, 0.3), base * CFrame.new(0, 2, -d / 2), wood, M.Wood, true)
		for _, s in ipairs({ -1, 1 }) do P(m, Vector3.new(0.3, 1.2, d), base * CFrame.new(s * w * 0.42, 0.6, 0), dark, M.Wood, true) end
	elseif t == "trough" then
		P(m, Vector3.new(w, 1.4, d), base * CFrame.new(0, 0.7, 0), wood, M.Wood, true)
		P(m, Vector3.new(w - 0.4, 0.2, d - 0.4), base * CFrame.new(0, 1.35, 0), "#4dabf7", M.Glass)
	elseif t == "haystack" then
		local h = b.used and 1.5 or 3.6
		P(m, Vector3.new(w, h, d), base * CFrame.new(0, h / 2, 0), "#e9c46a", M.Grass, true)
	elseif t == "tree" then
		P(m, Vector3.new(0.8, 4, 0.8), base * CFrame.new(0, 2, 0), "#6b4423", M.Wood, true)
		ball(m, 4.5, base * CFrame.new(0, 5.4, 0), "#4f8f3a", M.Grass)
		if (b.t or 0) <= 0 then
			for i = 1, 6 do
				local a = i / 6 * math.pi * 2
				ball(m, 0.6, base * CFrame.new(math.cos(a) * 1.9, 5 + (i % 2) * 0.8, math.sin(a) * 1.9), "#e03131")
			end
		end
	elseif t == "bunnyhouse" then
		P(m, Vector3.new(w, 2.4, d), base * CFrame.new(0, 1.2, 0), "#f1e3c6", M.SmoothPlastic, true)
		P(m, Vector3.new(w + 0.6, 0.5, d + 0.6), base * CFrame.new(0, 2.7, 0), "#e64980", M.SmoothPlastic, true)
		P(m, Vector3.new(0.9, 1.2, 0.2), base * CFrame.new(0, 0.6, d / 2), "#3b2a1a")
	elseif t == "well" then
		local wl = cyl(m, 2.6, w, base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), "#8d8476", M.Cobblestone, true)
		wl.CFrame = base * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
		P(m, Vector3.new(w + 0.6, 0.4, d + 0.6), base * CFrame.new(0, 5, 0), "#8c3b2a")
		for _, s in ipairs({ -1, 1 }) do P(m, Vector3.new(0.3, 3.6, 0.3), base * CFrame.new(s * w / 2, 3.3, 0), dark) end
	elseif t == "windmill" then
		P(m, Vector3.new(w * 0.6, 12, d * 0.6), base * CFrame.new(0, 6, 0), "#f1e3c6", M.SmoothPlastic, true)
		P(m, Vector3.new(w * 0.7, 2, d * 0.7), base * CFrame.new(0, 13, 0), "#a33a2a")
		local hub = P(m, Vector3.new(0.8, 0.8, 0.8), base * CFrame.new(0, 11, d * 0.36), "#5c3d1e")
		hub.Name = "Hub"
		for i = 0, 3 do
			local blade = P(m, Vector3.new(1.2, 7, 0.2), hub.CFrame * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 3.5, 0.3), "#ffffff", M.Fabric)
			blade.Name = "Blade"
		end
	elseif t == "stable5" then
		for _, wr in ipairs(Stalls.stableWalls(b)) do
			P(m, Vector3.new(wr.w * K, 8, wr.h * K), CFrame.new((wr.x + wr.w / 2) * K, 4, (wr.y + wr.h / 2) * K), "#c8a27a", M.WoodPlanks, true)
		end
		P(m, Vector3.new(w + 2, 0.6, d + 2), base * CFrame.new(0, 8.3, 0), "#a33a2a", M.WoodPlanks)
		for k = 1, 4 do
			if b.rot == 1 then P(m, Vector3.new(12, 4, 0.4), CFrame.new((r.x + 75) * K, 2, (r.y + k * 68) * K), wood, M.Wood, true)
			else P(m, Vector3.new(0.4, 4, 12), CFrame.new((r.x + k * 68) * K, 2, (r.y + 70) * K), wood, M.Wood, true) end
		end
	end
	return m
end
local function syncBuilds(list)
	local seen = {}
	for _, b in ipairs(list) do
		local key = b.owner .. ":" .. b.id
		seen[key] = true
		local sig = table.concat({ b.type, b.x, b.y, b.rot, tostring(b.crop), stage(b), (b.wet or 0) > 0 and 1 or 0, (b.t or 0) > 0 and 1 or 0, b.used and 1 or 0 }, "|")
		local cur = builtModels[key]
		if not cur or cur.sig ~= sig then
			if cur then cur.model:Destroy() end
			local m = buildModel(b)
			m.Parent = buildFolder
			if b.ownerName and (b.type == "stable5" or b.type == "windmill" or b.type == "bed") then
				local anchor = m:FindFirstChildWhichIsA("BasePart")
				if anchor then
					local bb = Instance.new("BillboardGui")
					bb.Size = UDim2.fromOffset(160, 20)
					bb.StudsOffset = Vector3.new(0, 3, 0)
					bb.MaxDistance = 60
					bb.Parent = anchor
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.fromScale(1, 1)
					tl.BackgroundTransparency = 1
					tl.Text = (b.type == "bed" and b.crop and Items.CROPS[b.crop] and (Items.CROPS[b.crop].name .. " · ") or "") .. b.ownerName
					tl.TextSize = 12
					tl.Font = Enum.Font.Gotham
					tl.TextColor3 = color("#3b2a1a")
					tl.TextStrokeTransparency = 0.5
					tl.TextStrokeColor3 = Color3.new(1, 1, 1)
					tl.Parent = bb
				end
			end
			builtModels[key] = { model = m, sig = sig }
		end
	end
	for key, cur in pairs(builtModels) do
		if not seen[key] then
			cur.model:Destroy()
			builtModels[key] = nil
		end
	end
end

function Decor.update(dt, t)
	lastCheck += dt
	if lastCheck > 0.5 then
		lastCheck = 0
		updateChunks()
	end
	processQueue()
	-- жители покачиваются, привидение парит
	for _, n in pairs(npcs) do
		local cam = workspace.CurrentCamera
		if cam and (n.model.PrimaryPart.Position - cam.CFrame.Position).Magnitude < 150 then
			local bob = n.ghost and (1 + math.sin(t * 1.5) * 0.5) or 0
			n.model:PivotTo(n.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.sin(t * 0.6) * 0.25, 0))
		end
	end
	-- мельницы крутятся, фонари горят ночью
	local night = (game:GetService("Lighting").ClockTime < 6.2 or game:GetService("Lighting").ClockTime > 19.8)
	for _, cur in pairs(builtModels) do
		local m = cur.model
		if m.Name == "windmill" then
			local hub = m:FindFirstChild("Hub")
			if hub then
				local i = 0
				for _, b in ipairs(m:GetChildren()) do
					if b.Name == "Blade" then
						b.CFrame = hub.CFrame * CFrame.Angles(0, 0, t * 0.8 + i * math.pi / 2) * CFrame.new(0, 3.5, 0.3)
						i += 1
					end
				end
			end
		elseif m.Name == "lamp" then
			local bulb = m:FindFirstChild("LampBulb")
			if bulb then
				local l = bulb:FindFirstChildOfClass("PointLight")
				if l and l.Enabled ~= night then
					l.Enabled = night
					bulb.Material = night and M.Neon or M.SmoothPlastic
				end
			end
		end
	end
end

function Decor.init()
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = workspace
	chunkFolder = Instance.new("Folder")
	chunkFolder.Name = "Chunks"
	chunkFolder.Parent = folder
	buildFolder = Instance.new("Folder")
	buildFolder.Name = "Builds"
	buildFolder.Parent = folder
	for _, t in ipairs(World.TREES) do addItem("tree", t, t.x, t.y) end
	for _, f in ipairs(World.FLOWERS) do addItem("flower", f, f.x, f.y) end
	for _, c in ipairs(World.CRYSTALS) do addItem("crystal", c, c.x, c.y) end
	for _, v in ipairs(World.VINES) do addItem("vine", v, v.x, v.y) end
	for _, s in ipairs(World.SHROOMS) do addItem("shroom", s, s.x, s.y) end
	buildNpcs()
	buildChest()
	State.on("profile", function(P)
		updateMarkers(P)
		if chest then
			if P.flags and P.flags.chest_opened then chest.Parent = nil else chest.Parent = folder end
		end
	end)
	State.on("picked", function(set)
		for id, it in pairs(shroomParts) do
			if it.model then
				if set[id] then it.model.Parent = nil else it.model.Parent = it.home end
			end
		end
	end)
	State.on("builds", syncBuilds)
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function(dt) Decor.update(dt, os.clock() - t0) end)
end

Decor.Players = Players
return Decor
