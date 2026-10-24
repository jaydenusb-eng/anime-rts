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
	  animation    Optional. "NinjaRun" makes the client pose the model's R6 joints: a
	               Naruto-style sprint while it moves (see Client.Visuals.NinjaRun).
]]

return {
	FA_NinjaScout = {
		displayName = "Genin Scout",
		faction = "FactionA",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.8,
		height = 5,
		asset = "Ninja_Scout",
		animation = "NinjaRun",
		placeholder = { shape = "Block", bodySize = Vector3.new(2.2, 3.6, 1.6) },
	},
	FA_NinjaJonin = {
		displayName = "Jonin",
		faction = "FactionA",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.8,
		height = 5,
		asset = "Ninja_Jonin",
		animation = "NinjaRun",
		placeholder = { shape = "Block", bodySize = Vector3.new(2.2, 3.6, 1.6) },
	},
	FA_NinjaKunoichi = {
		displayName = "Kunoichi",
		faction = "FactionA",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.8,
		height = 5,
		asset = "Ninja_Kunoichi",
		animation = "NinjaRun",
		placeholder = { shape = "Block", bodySize = Vector3.new(2.2, 3.6, 1.6) },
	},
	-- A squad of three genin that moves and is selected as one unit (one Meshy mesh).
	FA_Genin = {
		displayName = "Genin Squad",
		faction = "FactionA",
		role = "Infantry",
		moveSpeed = 14,
		radius = 4.2, -- the three figures stand about 8.4 studs wide
		height = 6,
		asset = "FA_Genin",
		placeholder = { shape = "Block", bodySize = Vector3.new(6, 4, 3) },
	},
	FB_Trooper = {
		displayName = "Faction B Trooper",
		faction = "FactionB",
		role = "Infantry",
		moveSpeed = 14,
		radius = 1.5,
		height = 5,
		asset = "FB_Trooper",
		-- No model yet: a block painted in the red team's colour stands in for it.
		placeholder = { shape = "Block", bodySize = Vector3.new(2.2, 3.6, 1.6) },
	},
}
