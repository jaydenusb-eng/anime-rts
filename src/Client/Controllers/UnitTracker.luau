--[[
	UnitTracker
	Keeps the client's list of unit models (the server creates them in Workspace.Units)
	and answers questions like "is this my unit?".

	Ownership on the client only decides what you can select. The server checks
	ownership again for every order, so changing this file can't let anyone command
	another player's units.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.UnitConfig)

local UnitTracker = {}

local localPlayer = Players.LocalPlayer
local units: { [Model]: boolean } = {}
local removedListeners: { (Model) -> () } = {}
local unitsFolder: Instance

function UnitTracker.start()
	unitsFolder = workspace:WaitForChild("Units")
	for _, model in unitsFolder:GetChildren() do
		units[model] = true
	end
	unitsFolder.ChildAdded:Connect(function(model)
		units[model] = true
	end)
	unitsFolder.ChildRemoved:Connect(function(model)
		units[model] = nil
		for _, listener in removedListeners do
			listener(model)
		end
	end)
end

function UnitTracker.getFolder(): Instance
	return unitsFolder
end

function UnitTracker.isOwn(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == localPlayer.UserId
end

-- Your own units that are currently in the world.
function UnitTracker.getOwnUnits(): { Model }
	local own = {}
	for model in units do
		if UnitTracker.isOwn(model) then
			table.insert(own, model)
		end
	end
	return own
end

-- The unit model that `part` belongs to, or nil if it isn't part of a unit.
function UnitTracker.getUnitFromPart(part: Instance?): Model?
	local current = part
	while current and current.Parent ~= unitsFolder do
		current = current.Parent
	end
	return current :: Model?
end

-- The middle of a unit's body in world space (used when picking units on screen).
function UnitTracker.getCenter(model: Model): Vector3?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local def = UnitConfig[model:GetAttribute("UnitType")]
	local height = if def then def.height else 4
	return root.Position + Vector3.new(0, height / 2, 0)
end

-- `listener(model)` runs when a unit leaves the world (removed, or its owner left).
function UnitTracker.onRemoved(listener: (Model) -> ())
	table.insert(removedListeners, listener)
end

return UnitTracker
