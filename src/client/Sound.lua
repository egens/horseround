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

-- звуки из библиотеки Roblox: берётся первый, который загрузился
local LIB = {
	neigh = { "rbxassetid://196261753", "rbxassetid://3300268804", "rbxassetid://6067768736" },
	rain = { "rbxassetid://1516791621", "rbxassetid://184352854", "rbxassetid://2304892796" },
	music = {}, -- сюда можно вписать rbxassetid:// спокойной музыки; пока пусто — играют «колокольчики»
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

-- запасное ржание без библиотеки: дрожащий звук, который взлетает вверх и спускается с «фырканьем»
local function synthNeigh(vol)
	vol = vol or 0.3
	local s = play(IDS.ping, 1.1, vol)
	if s then
		TweenService:Create(s, TweenInfo.new(0.18), { PlaybackSpeed = 2.2 }):Play()
		task.spawn(function()
			local t0 = os.clock()
			while s.Parent and os.clock() - t0 < 1.1 do
				-- дрожь голоса
				s.PlaybackSpeed = s.PlaybackSpeed * (1 + math.sin((os.clock() - t0) * 70) * 0.04)
				task.wait()
			end
		end)
		task.delay(0.2, function()
			if s.Parent then TweenService:Create(s, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = 0.7, Volume = 0 }):Play() end
		end)
	end
	play(IDS.swoosh, 0.55, vol * 0.8, 1.05) -- фырканье в конце
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
			synthNeigh(0.3 * vol)
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
	if not hrp or not m or not ch:FindFirstChild("Mount") or ch:GetAttribute("Flying") then
		hoof.t, hoof.i = 0, 1
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local spd = Vector3.new(v.X, 0, v.Z).Magnitude
	if spd < 1.5 then
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

--[[ ---------- дождь ---------- ]]
local rain
local function updateRain(dt)
	local wet = State.world.wet or 0
	local want = Sound.on and wet > 0.02 and not dryRegion(Sound.region) and Sound.region ~= "tundra"
	if not rain then
		local id = libOk.rain
		if not id then
			-- запасной дождь: частые тихие капли
			if want and math.random() < dt * 40 * wet then play(IDS.ping, 2.6 + math.random() * 1.2, 0.015 + math.random() * 0.02) end
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

--[[ ---------- природа: птицы, сверчки, ветер ---------- ]]
local natureT = 3
local function chirp()
	local base = 2.4 + math.random() * 1.2
	local n = math.random(2, 5)
	for i = 0, n - 1 do
		local s = play(IDS.ping, base, 0.035 + math.random() * 0.025, i * (0.09 + math.random() * 0.05))
		if s then
			task.delay(i * 0.1, function()
				if s.Parent then TweenService:Create(s, TweenInfo.new(0.07), { PlaybackSpeed = base * (1.15 + math.random() * 0.2) }):Play() end
			end)
		end
	end
end
local function cricket()
	for i = 0, 5 do play(IDS.ping, 3.6, 0.012, i * 0.045) end
end
local function updateNature(dt)
	natureT -= dt
	if natureT > 0 or not Sound.on then return end
	local reg = Sound.region or "farm"
	local underground = reg == "cave" or reg == "grottocave"
	local clock = Lighting.ClockTime
	local night = clock < 5.5 or clock > 20.5
	local raining = (State.world.wet or 0) > 0.2
	if underground then
		natureT = 6 + math.random() * 6
		play(IDS.ping, 0.9 + math.random() * 0.3, 0.02) -- капли в пещере
		return
	end
	if night then
		natureT = 1.5 + math.random() * 2.5
		cricket()
	elseif not raining and reg ~= "desert" then
		natureT = 2.5 + math.random() * 5
		chirp()
	else
		natureT = 4 + math.random() * 4
	end
	if math.random() < 0.12 then play(IDS.swoosh, 0.25 + math.random() * 0.1, 0.06) end -- ветер
end

--[[ ---------- тихая музыка природы ----------
	Если в LIB.music есть загрузившийся трек — играет он (тихо, по кругу).
	Иначе — «колокольчики»: медленные ноты пентатоники с паузами, каждая фраза своя. ]]
local music
local PENTA = { 1, 1.122, 1.26, 1.498, 1.682, 2, 2.245, 2.52 }
local musicT = 4
local function updateMusic(dt)
	if libOk.music then
		if not music then
			music = Instance.new("Sound")
			music.SoundId = libOk.music
			music.Looped = true
			music.Volume = 0.12
			music.Parent = SoundService
			music:Play()
		end
		music.Volume = Sound.on and 0.12 or 0
		return
	end
	if not Sound.on then return end
	musicT -= dt
	if musicT > 0 then return end
	local root = 0.62
	local n = math.random(3, 6)
	local idx = math.random(1, 5)
	local t = 0
	for _ = 1, n do
		idx = math.clamp(idx + math.random(-2, 2), 1, #PENTA)
		local s = play(IDS.ping, root * PENTA[idx], 0.045, t)
		-- нота тянется и затихает
		if s then task.delay(t, function() if s.Parent then TweenService:Create(s, TweenInfo.new(1.6), { Volume = 0 }):Play() end end) end
		play(IDS.ping, root * PENTA[idx] * 0.5, 0.02, t) -- мягкий бас октавой ниже
		t += 0.55 + math.random() * 0.5
	end
	musicT = t + 3 + math.random() * 5
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
		if Sound.on then updateHooves(dt) end
		updateRain(dt)
		updateNature(dt)
		updateMusic(dt)
	end)
end

return Sound
