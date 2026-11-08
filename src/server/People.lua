--[[
	Жители (NPC) — стандартные человечки Roblox (R15).
	Цвет одежды задаётся цветами частей тела, шляпы и крылья — простыми деталями.
	Ещё здесь создаётся шаблон всадника для ИИ-игроков и соперников на скачках:
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
	if opts.transparency then p.Transparency = opts.transparency end
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = rig
	return p
end

-- волосы и шляпа
local function dress(rig, look)
	local hair = look.hair or "#7a4a22"
	local hat = look.hat or "none"
	local hc = look.hatColor or "#555555"
	if hat ~= "scarf" then attach(rig, "Head", Vector3.new(1.25, 0.35, 1.25), CFrame.new(0, 0.55, 0.05), hair) end
	if hat == "none" or hat == "crown" then attach(rig, "Head", Vector3.new(1.2, 0.9, 0.3), CFrame.new(0, 0.15, 0.6), hair) end
	if look.beard then attach(rig, "Head", Vector3.new(0.9, 0.4, 0.2), CFrame.new(0, -0.45, -0.6), hair) end
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
			placeOnGround(rig, n.x, n.y, math.pi / 2)
			rig.Parent = folder
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
