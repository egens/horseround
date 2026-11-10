--[[
	Звуки игры.
	 - Короткие эффекты (монетка, фанфары, «бу!») — встроенные звуки движка Roblox с разной высотой тона.
	 - Ржание, дождь, музыка — сначала пробуем звуки из открытой библиотеки Roblox (Creator Store, бесплатные).
	   Если звук не загрузился (его убрали или он закрыт), играем запасной вариант на встроенных звуках.
	   Свои звуки можно загрузить в Roblox и вписать rbxassetid:// первым в нужный список LIB.
	 - Езда: стук копыт в такт аллюру (шаг — 4 удара, рысь — 2, галоп — 3 и пауза), в дождь — шлёпанье по лужам.
	 - Природа: шум дождя, днём птицы, ночью сверчки, иногда ветер и всегда тихая музыка-«колокольчики».
]]
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Client = script.Parent
local State = require(Client.State)

local Sound = {}
Sound.on = true
Sound.region = "farm"            -- задаёт Effects
Sound.nearPuddle = nil           -- function(Vector3) -> bool, задаёт Effects

-- встроенные звуки движка (есть всегда)
local IDS = {
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/button.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	ghost = "rbxasset://sounds/uuhhh.mp3",
	step = "rbxasset://sounds/action_footsteps_plastic.mp3",
	splash = "rbxasset://sounds/impact_water.mp3",
}
Sound.IDS = IDS

-- звуки из библиотеки Roblox: берётся первый, который загрузился.
-- После 2022 года многие чужие звуки в Roblox закрыты, поэтому для надёжности загрузите свои
-- (Creator Hub → Audio) и впишите rbxassetid:// первым в нужный список.
local LIB = {
	neigh = { "rbxassetid://196261753", "rbxassetid://3300268804", "rbxassetid://6067768736" },
	rain = { "rbxassetid://1516791621", "rbxassetid://184352854", "rbxassetid://2304892796" },
	birds = {},   -- пение птиц днём (если пусто — птиц не слышно)
	crickets = {}, -- сверчки ночью
	music = {},   -- спокойная музыка (если пусто — тишина)
}
Sound.LIB = LIB
local libOk = {} -- [name] = id, который загрузился

local function preloadLib()
	for name, list in pairs(LIB) do
		task.spawn(function()
			for _, id in ipairs(list) do
				local s = Instance.new("Sound")
				s.SoundId = id
				local ok = false
				pcall(function()
					ContentProvider:PreloadAsync({ s }, function(_, status)
						ok = status == Enum.AssetFetchStatus.Success
					end)
				end)
				if ok then
					libOk[name] = id
					print("[HorseFarm] звук «" .. name .. "»: " .. id)
					s:Destroy()
					return
				end
				s:Destroy()
			end
		end)
	end
end

local function play(id, speed, volume, delay)
	if not Sound.on or not id or id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 0.5
	s.Parent = SoundService
	local function go()
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
		task.delay(8, function() if s.Parent then s:Destroy() end end)
	end
	if delay and delay > 0 then task.delay(delay, go) else go() end
	return s
end

-- запасное ржание без библиотеки: голосовой звук движка, высоко и с дрожью (вибрато),
-- тон взлетает и спускается «и-го-го», в конце — фырканье. Раньше здесь был электронный «пинг» — он пиликал.
local function synthNeigh(vol)
	vol = vol or 0.6
	local s = play(IDS.ghost, 1.55, vol)
	if s then
		local t0 = os.clock()
		task.spawn(function()
			while s.Parent and os.clock() - t0 < 1.3 do
				local t = os.clock() - t0
				-- контур высоты: подъём, «гого» с переливами, спуск
				local base = t < 0.15 and (1.55 + t * 4) or (2.15 - (t - 0.15) * 0.65)
				s.PlaybackSpeed = math.max(0.9, base * (1 + math.sin(t * 2 * math.pi * 13) * 0.07))
				s.Volume = vol * (0.75 + 0.25 * math.sin(t * 2 * math.pi * 6.5)) * math.clamp((1.3 - t) / 0.4, 0, 1)
				task.wait()
			end
			if s.Parent then s:Stop() s:Destroy() end
		end)
	end
	play(IDS.swoosh, 0.5, vol * 0.7, 1.15) -- фырканье в конце
	play(IDS.swoosh, 0.42, vol * 0.5, 1.32)
end

local handlers = {
	tick = function() play(IDS.ping, 1.6, 0.35) end,
	beep = function(freq) play(IDS.ping, 0.5 + (freq or 800) / 900, 0.18) end,
	coin = function()
		play(IDS.ping, 1.9, 0.35)
		play(IDS.ping, 2.5, 0.35, 0.08)
	end,
	fail = function()
		play(IDS.click, 0.55, 0.5)
		play(IDS.click, 0.42, 0.5, 0.15)
	end,
	thud = function() play(IDS.click, 0.35, 0.7) end,
	whoosh = function() play(IDS.swoosh, 1.2, 0.4) end,
	fanfare = function()
		for i, k in ipairs({ 1, 1.26, 1.5, 2 }) do play(IDS.ping, k * 1.1, 0.4, (i - 1) * 0.11) end
	end,
	boo = function() play(IDS.ghost, 0.55, 0.5) end,
	train = function()
		play(IDS.ping, 0.75, 0.5)
		play(IDS.ping, 0.63, 0.5, 0.5)
	end,
	-- vol — громкость (дальше от лошади — тише)
	neigh = function(_, vol)
		vol = vol or 1
		local id = libOk.neigh
		if id then
			play(id, 0.95 + math.random() * 0.12, 0.7 * vol)
		else
			synthNeigh(0.6 * vol)
		end
	end,
}

function Sound.play(name, ...)
	local h = handlers[name]
	if h then h(...) end
end

--[[ ---------- копыта ---------- ]]
local player = Players.LocalPlayer
-- рисунок ударов за один шаг лошади (в секундах от начала шага) и длина шага
local GAIT_BEATS = {
	[0] = { len = 1.0, beats = { 0, 0.25, 0.5, 0.75 }, vol = 0.32, pitch = 0.85 },  -- шаг: 4 удара
	[1] = { len = 0.62, beats = { 0, 0.31 }, vol = 0.45, pitch = 0.95 },            -- рысь: 2 удара
	[2] = { len = 0.55, beats = { 0, 0.08, 0.16 }, vol = 0.55, pitch = 1.05 },      -- галоп: 3 удара и пауза
}
local hoof = { t = 0, i = 1 }
local function dryRegion(reg)
	return reg == "desert" or reg == "cave" or reg == "grottocave" or reg == "tundra" or string.sub(reg or "", 1, 3) == "sky"
end
local function updateHooves(dt)
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local m = State.hud and State.hud.mounted
	if not hrp or not m or not ch:FindFirstChild("Mount") or ch:GetAttribute("Flying") or ch:GetAttribute("Swimming") then
		hoof.t, hoof.i = 0, 1
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local spd = Vector3.new(v.X, 0, v.Z).Magnitude
	local hum = ch:FindFirstChildOfClass("Humanoid")
	-- в прыжке копыта не стучат
	if spd < 1.5 or (hum and hum.FloorMaterial == Enum.Material.Air) then
		hoof.t, hoof.i = 0, 1
		return
	end
	local G = GAIT_BEATS[m.gait or 0] or GAIT_BEATS[0]
	hoof.t += dt
	local beat = G.beats[hoof.i]
	if beat and hoof.t >= beat then
		local wet = (State.world.puddle or 0) > 0.05 and not dryRegion(Sound.region)
		local inPuddle = Sound.nearPuddle and Sound.nearPuddle(hrp.Position)
		local soft = Sound.region == "desert" or Sound.region == "tundra" or Sound.region == "mushroom"
		play(IDS.step, G.pitch * (soft and 0.7 or 1) * (0.94 + math.random() * 0.12), G.vol * (soft and 0.7 or 1))
		if inPuddle then
			play(IDS.splash, 1.3 + math.random() * 0.3, 0.35 + G.vol * 0.3)
		elseif wet then
			play(IDS.splash, 1.8 + math.random() * 0.4, 0.08) -- мокрая земля чавкает
		end
		hoof.i += 1
	end
	if hoof.t >= G.len then
		hoof.t -= G.len
		hoof.i = 1
	end
end

--[[ ---------- плавание: всплески в озере ---------- ]]
local swimT = 0
local function updateSwim(dt)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if hum:GetState() == Enum.HumanoidStateType.Swimming or ch:GetAttribute("Swimming") then
		swimT -= dt
		if swimT <= 0 then
			swimT = 0.7 + math.random() * 0.4
			local moving = hum.MoveDirection.Magnitude > 0.1
			play(IDS.splash, 0.9 + math.random() * 0.3, moving and 0.3 or 0.12)
		end
	else
		swimT = 0
	end
end

--[[ ---------- дождь ---------- ]]
local rain
local function updateRain(dt)
	local wet = State.world.wet or 0
	local want = Sound.on and wet > 0.02 and not dryRegion(Sound.region) and Sound.region ~= "tundra"
	if not rain then
		local id = libOk.rain
		if not id then
			-- без звука дождя из библиотеки — тишина (раньше «капли» пиликали)
			return
		end
		rain = Instance.new("Sound")
		rain.SoundId = id
		rain.Looped = true
		rain.Volume = 0
		rain.Parent = SoundService
		rain:Play()
	end
	local target = want and math.clamp(wet, 0, 1) * 0.45 or 0
	rain.Volume += (target - rain.Volume) * math.min(1, dt * 1.5)
end

--[[ ---------- природа: птицы, сверчки, ветер ----------
	Птицы и сверчки — только настоящими звуками из LIB (birds, crickets). Синтез из «пинга»
	убран: он звучал как пиликание. Ветер — мягкий шум. ]]
local natureT = 3
local function updateNature(dt)
	natureT -= dt
	if natureT > 0 or not Sound.on then return end
	local reg = Sound.region or "farm"
	local underground = reg == "cave" or reg == "grottocave"
	local clock = Lighting.ClockTime
	local night = clock < 5.5 or clock > 20.5
	local raining = (State.world.wet or 0) > 0.2
	natureT = 5 + math.random() * 6
	if underground then return end
	if night and libOk.crickets then
		play(libOk.crickets, 1, 0.15)
	elseif not night and not raining and reg ~= "desert" and libOk.birds then
		play(libOk.birds, 0.95 + math.random() * 0.1, 0.18)
	end
	if math.random() < 0.15 then play(IDS.swoosh, 0.25 + math.random() * 0.1, 0.05) end -- ветер
end

--[[ ---------- тихая музыка ----------
	Играет, только если в LIB.music есть загрузившийся трек. ]]
local music
local function updateMusic()
	if not libOk.music then return end
	if not music then
		music = Instance.new("Sound")
		music.SoundId = libOk.music
		music.Looped = true
		music.Volume = 0.12
		music.Parent = SoundService
		music:Play()
	end
	music.Volume = Sound.on and 0.12 or 0
end

function Sound.toggle()
	Sound.on = not Sound.on
	if rain then rain.Volume = 0 end
	if music then music.Volume = Sound.on and 0.12 or 0 end
	return Sound.on
end

function Sound.init()
	preloadLib()
	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 0.1)
		if Sound.on then
			updateHooves(dt)
			updateSwim(dt)
		end
		updateRain(dt)
		updateNature(dt)
		updateMusic()
	end)
end

return Sound
