--[[
	MovementSystem
	Moves every walking unit along its path, all inside ONE loop that runs once per
	server frame (Heartbeat). Idle units cost nothing: only units with a path are visited.

	The server decides every position and moves each model's Root part; Roblox then
	copies (replicates) that to all players. Units ignore physics entirely, so they are
	never pushed around, never fall over, and can't be moved by a cheating client.
]]

local RunService = game:GetService("RunService")

local UnitService = require(script.Parent.UnitService)

type Unit = UnitService.Unit

local MovementSystem = {}

local moving: { [number]: Unit } = {}
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local stats = { lastStepMs = 0, averageStepMs = 0, peakStepMs = 0, movingUnits = 0 }

local function step(deltaTime: number)
	local started = os.clock()
	local count = 0

	for id, unit in moving do
		local path = unit.path :: { Vector3 }
		local index = unit.waypointIndex
		local position = unit.position
		local budget = unit.def.moveSpeed * deltaTime -- studs this unit may move this frame

		while budget > 0 and index <= #path do
			local offset = path[index] - position
			local distance = offset.Magnitude
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude > 1e-3 then
				unit.facing = flat.Unit
			end
			if distance <= budget then
				position = path[index]
				budget -= distance
				index += 1
			else
				position += offset * (budget / distance)
				budget = 0
			end
		end

		unit.position = position
		unit.waypointIndex = index
		if index > #path then
			unit.path = nil
			moving[id] = nil -- arrived
		end

		count += 1
		parts[count] = unit.root
		cframes[count] = CFrame.lookAt(position, position + unit.facing)
	end

	for i = count + 1, #parts do
		parts[i] = nil
		cframes[i] = nil
	end
	if count > 0 then
		-- One engine call moves every unit; much cheaper than setting each CFrame separately.
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	local elapsedMs = (os.clock() - started) * 1000
	stats.lastStepMs = elapsedMs
	stats.averageStepMs = stats.averageStepMs * 0.95 + elapsedMs * 0.05
	stats.peakStepMs = math.max(stats.peakStepMs, elapsedMs)
	stats.movingUnits = count
end

-- Makes `unit` walk through `points` in order (its current position is not included).
-- Replaces whatever path it was following.
function MovementSystem.setPath(unit: Unit, points: { Vector3 })
	if #points == 0 then
		MovementSystem.stop(unit)
		return
	end
	unit.path = points
	unit.waypointIndex = 1
	moving[unit.id] = unit
end

function MovementSystem.stop(unit: Unit)
	unit.path = nil
	unit.waypointIndex = 0
	moving[unit.id] = nil
end

function MovementSystem.isMoving(unit: Unit): boolean
	return moving[unit.id] ~= nil
end

-- Timing numbers for benchmarks (milliseconds of server time per frame).
function MovementSystem.getStats()
	return table.clone(stats)
end

function MovementSystem.resetStats()
	stats.peakStepMs = 0
	stats.averageStepMs = 0
end

function MovementSystem.start()
	UnitService.onUnitRemoved(function(unit)
		moving[unit.id] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return MovementSystem
