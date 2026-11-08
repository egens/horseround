--[[
	Управление (аналог onKey/onPointer из js/game.js): клавиши, клик по лошади — лассо,
	поза «в седле», полёт на крылатой лошади, режим стройки с призраком постройки.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Stalls = require(Shared.Stalls)

local Client = script.Parent
local State = require(Client.State)
local Render = require(Client.Render)

local Controls = {}
local player = Players.LocalPlayer
local K = World.K
local Win, MG -- задаёт Main

local function hud() return State.hud or {} end
local function char() return player.Character end
local function hrp()
	local c = char()
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function humanoid()
	local c = char()
	return c and c:FindFirstChildOfClass("Humanoid")
end

--[[ ---------- стройка ---------- ]]
local build = nil -- { type, rot, ghost } или { remove = true }
local ghost
local function setGhost(size)
	if not ghost then
		ghost = Instance.new("Part")
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.Material = Enum.Material.ForceField
		ghost.Transparency = 0.3
		ghost.Name = "BuildGhost"
	end
	ghost.Size = size
	ghost.Parent = workspace
end
function Controls.startBuild(btype)
	build = { type = btype, rot = 0 }
	local d = Items.BUILDS[btype]
	State.emit("toast", "🔨 " .. d.name .. ": наведи и нажми, чтобы поставить. R — повернуть, Esc — отмена")
end
function Controls.startRemove()
	build = { remove = true }
	State.emit("toast", "🧹 Нажми на постройку, чтобы убрать её (вернётся половина цены). Esc — выход")
end
function Controls.cancelBuild()
	build = nil
	if ghost then ghost.Parent = nil end
end
local function mouseHit()
	local cam = workspace.CurrentCamera
	local pos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	local ignore = { ghost }
	if char() then table.insert(ignore, char()) end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(ray.Origin, ray.Direction * 600, params)
end
local function snap(v) return math.floor(v / 10 + 0.5) * 10 end
local function updateGhost()
	if not build or build.remove then
		if ghost then ghost.Parent = nil end
		return
	end
	local hit = mouseHit()
	if not hit then return end
	local x, y = World.fromStuds(hit.Position)
	x, y = snap(x), snap(y)
	local w, h = Stalls.dims(build.type, build.rot)
	setGhost(Vector3.new(w * K, 2, h * K))
	ghost.CFrame = CFrame.new(x * K, World.GROUND + 1, y * K)
	local ok = not World.blocked(x, y, math.min(w, h) / 2)
	ghost.Color = ok and Color3.fromRGB(81, 207, 102) or Color3.fromRGB(224, 49, 49)
	build.x, build.y = x, y
end
local function buildClick()
	if not build then return false end
	if build.remove then
		local hit = mouseHit()
		if hit then
			local x, y = World.fromStuds(hit.Position)
			State.act("unbuild", x, y)
		end
		return true
	end
	updateGhost()
	if build.x then State.act("build", build.type, { x = build.x, y = build.y, rot = build.rot }) end
	return true
end
function Controls.inBuild() return build ~= nil end

--[[ ---------- поза в седле ---------- ]]
local sitTrack, sitChar
local SIT_R15 = "rbxassetid://2506281703"
local SIT_R6 = "rbxassetid://178130996"
local function updateSit()
	local c = char()
	local hum = humanoid()
	local mounted = c and c:FindFirstChild("Mount") ~= nil
	if mounted and hum then
		if not sitTrack or sitChar ~= c then
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
			local a = Instance.new("Animation")
			a.AnimationId = hum.RigType == Enum.HumanoidRigType.R6 and SIT_R6 or SIT_R15
			local ok, track = pcall(function() return animator:LoadAnimation(a) end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = true
				track:Play(0.2)
				sitTrack, sitChar = track, c
			end
		end
	elseif sitTrack then
		sitTrack:Stop(0.2)
		sitTrack = nil
	end
end

--[[ ---------- полёт ---------- ]]
local fly = nil
local flyKeys = { up = false, down = false }
local function startFly()
	local root, hum = hrp(), humanoid()
	if not root or not hum then return end
	local att = Instance.new("Attachment")
	att.Name = "FlyAtt"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e7
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = Vector3.new(0, 18, 0)
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 25
	ao.CFrame = root.CFrame - root.Position
	ao.Parent = root
	hum.PlatformStand = true
	fly = { att = att, lv = lv, ao = ao, t = 0 }
end
local function stopFly()
	if not fly then return end
	fly.lv:Destroy()
	fly.ao:Destroy()
	fly.att:Destroy()
	fly = nil
	local hum = humanoid()
	if hum then hum.PlatformStand = false end
end
local function updateFly(dt)
	local c = char()
	local want = c and c:GetAttribute("Flying") == true
	if want and not fly then startFly() elseif not want and fly then stopFly() end
	if not fly then return end
	local root, hum = hrp(), humanoid()
	if not root or not hum then
		fly = nil
		return
	end
	fly.t += dt
	local move = hum.MoveDirection
	local speed = hum.WalkSpeed
	local vy = 0
	if flyKeys.up then vy = 16 elseif flyKeys.down then vy = -16 end
	if fly.t < 0.8 then vy = 18 end
	local alt = root.Position.Y
	if alt > 320 and vy > 0 then vy = 0 end
	local _, py = World.fromStuds(root.Position)
	local gy = World.groundY(0, py)
	if alt < gy + 4 and vy < 0 then vy = 0 end
	fly.lv.VectorVelocity = Vector3.new(move.X * speed, vy, move.Z * speed)
	if move.Magnitude > 0.05 then
		fly.ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(move.X, 0, move.Z))
	end
end

--[[ ---------- клавиши ---------- ]]
local liftT = 0
local function space()
	if MG.lassoOpen() then MG.throwLasso() return end
	if MG.careOpen() then MG.careButton() return end
	local c = char()
	if c and c:GetAttribute("Flying") then return end
	local x = hud().exercise
	if x and x.lift then
		State.act("lift")
		if x.liftLabel == "⤴ Прыжок!" then
			local hum = humanoid()
			if hum then hum.Jump = true end
		else
			liftT = 0.42
		end
		return
	end
	State.act("lasso")
end
Controls.space = space

local function onInput(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local code = input.KeyCode
	if processed or UserInputService:GetFocusedTextBox() then return end
	if code == Enum.KeyCode.Space then
		flyKeys.up = true
		space()
		return
	end
	if code == Enum.KeyCode.LeftControl or code == Enum.KeyCode.C then flyKeys.down = true end
	if MG.lassoOpen() then
		if code == Enum.KeyCode.Return then MG.throwLasso() end
		return
	end
	if Win.isOpen() then
		if code == Enum.KeyCode.Escape then Win.close() end
		return
	end
	if build then
		if code == Enum.KeyCode.Escape then Controls.cancelBuild() return end
		if code == Enum.KeyCode.R then build.rot = build.rot == 1 and 0 or 1 return end
	end
	if code == Enum.KeyCode.E or code == Enum.KeyCode.Return then State.act("interact")
	elseif code == Enum.KeyCode.One then State.act("setGait", 0)
	elseif code == Enum.KeyCode.Two then State.act("setGait", 1)
	elseif code == Enum.KeyCode.Three then State.act("setGait", 2)
	elseif code == Enum.KeyCode.Q then
		local m = hud().mounted
		if m then State.act("setGait", math.max(0, m.gait - 1)) end
	elseif code == Enum.KeyCode.R then
		local m = hud().mounted
		if m then State.act("setGait", math.min(2, m.gait + 1)) end
	elseif code == Enum.KeyCode.X or code == Enum.KeyCode.F then State.act("dismount")
	elseif code == Enum.KeyCode.Escape then State.act("cancelEx")
	elseif code == Enum.KeyCode.V then State.act("fly")
	elseif code == Enum.KeyCode.M then State.act("detector")
	elseif code == Enum.KeyCode.B then Win.open("build", {})
	elseif code == Enum.KeyCode.J then Win.open("quests", {})
	elseif code == Enum.KeyCode.T then
		local m = hud().mounted
		if m then Win.open("tricks", { id = m.id }) end
	elseif code == Enum.KeyCode.N then
		if hud().mounted then State.act("neigh") end
	end
end
local function onInputEnded(input)
	if input.KeyCode == Enum.KeyCode.Space then flyKeys.up = false end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then flyKeys.down = false end
end

-- клик: стройка или лассо по лошади
local function onClick(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if Win.isOpen() or MG.lassoOpen() or MG.careOpen() then return end
	if buildClick() then return end
	local hit = mouseHit()
	if not hit then return end
	local id, kind = Render.entityOf(hit.Instance)
	if id and kind == "horse" then State.act("lasso", id) end
end

function Controls.update(dt)
	updateSit()
	updateFly(dt)
	updateGhost()
	liftT = math.max(0, liftT - dt)
	Render.riderLift = liftT > 0 and 0.35 or 0
	-- кнопки полёта на телефоне
	local flying = char() and char():GetAttribute("Flying") == true
	if flying ~= Controls.flyButtons then
		Controls.flyButtons = flying
		if flying then
			ContextActionService:BindAction("FlyUp", function(_, state)
				flyKeys.up = state == Enum.UserInputState.Begin
				return Enum.ContextActionResult.Sink
			end, true)
			ContextActionService:SetTitle("FlyUp", "⬆")
			ContextActionService:SetPosition("FlyUp", UDim2.new(1, -130, 1, -200))
			ContextActionService:BindAction("FlyDown", function(_, state)
				flyKeys.down = state == Enum.UserInputState.Begin
				return Enum.ContextActionResult.Sink
			end, true)
			ContextActionService:SetTitle("FlyDown", "⬇")
			ContextActionService:SetPosition("FlyDown", UDim2.new(1, -130, 1, -130))
		else
			ContextActionService:UnbindAction("FlyUp")
			ContextActionService:UnbindAction("FlyDown")
		end
	end
end

function Controls.init(win, mg)
	Win, MG = win, mg
	-- пробел — лассо, а не прыжок
	ContextActionService:BindActionAtPriority("HorseSpace", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			if not UserInputService:GetFocusedTextBox() then
				flyKeys.up = true
				space()
			end
		elseif state == Enum.UserInputState.End then
			flyKeys.up = false
		end
		local x = hud().exercise
		if x and x.liftLabel == "⤴ Прыжок!" then return Enum.ContextActionResult.Pass end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode ~= Enum.KeyCode.Space then onInput(input, processed) end
		onClick(input, processed)
	end)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.RenderStepped:Connect(Controls.update)
end

Controls.Util = Util
return Controls
