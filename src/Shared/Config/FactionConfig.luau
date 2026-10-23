--[[
	FactionConfig
	Placeholder factions. When the team picks anime franchises, rename these entries
	and point them at the new unit ids in UnitConfig. Code only ever refers to a
	faction by its id ("FactionA"), so renaming the display name is always safe.

	Later milestones add: leaders, passive bonuses, building rosters, tech trees.
]]

return {
	FactionA = {
		displayName = "Faction A",
		-- The army each player of this faction starts with (Milestone 1 test army).
		startingArmy = {
			{ unitType = "FA_Trooper", count = 5 },
		},
	},
	FactionB = {
		displayName = "Faction B",
		startingArmy = {
			{ unitType = "FB_Trooper", count = 5 },
		},
	},
}
