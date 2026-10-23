--[[
	UnitService
	Owns the authoritative list of every unit in the match. Other systems look units
	up here; only UnitService creates or removes them.

	A unit is a Lua table (its "record", which is the truth) plus a Model in
	Workspace.Units that players see. Each model carries attributes so clients can
	recognise it: UnitId, OwnerUserId, UnitType, Slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UnitConfig = require(Shared.Config.UnitConfig)
local AssetRegistry = require(Shared.AssetRegistry)

export type Unit = {
	id: number,
	unitType: string,
	def: { [string]: any }, -- this unit type's entry in UnitConfig
	ownerUserId: number,
	slot: number,
	model: Model,
	root: BasePart,
	position: Vector3, -- feet, on the ground
	facing: Vector3, -- flat direction the unit faces
	squadId: number?, -- reserved for squads (Milestone 2)
	orderId: number, -- goes up with every new order, so stale path results can be ignored
	alive: boolean,
	path: { Vector3 }?, -- managed by MovementSystem
	waypointIndex: number, -- managed by MovementSystem
}

local UnitService = {}

local units: { [number]: Unit } = {}
local lastId = 0
local removedListeners: { (Unit) -> () } = {}
local unitsFolder: Folder

function UnitService.init()
	unitsFolder = Instance.new("Folder")
	unitsFolder.Name = "Units"
	unitsFolder.Parent = workspace
end

local function flatDirection(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Creates a unit standing at `position` (on the ground) facing `facing`.
function UnitService.spawnUnit(
	ownerUserId: number,
	slot: number,
	unitType: string,
	position: Vector3,
	facing: Vector3,
	teamColor: Color3
): Unit
	local def = UnitConfig[unitType]
	assert(def, "Unknown unit type: " .. tostring(unitType))

	lastId += 1
	local id = lastId
	local direction = flatDirection(facing)

	local model = AssetRegistry.createUnitModel(unitType, def, teamColor)
	model.Name = unitType .. "_" .. id
	model:SetAttribute("UnitId", id)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("UnitType", unitType)
	model:SetAttribute("Slot", slot)
	model:PivotTo(CFrame.lookAt(position, position + direction))
	model.Parent = unitsFolder

	local unit: Unit = {
		id = id,
		unitType = unitType,
		def = def,
		ownerUserId = ownerUserId,
		slot = slot,
		model = model,
		root = model.PrimaryPart :: BasePart,
		position = position,
		facing = direction,
		squadId = nil,
		orderId = 0,
		alive = true,
		path = nil,
		waypointIndex = 0,
	}
	units[id] = unit
	return unit
end

function UnitService.removeUnit(id: number)
	local unit = units[id]
	if not unit then
		return
	end
	units[id] = nil
	unit.alive = false
	for _, listener in removedListeners do
		listener(unit)
	end
	unit.model:Destroy()
end

function UnitService.removeAllOwnedBy(userId: number)
	for id, unit in units do
		if unit.ownerUserId == userId then
			UnitService.removeUnit(id)
		end
	end
end

function UnitService.get(id: number): Unit?
	return units[id]
end

-- All units by id. Treat the returned table as read-only.
function UnitService.getAll(): { [number]: Unit }
	return units
end

function UnitService.getOwnedBy(userId: number): { Unit }
	local owned = {}
	for _, unit in units do
		if unit.ownerUserId == userId then
			table.insert(owned, unit)
		end
	end
	return owned
end

-- `listener(unit)` runs just before a unit's model is destroyed.
function UnitService.onUnitRemoved(listener: (Unit) -> ())
	table.insert(removedListeners, listener)
end

return UnitService
