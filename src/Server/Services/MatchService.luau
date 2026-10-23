--[[
	MatchService
	Seats players into the match and gives each one a starting army.
	Milestone 1 rules: the first two players get slots 1 and 2; anyone else watches.
	When a player leaves, their units are removed and their slot opens up again.
	(Milestone 8 replaces this with the full lobby -> match -> victory -> restart flow.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local FactionConfig = require(Shared.Config.FactionConfig)
local UnitConfig = require(Shared.Config.UnitConfig)
local Formation = require(Shared.Formation)
local MapInfo = require(Shared.MapInfo)
local UnitService = require(script.Parent.UnitService)
local NavigationService = require(script.Parent.NavigationService)

local MatchService = {}

local slotOwners: { [number]: number } = {} -- slot -> UserId

local function findFreeSlot(): number?
	for slot = 1, GameConfig.MaxPlayers do
		if slotOwners[slot] == nil then
			return slot
		end
	end
	return nil
end

local function spawnStartingArmy(player: Player, slot: number)
	local slotInfo = GameConfig.Slots[slot]
	local faction = FactionConfig[slotInfo.faction]
	local start = MapInfo.getStartCFrame(slot)
	if not start then
		warn(string.format("[MatchService] The map has no StartPoints.Slot%d marker, so %s gets no units.", slot, player.Name))
		return
	end

	local unitTypes = {}
	local radius, height = 0, 0
	for _, entry in faction.startingArmy do
		local def = UnitConfig[entry.unitType]
		radius = math.max(radius, def.radius)
		height = math.max(height, def.height)
		for _ = 1, entry.count do
			table.insert(unitTypes, entry.unitType)
		end
	end

	local spacing = radius * 2 + GameConfig.Movement.FormationGap + 1
	local slots = Formation.pickSlots(start.Position, #unitTypes, spacing, start.LookVector, function(point)
		return NavigationService.resolveStandPoint(point, radius, height)
	end)
	for index, unitType in unitTypes do
		UnitService.spawnUnit(player.UserId, slot, unitType, slots[index].position, start.LookVector, slotInfo.color)
	end
end

local function onPlayerAdded(player: Player)
	local slot = findFreeSlot()
	if not slot then
		player:SetAttribute("Slot", 0) -- no free slot: this player watches
		return
	end
	slotOwners[slot] = player.UserId
	player:SetAttribute("Slot", slot)
	player:SetAttribute("Faction", GameConfig.Slots[slot].faction)
	spawnStartingArmy(player, slot)
end

local function onPlayerRemoving(player: Player)
	for slot, userId in slotOwners do
		if userId == player.UserId then
			slotOwners[slot] = nil
		end
	end
	UnitService.removeAllOwnedBy(player.UserId)
end

-- Which player (UserId) holds each slot.
function MatchService.getSlotOwners(): { [number]: number }
	return table.clone(slotOwners)
end

function MatchService.start()
	if Players.CharacterAutoLoads then
		warn("[MatchService] Players.CharacterAutoLoads is on. Run tools/ApplyPlaceSettings.luau; turning it off for now.")
		Players.CharacterAutoLoads = false
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MatchService
