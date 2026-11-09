--[[
	Сборка воксельной лошади из деталей Roblox (аналог makeHorseObj/poseHorse из js/voxel.js).
	Кубики одного цвета склеиваются в прямоугольники (жадное слияние), поэтому деталей немного.
	Модель: Root (якорь) → Content (наклон тела) → Head/Ears/Legs/Tail/Wings на суставах Motor6D.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local Genetics = require(Shared.Genetics)
local Horses = require(Shared.Horses)
local HV = require(Shared.HorseVoxels)

local HB = {}
local color = Util.color
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

local function newPart(size, cf, c, material, transparency)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or PLASTIC
	p.Color = color(c)
	p.Size = size
	p.CFrame = cf
	if transparency then p.Transparency = transparency end
	if material == NEON then p.CastShadow = false end
	return p
end

--[[ жадное слияние кубиков в прямоугольники по слоям z ]]
-- cells: { ["x|y|z"] = color }; offset — сдвиг всех кубиков (в кубиках); V — размер кубика
local function addCells(cells, parent, weldTo, V, baseCF, material, transparency, list)
	local layers = {}
	for k, c in pairs(cells) do
		local x, y, z = HV.parse(k)
		local L = layers[z]
		if not L then
			L = {}
			layers[z] = L
		end
		L[x .. "|" .. y] = c
	end
	for z, L in pairs(layers) do
		-- границы слоя
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for k in pairs(L) do
			local x, y = string.match(k, "^(-?%d+)|(-?%d+)$")
			x, y = tonumber(x), tonumber(y)
			if x < minX then minX = x end
			if x > maxX then maxX = x end
			if y < minY then minY = y end
			if y > maxY then maxY = y end
		end
		local used = {}
		for y = minY, maxY do
			for x = minX, maxX do
				local key = x .. "|" .. y
				local c = L[key]
				if c and not used[key] then
					local w = 1
					while L[(x + w) .. "|" .. y] == c and not used[(x + w) .. "|" .. y] do w += 1 end
					local h = 1
					while true do
						local ok = true
						for i = 0, w - 1 do
							local kk = (x + i) .. "|" .. (y + h)
							if L[kk] ~= c or used[kk] then ok = false; break end
						end
						if not ok then break end
						h += 1
					end
					for j = 0, h - 1 do
						for i = 0, w - 1 do used[(x + i) .. "|" .. (y + j)] = true end
					end
					local center = Vector3.new((x + w / 2) * V, (y + h / 2) * V, (z + 0.5) * V)
					local p = newPart(Vector3.new(w * V, h * V, V), baseCF * CFrame.new(center), c, material, transparency)
					p.Parent = parent
					if weldTo then
						local wc = Instance.new("WeldConstraint")
						wc.Part0 = weldTo
						wc.Part1 = p
						wc.Parent = p
					else
						p.Anchored = true
					end
					if list then table.insert(list, p) end
				end
			end
		end
	end
end
HB.addCells = addCells

local function pivotPart(name, cf, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = cf
	p.Parent = parent
	return p
end
local function motor(p0, p1, c0)
	local m = Instance.new("Motor6D")
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = CFrame.new()
	m.Parent = p1
	return m
end

local function wetCopy(map, wl)
	if wl == 0 then return map end
	local r = {}
	for k, c in pairs(map) do r[k] = Util.mix(c, "#0b1a2a", 0.13 * wl) end
	return r
end

-- look — Horses.look(h); opts.tack — упряжь (седло, уздечка), opts.anchored — для портрета
function HB.build(look, opts)
	opts = opts or {}
	local h = look
	local ph = Horses.pheno(h)
	local B = Genetics.BREEDS[h.breed] or Genetics.BREEDS.mix
	local mag = h.magic or {}
	local s = Horses.sizeOf(h)
	local V = HV.V * s
	local model = Instance.new("Model")
	model.Name = "Horse"
	local origin = CFrame.new()
	local root = pivotPart("Root", origin, model)
	root.Anchored = true
	model.PrimaryPart = root
	local content = pivotPart("Content", origin, model)
	local contentM = motor(root, content, CFrame.new())
	local wl = HV.wetLevel(h)
	local allGlow = ph.holiday == "newyearglow"
	local hc = HV.horseCells(h, ph, B)
	addCells(wetCopy(hc.cells, wl), model, content, V, origin, PLASTIC)
	addCells(hc.glow, model, content, V, origin, NEON)
	-- голова
	local HP = Vector3.new(HV.HEAD_PIV[1] * V, HV.HEAD_PIV[2] * V, 0)
	local head = pivotPart("Head", origin * CFrame.new(HP), model)
	local headM = motor(content, head, CFrame.new(HP))
	addCells(wetCopy(hc.headCells, wl), model, head, V, origin, PLASTIC)
	addCells(hc.headGlow, model, head, V, origin, NEON)
	local EP = Vector3.new(HV.EAR_PIV[1] * V, HV.EAR_PIV[2] * V, 0)
	local ears = pivotPart("Ears", origin * CFrame.new(EP), model)
	local earsM = motor(head, ears, CFrame.new(EP - HP))
	addCells(wetCopy(hc.ears, wl), model, ears, V, origin, PLASTIC)
	addCells(hc.earsGlow, model, ears, V, origin, NEON)
	-- ноги
	local legs = {}
	local LP = { { 5, -1.5 }, { 5, 1.5 }, { -6, -1.5 }, { -6, 1.5 } }
	for i = 1, 4 do
		local pos = Vector3.new(LP[i][1] * V, 7 * V, LP[i][2] * V)
		local piv = pivotPart("Leg" .. i, origin * CFrame.new(pos), model)
		local m = motor(content, piv, CFrame.new(pos))
		local lc = HV.legCells(h, ph, i - 1)
		local base = origin * CFrame.new(pos)
		addCells(wetCopy(lc.cells, wl), model, piv, V, base, allGlow and NEON or PLASTIC)
		addCells(lc.glow, model, piv, V, base, NEON)
		if mag.cloud then addCells(HV.cloudCells(), model, piv, V, base, NEON, 0.1) end
		legs[i] = { m = m, pos = pos }
	end
	-- хвост
	local TP = Vector3.new(-8 * V, 12.5 * V, 0.5 * V)
	local tail = pivotPart("Tail", origin * CFrame.new(TP), model)
	local tailM = motor(content, tail, CFrame.new(TP))
	local tc = HV.tailCells(h, ph, B)
	addCells(wetCopy(tc.cells, wl), model, tail, V, origin * CFrame.new(TP), allGlow and NEON or PLASTIC)
	addCells(tc.glow, model, tail, V, origin * CFrame.new(TP), NEON)
	-- крылья
	local wings = {}
	if mag.wings then
		local wtype = Horses.wingType(mag.wings)
		local def = HV.wingDef(wtype, h, ph)
		for _, sgn in ipairs({ -1, 1 }) do
			local pos = Vector3.new(2 * V, 12.5 * V, (sgn > 0 and 3 or -3) * V)
			local piv = pivotPart("Wing", origin * CFrame.new(pos), model)
			local m = motor(content, piv, CFrame.new(pos))
			local cells = def.cells
			if sgn < 0 then
				cells = {}
				for k, c in pairs(def.cells) do
					local x, y, z = HV.parse(k)
					cells[HV.key3(x, y, -z - 1)] = c
				end
			end
			addCells(cells, model, piv, V, origin * CFrame.new(pos), def.glass and GLASS or PLASTIC, def.glass and 0.35 or nil)
			table.insert(wings, { m = m, pos = pos, s = sgn, f = HV.FLAP[wtype] or HV.FLAP.pegasus })
		end
	end
	-- упряжь
	if opts.tack then
		local tk = HV.tackCells(opts.tack)
		addCells(tk.cells, model, content, V, origin, PLASTIC)
		addCells(tk.glow, model, content, V, origin, NEON)
	end
	-- сияние у светящихся
	if ph.glow then
		local l = Instance.new("PointLight")
		l.Color = color(ph.glow)
		l.Range = 10
		l.Brightness = 1.2
		l.Parent = content
	end
	if mag.horn or ph.elem == "fire" or ph.elem == "sun" or ph.holiday == "newyearglow" then
		local l = Instance.new("PointLight")
		l.Color = color(ph.elem == "fire" and "#ff922b" or ph.elem == "sun" and "#ffe066" or ph.holiday and ph.body or "#fff3bf")
		l.Range = 8
		l.Brightness = 0.8
		l.Parent = head
	end
	local e = {
		model = model, root = root, content = content, contentM = contentM, head = head, headM = headM, HP = HP,
		earsM = earsM, EP = EP, legs = legs, tailM = tailM, TP = TP, wings = wings, ph = ph, s = s, seed = h.seed,
		cloud = mag.cloud, V = V, moveS = 0,
	}
	if opts.tack then HB.addBridle(e, opts.tack) end
	if opts.anchored then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
	end
	return e
end

--[[ ---------- тонкие ремешки: уздечка, повод, верёвка на шее ----------
	Точки — в кубиках лошади (как в HorseVoxels): голова занимает x 11..16, y 14..17, z -1..1,
	морда x 14..16, y 14..16; шея — x 7..11. Ремешок — тонкий брусок между двумя точками,
	приваренный к голове (уздечка) или к корпусу (повод). ]]
local LEATHER = Enum.Material.Fabric
pcall(function() LEATHER = Enum.Material.Leather end)
local function strap(e, base, a, b, d, c, material)
	local V = e.V
	local off = base == e.head and e.HP or Vector3.zero
	local pa = Vector3.new(a[1] * V, a[2] * V, a[3] * V) - off
	local pb = Vector3.new(b[1] * V, b[2] * V, b[3] * V) - off
	local dir = pb - pa
	local len = dir.Magnitude
	if len < 0.01 then return nil end
	local up = math.abs(dir.Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local p = newPart(Vector3.new(d, d, len + d), base.CFrame * CFrame.lookAt((pa + pb) / 2, pb, up), c, material or LEATHER)
	p.CastShadow = false
	p.Parent = e.model
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	return p
end
local function knob(e, base, at, d, c, material, shape)
	local V = e.V
	local off = base == e.head and e.HP or Vector3.zero
	local p = newPart(Vector3.new(d, d, d), base.CFrame * CFrame.new(Vector3.new(at[1] * V, at[2] * V, at[3] * V) - off), c, material)
	p.Shape = shape or Enum.PartType.Ball
	p.CastShadow = false
	p.Parent = e.model
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	return p
end

-- уздечка как настоящая: оголовье за ушами, налобный ремень, нащёчные ремни, капсюль,
-- подбородный ремень, железо (трензель) с кольцами и тонкий повод к седлу
function HB.addBridle(e, R)
	local c = R.bridleColor or "#2b1a10"
	local d = 0.2 * e.V
	local H = e.head
	local Z = 1.07
	local MANE_TOP = 18.07
	for _, z in ipairs({ -Z, Z }) do
		strap(e, H, { 10.95, 13.93, z }, { 10.95, MANE_TOP, z }, d, c)           -- оголовье (по бокам)
		strap(e, H, { 12.2, 17.07, z }, { 10.95, 16.4, z }, d, c)               -- налобный ремень сбоку
		strap(e, H, { 10.95, 16.0, z }, { 15.2, 14.5, z }, d, c)                -- нащёчный ремень к кольцу
		strap(e, H, { 14.3, 13.93, z }, { 14.3, 16.07, z }, d, c)               -- капсюль сбоку
	end
	strap(e, H, { 10.95, MANE_TOP, -Z }, { 10.95, MANE_TOP, Z }, d, c)          -- оголовье поверх гривы
	strap(e, H, { 10.95, 13.93, -Z }, { 10.95, 13.93, Z }, d, c)                -- подбородный (под горлом)
	strap(e, H, { 12.2, 17.07, -Z }, { 12.2, 17.07, Z }, d, c)                  -- налобный ремень
	strap(e, H, { 14.3, 16.07, -Z }, { 14.3, 16.07, Z }, d, c)                  -- капсюль сверху
	strap(e, H, { 14.3, 13.93, -Z }, { 14.3, 13.93, Z }, d, c)                  -- капсюль снизу
	-- трензель: тонкая железка через рот и два кольца
	strap(e, H, { 15.25, 14.5, -1.25 }, { 15.25, 14.5, 1.25 }, d * 0.7, "#ced4da", Enum.Material.Metal)
	for _, z in ipairs({ -1.25, 1.25 }) do knob(e, H, { 15.25, 14.5, z }, 0.55 * e.V, "#dee2e6", Enum.Material.Metal) end
	-- повод: от колец вдоль шеи к луке седла
	for _, sg in ipairs({ -1, 1 }) do
		strap(e, H, { 15.25, 14.5, 1.25 * sg }, { 7.9, 15.3, 1.3 * sg }, d * 0.85, c)
		strap(e, e.content, { 7.9, 15.3, 1.3 * sg }, { 5.6, 15.35, 1.3 * sg }, d * 0.85, c)
		strap(e, e.content, { 5.6, 15.35, 1.3 * sg }, { 1.6, 15.45, 0.8 * sg }, d * 0.85, c)
	end
	-- украшения уздечки на налобном ремне
	local bs = R.bridleStyle or "classic"
	local deco = bs == "crystal" and { { "#74c0fc", NEON }, { "#f783ac", NEON }, { "#b197fc", NEON } }
		or bs == "plant" and { { "#69db7c", PLASTIC }, { "#ff8fab", PLASTIC }, { "#ffd43b", PLASTIC } }
		or bs == "shell" and { { "#ffc9de", PLASTIC }, { "#fff5f0", NEON }, { "#ffc9de", PLASTIC } }
	if deco then
		for i, z in ipairs({ -0.75, 0, 0.75 }) do
			knob(e, H, { 12.2, 17.2, z }, 0.42 * e.V, deco[i][1], deco[i][2], bs == "crystal" and Enum.PartType.Block or Enum.PartType.Ball)
		end
	end
end

-- тонкая верёвка на шее у лошади, которую ведут: петля вокруг шеи и узел снизу.
-- Возвращает Attachment в узле — к нему крепится сама верёвка (Beam) из руки игрока.
function HB.addCollar(e)
	local c = "#c9a66b"
	local d = 0.14 * e.V
	local H = e.head
	local X, Z = 9.4, 1.08
	for _, z in ipairs({ -Z, Z }) do strap(e, H, { X, 12.9, z }, { X, 18.08, z }, d, c, Enum.Material.Fabric) end
	strap(e, H, { X, 18.08, -Z }, { X, 18.08, Z }, d, c, Enum.Material.Fabric)
	strap(e, H, { X, 12.9, -Z }, { X, 12.9, Z }, d, c, Enum.Material.Fabric)
	knob(e, H, { X, 12.8, 0 }, 0.4 * e.V, c, Enum.Material.Fabric)
	local att = Instance.new("Attachment")
	att.Name = "RopeKnot"
	att.Position = Vector3.new(X * e.V, 12.75 * e.V, 0) - e.HP
	att.Parent = H
	return att
end

--[[ поза: как poseHorse в JS. o = { x, y(высота земли), z, angle, spd, phase, fly, lift, act, t, headTurn, hover } ]]
function HB.pose(e, o)
	local s = e.s
	local t = o.t
	local fly = o.fly or 0
	local lift = o.lift or 0
	local hover = e.cloud and (1.3 + math.sin(t * 2 + (e.seed % 9)) * 0.35) * s or 0
	local A = fly <= 0 and HV.actPose(o.act) or nil
	local K = HV.V * s / HV.V -- масштаб поз (позы считаются в кубиках V)
	local up = hover + lift * 2.6 * s + (o.flyH or 0) * fly + (A and A.up * s or 0)
	e.root.CFrame = CFrame.new(o.pos + Vector3.new(0, up, 0)) * CFrame.Angles(0, -o.angle + (A and A.yaw or 0), lift * 0.25 + fly * 0.08)
	local px, py = A and A.px * K or 0, A and A.py * K or 0
	e.contentM.C0 = CFrame.new(px, py, 0) * CFrame.Angles(A and A.roll or 0, 0, A and A.pitch or 0) * CFrame.new(-px, -py, 0)
	local move = math.min(1, (o.spd or 0) / 110)
	-- кивок головой в такт шагам. Раньше голова кивала вдвое чаще ног, а сила кивка
	-- скакала вместе со скоростью от сервера — голова тряслась. Теперь кивок сглажен и в такт ногам.
	e.moveS = (e.moveS or 0) + (move - (e.moveS or 0)) * 0.12
	local nod = math.clamp((e.moveS - 0.25) / 0.35, 0, 1)
	local bob = (fly <= 0 and not A) and math.sin(o.phase or 0) * 0.045 * nod or 0
	local headYaw = A and A.headYaw or (o.headTurn or 0) * 0.7
	e.headM.C0 = CFrame.new(e.HP) * CFrame.Angles(0, headYaw, (A and A.head or 0) + bob + (fly > 0 and 0.15 or 0))
	e.earsM.C0 = CFrame.new(e.EP - e.HP) * CFrame.Angles(0, 0, A and -A.ears or 0)
	for i, l in ipairs(e.legs) do
		local diag = (i == 1 or i == 4) and 1 or -1
		local r
		if fly > 0 then r = (i <= 2 and 0.7 or -0.5) * fly
		elseif A and A.legs then r = A.legs[i]
		elseif lift > 0 then r = (i <= 2 and 0.9 or -0.6) * lift
		else r = math.sin(o.phase or 0) * diag * 0.55 * move end
		l.m.C0 = CFrame.new(l.pos) * CFrame.Angles(0, 0, r)
	end
	local ty = math.sin(t * 2.2 + (e.seed % 7)) * 0.35
	local tz = move * 0.5 + fly * 0.4 + ((A and A.k == "kick") and 0.6 or 0)
	e.tailM.C0 = CFrame.new(e.TP) * CFrame.Angles(0, ty, tz)
	for _, w in ipairs(e.wings) do
		local f = w.f
		local flap
		if fly > 0 then flap = math.sin(t * f.speed) * f.amp
		elseif move > 0.6 then flap = math.sin(t * f.speed * 0.7) * f.amp * 0.4
		else flap = f.rest end
		w.m.C0 = CFrame.new(w.pos) * CFrame.Angles(w.s * (flap + (fly > 0 and 0.1 or 0)), 0, 0)
	end
end

--[[ всадник-бот (соперник на скачках): стандартный человечек Roblox в седле.
	Шаблон RiderTemplate создаёт сервер (People.lua), здесь его клонируем, красим и сажаем. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function setLimbColor(rig, names, c)
	for _, n in ipairs(names) do
		local p = rig:FindFirstChild(n)
		if p and p:IsA("BasePart") then p.Color = color(c) end
	end
end
function HB.addRider(e, R)
	local tpl = ReplicatedStorage:FindFirstChild("RiderTemplate")
	if not tpl then return end
	local rig = tpl:Clone()
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then bc:Destroy() end
	setLimbColor(rig, { "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }, R.shirt or "#4dabf7")
	setLimbColor(rig, { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }, "#33415c")
	setLimbColor(rig, { "LeftFoot", "RightFoot" }, "#1f1d22")
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.EvaluateStateMachine = false
		hum.PlatformStand = true
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	-- поза «сидя»: бёдра вперёд, голени вниз
	for _, j in ipairs(rig:GetDescendants()) do
		if j:IsA("Motor6D") then
			if j.Name == "LeftHip" or j.Name == "RightHip" then
				j.C0 = j.C0 * CFrame.Angles(math.rad(90), 0, j.Name == "LeftHip" and -0.25 or 0.25)
			elseif j.Name == "LeftKnee" or j.Name == "RightKnee" then
				j.C0 = j.C0 * CFrame.Angles(math.rad(-90), 0, 0)
			elseif j.Name == "LeftShoulder" or j.Name == "RightShoulder" then
				j.C0 = j.C0 * CFrame.Angles(math.rad(40), 0, 0)
			end
		end
	end
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hrp then
		rig:Destroy()
		return
	end
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	-- шлем
	local head = rig:FindFirstChild("Head")
	if head then
		local helm = Instance.new("Part")
		helm.Shape = Enum.PartType.Ball
		helm.Size = Vector3.new(1.35, 1.35, 1.35)
		helm.Color = color(R.helmet or "#222a3a")
		helm.CanCollide = false
		helm.Massless = true
		helm.CFrame = head.CFrame * CFrame.new(0, 0.32, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, helm
		w.Parent = helm
		helm.Parent = rig
	end
	-- в седло: лошадь смотрит по +X, человечек — по -Z; низ корпуса — на верх седла
	local V = e.V
	local hipH = (hum and hum.HipHeight or 2)
	local seat = Vector3.new(-1 * V, 15 * V + hrp.Size.Y / 2 + 0.15, 0)
	rig:PivotTo(e.content.CFrame * CFrame.new(seat) * CFrame.Angles(0, -math.pi / 2, 0))
	local w = Instance.new("WeldConstraint")
	w.Part0 = e.content
	w.Part1 = hrp
	w.Parent = hrp
	rig.Parent = e.model
	e.rider = rig
	e.riderHip = hipH
end

-- портрет лошади во вьюпорте
local portraitCache = {}
local cacheOrder = {}
function HB.portraitModel(look, tack)
	local key = tostring(look.id) .. "|" .. Horses.lookKey(look) .. "|" .. tostring(look.maneDye) .. "|" .. tostring(look.maneStyle) .. (tack and "t" or "")
	local m = portraitCache[key]
	if not m then
		local e = HB.build(look, { anchored = true, tack = tack })
		m = e.model
		portraitCache[key] = m
		table.insert(cacheOrder, key)
		if #cacheOrder > 60 then
			local old = table.remove(cacheOrder, 1)
			if portraitCache[old] then portraitCache[old]:Destroy() end
			portraitCache[old] = nil
		end
	end
	return m:Clone()
end
function HB.portrait(vpf, look, tack)
	vpf:ClearAllChildren()
	local model = HB.portraitModel(look, tack)
	model.Parent = vpf
	local cam = Instance.new("Camera")
	local s = Horses.sizeOf(look)
	local center = Vector3.new(2 * HV.V * s, 9 * HV.V * s, 0)
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(center + Vector3.new(4 * s, 3 * s, 19 * s), center)
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	vpf.LightDirection = Vector3.new(-0.4, -1, -0.6)
	vpf.Ambient = Color3.fromRGB(170, 170, 170)
	vpf.LightColor = Color3.fromRGB(255, 255, 255)
end

return HB
