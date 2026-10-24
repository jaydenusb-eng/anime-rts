--[[
	TeamController
	The HUD's team buttons ask the server to put you on that team. The client only asks:
	MatchService checks the slot is free, swaps your army, and sets your "Slot" attribute,
	which highlights the chosen button here and moves the camera to your new base
	(CameraController). If the team is taken, the reason arrives as a HUD message.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Client = script.Parent.Parent
local Hud = require(Client.UI.Hud)

local TeamController = {}

function TeamController.start()
	local localPlayer = Players.LocalPlayer
	local chooseRemote = Net.getRemote(Net.Remotes.ChooseTeam)

	Hud.bindTeamButtons(function(slot)
		if localPlayer:GetAttribute("Slot") ~= slot then
			chooseRemote:FireServer(slot)
		end
	end)

	local function refresh()
		Hud.setCurrentTeam(localPlayer:GetAttribute("Slot"))
	end
	localPlayer:GetAttributeChangedSignal("Slot"):Connect(refresh)
	refresh()
end

return TeamController
