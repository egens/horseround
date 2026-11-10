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
-- надпись над местом. Размер — в стадах (как у настоящей вывески): вблизи читается, издалека становится
-- маленькой и не загораживает полэкрана (раньше надписи были одного размера в пикселях на любом расстоянии)
local function label(text, x, y, h, color, maxDist, size)
	local anchor = part({ size = Vector3.new(0.2, 0.2, 0.2), cframe = CFrame.new(x * K, h, y * K), transparency = 1, collide = false, name = "Label" })
	anchor.CanQuery = false
	local bb = Instance.new("BillboardGui")
	local hs = (size or 22) / 16 -- высота строки в стадах
	local n = utf8.len(text) or #text
	bb.Size = UDim2.new(hs * (n * 0.62 + 1), 0, hs, 0)
	bb.MaxDistance = maxDist or 220
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
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
	-- в лесах — настоящая трава (живые травинки растут только на материале Grass),
	-- в Грибном королевстве — розовая травка (LeafyGrass розового цвета)
	forest = M.Grass, foxwood = M.Grass, deepforest = M.Grass, mushroom = M.LeafyGrass,
	desert = M.Sand, tundra = M.Snow, mountain = M.Rock, cave = M.Slate, grottocave = M.Slate, dragonrock = M.Basalt, steppe = M.Ground,
	i1 = M.Grass, i2 = M.Grass, i3 = M.Grass, i4 = M.Sandstone,
}
local measureGround
-- цвета материалов и воды: каждая настройка отдельно, чтобы одна ошибка не сорвала постройку рельефа
local function setColors()
	local colors = {
		{ M.LeafyGrass, "#e58fc4" }, { M.Salt, "#9b87c9" }, { M.Sand, "#e8cf8f" }, { M.Snow, "#f4f8fb" },
		{ M.Rock, "#8a8580" }, { M.Slate, "#4a4744" }, { M.Basalt, "#2a2224" }, { M.Ground, "#b9a35f" }, { M.Mud, "#8a6238" },
		{ M.Sandstone, "#7a3b2e" }, { M.Cobblestone, "#b8a98f" }, { M.Glacier, "#cfe9ff" }, { M.CrackedLava, "#ff5a00" }, { M.Concrete, "#9c8f7e" },
	}
	for _, c in ipairs(colors) do
		local ok, err = pcall(function() T:SetMaterialColor(c[1], col(c[2])) end)
		if not ok then warn("[HorseFarm] цвет материала " .. tostring(c[1]) .. ": " .. tostring(err)) end
	end
	-- Трава (материал Grass) — стандартного цвета Roblox. Живая колышущаяся трава (Terrain.Decoration)
	-- из скрипта не включается, поэтому она задана в default.project.json (Workspace → Terrain).
	for k, v in pairs({ WaterColor = col("#3f8fc0"), WaterTransparency = 0.35, WaterReflectance = 0.6, WaterWaveSize = 0.08 }) do
		pcall(function() T[k] = v end)
	end
end

-- клетки дорог (тропинок) на сетке 4 стада: ключ "i|j" → true
local function roadCells(VS)
	local set = {}
	local HALF = 38 -- полуширина тропинки, пикс. (≈7.5 стада в ширину)
	for _, r in ipairs(World.ROADS) do
		for i = 1, #r - 1 do
			local ax, ay, bx, by = r[i][1], r[i][2], r[i + 1][1], r[i + 1][2]
			local len = Util.hypot(bx - ax, by - ay)
			local n = math.max(1, math.ceil(len / 15))
			for k = 0, n do
				local t = k / n
				local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
				local i0, i1 = math.floor((x - HALF) * K / VS), math.floor((x + HALF) * K / VS)
				local j0, j1 = math.floor((y - HALF) * K / VS), math.floor((y + HALF) * K / VS)
				for ii = i0, i1 do
					for jj = j0, j1 do
						local cx, cy = (ii + 0.5) * VS / K, (jj + 0.5) * VS / K
						if Util.hypot(cx - x, cy - y) < HALF then set[ii .. "|" .. jj] = true end
					end
				end
			end
		end
	end
	return set
end

-- Рельеф одной записью вокселей: холмы по карте высот World.heightAt, озёра с пологим дном
-- (в них можно зайти и поплавать), тропинки, горы за краями земли.
local function buildLand()
	local VS = 4
	local EXT = World.RELIEF_EXT
	local Y0, NY = -16, 40 -- от -16 до 144 стад
	local i0 = math.floor(-EXT * K / VS)
	local i1 = math.ceil((World.W + EXT) * K / VS)
	local j0 = math.floor(-EXT * K / VS)
	local j1 = math.ceil((World.H + 1300) * K / VS)
	local roads = roadCells(VS)
	local CH = 32
	local LW = World.LAKE_WATER
	local function columnInfo(ii, jj)
		local x, y = (ii + 0.5) * VS / K, (jj + 0.5) * VS / K
		local g, mat, water = 0, nil, nil
		-- песчаный берег вокруг озёр: широкий, с неровным краем
		local L = World.lakeAt(x, y, 70 + World.vnoise(x / 90, y / 90, 13) * 60)
		if y > World.H then
			g = World.ridge(x, y)
			mat = M.Rock
		else
			g = World.heightAt(x, y)
			local reg = World.regionCoarse(x, y)
			mat = reg == "edge" and M.Rock or GROUND[reg] or M.Grass
			if x > World.W then
				mat = g < -1 and M.Sand or M.Rock
				if g < -2 then water = -2 end
			end
		end
		if g > 90 then mat = M.Snow end
		local inside = L and World.inBlob(L, x, y)
		if L and (L.lava or L.ice) and not inside then L = nil end
		if L then
			if L.lava then mat = M.CrackedLava; g = 0
			elseif L.ice then mat = M.Glacier; g = 0
			else
				mat = M.Sand -- дно и песчаная кайма у берега
				if inside then water = LW end
			end
		elseif roads[ii .. "|" .. jj] and y <= World.H then
			mat = M.Mud
		end
		return g, mat, water
	end
	for ci = i0, i1, CH do
		for cj = j0, j1, CH do
			local ni, nj = math.min(CH, i1 - ci + 1), math.min(CH, j1 - cj + 1)
			-- высоты с запасом в 1 клетку — для крутизны склонов
			local hs, ms, ws = {}, {}, {}
			for a = 0, ni + 1 do
				hs[a], ms[a], ws[a] = {}, {}, {}
				for b = 0, nj + 1 do
					local g, mt, w = columnInfo(ci + a - 1, cj + b - 1)
					hs[a][b], ms[a][b], ws[a][b] = math.min(g, 140), mt, w
				end
			end
			local mats, occs = {}, {}
			for a = 1, ni do
				local mx, ox = {}, {}
				mats[a], occs[a] = mx, ox
				for k = 1, NY do
					mx[k], ox[k] = {}, {}
				end
				for b = 1, nj do
					local g, mt, w = hs[a][b], ms[a][b], ws[a][b]
					local slope = math.max(math.abs(hs[a + 1][b] - hs[a - 1][b]), math.abs(hs[a][b + 1] - hs[a][b - 1])) / (2 * VS)
					if slope > 1.0 and not w and mt ~= M.Snow and mt ~= M.Mud and mt ~= M.CrackedLava and mt ~= M.Glacier then
						mt = (mt == M.Sand or mt == M.Sandstone) and M.Sandstone or M.Rock
					end
					for k = 1, NY do
						local y0 = Y0 + (k - 1) * VS
						local occ = math.clamp((g - y0) / VS, 0, 1)
						local m = mt
						if occ < 0.35 and w and w > y0 then
							m = M.Water
							occ = math.clamp((w - y0) / VS, 0, 1)
						end
						if occ <= 0.02 then
							m = M.Air
							occ = 0
						end
						mx[k][b], ox[k][b] = m, occ
					end
				end
			end
			local lo = Vector3.new(ci * VS, Y0, cj * VS)
			local hi = lo + Vector3.new(ni * VS, NY * VS, nj * VS)
			local ok, err = pcall(function() T:WriteVoxels(Region3.new(lo, hi), VS, mats, occs) end)
			if not ok then warn("[HorseFarm] рельеф: " .. tostring(err)) end
			task.wait()
		end
	end
end

local function buildTerrain()
	setColors()
	local W, H = World.W, World.H
	buildLand()
	local c8 = 80
	-- Вода в Roblox (с «береговой линией») может жить в одной клетке вместе с землёй: если залить
	-- воду поверх земли или землю поверх воды, вода остаётся сверху. Поэтому сначала вырезаем место (Air),
	-- потом заливаем. Уровень моря — на 2 стада ниже земли, чтобы берега и острова были над водой.
	local WATER_TOP = -2
	-- море: полосами от берега, потом острова клетками помельче
	local ystep = 80
	for y = 0, H - 1, ystep do
		local cx = World.coastX(y + ystep / 2)
		local x0 = cx - 40
		local cxx, cz, sx, sz = ((x0 + W) / 2) * K, (y + ystep / 2) * K, (W - x0) * K + 2, ystep * K
		T:FillBlock(CFrame.new(cxx, -4, cz), Vector3.new(sx, 24, sz), M.Air)
		T:FillBlock(CFrame.new(cxx, -14, cz), Vector3.new(sx, 4, sz), M.Sand)
		T:FillBlock(CFrame.new(cxx, (-12 + WATER_TOP) / 2, cz), Vector3.new(sx, WATER_TOP + 12, sz), M.Water)
		yieldSome()
	end
	for _, I in ipairs(World.ISLANDS) do
		local mat = I.bone and M.Sandstone or M.Grass
		for x = I.x - I.rx * 1.3, I.x + I.rx * 1.3, c8 do
			for y = I.y - I.ry * 1.3, I.y + I.ry * 1.3, c8 do
				local q = World.blobInfo(I, x, y)
				if q.d < q.R then
					local edge = q.d > q.R - 140 / q.unit
					T:FillBlock(CFrame.new(x * K, -4, y * K), Vector3.new(c8 * K, 24, c8 * K), M.Air)
					T:FillBlock(CFrame.new(x * K, -7, y * K), Vector3.new(c8 * K, 14, c8 * K), (edge and not I.bone) and M.Sand or mat)
				end
				yieldSome()
			end
		end
	end
	-- манеж и конкурное поле — песок, площадь деревни — брусчатка
	local A = World.ARENA
	T:FillBlock(CFrame.new((A.x + A.w / 2) * K, -2, (A.y + A.h / 2) * K), Vector3.new(A.w * K, 4, A.h * K), M.Sand)
	local J = World.JUMPF
	T:FillBlock(CFrame.new((J.x + J.w / 2) * K, -2, (J.y + J.h / 2) * K), Vector3.new(J.w * K, 4, J.h * K), M.Sand)
	-- в конюшнях под плиткой — бетон, а не трава (травинки Roblox пробивались сквозь пол)
	local function noGrass(r)
		T:FillBlock(CFrame.new((r.x + r.w / 2) * K, -2, (r.y + r.h / 2) * K), Vector3.new(r.w * K + 2, 4, r.h * K + 2), M.Concrete)
	end
	noGrass(World.STABLE)
	for _, I in ipairs(World.ISLANDS) do noGrass(I.stable) end
	for _, hh in ipairs(World.HOUSES) do noGrass(hh) end
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
	-- вершины гор: разные формы — купола, острые пики, гребни, столбы и скалы-«ступеньки»
	local Mo = World.MOUNTAIN
	local rr = Util.rng(77)
	for _ = 1, 46 do
		local x, y = Mo.x + rr() * Mo.w, Mo.y + rr() * Mo.h
		local h = 20 + rr() * 40
		local mat = rr() < 0.3 and M.Snow or M.Rock
		local kind = rr()
		local c = Vector3.new(x * K, 38 + h * 0.4, y * K)
		if kind < 0.3 then
			T:FillBall(c, 14 + rr() * 18, mat)
		elseif kind < 0.55 then
			-- острый пик: несколько шаров, всё меньше и выше
			local r0 = 12 + rr() * 10
			for i = 0, 3 do T:FillBall(c + Vector3.new((rr() - 0.5) * 4, i * r0 * 0.7, (rr() - 0.5) * 4), r0 * (1 - i * 0.22), i == 3 and M.Snow or mat) end
		elseif kind < 0.75 then
			-- гребень: клин
			local cf = CFrame.new(c) * CFrame.Angles(0, rr() * math.pi, 0)
			T:FillWedge(cf, Vector3.new(14 + rr() * 10, 18 + rr() * 22, 40 + rr() * 50), mat)
		elseif kind < 0.9 then
			-- каменный столб
			T:FillCylinder(CFrame.new(c + Vector3.new(0, 6, 0)), 20 + rr() * 26, 5 + rr() * 6, M.Rock)
			T:FillBall(c + Vector3.new(0, 18, 0), 6 + rr() * 4, M.Snow)
		else
			-- скала-ступенька
			local cf = CFrame.new(c) * CFrame.Angles(0, rr() * math.pi, rr() * 0.3)
			T:FillBlock(cf, Vector3.new(16 + rr() * 16, 14 + rr() * 14, 16 + rr() * 16), M.Slate)
		end
		yieldSome()
	end
	-- стены пещеры неровные: камни разного размера выпирают из стен
	for _, w in ipairs(World.CAVE_INNER_WALLS) do
		local n = math.floor((w.w + w.h) / 90)
		for _ = 1, n do
			local x = w.x + rr() * w.w
			local y = w.y + rr() * w.h
			T:FillBall(Vector3.new(x * K, 6 + rr() * 20, y * K), 4 + rr() * 6, rr() < 0.5 and M.Slate or M.Rock)
			yieldSome()
		end
	end
	-- маленькие пещерки: каменный потолок разной высоты, сверху — неровный холм
	for i, g in ipairs(World.GROTTOS) do
		local ch = 26 + (i % 3) * 4
		T:FillCylinder(CFrame.new(g.x * K, ch, g.y * K), 4, g.r * K + 4, M.Rock) -- потолок вдвое выше (был на 15)
		T:FillCylinder(CFrame.new(g.x * K, -2, g.y * K), 4, g.r * K, M.Slate)
		local gr = Util.rng(300 + i)
		for _ = 1, 5 + i do
			local a, d = gr() * math.pi * 2, gr() * g.r * 0.7
			T:FillBall(Vector3.new((g.x + math.cos(a) * d) * K, ch + 2 + gr() * 4, (g.y + math.sin(a) * d) * K), 5 + gr() * 9, gr() < 0.6 and M.Rock or M.Grass)
		end
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
	-- в обычные озёра можно зайти и поплавать; стенка только у лавы
	for _, L in ipairs(World.LAKES) do
		if not L.lava then continue end
		local pts = World.blobPoly(L, 6, 40)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			wall(a.x, a.y, b.x, b.y, 12)
		end
		yieldSome()
	end
	-- у берега и у островов стенок больше нет: можно доплыть до острова и выйти на него
	-- (и залететь на крылатой лошади), не упираясь в невидимый барьер
	-- края мира (над южным краем можно перелететь к небесным островам)
	local W, H = World.W, World.H
	wall(0, 0, W, 0, 80)
	wall(0, 0, 0, H, 80)
	wall(W, 0, W, H, 80)
	wall(0, H, W, H, 40) -- за южными горами — небо; перелететь можно сверху
	-- у небесных островов невидимых перил нет: на остров можно подняться с любой стороны
	-- (если упасть с острова, облачко вернёт к порталу)
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

-- двускатная (треугольная) крыша из двух клиньев над прямоугольником карты r; y — низ крыши.
-- Конёк идёт вдоль длинной стороны. Возвращает модель (вызывающий кладёт её в нужную папку).
local function roofOver(r, y, color, overhang, rise)
	overhang = overhang or 1
	local alongX = r.w >= r.h
	local L = (alongX and r.w or r.h) * K + overhang * 2
	local D = (alongX and r.h or r.w) * K + overhang * 2
	rise = rise or math.clamp(D * 0.38, 1.5, 10)
	local m = Instance.new("Model")
	m.Name = "Roof"
	local center = CFrame.new((r.x + r.w / 2) * K, World.GROUND + y + rise / 2, (r.y + r.h / 2) * K) * CFrame.Angles(0, alongX and 0 or math.pi / 2, 0)
	for _, s in ipairs({ -1, 1 }) do
		-- у клина высокая сторона смотрит в +Z: поворачиваем так, чтобы обе высокие стороны сходились в коньке
		local wd = Instance.new("WedgePart")
		wd.Anchored = true
		wd.Size = Vector3.new(L, rise, D / 2)
		wd.CFrame = center * CFrame.new(0, 0, s * D / 4) * CFrame.Angles(0, s > 0 and math.pi or 0, 0)
		wd.Color = col(color)
		wd.Material = M.WoodPlanks
		wd.TopSurface = Enum.SurfaceType.Smooth
		wd.BottomSurface = Enum.SurfaceType.Smooth
		wd.Parent = m
	end
	-- конёк
	local ridge = Instance.new("Part")
	ridge.Anchored = true
	ridge.Size = Vector3.new(L + 0.2, 0.5, 0.7)
	ridge.CFrame = center * CFrame.new(0, rise / 2, 0)
	ridge.Color = col(color):Lerp(Color3.new(0, 0, 0), 0.25)
	ridge.Material = M.WoodPlanks
	ridge.Parent = m
	m.Parent = root
	return m
end

-- плиточный пол: плитки двух оттенков с тёмными швами между ними
local TILE = M.Slate
pcall(function() TILE = Enum.Material.CeramicTiles end)
local function tileFloor(r, parent, inset)
	inset = inset or 10
	local x0, z0 = (r.x + inset) * K, (r.y + inset) * K
	local w, d = (r.w - inset * 2) * K, (r.h - inset * 2) * K
	-- шов (подложка)
	part({ size = Vector3.new(w, 0.1, d), cframe = CFrame.new(x0 + w / 2, 0.05, z0 + d / 2), color = "#7d7368", material = M.Concrete, parent = parent })
	local S = 3
	local nx, nz = math.floor(w / S), math.floor(d / S)
	local sx, sz = w / nx, d / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local c = (i + j) % 2 == 0 and "#d9cbb3" or "#bfae92"
			local t = part({ size = Vector3.new(sx - 0.14, 0.14, sz - 0.14), cframe = CFrame.new(x0 + (i + 0.5) * sx, 0.12, z0 + (j + 0.5) * sz), color = c, material = TILE, parent = parent })
			t.CastShadow = false
			yieldSome()
		end
	end
end

-- материалы поновее (если их нет в этой версии Roblox — запасные)
local PLASTER, ROOFTILE, SHINGLE = M.Concrete, M.WoodPlanks, M.WoodPlanks
pcall(function() PLASTER = Enum.Material.Plaster end)
pcall(function() ROOFTILE = Enum.Material.ClayRoofTiles end)
pcall(function() SHINGLE = Enum.Material.RoofShingles end)

-- грань прямоугольника карты r: side = south/north/east/west. Возвращает CFrame на середине грани
-- (локальная X — вдоль стены, Y — вверх, Z — наружу) и ширину грани в стадах
local function faceOf(r, side)
	local cx, cz = (r.x + r.w / 2) * K, (r.y + r.h / 2) * K
	if side == "north" then return CFrame.fromMatrix(Vector3.new(cx, 0, r.y * K), -Vector3.xAxis, Vector3.yAxis), r.w * K end
	if side == "east" then return CFrame.fromMatrix(Vector3.new((r.x + r.w) * K, 0, cz), -Vector3.zAxis, Vector3.yAxis), r.h * K end
	if side == "west" then return CFrame.fromMatrix(Vector3.new(r.x * K, 0, cz), Vector3.zAxis, Vector3.yAxis), r.h * K end
	return CFrame.fromMatrix(Vector3.new(cx, 0, (r.y + r.h) * K), Vector3.xAxis, Vector3.yAxis), r.w * K
end
WB.faceOf = faceOf

-- окно как настоящее: стекло насквозь через стену (видно и изнутри), белая рама с крестом,
-- подоконник; ставни — по желанию. cf — грань стены (Z наружу), u — сдвиг вдоль стены, y — высота центра
local function window(parent, cf, u, y, w, h, wallT, opts)
	opts = opts or {}
	local glass = part({ size = Vector3.new(w, h, wallT + 0.12), cframe = cf * CFrame.new(u, y, -wallT / 2), color = "#bfe3f7", material = M.Glass, transparency = 0.35, parent = parent, collide = false })
	glass.Reflectance = 0.25
	glass.CastShadow = false
	local fc = opts.frame or "#f8f4ec"
	local ft = 0.22
	for _, sy in ipairs({ -1, 1 }) do
		part({ size = Vector3.new(w + ft * 2, ft, 0.2), cframe = cf * CFrame.new(u, y + sy * (h / 2 + ft / 2), 0.08), color = fc, material = M.Wood, parent = parent, collide = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		part({ size = Vector3.new(ft, h, 0.2), cframe = cf * CFrame.new(u + sx * (w / 2 + ft / 2), y, 0.08), color = fc, material = M.Wood, parent = parent, collide = false })
	end
	part({ size = Vector3.new(0.12, h, 0.14), cframe = cf * CFrame.new(u, y, 0.07), color = fc, material = M.Wood, parent = parent, collide = false })
	part({ size = Vector3.new(w, 0.12, 0.14), cframe = cf * CFrame.new(u, y, 0.07), color = fc, material = M.Wood, parent = parent, collide = false })
	part({ size = Vector3.new(w + 0.7, 0.18, 0.45), cframe = cf * CFrame.new(u, y - h / 2 - 0.25, 0.2), color = opts.sill or "#d8cfc0", material = M.Wood, parent = parent, collide = false })
	if opts.shutters then
		for _, sx in ipairs({ -1, 1 }) do
			local sp = part({ size = Vector3.new(w * 0.5, h + 0.2, 0.12), cframe = cf * CFrame.new(u + sx * (w * 0.75 + 0.35), y, 0.12), color = opts.shutters, material = M.WoodPlanks, parent = parent, collide = false })
			sp.CastShadow = false
		end
	end
end
WB.window = window

-- фонарь как настоящий: каменное основание, чугунный столб с кольцами, кронштейн,
-- фонарь-коробка со стёклами, крышей-шатром и шишечкой, внутри — лампа (горит ночью)
local IRON = "#22262b"
local function lamp(x, y, parent)
	local base = CFrame.new(x * K, 0, y * K)
	local m = Instance.new("Model")
	m.Name = "Lamp"
	m.Parent = parent
	part({ size = Vector3.new(1.4, 0.5, 1.4), cframe = base * CFrame.new(0, 0.25, 0), color = "#8d8476", material = M.Cobblestone, parent = m })
	part({ size = Vector3.new(0.9, 0.8, 0.9), cframe = base * CFrame.new(0, 0.9, 0), color = IRON, material = M.Metal, parent = m })
	part({ size = Vector3.new(7.2, 0.38, 0.38), cframe = base * CFrame.new(0, 4.7, 0) * CFrame.Angles(0, 0, math.pi / 2), color = IRON, material = M.Metal, shape = Enum.PartType.Cylinder, parent = m })
	for _, yy in ipairs({ 1.5, 4.2, 7.9 }) do
		part({ size = Vector3.new(0.18, 0.62, 0.62), cframe = base * CFrame.new(0, yy, 0) * CFrame.Angles(0, 0, math.pi / 2), color = IRON, material = M.Metal, shape = Enum.PartType.Cylinder, parent = m, collide = false })
	end
	-- фонарь на вершине
	local top = base * CFrame.new(0, 8.25, 0)
	part({ size = Vector3.new(1.3, 0.15, 1.3), cframe = top, color = IRON, material = M.Metal, parent = m, collide = false })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part({ size = Vector3.new(0.1, 1.5, 0.1), cframe = top * CFrame.new(sx * 0.58, 0.8, sz * 0.58), color = IRON, material = M.Metal, parent = m, collide = false })
		end
	end
	local glass = part({ size = Vector3.new(1.08, 1.4, 1.08), cframe = top * CFrame.new(0, 0.78, 0), color = "#fff4d6", material = M.Glass, parent = m, collide = false, transparency = 0.55 })
	glass.CastShadow = false
	local bulb = part({ size = Vector3.new(0.45, 0.65, 0.45), cframe = top * CFrame.new(0, 0.72, 0), color = "#ffe9a8", material = M.SmoothPlastic, parent = m, collide = false })
	bulb.CastShadow = false
	bulb.Name = "LampBulb"
	part({ size = Vector3.new(1.5, 0.14, 1.5), cframe = top * CFrame.new(0, 1.57, 0), color = IRON, material = M.Metal, parent = m, collide = false })
	-- крыша-шатёр из четырёх клиньев
	for k = 0, 3 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.Size = Vector3.new(1.5, 0.55, 0.75)
		w.Color = col(IRON)
		w.Material = M.Metal
		w.CFrame = CFrame.new(0, World.GROUND, 0) * top * CFrame.new(0, 1.92, 0) * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -0.375)
		w.Parent = m
	end
	part({ size = Vector3.new(0.25, 0.25, 0.25), cframe = top * CFrame.new(0, 2.3, 0), color = IRON, material = M.Metal, shape = Enum.PartType.Ball, parent = m, collide = false })
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 1.6
	light.Color = col("#ffcf7a")
	light.Shadows = true
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
	-- конюшня как настоящая: каменный цоколь, дощатые стены с тёмными балками, окно в каждом деннике,
	-- раздвижные ворота с обеих сторон, двери денников, черепичная крыша с башенкой-вентиляцией
	local S = World.STABLE
	local SH = 18
	for _, s in ipairs(World.SOLIDS) do
		-- стены вдвое выше прежнего (были 9), внутри высокий потолок
		if s.kind == "stable" and s.x < World.SEA.x - 400 then
			rectBox(s, 0, SH, "#c8a27a", M.WoodPlanks, true, f)
			rectBox({ x = s.x - 1.5, y = s.y - 1.5, w = s.w + 3, h = s.h + 3 }, 0, 1.6, "#8d8476", M.Cobblestone, true, f)
		end
	end
	-- балки по стенам снаружи и внутри
	for _, side in ipairs({ "north", "south" }) do
		local cf, wd = faceOf(S, side)
		for u = -wd / 2 + 0.4, wd / 2, 7.2 do
			part({ size = Vector3.new(0.6, SH, 0.3), cframe = cf * CFrame.new(u, SH / 2, 0.15), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		end
		part({ size = Vector3.new(wd, 0.5, 0.3), cframe = cf * CFrame.new(0, SH - 0.4, 0.15), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		part({ size = Vector3.new(wd, 0.5, 0.3), cframe = cf * CFrame.new(0, 9, 0.15), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	end
	-- окна: по одному в каждом деннике (стекло видно и изнутри, и снаружи)
	for i = 0, 19 do
		local r = World.stallRect(i)
		local side = r.row == 1 and "south" or "north"
		local cf = faceOf(S, side)
		local cx = (r.x + r.w / 2) * K
		local u = side == "north" and ((S.x + S.w / 2) * K - cx) or (cx - (S.x + S.w / 2) * K)
		window(f, cf, u, 11.5, 2.8, 2.4, 1, { shutters = "#7a2e1f" })
	end
	-- ворота у проходов: раздвинутые створки
	for _, side in ipairs({ "west", "east" }) do
		local cf = faceOf(S, side)
		local gw = (World.AISLE_Y2 - World.AISLE_Y1) * K
		for _, sg in ipairs({ -1, 1 }) do
			local door = part({ size = Vector3.new(gw * 0.55, 11, 0.4), cframe = cf * CFrame.new(sg * gw * 0.82, 5.5, 0.35), color = "#a33a2a", material = M.WoodPlanks, parent = f, collide = false })
			door.Name = "StableDoor"
			for _, d in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(gw * 0.55 * 1.12, 0.35, 0.12), cframe = cf * CFrame.new(sg * gw * 0.82, 5.5, 0.58) * CFrame.Angles(0, 0, d * 0.62), color = WHITE, material = M.Wood, parent = f, collide = false })
			end
		end
		part({ size = Vector3.new(gw * 2.4, 0.5, 0.6), cframe = cf * CFrame.new(0, 11.4, 0.4), color = "#5f5f5f", material = M.Metal, parent = f, collide = false })
	end
	local roof = roofOver(S, SH, "#a33a2a", 1.5)
	for _, d in ipairs(roof:GetChildren()) do d.Material = ROOFTILE end
	roof.Parent = f
	-- башенка-вентиляция на коньке
	local rise = math.clamp((S.h * K + 3) * 0.38, 1.5, 10)
	local top = SH + rise
	local cx, cz = (S.x + S.w / 2) * K, (S.y + S.h / 2) * K
	part({ size = Vector3.new(4, 3, 4), cframe = CFrame.new(cx, top + 1.2, cz), color = "#e9dcc4", material = M.WoodPlanks, parent = f })
	for _, a in ipairs({ 0, math.pi / 2 }) do
		part({ size = Vector3.new(2.2, 1.6, 4.1), cframe = CFrame.new(cx, top + 1.4, cz) * CFrame.Angles(0, a, 0), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	end
	roofOver({ x = (cx - 2.6) / K, y = (cz - 2.6) / K, w = 5.2 / K, h = 5.2 / K }, top + 2.7, "#a33a2a", 0.3, 1.6).Parent = f
	part({ size = Vector3.new(0.15, 2.4, 0.15), cframe = CFrame.new(cx, top + 5.4, cz), color = IRON, material = M.Metal, parent = f, collide = false })
	part({ size = Vector3.new(1.4, 0.6, 0.08), cframe = CFrame.new(cx + 0.7, top + 6.1, cz), color = IRON, material = M.Metal, parent = f, collide = false })
	tileFloor(S, f)
	for i = 0, 19 do
		local r = World.stallRect(i)
		if i % 10 ~= 0 then
			part({ size = Vector3.new(0.4, 4.5, r.h * K), cframe = CFrame.new(r.x * K, 2.25, (r.y + r.h / 2) * K), color = WOOD, material = M.Wood, parent = f })
			-- решётка над перегородкой
			for k2 = 0, 5 do
				part({ size = Vector3.new(0.12, 2.2, 0.12), cframe = CFrame.new(r.x * K, 5.6, r.y * K + 1 + k2 * (r.h * K - 2) / 5), color = IRON, material = M.Metal, parent = f, collide = false })
			end
			part({ size = Vector3.new(0.25, 0.25, r.h * K), cframe = CFrame.new(r.x * K, 6.7, (r.y + r.h / 2) * K), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		end
		-- кормушка у задней стены и поилка
		local back = r.row == 1 and (r.y + r.h - 12) or (r.y + 12)
		part({ size = Vector3.new(3, 1, 1.2), cframe = CFrame.new((r.x + r.w / 2) * K, 2.5, back * K), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		part({ size = Vector3.new(1.2, 0.7, 1.0), cframe = CFrame.new((r.x + r.w * 0.85) * K, 2.4, back * K), color = "#adb5bd", material = M.Metal, parent = f, collide = false })
		-- дверь денника: половинки по краям, посередине проход (дверь распахнута)
		local front = r.row == 1 and r.y or (r.y + r.h)
		for _, sx in ipairs({ 0.12, 0.88 }) do
			part({ size = Vector3.new(r.w * K * 0.24, 3.6, 0.3), cframe = CFrame.new((r.x + r.w * sx) * K, 1.8, front * K), color = "#b07a45", material = M.WoodPlanks, parent = f, collide = false })
			part({ size = Vector3.new(r.w * K * 0.24, 0.25, 0.34), cframe = CFrame.new((r.x + r.w * sx) * K, 3.65, front * K), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		end
		-- солома
		part({ size = Vector3.new(r.w * K * 0.8, 0.12, r.h * K * 0.5), cframe = CFrame.new((r.x + r.w / 2) * K, 0.25, (back + (r.row == 1 and -25 or 25)) * K) * CFrame.Angles(0, (i % 3) * 0.2, 0), color = "#e6c96b", material = M.Fabric, parent = f, collide = false, shadow = false })
	end
	label("🐴 КОНЮШНЯ", S.x + S.w / 2, S.y - 10, 30, "#3b2a1a", 300, 26)
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
	-- старт скачек: высокий флагшток с настоящим клетчатым флагом (полотнище из клеточек,
	-- клиент колышет его на ветру — Effects ищет модель RaceFlag)
	local st = World.START
	local flag = Instance.new("Model")
	flag.Name = "RaceFlag"
	flag.Parent = f
	part({ size = Vector3.new(1.6, 0.6, 1.6), cframe = CFrame.new(st.x * K, 0.3, st.y * K), color = "#8d8476", material = M.Cobblestone, parent = flag })
	part({ size = Vector3.new(10, 0.32, 0.32), cframe = CFrame.new(st.x * K, 5, st.y * K) * CFrame.Angles(0, 0, math.pi / 2), color = "#dee2e6", material = M.Metal, shape = Enum.PartType.Cylinder, parent = flag })
	part({ size = Vector3.new(0.6, 0.6, 0.6), cframe = CFrame.new(st.x * K, 10.1, st.y * K), color = "#ffd43b", material = M.Metal, shape = Enum.PartType.Ball, parent = flag, collide = false })
	local NX, NY, CS = 8, 5, 0.55
	for i = 0, NX - 1 do
		for j = 0, NY - 1 do
			local tile = part({ size = Vector3.new(CS, CS, 0.06), cframe = CFrame.new(st.x * K + 0.2 + (i + 0.5) * CS, 9.6 - (j + 0.5) * CS, st.y * K),
				color = (i + j) % 2 == 0 and "#111111" or "#ffffff", material = M.Fabric, parent = flag, collide = false })
			tile.Name = "FlagCell"
			tile:SetAttribute("I", i)
			tile:SetAttribute("J", j)
			tile.CastShadow = false
		end
	end
	label("🏁 СКАЧКИ", st.x, st.y, 11.5, "#3b2a1a", 260, 22)
end

-- дом как настоящий: каменный фундамент, оштукатуренные стены с деревянными балками, дверь с наличником,
-- крыльцом и ручкой, окна с рамами и ставнями на всех сторонах (в два этажа), труба, черепичная крыша.
-- Дверь смотрит туда, куда указывает hh.door (на ближайшую дорогу).
local SHUTTERS = { "#2f6f8f", "#2b8a3e", "#a33a2a", "#5c3d1e", "#7048e8", "#e67700" }
local function house(hh, parent)
	local r = hh
	local door = hh.door or "south"
	local WALL = 14
	local rnd = Util.rng(math.floor(r.x + r.y))
	rectBox({ x = r.x - 6, y = r.y - 6, w = r.w + 12, h = r.h + 12 }, 0, 1.2, "#8d8476", M.Cobblestone, true, parent)
	local walls = rectBox(r, 0, WALL, hh.wall, PLASTER, true, parent)
	walls.Name = "HouseWalls"
	-- балки: углы, пояс между этажами, верх
	for _, sx in ipairs({ 0, 1 }) do
		for _, sy in ipairs({ 0, 1 }) do
			part({ size = Vector3.new(0.7, WALL, 0.7), cframe = CFrame.new((r.x + r.w * sx) * K, WALL / 2, (r.y + r.h * sy) * K), color = DARKWOOD, material = M.Wood, parent = parent, collide = false })
		end
	end
	rectBox({ x = r.x - 2, y = r.y - 2, w = r.w + 4, h = r.h + 4 }, 7, 0.45, DARKWOOD, M.Wood, false, parent)
	rectBox({ x = r.x - 2, y = r.y - 2, w = r.w + 4, h = r.h + 4 }, WALL - 0.45, 0.45, DARKWOOD, M.Wood, false, parent)
	local roof = roofOver(r, WALL, hh.roof, 1.1, math.clamp(math.min(r.w, r.h) * K * 0.45, 3, 7))
	for _, d in ipairs(roof:GetChildren()) do d.Material = ROOFTILE end
	roof.Parent = parent
	-- труба
	local chx = (r.x + r.w * (0.22 + rnd() * 0.56)) * K
	local chz = (r.y + r.h * (rnd() < 0.5 and 0.3 or 0.7)) * K
	part({ size = Vector3.new(1.4, 7, 1.4), cframe = CFrame.new(chx, WALL + 3.5, chz), color = "#9c4a35", material = M.Brick, parent = parent, collide = false })
	part({ size = Vector3.new(1.8, 0.35, 1.8), cframe = CFrame.new(chx, WALL + 7.1, chz), color = "#6b6b6b", material = M.Concrete, parent = parent, collide = false })
	local shut = SHUTTERS[math.floor(rnd() * #SHUTTERS) + 1]
	for _, side in ipairs({ "south", "north", "east", "west" }) do
		local cf, wd = faceOf(r, side)
		if side == door then
			-- дверь с наличником, ручкой, ступенькой и козырьком
			part({ size = Vector3.new(2.6, 5.2, 0.25), cframe = cf * CFrame.new(0, 2.6 + 1.2, 0.12), color = "#6b4423", material = M.WoodPlanks, parent = parent, collide = false })
			for _, sx in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(0.3, 5.6, 0.35), cframe = cf * CFrame.new(sx * 1.45, 2.8 + 1.2, 0.15), color = "#f1ece2", material = M.Wood, parent = parent, collide = false })
			end
			part({ size = Vector3.new(3.2, 0.3, 0.35), cframe = cf * CFrame.new(0, 6.65, 0.15), color = "#f1ece2", material = M.Wood, parent = parent, collide = false })
			part({ size = Vector3.new(0.25, 0.25, 0.25), cframe = cf * CFrame.new(0.85, 3.8, 0.33), color = "#ffd43b", material = M.Metal, shape = Enum.PartType.Ball, parent = parent, collide = false })
			part({ size = Vector3.new(4, 0.6, 2), cframe = cf * CFrame.new(0, 0.6, 1), color = "#8d8476", material = M.Cobblestone, parent = parent })
			part({ size = Vector3.new(4.4, 0.25, 2.2), cframe = cf * CFrame.new(0, 7.3, 1.1) * CFrame.Angles(0.25, 0, 0), color = hh.roof, material = ROOFTILE, parent = parent, collide = false })
			for _, sx in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(0.25, 6, 0.25), cframe = cf * CFrame.new(sx * 2, 4.2, 2), color = DARKWOOD, material = M.Wood, parent = parent, collide = false })
			end
			-- окна по бокам от двери и на втором этаже
			for _, sx in ipairs({ -1, 1 }) do
				if wd > 10 then window(parent, cf, sx * wd * 0.3, 4.6, 2, 2.2, 0.2, { shutters = shut }) end
				window(parent, cf, sx * wd * 0.3, 10.6, 2, 2.2, 0.2, { shutters = shut })
			end
			window(parent, cf, 0, 10.6, 1.8, 2, 0.2, { shutters = shut })
		else
			local n = wd > 16 and 2 or 1
			for i = 1, n do
				local u = n == 1 and 0 or (i == 1 and -wd * 0.25 or wd * 0.25)
				window(parent, cf, u, 4.6, 2, 2.2, 0.2, { shutters = shut })
				window(parent, cf, u, 10.6, 2, 2.2, 0.2, { shutters = shut })
			end
		end
	end
	if hh.name then label(hh.name, r.x + r.w / 2, r.y + r.h / 2, WALL + 9, "#3b2a1a", 220, 18) end
end

-- заборы участков: штакетник у домов, жердяной забор у огородов (отрезки из World.FENCES)
local function buildFences(parent)
	local f = Instance.new("Folder")
	f.Name = "Fences"
	f.Parent = parent
	for _, q in ipairs(World.FENCES) do
		local a = Vector3.new(q[1] * K, 0, q[2] * K)
		local b = Vector3.new(q[3] * K, 0, q[4] * K)
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		if q.kind == "picket" then
			for _, yy in ipairs({ 0.9, 2.1 }) do
				part({ size = Vector3.new(0.12, 0.28, len), cframe = cf * CFrame.new(0, yy, 0), color = "#f1ece2", material = M.Wood, parent = f, collide = false })
			end
			local n = math.max(1, math.floor(len / 0.8))
			for i = 0, n - 1 do
				local z = -len / 2 + (i + 0.5) * len / n
				part({ size = Vector3.new(0.14, 2.7, 0.45), cframe = cf * CFrame.new(0.12, 1.35, z), color = "#fbf8f1", material = M.Wood, parent = f, collide = false })
				local tip = Instance.new("WedgePart")
				tip.Anchored = true
				tip.CanCollide = false
				tip.Size = Vector3.new(0.14, 0.3, 0.45)
				tip.Color = col("#fbf8f1")
				tip.Material = M.Wood
				tip.CFrame = CFrame.new(0, World.GROUND, 0) * cf * CFrame.new(0.12, 2.85, z)
				tip.Parent = f
			end
			part({ size = Vector3.new(0.35, 3, 0.35), cframe = cf * CFrame.new(0, 1.5, -len / 2), color = "#d8d0c2", material = M.Wood, parent = f, collide = false })
		else
			for _, yy in ipairs({ 1.0, 2.0 }) do
				part({ size = Vector3.new(0.3, 0.3, len), cframe = cf * CFrame.new(0, yy, 0), color = WOOD, material = M.Wood, parent = f, collide = false })
			end
			part({ size = Vector3.new(0.45, 2.6, 0.45), cframe = cf * CFrame.new(0, 1.3, -len / 2), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		end
		-- невидимая стенка, чтобы не перелезть (калитка и дорога — открыты)
		local inv = part({ size = Vector3.new(0.6, 5, len + 0.3), cframe = cf * CFrame.new(0, 2.5, 0), transparency = 1, parent = f })
		inv.CastShadow = false
		inv.CanQuery = false
		yieldSome()
	end
end

-- огороды: грядки с рыхлой землёй и овощами
local CROP = {
	cabbage = { "#8fce6a", "#5fa04a", 0.9, 0.7, true }, carrot = { "#4caf50", "#ff922b", 0.35, 0.8, false },
	pumpkin = { "#3f8f3a", "#f08c00", 1.1, 0.8, true }, corn = { "#6aa84f", "#f2c94c", 0.35, 2.6, false },
	potato = { "#5c9e3e", "#8bb85a", 0.6, 0.6, true },
}
local function buildPlots(parent)
	local f = Instance.new("Folder")
	f.Name = "Plots"
	f.Parent = parent
	for k, r in ipairs(World.PLOTS) do
		local c = CROP[r.crop] or CROP.cabbage
		local rnd = Util.rng(900 + k)
		local rows = math.floor((r.h - 50) / 34)
		for j = 0, rows - 1 do
			local y = r.y + 30 + j * 34
			local x1, x2 = r.x + 30, r.x + r.w - 30
			part({ size = Vector3.new((x2 - x1) * K, 0.35, 1.8), cframe = CFrame.new((x1 + x2) / 2 * K, 0.15, y * K), color = "#6b4a2b", material = M.Ground, parent = f, collide = false, shadow = false })
			local x = x1 + 10
			while x < x2 - 6 do
				local cf = CFrame.new(x * K, 0.3, y * K) * CFrame.Angles(0, rnd() * 6, 0)
				if r.crop == "corn" then
					part({ size = Vector3.new(0.16, c[4], 0.16), cframe = cf * CFrame.new(0, c[4] / 2, 0), color = c[1], material = M.Grass, parent = f, collide = false })
					part({ size = Vector3.new(0.9, 0.08, 0.25), cframe = cf * CFrame.new(0.3, c[4] * 0.6, 0) * CFrame.Angles(0, 0, -0.5), color = c[1], material = M.Grass, parent = f, collide = false, shadow = false })
					part({ size = Vector3.new(0.22, 0.55, 0.22), cframe = cf * CFrame.new(-0.12, c[4] * 0.55, 0), color = c[2], parent = f, collide = false, shadow = false })
				elseif c[5] then
					part({ size = Vector3.new(c[3], c[3] * 0.75, c[3]), cframe = cf * CFrame.new(0, c[3] * 0.35, 0), color = c[2], material = r.crop == "pumpkin" and M.SmoothPlastic or M.Grass, shape = Enum.PartType.Ball, parent = f, collide = false, shadow = false })
					part({ size = Vector3.new(c[3] * 1.3, 0.1, c[3] * 0.5), cframe = cf * CFrame.new(0, c[3] * 0.2, 0) * CFrame.Angles(0, 0.8, 0.25), color = c[1], material = M.Grass, parent = f, collide = false, shadow = false })
				else
					for i = 0, 2 do
						part({ size = Vector3.new(0.08, c[4], 0.08), cframe = cf * CFrame.Angles(0, i * 2.1, 0.3) * CFrame.new(0, c[4] / 2, 0), color = c[1], material = M.Grass, parent = f, collide = false, shadow = false })
					end
					part({ size = Vector3.new(0.18, 0.12, 0.18), cframe = cf * CFrame.new(0, 0.02, 0), color = c[2], parent = f, collide = false, shadow = false })
				end
				x += r.crop == "pumpkin" and 30 or 16
				yieldSome()
			end
		end
		-- пугало в каждом втором огороде
		if k % 2 == 1 then
			local cx, cy = (r.x + r.w - 40) * K, (r.y + 40) * K
			part({ size = Vector3.new(0.3, 4.2, 0.3), cframe = CFrame.new(cx, 2.1, cy), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
			part({ size = Vector3.new(3, 0.25, 0.25), cframe = CFrame.new(cx, 3.2, cy), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
			part({ size = Vector3.new(1.4, 1.4, 0.6), cframe = CFrame.new(cx, 3, cy), color = "#c92a2a", material = M.Fabric, parent = f, collide = false })
			part({ size = Vector3.new(0.9, 0.9, 0.9), cframe = CFrame.new(cx, 4.3, cy), color = "#e9d8a6", material = M.Fabric, shape = Enum.PartType.Ball, parent = f, collide = false })
			part({ size = Vector3.new(1.6, 0.12, 1.6), cframe = CFrame.new(cx, 4.72, cy), color = "#d4a017", material = M.Fabric, parent = f, collide = false })
			part({ size = Vector3.new(0.8, 0.5, 0.8), cframe = CFrame.new(cx, 4.98, cy), color = "#d4a017", material = M.Fabric, parent = f, collide = false })
		end
	end
	for _, r in ipairs(World.PLOTS) do label("🥕 Огород", r.x + r.w / 2, r.y - 10, 5, "#3b2a1a", 140, 16) end
end

local function buildVillage()
	local f = Instance.new("Folder")
	f.Name = "Village"
	f.Parent = root
	for _, hh in ipairs(World.HOUSES) do house(hh, f) end
	buildFences(f)
	buildPlots(f)
	local W = World.WELL
	local well = part({ size = Vector3.new(2.6, W.r * 2 * K, W.r * 2 * K), cframe = CFrame.new(W.x * K, 1.3, W.y * K) * CFrame.Angles(0, 0, math.pi / 2), color = "#8d8476", material = M.Cobblestone, shape = Enum.PartType.Cylinder, parent = f })
	well.Name = "Well"
	part({ size = Vector3.new(0.4, W.r * 1.6 * K, W.r * 1.6 * K), cframe = CFrame.new(W.x * K, 2.65, W.y * K) * CFrame.Angles(0, 0, math.pi / 2), color = "#3f8fc0", shape = Enum.PartType.Cylinder, parent = f, collide = false })
	-- крыша колодца на деревянных опорах, ворот с ручкой, верёвка и ведро
	local wr = W.r * K
	for _, sx in ipairs({ -1, 1 }) do
		part({ size = Vector3.new(0.45, 5.2, 0.45), cframe = CFrame.new(W.x * K + sx * (wr - 0.1), 3.9, W.y * K), color = DARKWOOD, material = M.Wood, parent = f })
		-- подкосы
		part({ size = Vector3.new(0.25, 1.6, 0.25), cframe = CFrame.new(W.x * K + sx * (wr - 0.55), 5.85, W.y * K) * CFrame.Angles(0, 0, sx * 0.7), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	end
	part({ size = Vector3.new(0.4, 0.4, wr * 2 + 0.6), cframe = CFrame.new(W.x * K, 6.35, W.y * K) * CFrame.Angles(0, math.pi / 2, 0), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	part({ size = Vector3.new(wr * 1.8, 0.55, 0.55), cframe = CFrame.new(W.x * K, 4.6, W.y * K) * CFrame.Angles(0, 0, 0), color = "#8a5a32", material = M.Wood, shape = Enum.PartType.Cylinder, parent = f, collide = false })
	part({ size = Vector3.new(0.18, 0.18, 1.2), cframe = CFrame.new(W.x * K + wr + 0.1, 4.6, W.y * K - 0.5), color = IRON, material = M.Metal, parent = f, collide = false })
	part({ size = Vector3.new(0.06, 1.6, 0.06), cframe = CFrame.new(W.x * K, 3.6, W.y * K), color = "#c9a66b", material = M.Fabric, parent = f, collide = false })
	part({ size = Vector3.new(0.7, 0.7, 0.7), cframe = CFrame.new(W.x * K, 2.65, W.y * K), color = "#8a5a32", material = M.WoodPlanks, parent = f, collide = false })
	roofOver({ x = W.x - W.r - 6, y = W.y - W.r - 4, w = W.r * 2 + 12, h = W.r * 2 + 8 }, 6.5, "#8c3b2a", 0.5).Parent = f
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
	-- большой парусник у причала: корпус с острым носом, палуба, рубка, мачта с парусами, борта
	local function ship(cf, hull)
		local m = Instance.new("Model")
		m.Name = "Ship"
		m.Parent = f
		local L, Wd = 22, 7.5
		local function P2(size, off, c, mat, shape)
			return part({ size = size, cframe = cf * off, color = c, material = mat or M.WoodPlanks, parent = m, collide = false, shape = shape })
		end
		-- корпус (вода на высоте -2): днище и борта
		P2(Vector3.new(L, 2.6, Wd), CFrame.new(0, -2.3, 0), hull)
		P2(Vector3.new(L, 0.5, Wd + 0.2), CFrame.new(0, -1.25, 0), "#f8f9fa")
		P2(Vector3.new(L, 0.9, 0.35), CFrame.new(0, -0.5, Wd / 2), hull)
		P2(Vector3.new(L, 0.9, 0.35), CFrame.new(0, -0.5, -Wd / 2), hull)
		-- нос: два клина сходятся в острие
		for _, sg in ipairs({ -1, 1 }) do
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide = true, false
			w.Color, w.Material = col(hull), M.WoodPlanks
			-- треугольник клина лежит горизонтально: прямой угол у середины носа, острие — вперёд
			w.Size = Vector3.new(3.5, Wd / 2, 6)
			w.CFrame = CFrame.new(0, World.GROUND, 0) * cf * CFrame.fromMatrix(Vector3.new(L / 2 + 3, -1.85, sg * Wd / 4), Vector3.new(0, -sg, 0), Vector3.new(0, 0, sg))
			w.Parent = m
		end
		-- корма
		P2(Vector3.new(1, 3.4, Wd), CFrame.new(-L / 2 - 0.3, -1.5, 0), "#7a4a22")
		-- палуба и рубка
		P2(Vector3.new(L + 2, 0.3, Wd - 0.4), CFrame.new(0.5, -0.95, 0), "#c8a27a")
		P2(Vector3.new(5, 3, 4.2), CFrame.new(-6, 0.6, 0), "#f1e3c6")
		for _, sz in ipairs({ -1, 1 }) do window(m, cf * CFrame.new(-6, 0, sz * 2.1) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0), 0, 0.9, 1.2, 1, 0.2) end
		P2(Vector3.new(5.6, 0.4, 4.8), CFrame.new(-6, 2.3, 0), hull)
		-- мачта, рея и паруса
		P2(Vector3.new(0.6, 16, 0.6), CFrame.new(2, 7, 0), "#5c3d1e", M.Wood)
		P2(Vector3.new(0.35, 0.35, Wd + 2), CFrame.new(2, 12.5, 0), "#5c3d1e", M.Wood)
		P2(Vector3.new(0.35, 0.35, Wd), CFrame.new(2, 3.2, 0), "#5c3d1e", M.Wood)
		local sail = P2(Vector3.new(0.12, 9, Wd + 1.4), CFrame.new(2.4, 7.8, 0) * CFrame.Angles(0, 0, -0.06), "#fdf8ee", M.Fabric)
		sail.CastShadow = true
		P2(Vector3.new(0.13, 1, Wd + 1.4), CFrame.new(2.45, 9.5, 0) * CFrame.Angles(0, 0, -0.06), "#e03131", M.Fabric)
		-- косой парус к носу
		local jib = Instance.new("WedgePart")
		jib.Anchored, jib.CanCollide = true, false
		jib.Size = Vector3.new(0.12, 10, 8)
		jib.Color, jib.Material = col("#fdf8ee"), M.Fabric
		jib.CFrame = CFrame.new(0, World.GROUND, 0) * cf * CFrame.new(6.5, 4.2, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		jib.Parent = m
		-- флажок на мачте
		P2(Vector3.new(0.08, 0.9, 1.6), CFrame.new(2, 15.4, 0.8), "#1c7ed6", M.Fabric)
		-- перила на борту
		for i = 0, 6 do
			for _, sz in ipairs({ -1, 1 }) do
				P2(Vector3.new(0.18, 1.1, 0.18), CFrame.new(-L / 2 + 1 + i * (L - 2) / 6, -0.3, sz * (Wd / 2 - 0.1)), "#5c3d1e", M.Wood)
			end
		end
		for _, sz in ipairs({ -1, 1 }) do P2(Vector3.new(L - 1, 0.18, 0.2), CFrame.new(0, 0.25, sz * (Wd / 2 - 0.1)), "#5c3d1e", M.Wood) end
		return m
	end
	local function pier(x, y, dir)
		-- dir: +1 — в сторону моря на восток
		local len = 34
		part({ size = Vector3.new(len, 0.6, 6), cframe = CFrame.new(x * K + dir * len / 2, 0.6, y * K), color = "#a0764a", material = M.WoodPlanks, parent = f })
		for i = 0, 4 do
			for _, s in ipairs({ -1, 1 }) do
				part({ size = Vector3.new(0.6, 5, 0.6), cframe = CFrame.new(x * K + dir * (i * len / 4), -1.2, y * K + s * 2.8), color = DARKWOOD, parent = f })
			end
		end
		-- большой парусник у конца причала (вода на 2 стада ниже земли — он стоит на воде)
		local bx = x * K + dir * (len - 9)
		ship(CFrame.new(bx, 0, y * K + 8.2) * CFrame.Angles(0, dir > 0 and 0 or math.pi, 0), dir > 0 and "#c92a2a" or "#1c4f8a")
	end
	pier(World.PIER.x - 20, World.PIER.y, 1)
	label("⛵ Пристань", World.PIER.x, World.PIER.y - 40, 8, "#1c4f8a", 220, 20)
	for _, I in ipairs(World.ISLANDS) do
		pier(I.pier.x, I.pier.y, -1)
		-- конюшня на 5 денников
		for _, s in ipairs(World.SOLIDS) do
			if s.kind == "stable" and World.inRect(s.x, s.y, I.stable, 5) then rectBox(s, 0, 16, "#c8a27a", M.WoodPlanks, true, f) end
		end
		local iroof = roofOver(I.stable, 16, "#2f6f8f", 1)
		for _, d in ipairs(iroof:GetChildren()) do d.Material = ROOFTILE end
		iroof.Parent = f
		tileFloor(I.stable, f)
		-- окна в задней стене
		local icf, iwd = faceOf(I.stable, "north")
		for k = 0, 4 do window(f, icf, -iwd / 2 + iwd * (k + 0.5) / 5, 10, 2.4, 2.2, 1, { shutters = "#2f6f8f" }) end
		for k = 1, 4 do
			part({ size = Vector3.new(0.4, 4, 12), cframe = CFrame.new((I.stable.x + k * 68) * K, 2, (I.stable.y + 70) * K), color = WOOD, parent = f })
		end
		label("🏝️ " .. I.name, I.x, I.y - I.ry + 160, 12, "#1c4f8a", 400, 24)
		-- пастбище
		for _, s in ipairs(World.SOLIDS) do
			if s.kind == "fence" and World.inRect(s.x + s.w / 2, s.y + s.h / 2, I.pasture, 20) then fenceRect(s, f) end
			if s.kind == "post" and math.abs(s.x - I.pen.x) < I.pen.r + 30 and math.abs(s.y - I.pen.y) < I.pen.r + 30 then
				part({ size = Vector3.new(1.0, 3.6, 1.0), cframe = CFrame.new((s.x + 9) * K, 1.8, (s.y + 9) * K), color = DARKWOOD, material = M.Wood, parent = f })
			end
		end
		-- круглый загон: столбики соединены деревянными жердями (в проходе жердей нет)
		local pen = I.pen
		for k = 0, 23 do
			local a1, a2 = k / 24 * math.pi * 2, (k + 1) / 24 * math.pi * 2
			local gate = math.abs(a1 - math.pi * 1.5) < 0.3 or math.abs(a2 - math.pi * 1.5) < 0.3
			if not gate then
				local x1, y1 = pen.x + math.cos(a1) * pen.r, pen.y + math.sin(a1) * pen.r
				local x2, y2 = pen.x + math.cos(a2) * pen.r, pen.y + math.sin(a2) * pen.r
				for _, hy in ipairs({ 1.3, 2.8 }) do
					segment(x1, y1, x2, y2, hy - 0.15, 0.3, 0.3, WOOD, M.Wood, false, f)
				end
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
			-- настил чуть выше земли острова: концы моста лежат на островах, щели нет
			local cf = CFrame.lookAt(Vector3.new(x * K, World.SKY_Y - 0.15, y * K), Vector3.new(x * K, World.SKY_Y - 0.15, y * K) + (c - a))
			part({ size = Vector3.new(World.BRIDGE_W * 2 * K, 0.5, 3.1), cframe = cf, color = i % 2 == 0 and "#a0764a" or "#8a5a32", material = M.WoodPlanks, parent = f })
		end
		-- столбики и перила из лиан по обеим сторонам
		local dir = Vector3.new(b[3] - b[1], 0, b[4] - b[2]).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local hw = World.BRIDGE_W * K - 0.3
		local np = math.max(2, math.floor(len * K / 9))
		local prevs = {}
		for i = 0, np do
			local t = i / np
			local p = Vector3.new((b[1] + (b[3] - b[1]) * t) * K, World.SKY_Y, (b[2] + (b[4] - b[2]) * t) * K)
			for _, sg in ipairs({ -1, 1 }) do
				local q = p + side * hw * sg
				part({ size = Vector3.new(0.4, 3.4, 0.4), cframe = CFrame.new(q + Vector3.new(0, 1.6, 0)), color = "#6b4423", material = M.Wood, parent = f })
				local pv = prevs[sg]
				if pv then
					for _, hy in ipairs({ 1.6, 3.1 }) do
						local a2, b2 = pv + Vector3.new(0, hy, 0), q + Vector3.new(0, hy, 0)
						part({ size = Vector3.new(0.18, 0.18, (b2 - a2).Magnitude), cframe = CFrame.lookAt((a2 + b2) / 2, b2), color = "#2f9e44", material = M.Grass, parent = f, collide = false })
					end
				end
				prevs[sg] = q
			end
		end
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
	-- колея шире — поезд стал больше
	part({ size = Vector3.new((R.x2 - R.x1) * K + 140, 0.3, 9), cframe = CFrame.new((R.x1 + R.x2) / 2 * K, 0.1, R.y * K), color = "#8b8378", material = M.Pebble, parent = f, collide = false, shadow = false })
	for _, dz in ipairs({ -2.5, 2.5 }) do
		part({ size = Vector3.new((R.x2 - R.x1) * K + 140, 0.45, 0.4), cframe = CFrame.new((R.x1 + R.x2) / 2 * K, 0.6, R.y * K + dz), color = "#868e96", material = M.Metal, parent = f, collide = false })
	end
	local x = R.x1 * K - 70
	while x < R.x2 * K + 70 do
		part({ size = Vector3.new(1.1, 0.3, 7), cframe = CFrame.new(x, 0.3, R.y * K), color = "#6b4423", material = M.Wood, parent = f, collide = false })
		x += 3.5
		yieldSome()
	end
	local St = World.STATION
	rectBox({ x = St.x, y = St.y, w = St.w, h = St.h }, 0, 0.8, "#c8a27a", M.WoodPlanks, true, f)
	house({ x = St.x + 30, y = St.y - 60, w = 160, h = 70, wall = "#f1e3c6", roof = "#c92a2a" }, f)
	-- навес над платформой на деревянных опорах с перекладинами
	local canopy = { x = St.x + 220, y = St.y, w = 280, h = St.h }
	roofOver(canopy, 7.3, "#2f6f8f", 0).Parent = f
	for px = canopy.x + 8, canopy.x + canopy.w - 4, 45 do
		for _, py in ipairs({ canopy.y + 6, canopy.y + canopy.h - 6 }) do
			part({ size = Vector3.new(0.55, 6.5, 0.55), cframe = CFrame.new(px * K, 0.8 + 3.25, py * K), color = DARKWOOD, material = M.Wood, parent = f })
			part({ size = Vector3.new(0.3, 2, 0.3), cframe = CFrame.new(px * K + 0.6, 6.5, py * K) * CFrame.Angles(0, 0, -0.75), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
		end
	end
	for _, py in ipairs({ canopy.y + 6, canopy.y + canopy.h - 6 }) do
		part({ size = Vector3.new(canopy.w * K, 0.45, 0.45), cframe = CFrame.new((canopy.x + canopy.w / 2) * K, 7.25, py * K), color = DARKWOOD, material = M.Wood, parent = f, collide = false })
	end
	label("🚂 СТАНЦИЯ", St.x + 110, St.y - 25, 24, "#c92a2a", 300, 22)
	for _, g in ipairs(World.GROTTOS) do label("🕳️ Пещерка", g.x, g.y - g.r - 30, 20, "#343a40", 260, 18) end
end

-- лавовые озёра: светящаяся поверхность лавы (материал Neon), тёмная корка, каменный берег,
-- огоньки и искры. Раньше лава была только материалом рельефа и издалека выглядела как камень.
local function buildLava()
	local f = Instance.new("Folder")
	f.Name = "Lava"
	f.Parent = root
	for li, L in ipairs(World.LAKES) do
		if L.lava then
			local rnd = Util.rng(500 + li)
			local step = 30
			local n = 0
			for x = L.x - L.rx * 1.3, L.x + L.rx * 1.3, step do
				for y = L.y - L.ry * 1.3, L.y + L.ry * 1.3, step do
					if World.inBlob(L, x, y, -6) then
						n += 1
						local crust = rnd() < 0.12
						local c = crust and "#2b1d18" or ({ "#ff3d00", "#ff6d00", "#ff9100", "#ffb300", "#ff5722" })[math.floor(rnd() * 5) + 1]
						local p = part({ size = Vector3.new(step * K + 0.2, 0.3, step * K + 0.2), cframe = CFrame.new(x * K, 0.12 + rnd() * 0.06, y * K),
							color = c, material = crust and M.Basalt or M.Neon, parent = f, collide = false, shadow = false })
						p.CanQuery = false
						if not crust and n % 9 == 0 then
							local l = Instance.new("PointLight")
							l.Color = col("#ff7a1a")
							l.Range = 26
							l.Brightness = 2.2
							l.Parent = p
						end
						if not crust and n % 7 == 0 then
							local pe = Instance.new("ParticleEmitter")
							pe.Rate = 3
							pe.Lifetime = NumberRange.new(1, 2.2)
							pe.Speed = NumberRange.new(3, 7)
							pe.SpreadAngle = Vector2.new(25, 25)
							pe.EmissionDirection = Enum.NormalId.Top
							pe.LightEmission = 1
							pe.Color = ColorSequence.new(col("#ffd166"), col("#ff3d00"))
							pe.Size = NumberSequence.new(0.35, 0)
							pe.Acceleration = Vector3.new(0, -6, 0)
							pe.Parent = p
						end
						yieldSome()
					end
				end
			end
			-- каменный берег
			local pts = World.blobPoly(L, 10, 36)
			for _, q in ipairs(pts) do
				local s0 = 1.6 + rnd() * 2.2
				part({ size = Vector3.new(s0 * 1.4, s0, s0 * 1.2), cframe = CFrame.new(q.x * K, s0 * 0.35, q.y * K) * CFrame.Angles(rnd(), rnd() * 6, rnd() * 0.4),
					color = rnd() < 0.5 and "#1f1a1b" or "#2e2627", material = M.Basalt, parent = f })
			end
			label("🌋 " .. (L.name or "Лава"), L.x, L.y - L.ry - 40, 10, "#c92a2a", 300, 20)
		end
	end
end

-- замерить, где на самом деле поверхность земли: блоки рельефа выравниваются по сетке 4 стада,
-- и верх может оказаться не на нуле. Берём медиану по нескольким ровным местам фермы.
measureGround = function()
	local pts = {
		-- только ровный двор фермы: на поле и в лесу теперь холмы
		{ World.OX + 960, World.OY + 470 }, { World.PADDOCK.x + 200, World.PADDOCK.y + 200 }, { World.JUMPF.x + 300, World.JUMPF.y + 300 },
		{ World.JUMPF.x + 900, World.JUMPF.y + 200 }, { World.PADDOCK.x + 400, World.PADDOCK.y + 300 },
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

-- этап постройки: ошибка в одном этапе не должна останавливать остальные
local function stage(name, fn)
	local t0 = os.clock()
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		print(string.format("[HorseFarm] %s: %.1f с", name, os.clock() - t0))
	else
		warn("[HorseFarm] ОШИБКА на этапе «" .. name .. "»: " .. tostring(err))
	end
	return ok
end

function WB.build()
	root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace
	WB.root = root
	stage("рельеф", buildTerrain)
	-- страховка: если рельеф не построился, игрок не провалится в пустоту
	local floor = Instance.new("Part")
	floor.Name = "SafetyFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(World.W * K + 40, 2, World.H * K + 40)
	floor.CFrame = CFrame.new(World.W * K / 2, -15, World.H * K / 2)
	floor.Color = col("#86b84f")
	floor.Material = M.Grass
	floor.Parent = root
	if not stage("замер земли", measureGround) then
		World.GROUND = 0
		workspace:SetAttribute("GroundY", 0)
	end
	stage("границы воды", buildBarriers)
	stage("ферма", buildFarm)
	stage("деревня и рынок", buildVillage)
	stage("пристани и острова", buildSeaside)
	stage("пещера, небо и железная дорога", buildCaveAndSky)
	stage("лава", buildLava)
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
WB.stage = stage

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
