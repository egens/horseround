--[[
	Строка состояния и кнопки (аналог #hud, #bottom, #exercise, #toasts и миникарты из index.html):
	деньги, лошади, часы, медали, события; кнопки окон; подсказка; панель езды; кнопка «E»;
	всплывающие сообщения; металлоискатель; миникарта.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local World = require(Shared.World)
local Items = require(Shared.Items)
local Q = require(Shared.QuestData)

local Client = script.Parent.Parent
local State = require(Client.State)
local Kit = require(script.Parent.Kit)
local Sound = require(Client.Sound)

local Hud = {}
local make, C, color = Kit.make, Kit.C, Util.color
local player = Players.LocalPlayer
local gui
local el = {}
Hud.windows = nil -- задаёт Main

local function pill(parent, text)
	local t = make("TextLabel", {
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.panel, BackgroundTransparency = 0.05,
		Text = text or "", Font = Kit.BOLD, TextSize = 15, TextColor3 = C.text, Parent = parent,
	})
	Kit.corner(t, 15)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = t })
	return t
end
local function hudButton(parent, text, fn, title)
	local b = make("TextButton", {
		Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.panel, Text = text, Font = Kit.BOLD, TextSize = 17, TextColor3 = C.text, Parent = parent,
	})
	Kit.corner(b, 17)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = b })
	b.Activated:Connect(fn)
	return b
end
local function hlist(parent, align, gap)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = parent })
end

--[[ ---------- всплывающие сообщения ---------- ]]
function Hud.toast(msg, kind)
	if not el.toasts then return end
	local bg = kind == "good" and color("#d3f9d8") or kind == "warn" and color("#ffe3e3") or C.panel
	local t = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = bg, Text = msg, TextWrapped = true,
		Font = Kit.BOLD, TextSize = 15, TextColor3 = C.text, LayoutOrder = math.floor(os.clock() * 1000), Parent = el.toasts,
	})
	Kit.corner(t, 10)
	Kit.pad(t, 8)
	local kids = {}
	for _, c in ipairs(el.toasts:GetChildren()) do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	while #kids > 4 do table.remove(kids, 1):Destroy() end
	task.delay(4.6, function()
		if t.Parent then
			for i = 1, 10 do
				t.BackgroundTransparency = i / 10
				t.TextTransparency = i / 10
				task.wait(0.03)
			end
			t:Destroy()
		end
	end)
end

--[[ ---------- построение ---------- ]]
function Hud.build()
	gui = make("ScreenGui", { Name = "HorseFarmHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false, Parent = player:WaitForChild("PlayerGui") })
	Hud.gui = gui
	-- верх слева
	local left = make("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0.55, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui })
	hlist(left)
	el.money = pill(left, "💰 0")
	el.count = pill(left, "🐴 0/20")
	el.clock = pill(left, "☀️ 08:00")
	el.medals = pill(left, "")
	el.event = pill(left, "")
	-- верх справа
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.new(0.44, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui })
	hlist(right, Enum.HorizontalAlignment.Right)
	local W = function(name, data) return function() Hud.windows.open(name, data) end end
	hudButton(right, "🐴 Лошади", function() Hud.windows.open("stable", { can = true }) end)
	el.quests = hudButton(right, "📜", W("quests"))
	hudButton(right, "👥", W("players"))
	hudButton(right, "📖 Индекс", W("index"))
	hudButton(right, "🗺 Карта", function() Hud.toggleMap() end)
	el.detector = hudButton(right, "📡", function() State.act("detector") end)
	hudButton(right, "🎒", W("inventory"))
	hudButton(right, "❓", W("help"))
	local snd
	snd = hudButton(right, "🔊", function() snd.Text = Sound.toggle() and "🔊" or "🔇" end)
	-- подсказка
	el.hint = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.new(0.6, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel, BackgroundTransparency = 0.15, Text = "", TextWrapped = true, Font = Kit.FONT, TextSize = 15, TextColor3 = C.text, Parent = gui,
	})
	Kit.corner(el.hint, 10)
	Kit.pad(el.hint, 6)
	-- металлоискатель
	el.meter = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(220, 26), BackgroundColor3 = C.panel, Visible = false, Parent = gui })
	Kit.corner(el.meter, 13)
	make("TextLabel", { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "📡", TextSize = 18, Parent = el.meter })
	local track = Kit.corner(make("Frame", { Position = UDim2.fromOffset(30, 7), Size = UDim2.new(1, -40, 0, 12), BackgroundColor3 = color("#e9dcc4"), ClipsDescendants = true, Parent = el.meter }), 6)
	el.meterBar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green, BorderSizePixel = 0, Parent = track })
	-- всплывающие сообщения
	el.toasts = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 96), Size = UDim2.fromOffset(340, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = el.toasts })
	-- упражнение
	el.exercise = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel, Visible = false, Parent = gui })
	Kit.corner(el.exercise, 12)
	Kit.pad(el.exercise, 8)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = el.exercise })
	el.exTitle = Kit.text(el.exercise, "", { bold = true, size = 17 })
	el.exLine = Kit.text(el.exercise, "", { size = 15 })
	el.exHint = Kit.text(el.exercise, "", { size = 15, bold = true })
	el.exLetter = make("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -34, 0, 0), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.white, Text = "", Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = color("#1c4f8a"), Parent = el.exercise })
	Kit.corner(el.exLetter, 8)
	Kit.closeButton(el.exercise, function() State.act("cancelEx") end, 28, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0) })
	-- низ: панели
	local bottom = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(0.9, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder, Parent = bottom })
	local function panel(order)
		local f = make("Frame", { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = C.panel, LayoutOrder = order, Visible = false, Parent = bottom })
		Kit.corner(f, 12)
		Kit.pad(f, 6)
		hlist(f, Enum.HorizontalAlignment.Center)
		return f
	end
	el.lead = panel(1)
	el.leadName = pill(el.lead, "")
	Kit.button(el.lead, "Отпустить", function() State.act("release") end, { small = true })
	el.walk = panel(2)
	el.walkName = pill(el.walk, "")
	Kit.button(el.walk, "💕 Погладить", function() State.act("pet") end, { small = true })
	Kit.button(el.walk, "🎾 Играть", function() State.act("play") end, { small = true })
	Kit.button(el.walk, "🏠 В денник", function() State.act("stopWalk") end, { small = true })
	el.ride = panel(3)
	el.rideName = pill(el.ride, "")
	local energy = Kit.corner(make("Frame", { Size = UDim2.fromOffset(110, 14), BackgroundColor3 = color("#e9dcc4"), ClipsDescendants = true, Parent = el.ride }), 7)
	el.energy = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.green, BorderSizePixel = 0, Parent = energy })
	el.gaits = {}
	for g = 0, 2 do
		el.gaits[g] = Kit.button(el.ride, (g + 1) .. " " .. Items.GAITS[g + 1], function() State.act("setGait", g) end, { small = true })
	end
	el.fly = Kit.button(el.ride, "🕊️ Взлететь", function() State.act("fly") end, { small = true })
	Kit.button(el.ride, "🎭 Трюки", function()
		local m = State.mounted()
		if m then Hud.windows.open("tricks", { id = m.id }) end
	end, { small = true })
	Kit.button(el.ride, "Слезть", function() State.act("dismount") end, { small = true, color = "ghost" })
	-- большие кнопки действий
	local actions = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4, Parent = bottom })
	hlist(actions, Enum.HorizontalAlignment.Center, 10)
	el.birth = Kit.button(actions, "🍼 Родить жеребёнка", function() State.act("birth") end, { big = true, color = "pink" })
	el.lift = Kit.button(actions, "⤴ Ноги выше!", function() Hud.onLift() end, { big = true, color = "orange" })
	el.lasso = Kit.button(actions, "🤠 Бросить лассо [F]", function() State.act("lasso") end, { big = true, color = "orange" })
	el.prompt = Kit.button(actions, "", function() State.act("interact") end, { big = true, color = "green" })
	-- миникарта и большая карта
	-- ошибка в карте не должна ломать весь интерфейс
	for _, f in ipairs({ Hud.buildMinimap, Hud.buildBigMap }) do
		local ok, err = pcall(f)
		if not ok then warn("[Hud] карта: " .. tostring(err)) end
	end
end

function Hud.onLift()
	State.act("lift")
end

--[[ ---------- миникарта ---------- ]]
local mm = {}
local MM_W, MM_H = 210, 160
local REGION_COLORS = {
	farm = "#9ccb6c", field = "#a9d26f", village = "#b5d38a", farmland = "#c8b26f", lake = "#8ec46a", forest = "#4f8a3a", foxwood = "#3f7231",
	deepforest = "#2f5a2a", mushroom = "#9b87c9", desert = "#e8cf8f", tundra = "#eef4f8", mountain = "#8a8580", cave = "#4a4744", grotto = "#86b84f",
	grottocave = "#4a4744", dragonrock = "#3b3436", steppe = "#c8b46a", sea = "#3f8fc0", market = "#d9b98c", i1 = "#86b84f", i2 = "#86b84f", i3 = "#86b84f", i4 = "#7a3b2e",
}
function Hud.buildMinimap()
	local frame = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.fromOffset(MM_W, MM_H), BackgroundColor3 = color("#3f8fc0"), ClipsDescendants = true, Parent = gui })
	Kit.corner(frame, 8)
	Kit.stroke(frame, C.panel, 2)
	mm.frame = frame
	-- карта суши по биомам (грубая сетка)
	local cols, rows = 44, 32
	local cw, ch = MM_W / cols, MM_H / rows
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local x, y = (i + 0.5) / cols * World.W, (j + 0.5) / rows * World.H
			local reg = World.regionAt(x, y)
			if World.lakeAt(x, y) then reg = "sea" end
			make("Frame", { Position = UDim2.fromOffset(i * cw, j * ch), Size = UDim2.fromOffset(cw + 1, ch + 1), BackgroundColor3 = color(REGION_COLORS[reg] or "#9ccb6c"), BorderSizePixel = 0, Parent = frame })
		end
	end
	local function dot(c, s)
		local d = make("Frame", { Size = UDim2.fromOffset(s, s), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color(c), BorderSizePixel = 0, ZIndex = 3, Parent = frame })
		Kit.corner(d, s)
		return d
	end
	mm.dot = dot
	mm.me = dot("#e64980", 8)
	mm.me.ZIndex = 5
	Kit.stroke(mm.me, C.white, 1)
	mm.others, mm.herds, mm.bunnies = {}, {}, {}
	-- жители — цветные точки (те же цвета, что на большой карте)
	for _, n in ipairs(Q.NPCS) do
		local d = dot(n.dot or "#ffffff", 5)
		d.Position = UDim2.fromOffset(n.x / World.W * MM_W, math.min(n.y, World.H) / World.H * MM_H)
		Kit.stroke(d, color("#222222"), 1)
	end
	mm.shoe = dot("#ffe066", 6)
	mm.treasure = make("TextLabel", { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "✖", TextColor3 = C.red, Font = Kit.BOLD, TextSize = 14, ZIndex = 4, Parent = frame })
	-- клик или тап по миникарте открывает большую карту
	local open = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8, Parent = frame })
	open.Activated:Connect(function() Hud.toggleMap(true) end)
	make("TextLabel", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -2), Size = UDim2.fromOffset(110, 14), BackgroundTransparency = 1,
		Text = "нажми — большая карта", TextSize = 10, Font = Kit.BOLD, TextColor3 = C.white, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = frame })
	mm.label = make("TextLabel", { Position = UDim2.fromOffset(4, 2), Size = UDim2.new(1, -8, 0, 14), BackgroundTransparency = 1, Text = "", TextSize = 11, Font = Kit.BOLD, TextColor3 = C.white, TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })
end
local function mmPos(x, y)
	local yy = math.min(y, World.H)
	return UDim2.fromOffset(x / World.W * MM_W, yy / World.H * MM_H)
end
local function updateMinimap()
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if r then
		local x, y = World.fromStuds(r.Position)
		mm.me.Position = mmPos(x, y)
		mm.label.Text = y > World.H and "☁️ Небесные острова" or ""
	end
	local ws = State.world
	-- другие игроки
	local seen = {}
	for _, p in ipairs(ws.players or {}) do
		if p.id ~= player.UserId then
			local d = mm.others[p.id] or mm.dot("#ffffff", 7)
			mm.others[p.id] = d
			d.Position = mmPos(p.x, p.y)
			seen[p.id] = true
		end
	end
	for id, d in pairs(mm.others) do
		if not seen[id] then d:Destroy(); mm.others[id] = nil end
	end
	-- табуны — головы лошадей
	for k, hpos in pairs(ws.herds or {}) do
		local d = mm.herds[k]
		if not d then
			d = make("TextLabel", { Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "🐴", TextSize = 10, ZIndex = 4, Parent = mm.frame })
			mm.herds[k] = d
		end
		d.Position = mmPos(hpos[1], hpos[2])
		d.Visible = hpos[2] <= World.H
	end
	for i, d in ipairs(mm.bunnies) do d.Visible = false end
	for i, b in ipairs(ws.bunnies or {}) do
		local d = mm.bunnies[i] or mm.dot("#ffffff", 3)
		mm.bunnies[i] = d
		d.Visible = true
		d.Position = mmPos(b[1], b[2])
	end
	mm.shoe.Visible = ws.shoe ~= nil
	if ws.shoe then mm.shoe.Position = mmPos(ws.shoe.x, ws.shoe.y) end
	local bt = State.hud and State.hud.bigTreasure
	mm.treasure.Visible = bt ~= nil
	if bt then mm.treasure.Position = mmPos(bt.x, bt.y) end
end

--[[ ---------- большая карта (M) ---------- ]]
local bm = {}
local BM_COLS, BM_ROWS = 132, 96
local function bmPos(x, y)
	return UDim2.fromScale(math.clamp(x / World.W, 0, 1), math.clamp(math.min(y, World.H) / World.H, 0, 1))
end
local function bmLabel(parent, text, x, y, size, col, z)
	local t = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = bmPos(x, y), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, Text = text, Font = Kit.BOLD, TextSize = size or 13, TextColor3 = col or C.white,
		TextStrokeTransparency = 0.3, ZIndex = z or 34, Parent = parent,
	})
	return t
end
function Hud.buildBigMap()
	local shade = make("TextButton", { Name = "BigMap", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
		Text = "", AutoButtonColor = false, Visible = false, ZIndex = 30, Parent = gui })
	shade.Activated:Connect(function() Hud.toggleMap(false) end)
	bm.shade = shade
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.94, 0.84),
		BackgroundColor3 = color("#3f8fc0"), ClipsDescendants = true, ZIndex = 31, Parent = shade })
	make("UIAspectRatioConstraint", { AspectRatio = World.W / World.H, Parent = frame })
	Kit.corner(frame, 12)
	Kit.stroke(frame, C.panel, 3)
	bm.frame = frame
	-- суша по биомам: одинаковые клетки подряд в строке склеиваем в одну полоску
	local sums = {}
	for j = 0, BM_ROWS - 1 do
		local runStart, runReg = 0, nil
		local function flush(i)
			if runReg and runReg ~= "sea" then
				make("Frame", { Position = UDim2.fromScale(runStart / BM_COLS, j / BM_ROWS), Size = UDim2.new((i - runStart) / BM_COLS, 1, 1 / BM_ROWS, 1),
					BackgroundColor3 = color(REGION_COLORS[runReg] or "#9ccb6c"), BorderSizePixel = 0, ZIndex = 32, Parent = frame })
			end
		end
		for i = 0, BM_COLS - 1 do
			local x, y = (i + 0.5) / BM_COLS * World.W, (j + 0.5) / BM_ROWS * World.H
			local reg = World.regionAt(x, y)
			if World.lakeAt(x, y) then reg = "sea" end
			if reg ~= "sea" then
				local sm = sums[reg] or { x = 0, y = 0, n = 0 }
				sm.x += x; sm.y += y; sm.n += 1
				sums[reg] = sm
			end
			if reg ~= runReg then
				flush(i)
				runStart, runReg = i, reg
			end
		end
		flush(BM_COLS)
	end
	-- дороги — коричневые линии
	for _, r in ipairs(World.ROADS) do
		for i = 1, #r - 1 do
			local ax, ay, bx, by = r[i][1], r[i][2], r[i + 1][1], r[i + 1][2]
			if ay <= World.H and by <= World.H then
				local L = Util.hypot(bx - ax, by - ay)
				make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((ax + bx) / 2 / World.W, (ay + by) / 2 / World.H),
					Size = UDim2.new(L / World.W, 2, 0, 3), Rotation = math.deg(math.atan2(by - ay, bx - ax)), BackgroundColor3 = color("#8a6238"),
					BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 33, Parent = frame })
			end
		end
	end
	-- названия краёв — в середине их клеток, на тёмной подложке (их легко прочитать)
	for reg, sm in pairs(sums) do
		local name = World.REGION_NAMES[reg]
		if name and sm.n >= 12 and reg ~= "grottocave" then
			local t = bmLabel(frame, name, sm.x / sm.n, sm.y / sm.n, 15, C.white, 33)
			t.BackgroundColor3 = Color3.new(0, 0, 0)
			t.BackgroundTransparency = 0.6
			Kit.corner(t, 6)
			make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = t })
		end
	end
	-- озёра с названиями
	for _, L in ipairs(World.LAKES) do
		if L.name then bmLabel(frame, (L.lava and "🌋 " or "💧 ") .. L.name, L.x, L.y, 11, L.lava and color("#ffd8a8") or color("#d0ebff"), 34) end
	end
	-- важные места
	local function place(icon, name, x, y)
		bmLabel(frame, icon .. " " .. name, x, y, 12, color("#fff3bf"), 34)
	end
	local S, Mk, St = World.STABLE, World.MARKET, World.STATION
	place("🏠", "Конюшня", S.x + S.w / 2, S.y + S.h / 2)
	place("🎪", "Рынок", Mk.x + Mk.w / 2, Mk.y + Mk.h / 2)
	place("🚂", "Станция", St.x + St.w / 2, St.y)
	place("⛵", World.PIER.name or "Пристань", World.PIER.x, World.PIER.y)
	place("🌀", "Портал", World.PORTAL.x, World.PORTAL.y)
	place("🏁", "Скачки", World.START.x, World.START.y)
	for _, I in ipairs(World.ISLANDS) do place("⛵", "", I.pier.x, I.pier.y) end
	-- жители: у каждого своя цветная точка (список цветов — справа)
	for _, n in ipairs(Q.NPCS) do
		local d = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = bmPos(n.x, n.y), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = color(n.dot or "#ffffff"),
			BorderSizePixel = 0, ZIndex = 36, Parent = frame })
		Kit.corner(d, 7)
		Kit.stroke(d, color("#222222"), 2)
		bm.npc = bm.npc or {}
		bm.npc[n.id] = d
	end
	-- живые отметки
	local function dot(c, sz, z)
		local d = make("Frame", { Size = UDim2.fromOffset(sz, sz), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color(c), BorderSizePixel = 0, ZIndex = z or 35, Parent = frame })
		Kit.corner(d, sz)
		return d
	end
	bm.dot = dot
	bm.me = make("TextLabel", { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "▲",
		TextColor3 = color("#e64980"), TextStrokeColor3 = C.white, TextStrokeTransparency = 0, Font = Kit.BOLD, TextSize = 24, ZIndex = 38, Parent = frame })
	bm.others, bm.herds = {}, {}
	bm.shoe = bmLabel(frame, "🧲", 0, 0, 14, C.white, 36)
	bm.treasure = bmLabel(frame, "✖", 0, 0, 20, C.red, 36)
	bm.train = bmLabel(frame, "🚂", 0, 0, 18, C.white, 36)
	-- заголовок и подсказка
	local top = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(1, -20, 0, 26), BackgroundTransparency = 1,
		Text = "🗺️ Карта мира — M или клик, чтобы закрыть", Font = Kit.BOLD, TextSize = 18, TextColor3 = C.white, TextStrokeTransparency = 0.2, ZIndex = 39, Parent = frame })
	bm.title = top
	Kit.closeButton(frame, function() Hud.toggleMap(false) end, 34, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), ZIndex = 40 })
	local legend = make("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -6), Size = UDim2.new(1, -16, 0, 20), BackgroundTransparency = 1,
		Text = "▲ ты   ⚪ игроки   🐴 лошади (табуны)   ● жители   ✖ клад   🚂 поезд   🧲 подкова   — дороги", Font = Kit.BOLD, TextSize = 14, TextColor3 = C.white, TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 39, Parent = frame })
	bm.legend = legend
	-- список жителей сбоку: какая точка — кто
	local side = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 39, Parent = frame })
	Kit.corner(side, 8)
	Kit.pad(side, 6)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = side })
	make("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "Жители на карте:", Font = Kit.BOLD, TextSize = 14, TextColor3 = C.white,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 40, LayoutOrder = 0, Parent = side })
	for i, n in ipairs(Q.NPCS) do
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, ZIndex = 40, LayoutOrder = i, Parent = side })
		local d = make("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = color(n.dot or "#ffffff"), BorderSizePixel = 0, ZIndex = 41, Parent = row })
		Kit.corner(d, 6)
		Kit.stroke(d, color("#222222"), 1)
		make("TextLabel", { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -20, 1, 0), BackgroundTransparency = 1, Text = n.name .. " — " .. (n.dotName or "") .. " точка",
			Font = Kit.FONT, TextSize = 12, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 41, Parent = row })
	end
	bm.side = side
end
local function updateBigMap()
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if r then
		local x, y = World.fromStuds(r.Position)
		bm.me.Position = bmPos(x, y)
		local lv = r.CFrame.LookVector
		bm.me.Rotation = math.deg(math.atan2(lv.X, -lv.Z))
		bm.title.Text = (y > World.H and "☁️ Ты на небесных островах · " or "🗺️ ") .. "Карта мира — M или клик, чтобы закрыть"
	end
	local ws = State.world
	local seen = {}
	for _, p in ipairs(ws.players or {}) do
		if p.id ~= player.UserId then
			local o = bm.others[p.id]
			if not o then
				o = { d = bm.dot("#ffffff", 10, 37) }
				Kit.stroke(o.d, color("#333333"), 1)
				o.l = bmLabel(bm.frame, "", 0, 0, 12, C.white, 37)
				bm.others[p.id] = o
			end
			o.d.Position = bmPos(p.x, p.y)
			o.l.Position = bmPos(p.x, p.y) + UDim2.fromOffset(0, -13)
			o.l.Text = p.name or ""
			seen[p.id] = true
		end
	end
	for id, o in pairs(bm.others) do
		if not seen[id] then o.d:Destroy(); o.l:Destroy(); bm.others[id] = nil end
	end
	-- табуны: голова лошади там, где пасутся лошади
	for k, hpos in pairs(ws.herds or {}) do
		local d = bm.herds[k]
		if not d then
			d = make("TextLabel", { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "🐴", TextSize = 18, ZIndex = 35, Parent = bm.frame })
			bm.herds[k] = d
		end
		d.Position = bmPos(hpos[1], hpos[2])
		d.Visible = hpos[2] <= World.H
	end
	bm.shoe.Visible = ws.shoe ~= nil
	if ws.shoe then bm.shoe.Position = bmPos(ws.shoe.x, ws.shoe.y) end
	local bt = State.hud and State.hud.bigTreasure
	bm.treasure.Visible = bt ~= nil
	if bt then bm.treasure.Position = bmPos(bt.x, bt.y) end
	bm.train.Visible = ws.train ~= nil
	if ws.train then bm.train.Position = bmPos(ws.train.x, World.RAIL.y) end
end
function Hud.toggleMap(on)
	if not bm.shade then return end
	if on == nil then on = not bm.shade.Visible end
	bm.shade.Visible = on
	if on then
		local ok, err = pcall(updateBigMap)
		if not ok then warn("[Hud] большая карта: " .. tostring(err)) end
	end
end
function Hud.mapOpen() return bm.shade ~= nil and bm.shade.Visible end

--[[ ---------- обновление ---------- ]]
local function show(o, on) o.Visible = on and true or false end
function Hud.update(d)
	el.money.Text = "💰 " .. d.money
	el.count.Text = "🐴 " .. d.count .. "/" .. d.max
	el.clock.Text = d.clock .. " · " .. (d.region or "")
	el.quests.Text = d.quests > 0 and ("📜 " .. d.quests) or "📜"
	local md = {}
	for _, k in ipairs({ "gold", "silver", "bronze" }) do
		if (d.medals[k] or 0) > 0 then table.insert(md, Items.MEDALS[k] .. d.medals[k]) end
	end
	el.medals.Text = table.concat(md, " ")
	show(el.medals, #md > 0)
	el.hint.Text = d.hint or ""
	show(el.hint, d.hint and d.hint ~= "")
	show(el.detector, d.detector ~= nil)
	show(el.meter, d.detector and d.detector.on)
	if d.detector then
		el.detector.BackgroundColor3 = d.detector.on and color("#d0ebff") or C.panel
		el.meterBar.Size = UDim2.fromScale(d.detector.signal, 1)
		el.meterBar.BackgroundColor3 = d.detector.signal > 0.85 and C.red or d.detector.signal > 0.5 and C.orange or C.green
	end
	-- кнопка «E»
	show(el.prompt, d.prompt ~= nil)
	if d.prompt then el.prompt.Text = d.prompt .. "  [E]" end
	show(el.lasso, d.canLasso)
	-- езда
	show(el.ride, d.mounted ~= nil)
	if d.mounted then
		local m = d.mounted
		el.rideName.Text = "🏇 " .. m.name
		el.energy.Size = UDim2.fromScale(math.clamp(m.energy / 100, 0, 1), 1)
		el.energy.BackgroundColor3 = m.energy < 25 and C.red or m.energy < 50 and C.orange or C.green
		for g = 0, 2 do
			el.gaits[g].BackgroundColor3 = g == m.gait and C.blue or C.btn
			el.gaits[g].TextColor3 = g == m.gait and C.white or C.text
		end
		show(el.fly, m.wings)
		el.fly.Text = m.fly and "🛬 Сесть" or "🕊️ Взлететь"
	end
	show(el.walk, d.walk ~= nil)
	if d.walk then el.walkName.Text = "🐴 Гуляем: " .. d.walk end
	show(el.birth, d.birth ~= nil and d.mounted == nil)
	if d.birth then el.birth.Text = "🍼 Родить жеребёнка (" .. d.birth .. ")" end
	show(el.lead, d.led ~= nil)
	if d.led then el.leadName.Text = "➰ " .. d.led end
	-- события: поезд, праздник
	local ev = ""
	local tr, hd = d.train or {}, d.holiday or {}
	if tr.catchLeft then ev = "🚂 Лови лошадей у поезда! " .. Util.mmss(tr.catchLeft)
	elseif tr.moving then ev = "🚂 Поезд едет по пустыне!"
	elseif hd.k then ev = hd.icon .. " " .. hd.name .. ": ещё " .. Util.mmss(hd.left)
	elseif tr.next and tr.next < 120 then ev = "🚂 Поезд через " .. Util.mmss(tr.next) end
	if State.world.fair then ev = (ev ~= "" and ev .. " · " or "") .. "🎪 Ярмарка" end
	if (State.world.invite or 0) > 0 then ev = (ev ~= "" and ev .. " · " or "") .. "🏁 Скачки ×2" end
	el.event.Text = ev
	show(el.event, ev ~= "")
	-- упражнение
	local x = d.exercise
	show(el.exercise, x ~= nil)
	show(el.lift, x ~= nil and x.lift == true)
	if x then
		if x.lift then el.lift.Text = x.liftLabel end
		el.exTitle.Text = x.title
		el.exLine.Text = x.line
		el.exHint.Text = x.hint
		el.exHint.TextColor3 = x.ok and color("#2b8a3e") or C.red
		el.exLetter.Text = x.letter or ""
		show(el.exLetter, x.letter ~= nil)
	end
end

function Hud.init()
	Hud.build()
	State.on("hud", Hud.update)
	RunService.Heartbeat:Connect(function()
		if mm.frame then pcall(updateMinimap) end
		if bm.shade and bm.shade.Visible then pcall(updateBigMap) end
	end)
	GuiService.MenuOpened:Connect(function() end)
end

Hud.el = el
return Hud
