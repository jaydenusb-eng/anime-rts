--[[
	GameConfig
	Match-wide settings. Unit stats live in UnitConfig and faction data in FactionConfig.
	These are plain values so designers can tune them without touching any logic.
]]

local GameConfig = {}

-- Milestone 1 is a 1v1. Team matches raise this later.
GameConfig.MaxPlayers = 2

-- What each player slot gets. On the Hidden Valley map slot 1 starts in the north-east
-- compound and slot 2 in the south-east fortress (Workspace.Map.Markers.StartPoints).
-- `name` labels the slot's team button in the HUD.
GameConfig.Slots = {
	{ name = "Blue Team", faction = "FactionA", color = Color3.fromRGB(64, 140, 255) },
	{ name = "Red Team", faction = "FactionB", color = Color3.fromRGB(235, 70, 60) },
}

-- Seconds a player must wait between team switches.
GameConfig.TeamSwitchCooldown = 2

GameConfig.Map = {
	-- Name of the folder in Workspace that holds the current map.
	FolderName = "Map",
}

GameConfig.Commands = {
	-- The most units a single order may include. Larger requests are rejected.
	MaxUnitsPerCommand = 120,
	-- Rate limit: a player may send this many orders in a burst...
	BurstLimit = 20,
	-- ...and earns back this many per second.
	RefillPerSecond = 10,
}

GameConfig.Movement = {
	-- Extra space (studs) between neighbouring units in a formation, on top of their size.
	FormationGap = 1,
	-- Move targets are kept at least this far inside the play-area edge.
	EdgeMargin = 4,
	-- How many path calculations the server runs at the same time. The rest wait in a queue.
	MaxConcurrentPathJobs = 16,
	-- If a destination can't be reached, look this far (studs) for the closest spot that can.
	UnreachableSearchRadius = 48,
	-- Distance between the rings checked during that search.
	UnreachableSearchStep = 6,
	-- At most this many full path calculations are spent finding that spot.
	MaxReachabilityProbes = 5,
}

return GameConfig
