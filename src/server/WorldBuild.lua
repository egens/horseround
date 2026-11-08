--[[
	Построение статичного мира на сервере: рельеф (Terrain) по биомам, озёра и море,
	горы с пещерой, постройки фермы, деревня, рынок, острова, небесные острова, железная дорога.
	Деревья, камни, цветы и грибы рисует клиент (Decor) — их много, и так быстрее.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)

local WB = {}
local K = World.K
local T = workspace.Terrain
local root
local lamps = {}
WB.lamps = lamps
local ops = 0
local function yieldSome()
	ops += 1
	if ops % 400 == 0 then task.wait() end
end

local M = Enum.Material
local function col(h) return Util.color(h) end

-- деталь
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or M.SmoothPlastic
	p.Color = props.color and col(props.color) or Color3.new(1, 1, 1)
	p.Size = props.size
	-- всё ставим на настоящую поверхность рельефа (World.GROUND замерен после постройки рельефа)
	p.CFrame = CFrame.new(0, World.GROUND, 0) * props.cframe
	p.CanCollide = props.collide ~= false
	p.CastShadow = props.shadow ~= false
	if props.transparency then p.Transparency = props.transparency end
	if props.shape then p.Shape = props.shape end
	p.Name = props.name or "Part"
	p.Parent = props.parent or root
	return p
end
WB.part = part
-- прямоугольник карты (пиксели) → коробка в стадах
local function rectBox(r, y0, h, color, material, collide, parent)
	return part({
		size = Vector3.new(math.max(0.2, r.w * K), h, math.max(0.2, r.h * K)),
		cframe = CFrame.new((r.x + r.w / 2) * K, y0 + h / 2, (r.y + r.h / 2) * K),
		color = color, material = material, collide = collide, parent = parent,
	})
end
-- отрезок между двумя точками карты
local function segment(x1, y1, x2, y2, y0, h, thick, color, material, collide, parent, transparency)
	local a, b = Vector3.new(x1 * K, y0 + h / 2, y1 * K), Vector3.new(x2 * K, y0 + h / 2, y2 * K)
	local len = (b - a).Magnitude
	if len < 0.05 then return nil end
	return part({
		size = Vector3.new(thick, h, len), cframe = CFrame.lookAt((a + b) / 2, b),
		color = color, material = material, collide = collide, parent = parent, transparency = transparency, shadow = transparency == nil,
	})
end
local function label(text, x, y, h, color, maxDist, size)
	local anchor = part({ size = Vector3.new(0.2, 0.2, 0.2), cframe = CFrame.new(x * K, h, y * K), transparency = 1, collide = false, name = "Label" })
	anchor.CanQuery = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 40)
	bb.MaxDistance = maxDist or 220
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBold
	t.TextSize = size or 22
	t.TextColor3 = col(color or "#3b2a1a")
	t.TextStrokeColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.Parent = bb
	return anchor
end
WB.label = label

--[[ ---------- рельеф ---------- ]]
local GROUND = {
	farm = M.Grass, field = M.Grass, village = M.Grass, farmland = M.Grass, lake = M.Grass, grotto = M.Grass, market = M.Cobblestone,
	forest = M.LeafyGrass, foxwood = M.LeafyGrass, deepforest = M.LeafyGrass, mushroom = M.Salt,
	desert = M.Sand, tundra = M.Snow, mountain = M.Rock, cave = M.Slate, grottocave = M.Slate, dragonrock = M.Basalt, steppe = M.Ground,
	i1 = M.Grass, i2 = M.Grass, i3 = M.Grass, i4 = M.Sandstone,
}
local measureGround
local function setColors()
	T:SetMaterialColor(M.Grass, col("#86b84f"))
	T:SetMaterialColor(M.LeafyGrass, col("#4f8a3a"))
	T:SetMaterialColor(M.Salt, col("#9b87c9"))
	T:SetMaterialColor(M.Sand, col("#e8cf8f"))
	T:SetMaterialColor(M.Snow, col("#f4f8fb"))
	T:SetMaterialColor(M.Rock, col("#8a8580"))
	T:SetMaterialColor(M.Slate, col("#4a4744"))
	T:SetMaterialColor(M.Basalt, col("#3b3436"))
	T:SetMaterialColor(M.Ground, col("#b9a35f"))
	T:SetMaterialColor(M.Mud, col("#b08d5c"))
	T:SetMaterialColor(M.Sandstone, col("#7a3b2e"))
	T:SetMaterialColor(M.Cobblestone, col("#b8a98f"))
	T:SetMaterialColor(M.Glacier, col("#cfe9ff"))
	T:SetMaterialColor(M.CrackedLava, col("#ff6a00"))
	-- декоративная трава прячет низ лошадей, копыт и построек — выключаем
	T.Decoration = false
	T.WaterColor = col("#3f8fc0")
	T.WaterTransparency = 0.35
	T.WaterReflectance = 0.6
	T.WaterWaveSize = 0.08
end

local function buildTerrain()
	setColors()
	local W, H = World.W, World.H
	local step = 160
	-- суша по биомам
	for x = 0, W - 1, step do
		for y = 0, H - 1, step do
			local cx, cy = x + step / 2, y + step / 2
			local reg = World.regionAt(cx, cy)
			-- море и острова — точнее ниже
			local island = string.sub(reg, 1, 1) == "i" and #reg == 2
			if reg ~= "sea" and not island then
				T:FillBlock(CFrame.new(cx * K, -6, cy * K), Vector3.new(step * K, 12, step * K), GROUND[reg] or M.Grass)
			end
			yieldSome()
		end
	end
	-- море: полосами от берега, потом острова клетками помельче
	local ystep = 80
	for y = 0, H - 1, ystep do
		local cx = World.coastX(y + ystep / 2)
		local x0 = cx - 40
		T:FillBlock(CFrame.new(((x0 + W) / 2) * K, -6, (y + ystep / 2) * K), Vector3.new((W - x0) * K + 2, 12, ystep * K), M.Water)
		yieldSome()
	end
	local c8 = 80
	for _, I in ipairs(World.ISLANDS) do
		local mat = I.bone and M.Sandstone or M.Grass
		for x = I.x - I.rx * 1.3, I.x + I.rx * 1.3, c8 do
			for y = I.y - I.ry * 1.3, I.y + I.ry * 1.3, c8 do
				local q = World.blobInfo(I, x, y)
				if q.d < q.R then
					local edge = q.d > q.R - 140 / q.unit
					T:FillBlock(CFrame.new(x * K, -6, y * K), Vector3.new(c8 * K, 12, c8 * K), (edge and not I.bone) and M.Sand or mat)
				end
				yieldSome()
			end
		end
	end
	-- озёра
	for _, L in ipairs(World.LAKES) do
		for x = L.x - L.rx * 1.4, L.x + L.rx * 1.4, c8 / 2 do
			for y = L.y - L.ry * 1.4, L.y + L.ry * 1.4, c8 / 2 do
				if World.inBlob(L, x, y) then
					local cf = CFrame.new(x * K, -3, y * K)
					local size = Vector3.new(c8 / 2 * K, 6, c8 / 2 * K)
					if L.lava then
						T:FillBlock(CFrame.new(x * K, -2, y * K), Vector3.new(c8 / 2 * K, 4, c8 / 2 * K), M.CrackedLava)
					elseif L.ice then
						T:FillBlock(CFrame.new(x * K, -2, y * K), Vector3.new(c8 / 2 * K, 4, c8 / 2 * K), M.Glacier)
					else
						T:FillBlock(cf, size, M.Water)
					end
				end
				yieldSome()
			end
		end
	end
	-- дороги
	for _, r in ipairs(World.ROADS) do
		for i = 1, #r - 1 do
			local a = Vector3.new(r[i][1] * K, -2, r[i][2] * K)
			local b = Vector3.new(r[i + 1][1] * K, -2, r[i + 1][2] * K)
			local len = (b - a).Magnitude
			if len > 0.1 then
				T:FillBlock(CFrame.lookAt((a + b) / 2, b), Vector3.new(6, 4, len + 3), M.Mud)
			end
			yieldSome()
		end
	end
	-- манеж — песок, площадь деревни — брусчатка
	local A = World.ARENA
	T:FillBlock(CFrame.new((A.x + A.w / 2) * K, -2, (A.y + A.h / 2) * K), Vector3.new(A.w * K, 4, A.h * K), M.Sand)
	local Sq = World.SQUARE
	T:FillCylinder(CFrame.new(Sq.x * K, -2, Sq.y * K), 4, Sq.ry * K, M.Cobblestone)
	-- горы и пещера: каменные стены, потолок
	for _, w in ipairs(World.CAVE_WALLS) do
		T:FillBlock(CFrame.new((w.x + w.w / 2) * K, 22, (w.y + w.h / 2) * K), Vector3.new(w.w * K, 44, w.h * K), M.Rock)
		yieldSome()
	end
	for _, w in ipairs(World.CAVE_INNER_WALLS) do
		T:FillBlock(CFrame.new((w.x + w.w / 2) * K, 18, (w.y + w.h / 2) * K), Vector3.new(w.w * K, 36, w.h * K), M.Slate)
	end
	local C = World.CAVE
	T:FillBlock(CFrame.new((C.x + C.w / 2) * K, 36, (C.y + C.h / 2) * K), Vector3.new(C.w * K, 8, C.h * K), M.Rock)
	-- вершины гор
	local Mo = World.MOUNTAIN
	local rr = Util.rng(77)
	for _ = 1, 40 do
		local x, y = Mo.x + rr() * Mo.w, Mo.y + rr() * Mo.h
		local h = 20 + rr() * 40
		T:FillBall(Vector3.new(x * K, 38 + h * 0.4, y * K), 14 + rr() * 18, rr() < 0.3 and M.Snow or M.Rock)
		yieldSome()
	end
	-- маленькие пещерки: каменный потолок
	for _, g in ipairs(World.GROTTOS) do
		T:FillCylinder(CFrame.new(g.x * K, 15, g.y * K), 4, g.r * K + 4, M.Rock)
		T:FillCylinder(CFrame.new(g.x * K, -2, g.y * K), 4, g.r * K, M.Slate)
	end
	-- небесные острова
	for _, I in ipairs(World.SKY_ISLANDS) do
		for x = I.x - I.rx * 1.2, I.x + I.rx * 1.2, c8 do
			for y = I.y - I.ry * 1.2, I.y + I.ry * 1.2, c8 do
				local q = World.blobInfo(I, x, y)
				if q.d < q.R then
					T:FillBlock(CFrame.new(x * K, World.SKY_Y - 4, y * K), Vector3.new(c8 * K, 8, c8 * K), M.Grass)
					local depth = 8 + (1 - q.d / q.R) * 26
					T:FillBlock(CFrame.new(x * K, World.SKY_Y - 8 - depth / 2, y * K), Vector3.new(c8 * K, depth, c8 * K), M.Rock)
				end
				yieldSome()
			end
		end
	end
end

--[[ ---------- невидимые границы: вода, край мира ---------- ]]
local function buildBarriers()
	local folder = Instance.new("Folder")
	folder.Name = "Barriers"
	folder.Parent = root
	local function wall(x1, y1, x2, y2, h, y0)
		local p = segment(x1, y1, x2, y2, y0 or -2, h or 14, 1.2, "#ffffff", M.SmoothPlastic, true, folder, 1)
		if p then
			p.CanQuery = false
			p.CastShadow = false
		end
	end
	for _, L in ipairs(World.LAKES) do
		local pts = World.blobPoly(L, 6, 40)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			wall(a.x, a.y, b.x, b.y, 12)
		end
		yieldSome()
	end
	-- берег большой земли
	local prev = nil
	for y = -200, World.H + 200, 160 do
		local p = { x = World.coastX(y) - 8, y = y }
		if prev then wall(prev.x, prev.y, p.x, p.y, 14) end
		prev = p
	end
	-- острова: с острова на большую землю — только на лодке
	for _, I in ipairs(World.ISLANDS) do
		local pts = World.blobPoly(I, -10, 64)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			wall(a.x, a.y, b.x, b.y, 14)
		end
	end
	-- края мира (над южным краем можно перелететь к небесным островам)
	local W, H = World.W, World.H
	wall(0, 0, W, 0, 80)
	wall(0, 0, 0, H, 80)
	wall(W, 0, W, H, 80)
	wall(0, H, W, H, 14)
	-- небесные острова: невидимые перила по краю (мосты остаются открытыми)
	for _, I in ipairs(World.SKY_ISLANDS) do
		local pts = World.blobPoly(I, -8, 56)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			if not World.onBridge(mx, my, -30) then wall(a.x, a.y, b.x, b.y, 4, World.SKY_Y) end
		end
	end
end

--[[ ---------- постройки ---------- ]]
local WOOD, DARKWOOD, WHITE = "#8a5a32", "#5c3d1e", "#f6f3ec"

local function fenceRect(s, parent, height, color)
	height = height or 3.2
	color = color or WOOD
	local long = s.w >= s.h
	local len = (long and s.w or s.h) * K
	local cx, cz = (s.x + s.w / 2) * K, (s.y + s.h / 2) * K
	local dirCF = long and CFrame.new(cx, 0, cz) or CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.pi / 2, 0)
	for _, yy in ipairs({ height * 0.45, height * 0.9 }) do
		part({ size = Vector3.new(len, 0.35, 0.35), cframe = dirCF * CFrame.new(0, yy, 0), color = color, material = M.Wood, parent = parent })
	end
	local n = math.max(1, math.floor(len / 8))
	for i = 0, n do
		local off = -len / 2 + len * i / n
		part({ size = Vector3.new(0.5, height, 0.5), cframe = dirCF * CFrame.new(off, height / 2, 0), color = DARKWOOD, material = M.Wood, parent = parent })
	end
	-- невидимая стенка, чтобы не перелезть
	local inv = part({ size = Vector3.new(len, 6, 0.8), cframe = dirCF * CFrame.new(0, 3, 0), transparency = 1, parent = parent })
	inv.CastShadow = false
	inv.CanQuery = false
end

local function roofOver(r, y, color, overhang)
	overhang = overhang or 1
	return part({ size = Vector3.new(r.w * K + overhang * 2, 0.6, r.h * K + overhang * 2), cframe = CFrame.new((r.x + r.w / 2) * K, y, (r.y + r.h / 2) * K), color = color, material = M.WoodPlanks })
end

local function lamp(x, y, parent)
	local base = Vector3.new(x * K, 0, y * K)
	part({ size = Vector3.new(0.5, 7, 0.5), cframe = CFrame.new(base + Vector3.new(0, 3.5, 0)), color = "#2b2b2b", material = M.Metal, parent = parent })
	local bulb = part({ size = Vector3.new(1.2, 1.2, 1.2), cframe = CFrame.new(base + Vector3.new(0, 7.4, 0)), color = "#ffe9a8", material = M.SmoothPlastic, parent = parent, collide = false })
	bulb.Name = "LampBulb"
	local light = Instance.new("PointLight")
	light.Range = 34
	light.Brightness = 2
	light.Color = col("#ffd88a")
	light.Shadows = false
	light.Enabled = false
	light.Parent = bulb
	table.insert(lamps, bulb)
	return bulb
end
WB.lamp = lamp

local function buildFarm()
	local f = Instance.new("Folder")
	f.Name = "Farm"
	f.Parent = root
	-- конюшня
	local S = World.STABLE
	for _, s in ipairs(World.SOLIDS) do
		if s.kind == "stable" and s.x < World.SEA.x - 400 then rectBox(s, 0, 9, "#c8a27a", M.WoodPlanks, true, f) end
	end
	roofOver(S, 9.3, "#a33a2a", 1.5).Parent = f
	for i = 0, 19 do
		local r = World.stallRect(i)
		if i % 10 ~= 0 then
			part({ size = Vector3.new(0.4, 4.5, r.h * K), cframe = CFrame.new(r.x * K, 2.25, (r.y + r.h / 2) * K), color = WOOD, material = M.Wood, parent = f })
		end
		-- кормушка у задней стены
		local back = r.row == 1 and (r.y + r.h - 12) or (r.y + 12)
		part({ size = Vector3.new(3, 1, 1.2), cframe = CFrame.new((r.x + r.w / 2) * K, 2.5, back * K), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	end
	label("🐴 КОНЮШНЯ", S.x + S.w / 2, S.y - 10, 13, "#3b2a1a", 300, 26)
	-- манеж
	local A = World.ARENA
	for _, s in ipairs(World.SOLIDS) do
		if s.kind == "fence" and s.x < World.SEA.x - 400 then fenceRect(s, f) end
		yieldSome()
	end
	for L, p in pairs(World.LETTERS) do
		if L ~= "X" then
			local post = part({ size = Vector3.new(1.4, 1.6, 1.4), cframe = CFrame.new(p.x * K, 0.8, p.y * K), color = WHITE, parent = f, collide = false })
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(40, 40)
			bb.StudsOffset = Vector3.new(0, 2.2, 0)
			bb.MaxDistance = 160
			bb.Parent = post
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundColor3 = Color3.new(1, 1, 1)
			t.Text = L
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = col("#1c4f8a")
			t.Parent = bb
		end
	end
	label("🏇 МАНЕЖ", A.x + A.w * 0.32, A.y - 20, 6, "#3b2a1a", 260, 24)
	-- кавалетти
	local C = World.CAV
	for _, x in ipairs(C.poles) do
		local len = (C.y2 - C.y1) * K
		for i = 0, 3 do
			part({ size = Vector3.new(0.5, 0.5, len / 4), cframe = CFrame.new(x * K, 0.6, (C.y1 * K) + len / 8 + i * len / 4), color = i % 2 == 0 and "#e03131" or WHITE, collide = false, parent = f })
		end
		part({ size = Vector3.new(0.8, 0.8, 0.8), cframe = CFrame.new(x * K, 0.4, C.y1 * K), color = DARKWOOD, collide = false, parent = f })
		part({ size = Vector3.new(0.8, 0.8, 0.8), cframe = CFrame.new(x * K, 0.4, C.y2 * K), color = DARKWOOD, collide = false, parent = f })
	end
	label("🌿 ЛЕВАДА", World.PADDOCK.x + World.PADDOCK.w / 2, World.PADDOCK.y - 15, 7, "#3b2a1a", 260, 24)
	-- конкурное поле: препятствия
	local J = World.JUMPF
	label("🏆 КОНКУРНОЕ ПОЛЕ", J.x + J.w / 2, J.y - 20, 6, "#3b2a1a", 300, 24)
	for _, o in ipairs(World.COURSE) do
		local cf = CFrame.new(o.x * K, 0, o.y * K) * CFrame.Angles(0, -o.a, 0)
		local half = o.half * K
		local rails = o.type == "oxer" and { -1, 1 } or o.type == "triple" and { -1.5, 0, 1.5 } or { 0 }
		for _, dz in ipairs(rails) do
			-- стойки по краям (вдоль направления прыжка — ось X, поперёк — Z)
			for _, s in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(0.6, 5, 0.6), cframe = cf * CFrame.new(dz, 2.5, s * half), color = s > 0 and "#e03131" or WHITE, parent = f, collide = false })
			end
			if o.type == "wall" then
				part({ size = Vector3.new(1, 3.2, half * 2), cframe = cf * CFrame.new(dz, 1.6, 0), color = "#c2552d", material = M.Brick, parent = f, collide = false })
			elseif o.type == "cross" then
				for _, s in ipairs({ -1, 1 }) do
					local rail = part({ size = Vector3.new(0.35, 0.35, half * 2.2), cframe = cf * CFrame.new(dz, 1.6, 0) * CFrame.Angles(s * 0.35, 0, 0), color = "#1c7ed6", parent = f, collide = false })
					rail.Name = "Rail"
				end
			else
				for _, yy in ipairs({ 1.3, 2.6 }) do
					part({ size = Vector3.new(0.35, 0.35, half * 2), cframe = cf * CFrame.new(dz, yy, 0), color = yy > 2 and "#f08c00" or WHITE, parent = f, collide = false })
				end
			end
		end
		label(tostring(o.n), o.x, o.y, 6.5, "#1c4f8a", 140, 22)
	end
	-- повозки
	for _, cart in ipairs({ { World.SELL, "#c92a2a" }, { World.SHOP, "#2b8a3e" } }) do
		local r, c = cart[1], cart[2]
		rectBox({ x = r.x, y = r.y, w = r.w, h = r.h }, 1.2, 3.2, "#c8a27a", M.WoodPlanks, true, f)
		roofOver(r, 6.2, c, 0.6).Parent = f
		for _, sx in ipairs({ 0.15, 0.85 }) do
			for _, sy in ipairs({ 0, 1 }) do
				part({ size = Vector3.new(0.4, 2.4, 2.4), cframe = CFrame.new((r.x + r.w * sx) * K, 1.2, (r.y + r.h * sy) * K) * CFrame.Angles(0, math.pi / 2, 0),
					color = DARKWOOD, shape = Enum.PartType.Cylinder, parent = f })
			end
		end
		for _, sx in ipairs({ 0, 1 }) do
			for _, sy in ipairs({ 0, 1 }) do
				part({ size = Vector3.new(0.3, 2, 0.3), cframe = CFrame.new((r.x + r.w * sx) * K, 5.2, (r.y + r.h * sy) * K), color = DARKWOOD, parent = f, collide = false })
			end
		end
		label(r.name, r.x + r.w / 2, r.y - 10, 9, "#3b2a1a", 220, 20)
	end
	-- фонари
	for _, L in ipairs(World.LAMPS) do lamp(L.x, L.y, f) end
	-- стартовый столб скачек (клетчатый)
	local st = World.START
	for i = 0, 7 do
		for j = 0, 1 do
			part({ size = Vector3.new(0.7, 0.9, 0.7), cframe = CFrame.new(st.x * K + (j - 0.5) * 0.7, 0.45 + i * 0.9, st.y * K), color = (i + j) % 2 == 0 and "#111111" or "#ffffff", parent = f })
		end
	end
	label("🏁 СКАЧКИ", st.x, st.y, 9, "#3b2a1a", 260, 22)
end

local function house(hh, parent)
	local r = hh
	rectBox(r, 0, 7, hh.wall, M.SmoothPlastic, true, parent)
	-- двускатная крыша из двух клиньев
	local w, d = r.w * K + 1.4, r.h * K + 1.4
	local cx, cz = (r.x + r.w / 2) * K, (r.y + r.h / 2) * K
	for _, s in ipairs({ -1, 1 }) do
		local wd = Instance.new("WedgePart")
		wd.Anchored = true
		wd.Size = Vector3.new(w, 4, d / 2)
		wd.CFrame = CFrame.new(cx, World.GROUND + 9, cz + s * d / 4) * CFrame.Angles(0, s > 0 and math.pi or 0, 0)
		wd.Color = col(hh.roof)
		wd.Material = M.SmoothPlastic
		wd.Parent = parent
	end
	-- дверь и окна
	part({ size = Vector3.new(2, 3.6, 0.2), cframe = CFrame.new(cx, 1.8, (r.y + r.h) * K + 0.1), color = DARKWOOD, parent = parent, collide = false })
	for _, sx in ipairs({ -1, 1 }) do
		part({ size = Vector3.new(1.8, 1.5, 0.2), cframe = CFrame.new(cx + sx * r.w * K * 0.3, 4, (r.y + r.h) * K + 0.1), color = "#a5d8ff", material = M.Glass, parent = parent, collide = false })
	end
	if hh.name then label(hh.name, r.x + r.w / 2, r.y - 10, 13, "#3b2a1a", 220, 18) end
end

local function buildVillage()
	local f = Instance.new("Folder")
	f.Name = "Village"
	f.Parent = root
	for _, hh in ipairs(World.HOUSES) do house(hh, f) end
	local W = World.WELL
	local well = part({ size = Vector3.new(2.6, W.r * 2 * K, W.r * 2 * K), cframe = CFrame.new(W.x * K, 1.3, W.y * K) * CFrame.Angles(0, 0, math.pi / 2), color = "#8d8476", material = M.Cobblestone, shape = Enum.PartType.Cylinder, parent = f })
	well.Name = "Well"
	part({ size = Vector3.new(0.4, W.r * 1.6 * K, W.r * 1.6 * K), cframe = CFrame.new(W.x * K, 2.65, W.y * K) * CFrame.Angles(0, 0, math.pi / 2), color = "#3f8fc0", shape = Enum.PartType.Cylinder, parent = f, collide = false })
	roofOver({ x = W.x - W.r, y = W.y - W.r, w = W.r * 2, h = W.r * 2 }, 6, "#8c3b2a", 0.5).Parent = f
	-- доска заданий
	local B = World.BOARD
	part({ size = Vector3.new(4, 3, 0.4), cframe = CFrame.new(B.x * K, 3, B.y * K), color = "#c8a27a", material = M.WoodPlanks, parent = f })
	for _, s in ipairs({ -1, 1 }) do
		part({ size = Vector3.new(0.4, 4, 0.4), cframe = CFrame.new(B.x * K + s * 1.8, 2, B.y * K), color = DARKWOOD, parent = f })
	end
	label("📋 Доска заданий", B.x, B.y, 6, "#3b2a1a", 160, 16)
	-- рынок
	local Mk = World.MARKET
	label("🎪 РЫНОК", Mk.x + Mk.w / 2, Mk.y - 10, 10, "#b35c00", 260, 24)
	for _, st in ipairs(World.MARKET_STALLS) do
		rectBox(st, 0, 3, "#c8a27a", M.WoodPlanks, true, f)
		local roof = { x = st.x - 10, y = st.y - 10, w = st.w + 20, h = st.h + 60 }
		roofOver(roof, 6.5, st.roof, 0).Parent = f
		for _, sx in ipairs({ 0, 1 }) do
			part({ size = Vector3.new(0.35, 6.5, 0.35), cframe = CFrame.new((roof.x + roof.w * sx) * K, 3.25, (roof.y + roof.h) * K), color = DARKWOOD, parent = f, collide = false })
		end
		label(st.name, st.x + st.w / 2, st.y, 8.5, "#3b2a1a", 160, 16)
	end
end

local function buildSeaside()
	local f = Instance.new("Folder")
	f.Name = "Seaside"
	f.Parent = root
	local function pier(x, y, dir)
		-- dir: +1 — в сторону моря на восток
		local len = 26
		part({ size = Vector3.new(len, 0.6, 6), cframe = CFrame.new(x * K + dir * len / 2, 0.6, y * K), color = "#a0764a", material = M.WoodPlanks, parent = f })
		for i = 0, 3 do
			for _, s in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(0.6, 4, 0.6), cframe = CFrame.new(x * K + dir * (i * len / 3), -1, y * K + s * 2.8), color = DARKWOOD, parent = f })
			end
		end
		-- лодка
		local bx = x * K + dir * (len + 3)
		part({ size = Vector3.new(7, 1.4, 3.2), cframe = CFrame.new(bx, 0.2, y * K + 4.5), color = "#c92a2a", material = M.Wood, parent = f, collide = false })
		part({ size = Vector3.new(0.3, 6, 0.3), cframe = CFrame.new(bx, 3.5, y * K + 4.5), color = DARKWOOD, parent = f, collide = false })
		part({ size = Vector3.new(0.1, 4, 3), cframe = CFrame.new(bx + 0.3, 4, y * K + 4.5) * CFrame.Angles(0, math.pi / 2, 0), color = "#ffffff", material = M.Fabric, parent = f, collide = false })
	end
	pier(World.PIER.x - 20, World.PIER.y, 1)
	label("⛵ Пристань", World.PIER.x, World.PIER.y - 40, 8, "#1c4f8a", 220, 20)
	for _, I in ipairs(World.ISLANDS) do
		pier(I.pier.x, I.pier.y, -1)
		-- конюшня на 5 денников
		for _, s in ipairs(World.SOLIDS) do
			if s.kind == "stable" and World.inRect(s.x, s.y, I.stable, 5) then rectBox(s, 0, 8, "#c8a27a", M.WoodPlanks, true, f) end
		end
		roofOver(I.stable, 8.3, "#2f6f8f", 1).Parent = f
		for k = 1, 4 do
			part({ size = Vector3.new(0.4, 4, 12), cframe = CFrame.new((I.stable.x + k * 68) * K, 2, (I.stable.y + 70) * K), color = WOOD, parent = f })
		end
		label("🏝️ " .. I.name, I.x, I.y - I.ry + 160, 12, "#1c4f8a", 400, 24)
		-- пастбище
		for _, s in ipairs(World.SOLIDS) do
			if s.kind == "fence" and World.inRect(s.x + s.w / 2, s.y + s.h / 2, I.pasture, 20) then fenceRect(s, f) end
			if s.kind == "post" and math.abs(s.x - I.pen.x) < I.pen.r + 30 and math.abs(s.y - I.pen.y) < I.pen.r + 30 then
				part({ size = Vector3.new(1.4, 3.4, 1.4), cframe = CFrame.new((s.x + 9) * K, 1.7, (s.y + 9) * K), color = DARKWOOD, material = M.Wood, parent = f })
			end
		end
	end
end

local function portal(P, y0, color, parent)
	local center = Vector3.new(P.x * K, y0 + 6, P.y * K)
	local n = 18
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * 5, math.sin(a) * 5, 0)
		local p = part({ size = Vector3.new(1.8, 1, 1), cframe = CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2), color = color, material = M.Neon, parent = parent, collide = false })
		p.CastShadow = false
	end
	local disc = part({ size = Vector3.new(0.3, 9, 9), cframe = CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0), color = color, material = M.ForceField, parent = parent, collide = false, shape = Enum.PartType.Cylinder, transparency = 0.2 })
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 4
	light.Color = col(color)
	light.Parent = disc
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 25
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 1
	pe.Color = ColorSequence.new(col(color))
	pe.Size = NumberSequence.new(0.4, 0)
	pe.Parent = disc
end

local function buildCaveAndSky()
	local f = Instance.new("Folder")
	f.Name = "Magic"
	f.Parent = root
	portal(World.PORTAL, 0, "#9775fa", f)
	label("🌀 Портал", World.PORTAL.x, World.PORTAL.y, 14, "#7048e8", 200, 20)
	portal(World.SKY_PORTAL, World.SKY_Y, "#9775fa", f)
	label("🌀 Портал в пещеру", World.SKY_PORTAL.x, World.SKY_PORTAL.y, World.SKY_Y + 14, "#7048e8", 220, 20)
	label("🦇 Пещера", World.CAVE.x - 120, (World.CAVE_GATE.y1 + World.CAVE_GATE.y2) / 2, 30, "#343a40", 400, 26)
	for _, I in ipairs(World.SKY_ISLANDS) do
		label("☁️ " .. I.name, I.x, I.y - I.ry + 80, World.SKY_Y + 8, "#1c4f8a", 400, 22)
	end
	-- мосты из лиан
	for _, b in ipairs(World.SKY_BRIDGES) do
		local len = Util.hypot(b[3] - b[1], b[4] - b[2])
		local n = math.floor(len / 30)
		for i = 0, n do
			local t = i / n
			local x, y = b[1] + (b[3] - b[1]) * t, b[2] + (b[4] - b[2]) * t
			local a = Vector3.new(b[1] * K, 0, b[2] * K)
			local c = Vector3.new(b[3] * K, 0, b[4] * K)
			local cf = CFrame.lookAt(Vector3.new(x * K, World.SKY_Y - 0.3, y * K), Vector3.new(x * K, World.SKY_Y - 0.3, y * K) + (c - a))
			part({ size = Vector3.new(World.BRIDGE_W * 2 * K, 0.5, 2.6), cframe = cf, color = i % 2 == 0 and "#a0764a" or "#8a5a32", material = M.WoodPlanks, parent = f })
		end
		segment(b[1], b[2], b[3], b[4], World.SKY_Y + 2.6, 0.3, 0.3, "#2f9e44", M.Grass, false, f)
	end
	-- облака под островами и у края земли
	local rr = Util.rng(5)
	for _ = 1, 60 do
		local x = World.SKY.x + rr() * World.SKY.w
		local y = World.H + 200 + rr() * (World.TOTAL_H - World.H - 200)
		local s = 20 + rr() * 40
		local c = part({ size = Vector3.new(s, s * 0.35, s * 0.7), cframe = CFrame.new(x * K, World.SKY_Y - 40 - rr() * 60, y * K), color = "#ffffff", material = M.SmoothPlastic, parent = f, collide = false, transparency = 0.15 })
		c.CastShadow = false
	end
	-- железная дорога и станция
	local R = World.RAIL
	for _, dz in ipairs({ -1.6, 1.6 }) do
		part({ size = Vector3.new((R.x2 - R.x1) * K + 140, 0.4, 0.35), cframe = CFrame.new((R.x1 + R.x2) / 2 * K, 0.5, R.y * K + dz), color = "#868e96", material = M.Metal, parent = f, collide = false })
	end
	local x = R.x1 * K - 70
	while x < R.x2 * K + 70 do
		part({ size = Vector3.new(1, 0.3, 5), cframe = CFrame.new(x, 0.2, R.y * K), color = "#6b4423", material = M.Wood, parent = f, collide = false })
		x += 3.5
		yieldSome()
	end
	local St = World.STATION
	rectBox({ x = St.x, y = St.y, w = St.w, h = St.h }, 0, 0.8, "#c8a27a", M.WoodPlanks, true, f)
	house({ x = St.x + 30, y = St.y - 60, w = 160, h = 70, wall = "#f1e3c6", roof = "#c92a2a" }, f)
	roofOver({ x = St.x + 220, y = St.y, w = 280, h = St.h }, 6.5, "#2f6f8f", 0).Parent = f
	label("🚂 СТАНЦИЯ", St.x + 110, St.y - 25, 12, "#c92a2a", 300, 22)
	for _, g in ipairs(World.GROTTOS) do label("🕳️ Пещерка", g.x, g.y - g.r - 30, 20, "#343a40", 260, 18) end
end

-- замерить, где на самом деле поверхность земли: блоки рельефа выравниваются по сетке 4 стада,
-- и верх может оказаться не на нуле. Берём медиану по нескольким ровным местам фермы.
measureGround = function()
	local pts = {
		{ World.FIELD.x + World.FIELD.w / 2, World.FIELD.y + World.FIELD.h / 2 }, { World.START.x - 200, World.START.y },
		{ World.OX + 960, World.OY + 470 }, { World.PADDOCK.x + 200, World.PADDOCK.y + 200 }, { World.JUMPF.x + 300, World.JUMPF.y + 300 },
		{ World.FARMLAND.x + 400, World.FARMLAND.y + 400 }, { World.FIELD.x + 300, World.FIELD.y + 1600 },
	}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { T }
	local hs = {}
	for _, q in ipairs(pts) do
		local hit = workspace:Raycast(Vector3.new(q[1] * K, 60, q[2] * K), Vector3.new(0, -120, 0), params)
		if hit and hit.Material ~= M.Water then table.insert(hs, hit.Position.Y) end
	end
	table.sort(hs)
	local g = #hs > 0 and hs[math.ceil(#hs / 2)] or 0
	World.GROUND = g
	workspace:SetAttribute("GroundY", g)
	print(string.format("[HorseFarm] поверхность земли на высоте %.2f стада", g))
end

function WB.build()
	root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace
	WB.root = root
	buildTerrain()
	measureGround()
	buildBarriers()
	buildFarm()
	buildVillage()
	buildSeaside()
	buildCaveAndSky()
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new((World.OX + 960) * K, World.GROUND + 0.2, (World.OY + 470) * K)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
end

-- фонари ночью
function WB.updateLamps(night)
	for _, b in ipairs(lamps) do
		local l = b:FindFirstChildOfClass("PointLight")
		if l and l.Enabled ~= night then
			l.Enabled = night
			b.Material = night and M.Neon or M.SmoothPlastic
		end
	end
end

return WB
