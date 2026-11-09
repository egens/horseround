--[[
	Мини-игры (перенос js/care.js и лассо из js/ui.js) и заставка рождения жеребёнка:
	 - лассо: останови стрелку в зелёной зоне;
	 - расчесать: води щёткой, пока не исчезнет пыль;
	 - помыть: намыль губкой, потом смой водой;
	 - подковать: по 3 гвоздика в каждое копыто, когда молоточек над зелёной зоной.
]]
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local Horses = require(Shared.Horses)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local State = require(Client.State)
local HB = require(Client.HorseBuilder)
local Sound = require(Client.Sound)
local Kit = require(script.Parent.Kit)

local MG = {}
local make, C, color = Kit.make, Kit.C, Util.color
local gui

local function overlay(name)
	local shade = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Visible = false, ZIndex = 30, Parent = gui })
	local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel, ZIndex = 31, Parent = shade })
	make("UISizeConstraint", { MaxSize = Vector2.new(600, 2000), Parent = box })
	make("UIScale", { Name = "Scale", Parent = box })
	Kit.corner(box, 14)
	Kit.pad(box, 12)
	make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	return shade, box
end
local function fitScale(box)
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 800
	box.Scale.Scale = math.min(1, (vw - 20) / 620)
end

--[[ ================= лассо ================= ]]
local lasso = { data = nil }
local function lassoPos(d)
	local s = (workspace:GetServerTimeNow() - d.start) * d.speed
	local m = s % 2
	return m <= 1 and m or 2 - m
end
local function buildLasso()
	local shade, box = overlay("Lasso")
	lasso.shade = shade
	Kit.text(box, "<b>🤠 Бросай лассо!</b>", { size = 24, center = true })
	lasso.who = Kit.text(box, "", { center = true, size = 15 })
	lasso.temper = Kit.text(box, "", { center = true, size = 15 })
	local bar = Kit.corner(make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = color("#ffc9c9"), LayoutOrder = Kit.nextOrder(), Parent = box }), 8)
	lasso.zone = make("Frame", { BackgroundColor3 = color("#69db7c"), BorderSizePixel = 0, Size = UDim2.fromScale(0.2, 1), Parent = bar })
	lasso.needle = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = color("#3b2a1a"), BorderSizePixel = 0, Size = UDim2.new(0, 5, 1, 8), Position = UDim2.new(0, 0, 0, -4), Parent = bar })
	Kit.small(box, "Останови стрелку в зелёной зоне")
	Kit.button(Kit.row(box, { center = true }), "Бросить! (Пробел)", function() MG.throwLasso() end, { big = true, color = "orange" })
end
function MG.showLasso(d)
	if d.close then
		lasso.data = nil
		lasso.shade.Visible = false
		return
	end
	lasso.data = d
	lasso.who.Text = d.who
	lasso.temper.Text = d.temper .. " " .. d.bait
	lasso.zone.Position = UDim2.fromScale(d.center - d.zone / 2, 0)
	lasso.zone.Size = UDim2.fromScale(d.zone, 1)
	fitScale(lasso.shade:FindFirstChildWhichIsA("Frame"))
	lasso.shade.Visible = true
end
function MG.throwLasso()
	local d = lasso.data
	if not d then return end
	lasso.data = nil
	State.act("lassoThrow", lassoPos(d))
	task.delay(1, function() if not lasso.data then lasso.shade.Visible = false end end)
end
function MG.lassoOpen() return lasso.data ~= nil end

--[[ ================= уход ================= ]]
local care = {}
local AREA_W, AREA_H = 560, 320
local function buildCare()
	local shade, box = overlay("Care")
	care.shade, care.box = shade, box
	local head = Kit.row(box)
	care.title = Kit.text(head, "", { bold = true, size = 20, width = 0, widthOffset = 500 })
	Kit.closeButton(head, function() MG.closeCare(false) end, 30, { LayoutOrder = Kit.nextOrder() })
	care.hint = Kit.text(box, "", { size = 15 })
	care.area = make("Frame", { Size = UDim2.fromOffset(AREA_W, AREA_H), BackgroundColor3 = color("#fff3dc"), ClipsDescendants = true, LayoutOrder = Kit.nextOrder(), Parent = box })
	Kit.corner(care.area, 10)
	care.vpf = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = care.area })
	care.layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = care.area })
	care.cursor = make("TextLabel", { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "", TextSize = 34, ZIndex = 5, Parent = care.area })
	local track = Kit.corner(make("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = color("#e9dcc4"), ClipsDescendants = true, LayoutOrder = Kit.nextOrder(), Parent = box }), 7)
	care.progress = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green, BorderSizePixel = 0, Parent = track })
	care.btn = Kit.button(Kit.row(box, { center = true }), "", function() if care.game and care.game.button then care.game.button() end end, { big = true, color = "orange" })
end
local function setProgress(v) care.progress.Size = UDim2.fromScale(math.clamp(v, 0, 1), 1) end
local function setButton(text)
	care.btn.Visible = text ~= nil
	if text then care.btn.Text = text end
end
local function blob(c, x, y, r, rnd)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(r * 2, r * 1.4), BackgroundColor3 = color(c), BackgroundTransparency = 0.15, BorderSizePixel = 0, Rotation = rnd and rnd() * 180 or 0, Parent = care.layer })
	Kit.corner(f, r)
	return f
end
local function eraseAt(list, p, r)
	local n = 0
	for i = #list, 1, -1 do
		local f = list[i]
		local dx, dy = f.Position.X.Offset - p.X, f.Position.Y.Offset - p.Y
		if dx * dx + dy * dy < r * r then
			f:Destroy()
			table.remove(list, i)
			n += 1
		end
	end
	return n
end

local function brushGame(h)
	local rnd = Util.rng(h.seed + 77)
	local dust = {}
	for _ = 1, 40 do
		local c = ({ "#8b653c", "#785a37", "#a07d50" })[math.floor(rnd() * 3) + 1]
		table.insert(dust, blob(c, 160 + rnd() * 300, 100 + rnd() * 120, 18 * (0.6 + rnd() * 0.8), rnd))
	end
	local start = #dust
	local g = { score = 0, cursor = "🖌️" }
	g.move = function(p) eraseAt(dust, p, 30) end
	g.button = function() if 1 - #dust / start >= 0.92 then MG.closeCare(true) end end
	g.step = function()
		local prog = 1 - #dust / start
		setProgress(prog)
		if prog >= 0.92 then
			g.score = 1
			setButton("✨ Готово! Лошадь блестит")
		end
	end
	return { title = "🖌️ Расчесать: " .. h.name, hint = "Води щёткой (мышкой или пальцем) по лошади, пока не исчезнет вся пыль", game = g }
end

local function washGame(h)
	local rnd = Util.rng(h.seed + 91)
	local dirt, foam = {}, {}
	for _ = 1, 22 do table.insert(dirt, blob("#6e502d", 160 + rnd() * 300, 100 + rnd() * 120, 16 * (0.6 + rnd() * 0.8), rnd)) end
	local step, soapT = "soap", 0
	local g = { score = 0, cursor = "🧽" }
	g.move = function(p)
		if step == "soap" then
			if p.X < 140 or p.X > 480 or p.Y < 60 or p.Y > 250 then return end
			for i = 1, 2 do
				local f = blob(({ "#ffffff", "#e6f5ff", "#fff0fa" })[i], p.X + (math.random() - 0.5) * 34, p.Y + (math.random() - 0.5) * 26, 6 + math.random() * 8)
				f.BackgroundTransparency = 0.05
				table.insert(foam, f)
			end
			eraseAt(dirt, p, 18)
			soapT += 1
		elseif step == "rinse" then
			eraseAt(foam, p, 34)
			eraseAt(dirt, p, 34)
		end
	end
	g.button = function()
		if step == "soap" and soapT > 70 then
			step = "rinse"
			g.cursor = "🚿"
			care.hint.Text = "Теперь смой пену водой из шланга 🚿 — води по лошади"
			setButton(nil)
		elseif step == "done" then
			MG.closeCare(true)
		end
	end
	local foamMax = 1
	g.step = function()
		if step == "soap" then
			setProgress(math.min(1, soapT / 70) * 0.5)
			foamMax = math.max(foamMax, #foam)
			if soapT > 70 then setButton("🚿 Смыть пену") end
		elseif step == "rinse" then
			local left = #foam / math.max(1, foamMax)
			setProgress(0.5 + (1 - left) * 0.5)
			if #foam <= 2 then
				for _, f in ipairs(foam) do f:Destroy() end
				table.clear(foam)
				step = "done"
				g.score = 1
				setButton("✨ Готово! Чистая и мокрая")
				care.hint.Text = "Лошадь чистая! Она немного мокрая — скоро высохнет"
			end
		end
	end
	return { title = "🛁 Помыть: " .. h.name, hint = "Намыль лошадь губкой 🧽 — води по ней, чтобы появилась пена", game = g }
end

local function shoeGame(h)
	local HOOVES = { "левое переднее", "правое переднее", "левое заднее", "правое заднее" }
	local hoof, nail, hits, pos, dir, done = 0, 0, 0, 0, 1, false
	local zone = { c = 0.5, w = 0.2 }
	local function newZone() zone = { c = 0.2 + math.random() * 0.6, w = 0.16 + math.random() * 0.08 } end
	newZone()
	local bar = Kit.corner(make("Frame", { Position = UDim2.fromOffset(60, 262), Size = UDim2.fromOffset(440, 30), BackgroundColor3 = color("#ffc9c9"), Parent = care.layer }), 6)
	local zf = make("Frame", { BackgroundColor3 = color("#69db7c"), BorderSizePixel = 0, Parent = bar })
	local hammer = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Text = "🔨", TextSize = 32, Size = UDim2.fromOffset(40, 40), Parent = care.layer })
	local status = make("TextLabel", { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(520, 30), BackgroundTransparency = 1, Text = "", Font = Kit.BOLD, TextSize = 18, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = care.layer })
	local flash = make("TextLabel", { Position = UDim2.fromOffset(180, 50), Size = UDim2.fromOffset(200, 34), BackgroundTransparency = 1, Text = "", Font = Kit.BOLD, TextSize = 26, TextTransparency = 1, Parent = care.layer })
	local g = { score = 0, cursor = "" }
	g.button = function()
		if done then MG.closeCare(true) return end
		local ok = math.abs(pos - zone.c) < zone.w / 2
		flash.Text = ok and "Тук! Ровно!" or "Мимо!"
		flash.TextColor3 = ok and color("#2b8a3e") or C.red
		flash.TextTransparency = 0
		if ok then hits += 1; Sound.play("tick") else Sound.play("thud") end
		nail += 1
		if nail >= 3 then nail = 0; hoof += 1 end
		if hoof >= 4 then
			done = true
			g.score = hits / 12
			setButton("🔧 Готово! Попаданий: " .. hits .. " из 12")
			care.hint.Text = hits >= 9 and "Отличная работа, как у настоящего кузнеца!" or "Подковы на месте. В следующий раз получится ещё ровнее!"
			return
		end
		newZone()
	end
	g.step = function(dt)
		if not done then
			pos += dir * dt * 1.08 * (1 + hoof * 0.15)
			if pos > 1 then pos = 1; dir = -1 end
			if pos < 0 then pos = 0; dir = 1 end
		end
		zf.Position = UDim2.fromScale(zone.c - zone.w / 2, 0)
		zf.Size = UDim2.fromScale(zone.w, 1)
		hammer.Position = UDim2.fromOffset(60 + pos * 440, 260)
		flash.TextTransparency = math.min(1, flash.TextTransparency + dt * 1.8)
		status.Text = done and "" or ("Копыто: " .. HOOVES[hoof + 1] .. " · гвоздик " .. (nail + 1) .. " из 3   " .. string.rep("🧲", hoof) .. string.rep("⚪", 4 - hoof))
		setProgress((hoof * 3 + nail) / 12)
	end
	return { title = "🔧 Подковать: " .. h.name, hint = "Жми «Забить гвоздь» (или Пробел), когда молоточек над зелёной зоной", game = g, btn = "🔨 Забить гвоздь" }
end

function MG.openCare(d)
	local h = State.byId(d.id)
	if not h then return end
	care.kind, care.id = d.kind, d.id
	for _, c in ipairs(care.layer:GetChildren()) do c:Destroy() end
	pcall(HB.portrait, care.vpf, Horses.look(h))
	local def = d.kind == "brush" and brushGame(h) or d.kind == "wash" and washGame(h) or shoeGame(h)
	care.game = def.game
	care.title.Text = def.title
	care.hint.Text = def.hint
	setButton(def.btn)
	setProgress(0)
	fitScale(care.box)
	care.shade.Visible = true
end
function MG.closeCare(done)
	local g = care.game
	care.game = nil
	care.shade.Visible = false
	care.cursor.Text = ""
	if done and g then State.act("careDone", care.id, care.kind, g.score or 0) end
end
function MG.careOpen() return care.game ~= nil end
function MG.careButton()
	if care.game and care.game.button then care.game.button() end
end

local pointerDown = false
local function areaPoint(screen)
	local a = care.area
	local scale = care.box.Scale.Scale
	local rel = (screen - a.AbsolutePosition) / scale
	return rel
end
local function onPointer(screen)
	if not care.game then return end
	local p = areaPoint(screen)
	care.cursor.Position = UDim2.fromOffset(p.X, p.Y)
	care.cursor.Text = care.game.cursor or ""
	if pointerDown and care.game.move and p.X >= 0 and p.Y >= 0 and p.X <= AREA_W and p.Y <= AREA_H then care.game.move(p) end
end

--[[ ================= рождение жеребёнка ================= ]]
local birth = {}
local function buildBirth()
	local shade, box = overlay("Birth")
	birth.shade, birth.box = shade, box
	Kit.text(box, "<b>🍼 Рождается жеребёнок!</b>", { size = 22, center = true })
	birth.vpf = make("ViewportFrame", { Size = UDim2.fromOffset(560, 300), BackgroundColor3 = color("#d8eec0"), LayoutOrder = Kit.nextOrder(), Parent = box })
	Kit.corner(birth.vpf, 10)
	birth.text = Kit.text(box, "", { center = true, size = 16 })
	birth.ok = Kit.button(Kit.row(box, { center = true }), "Ура! 💕", function()
		birth.shade.Visible = false
		birth.running = nil
		require(script.Parent.Hud).toast("🍼 Жеребёнок в деннике. С ним можно гулять, поить молоком, гладить и играть!", "good")
	end, { big = true, color = "green" })
end
-- сердечко из простых деталей (квадрат, повёрнутый на 45°, и два кружка) — так оно видно на любом устройстве
local HEART_COLS = { "#ff4d6d", "#ff8fab", "#e64980", "#f783ac", "#c2255c" }
local function heart(parent, size, c)
	local h = make("Frame", { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 40, Parent = parent })
	local parts = {}
	table.insert(parts, make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(0.5, 0.5), Rotation = 45,
		BackgroundColor3 = color(c), BorderSizePixel = 0, ZIndex = 40, Parent = h }))
	for _, x in ipairs({ 0.323, 0.677 }) do
		local b = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.423), Size = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = color(c), BorderSizePixel = 0, ZIndex = 40, Parent = h })
		Kit.corner(b, size)
		table.insert(parts, b)
	end
	return h, parts
end
local function heartBurst(parent, token)
	task.spawn(function()
		local t0 = os.clock()
		while birth.running == token and os.clock() - t0 < 12 do
			local size = math.random(18, 34)
			local h, parts = heart(parent, size, HEART_COLS[math.random(1, #HEART_COLS)])
			local x0 = 0.15 + math.random() * 0.7
			local y0 = 0.75 + math.random() * 0.2
			local sway, life, born = math.random() * 6, 2.2 + math.random() * 1.2, os.clock()
			h.Position = UDim2.fromScale(x0, y0)
			task.spawn(function()
				while h.Parent do
					local k = (os.clock() - born) / life
					if k >= 1 then h:Destroy() break end
					h.Position = UDim2.fromScale(x0 + math.sin(k * 6 + sway) * 0.03, y0 - k * 0.7)
					h.Rotation = math.sin(k * 5 + sway) * 12
					for _, p in ipairs(parts) do p.BackgroundTransparency = math.clamp((k - 0.6) / 0.4, 0, 1) end
					RunService.RenderStepped:Wait()
				end
			end)
			task.wait(os.clock() - t0 < 7 and 0.35 or 0.15)
		end
	end)
end

function MG.birth(d)
	task.spawn(function()
		local mare, foal
		for _ = 1, 30 do
			mare, foal = State.byId(d.mare), State.byId(d.foal)
			if foal then break end
			task.wait(0.1)
		end
		if not foal then return end
		birth.vpf:ClearAllChildren()
		local wm = Instance.new("WorldModel")
		wm.Parent = birth.vpf
		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		cam.CFrame = CFrame.lookAt(Vector3.new(2, 6, 22), Vector3.new(0, 3, 0))
		cam.Parent = birth.vpf
		birth.vpf.CurrentCamera = cam
		local me = mare and HB.build(Horses.look(mare)) or nil
		local fe = HB.build(Horses.look(foal))
		if me then me.model.Parent = wm end
		fe.model.Parent = wm
		birth.text.Text = "У кобылы " .. (mare and mare.name or "") .. " рождается малыш…"
		birth.ok.Visible = false
		fitScale(birth.box)
		birth.shade.Visible = true
		local t0 = os.clock()
		local token = {}
		birth.running = token
		heartBurst(birth.vpf, token)
		while birth.running == token do
			local t = os.clock() - t0
			if me then HB.pose(me, { pos = Vector3.new(-5, 0, -1), angle = 0.3, spd = 0, act = t < 2.5 and nil or { k = "lookDown", t = math.min(t - 2.5, 1.2), d = 2.5 }, t = t }) end
			local act
			if t < 2 then act = { k = "lie", t = t, d = 99 }
			elseif t < 7 then act = { k = "getup", t = t - 2, d = 5 }
			else act = nil end
			HB.pose(fe, { pos = Vector3.new(4, 0, 2), angle = math.pi - 0.4, spd = 0, act = act, t = t })
			if t >= 7 and not birth.ok.Visible then
				local ph = Horses.pheno(foal)
				birth.text.Text = "🎉 Родился жеребёнок! <b>" .. Kit.esc(foal.name) .. "</b> — " .. Horses.sexText(foal) .. ", " .. Kit.esc(ph.name) ..
					(foal.magic and (", " .. Kit.esc(Horses.magicText(foal))) or "") .. ". " .. Horses.v(foal, "Она", "Он") .. " уже стоит на ножках!"
				birth.ok.Visible = true
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

function MG.init(parentGui)
	gui = parentGui
	buildLasso()
	buildCare()
	buildBirth()
	Net.get("Lasso").OnClientEvent:Connect(MG.showLasso)
	Net.get("Care").OnClientEvent:Connect(MG.openCare)
	Net.get("Birth").OnClientEvent:Connect(MG.birth)
	RunService.RenderStepped:Connect(function(dt)
		if lasso.data then
			local p = lassoPos(lasso.data)
			lasso.needle.Position = UDim2.new(p, 0, 0, -4)
		end
		if care.game and care.game.step then care.game.step(dt) end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pointerDown = true
			onPointer(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then pointerDown = false end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			onPointer(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
end

return MG
