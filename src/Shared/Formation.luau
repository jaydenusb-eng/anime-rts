--[[
	Formation
	Math for spreading a group of units around a destination so they don't all try
	to stand on the same point. Nothing here touches the game world directly, which
	keeps it easy to test and reuse (squads in Milestone 2 will reuse it).

	Slots sit on a square grid ("lattice") turned to face the direction of travel.
	Row numbers grow towards the front, column numbers grow towards the right.
]]

local Formation = {}

export type Slot = {
	position: Vector3,
	row: number,
	column: number,
}

-- The flat "front" and "right" directions for a group travelling along `forward`.
local function getAxes(forward: Vector3): (Vector3, Vector3)
	local front = Vector3.new(forward.X, 0, forward.Z)
	if front.Magnitude < 1e-3 then
		front = Vector3.new(0, 0, -1)
	end
	front = front.Unit
	return front, Vector3.new(-front.Z, 0, front.X)
end

-- Picks `count` slots around `center`, `spacing` studs apart, closest to the centre first.
-- `resolve(point)` may move a slot (e.g. onto the ground) or return nil to skip it
-- (e.g. inside a wall). Returns slots sorted front row first, left to right.
function Formation.pickSlots(
	center: Vector3,
	count: number,
	spacing: number,
	forward: Vector3,
	resolve: ((Vector3) -> Vector3?)?
): { Slot }
	local front, right = getAxes(forward)

	-- Every lattice point near the centre, nearest first.
	local reach = math.ceil(math.sqrt(count)) + 6
	local candidates = {}
	for row = -reach, reach do
		for column = -reach, reach do
			table.insert(candidates, { row = row, column = column, distance = row * row + column * column })
		end
	end
	table.sort(candidates, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		elseif a.row ~= b.row then
			return a.row > b.row
		end
		return a.column < b.column
	end)

	local slots: { Slot } = {}
	for _, candidate in candidates do
		if #slots == count then
			break
		end
		local point = center + front * (candidate.row * spacing) + right * (candidate.column * spacing)
		local resolved = if resolve then resolve(point) else point
		if resolved then
			table.insert(slots, { position = resolved, row = candidate.row, column = candidate.column })
		end
	end
	-- Not enough free room nearby: the remaining units share the centre.
	while #slots < count do
		table.insert(slots, { position = center, row = 0, column = 0 })
	end

	table.sort(slots, function(a, b)
		if a.row ~= b.row then
			return a.row > b.row
		end
		return a.column < b.column
	end)
	return slots
end

-- Matches units to slots so the group keeps its shape: the units furthest forward take
-- the front row, and within a row the left-most unit takes the left-most slot. This
-- stops units crossing through each other on the way. `slots` must come from pickSlots
-- and have one slot per unit. Returns result[unitIndex] = slotIndex.
function Formation.assign(unitPositions: { Vector3 }, slots: { Slot }, forward: Vector3): { number }
	local front, right = getAxes(forward)

	local byDepth = {}
	for index = 1, #unitPositions do
		byDepth[index] = index
	end
	table.sort(byDepth, function(a, b)
		return unitPositions[a]:Dot(front) > unitPositions[b]:Dot(front)
	end)

	local result = {}
	local nextUnit = 1
	local rowStart = 1
	while rowStart <= #slots do
		local rowEnd = rowStart
		while rowEnd < #slots and slots[rowEnd + 1].row == slots[rowStart].row do
			rowEnd += 1
		end
		local rowSize = rowEnd - rowStart + 1

		local rowUnits = table.move(byDepth, nextUnit, nextUnit + rowSize - 1, 1, {})
		table.sort(rowUnits, function(a, b)
			return unitPositions[a]:Dot(right) < unitPositions[b]:Dot(right)
		end)
		for offset, unitIndex in rowUnits do
			result[unitIndex] = rowStart + offset - 1
		end

		nextUnit += rowSize
		rowStart = rowEnd + 1
	end
	return result
end

return Formation
