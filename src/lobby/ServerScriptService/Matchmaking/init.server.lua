--!strict
-- Serwer matchmakingu w lobby.
-- Gracz wchodzi na pusty pad -> okno "Create Party" (tryb + rozmiar) -> CREATE.
-- Inni wchodzą na pad, żeby dołączyć. Po odliczaniu cała party leci na prywatny serwer gry.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Tworzy leaderstats.Wins z DataStore (z nich Config.GetWins czyta odblokowane tryby).
require(ServerScriptService:WaitForChild("PlayerStats"))
local Config = require(ReplicatedStorage:WaitForChild("MatchmakingConfig"))
local Pad = require(script.Pad)
local Teleporter = require(script.Teleporter)

type Pad = Pad.Pad

local POLL_INTERVAL = 0.2

-- Remotes -------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "MatchmakingRemotes"

local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end

local OpenCreate = remote("OpenCreate") -- S->C (padId, padInfo)
local CloseCreate = remote("CloseCreate") -- S->C ()
local PartyUpdate = remote("PartyUpdate") -- S->C (partyInfo | nil)
local Notify = remote("Notify") -- S->C (message)
local CreateParty = remote("CreateParty") -- C->S (padId, modeId, size)
local CancelCreate = remote("CancelCreate") -- C->S (padId)
local LeaveParty = remote("LeaveParty") -- C->S ()
remotes.Parent = ReplicatedStorage

-- Stan ----------------------------------------------------------------------

local pads: { Pad } = {}
local padsById: { [string]: Pad } = {}
local playerPad: { [Player]: Pad } = {}
local cooldownUntil: { [Player]: number } = {}
local teleporting: { [Player]: { Since: number, Pad: Pad } } = {}
local lastBroadcast: { [Pad]: number } = {}

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character.PrimaryPart
end

local function partyInfo(pad: Pad)
	local mode = pad.ModeId and Config.GetMode(pad.ModeId)
	return {
		PadId = pad.Id,
		MapName = pad.MapName,
		ModeName = if mode then mode.DisplayName else "",
		Count = #pad.Members,
		Size = pad.Size,
		TimeLeft = pad:TimeLeft(),
		Status = pad.State,
	}
end

local function broadcast(pad: Pad)
	pad:Refresh()
	lastBroadcast[pad] = pad:TimeLeft()
	local info = partyInfo(pad)
	for _, member in pad.Members do
		PartyUpdate:FireClient(member, info)
	end
end

local function reject(player: Player, pad: Pad, message: string)
	Notify:FireClient(player, message)
	pad:PushOut(player.Character)
	cooldownUntil[player] = os.clock() + Config.ReentryCooldown
end

-- Usuwa gracza z padu, na którym stoi (wyjście ze strefy, BACK, LEAVE, śmierć, wyjście z gry).
local function removeFromPad(player: Player, pushOut: boolean)
	local pad = playerPad[player]
	if not pad then
		return
	end
	playerPad[player] = nil
	cooldownUntil[player] = os.clock() + Config.ReentryCooldown
	if pushOut then
		pad:PushOut(player.Character)
	end

	if pad.State == "Creating" and pad.Owner == player then
		CloseCreate:FireClient(player)
		pad:Reset()
	elseif pad.State == "Waiting" then
		local index = table.find(pad.Members, player)
		if index then
			table.remove(pad.Members, index)
		end
		PartyUpdate:FireClient(player, nil)
		if #pad.Members == 0 then
			pad:Reset()
		else
			broadcast(pad)
		end
	end
end

local function releaseTeleporting(player: Player, message: string)
	local entry = teleporting[player]
	if not entry then
		return
	end
	teleporting[player] = nil
	Teleporter.Cancel(player)
	cooldownUntil[player] = os.clock() + Config.ReentryCooldown
	if player.Parent == Players then
		entry.Pad:PushOut(player.Character)
		PartyUpdate:FireClient(player, nil)
		Notify:FireClient(player, message)
	end
end

Teleporter.OnPlayerFailed = releaseTeleporting

local function startTeleport(pad: Pad)
	pad.State = "Teleporting"
	local members = table.clone(pad.Members)
	local now = os.clock()
	for _, member in members do
		playerPad[member] = nil
		teleporting[member] = { Since = now, Pad = pad }
	end
	broadcast(pad)

	local playerIds = {}
	for _, member in members do
		table.insert(playerIds, member.UserId)
	end
	local matchData = {
		MatchId = HttpService:GenerateGUID(false),
		Mode = pad.ModeId,
		MapName = pad.MapName,
		PartySize = pad.Size,
		PlayerIds = playerIds,
		LobbyPlaceId = game.PlaceId,
		CreatedAt = os.time(),
	}

	task.spawn(function()
		local ok, message = Teleporter.TeleportParty(members, pad.PlaceId, matchData)
		if not ok then
			warn("[Matchmaking]", message)
			for _, member in members do
				releaseTeleporting(member, message or "Teleport failed.")
			end
		else
			-- Gracze są oznaczeni jako teleportowani, więc nie odpalą padu ponownie.
			task.wait(3)
		end
		pad:Reset()
	end)
end

local function onEnter(player: Player, pad: Pad)
	if pad.State == "Idle" then
		pad.State = "Creating"
		pad.Owner = player
		pad.Deadline = os.clock() + Config.CreateTimeout
		playerPad[player] = pad
		pad:Refresh()
		OpenCreate:FireClient(player, pad.Id, {
			MapName = pad.MapName,
			MapImage = pad.MapImage,
			MaxPlayers = pad.MaxPlayers,
		})
	elseif pad.State == "Creating" then
		reject(player, pad, "Someone is creating a party here.")
	elseif pad.State == "Waiting" then
		local mode = pad.ModeId and Config.GetMode(pad.ModeId)
		if #pad.Members >= pad.Size then
			reject(player, pad, "This party is full.")
		elseif mode and not Config.IsModeUnlocked(player, mode) then
			reject(player, pad, `You need {Config.FormatRequirement(mode)} to play {mode.DisplayName}.`)
		else
			table.insert(pad.Members, player)
			playerPad[player] = pad
			if #pad.Members >= pad.Size then
				pad.Deadline = math.min(pad.Deadline, os.clock() + Config.FullCountdown)
			end
			broadcast(pad)
		end
	else
		reject(player, pad, "This party is already starting.")
	end
end

-- Remote handlers -----------------------------------------------------------

CreateParty.OnServerEvent:Connect(function(player, padId, modeId, size)
	if typeof(padId) ~= "string" or typeof(modeId) ~= "string" or typeof(size) ~= "number" then
		return
	end
	local pad = padsById[padId]
	if not pad or pad.State ~= "Creating" or pad.Owner ~= player or playerPad[player] ~= pad then
		return
	end
	local mode = Config.GetMode(modeId)
	if not mode then
		return
	end
	if not Config.IsModeUnlocked(player, mode) then
		Notify:FireClient(player, `You need {Config.FormatRequirement(mode)} to play {mode.DisplayName}.`)
		return
	end
	if size ~= size or size % 1 ~= 0 or size < 1 or size > pad.MaxPlayers then
		return
	end

	pad.State = "Waiting"
	pad.Owner = nil
	pad.ModeId = mode.Id
	pad.Size = size
	pad.Members = { player }
	pad.Deadline = os.clock() + if size == 1 then Config.FullCountdown else Config.LobbyCountdown
	broadcast(pad)
end)

CancelCreate.OnServerEvent:Connect(function(player, padId)
	local pad = playerPad[player]
	if pad and pad.Id == padId and pad.State == "Creating" and pad.Owner == player then
		removeFromPad(player, true)
	end
end)

LeaveParty.OnServerEvent:Connect(function(player)
	local pad = playerPad[player]
	if pad and pad.State == "Waiting" then
		removeFromPad(player, true)
	end
end)

-- Pady ----------------------------------------------------------------------

local function isInsideRegisteredPad(model: Model): boolean
	for _, pad in pads do
		if model:IsDescendantOf(pad.Model) then
			return true
		end
	end
	return false
end

local function tryRegister(instance: Instance)
	if not instance:IsA("Model") or not string.find(string.lower(instance.Name), Config.ModelNamePattern) then
		return
	end
	if isInsideRegisteredPad(instance) then
		return
	end
	for _, pad in pads do
		if pad.Model == instance then
			return
		end
	end

	local id = `Pad{#pads + 1}`
	local pad = Pad.new(instance, id)
	if not pad then
		warn(`[Matchmaking] {instance:GetFullName()} has no BasePart to use as a pad, skipping.`)
		return
	end
	table.insert(pads, pad)
	padsById[id] = pad
	print(`[Matchmaking] Registered {instance:GetFullName()} (zone: {pad.Part.Name}, max {pad.MaxPlayers}).`)
end

for _, instance in Workspace:GetDescendants() do
	tryRegister(instance)
end
Workspace.DescendantAdded:Connect(tryRegister)

if #pads == 0 then
	warn("[Matchmaking] No Matchmaking models found in Workspace.")
end

-- Pętla: wykrywanie wejścia/wyjścia ze strefy i odliczanie ---------------------

Players.PlayerRemoving:Connect(function(player)
	removeFromPad(player, false)
	cooldownUntil[player] = nil
	teleporting[player] = nil
end)

while true do
	task.wait(POLL_INTERVAL)
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		local entry = teleporting[player]
		if entry then
			if now - entry.Since > Config.TeleportTimeout then
				releaseTeleporting(player, "Teleport timed out. Try again.")
			end
			continue
		end

		local root = rootPart(player)
		local current = playerPad[player]
		if current then
			if not root or not current:Contains(root.Position) then
				removeFromPad(player, false)
			end
		elseif root and (cooldownUntil[player] or 0) <= now then
			for _, pad in pads do
				if pad:Contains(root.Position) then
					onEnter(player, pad)
					break
				end
			end
		end
	end

	for _, pad in pads do
		if pad.State == "Creating" and now >= pad.Deadline then
			local owner = pad.Owner
			if owner then
				Notify:FireClient(owner, "Party creation timed out.")
				removeFromPad(owner, true)
			else
				pad:Reset()
			end
		elseif pad.State == "Waiting" then
			if now >= pad.Deadline then
				startTeleport(pad)
			elseif lastBroadcast[pad] ~= pad:TimeLeft() then
				broadcast(pad)
			end
		end
	end
end
