--!strict
-- Teleport party do prywatnego (zarezerwowanego) serwera w miejscu gry.
-- Dane meczu trafiają do MemoryStore pod PrivateServerId, więc serwer gry może im ufać
-- (TeleportData idzie przez klienta i służy tylko jako zapas).

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("MatchmakingConfig"))

-- Ta sama nazwa musi być w skrypcie MatchLoader w miejscu gry.
local MATCHES_MAP = "MatchmakingMatches"
local MATCH_TTL = 60 * 60

type Pending = { PlaceId: number, Options: TeleportOptions, Attempts: number }

local Teleporter = {}

-- Wywoływane, gdy teleport gracza ostatecznie się nie powiódł (ustawiane przez skrypt główny).
Teleporter.OnPlayerFailed = function(_player: Player, _message: string) end

local matches = MemoryStoreService:GetSortedMap(MATCHES_MAP)
local pending: { [Player]: Pending } = {}

local function retry(attempts: number, callback: () -> ...any): (boolean, ...any)
	local lastError: any
	for attempt = 1, attempts do
		local result = table.pack(pcall(callback))
		if result[1] then
			return true, table.unpack(result, 2, result.n)
		end
		lastError = result[2]
		if attempt < attempts then
			task.wait(attempt * 2)
		end
	end
	return false, lastError
end

-- Zwraca true, gdy teleport został zainicjowany. Pojedyncze porażki graczy
-- przychodzą później przez Teleporter.OnPlayerFailed.
function Teleporter.TeleportParty(players: { Player }, placeId: number, matchData: { [string]: any }): (boolean, string?)
	if placeId == 0 then
		return false, "Game PlaceId is not set (MatchmakingConfig.GamePlaceId)."
	end
	if RunService:IsStudio() then
		return false, "Teleport works only in a published game, not in Studio."
	end

	local reserved, accessCode, privateServerId = retry(Config.TeleportRetries, function()
		return TeleportService:ReserveServer(placeId)
	end)
	if not reserved then
		warn("[Matchmaking] ReserveServer failed:", accessCode)
		return false, "Could not reserve a server. Try again."
	end

	local saved, saveError = pcall(function()
		matches:SetAsync(privateServerId, matchData, MATCH_TTL)
	end)
	if not saved then
		warn("[Matchmaking] Could not save match data, game server will fall back to TeleportData:", saveError)
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(matchData)

	local present = {}
	for _, player in players do
		if player.Parent == Players then
			table.insert(present, player)
			pending[player] = { PlaceId = placeId, Options = options, Attempts = 0 }
		end
	end
	if #present == 0 then
		return false, "Everyone left the party."
	end

	local teleported, teleportError = retry(Config.TeleportRetries, function()
		return TeleportService:TeleportAsync(placeId, present, options)
	end)
	if not teleported then
		for _, player in present do
			pending[player] = nil
		end
		warn("[Matchmaking] TeleportAsync failed:", teleportError)
		return false, "Teleport failed. Try again."
	end
	return true, nil
end

-- Zapomina oczekujący teleport (np. po przekroczeniu Config.TeleportTimeout).
function Teleporter.Cancel(player: Player)
	pending[player] = nil
end

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	local entry = pending[player]
	if not entry or result == Enum.TeleportResult.IsTeleporting then
		return
	end

	local retryable = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
	if retryable and entry.Attempts < Config.TeleportRetries then
		entry.Attempts += 1
		task.wait(entry.Attempts * 2)
		if pending[player] ~= entry or player.Parent ~= Players then
			return
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(entry.PlaceId, { player }, entry.Options)
		end)
		if ok then
			return
		end
		message = tostring(err)
	end

	pending[player] = nil
	warn(`[Matchmaking] Teleport of {player.Name} failed ({result.Name}): {message}`)
	Teleporter.OnPlayerFailed(player, "Teleport failed. Try again.")
end)

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

return Teleporter
