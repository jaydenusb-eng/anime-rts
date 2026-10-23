--[[
	DevBridge (Studio only)
	A BindableFunction at ServerStorage.DevBridge that lets testers (and Claude, through
	the Studio MCP) look at and poke the running server during a playtest. It is never
	created in a live game, because RunService:IsStudio() is false there.

	Example, in the Studio command bar during a playtest (switch the bar to "Server"):
	  print(game.ServerStorage.DevBridge:Invoke("listUnits"))
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local UnitConfig = require(Shared.Config.UnitConfig)
local Formation = require(Shared.Formation)

local UnitService = require(script.Parent.UnitService)
local MovementSystem = require(script.Parent.MovementSystem)
local NavigationService = require(script.Parent.NavigationService)
local CommandService = require(script.Parent.CommandService)
local MatchService = require(script.Parent.MatchService)

local DevBridge = {}

local actions = {}

-- Every unit with its owner, position and whether it is walking.
function actions.listUnits()
	local list = {}
	for id, unit in UnitService.getAll() do
		table.insert(list, {
			id = id,
			owner = unit.ownerUserId,
			unitType = unit.unitType,
			position = unit.position,
			moving = MovementSystem.isMoving(unit),
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

function actions.getStats()
	local count = 0
	for _ in UnitService.getAll() do
		count += 1
	end
	return {
		units = count,
		movement = MovementSystem.getStats(),
		navigation = NavigationService.getStats(),
		commands = CommandService.getStats(),
		slots = MatchService.getSlotOwners(),
	}
end

function actions.resetStats()
	MovementSystem.resetStats()
	NavigationService.resetStats()
	CommandService.resetStats()
end

-- Spawns `count` units of `unitType` around `center`, owned by `ownerUserId`. Use an
-- owner id no player has (like 0) to make units nobody controls, for ownership tests.
function actions.spawnUnits(ownerUserId: number, unitType: string, count: number, center: Vector3, slot: number?)
	local def = UnitConfig[unitType]
	assert(def, "Unknown unit type: " .. tostring(unitType))
	local color = (GameConfig.Slots[slot or 0] or { color = Color3.fromRGB(200, 200, 200) }).color
	local spacing = def.radius * 2 + GameConfig.Movement.FormationGap
	local slots = Formation.pickSlots(center, count, spacing, Vector3.new(0, 0, -1), function(point)
		return NavigationService.resolveStandPoint(point, def.radius, def.height)
	end)
	local ids = {}
	for index = 1, count do
		local unit = UnitService.spawnUnit(ownerUserId, slot or 0, unitType, slots[index].position, Vector3.new(0, 0, -1), color)
		table.insert(ids, unit.id)
	end
	return ids
end

function actions.removeUnitsOwnedBy(ownerUserId: number)
	UnitService.removeAllOwnedBy(ownerUserId)
end

-- Orders units directly, skipping the RemoteEvent and its checks. For benchmarks only.
function actions.moveUnits(ids: { number }, target: Vector3)
	local units = {}
	for _, id in ids do
		local unit = UnitService.get(id)
		if unit then
			table.insert(units, unit)
		end
	end
	NavigationService.moveGroup(units, target)
	return #units
end

function DevBridge.start()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DevBridge"
	bindable.OnInvoke = function(action: string, ...)
		local handler = actions[action]
		assert(handler, "Unknown DevBridge action: " .. tostring(action))
		return handler(...)
	end
	bindable.Parent = ServerStorage
end

return DevBridge
