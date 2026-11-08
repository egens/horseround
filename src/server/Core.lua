--[[
	Общий контекст сервера (аналог объекта api/G в JS-версии): сессии игроков, общее время,
	отправка сообщений клиентам, счётчики достижений. Все серверные модули получают его в init.
]]
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Horses = require(Shared.Horses)
local Net = require(Shared.Net)

local G = {}
G.sessions = {}      -- [Player] = sess
G.time = 0           -- секунды игры с запуска сервера
G.clock = 8 * 60     -- минуты от полуночи (общие для всех)
G.modules = {}

local R = {}
function G.initRemotes()
	Net.init()
	for _, n in ipairs(Net.TO_CLIENT) do R[n] = Net.get(n) end
	for _, n in ipairs(Net.TO_SERVER) do R[n] = Net.get(n) end
	for _, n in ipairs(Net.FUNCTIONS) do R[n] = Net.get(n) end
	G.R = R
end

function G.each()
	local list = {}
	for _, s in pairs(G.sessions) do
		if s.ready then table.insert(list, s) end
	end
	return list
end

function G.toast(sess, msg, kind)
	if sess and sess.player.Parent then R.Toast:FireClient(sess.player, msg, kind or "") end
end
function G.toastAll(msg, kind, filter)
	for _, s in ipairs(G.each()) do
		if not filter or filter(s) then G.toast(s, msg, kind) end
	end
end
function G.sfx(sess, name)
	if sess then
		if sess.player.Parent then R.Sfx:FireClient(sess.player, name) end
	else
		R.Sfx:FireAllClients(name)
	end
end
-- летящая надпись видна всем, кто рядом
function G.float(text, x, y, color)
	R.Float:FireAllClients(text, x, y, color or "#333333")
end
function G.open(sess, name, data)
	if sess and sess.player.Parent then R.Open:FireClient(sess.player, name, data) end
end
function G.stat(sess, k, n)
	local st = sess.P.stats
	st[k] = (st[k] or 0) + (n or 1)
	sess.dirty = true
end
function G.dirty(sess) sess.dirty = true end

-- день и ночь: 1 секунда = 3 игровые минуты, сутки — 8 минут
function G.daylight()
	local h = G.clock / 60
	if h >= 7 and h < 19 then return 1 end
	if h >= 5 and h < 7 then return (h - 5) / 2 end
	if h >= 19 and h < 21 then return 1 - (h - 19) / 2 end
	return 0
end
function G.isNight() return G.daylight() < 0.35 end
function G.clockText()
	local h, mi = math.floor(G.clock / 60), math.floor(G.clock % 60)
	local d = G.daylight()
	local icon = d >= 1 and "☀️" or d > 0 and (G.clock < 720 and "🌅" or "🌇") or "🌙"
	return string.format("%s %02d:%02d", icon, h, mi)
end
function G.updateClock(dt)
	G.clock = (G.clock + dt * 3) % 1440
	Lighting.ClockTime = G.clock / 60
end

-- лошадь, на которой сидит игрок
function G.mounted(sess)
	local id = sess.p.mountId
	if id == nil then return nil end
	for _, h in ipairs(sess.P.horses) do
		if h.id == id then return h end
	end
	return nil
end
function G.byId(sess, id)
	for _, h in ipairs(sess.P.horses) do
		if h.id == id then return h end
	end
	return nil
end
-- персонаж игрока
function G.root(sess)
	local ch = sess.player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end
function G.humanoid(sess)
	local ch = sess.player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end
-- перенести игрока (и лошадь на верёвке) в точку карты
function G.teleport(sess, x, y, alt)
	local root = G.root(sess)
	local p = sess.p
	p.x, p.y = x, y
	if root then
		local gy = World.groundY(x, y)
		local hum = G.humanoid(sess)
		local hip = hum and hum.HipHeight or 2
		local pos = World.toStuds(x, y, gy + hip + root.Size.Y / 2 + 0.5 + (alt or 0))
		sess.player.Character:PivotTo(CFrame.new(pos) * (root.CFrame - root.Position))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if sess.led then
		sess.led.x, sess.led.y = x - 60, y + 30
		sess.led.vx, sess.led.vy = 0, 0
	end
	sess.teleportT = 1
end

-- ближайший игрок к точке
function G.nearestPlayer(x, y, maxD)
	local best, bd = nil, maxD or 1e9
	for _, s in ipairs(G.each()) do
		local d = Util.hypot(s.p.x - x, s.p.y - y)
		if d < bd then
			bd = d
			best = s
		end
	end
	return best, bd
end

function G.playerName(sess)
	return sess.player.DisplayName ~= "" and sess.player.DisplayName or sess.player.Name
end

-- все имена лошадей игрока (чтобы не повторялись)
function G.takenNames(sess)
	local t = {}
	if sess then
		for _, h in ipairs(sess.P.horses) do table.insert(t, h.name) end
	end
	return t
end

G.Players = Players
G.Horses = Horses
return G
