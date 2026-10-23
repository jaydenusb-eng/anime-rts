--[[
	NavigationService
	Turns "move these units to that point" into a path for each unit.

	For a group order it:
	  1. Finds the ground under the target and, if a unit can't stand there (inside a
	     rock, on top of a mesa), the nearest spot where it can.
	  2. Checks the group can actually get there. If not (for example the spot is inside
	     a closed pen), it steps back towards the group to the nearest reachable spot.
	  3. Spreads the units into formation slots around that spot (Shared/Formation).
	  4. Works out each unit's path and hands it to MovementSystem.

	Paths are worked out once per order, never every frame. A clear straight line skips
	pathfinding entirely, and at most MaxConcurrentPathJobs path calculations run at
	once; the rest wait their turn.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formation = require(Shared.Formation)
local MapInfo = require(Shared.MapInfo)
local MovementSystem = require(script.Parent.MovementSystem)
local UnitService = require(script.Parent.UnitService)

type Unit = UnitService.Unit

export type MoveSummary = {
	requested: number,
	moved: number, -- units that got a path
	failed: number, -- units that can't get there
	superseded: number, -- units that got a newer order before this one was worked out
	adjusted: boolean, -- the destination was moved to the nearest reachable spot
	unreachable: boolean, -- nowhere near the destination could be reached
}

local SETTINGS = GameConfig.Movement
local PROBE_HEIGHT = 500 -- ground checks start this high and look straight down
local GROUND_SAMPLE_SPACING = 10 -- studs between ground checks along a straight route
local MAX_STRAIGHT_ROUTE = 1000 -- longer moves always use pathfinding

local NavigationService = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local blockerRayParams = RaycastParams.new()
blockerRayParams.FilterType = Enum.RaycastFilterType.Include
blockerRayParams.RespectCanCollide = true

local blockerOverlapParams = OverlapParams.new()
blockerOverlapParams.FilterType = Enum.RaycastFilterType.Include
blockerOverlapParams.RespectCanCollide = true

local stats = {
	groupOrders = 0,
	straightRoutes = 0,
	pathJobs = 0,
	cancelledJobs = 0,
	failedPaths = 0,
	peakQueue = 0,
	totalPathMs = 0,
	slowestPathMs = 0,
}

-- Path job limiter ---------------------------------------------------------------
-- At most MaxConcurrentPathJobs path calculations run at once; the rest wait in line.

local activeJobs = 0
local waitingJobs: { thread } = {}

local function acquireJobSlot()
	if activeJobs < SETTINGS.MaxConcurrentPathJobs then
		activeJobs += 1
		return
	end
	table.insert(waitingJobs, coroutine.running())
	stats.peakQueue = math.max(stats.peakQueue, #waitingJobs)
	coroutine.yield()
end

local function releaseJobSlot()
	local nextJob = table.remove(waitingJobs, 1)
	if nextJob then
		task.spawn(nextJob) -- hand this slot straight to the next job in line
	else
		activeJobs -= 1
	end
end

-- Ground and space checks -----------------------------------------------------------

-- The ground point under (x, z), or nil if there is no ground there.
function NavigationService.groundAt(x: number, z: number): Vector3?
	local origin = Vector3.new(x, PROBE_HEIGHT, z)
	local result = workspace:Raycast(origin, Vector3.new(0, -2 * PROBE_HEIGHT, 0), groundParams)
	return result and result.Position
end

-- True if an obstacle overlaps the space a unit of this size would fill standing at `feet`.
local function isBlocked(feet: Vector3, radius: number, height: number): boolean
	local box = CFrame.new(feet + Vector3.new(0, height / 2 + 0.2, 0))
	local size = Vector3.new(radius * 2, height, radius * 2)
	return #workspace:GetPartBoundsInBox(box, size, blockerOverlapParams) > 0
end

-- The ground point under `point` if a unit of this size fits there, otherwise nil.
function NavigationService.resolveStandPoint(point: Vector3, radius: number, height: number): Vector3?
	local ground = NavigationService.groundAt(point.X, point.Z)
	if ground and MapInfo.isInsidePlayArea(ground, radius) and not isBlocked(ground, radius, height) then
		return ground
	end
	return nil
end

-- Searches outward from `point` in rings for a spot where a unit fits. In the first ring
-- that has any, picks the spot closest to `prefer` (usually where the group is).
local function findStandSpotNear(point: Vector3, radius: number, height: number, prefer: Vector3): Vector3?
	local direct = NavigationService.resolveStandPoint(point, radius, height)
	if direct then
		return direct
	end
	local step = SETTINGS.UnreachableSearchStep
	for ringRadius = step, SETTINGS.UnreachableSearchRadius, step do
		local samples = math.max(8, math.floor(2 * math.pi * ringRadius / step))
		local best, bestDistance = nil, math.huge
		for i = 1, samples do
			local angle = i / samples * 2 * math.pi
			local offset = Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
			local spot = NavigationService.resolveStandPoint(point + offset, radius, height)
			if spot and (spot - prefer).Magnitude < bestDistance then
				best, bestDistance = spot, (spot - prefer).Magnitude
			end
		end
		if best then
			return best
		end
	end
	return nil
end

-- Paths ------------------------------------------------------------------------------

-- True if a unit can walk straight from `from` to `to`: nothing in the way and level
-- ground all along (a straight line must not cut through hills or cross holes).
local function isStraightRouteClear(from: Vector3, to: Vector3, radius: number, height: number): boolean
	local offset = to - from
	local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if flatDistance < 0.05 then
		return true
	end
	if flatDistance > MAX_STRAIGHT_ROUTE or math.abs(offset.Y) > 0.5 then
		return false
	end
	-- A sweep can't see an obstacle it starts inside, so check the starting spot first.
	if isBlocked(from, radius, height) then
		return false
	end
	if workspace:Spherecast(from + Vector3.new(0, radius + 0.3, 0), radius, offset, blockerRayParams) then
		return false
	end
	local samples = math.floor(flatDistance / GROUND_SAMPLE_SPACING)
	for i = 1, samples do
		local point = from + offset * (i / (samples + 1))
		local ground = NavigationService.groundAt(point.X, point.Z)
		if not ground or math.abs(ground.Y - from.Y) > 0.5 then
			return false
		end
	end
	return true
end

-- The points a unit should walk through to get from `from` to `to` (not including
-- `from`), or nil if there is no way there. `isWanted` is asked again after waiting in
-- line: if the order was replaced in the meantime, the work is skipped and nil returned.
local function computePath(from: Vector3, to: Vector3, radius: number, height: number, isWanted: () -> boolean): { Vector3 }?
	if isStraightRouteClear(from, to, radius, height) then
		stats.straightRoutes += 1
		return { to }
	end

	acquireJobSlot()
	if not isWanted() then
		releaseJobSlot()
		stats.cancelledJobs += 1
		return nil
	end
	stats.pathJobs += 1
	local started = os.clock()
	local path = PathfindingService:CreatePath({
		AgentRadius = math.ceil(radius),
		AgentHeight = math.ceil(height),
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = math.huge, -- corners only; units walk straight between them
	})
	local ok, err = pcall(function()
		path:ComputeAsync(from, to)
	end)
	local elapsedMs = (os.clock() - started) * 1000
	releaseJobSlot()
	stats.totalPathMs += elapsedMs
	stats.slowestPathMs = math.max(stats.slowestPathMs, elapsedMs)

	if not ok then
		warn("[NavigationService] Path calculation error: " .. tostring(err))
	end
	if not ok or path.Status ~= Enum.PathStatus.Success then
		stats.failedPaths += 1
		return nil
	end

	local points = {}
	for index, waypoint in path:GetWaypoints() do
		if index > 1 then -- the first waypoint is where the unit already stands
			local ground = NavigationService.groundAt(waypoint.Position.X, waypoint.Position.Z)
			table.insert(points, ground or waypoint.Position)
		end
	end
	-- Finish exactly on the requested spot; pathfinding can stop slightly short of it.
	if #points > 0 and (points[#points] - to).Magnitude < 4 then
		points[#points] = to
	else
		table.insert(points, to)
	end
	return points
end

-- Group orders -------------------------------------------------------------------------

local function isCurrent(unit: Unit, orderIds: { [Unit]: number }): boolean
	return unit.alive and unit.orderId == orderIds[unit]
end

-- The unit nearest the middle of the group; used to test whether a spot is reachable.
local function findLeader(units: { Unit }, centroid: Vector3): Unit
	local leader, bestDistance = units[1], math.huge
	for _, unit in units do
		local distance = (unit.position - centroid).Magnitude
		if distance < bestDistance then
			leader, bestDistance = unit, distance
		end
	end
	return leader
end

-- `center` can't be reached. Step back from it towards the group and return the first
-- spot that has room for a unit and a path from the leader.
local function findReachableNear(
	center: Vector3,
	leader: Unit,
	centroid: Vector3,
	radius: number,
	height: number,
	isWanted: () -> boolean
): Vector3?
	local toGroup = Vector3.new(centroid.X - center.X, 0, centroid.Z - center.Z)
	local distance = toGroup.Magnitude
	if distance < 1 then
		return nil
	end
	local direction = toGroup.Unit
	local probes = 0
	local step = SETTINGS.UnreachableSearchStep
	for travelled = step, math.min(distance, SETTINGS.UnreachableSearchRadius), step do
		local spot = NavigationService.resolveStandPoint(center + direction * travelled, radius, height)
		if spot then
			if computePath(leader.position, spot, leader.def.radius, leader.def.height, isWanted) then
				return spot
			end
			probes += 1
			if probes >= SETTINGS.MaxReachabilityProbes or not isWanted() then
				break
			end
		end
	end
	return nil
end

local function runGroupMove(units: { Unit }, orderIds: { [Unit]: number }, target: Vector3): MoveSummary
	local summary: MoveSummary = {
		requested = #units,
		moved = 0,
		failed = 0,
		superseded = 0,
		adjusted = false,
		unreachable = false,
	}

	local centroid = Vector3.zero
	local radius, height = 0, 0
	for _, unit in units do
		centroid += unit.position
		radius = math.max(radius, unit.def.radius)
		height = math.max(height, unit.def.height)
	end
	centroid /= #units

	-- False once every unit in the group has been given a newer order.
	local function isAnyCurrent(): boolean
		for _, unit in units do
			if isCurrent(unit, orderIds) then
				return true
			end
		end
		return false
	end

	-- Ends the order early: units still on it stop where they are; the rest already
	-- have a newer order and are left alone.
	local function stopRemaining(): MoveSummary
		for _, unit in units do
			if isCurrent(unit, orderIds) then
				MovementSystem.stop(unit)
				summary.failed += 1
			else
				summary.superseded += 1
			end
		end
		summary.unreachable = summary.failed > 0
		return summary
	end

	-- 1. A spot inside the play area where a unit fits (not inside a rock or on a mesa).
	local clamped = MapInfo.clampToPlayArea(target, SETTINGS.EdgeMargin)
	local center = findStandSpotNear(clamped, radius, height, centroid)
	if not center then
		return stopRemaining()
	end
	if Vector3.new(center.X - clamped.X, 0, center.Z - clamped.Z).Magnitude > 0.5 then
		summary.adjusted = true
	end

	-- 2. Check the group can get there, using the unit nearest the middle of the group.
	local leader = findLeader(units, centroid)
	if not computePath(leader.position, center, leader.def.radius, leader.def.height, isAnyCurrent) then
		local reachable = if isAnyCurrent()
			then findReachableNear(center, leader, centroid, radius, height, isAnyCurrent)
			else nil
		if not reachable then
			return stopRemaining()
		end
		center = reachable
		summary.adjusted = true
	end
	if not isAnyCurrent() then
		return stopRemaining() -- every unit already has a newer order
	end

	-- 3. Spread the group into formation slots around the destination.
	local forward = center - centroid
	local spacing = radius * 2 + SETTINGS.FormationGap
	local slots = Formation.pickSlots(center, #units, spacing, forward, function(point)
		return NavigationService.resolveStandPoint(point, radius, height)
	end)
	local positions = table.create(#units)
	for index, unit in units do
		positions[index] = unit.position
	end
	local assignment = Formation.assign(positions, slots, forward)

	-- 4. A path for every unit. They are worked out side by side; the job limiter keeps
	-- the number of simultaneous path calculations in check.
	local thread = coroutine.running()
	local remaining = #units
	local waiting = false
	for index, unit in units do
		task.spawn(function()
			local function isWanted(): boolean
				return isCurrent(unit, orderIds)
			end
			local ok, err = pcall(function()
				local slot = slots[assignment[index]].position
				local points = nil
				if isWanted() then
					points = computePath(unit.position, slot, unit.def.radius, unit.def.height, isWanted)
					if not points and slot ~= center and isWanted() then
						points = computePath(unit.position, center, unit.def.radius, unit.def.height, isWanted)
					end
				end
				if not isCurrent(unit, orderIds) then
					summary.superseded += 1
				elseif points then
					MovementSystem.setPath(unit, points)
					summary.moved += 1
				else
					MovementSystem.stop(unit)
					summary.failed += 1
				end
			end)
			if not ok then
				warn("[NavigationService] Error while routing unit " .. unit.id .. ": " .. tostring(err))
				summary.failed += 1
			end
			remaining -= 1
			if remaining == 0 and waiting then
				task.spawn(thread)
			end
		end)
	end
	if remaining > 0 then
		waiting = true
		coroutine.yield()
	end
	return summary
end

-- Orders `units` to move to `target`. Returns straight away: paths are worked out in the
-- background and `onDone(summary)` runs once every unit has a path or has given up.
-- A newer order for a unit always wins over an older one still being worked out.
function NavigationService.moveGroup(units: { Unit }, target: Vector3, onDone: ((MoveSummary) -> ())?)
	stats.groupOrders += 1
	local orderIds = {}
	for _, unit in units do
		unit.orderId += 1
		orderIds[unit] = unit.orderId
	end
	task.spawn(function()
		local summary = runGroupMove(units, orderIds, target)
		if onDone then
			onDone(summary)
		end
	end)
end

function NavigationService.getStats()
	local snapshot = table.clone(stats)
	snapshot.activeJobs = activeJobs
	snapshot.queuedJobs = #waitingJobs
	return snapshot
end

function NavigationService.resetStats()
	for key in stats do
		stats[key] = 0
	end
end

function NavigationService.init()
	local ground = MapInfo.getFolder("Ground")
	local obstacles = MapInfo.getFolder("Obstacles")
	local boundary = MapInfo.getFolder("Boundary")
	assert(ground and obstacles and boundary,
		"Workspace.Map needs Ground, Obstacles and Boundary folders. Run tools/BuildTestMap.luau in Studio.")
	groundParams.FilterDescendantsInstances = { ground }
	blockerRayParams.FilterDescendantsInstances = { obstacles, boundary }
	blockerOverlapParams.FilterDescendantsInstances = { obstacles, boundary }
end

return NavigationService
