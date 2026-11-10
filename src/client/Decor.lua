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
-- цилиндр между двумя точками (ветка, кость, ребро)
local function limb(model, a, b, d, c, material, collide)
	local len = (b - a).Magnitude
	if len < 0.05 then return nil end
	local p = P(model, Vector3.new(len, d, d), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), c, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function wedge(model, size, cf, c, material)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Size = size
	w.CFrame = cf
	w.Color = color(c)
	w.Material = material or M.SmoothPlastic
	w.Parent = model
	return w
end
local function shade(c, k) return Util.mix(c, k > 0 and "#ffffff" or "#000000", math.abs(k)) end

-- падающие листья: медленные кружащиеся частицы под кроной (не у каждого дерева, чтобы не было тяжело)
local function leafFall(part, c, rate)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = rate or 0.6
	pe.Lifetime = NumberRange.new(5, 8)
	pe.Speed = NumberRange.new(0.6, 1.4)
	pe.Acceleration = Vector3.new(0.4, -1.1, 0.2)
	pe.Drag = 0.8
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-120, 120)
	pe.Size = NumberSequence.new(0.28)
	pe.Squash = NumberSequence.new(0.5)
	pe.Color = ColorSequence.new(color(c), color(Util.mix(c, "#e8a33d", 0.5)))
	pe.LightInfluence = 1
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Parent = part
end

-- крона из нескольких «облаков» листвы (сплюснутых шаров) разных оттенков
local function crown(m, rnd, center, R, leaf, n, flat)
	local main
	for i = 1, n do
		local a = i / n * math.pi * 2 + rnd() * 0.8
		local d = i == 1 and 0 or R * (0.45 + rnd() * 0.35)
		local s = R * (i == 1 and 1.25 or (0.7 + rnd() * 0.35))
		local dy = i == 1 and 0 or (rnd() - 0.35) * R * 0.7
		local c = shade(leaf, (rnd() - 0.5) * 0.16)
		local p = ellip(m, Vector3.new(s * 1.9, s * (flat or 1.35), s * 1.9), center * CFrame.new(math.cos(a) * d, dy, math.sin(a) * d) * CFrame.Angles(0, rnd() * 3, 0), c, M.Grass)
		if i == 1 then main = p end
	end
	return main
end

local ROCK_KINDS = { cliff = true, rock = true, snowrock = true, basalt = true, cavewall = true }
local function makeTree(m, t)
	local rnd = Util.rng(t.s or 1)
	local x, z = t.x * K, t.y * K
	local gy = t.sky and World.SKY_Y or 0
	local base = CFrame.new(x, gy, z)
	local r = (t.r or 30) * K
	local k = t.kind
	local dark = t.dark
	if k == "oak" or k == "birch" or k == "vinetree" or k == "apple" then
		-- дерево как настоящее: ствол сужается кверху, у корней расширение, ветки расходятся в стороны,
		-- крона из нескольких облаков листвы разных оттенков; у яблони — яблоки, у берёзы — чёрные полоски
		local big = k == "apple" and 1.25 or 1
		local th = (k == "apple" and r * 2.4 or r * 4.2) + rnd() * 4
		local trunk = k == "birch" and "#efe9de" or (k == "apple" and "#7a5134" or "#6b4423")
		local tw = (0.9 + r * 0.18) * big
		local lean = CFrame.Angles((rnd() - 0.5) * 0.08, 0, (rnd() - 0.5) * 0.08)
		local tb = base * lean
		cyl(m, th * 0.55, tw, tb * CFrame.new(0, th * 0.275, 0), trunk, M.Wood, true)
		cyl(m, th * 0.5, tw * 0.72, tb * CFrame.new(0, th * 0.75, 0) * CFrame.Angles(0, 0, (rnd() - 0.5) * 0.06), trunk, M.Wood, false)
		ellip(m, Vector3.new(tw * 2.2, tw * 0.9, tw * 2.2), base * CFrame.new(0, 0.15, 0), shade(trunk, -0.1), M.Wood)
		if k == "birch" then
			for i = 1, 5 do
				P(m, Vector3.new(tw * 0.5, 0.18, tw * 1.02), tb * CFrame.new(0, th * (0.12 + i * 0.15), 0) * CFrame.Angles(0, i * 1.7, 0) * CFrame.new(0, 0, 0), "#2b2b2b")
			end
		end
		-- ветки
		local top = tb * CFrame.new(0, th, 0)
		local leaf = k == "birch" and "#8cc152" or k == "apple" and "#4c9a35" or (dark and "#2f6b2f" or "#4f8f3a")
		local cr = r * 1.6 * big
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2 + rnd()
			local from = (tb * CFrame.new(0, th * (0.6 + rnd() * 0.25), 0)).Position
			local to = from + Vector3.new(math.cos(a) * cr * 0.75, cr * 0.45, math.sin(a) * cr * 0.75)
			limb(m, from, to, 0.35 * big, trunk, M.Wood)
		end
		local main = crown(m, rnd, top * CFrame.new(0, cr * 0.15, 0), cr, leaf, k == "birch" and 4 or 5, k == "apple" and 1.15 or 1.35)
		if k == "apple" then
			for i = 1, 9 do
				local a, d = rnd() * math.pi * 2, cr * (0.6 + rnd() * 0.5)
				local p = ball(m, 0.55, top * CFrame.new(math.cos(a) * d, cr * (rnd() - 0.6) * 0.9, math.sin(a) * d), rnd() < 0.8 and "#d9302c" or "#9bc53d", M.SmoothPlastic, false)
				p.CastShadow = false
			end
		end
		if k == "vinetree" then
			for i = 1, 5 do
				local a = i / 5 * math.pi * 2
				P(m, Vector3.new(0.2, th * 0.8, 0.2), base * CFrame.new(math.cos(a) * cr * 0.7, th * 0.6, math.sin(a) * cr * 0.7), "#2f9e44", M.Grass)
			end
		end
		if main and not t.sky and (t.s or 0) % 3 == 0 then leafFall(main, leaf, k == "birch" and 0.9 or 0.6) end
	elseif k == "pine" or k == "spruce" or k == "snowspruce" then
		local leaf = k == "pine" and (dark and "#244d24" or "#2f6b2f") or (k == "snowspruce" and "#2d5a3d" or (dark and "#1e3d2c" or "#2b5d4a"))
		if k == "pine" then
			-- сосна: высокий голый рыжеватый ствол, крона наверху «облаками»
			local th = r * 4.6 + rnd() * 3
			cyl(m, th, 0.8 + r * 0.1, base * CFrame.new(0, th / 2, 0), "#9c5a33", M.Wood, true)
			ellip(m, Vector3.new(1.8, 0.7, 1.8), base * CFrame.new(0, 0.15, 0), "#7a4528", M.Wood)
			for i = 1, 2 do
				local a = rnd() * 6.28
				local from = (base * CFrame.new(0, th * (0.72 + i * 0.08), 0)).Position
				limb(m, from, from + Vector3.new(math.cos(a) * r * 0.9, r * 0.4, math.sin(a) * r * 0.9), 0.3, "#7a4528", M.Wood)
			end
			crown(m, rnd, base * CFrame.new(0, th + r * 0.2, 0), r * 1.15, leaf, 4, 0.8)
		else
			-- ель: конус из ярусов «лап», внизу шире, наверху острая макушка
			local th = r * 1.2
			local tiers = 6
			local step = r * 0.72
			local H = th + tiers * step
			cyl(m, H, 0.8, base * CFrame.new(0, H / 2, 0), "#5c3d1e", M.Wood, true)
			local w = r * 2.1
			for i = 0, tiers - 1 do
				local s0 = w * (1 - i * 0.14)
				local y = th + i * step
				ellip(m, Vector3.new(s0, r * 0.9, s0), base * CFrame.new(0, y, 0) * CFrame.Angles(0, i * 0.5, 0), shade(leaf, (i % 2) * 0.05), M.Grass)
				-- свисающие края лап
				P(m, Vector3.new(s0 * 0.72, r * 0.35, s0 * 0.72), base * CFrame.new(0, y - r * 0.32, 0) * CFrame.Angles(0, i * 0.5 + 0.4, 0), shade(leaf, -0.08), M.Grass)
				if k == "snowspruce" then ellip(m, Vector3.new(s0 * 0.85, r * 0.35, s0 * 0.85), base * CFrame.new(0, y + r * 0.3, 0), "#ffffff", M.Snow) end
			end
			ellip(m, Vector3.new(r * 0.45, r * 1.3, r * 0.45), base * CFrame.new(0, H + r * 0.35, 0), leaf, M.Grass)
		end
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
		if k == "glowshroom" then cap:SetAttribute("Glow12", true) end
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
		-- светящиеся грибы светят на 12% сильнее, чем раньше (и свет есть у большего числа грибов)
		if k == "glowshroom" and rnd() < 0.56 then
			local l = Instance.new("PointLight")
			l.Color = cap.Color
			l.Range = 14
			l.Brightness = 1
			l:SetAttribute("Glow12", true)
			l.Parent = cap
		end
	elseif ROCK_KINDS[k] then
		-- камни и скалы разной формы: глыбы, валуны, плиты, столбы и груды
		local c = k == "basalt" and "#2b2626" or k == "cavewall" and "#5a5550" or (k == "cliff" and "#8a8580" or "#9a958f")
		local mat = k == "basalt" and M.Basalt or (k == "cavewall" and (rnd() < 0.5 and M.Slate or M.Rock) or M.Rock)
		local form = math.floor(rnd() * 5)
		if k == "cavewall" then
			local h = 22 + rnd() * 9
			P(m, Vector3.new(r * (1.4 + rnd() * 0.6), h, r * (1.3 + rnd() * 0.5)), base * CFrame.new(0, h / 2 - 0.3, 0) * CFrame.Angles((rnd() - 0.5) * 0.15, rnd() * 3, (rnd() - 0.5) * 0.15), c, mat, true)
			P(m, Vector3.new(r * 1.0, h * 0.4, r * 1.0), base * CFrame.new((rnd() - 0.5) * r, h * (0.3 + rnd() * 0.5), (rnd() - 0.5) * r) * CFrame.Angles(rnd(), rnd() * 3, rnd()), shade(c, 0.06), mat, true)
		elseif k == "basalt" then
			-- базальтовые столбы
			for i = 1, 3 + math.floor(rnd() * 3) do
				local a, d = rnd() * 6.28, r * rnd() * 0.5
				local h = r * (0.6 + rnd() * 1.2)
				P(m, Vector3.new(r * 0.45, h, r * 0.45), base * CFrame.new(math.cos(a) * d, h / 2 - 0.2, math.sin(a) * d) * CFrame.Angles(0, rnd() * 3, 0), shade(c, (rnd() - 0.5) * 0.1), mat, true)
			end
		elseif form == 0 then
			-- угловатая глыба с наклоном
			local h = (k == "cliff" and r * 1.4 or r * (0.7 + rnd() * 0.5))
			P(m, Vector3.new(r * 1.7, h, r * 1.5), base * CFrame.new(0, h / 2 - 0.3, 0) * CFrame.Angles((rnd() - 0.5) * 0.3, rnd() * 3, (rnd() - 0.5) * 0.3), c, mat, true)
			P(m, Vector3.new(r * 1.1, h * 0.5, r * 1.1), base * CFrame.new((rnd() - 0.5) * r, h * 0.85, (rnd() - 0.5) * r) * CFrame.Angles(rnd() * 0.5, rnd() * 3, rnd() * 0.5), shade(c, 0.08), mat, true)
		elseif form == 1 then
			-- круглый валун
			local d = r * (1.2 + rnd() * 0.5) * (k == "cliff" and 1.3 or 1)
			ball(m, d, base * CFrame.new(0, d * 0.3, 0), c, mat, true)
			ball(m, d * 0.55, base * CFrame.new(d * 0.45, d * 0.12, (rnd() - 0.5) * d * 0.5), shade(c, -0.06), mat, true)
		elseif form == 2 then
			-- плита-клин
			local h = r * (k == "cliff" and 1.6 or 0.9)
			local w = wedge(m, Vector3.new(r * 1.4, h, r * 1.8), base * CFrame.new(0, h / 2 - 0.2, 0) * CFrame.Angles(0, rnd() * 6.28, 0), c, mat)
			w.CanCollide = true
			w.CanQuery = true
			P(m, Vector3.new(r * 0.8, h * 0.35, r * 0.8), base * CFrame.new(r * 0.5, h * 0.15, r * 0.3) * CFrame.Angles(0.3, rnd() * 3, 0.2), shade(c, -0.05), mat, true)
		elseif form == 3 then
			-- столб-останец
			local h = r * (k == "cliff" and 2.2 or 1.4)
			P(m, Vector3.new(r * 0.9, h, r * 0.8), base * CFrame.new(0, h / 2 - 0.3, 0) * CFrame.Angles((rnd() - 0.5) * 0.2, rnd() * 3, (rnd() - 0.5) * 0.2), c, mat, true)
			P(m, Vector3.new(r * 1.2, h * 0.3, r * 1.1), base * CFrame.new(0, h * 0.12, 0) * CFrame.Angles(0, rnd() * 3, 0), shade(c, -0.05), mat, true)
		else
			-- груда камней
			for i = 1, 4 do
				local a, d = rnd() * 6.28, r * rnd() * 0.6
				local s0 = r * (0.5 + rnd() * 0.6)
				P(m, Vector3.new(s0, s0 * 0.8, s0 * 0.9), base * CFrame.new(math.cos(a) * d, s0 * 0.3, math.sin(a) * d) * CFrame.Angles(rnd(), rnd() * 3, rnd()), shade(c, (rnd() - 0.5) * 0.12), mat, true)
			end
		end
		if k == "snowrock" then ellip(m, Vector3.new(r * 1.7, 0.8, r * 1.5), base * CFrame.new(0, r * 0.8, 0), "#ffffff", M.Snow) end
	elseif k == "palm" then
		-- пальма: изогнутый ствол из колец, свисающие листья из двух частей, кокосы
		local th = r * 3.6
		local seg = 7
		local bendA = rnd() * 6.28
		local bend = 0.05 + rnd() * 0.06
		local cf = base
		local lastTop
		for i = 0, seg - 1 do
			local L = th / seg
			cf = cf * CFrame.Angles(math.cos(bendA) * bend, 0, math.sin(bendA) * bend)
			local mid = cf * CFrame.new(0, L / 2, 0)
			cyl(m, L * 1.05, 0.95 - i * 0.05, mid, i % 2 == 0 and "#a0764a" or "#8a6440", M.Wood, i == 0)
			cf = cf * CFrame.new(0, L, 0)
			lastTop = cf
		end
		local top = lastTop
		ellip(m, Vector3.new(1.4, 1, 1.4), top, "#6b4f2a", M.Wood)
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2 + rnd() * 0.3
			local L1, L2 = r * (0.7 + rnd() * 0.2), r * (0.8 + rnd() * 0.3)
			local c = shade("#3a9d23", (rnd() - 0.5) * 0.2)
			local f1 = top * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, 0.25)
			P(m, Vector3.new(L1, 0.12, 0.95), f1 * CFrame.new(L1 / 2, 0, 0), c, M.Grass)
			local f2 = f1 * CFrame.new(L1, 0, 0) * CFrame.Angles(0, 0, -0.75)
			P(m, Vector3.new(L2, 0.1, 0.75), f2 * CFrame.new(L2 / 2, 0, 0), shade(c, -0.08), M.Grass)
		end
		for i = 1, 3 do
			local a = i / 3 * 6.28 + rnd()
			ball(m, 0.7, top * CFrame.new(math.cos(a) * 0.6, -0.55, math.sin(a) * 0.6), "#5b3a1e", M.Wood, false)
		end
	elseif k == "cactus" then
		local kind = rnd()
		local g = "#3a7d44"
		if kind < 0.6 then
			-- сагуаро: круглый ствол с куполом, руки загибаются вверх, светлые полоски-рёбра, цветок
			local h = r * 0.35 + 3.5
			local d = 1.25
			cyl(m, h, d, base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, 0), g, M.Grass, true)
			ball(m, d, base * CFrame.new(0, h, 0), g, M.Grass, false)
			for i = 0, 3 do
				local a = i / 4 * math.pi * 2
				P(m, Vector3.new(0.08, h * 0.95, 0.08), base * CFrame.new(math.cos(a) * d * 0.5, h / 2, math.sin(a) * d * 0.5), "#5aa363", M.Grass)
			end
			for _, sgn in ipairs({ -1, 1 }) do
				if rnd() < 0.8 then
					local ay = h * (0.35 + rnd() * 0.25)
					local out = 1.3 + rnd() * 0.6
					local up = 1.3 + rnd() * 1.4
					local ry = rnd() * 0.6
					local root = base * CFrame.Angles(0, ry, 0)
					cyl(m, out, d * 0.7, root * CFrame.new(sgn * out / 2, ay, 0) * CFrame.Angles(0, 0, math.pi / 2), g, M.Grass, false)
					ball(m, d * 0.7, root * CFrame.new(sgn * out, ay, 0), g, M.Grass, false)
					cyl(m, up, d * 0.7, root * CFrame.new(sgn * out, ay + up / 2, 0), g, M.Grass, false)
					ball(m, d * 0.7, root * CFrame.new(sgn * out, ay + up, 0), g, M.Grass, false)
				end
			end
			if rnd() < 0.5 then ball(m, 0.45, base * CFrame.new(0, h + 0.55, 0), rnd() < 0.5 and "#ff8fab" or "#ffd43b", M.SmoothPlastic, false) end
		elseif kind < 0.8 then
			-- шаровидный кактус с рёбрами и колючками
			local d = 1.4 + rnd() * 1.2
			ellip(m, Vector3.new(d, d * 1.15, d), base * CFrame.new(0, d * 0.5, 0), g, M.Grass)
			for i = 0, 5 do
				local a = i / 6 * math.pi
				ellip(m, Vector3.new(d * 1.02, d * 1.12, 0.12), base * CFrame.new(0, d * 0.5, 0) * CFrame.Angles(0, a, 0), "#5aa363", M.Grass)
			end
			ball(m, 0.4, base * CFrame.new(0, d * 1.08, 0), "#ff6b6b", M.SmoothPlastic, false)
			P(m, Vector3.new(d * 0.8, d, d * 0.8), base * CFrame.new(0, d * 0.5, 0), g, M.Grass, true).Transparency = 1
		else
			-- опунция: плоские «лепёшки» друг на друге
			local function pad(cf, s0, n)
				ellip(m, Vector3.new(s0, s0 * 1.3, 0.35), cf * CFrame.new(0, s0 * 0.6, 0), g, M.Grass)
				if n > 0 then
					for _, sgn in ipairs({ -1, 1 }) do
						if rnd() < 0.6 then pad(cf * CFrame.new(sgn * s0 * 0.35, s0 * 1.1, 0) * CFrame.Angles(0, rnd() * 0.8, sgn * -0.45), s0 * 0.8, n - 1) end
					end
				end
			end
			pad(base * CFrame.Angles(0, rnd() * 3, 0), 1.6, 2)
			P(m, Vector3.new(1.2, 2.4, 1.2), base * CFrame.new(0, 1.2, 0), g, M.Grass, true).Transparency = 1
		end
	elseif k == "mesa" then
		local h = 4 + r * 0.25
		P(m, Vector3.new(r * 1.8, h, r * 1.6), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, rnd() * 3, 0), "#b5502e", M.Sandstone, true)
		P(m, Vector3.new(r * 1.4, 1.2, r * 1.2), base * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(0, rnd() * 3, 0), "#c86a3e", M.Sandstone, true)
		P(m, Vector3.new(r * 1.85, 0.5, r * 1.65), base * CFrame.new(0, h * 0.45, 0) * CFrame.Angles(0, rnd() * 3, 0), "#9c4426", M.Sandstone, false)
	elseif k == "bush" or k == "bigbush" then
		-- куст: несколько круглых пучков листвы, у больших — ягоды или цветы
		local s0 = r * (k == "bigbush" and 0.75 or 0.95)
		local leaf = shade(t.dark and "#2f6b2f" or "#3f7f35", (rnd() - 0.5) * 0.15)
		local n = k == "bigbush" and 7 or 4
		for i = 1, n do
			local a, d = i / n * 6.28 + rnd(), i == 1 and 0 or s0 * (0.35 + rnd() * 0.3)
			local ss = s0 * (i == 1 and 1 or (0.6 + rnd() * 0.3))
			ellip(m, Vector3.new(ss * 1.2, ss * 0.95, ss * 1.2), base * CFrame.new(math.cos(a) * d, ss * 0.4, math.sin(a) * d), shade(leaf, (rnd() - 0.5) * 0.14), M.Grass)
		end
		if k == "bigbush" or rnd() < 0.3 then
			local berry = Util.pick({ "#e03131", "#ffffff", "#ff8fab", "#7048e8" })
			for _ = 1, 6 do
				local a, d = rnd() * 6.28, s0 * (0.45 + rnd() * 0.35)
				ball(m, 0.3, base * CFrame.new(math.cos(a) * d, s0 * (0.3 + rnd() * 0.6), math.sin(a) * d), berry, M.SmoothPlastic, false).CastShadow = false
			end
		end
		if k == "bigbush" then P(m, Vector3.new(s0 * 1.3, s0, s0 * 1.3), base * CFrame.new(0, s0 * 0.5, 0), leaf, M.Grass, true).Transparency = 1 end
	elseif k == "drybush" then
		-- сухой куст перекати-поле: веточки во все стороны и немного сухой листвы
		local s0 = r * 0.9
		for i = 1, 7 do
			local a = rnd() * 6.28
			local from = (base * CFrame.new(0, 0.1, 0)).Position
			limb(m, from, from + Vector3.new(math.cos(a) * s0 * 0.6, s0 * (0.3 + rnd() * 0.5), math.sin(a) * s0 * 0.6), 0.1, "#7a5a33", M.Wood)
		end
		ellip(m, Vector3.new(s0, s0 * 0.6, s0), base * CFrame.new(0, s0 * 0.3, 0), "#a88a52", M.Grass).Transparency = 0.3
	elseif k == "spire" then
		-- страшный шпиль из чёрного камня: изломанный, с острыми гранями, в трещинах светится лава
		local h = r * 1.8
		local tilt = CFrame.Angles((rnd() - 0.5) * 0.25, rnd() * 3, (rnd() - 0.5) * 0.25)
		local cf = base * tilt
		local w0 = r * 0.95
		for i = 0, 3 do
			local hh = h * (0.36 - i * 0.05)
			local ww = w0 * (1 - i * 0.22)
			P(m, Vector3.new(ww, hh, ww * 0.85), cf * CFrame.new(0, hh / 2, 0) * CFrame.Angles(0, i * 0.7, 0), shade("#1d1718", (i % 2) * 0.06), M.Basalt, true)
			cf = cf * CFrame.new((rnd() - 0.5) * ww * 0.2, hh * 0.92, (rnd() - 0.5) * ww * 0.2) * CFrame.Angles((rnd() - 0.5) * 0.2, 0, (rnd() - 0.5) * 0.2)
		end
		wedge(m, Vector3.new(w0 * 0.3, h * 0.3, w0 * 0.4), cf * CFrame.new(0, h * 0.14, 0), "#140f10", M.Basalt)
		-- острые выступы
		for _ = 1, 3 do
			local a = rnd() * 6.28
			local y = h * (0.15 + rnd() * 0.4)
			local from = (base * tilt * CFrame.new(math.cos(a) * w0 * 0.4, y, math.sin(a) * w0 * 0.4)).Position
			limb(m, from, from + Vector3.new(math.cos(a) * w0 * 0.7, r * 0.5, math.sin(a) * w0 * 0.7), 0.5, "#1d1718", M.Basalt)
		end
		for i = 1, 2 do
			local vein = P(m, Vector3.new(0.25, h * 0.55, 0.3), base * tilt * CFrame.new(w0 * 0.49 * (i == 1 and 1 or -1), h * 0.3, (rnd() - 0.5) * w0 * 0.5) * CFrame.Angles(0, 0, (rnd() - 0.5) * 0.4), "#ff4d00", M.Neon)
			if i == 1 and rnd() < 0.4 then
				local l = Instance.new("PointLight")
				l.Color = color("#ff5a1a")
				l.Range = 12
				l.Brightness = 1.4
				l.Parent = vein
			end
		end
	elseif k == "deadtree" then
		-- мёртвое дерево: кривой чёрный ствол и острые голые ветки
		local th = r * 2.4 + 3
		local tc = t.dragon and "#2a2424" or "#4a4440"
		local cf = base
		for i = 0, 2 do
			local L = th / 3
			cf = cf * CFrame.Angles((rnd() - 0.5) * 0.35, 0, (rnd() - 0.5) * 0.35)
			cyl(m, L * 1.05, 0.85 - i * 0.18, cf * CFrame.new(0, L / 2, 0), tc, M.Wood, i == 0)
			cf = cf * CFrame.new(0, L, 0)
		end
		for i = 1, 5 do
			local from = (base * CFrame.new(0, th * (0.4 + i * 0.1), 0)).Position
			local a = i * 2.1 + rnd()
			local mid = from + Vector3.new(math.cos(a) * r * 0.6, r * (0.2 + rnd() * 0.3), math.sin(a) * r * 0.6)
			limb(m, from, mid, 0.3, tc, M.Wood)
			limb(m, mid, mid + Vector3.new(math.cos(a + 0.6) * r * 0.4, r * (0.3 + rnd() * 0.3), math.sin(a + 0.6) * r * 0.4), 0.15, tc, M.Wood)
		end
	elseif k == "bigbone" or k == "smallbone" then
		-- кость как настоящая: длинное тело кости, сужается к середине, на концах — по два мыщелка
		local L = r * (k == "bigbone" and 1.6 or 1)
		local d = k == "bigbone" and 1.3 or 0.32
		local bc = shade("#ece6d6", (rnd() - 0.5) * 0.12)
		local cf = base * CFrame.new(0, d * 0.35, 0) * CFrame.Angles(0, rnd() * 3, (rnd() - 0.5) * 0.25)
		cyl(m, L * 0.55, d * 0.8, cf, bc)
		for _, sx in ipairs({ -1, 1 }) do
			cyl(m, L * 0.25, d, cf * CFrame.new(sx * L * 0.37, 0, 0), bc)
			for _, sz in ipairs({ -1, 1 }) do
				ball(m, d * 1.25, cf * CFrame.new(sx * L / 2, 0, sz * d * 0.45), shade(bc, -0.04))
			end
		end
	elseif k == "ribcage" then
		-- скелет: позвоночник и изогнутые рёбра, наполовину ушедшие в землю
		local L = r * 1.6
		local bc = t.dragon and "#d8cfbd" or "#ece6d6"
		local cf = base * CFrame.Angles(0, rnd() * 6.28, 0) * CFrame.Angles(0, 0, (rnd() - 0.5) * 0.12)
		local spineY = r * 0.85
		for i = 0, 7 do
			local x = -L / 2 + i * L / 7
			P(m, Vector3.new(L / 9, 0.8, 0.9), cf * CFrame.new(x, spineY, 0), shade(bc, (i % 2) * -0.05))
		end
		local ribs = 6
		for i = 0, ribs - 1 do
			local x = -L * 0.35 + i * L * 0.7 / (ribs - 1)
			local R0 = r * (0.85 - math.abs(i - ribs / 2 + 0.5) * 0.08)
			for _, sz in ipairs({ -1, 1 }) do
				local a0 = (cf * CFrame.new(x, spineY, 0)).Position
				local a1 = (cf * CFrame.new(x, spineY - R0 * 0.25, sz * R0 * 0.6)).Position
				local a2 = (cf * CFrame.new(x + L * 0.02, spineY - R0 * 0.8, sz * R0 * 0.7)).Position
				local a3 = (cf * CFrame.new(x + L * 0.04, -0.3, sz * R0 * 0.45)).Position
				limb(m, a0, a1, 0.38, bc)
				limb(m, a1, a2, 0.34, bc)
				limb(m, a2, a3, 0.3, bc)
			end
		end
	elseif k == "bigskull" or k == "dragonskull" then
		-- череп: свод, длинная морда, глазницы, ноздри, челюсть с зубами; у дракона — рога и клыки
		local dragon = k == "dragonskull"
		local s0 = r * (dragon and 0.75 or 0.9)
		local bc = dragon and "#d6ccb8" or "#ece6d6"
		local cf = base * CFrame.Angles(0, rnd() * 6.28, 0) * CFrame.Angles((rnd() - 0.5) * 0.2, 0, -0.12)
		ellip(m, Vector3.new(s0 * 1.2, s0 * 0.95, s0 * 1.05), cf * CFrame.new(-s0 * 0.25, s0 * 0.45, 0), bc)
		P(m, Vector3.new(s0 * 1.3, s0 * 0.5, s0 * 0.62), cf * CFrame.new(s0 * 0.75, s0 * 0.35, 0) * CFrame.Angles(0, 0, -0.08), shade(bc, -0.04), M.SmoothPlastic)
		P(m, Vector3.new(s0 * 1.1, s0 * 0.18, s0 * 0.55), cf * CFrame.new(s0 * 0.6, s0 * 0.05, 0), shade(bc, -0.1))
		P(m, Vector3.new(s0 * 1.6, s0 * 0.9, s0 * 1.0), cf * CFrame.new(0.1 * s0, s0 * 0.45, 0), bc, M.SmoothPlastic, true).Transparency = 1
		for _, sz in ipairs({ -1, 1 }) do
			ellip(m, Vector3.new(s0 * 0.34, s0 * 0.3, s0 * 0.12), cf * CFrame.new(s0 * 0.05, s0 * 0.6, sz * s0 * 0.5), "#141010")
			ball(m, s0 * 0.12, cf * CFrame.new(s0 * 1.38, s0 * 0.42, sz * s0 * 0.13), "#1a1412")
			if dragon then
				local a = (cf * CFrame.new(-s0 * 0.5, s0 * 0.85, sz * s0 * 0.35)).Position
				local b = (cf * CFrame.new(-s0 * 1.2, s0 * 1.4, sz * s0 * 0.6)).Position
				local c = (cf * CFrame.new(-s0 * 1.7, s0 * 1.3, sz * s0 * 0.5)).Position
				limb(m, a, b, s0 * 0.16, "#5c5f66")
				limb(m, b, c, s0 * 0.1, "#4a4d54")
			end
		end
		for i = 0, (dragon and 4 or 5) do
			local x = s0 * (0.3 + i * 0.2)
			for _, sz in ipairs({ -1, 1 }) do
				if dragon then
					wedge(m, Vector3.new(0.08, s0 * 0.3, s0 * 0.12), cf * CFrame.new(x, s0 * 0.02, sz * s0 * 0.26) * CFrame.Angles(math.pi, 0, 0), "#f8f4ea")
				else
					P(m, Vector3.new(s0 * 0.12, s0 * 0.12, s0 * 0.08), cf * CFrame.new(x, s0 * 0.12, sz * s0 * 0.27), "#f8f4ea")
				end
			end
		end
	elseif k == "lavacrack" then
		-- светящаяся трещина в земле: ломаная полоса лавы с тёмными краями
		local cf = base * CFrame.Angles(0, rnd() * 6.28, 0)
		local len = r * 1.6
		local n = 4
		local pts = {}
		for i = 0, n do table.insert(pts, (cf * CFrame.new(-len / 2 + len * i / n, 0.06, (rnd() - 0.5) * r * 0.5)).Position) end
		for i = 1, n do
			local a, b = pts[i], pts[i + 1]
			local L = (b - a).Magnitude
			local mid = (a + b) / 2
			local p = P(m, Vector3.new(0.35 + rnd() * 0.3, 0.12, L + 0.3), CFrame.lookAt(mid, b), "#ff5a00", M.Neon)
			P(m, Vector3.new(1.2, 0.08, L + 0.5), CFrame.lookAt(mid - Vector3.new(0, 0.03, 0), b - Vector3.new(0, 0.03, 0)), "#120c0c", M.Basalt)
			if i == 2 then
				local l = Instance.new("PointLight")
				l.Color = color("#ff4d00")
				l.Range = 10
				l.Brightness = 1.2
				l.Parent = p
			end
		end
	elseif k == "vent" then
		-- дымящееся жерло: чёрный каменный конус, внутри светится, идёт дым и летят искры
		local s0 = r
		P(m, Vector3.new(s0 * 1.6, s0 * 0.35, s0 * 1.6), base * CFrame.new(0, s0 * 0.1, 0) * CFrame.Angles(0, rnd() * 3, 0), "#1f1a1b", M.Basalt, true)
		P(m, Vector3.new(s0 * 1.1, s0 * 0.3, s0 * 1.1), base * CFrame.new(0, s0 * 0.4, 0) * CFrame.Angles(0, rnd() * 3 + 0.4, 0), "#2a2224", M.Basalt, true)
		local hot = ellip(m, Vector3.new(s0 * 0.6, 0.25, s0 * 0.6), base * CFrame.new(0, s0 * 0.56, 0), "#ff6a00", M.Neon)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Rate = 4
		smoke.Lifetime = NumberRange.new(4, 6)
		smoke.Speed = NumberRange.new(3, 5)
		smoke.SpreadAngle = Vector2.new(12, 12)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Size = NumberSequence.new(1.2, 5)
		smoke.Transparency = NumberSequence.new(0.35, 1)
		smoke.Color = ColorSequence.new(color("#3a3333"), color("#6c6464"))
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Parent = hot
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 2
		sparks.Lifetime = NumberRange.new(0.8, 1.6)
		sparks.Speed = NumberRange.new(5, 9)
		sparks.SpreadAngle = Vector2.new(20, 20)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.LightEmission = 1
		sparks.Acceleration = Vector3.new(0, -8, 0)
		sparks.Size = NumberSequence.new(0.25, 0)
		sparks.Color = ColorSequence.new(color("#ffd166"), color("#ff3d00"))
		sparks.Parent = hot
		local l = Instance.new("PointLight")
		l.Color = color("#ff5a1a")
		l.Range = 14
		l.Brightness = 1.5
		l.Parent = hot
	elseif k == "grass" then
		for i = 1, 3 do
			P(m, Vector3.new(0.25, 1.4 + i * 0.3, 0.25), base * CFrame.new((rnd() - 0.5) * 1.5, 0.8, (rnd() - 0.5) * 1.5) * CFrame.Angles(rnd() * 0.4, 0, rnd() * 0.4), "#b5a642", M.Grass)
		end
	elseif k == "tuft" or k == "pinktuft" then
		-- кустик травы: тонкие травинки, наклонённые в разные стороны
		local gc = k == "pinktuft" and "#f08ac4" or (rnd() < 0.5 and "#4f9a3a" or "#5fae43")
		local n = 4
		for i = 1, n do
			local a = i / n * 6.28 + rnd()
			local h = 0.9 + rnd() * 1.1
			local p = P(m, Vector3.new(0.12, h, 0.3), base * CFrame.new(math.cos(a) * 0.25, h / 2 - 0.1, math.sin(a) * 0.25) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, 0.25 + rnd() * 0.3), shade(gc, (rnd() - 0.5) * 0.2), M.Grass)
			p.CastShadow = false
		end
		if k == "pinktuft" and rnd() < 0.35 then
			ball(m, 0.25, base * CFrame.new(0, 1.3, 0), "#fff0f6", M.Neon, false):SetAttribute("Glow12", true)
		end
	elseif k == "fern" then
		-- папоротник: длинные изогнутые вайи из центра
		for i = 1, 6 do
			local a = i / 6 * 6.28 + rnd() * 0.4
			local f1 = base * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, 0.7)
			local L = 1.4 + rnd() * 0.6
			local p1 = ellip(m, Vector3.new(L, 0.08, 0.55), f1 * CFrame.new(L / 2, 0, 0), shade("#2f7d32", (rnd() - 0.5) * 0.15), M.Grass)
			p1.CastShadow = false
			local p2 = ellip(m, Vector3.new(L * 0.8, 0.07, 0.45), f1 * CFrame.new(L, 0, 0) * CFrame.Angles(0, 0, -0.8) * CFrame.new(L * 0.4, 0, 0), shade("#3a8f3c", (rnd() - 0.5) * 0.15), M.Grass)
			p2.CastShadow = false
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

local buildItemRaw
-- насколько утопить в землю (мелкое — почти не утапливаем, иначе травинки и кости уходят под землю)
local SINK = { tuft = 0.08, pinktuft = 0.08, fern = 0.05, lavacrack = -0.03, smallbone = 0.03, bigbone = 0.25, ribcage = 0.3, grass = 0.1, bush = 0.2, bigbush = 0.25, drybush = 0.1 }
-- каждый предмет ставим на высоту рельефа в своей точке (чуть утапливаем, чтобы на склоне не висел)
local function buildItem(m, it)
	local o = it.item
	local sub = Instance.new("Model")
	sub.Name = it.kind
	buildItemRaw(sub, it)
	if not o.sky and it.kind ~= "vine" then
		local sink = (it.kind == "tree") and (SINK[o.kind] or 0.5) or (it.kind == "flower" and 0.05 or 0.15)
		sub:TranslateBy(Vector3.new(0, World.heightAt(o.x, o.y) - sink, 0))
	end
	sub.Parent = m
	if it.kind == "shroom" then it.home = sub end
end
buildItemRaw = function(m, it)
	local o = it.item
	if it.kind == "tree" then
		makeTree(m, o)
	elseif it.kind == "flower" then
		buildFlower(m, o)
	elseif it.kind == "crystal" then
		-- друза кристаллов как настоящая: шестигранные столбики с острой верхушкой, растут из одного
		-- основания в разные стороны; полупрозрачное стекло, внутри светится сердцевина
		local rnd = Util.rng((o.s or 1) + 7)
		local base = CFrame.new(o.x * K, 0, o.y * K) * CFrame.Angles(0, rnd() * 6.28, 0)
		local n = 3 + math.floor(rnd() * 3)
		local light
		ellip(m, Vector3.new(1.6, 0.5, 1.4), base * CFrame.new(0, 0.1, 0), "#3d3a44", M.Slate)
		for i = 1, n do
			local h = (1.2 + o.h * 1.2) * (i == 1 and 1 or (0.45 + rnd() * 0.45))
			local R = (i == 1 and 0.42 or 0.24 + rnd() * 0.14) * (0.8 + o.h * 0.2)
			local a = i == 1 and 0 or (i / n * 6.28 + rnd() * 0.5)
			local tiltA = i == 1 and (rnd() - 0.5) * 0.25 or (0.35 + rnd() * 0.5)
			local cf = base * CFrame.Angles(0, a, 0) * CFrame.new(i == 1 and 0 or 0.25, 0, 0) * CFrame.Angles(0, 0, -tiltA) * CFrame.new(0, h / 2, 0)
			for j = 0, 2 do
				local pp = P(m, Vector3.new(R * 1.732, h, R), cf * CFrame.Angles(0, j * math.pi / 3, 0), o.c, M.Glass, false, 0.3)
				pp.Reflectance = 0.15
			end
			-- острая верхушка: две пары клиньев (пирамидка)
			for j = 0, 1 do
				for _, sg in ipairs({ -1, 1 }) do
					local w = Instance.new("WedgePart")
					w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch = true, false, false, false
					w.Size = Vector3.new(R * 1.6, R * 1.6, R * 0.8)
					w.Color = color(o.c)
					w.Material = M.Glass
					w.Transparency = 0.3
					w.CFrame = cf * CFrame.new(0, h / 2 + R * 0.8, 0) * CFrame.Angles(0, j * math.pi / 2 + (sg > 0 and math.pi or 0), 0) * CFrame.new(0, 0, -R * 0.4)
					w.Parent = m
				end
			end
			local core = P(m, Vector3.new(R * 0.6, h * 0.85, R * 0.6), cf, Util.mix(o.c, "#ffffff", 0.2), M.Neon)
			if i == 1 then light = core end
		end
		if light and (o.s or 0) % 3 == 0 then
			local l = Instance.new("PointLight")
			l.Color = light.Color
			l.Range = 12
			l.Brightness = 1.2
			l.Parent = light
		end
	elseif it.kind == "vine" then
		local L = o.len * 0.5
		P(m, Vector3.new(0.2, L, 0.2), CFrame.new(o.x * K, World.SKY_Y - L / 2, o.y * K), "#2f9e44", M.Grass)
	elseif it.kind == "shroom" then
		local cap = o.type == "amanita" and "#e03131" or o.type == "chanterelle" and "#f59f00" or o.type == "glow" and "#7df9ff" or o.type == "violet" and "#c77dff" or "#8b5a2b"
		local mdl = Instance.new("Model")
		mdl.Name = "Shroom"
		P(mdl, Vector3.new(0.25, 0.5, 0.25), CFrame.new(o.x * K, 0.25, o.y * K), "#f8f4ea")
		local capP = ellip(mdl, Vector3.new(0.75, 0.4, 0.75), CFrame.new(o.x * K, 0.55, o.y * K), cap, (o.type == "glow" or o.type == "violet") and M.Neon or M.SmoothPlastic)
		if o.type == "glow" or o.type == "violet" then capP:SetAttribute("Glow12", true) end
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
