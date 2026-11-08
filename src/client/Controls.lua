--[[
	Управление (аналог onKey/onPointer из js/game.js): клавиши, клик по лошади — лассо,
	поза «в седле», полёт на крылатой лошади, бег (Shift) и прыжок пешком.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)

local Client = script.Parent
local State = require(Client.State)
local Render = require(Client.Render)

local Controls = {}
local player = Players.LocalPlayer
local K = World.K
local Win, MG, Hud -- задаёт Main
local fly = nil -- полёт на крылатой лошади (ниже)

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

local function mouseHit()
	local cam = workspace.CurrentCamera
	local pos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	local ignore = {}
	if char() then table.insert(ignore, char()) end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(ray.Origin, ray.Direction * 600, params)
end

--[[ ---------- бег и прыжок пешком ----------
	Скорость пешком задаёт клиент (как в обычных играх Roblox): шаг 16, с Shift — бег 26.
	Верхом скорость считает сервер по аллюру и присылает в атрибутах RideSpeed/RideJump. ]]
local WALK, RUN = 16, 26
local JUMP_H = 7.2 -- стандартная высота прыжка Roblox
local sprint = false
local function mounted()
	local c = char()
	return c ~= nil and c:FindFirstChild("Mount") ~= nil
end
local function updateFoot()
	local c, hum, root = char(), humanoid(), hrp()
	if not c or not hum then return end
	-- на всякий случай: персонаж не должен оставаться закреплённым или «без ног» после телепорта или полёта
	if root and root.Anchored then root.Anchored = false end
	if not fly and hum.PlatformStand then hum.PlatformStand = false end
	local speed, jump
	if mounted() or c:GetAttribute("Flying") then
		speed, jump = c:GetAttribute("RideSpeed") or 0, c:GetAttribute("RideJump") or 0
	else
		speed, jump = sprint and RUN or WALK, JUMP_H
	end
	if hum.WalkSpeed ~= speed then hum.WalkSpeed = speed end
	if hum.UseJumpPower then hum.UseJumpPower = false end
	if hum.JumpHeight ~= jump then hum.JumpHeight = jump end
end

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
fly = nil
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
-- Пробел: мини-игры, полёт и упражнения верхом; иначе — обычный прыжок Roblox.
-- Возвращает true, если пробел «съели» и прыгать не надо.
local function space()
	if MG.lassoOpen() then MG.throwLasso() return true end
	if MG.careOpen() then MG.careButton() return true end
	local c = char()
	if c and c:GetAttribute("Flying") then return true end
	local x = hud().exercise
	if x and x.lift then
		State.act("lift")
		if x.liftLabel == "⤴ Прыжок!" then return false end
		liftT = 0.42
		return true
	end
	return false
end
Controls.space = space
local function lasso()
	if MG.lassoOpen() then MG.throwLasso() return end
	State.act("lasso")
end
Controls.lasso = lasso

local function onInput(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local code = input.KeyCode
	if processed or UserInputService:GetFocusedTextBox() then return end
	if code == Enum.KeyCode.LeftShift or code == Enum.KeyCode.RightShift then sprint = true end
	if code == Enum.KeyCode.LeftControl or code == Enum.KeyCode.C then flyKeys.down = true end
	if MG.lassoOpen() then
		if code == Enum.KeyCode.Return then MG.throwLasso() end
		return
	end
	if Hud.mapOpen() then
		if code == Enum.KeyCode.Escape or code == Enum.KeyCode.M then Hud.toggleMap(false) end
		return
	end
	if Win.isOpen() then
		if code == Enum.KeyCode.Escape then Win.close() end
		return
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
	elseif code == Enum.KeyCode.X then State.act("dismount")
	elseif code == Enum.KeyCode.F then lasso()
	elseif code == Enum.KeyCode.Escape then State.act("cancelEx")
	elseif code == Enum.KeyCode.V then State.act("fly")
	elseif code == Enum.KeyCode.M then Hud.toggleMap()
	elseif code == Enum.KeyCode.G then State.act("detector")
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
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then sprint = false end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then flyKeys.down = false end
end

-- клик по лошади — лассо
local function onClick(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if Win.isOpen() or MG.lassoOpen() or MG.careOpen() or Hud.mapOpen() then return end
	local hit = mouseHit()
	if not hit then return end
	local id, kind = Render.entityOf(hit.Instance)
	if id and kind == "horse" then State.act("lasso", id) end
end

function Controls.update(dt)
	updateSit()
	updateFly(dt)
	updateFoot()
	liftT = math.max(0, liftT - dt)
	Render.riderLift = liftT > 0 and 0.35 or 0
	-- кнопка бега на телефоне (пешком)
	local foot = char() ~= nil and not mounted()
	if foot ~= Controls.runButton and UserInputService.TouchEnabled then
		Controls.runButton = foot
		if foot then
			ContextActionService:BindAction("Run", function(_, state)
				if state == Enum.UserInputState.Begin then sprint = not sprint end
				ContextActionService:SetTitle("Run", sprint and "🚶" or "🏃")
				return Enum.ContextActionResult.Sink
			end, true)
			ContextActionService:SetTitle("Run", sprint and "🚶" or "🏃")
			ContextActionService:SetPosition("Run", UDim2.new(1, -200, 1, -130))
		else
			ContextActionService:UnbindAction("Run")
			sprint = false
		end
	end
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

function Controls.init(win, mg, hudModule)
	Win, MG, Hud = win, mg, hudModule
	-- пробел: мини-игры, полёт и «ноги выше» перехватываем, в остальных случаях — обычный прыжок
	ContextActionService:BindActionAtPriority("HorseSpace", function(_, state)
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then
			flyKeys.up = true
			if space() then return Enum.ContextActionResult.Sink end
		elseif state == Enum.UserInputState.End then
			flyKeys.up = false
		end
		return Enum.ContextActionResult.Pass
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
