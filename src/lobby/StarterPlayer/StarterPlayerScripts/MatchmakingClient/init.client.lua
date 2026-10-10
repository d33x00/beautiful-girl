--!strict
-- Klient matchmakingu: reaguje na zdarzenia serwera i obsługuje okno "Create Party".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MatchmakingConfig"))
local MatchmakingUI = require(script:WaitForChild("MatchmakingUI"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("MatchmakingRemotes")
local OpenCreate = remotes:WaitForChild("OpenCreate") :: RemoteEvent
local CloseCreate = remotes:WaitForChild("CloseCreate") :: RemoteEvent
local PartyUpdate = remotes:WaitForChild("PartyUpdate") :: RemoteEvent
local Notify = remotes:WaitForChild("Notify") :: RemoteEvent
local CreateParty = remotes:WaitForChild("CreateParty") :: RemoteEvent
local CancelCreate = remotes:WaitForChild("CancelCreate") :: RemoteEvent
local LeaveParty = remotes:WaitForChild("LeaveParty") :: RemoteEvent

local view: MatchmakingUI.CreateView = {
	MapName = Config.MapName,
	MapImage = Config.MapImage,
	SelectedModeId = nil,
	Size = Config.DefaultPartySize,
	MaxPlayers = Config.MaxPartySize,
	Wins = 0,
}
local padId: string? = nil
local busy = false

local ui: MatchmakingUI.MatchmakingUI

local function setBusy(value: boolean)
	busy = value
	ui:SetCreateBusy(value)
end

ui = MatchmakingUI.new(player:WaitForChild("PlayerGui"), {
	OnModeClicked = function(mode)
		if not Config.IsModeUnlocked(player, mode) then
			ui:Toast(`Win {Config.FormatRequirement(mode)} to unlock {mode.DisplayName}.`)
			return
		end
		view.SelectedModeId = mode.Id
		ui:RenderCreate(view)
	end,
	OnSizeChanged = function(delta)
		view.Size = math.clamp(view.Size + delta, 1, view.MaxPlayers)
		ui:RenderCreate(view)
	end,
	OnCreate = function()
		if busy or not padId or not view.SelectedModeId then
			return
		end
		setBusy(true)
		CreateParty:FireServer(padId, view.SelectedModeId, view.Size)
		-- Jeśli serwer odrzuci prośbę, odblokuj przycisk.
		task.delay(2, function()
			if busy then
				setBusy(false)
			end
		end)
	end,
	OnBack = function()
		if padId then
			CancelCreate:FireServer(padId)
		end
		padId = nil
		ui:CloseCreate()
	end,
	OnLeave = function()
		LeaveParty:FireServer()
	end,
})

OpenCreate.OnClientEvent:Connect(function(id: string, info: { MapName: string, MapImage: string, MaxPlayers: number })
	padId = id
	view.MapName = info.MapName
	view.MapImage = info.MapImage
	view.MaxPlayers = info.MaxPlayers
	view.Size = math.clamp(Config.DefaultPartySize, 1, info.MaxPlayers)
	view.Wins = Config.GetWins(player)
	view.SelectedModeId = nil
	for _, mode in Config.Modes do
		if Config.IsModeUnlocked(player, mode) then
			view.SelectedModeId = mode.Id
			break
		end
	end
	setBusy(false)
	ui:OpenCreate(view)
end)

CloseCreate.OnClientEvent:Connect(function()
	padId = nil
	ui:CloseCreate()
end)

PartyUpdate.OnClientEvent:Connect(function(info: MatchmakingUI.PartyView?)
	if info then
		padId = nil
		setBusy(false)
		ui:CloseCreate()
		ui:ShowParty(info)
	else
		ui:HideParty()
	end
end)

Notify.OnClientEvent:Connect(function(message: string)
	setBusy(false)
	ui:Toast(message)
end)
