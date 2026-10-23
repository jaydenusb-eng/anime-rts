--[[
	BuildTestMap.luau
	Builds the Milestone 1 test map in Workspace.Map.

	How to run: Studio > View > Command Bar, paste this whole file, press Enter.
	(Or ask Claude to run it through the Studio MCP.)

	Safe on a place that already has work in it:
	  - If Workspace.Map exists it stops. Set REBUILD = true to replace only the
	    generated folders (Obstacles, Boundary, Markers); Ground is kept.
	  - An existing Workspace.GrassFloor is reused as the ground.
	  - An existing Workspace.SpawnLocation is moved to ServerStorage.Unused
	    (RTS players have no avatar, so it isn't used).

	Layout seen from above (north = -Z, east = +X):
	  - Player slot 1 starts west (x = -150), slot 2 starts east (x = 150).
	  - Wall lines at x = -80 and x = 80, each with two 32-stud gaps (chokepoints).
	  - Centre: a rock. North of it: a closed pen (its inside is unreachable).
	    South of it: a tall mesa (its top is unreachable).
	  - Small cover blocks and boulders to path around.
]]

local REBUILD = false

local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local PLAY_AREA_SIZE = Vector3.new(360, 1, 240) -- X by Z footprint of the playable rectangle
local SLOT_COLORS = { Color3.fromRGB(64, 140, 255), Color3.fromRGB(235, 70, 60) }

local ROCK = { Material = Enum.Material.Rock, Color = Color3.fromRGB(112, 106, 98) }
local WALL = { Material = Enum.Material.Slate, Color = Color3.fromRGB(88, 92, 102) }
local PEN = { Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(124, 88, 60) }
local MESA = { Material = Enum.Material.Sandstone, Color = Color3.fromRGB(176, 140, 100) }
local EDGE = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(62, 64, 72) }

local function makePart(name: string, size: Vector3, position: Vector3, style, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = style.Material
	part.Color = style.Color
	part.Parent = parent
	return part
end

local function makeFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function build(): boolean
	local map = workspace:FindFirstChild("Map")
	if map and not REBUILD then
		warn("[BuildTestMap] Workspace.Map already exists. Set REBUILD = true to regenerate it.")
		return false
	end
	if not map then
		map = makeFolder("Map", workspace)
	end
	for _, name in { "Obstacles", "Boundary", "Markers" } do
		local old = map:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- Ground: reuse the place's existing floor if there is one.
	local ground = map:FindFirstChild("Ground") or makeFolder("Ground", map)
	if #ground:GetChildren() == 0 then
		local floor = workspace:FindFirstChild("GrassFloor")
		if floor and floor:IsA("BasePart") then
			floor.Parent = ground
		else
			makePart("Floor", Vector3.new(1024, 16, 1024), Vector3.new(0, -8, 0),
				{ Material = Enum.Material.Grass, Color = Color3.fromRGB(86, 124, 64) }, ground)
		end
	end

	-- The template SpawnLocation isn't used (no avatars). Keep it, out of the way.
	local spawnLocation = workspace:FindFirstChild("SpawnLocation")
	if spawnLocation then
		local unused = ServerStorage:FindFirstChild("Unused") or makeFolder("Unused", ServerStorage)
		spawnLocation.Parent = unused
	end

	local obstacles = makeFolder("Obstacles", map)

	-- Wall lines with two gaps each, at x = -80 and x = 80.
	for _, x in { -80, 80 } do
		local side = if x < 0 then "West" else "East"
		makePart("Wall" .. side .. "_North", Vector3.new(6, 12, 58), Vector3.new(x, 6, -91), WALL, obstacles)
		makePart("Wall" .. side .. "_Middle", Vector3.new(6, 12, 60), Vector3.new(x, 6, 0), WALL, obstacles)
		makePart("Wall" .. side .. "_South", Vector3.new(6, 12, 58), Vector3.new(x, 6, 91), WALL, obstacles)
	end

	makePart("CenterRock", Vector3.new(22, 14, 22), Vector3.new(0, 7, 0), ROCK, obstacles)

	-- Closed pen: four walls with no opening. Ordering units inside it tests "unreachable".
	makePart("Pen_North", Vector3.new(34, 10, 3), Vector3.new(0, 5, -95.5), PEN, obstacles)
	makePart("Pen_South", Vector3.new(34, 10, 3), Vector3.new(0, 5, -64.5), PEN, obstacles)
	makePart("Pen_West", Vector3.new(3, 10, 28), Vector3.new(-15.5, 5, -80), PEN, obstacles)
	makePart("Pen_East", Vector3.new(3, 10, 28), Vector3.new(15.5, 5, -80), PEN, obstacles)

	-- Tall mesa: clicking its top tests "destination inside an obstacle".
	makePart("Mesa", Vector3.new(30, 18, 30), Vector3.new(0, 9, 80), MESA, obstacles)

	for _, x in { -40, 40 } do
		for _, z in { -45, 45 } do
			makePart(string.format("Cover_%d_%d", x, z), Vector3.new(14, 6, 5), Vector3.new(x, 3, z), ROCK, obstacles)
		end
	end
	for _, x in { -125, 125 } do
		for _, z in { -40, 40 } do
			makePart(string.format("Boulder_%d_%d", x, z), Vector3.new(10, 6, 14), Vector3.new(x, 3, z), ROCK, obstacles)
		end
	end

	-- Walls around the play area so paths can't wander off the map.
	local boundary = makeFolder("Boundary", map)
	local halfX, halfZ = PLAY_AREA_SIZE.X / 2, PLAY_AREA_SIZE.Z / 2
	makePart("Edge_North", Vector3.new(PLAY_AREA_SIZE.X + 8, 10, 4), Vector3.new(0, 5, -halfZ - 2), EDGE, boundary)
	makePart("Edge_South", Vector3.new(PLAY_AREA_SIZE.X + 8, 10, 4), Vector3.new(0, 5, halfZ + 2), EDGE, boundary)
	makePart("Edge_West", Vector3.new(4, 10, PLAY_AREA_SIZE.Z), Vector3.new(-halfX - 2, 5, 0), EDGE, boundary)
	makePart("Edge_East", Vector3.new(4, 10, PLAY_AREA_SIZE.Z), Vector3.new(halfX + 2, 5, 0), EDGE, boundary)

	-- Markers: invisible or decorative parts that code reads. Never obstacles.
	local markers = makeFolder("Markers", map)
	local playArea = makePart("PlayArea", PLAY_AREA_SIZE, Vector3.new(0, PLAY_AREA_SIZE.Y / 2, 0), EDGE, markers)
	playArea.Transparency = 1

	local startPoints = makeFolder("StartPoints", markers)
	for slot, x in { -150, 150 } do
		local pad = makePart("Slot" .. slot, Vector3.new(36, 0.1, 36), Vector3.zero,
			{ Material = Enum.Material.SmoothPlastic, Color = SLOT_COLORS[slot] }, startPoints)
		-- Face the map centre: the army spawns facing the same way.
		pad.CFrame = CFrame.lookAt(Vector3.new(x, 0.05, 0), Vector3.new(0, 0.05, 0))
		pad.Transparency = 0.6
		pad.CastShadow = false
	end

	for _, item in markers:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	return true
end

local recording
pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Build RTS test map")
end)
local ok, result = pcall(build)
if recording then
	ChangeHistoryService:FinishRecording(recording,
		if ok and result then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
end
if not ok then
	error(result)
elseif result then
	print("[BuildTestMap] Built Workspace.Map.")
end
