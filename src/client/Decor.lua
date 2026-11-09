--[[
	Декорации мира на клиенте: деревья, грибы, камни, кактусы, кости, цветы, кристаллы, лианы
	(списки детерминированно строит World — как в JS-версии). Рисуются кусками (чанками) вокруг камеры.
	А также жители (NPC) и сундук графа.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Q = require(Shared.QuestData)

local Client = script.Parent
local State = require(Client.State)

local Decor = {}
local K = World.K
local CHUNK = 64          -- стадов
local RADIUS = 250        -- стадов
local color = Util.color
local M = Enum.Material
local folder, chunkFolder
local chunks = {}         -- [key] = { items = {}, model = nil }
local queue = {}
local shroomParts = {}    -- [id] = part
local buildFlower

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

-- эллипсоид (сплюснутый шар): деталь со SpecialMesh «Sphere» принимает форму размера детали
local function ellip(model, size, cf, c, material)
	local p = P(model, size, cf, c, material, false)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
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
		-- высокие деревья: ствол втрое выше прежнего, крона больше и из нескольких частей
		local th = r * 4.2 + rnd() * 5
		local trunk = k == "birch" and "#efe9de" or "#6b4423"
		local tw = 0.9 + r * 0.18
		P(m, Vector3.new(tw, th, tw), base * CFrame.new(0, th / 2, 0), trunk, M.Wood, true)
		if k == "birch" then
			for i = 1, 6 do P(m, Vector3.new(tw + 0.05, 0.25, tw + 0.05), base * CFrame.new(0, th * i / 7, 0) * CFrame.Angles(0, i, 0), "#2b2b2b") end
		end
		-- пара веток
		for i = 1, 2 do
			local a = rnd() * 6.28
			P(m, Vector3.new(0.4, r * 1.2, 0.4), base * CFrame.new(0, th * (0.55 + i * 0.12), 0) * CFrame.Angles(0, a, 0.9) * CFrame.new(0, r * 0.6, 0), trunk, M.Wood)
		end
		local leaf = k == "birch" and "#8cc152" or (dark and "#2f6b2f" or "#4f8f3a")
		local cr = r * 1.6
		P(m, Vector3.new(cr * 1.7, cr * 1.2, cr * 1.7), base * CFrame.new(0, th + cr * 0.1, 0) * CFrame.Angles(0, rnd() * 3, 0), leaf, M.Grass)
		P(m, Vector3.new(cr * 1.2, cr * 1.0, cr * 1.2), base * CFrame.new((rnd() - 0.5) * cr, th + cr * 0.8, (rnd() - 0.5) * cr) * CFrame.Angles(0, rnd() * 3, 0), Util.mix(leaf, "#ffffff", 0.08), M.Grass)
		P(m, Vector3.new(cr * 1.1, cr * 0.8, cr * 1.1), base * CFrame.new((rnd() - 0.5) * cr * 1.2, th - cr * 0.35, (rnd() - 0.5) * cr * 1.2) * CFrame.Angles(0, rnd() * 3, 0), Util.mix(leaf, "#000000", 0.08), M.Grass)
		if k == "vinetree" then
			for i = 1, 5 do
				local a = i / 5 * math.pi * 2
				P(m, Vector3.new(0.2, th * 0.8, 0.2), base * CFrame.new(math.cos(a) * cr * 0.7, th * 0.6, math.sin(a) * cr * 0.7), "#2f9e44", M.Grass)
			end
		end
	elseif k == "pine" or k == "spruce" or k == "snowspruce" then
		-- высокие ели и сосны: ствол выше, ярусов больше
		local th = r * 1.5
		local tiers = 6
		local step = r * 0.75
		P(m, Vector3.new(0.9, th + tiers * step, 0.9), base * CFrame.new(0, (th + tiers * step) / 2, 0), "#5c3d1e", M.Wood, true)
		local leaf = k == "pine" and (dark and "#244d24" or "#2f6b2f") or (k == "snowspruce" and "#2d5a3d" or (dark and "#1e3d2c" or "#2b5d4a"))
		local w = r * 2
		for i = 0, tiers - 1 do
			local s = w * (1 - i * 0.15)
			local y = th + i * step
			P(m, Vector3.new(s, r * 0.7, s), base * CFrame.new(0, y, 0) * CFrame.Angles(0, i * 0.4, 0), leaf, M.Grass)
			if k == "snowspruce" then P(m, Vector3.new(s * 0.9, 0.3, s * 0.9), base * CFrame.new(0, y + r * 0.36, 0) * CFrame.Angles(0, i * 0.4, 0), "#ffffff", M.Snow) end
		end
		P(m, Vector3.new(r * 0.35, r * 0.8, r * 0.35), base * CFrame.new(0, th + tiers * step + r * 0.1, 0), leaf, M.Grass)
	elseif k == "amanita" or k == "boletus" or k == "glowshroom" then
		-- большие грибы как настоящие: ножка с утолщением внизу (и «юбочкой» у мухомора),
		-- шляпка-купол, под ней светлые пластинки; у мухомора белые точки по всей шляпке
		local sh = r * (k == "boletus" and 1.0 or 1.5)
		local stem = k == "boletus" and "#e8d9b5" or "#f8f4ea"
		local sw = r * (k == "boletus" and 0.75 or 0.45)
		cyl(m, sh, sw, base * CFrame.new(0, sh / 2, 0), stem, M.SmoothPlastic, true)
		ellip(m, Vector3.new(sw * 1.5, sw * 1.1, sw * 1.5), base * CFrame.new(0, sw * 0.4, 0), stem)
		if k == "amanita" then
			-- «юбочка» на ножке
			cyl(m, 0.25, sw * 1.9, base * CFrame.new(0, sh * 0.72, 0), "#ffffff")
			cyl(m, 0.35, sw * 1.5, base * CFrame.new(0, sh * 0.72 - 0.25, 0), "#f1ece0")
		end
		local capC = k == "amanita" and "#e03131" or k == "boletus" and "#8b5a2b" or (rnd() < 0.5 and "#7df9ff" or "#c77dff")
		-- шляпка: сплюснутый шар, центр чуть выше верха ножки
		local A, B = r * 1.05, r * (k == "boletus" and 0.62 or 0.5)
		local capCenter = base * CFrame.new(0, sh + B * 0.2, 0)
		local cap = ellip(m, Vector3.new(A * 2, B * 2, A * 2), capCenter, capC, k == "glowshroom" and M.Neon or M.SmoothPlastic)
		-- пластинки под шляпкой
		cyl(m, 0.2, A * 1.5, base * CFrame.new(0, sh - B * 0.55, 0), k == "boletus" and "#d9b45a" or "#f3ead6")
		if k == "amanita" then
			-- белые точки равномерно по всей шляпке (спираль Фибоначчи), повёрнуты по поверхности
			local n = 26
			local golden = math.pi * (3 - math.sqrt(5))
			for i = 0, n - 1 do
				local cy = 1 - (i + 0.5) / n * 1.15 -- от макушки до чуть ниже «экватора»
				local rad = math.sqrt(math.max(0, 1 - cy * cy))
				local ph = i * golden + rnd() * 0.3
				local lx, ly, lz = math.cos(ph) * rad * A, cy * B, math.sin(ph) * rad * A
				local normal = Vector3.new(lx / (A * A), ly / (B * B), lz / (A * A)).Unit
				local pos = capCenter * Vector3.new(lx, ly, lz)
				local right = normal:Cross(Vector3.zAxis)
				if right.Magnitude < 0.05 then right = Vector3.xAxis end
				right = right.Unit
				local ds = r * (0.13 + rnd() * 0.08)
				ellip(m, Vector3.new(ds, ds * 0.35, ds), CFrame.fromMatrix(pos, right, normal), "#ffffff")
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
		local h = k == "cliff" and r * 1.4 or k == "cavewall" and 25 + rnd() * 4 or r * (0.7 + rnd() * 0.5)
		local c = k == "basalt" and "#2b2626" or k == "cavewall" and "#5a5550" or (k == "cliff" and "#8a8580" or "#9a958f")
		P(m, Vector3.new(r * 1.7, h, r * 1.5), base * CFrame.new(0, h / 2 - 0.3, 0) * CFrame.Angles(0, rnd() * 3, 0), c, M.Rock, true)
		P(m, Vector3.new(r * 1.1, h * 0.5, r * 1.1), base * CFrame.new((rnd() - 0.5) * r, h * 0.85, (rnd() - 0.5) * r) * CFrame.Angles(0, rnd() * 3, 0), Util.mix(c, "#ffffff", 0.08), M.Rock, true)
		if k == "snowrock" then P(m, Vector3.new(r * 1.6, 0.5, r * 1.4), base * CFrame.new(0, h + 0.1, 0), "#ffffff", M.Snow) end
	elseif k == "palm" then
		local th = r * 3.6
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
		local th = r * 2.4 + 3
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

--[[ ---------- цветы ----------
	Похожие на настоящие: зелёный стебель с листиком и головка из лепестков вокруг серединки.
	Вид зависит от цвета: белые — ромашки, жёлтые — лютики, розовые и сиреневые — космеи,
	красные — маки (с тёмной серединкой), персиковые — тюльпаны (бутон из лепестков вверх). ]]
local FLOWER_KIND = { ["#ffffff"] = "daisy", ["#ffe066"] = "buttercup", ["#ff8fab"] = "cosmos", ["#c77dff"] = "cosmos", ["#ffd6a5"] = "tulip", ["#f94144"] = "poppy" }
buildFlower = function(m, o)
	local gy = o.sky and World.SKY_Y or 0
	local rnd = Util.rng(math.floor((o.x * 7 + o.y * 13) % 100000) + 1)
	local kind = FLOWER_KIND[o.c] or "daisy"
	local sz = 0.75 + (o.s or 2) * 0.12
	local h = (kind == "tulip" and 1.0 or 0.75) * sz + rnd() * 0.25
	local base = CFrame.new(o.x * K, gy, o.y * K) * CFrame.Angles(0, rnd() * 6.28, 0)
	local tilt = CFrame.Angles((rnd() - 0.5) * 0.25, 0, (rnd() - 0.5) * 0.25)
	local function nc(p) p.CastShadow = false; return p end
	nc(P(m, Vector3.new(0.07, h, 0.07), base * tilt * CFrame.new(0, h / 2, 0), "#2f9e44", M.Grass))
	nc(ellip(m, Vector3.new(0.34 * sz, 0.05, 0.13 * sz), base * CFrame.new(0.13 * sz, h * 0.3, 0) * CFrame.Angles(0, 0, 0.5), "#37b24d", M.Grass))
	local head = base * tilt * CFrame.new(0, h, 0)
	if kind == "tulip" then
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			nc(ellip(m, Vector3.new(0.17 * sz, 0.42 * sz, 0.12 * sz), head * CFrame.Angles(0, a, 0) * CFrame.new(0.08 * sz, 0.15 * sz, 0) * CFrame.Angles(0, 0, 0.15), o.c))
		end
		return
	end
	local n = kind == "daisy" and 8 or kind == "poppy" and 4 or 5
	local pl = (kind == "daisy" and 0.24 or kind == "poppy" and 0.26 or 0.22) * sz
	local pw = (kind == "daisy" and 0.09 or kind == "poppy" and 0.24 or 0.15) * sz
	local cup = kind == "poppy" and 0.35 or kind == "buttercup" and 0.45 or 0.12
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		nc(ellip(m, Vector3.new(pl, 0.04, pw), head * CFrame.Angles(0, a, 0) * CFrame.new(pl * 0.55, 0, 0) * CFrame.Angles(0, 0, cup), o.c))
	end
	local mid = kind == "poppy" and "#2b2b2b" or kind == "cosmos" and "#ffd43b" or "#fab005"
	nc(ellip(m, Vector3.new(0.13 * sz, 0.08 * sz, 0.13 * sz), head * CFrame.new(0, 0.03, 0), mid))
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
		buildFlower(m, o)
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
		ellip(mdl, Vector3.new(0.75, 0.4, 0.75), CFrame.new(o.x * K, 0.55, o.y * K), cap, (o.type == "glow" or o.type == "violet") and M.Neon or M.SmoothPlastic)
		if o.type == "amanita" then
			for i = 0, 4 do
				local a = i / 5 * math.pi * 2
				P(mdl, Vector3.new(0.08, 0.05, 0.08), CFrame.new(o.x * K + math.cos(a) * 0.2, 0.71, o.y * K + math.sin(a) * 0.2), "#ffffff")
			end
		end
		mdl.Parent = m
		it.model = mdl
		it.home = m
		shroomParts[o.id] = it
	end
end

local function buildChunk(c)
	local m = Instance.new("Model")
	m.Name = "Chunk"
	for _, it in ipairs(c.items) do buildItem(m, it) end
	m:TranslateBy(Vector3.new(0, World.GROUND, 0))
	-- сорванные грибы прячем после сдвига, иначе они не сдвинутся
	for _, it in ipairs(c.items) do
		if it.kind == "shroom" and it.model and State.world.picked and State.world.picked[it.item.id] then it.model.Parent = nil end
	end
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
-- жителей создаёт сервер (стандартные человечки Roblox), здесь — только значки заданий над ними
local npcs = {}
local function addMarker(rig)
	local id = rig:GetAttribute("NpcId")
	local head = rig:WaitForChild("Head", 10)
	if not id or not head or npcs[id] then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "QuestMarker"
	bb.Size = UDim2.fromOffset(60, 40)
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.Parent = head
	local mk = Instance.new("TextLabel")
	mk.Size = UDim2.fromScale(1, 1)
	mk.BackgroundTransparency = 1
	mk.Text = ""
	mk.TextScaled = true
	mk.Font = Enum.Font.GothamBlack
	mk.TextColor3 = color("#e67700")
	mk.TextStrokeTransparency = 0.2
	mk.Parent = bb
	npcs[id] = { marker = mk }
	if State.P then
		local m = Q.marker(State.P, id)
		mk.Text = (m == "❗" or m == "❓") and m or ""
	end
end
local function buildNpcs()
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		local people = world:WaitForChild("People")
		for _, rig in ipairs(people:GetChildren()) do task.spawn(addMarker, rig) end
		people.ChildAdded:Connect(function(rig) task.spawn(addMarker, rig) end)
	end)
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
	m:TranslateBy(Vector3.new(0, World.GROUND, 0))
	m.Parent = folder
	chest = m
end

function Decor.update(dt, t)
	lastCheck += dt
	if lastCheck > 0.5 then
		lastCheck = 0
		updateChunks()
	end
	processQueue()
end

function Decor.init()
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = workspace
	chunkFolder = Instance.new("Folder")
	chunkFolder.Name = "Chunks"
	chunkFolder.Parent = folder
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
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function(dt) Decor.update(dt, os.clock() - t0) end)
end

Decor.Players = Players
return Decor
