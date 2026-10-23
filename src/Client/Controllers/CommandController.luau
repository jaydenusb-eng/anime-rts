--[[
	CommandController
	Right-click turns your selection into an order:
	  right-click the ground -> Move there.
	(Later milestones: right-click an enemy -> Attack; attack-move, stop, rally points.)

	The client only asks. The server decides what really happens, and replies through
	the CommandFeedback remote when something goes wrong ("Can't reach that location.").
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MapInfo = require(Shared.MapInfo)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local InputGuard = require(script.Parent.InputGuard)
local SelectionController = require(script.Parent.SelectionController)
local Hud = require(Client.UI.Hud)
local ClickMarker = require(Client.Visuals.ClickMarker)

local CommandController = {}

local camera = workspace.CurrentCamera
local commandRemote: RemoteEvent
local worldRayParams = RaycastParams.new()
worldRayParams.FilterType = Enum.RaycastFilterType.Include

-- The point on the map under the mouse (ground or obstacle; units are ignored).
local function getWorldPoint(screenPoint: Vector2): Vector3?
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 3000, worldRayParams)
	if hit then
		return hit.Position
	end
	-- Pointing past the edge of the world: use where the ray crosses ground level.
	if ray.Direction.Y < -1e-3 then
		local groundY = MapInfo.getPlayArea().Y
		return ray.Origin + ray.Direction * ((groundY - ray.Origin.Y) / ray.Direction.Y)
	end
	return nil
end

local function issueMove(screenPoint: Vector2)
	local ids = SelectionController.getSelectedIds()
	if #ids == 0 then
		return
	end
	local limit = GameConfig.Commands.MaxUnitsPerCommand
	if #ids > limit then
		ids = table.move(ids, 1, limit, 1, {})
		Hud.showMessage(string.format("Only %d units can take one order; the rest stay put.", limit))
	end
	local target = getWorldPoint(screenPoint)
	if not target then
		return
	end
	commandRemote:FireServer({ kind = Net.CommandKind.Move, unitIds = ids, target = target })
	ClickMarker.play(target)
end

function CommandController.start()
	commandRemote = Net.getRemote(Net.Remotes.UnitCommand)
	worldRayParams.FilterDescendantsInstances = { MapInfo.waitForMap() }

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and InputGuard.worldMayUse(gameProcessed) then
			issueMove(UserInputService:GetMouseLocation())
		end
	end)

	Net.getRemote(Net.Remotes.CommandFeedback).OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.message) == "string" then
			Hud.showMessage(data.message)
		end
	end)
end

return CommandController
