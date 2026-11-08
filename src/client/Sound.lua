--[[
	Звуки (аналог Sound из js/game.js, где звуки синтезировались осциллятором).
	В Roblox синтеза нет, поэтому играем встроенные звуки движка с разной высотой тона.
	Свои звуки можно загрузить в Roblox и подставить rbxassetid:// в таблицу IDS.
]]
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sound = {}
Sound.on = true

local IDS = {
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/button.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	ghost = "rbxasset://sounds/uuhhh.mp3",
	neigh = "", -- сюда можно вписать rbxassetid:// настоящего ржания
}
Sound.IDS = IDS

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
		task.delay(6, function() if s.Parent then s:Destroy() end end)
	end
	if delay and delay > 0 then task.delay(delay, go) else go() end
	return s
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
	neigh = function()
		if IDS.neigh ~= "" then
			play(IDS.neigh, 1, 0.6)
			return
		end
		-- «иго-го»: высокий звук, который спускается вниз
		local s = play(IDS.ping, 1.3, 0.3)
		if s then
			TweenService:Create(s, TweenInfo.new(0.22), { PlaybackSpeed = 2.1 }):Play()
			task.delay(0.22, function()
				if s.Parent then TweenService:Create(s, TweenInfo.new(0.9), { PlaybackSpeed = 0.8 }):Play() end
			end)
		end
	end,
}

function Sound.play(name, ...)
	local h = handlers[name]
	if h then h(...) end
end
function Sound.toggle()
	Sound.on = not Sound.on
	return Sound.on
end

return Sound
