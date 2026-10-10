--!strict
-- Skrypt dla MIEJSCA GRY (nie lobby). Odczytuje dane meczu wysłane przez matchmaking:
-- tryb, mapę i listę graczy. Ustawia je jako atrybuty, żeby reszta gry mogła z nich korzystać:
--   Workspace:GetAttribute("MatchMode")      -> "Normal" / "Hard"
--   Workspace:GetAttribute("MatchMap")       -> "FARMHOUSE"
--   Workspace:GetAttribute("MatchPartySize") -> 1..4
--   Workspace:GetAttribute("MatchVerified")  -> true, gdy dane pochodzą z MemoryStore (zaufane)
--   Workspace:GetAttribute("MatchReady")     -> true, gdy dane zostały wczytane
-- Powrót do lobby: ServerStorage.ReturnToLobby:Fire({ gracze }) lub :Fire() dla wszystkich.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

-- Musi być takie samo jak w Teleporter.lua w lobby.
local MATCHES_MAP = "MatchmakingMatches"
-- Używane, gdy dane meczu nie zawierają LobbyPlaceId (np. test w Studio).
local FALLBACK_LOBBY_PLACE_ID = 0

local match: { [string]: any }? = nil

local function apply(data: { [string]: any }, verified: boolean)
	if match then
		return
	end
	match = data
	Workspace:SetAttribute("MatchMode", data.Mode)
	Workspace:SetAttribute("MatchMap", data.MapName)
	Workspace:SetAttribute("MatchPartySize", data.PartySize)
	Workspace:SetAttribute("MatchVerified", verified)
	Workspace:SetAttribute("MatchReady", true)
	print(`[Match] Mode={data.Mode} Map={data.MapName} PartySize={data.PartySize} Verified={verified}`)
end

local function loadFromMemoryStore()
	if game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0 then
		return -- to nie jest serwer zarezerwowany przez matchmaking
	end
	local map = MemoryStoreService:GetSortedMap(MATCHES_MAP)
	for _ = 1, 5 do
		local ok, data = pcall(function()
			return map:GetAsync(game.PrivateServerId)
		end)
		if ok and typeof(data) == "table" then
			apply(data, true)
			return
		end
		task.wait(1)
	end
	warn("[Match] No match data in MemoryStore, waiting for TeleportData.")
end

-- Zapas: TeleportData przychodzi przez klienta, więc nie jest zaufane (MatchVerified = false).
local function onPlayerAdded(player: Player)
	local teleportData = player:GetJoinData().TeleportData :: any
	if typeof(teleportData) == "table" and teleportData.Mode then
		task.delay(10, function()
			apply(teleportData, false)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
task.spawn(loadFromMemoryStore)

local returnToLobby = Instance.new("BindableEvent")
returnToLobby.Name = "ReturnToLobby"
returnToLobby.Parent = ServerStorage

returnToLobby.Event:Connect(function(players: { Player }?)
	local lobbyPlaceId = if match and typeof(match.LobbyPlaceId) == "number"
		then match.LobbyPlaceId
		else FALLBACK_LOBBY_PLACE_ID
	if lobbyPlaceId == 0 then
		warn("[Match] Lobby PlaceId unknown, set FALLBACK_LOBBY_PLACE_ID.")
		return
	end
	local targets = players or Players:GetPlayers()
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(lobbyPlaceId, targets)
	end)
	if not ok then
		warn("[Match] Return to lobby failed:", err)
	end
end)
