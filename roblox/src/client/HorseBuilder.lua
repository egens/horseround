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
	if opts.anchored then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
	end
	return {
		model = model, root = root, content = content, contentM = contentM, head = head, headM = headM, HP = HP,
		earsM = earsM, EP = EP, legs = legs, tailM = tailM, TP = TP, wings = wings, ph = ph, s = s, seed = h.seed,
		cloud = mag.cloud, V = V,
	}
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
	local bob = (move > 0.25 and fly <= 0 and not A) and math.sin((o.phase or 0) * 2) * 0.08 * move or 0
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

--[[ всадник-бот (ИИ-игроки и соперники на скачках): сидит на лошади ]]
function HB.addRider(e, R)
	local cells = {}
	local function fill(x0, x1, y0, y1, z0, z1, c)
		for x = x0, x1 do for y = y0, y1 do for z = z0, z1 do cells[HV.key3(x, y, z)] = c end end end
	end
	fill(-2, -1, 10, 13, -4, -4, "#33415c")
	fill(-2, -1, 10, 13, 3, 3, "#33415c")
	fill(-2, -1, 8, 9, -4, -4, "#1f1d22")
	fill(-2, -1, 8, 9, 3, 3, "#1f1d22")
	fill(-3, -1, 15, 19, -2, 1, R.shirt or "#4dabf7")
	fill(0, 2, 17, 18, -3, -3, R.shirt or "#4dabf7")
	fill(0, 2, 17, 18, 2, 2, R.shirt or "#4dabf7")
	cells[HV.key3(3, 17, -3)] = "#f2c9a5"
	cells[HV.key3(3, 17, 2)] = "#f2c9a5"
	fill(-3, 0, 20, 22, -2, 1, "#f2c9a5")
	fill(-3, 0, 23, 23, -2, 1, R.helmet or "#222a3a")
	fill(-3, -3, 21, 22, -2, 1, R.helmet or "#222a3a")
	fill(1, 1, 22, 22, -1, 0, R.helmet or "#222a3a")
	cells[HV.key3(0, 21, -1)] = "#2b2b2b"
	cells[HV.key3(0, 21, 0)] = "#2b2b2b"
	fill(-5, -4, 19, 21, -1, 0, "#7a4a22")
	addCells(cells, e.model, e.content, e.V, CFrame.new(), PLASTIC)
end

--[[ жители (NPC): одна модель с разной одеждой ]]
function HB.buildPerson(look, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = "Person"
	local V = HV.V
	local root = pivotPart("Root", CFrame.new(), model)
	root.Anchored = true
	model.PrimaryPart = root
	local cells = HV.personCells(look)
	addCells(cells, model, root, V, CFrame.new(0, 0, 0), opts.ghost and Enum.Material.ForceField or PLASTIC, opts.ghost and 0.3 or nil)
	if opts.fairy then
		local wc = {}
		for y = 0, 4 do
			for z = 0, 3 - math.floor(y / 2) do wc[HV.key3(0, y, z)] = y % 2 == 1 and "#e5dbff" or "#c5f6fa" end
		end
		for _, sgn in ipairs({ -1, 1 }) do
			local base = CFrame.new(-1.6 * V, 9 * V, sgn * 1.2 * V) * CFrame.Angles(0, sgn > 0 and 0.3 or math.pi - 0.3, 0)
			addCells(wc, model, root, V, base, NEON, 0.2)
		end
	end
	return model
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
