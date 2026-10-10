--!strict
-- Jeden pad matchmakingu (model Matchmaking1..4): strefa, stan party i billboard "0/4".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MatchmakingConfig"))

export type State = "Idle" | "Creating" | "Waiting" | "Teleporting"

local Pad = {}
Pad.__index = Pad

export type Pad = typeof(setmetatable(
	{} :: {
		Id: string,
		Model: Model,
		Part: BasePart,
		MapName: string,
		MapImage: string,
		MaxPlayers: number,
		PlaceId: number,
		State: State,
		Owner: Player?,
		Members: { Player },
		ModeId: string?,
		Size: number,
		Deadline: number,
		_countLabel: TextLabel,
		_statusLabel: TextLabel,
	},
	Pad
))

local function worldExtents(part: BasePart): Vector3
	local cf, size = part.CFrame, part.Size
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return Vector3.new(
		math.abs(x.X) * size.X + math.abs(y.X) * size.Y + math.abs(z.X) * size.Z,
		math.abs(x.Y) * size.X + math.abs(y.Y) * size.Y + math.abs(z.Y) * size.Z,
		math.abs(x.Z) * size.X + math.abs(y.Z) * size.Y + math.abs(z.Z) * size.Z
	)
end

local function findZonePart(model: Model): BasePart?
	local named: { [string]: boolean } = {}
	for _, name in Config.PadPartNames do
		named[name] = true
	end

	local flattest: BasePart? = nil
	local flattestArea = 0
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant:GetAttribute("MatchmakingPad") == true or named[string.lower(descendant.Name)] then
			return descendant
		end
		local extents = worldExtents(descendant)
		local area = extents.X * extents.Z
		if extents.Y < math.min(extents.X, extents.Z) / 2 and area > flattestArea then
			flattest, flattestArea = descendant, area
		end
	end
	return model.PrimaryPart or flattest
end

local function attribute<T>(model: Model, name: string, kind: string, default: T): T
	local value = model:GetAttribute(name)
	if typeof(value) == kind then
		return (value :: any) :: T
	end
	return default
end

local function label(parent: Instance, name: string, font: Enum.Font, position: UDim2, size: UDim2): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Position = position
	text.Size = size
	text.Font = font
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Parent = parent
	return text
end

function Pad.new(model: Model, id: string): Pad?
	local part = findZonePart(model)
	if not part then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MatchmakingBillboard"
	billboard.Adornee = part
	billboard.Size = UDim2.fromScale(10, 3.6) -- w studach, skaluje się z odległością
	billboard.StudsOffsetWorldSpace = Vector3.new(0, worldExtents(part).Y / 2 + 4.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	local countLabel = label(billboard, "Count", Enum.Font.FredokaOne, UDim2.new(), UDim2.fromScale(1, 0.58))
	local statusLabel =
		label(billboard, "Status", Enum.Font.SpecialElite, UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.4))
	billboard.Parent = part

	local maxPlayers = math.clamp(math.floor(attribute(model, "MaxPlayers", "number", Config.MaxPartySize)), 1, 50)
	local self = setmetatable({
		Id = id,
		Model = model,
		Part = part,
		MapName = attribute(model, "MapName", "string", Config.MapName),
		MapImage = attribute(model, "MapImage", "string", Config.MapImage),
		MaxPlayers = maxPlayers,
		PlaceId = attribute(model, "PlaceId", "number", Config.GamePlaceId),
		State = "Idle" :: State,
		Owner = nil :: Player?,
		Members = {} :: { Player },
		ModeId = nil :: string?,
		Size = maxPlayers,
		Deadline = 0,
		_countLabel = countLabel,
		_statusLabel = statusLabel,
	}, Pad)
	self:Refresh()
	return self
end

-- Czy pozycja (HumanoidRootPart) stoi w kole padu.
function Pad.Contains(self: Pad, position: Vector3): boolean
	local extents = worldExtents(self.Part)
	local center = self.Part.Position
	local radius = math.min(extents.X, extents.Z) / 2
	local top = center.Y + extents.Y / 2
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	return offset.Magnitude <= radius and position.Y >= top - 3 and position.Y <= top + 10
end

-- Wypycha postać poza krawędź padu, żeby nie odpalała go ponownie.
function Pad.PushOut(self: Pad, character: Model?)
	if not character or not character.PrimaryPart then
		return
	end
	local extents = worldExtents(self.Part)
	local center = self.Part.Position
	local offset = character.PrimaryPart.Position - center
	local direction = Vector3.new(offset.X, 0, offset.Z)
	direction = if direction.Magnitude > 0.1 then direction.Unit else Vector3.xAxis
	local target = center
		+ direction * (math.max(extents.X, extents.Z) / 2 + 4)
		+ Vector3.yAxis * (extents.Y / 2 + 3)
	character:PivotTo(CFrame.lookAt(target, target + direction))
end

function Pad.TimeLeft(self: Pad): number
	return math.max(0, math.ceil(self.Deadline - os.clock()))
end

function Pad.Refresh(self: Pad)
	local mode = self.ModeId and Config.GetMode(self.ModeId)
	local modeName = if mode then mode.DisplayName else ""
	if self.State == "Idle" then
		self._countLabel.Text = `0/{self.MaxPlayers}`
		self._statusLabel.Text = "Touch to create a party"
	elseif self.State == "Creating" then
		self._countLabel.Text = `0/{self.MaxPlayers}`
		self._statusLabel.Text = `{if self.Owner then self.Owner.DisplayName else "Someone"} is creating a party...`
	elseif self.State == "Waiting" then
		self._countLabel.Text = `{#self.Members}/{self.Size}`
		self._statusLabel.Text = `{modeName} • Starting in {self:TimeLeft()}s`
	else
		self._countLabel.Text = `{#self.Members}/{self.Size}`
		self._statusLabel.Text = `{modeName} • Teleporting...`
	end
end

function Pad.Reset(self: Pad)
	self.State = "Idle"
	self.Owner = nil
	self.Members = {}
	self.ModeId = nil
	self.Size = self.MaxPlayers
	self.Deadline = 0
	self:Refresh()
end

return Pad
