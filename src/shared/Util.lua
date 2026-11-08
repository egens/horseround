--[[
	Общие помощники: случайные числа, детерминированный генератор (встроенный Random),
	смешивание цветов в hex, склонения, работа с таблицами.
]]
local Util = {}

-- детерминированный генератор на встроенном Random: одно зерно — одна и та же последовательность
-- (одинаково на сервере и у всех клиентов, поэтому мир у всех совпадает)
function Util.rng(seed)
	local r = Random.new(math.floor(seed))
	return function()
		return r:NextNumber()
	end
end

function Util.rand(a, b)
	return a + math.random() * (b - a)
end
function Util.clamp(v, a, b)
	if v < a then return a end
	if v > b then return b end
	return v
end
function Util.pick(arr)
	return arr[math.random(1, #arr)]
end
function Util.hypot(x, y)
	return math.sqrt(x * x + y * y)
end
function Util.dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end
function Util.lerpAngle(a, b, t)
	local d = b - a
	while d > math.pi do d -= math.pi * 2 end
	while d < -math.pi do d += math.pi * 2 end
	return a + d * t
end
function Util.round5(v)
	return math.max(5, math.floor(v / 5 + 0.5) * 5)
end
function Util.round(v)
	return math.floor(v + 0.5)
end

-- цвета: строки '#rrggbb', как в JS
function Util.hexToRgb(h)
	local n = tonumber(string.sub(h, 2), 16) or 0
	return n // 65536, (n // 256) % 256, n % 256
end
function Util.rgbToHex(r, g, b)
	local function c(v)
		return math.clamp(math.floor(v + 0.5), 0, 255)
	end
	return string.format("#%02x%02x%02x", c(r), c(g), c(b))
end
function Util.mix(a, b, t)
	local ar, ag, ab = Util.hexToRgb(a)
	local br, bg, bb = Util.hexToRgb(b)
	return Util.rgbToHex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end
local colorCache = {}
function Util.color(hex)
	local c = colorCache[hex]
	if not c then
		local r, g, b = Util.hexToRgb(hex)
		c = Color3.fromRGB(r, g, b)
		colorCache[hex] = c
	end
	return c
end
function Util.hslHex(h, sat, l)
	local a = sat * math.min(l, 1 - l)
	local function f(n)
		local k = (n + h * 12) % 12
		return l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
	end
	return Util.rgbToHex(f(0) * 255, f(8) * 255, f(4) * 255)
end

-- склонение: 1 лошадь, 2 лошади, 5 лошадей
function Util.plural(n, one, few, many)
	local m10, m100 = n % 10, n % 100
	if m10 == 1 and m100 ~= 11 then return one end
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then return few end
	return many
end

-- таблицы
function Util.copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = Util.copy(v) end
	return r
end
function Util.assign(dst, ...)
	for i = 1, select("#", ...) do
		local src = select(i, ...)
		if src then
			for k, v in pairs(src) do dst[k] = v end
		end
	end
	return dst
end
function Util.keys(t)
	local r = {}
	for k in pairs(t) do table.insert(r, k) end
	table.sort(r, function(a, b) return tostring(a) < tostring(b) end)
	return r
end
function Util.filter(arr, fn)
	local r = {}
	for _, v in ipairs(arr) do
		if fn(v) then table.insert(r, v) end
	end
	return r
end
function Util.find(arr, fn)
	for i, v in ipairs(arr) do
		if fn(v) then return v, i end
	end
	return nil
end
function Util.count(arr, fn)
	local n = 0
	for _, v in ipairs(arr) do
		if fn(v) then n += 1 end
	end
	return n
end
function Util.some(arr, fn)
	for _, v in ipairs(arr) do
		if fn(v) then return true end
	end
	return false
end
function Util.map(arr, fn)
	local r = {}
	for i, v in ipairs(arr) do r[i] = fn(v, i) end
	return r
end
function Util.removeValue(arr, value)
	for i = #arr, 1, -1 do
		if arr[i] == value then table.remove(arr, i) end
	end
end
function Util.removeIf(arr, fn)
	for i = #arr, 1, -1 do
		if fn(arr[i]) then table.remove(arr, i) end
	end
end
-- случайный ключ словаря (в стабильном порядке)
function Util.pickKey(t)
	return Util.pick(Util.keys(t))
end
-- взвешенный выбор: list = { {key, weight}, ... }
function Util.weighted(list)
	local total = 0
	for _, o in ipairs(list) do total += o[2] end
	local r = math.random() * total
	for _, o in ipairs(list) do
		r -= o[2]
		if r <= 0 then return o[1] end
	end
	return list[#list][1]
end

function Util.mmss(v)
	v = math.max(0, v)
	return string.format("%d:%02d", v // 60, math.floor(v % 60))
end

return Util
