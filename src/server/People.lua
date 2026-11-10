--[[
	Жители (NPC) — стандартные человечки Roblox (R15).
	Цвет одежды задаётся цветами частей тела, шляпы и крылья — простыми деталями.
	Ещё здесь создаётся шаблон всадника для соперников на скачках:
	клиенты клонируют его и сажают на лошадь.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Q = require(Shared.QuestData)

local People = {}
local color = Util.color
local IDLE_R15 = "rbxassetid://507766388"

local function description(look)
	local d = Instance.new("HumanoidDescription")
	local skin = color(look.skin or "#f2c9a5")
	local shirt = color(look.shirt or "#4dabf7")
	local pants = color(look.pants or "#33415c")
	d.HeadColor = skin
	d.TorsoColor = shirt
	d.LeftArmColor = shirt
	d.RightArmColor = shirt
	d.LeftLegColor = pants
	d.RightLegColor = pants
	return d
end

local function newRig(look)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(look or {}), Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn("[People] не получилось создать человечка: " .. tostring(rig))
		return nil
	end
	-- без одежды по умолчанию: цвета частей тела и есть одежда
	for _, c in ipairs(rig:GetChildren()) do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c:Destroy() end
	end
	return rig
end

-- кисти рук — цвета кожи, обувь — тёмная, у кого короткий рукав — предплечья тоже цвета кожи
local function refine(rig, look)
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then bc:Destroy() end -- иначе цвета частей вернутся к цветам описания
	local skin = color(look.skin or "#f2c9a5")
	local shoes = color(look.shoes or "#3b2a20")
	for _, n in ipairs({ "LeftHand", "RightHand" }) do
		local p = rig:FindFirstChild(n)
		if p then p.Color = skin end
	end
	if look.short then
		for _, n in ipairs({ "LeftLowerArm", "RightLowerArm" }) do
			local p = rig:FindFirstChild(n)
			if p then p.Color = skin end
		end
	end
	for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
		local p = rig:FindFirstChild(n)
		if p then p.Color = shoes end
	end
end

-- простая деталь, приваренная к голове или спине
local function attach(rig, partName, size, offset, c, opts)
	opts = opts or {}
	local base = rig:FindFirstChild(partName)
	if not base then return nil end
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color(c)
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	if opts.shape then p.Shape = opts.shape end
	if opts.round then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	if opts.transparency then p.Transparency = opts.transparency end
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = rig
	return p
end

-- волосы и шляпа: причёска из округлых деталей (шапочка волос, затылок, чёлка, у длинных волос — хвост),
-- воротник и ремень — человечки как в Roblox, но аккуратнее
local function dress(rig, look)
	local hair = look.hair or "#7a4a22"
	local hat = look.hat or "none"
	local hc = look.hatColor or "#555555"
	if hat ~= "scarf" then
		attach(rig, "Head", Vector3.new(1.32, 0.62, 1.3), CFrame.new(0, 0.42, 0.06), hair, { round = true })
		attach(rig, "Head", Vector3.new(1.26, 0.95, 0.42), CFrame.new(0, 0.05, 0.5), hair, { round = true })
		if hat == "none" or hat == "crown" then
			-- чёлка
			attach(rig, "Head", Vector3.new(1.05, 0.28, 0.3), CFrame.new(0, 0.45, -0.52) * CFrame.Angles(-0.3, 0, 0), hair, { round = true })
		end
	end
	if look.long and hat ~= "scarf" then
		attach(rig, "Head", Vector3.new(1.2, 1.5, 0.35), CFrame.new(0, -0.35, 0.55), hair, { round = true })
		attach(rig, "Head", Vector3.new(0.3, 1.1, 0.5), CFrame.new(-0.62, -0.2, 0.1), hair, { round = true })
		attach(rig, "Head", Vector3.new(0.3, 1.1, 0.5), CFrame.new(0.62, -0.2, 0.1), hair, { round = true })
	elseif look.ponytail and hat ~= "scarf" then
		attach(rig, "Head", Vector3.new(0.4, 1.3, 0.4), CFrame.new(0, -0.15, 0.78) * CFrame.Angles(0.35, 0, 0), hair, { round = true })
		attach(rig, "Head", Vector3.new(0.45, 0.22, 0.45), CFrame.new(0, 0.42, 0.72), look.bow or "#ff6fae")
	end
	if look.beard then attach(rig, "Head", Vector3.new(0.95, 0.5, 0.35), CFrame.new(0, -0.42, -0.5), hair, { round = true }) end
	-- воротник и ремень
	attach(rig, "UpperTorso", Vector3.new(1.3, 0.22, 0.9), CFrame.new(0, 0.85, 0), look.collar or "#f8f9fa")
	attach(rig, "LowerTorso", Vector3.new(2.05, 0.22, 1.05), CFrame.new(0, 0.2, 0), look.belt or "#3b2a20")
	attach(rig, "LowerTorso", Vector3.new(0.32, 0.26, 0.08), CFrame.new(0, 0.2, -0.53), "#ffd43b", { material = Enum.Material.Metal })
	if hat == "cap" then
		attach(rig, "Head", Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 0.7, 0), hc)
		attach(rig, "Head", Vector3.new(1, 0.12, 0.6), CFrame.new(0, 0.55, -0.85), hc)
	elseif hat == "hat" then
		attach(rig, "Head", Vector3.new(2, 0.12, 2), CFrame.new(0, 0.62, 0), hc)
		attach(rig, "Head", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 0.9, 0), hc)
	elseif hat == "tophat" then
		attach(rig, "Head", Vector3.new(1.8, 0.12, 1.8), CFrame.new(0, 0.62, 0), hc)
		attach(rig, "Head", Vector3.new(1.1, 1.3, 1.1), CFrame.new(0, 1.3, 0), hc)
	elseif hat == "scarf" then
		attach(rig, "Head", Vector3.new(1.3, 0.5, 1.3), CFrame.new(0, 0.5, 0), hc)
		attach(rig, "Head", Vector3.new(1.3, 1, 0.2), CFrame.new(0, 0, 0.62), hc)
	elseif hat == "crown" then
		attach(rig, "Head", Vector3.new(1.1, 0.4, 1.1), CFrame.new(0, 0.8, 0), hc, { material = Enum.Material.Neon })
	end
	if look.apron then attach(rig, "UpperTorso", Vector3.new(1.6, 1.8, 0.15), CFrame.new(0, -0.3, -0.55), look.apron) end
end

local function placeOnGround(rig, x, y, faceAngle)
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local hip = hum and hum.HipHeight or 2
	local pos = World.toStuds(x, y, World.groundY(x, y) + hip + (hrp and hrp.Size.Y / 2 or 1))
	rig:PivotTo(CFrame.new(pos) * CFrame.Angles(0, faceAngle or 0, 0))
	if hrp then hrp.Anchored = true end
end

local function playIdle(rig)
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local a = Instance.new("Animation")
	a.AnimationId = IDLE_R15
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if ok and track then
		track.Looped = true
		track:Play()
	end
end

function People.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "People"
	folder.Parent = parent
	for _, n in ipairs(Q.NPCS) do
		local rig = newRig(n.look)
		if rig then
			rig.Name = n.id
			rig:SetAttribute("NpcId", n.id)
			local hum = rig:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayName = n.name
				hum.NameDisplayDistance = 120
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
			refine(rig, n.look)
			dress(rig, n.look)
			if n.fairy then
				for _, s in ipairs({ -1, 1 }) do
					attach(rig, "UpperTorso", Vector3.new(0.15, 2.2, 1.6), CFrame.new(s * 0.7, 0.3, 0.9) * CFrame.Angles(0, s * 0.5, s * 0.3), "#e5dbff", { material = Enum.Material.Neon, transparency = 0.3 })
				end
			end
			if n.ghost then
				for _, d in ipairs(rig:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
						d.Material = Enum.Material.ForceField
						d.Color = color("#dbe4ff")
					end
				end
			end
			placeOnGround(rig, n.x, n.y, n.face or math.pi / 2)
			rig.Parent = folder
			playIdle(rig)
		end
	end
	-- люди на рынке: продавцы за прилавками и покупатели перед ними
	local rnd = Util.rng(2024)
	local SHIRTS = { "#e8590c", "#2b8a3e", "#1c7ed6", "#c2255c", "#f59f00", "#6741d9", "#0b7285", "#e03131", "#f8f9fa", "#495057" }
	local PANTS = { "#343a40", "#1864ab", "#5c3d2e", "#495057", "#2b2b2b", "#e9e0cc" }
	local HAIRS = { "#2b1a10", "#5a3d2b", "#d4a017", "#a0522d", "#1b1b1b", "#e8c07a", "#c0c0c0" }
	local SKINS = { "#f2c9a5", "#e0ac83", "#c68b5e", "#8d5a3b", "#f7d7bd" }
	local HATS = { "none", "none", "cap", "hat", "none", "scarf" }
	local function crowdLook()
		local hat = HATS[math.floor(rnd() * #HATS) + 1]
		return {
			shirt = SHIRTS[math.floor(rnd() * #SHIRTS) + 1], pants = PANTS[math.floor(rnd() * #PANTS) + 1], hair = HAIRS[math.floor(rnd() * #HAIRS) + 1],
			skin = SKINS[math.floor(rnd() * #SKINS) + 1], hat = hat, hatColor = SHIRTS[math.floor(rnd() * #SHIRTS) + 1], short = rnd() < 0.5,
			long = rnd() < 0.3, ponytail = rnd() < 0.3, beard = rnd() < 0.15, apron = nil,
		}
	end
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = parent
	local spots = {}
	for i, st in ipairs(World.MARKET_STALLS) do
		-- продавец за прилавком (смотрит на покупателей)
		table.insert(spots, { x = st.x + st.w * (0.3 + (i % 2) * 0.4), y = st.y - 14, a = math.pi, apron = true })
		-- покупатели перед стойкой
		local fr = World.stallFront(st)
		if i % 2 == 1 then table.insert(spots, { x = fr.x - 35, y = fr.y - 18, a = 0.3 }) end
		table.insert(spots, { x = fr.x + 40, y = fr.y + 10, a = -0.4 })
	end
	-- гуляющие по площади
	local Mk = World.MARKET
	for k = 1, 4 do table.insert(spots, { x = Mk.x + 60 + k * 120, y = Mk.y + Mk.h - 40 - (k % 2) * 30, a = rnd() * 6.28 }) end
	for _, q in ipairs(spots) do
		local look = crowdLook()
		if q.apron then look.apron = "#f1e3c6" end
		local rig = newRig(look)
		if rig then
			rig.Name = "Shopper"
			local hum = rig:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
			refine(rig, look)
			dress(rig, look)
			placeOnGround(rig, q.x, q.y, q.a)
			rig.Parent = crowd
			playIdle(rig)
		end
	end
	-- шаблон всадника для клиентов
	local tpl = newRig({ shirt = "#4dabf7", pants = "#33415c" })
	if tpl then
		tpl.Name = "RiderTemplate"
		local hum = tpl:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
		tpl.Parent = ReplicatedStorage
	end
	return folder
end

return People
