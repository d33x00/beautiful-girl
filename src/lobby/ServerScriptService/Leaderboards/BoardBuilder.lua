--!strict
-- Zamienia znacznik (biały model "Leaderboard") na drewnianą tablicę w stylu farmy:
-- dwa słupy, deska z topką, belki, czerwony daszek i dynie u podstawy. Znacznik jest usuwany.
-- Tablica ma szerokość i wysokość znacznika, stoi na jego spodzie i jest obrócona wzdłuż
-- jego dłuższego boku.

local BoardBuilder = {}

-- Kolory: zmień tutaj, żeby dopasować tablicę do mostu / reszty mapy.
local POST = Color3.fromRGB(92, 62, 40)
local PLANKS = Color3.fromRGB(125, 84, 52)
local BEAM = Color3.fromRGB(70, 45, 28)
local ROOF = Color3.fromRGB(156, 48, 42)
local TRIM = Color3.fromRGB(246, 238, 222)
local PUMPKIN = Color3.fromRGB(235, 128, 30)
local STEM = Color3.fromRGB(76, 110, 40)

local MIN_WIDTH, MAX_WIDTH = 8, 30
local MIN_HEIGHT, MAX_HEIGHT = 9, 30
local ROOF_ANGLE = math.rad(32)

local function part(model: Model, props: { [string]: any }): Part
	local newPart = Instance.new("Part")
	newPart.Anchored = true
	newPart.Material = Enum.Material.Wood
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(newPart :: any)[key] = value
	end
	newPart.Parent = model
	return newPart
end

function BoardBuilder.IsBuilt(model: Model): boolean
	return model:GetAttribute("LeaderboardBuilt") == true
end

-- Buduje tablicę w miejscu znacznika. Zwraca nowy model bez rodzica (parentuje wywołujący).
function BoardBuilder.Build(marker: Model): Model
	local boxCFrame, boxSize = marker:GetBoundingBox()

	-- Oś wzdłuż tablicy = dłuższy poziomy bok znacznika.
	local along = if boxSize.X >= boxSize.Z then boxCFrame.RightVector else boxCFrame.LookVector
	along = Vector3.new(along.X, 0, along.Z)
	along = if along.Magnitude > 0.01 then along.Unit else Vector3.xAxis
	local ground = boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0)
	local base = CFrame.fromMatrix(ground, along, Vector3.yAxis)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	local width = math.clamp(math.max(boxSize.X, boxSize.Z), MIN_WIDTH, MAX_WIDTH)
	local height = math.clamp(boxSize.Y, MIN_HEIGHT, MAX_HEIGHT)
	local boardBottom, boardTop = height * 0.12, height * 0.84

	local model = Instance.new("Model")
	model.Name = marker.Name
	for name, value in marker:GetAttributes() do
		model:SetAttribute(name, value)
	end
	model:SetAttribute("LeaderboardBuilt", true)

	-- Słupy
	for _, side in { -1, 1 } do
		part(model, {
			Name = "Post",
			Size = Vector3.new(0.9, height * 0.95, 0.9),
			CFrame = at(side * width / 2, height * 0.475, 0),
			Color = POST,
		})
	end

	-- Deska z topką (na niej jest SurfaceGui)
	local board = part(model, {
		Name = "Board",
		Size = Vector3.new(width - 0.9, boardTop - boardBottom, 0.35),
		CFrame = at(0, (boardBottom + boardTop) / 2, 0),
		Color = PLANKS,
		Material = Enum.Material.WoodPlanks,
	})

	-- Belki nad i pod deską
	part(model, {
		Name = "TopBeam",
		Size = Vector3.new(width + 0.9, 0.7, 0.8),
		CFrame = at(0, boardTop + 0.35, 0),
		Color = BEAM,
	})
	part(model, {
		Name = "BottomBeam",
		Size = Vector3.new(width + 0.9, 0.6, 0.8),
		CFrame = at(0, boardBottom - 0.3, 0),
		Color = BEAM,
	})

	-- Dwuspadowy daszek jak na stodole
	local roofDepth = 1.8
	local peak = boardTop + 0.7 + math.sin(ROOF_ANGLE) * roofDepth
	for _, side in { -1, 1 } do
		part(model, {
			Name = "Roof",
			Size = Vector3.new(width + 2.2, 0.35, roofDepth),
			CFrame = at(0, peak, 0)
				* CFrame.Angles(side * ROOF_ANGLE, 0, 0)
				* CFrame.new(0, 0, side * roofDepth / 2),
			Color = ROOF,
			Material = Enum.Material.WoodPlanks,
		})
	end
	part(model, {
		Name = "RoofRidge",
		Size = Vector3.new(width + 2.4, 0.35, 0.35),
		CFrame = at(0, peak + 0.15, 0),
		Color = TRIM,
	})

	-- Dynie u podstawy
	for _, pumpkin in { { x = -1, size = 1.8 }, { x = 1, size = 1.3 } } do
		local position = at(pumpkin.x * (width / 2 + 1.3), pumpkin.size * 0.42, -0.6)
		part(model, {
			Name = "Pumpkin",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(pumpkin.size, pumpkin.size * 0.85, pumpkin.size),
			CFrame = position,
			Color = PUMPKIN,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		part(model, {
			Name = "Stem",
			Size = Vector3.new(0.2, 0.45, 0.2),
			CFrame = position * CFrame.new(0, pumpkin.size * 0.45, 0),
			Color = STEM,
			CanCollide = false,
		})
	end

	model.PrimaryPart = board
	marker:Destroy()
	return model
end

return BoardBuilder
