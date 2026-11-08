--[[
	Маленький набор деталей интерфейса (вместо HTML и CSS из JS-версии):
	текст, кнопки, ряды кнопок, полоски, карточки лошадей с портретом, образцы цветов.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)
local Horses = require(Shared.Horses)

local Client = script.Parent.Parent
local HB = require(Client.HorseBuilder)

local Kit = {}
local color = Util.color
Kit.C = {
	text = color("#3b2a1a"), muted = color("#7a6650"), panel = color("#fff8ec"), panel2 = color("#f6ead4"),
	btn = color("#f1e3c6"), green = color("#37b24d"), orange = color("#f08c00"), pink = color("#e64980"), blue = color("#1c7ed6"),
	red = color("#e03131"), white = Color3.new(1, 1, 1), note = color("#fff3bf"), line = color("#e2cfae"),
}
local C = Kit.C
Kit.FONT = Enum.Font.Gotham
Kit.BOLD = Enum.Font.GothamBold

function Kit.make(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if props and props.Parent then o.Parent = props.Parent end
	return o
end
local make = Kit.make

function Kit.corner(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = o })
	return o
end
function Kit.pad(o, p)
	make("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), Parent = o })
	return o
end
function Kit.stroke(o, c, th)
	make("UIStroke", { Color = c or C.line, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = o })
	return o
end

local order = 0
local function nextOrder()
	order += 1
	return order
end
Kit.nextOrder = nextOrder

function Kit.text(parent, text, opts)
	opts = opts or {}
	local t = make("TextLabel", {
		Size = UDim2.new(opts.width or 1, opts.widthOffset or 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = opts.bg and 0 or 1, BackgroundColor3 = opts.bg or C.note,
		Text = text, RichText = true, TextWrapped = true, TextXAlignment = opts.center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
		Font = opts.bold and Kit.BOLD or Kit.FONT, TextSize = opts.size or 16, TextColor3 = opts.color or C.text,
		LayoutOrder = nextOrder(), Parent = parent,
	})
	if opts.bg then
		Kit.corner(t, 8)
		Kit.pad(t, 8)
	end
	return t
end
function Kit.h(parent, text)
	return Kit.text(parent, text, { bold = true, size = 18 })
end
function Kit.small(parent, text)
	return Kit.text(parent, text, { size = 13, color = C.muted })
end
function Kit.note(parent, text)
	return Kit.text(parent, text, { bg = C.note, size = 15 })
end

-- ряд с переносом на новую строку. Высоту считаем сами по AbsoluteContentSize:
-- AutomaticSize у ряда с Wraps учитывает только первую строку, и следующие блоки наезжают на перенесённые.
function Kit.row(parent, opts)
	opts = opts or {}
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = parent,
	})
	local layout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, opts.gap or 6),
		HorizontalAlignment = opts.center and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left,
		VerticalAlignment = opts.top and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = f,
	})
	local function fit()
		local hgt = layout.AbsoluteContentSize.Y
		if f.Size.Y.Offset ~= hgt then f.Size = UDim2.new(1, 0, 0, hgt) end
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()
	return f
end
function Kit.col(parent, opts)
	opts = opts or {}
	local f = make("Frame", {
		Size = UDim2.new(opts.width or 1, opts.widthOffset or 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = opts.bg and 0 or 1, BackgroundColor3 = opts.bg or C.panel2, LayoutOrder = nextOrder(), Parent = parent,
	})
	make("UIListLayout", { Padding = UDim.new(0, opts.gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = opts.center and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left, Parent = f })
	if opts.bg then
		Kit.corner(f, 10)
		Kit.pad(f, 8)
	end
	return f
end

-- кнопка; opts: color ('green'|'orange'|'pink'|'blue'|'ghost'), small, big, disabled, active, width
function Kit.button(parent, text, onClick, opts)
	opts = opts or {}
	local bg = opts.color and C[opts.color] or C.btn
	local fg = (opts.color and opts.color ~= "ghost" and opts.color ~= "btn") and C.white or C.text
	if opts.color == "ghost" then bg = C.panel2 end
	if opts.active then bg = C.blue; fg = C.white end
	local b = make("TextButton", {
		AutoButtonColor = not opts.disabled,
		Size = opts.width and UDim2.fromOffset(opts.width, opts.big and 46 or opts.small and 28 or 36) or UDim2.fromOffset(0, opts.big and 46 or opts.small and 28 or 36),
		AutomaticSize = opts.width and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		BackgroundColor3 = bg, Text = text, RichText = true, Font = Kit.BOLD, TextSize = opts.big and 19 or opts.small and 13 or 15, TextColor3 = fg,
		LayoutOrder = nextOrder(), Parent = parent,
	})
	Kit.corner(b, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, opts.small and 8 or 12), PaddingRight = UDim.new(0, opts.small and 8 or 12), Parent = b })
	if opts.disabled then
		b.BackgroundTransparency = 0.45
		b.TextTransparency = 0.45
	elseif onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function careColor(v) return v < 25 and C.red or v < 50 and C.orange or C.green end
Kit.careColor = careColor
function Kit.bar(parent, label, v, c, maxV)
	v = math.floor((v or 0) + 0.5)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = parent })
	make("TextLabel", { Size = UDim2.new(0.38, 0, 1, 0), BackgroundTransparency = 1, Text = label, Font = Kit.FONT, TextSize = 14, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
	local track = Kit.corner(make("Frame", { Position = UDim2.new(0.38, 0, 0.2, 0), Size = UDim2.new(0.5, 0, 0.6, 0), BackgroundColor3 = color("#e9dcc4"), ClipsDescendants = true, Parent = f }), 6)
	make("Frame", { Size = UDim2.new(math.clamp(v / (maxV or 100), 0, 1), 0, 1, 0), BackgroundColor3 = typeof(c) == "Color3" and c or (c and color(c) or careColor(v)), BorderSizePixel = 0, Parent = track })
	make("TextLabel", { Position = UDim2.new(0.9, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0), BackgroundTransparency = 1, Text = tostring(v), Font = Kit.BOLD, TextSize = 14, TextColor3 = C.text, Parent = f })
	return f
end
function Kit.skillBar(parent, h, k)
	local base, all = h.base[k], Horses.skill(h, k)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = parent })
	make("TextLabel", { Size = UDim2.new(0.38, 0, 1, 0), BackgroundTransparency = 1, Text = Horses.SKILLS[k], Font = Kit.FONT, TextSize = 14, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
	local track = Kit.corner(make("Frame", { Position = UDim2.new(0.38, 0, 0.2, 0), Size = UDim2.new(0.5, 0, 0.6, 0), BackgroundColor3 = color("#e9dcc4"), ClipsDescendants = true, Parent = f }), 6)
	make("Frame", { Size = UDim2.new(base / 100, 0, 1, 0), BackgroundColor3 = color("#748ffc"), BorderSizePixel = 0, Parent = track })
	make("Frame", { Position = UDim2.new(base / 100, 0, 0, 0), Size = UDim2.new(math.max(0, all - base) / 100, 0, 1, 0), BackgroundColor3 = color("#ffd43b"), BorderSizePixel = 0, Parent = track })
	make("TextLabel", { Position = UDim2.new(0.9, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0), BackgroundTransparency = 1, Text = tostring(all), Font = Kit.BOLD, TextSize = 14, TextColor3 = C.text, Parent = f })
	return f
end

-- портрет лошади (3D во вьюпорте)
function Kit.portrait(parent, look, w, h, tack)
	local vpf = make("ViewportFrame", { Size = UDim2.fromOffset(w or 150, h or 80), BackgroundColor3 = color("#fdf4e3"), LayoutOrder = nextOrder(), Parent = parent })
	Kit.corner(vpf, 8)
	local ok = pcall(HB.portrait, vpf, look, tack)
	if not ok then vpf.BackgroundColor3 = color(Horses.pheno(look).body) end
	return vpf
end

-- карточка: портрет и строки, extra(card) — кнопки
function Kit.card(parent, look, lines, extra, opts)
	opts = opts or {}
	local card = make("Frame", { Size = UDim2.fromOffset(opts.width or 176, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = opts.selected and color("#d0ebff") or C.panel2, LayoutOrder = nextOrder(), Parent = parent })
	Kit.corner(card, 10)
	Kit.pad(card, 6)
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = card })
	if look then Kit.portrait(card, look, (opts.width or 176) - 12, 80) end
	for i, line in ipairs(lines or {}) do
		Kit.text(card, line, { size = i == 1 and 15 or 13, bold = i == 1, color = i == 1 and C.text or C.muted })
	end
	if extra then extra(card) end
	if opts.onClick then
		local b = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = card })
		b.Activated:Connect(opts.onClick)
	end
	return card
end

function Kit.grid(parent)
	return Kit.row(parent, { gap = 8, top = true })
end

-- образец цвета
function Kit.swatch(parent, hex, selected, onClick)
	local b = make("TextButton", { Size = UDim2.fromOffset(30, 30), BackgroundColor3 = hex == "rainbow" and color("#cc5de8") or color(hex), Text = selected and "✔" or "", TextColor3 = C.white, Font = Kit.BOLD, TextSize = 16, LayoutOrder = nextOrder(), Parent = parent })
	Kit.corner(b, 15)
	Kit.stroke(b, selected and C.blue or C.line, selected and 3 or 1)
	if hex == "rainbow" then
		make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color("#ff6b6b")), ColorSequenceKeypoint.new(0.3, color("#ffe066")), ColorSequenceKeypoint.new(0.6, color("#69db7c")), ColorSequenceKeypoint.new(1, color("#9775fa")) }), Parent = b })
	end
	if onClick then b.Activated:Connect(onClick) end
	return b
end

-- строка магазина: иконка, название, подпись, кнопки
function Kit.item(parent, icon, title, sub, buttons)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel2, LayoutOrder = nextOrder(), Parent = parent })
	Kit.corner(f, 8)
	Kit.pad(f, 6)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	make("TextLabel", { Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, Text = icon, TextSize = 26, Font = Kit.FONT, LayoutOrder = nextOrder(), Parent = f })
	local tf = make("Frame", { Size = UDim2.new(0.5, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = f })
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = tf })
	Kit.text(tf, "<b>" .. title .. "</b>", { size = 15 })
	if sub and sub ~= "" then Kit.text(tf, sub, { size = 12, color = C.muted }) end
	if buttons then buttons(f) end
	return f
end

function Kit.input(parent, default, maxLen)
	local tb = make("TextBox", {
		Size = UDim2.fromOffset(170, 32), BackgroundColor3 = C.white, Text = default or "", ClearTextOnFocus = false,
		Font = Kit.FONT, TextSize = 15, TextColor3 = C.text, LayoutOrder = nextOrder(), Parent = parent,
	})
	Kit.corner(tb, 6)
	Kit.stroke(tb)
	if maxLen then
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			if utf8.len(tb.Text) and utf8.len(tb.Text) > maxLen then tb.Text = string.sub(tb.Text, 1, utf8.offset(tb.Text, maxLen + 1) - 1) end
		end)
	end
	return tb
end

function Kit.sexIcon(h)
	return h.sex == "f" and '<font color="#e64980">♀</font>' or '<font color="#1c7ed6">♂</font>'
end
function Kit.esc(s)
	s = tostring(s)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

return Kit
