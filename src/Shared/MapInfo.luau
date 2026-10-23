--[[
	MapInfo
	Reads the current map's layout so the server and every client agree on where the
	play area is and where each player starts. Map designers move these parts in
	Studio; no map coordinates are written into code.

	Expected layout (tools/BuildTestMap.luau creates it):
	  Workspace.Map
	    Ground       floor parts units walk on
	    Obstacles    anything units must path around
	    Boundary     walls around the play area
	    Markers
	      PlayArea      invisible, unrotated part. Its X/Z footprint is the playable
	                    area and its bottom face is ground level.
	      StartPoints
	        Slot1, Slot2, ...  where each player's army starts. The army faces the
	                           same way as the part's front face.
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local MapInfo = {}

local function getMarkers(): Instance?
	local map = workspace:FindFirstChild(GameConfig.Map.FolderName)
	return map and map:FindFirstChild("Markers")
end

local function getPlayAreaPart(): BasePart
	local markers = getMarkers()
	local playArea = markers and markers:FindFirstChild("PlayArea")
	assert(playArea, "Workspace.Map.Markers.PlayArea is missing. Run tools/BuildTestMap.luau in Studio.")
	return playArea :: BasePart
end

-- Waits until the map has arrived (it replicates to clients after they join) and returns it.
function MapInfo.waitForMap(): Instance
	local map = workspace:WaitForChild(GameConfig.Map.FolderName)
	local markers = map:WaitForChild("Markers")
	markers:WaitForChild("PlayArea")
	markers:WaitForChild("StartPoints")
	return map
end

-- Returns one of the map's folders ("Ground", "Obstacles", "Boundary", "Markers"), or nil.
function MapInfo.getFolder(name: string): Instance?
	local map = workspace:FindFirstChild(GameConfig.Map.FolderName)
	return map and map:FindFirstChild(name)
end

-- Returns the two corners of the playable rectangle. Their Y is ground level.
function MapInfo.getPlayArea(): (Vector3, Vector3)
	local part = getPlayAreaPart()
	local half = part.Size / 2
	local center = part.Position
	local groundY = center.Y - half.Y
	return Vector3.new(center.X - half.X, groundY, center.Z - half.Z),
		Vector3.new(center.X + half.X, groundY, center.Z + half.Z)
end

function MapInfo.getCenter(): Vector3
	local minCorner, maxCorner = MapInfo.getPlayArea()
	return (minCorner + maxCorner) / 2
end

-- Moves a point inside the play area, keeping it `margin` studs away from the edges.
function MapInfo.clampToPlayArea(point: Vector3, margin: number?): Vector3
	local minCorner, maxCorner = MapInfo.getPlayArea()
	local m = margin or 0
	return Vector3.new(
		math.clamp(point.X, minCorner.X + m, maxCorner.X - m),
		point.Y,
		math.clamp(point.Z, minCorner.Z + m, maxCorner.Z - m)
	)
end

function MapInfo.isInsidePlayArea(point: Vector3, margin: number?): boolean
	local minCorner, maxCorner = MapInfo.getPlayArea()
	local m = margin or 0
	return point.X >= minCorner.X + m
		and point.X <= maxCorner.X - m
		and point.Z >= minCorner.Z + m
		and point.Z <= maxCorner.Z - m
end

-- Where a player slot's army starts, or nil if the map has no marker for that slot.
function MapInfo.getStartCFrame(slot: number): CFrame?
	local markers = getMarkers()
	local starts = markers and markers:FindFirstChild("StartPoints")
	local marker = starts and starts:FindFirstChild("Slot" .. slot)
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	return nil
end

return MapInfo
