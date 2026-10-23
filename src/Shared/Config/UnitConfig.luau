--[[
	UnitConfig
	Every unit type, keyed by a stable id. Balance numbers belong here, never in code.

	Fields:
	  displayName  Name shown in the UI.
	  faction      Id from FactionConfig.
	  role         "Infantry" | "Armored" | "Air" | "Hero". The counter system (Milestone 3)
	               uses this to decide strengths and weaknesses.
	  moveSpeed    Studs per second.
	  radius       Footprint radius in studs. Drives formation spacing and path clearance.
	  height       Studs. Used for path clearance.
	  asset        Name of a Model in ReplicatedStorage.Assets.Units. If there is none,
	               AssetRegistry builds the placeholder described below instead.
	  placeholder  Look of the stand-in model: shape ("Block" or "Cylinder") and body size.
]]

return {
	FA_Trooper = {
		displayName = "Faction A Trooper",
		faction = "FactionA",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.5,
		height = 5,
		asset = "FA_Trooper",
		placeholder = { shape = "Block", bodySize = Vector3.new(2.2, 3.6, 1.6) },
	},
	FB_Trooper = {
		displayName = "Faction B Trooper",
		faction = "FactionB",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.5,
		height = 5,
		asset = "FB_Trooper",
		placeholder = { shape = "Cylinder", bodySize = Vector3.new(2.2, 3.6, 2.2) },
	},
}
