--[[
	Приглушает всё, что светится в темноте: неоновые детали (кристаллы, светящиеся грибы,
	узоры лошадей, портал, фонари) и источники света (PointLight, SpotLight, SurfaceLight).
	Работает на клиенте для всего мира сразу, в том числе для того, что появится позже.
	Насколько приглушать — настройки ниже.
]]
local Glow = {}

local NEON_DARKEN = 0.4   -- неон: цвет темнее на 40% (у неона яркость свечения зависит от цвета)
local LIGHT_BRIGHT = 0.5  -- источники света: яркость ×0.5
local LIGHT_RANGE = 0.8   -- и дальность ×0.8

local BLACK = Color3.new(0, 0, 0)
local DONE = "GlowDimmed" -- метка, чтобы не приглушать дважды (модели снимают и возвращают в мир)

-- светящиеся грибы (атрибут Glow12) светят на 12% ярче остального
local BOOST = 1.12
local function dimPart(p)
	if p:GetAttribute(DONE) then return end
	-- фонари на столбах становятся неоновыми только ночью — их лампочки приглушаем сразу
	if p.Material ~= Enum.Material.Neon and p.Name ~= "LampBulb" then return end
	p:SetAttribute(DONE, true)
	local k = NEON_DARKEN
	if p:GetAttribute("Glow12") then k = 1 - (1 - NEON_DARKEN) * BOOST end
	p.Color = p.Color:Lerp(BLACK, k)
end

local function dimLight(l)
	if l:GetAttribute(DONE) then return end
	l:SetAttribute(DONE, true)
	local b = l:GetAttribute("Glow12") and BOOST or 1
	l.Brightness *= LIGHT_BRIGHT * b
	l.Range *= LIGHT_RANGE * b
end

local function handle(d)
	if d:IsA("BasePart") then
		-- цвет часто ставят сразу после того, как деталь попала в мир — приглушаем чуть позже
		if d.Material == Enum.Material.Neon or d.Name == "LampBulb" then task.defer(dimPart, d) end
	elseif d:IsA("Light") then
		task.defer(dimLight, d)
	end
end

function Glow.init()
	for _, d in ipairs(workspace:GetDescendants()) do handle(d) end
	workspace.DescendantAdded:Connect(handle)
end

return Glow
