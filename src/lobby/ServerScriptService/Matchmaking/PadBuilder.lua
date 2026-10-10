--!strict
-- Zamienia znacznik (biały model "MatchmakingN") na gotowy pad: jasne koło z białą obwódką,
-- jak na screenie "0/4 Touch to create a party". Znacznik jest usuwany.

local PadBuilder = {}

local PAD_COLOR = Color3.fromRGB(226, 200, 164)
local RING_COLOR = Color3.fromRGB(250, 246, 238)
local MIN_DIAMETER = 8
local MAX_DIAMETER = 40

local function part(props: { [string]: any }): Part
	local newPart = Instance.new("Part")
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	newPart.Material = Enum.Material.SmoothPlastic
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(newPart :: any)[key] = value
	end
	return newPart
end

-- Czy model to gotowy pad (zbudowany przez ten moduł), a nie znacznik.
function PadBuilder.IsBuilt(model: Model): boolean
	return model:GetAttribute("MatchmakingBuilt") == true
end

-- Buduje pad w miejscu znacznika. Zwraca nowy model bez rodzica (parentuje wywołujący).
function PadBuilder.Build(marker: Model): Model
	local boxCFrame, boxSize = marker:GetBoundingBox()
	local ground = boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0)
	local diameter = math.clamp(math.min(boxSize.X, boxSize.Z), MIN_DIAMETER, MAX_DIAMETER)
	-- Cylinder w Roblox ma oś wzdłuż X, więc obracamy go "na płasko".
	local flat = CFrame.Angles(0, 0, math.rad(90))

	local model = Instance.new("Model")
	model.Name = marker.Name
	for name, value in marker:GetAttributes() do
		model:SetAttribute(name, value)
	end
	model:SetAttribute("MatchmakingBuilt", true)

	part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter + 0.8, diameter + 0.8),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * flat,
		Color = RING_COLOR,
		Parent = model,
	})
	local pad = part({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, diameter, diameter),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * flat,
		Color = PAD_COLOR,
		Transparency = 0.2,
		Parent = model,
	})
	model.PrimaryPart = pad

	marker:Destroy()
	return model
end

return PadBuilder
