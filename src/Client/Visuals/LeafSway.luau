--[[
	LeafSway
	Rocks tree leaves gently in the wind. The map generator groups each tree's leaves (and each
	bamboo clump) into a Model tagged "SwayingLeaves" with a SwayPivot (Vector3) and a SwayAmount
	(degrees). Only groups near the camera's focus move, a fixed number of times per second, and
	every moving part is placed in one BulkMoveTo call. Purely visual: it runs on this computer
	only and never touches anything the game logic uses.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local LeafSway = {}

local TAG = "SwayingLeaves"
local RANGE = 280 -- studs from the camera focus within which leaves move
local UPDATES_PER_SECOND = 24
local WIND = Vector3.new(1, 0, 0.35).Unit
-- Trees lean around this axis, i.e. towards and away from the wind.
local LEAN_AXIS = Vector3.new(-WIND.Z, 0, WIND.X)

type Group = {
	pivot: Vector3,
	amount: number, -- radians
	phase: number,
	parts: { BasePart },
	base: { CFrame },
}

local groups: { [Instance]: Group } = {}
local movingParts: { BasePart } = {}
local movingCFrames: { CFrame } = {}

local function addGroup(model: Instance)
	local pivot = model:GetAttribute("SwayPivot")
	if groups[model] or typeof(pivot) ~= "Vector3" then
		return
	end
	local group: Group = {
		pivot = pivot,
		amount = math.rad(model:GetAttribute("SwayAmount") or 2),
		-- Neighbouring trees are a little out of step, so the wind seems to roll across the map.
		phase = pivot.X * 0.012 + pivot.Z * 0.004,
		parts = {},
		base = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(group.parts, d)
			table.insert(group.base, d.CFrame)
		end
	end
	groups[model] = group
end

local function step(now: number)
	local focus = CameraController.getFocus()
	local count = 0
	for _, group in groups do
		local dx, dz = group.pivot.X - focus.X, group.pivot.Z - focus.Z
		if dx * dx + dz * dz < RANGE * RANGE then
			-- A slow sway plus a faster flutter, leaning mostly with the wind.
			local t = now + group.phase
			local lean = group.amount * (0.35 + 0.5 * math.sin(t * 1.1) + 0.15 * math.sin(t * 2.9))
			local rotation = CFrame.new(group.pivot) * CFrame.fromAxisAngle(LEAN_AXIS, lean) * CFrame.new(-group.pivot)
			for i, p in group.parts do
				count += 1
				movingParts[count] = p
				movingCFrames[count] = rotation * group.base[i]
			end
		end
	end
	for i = count + 1, #movingParts do
		movingParts[i] = nil
		movingCFrames[i] = nil
	end
	if count > 0 then
		workspace:BulkMoveTo(movingParts, movingCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function LeafSway.start()
	for _, model in CollectionService:GetTagged(TAG) do
		addGroup(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(addGroup)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		groups[model] = nil
	end)

	local sinceLast = 0
	RunService.RenderStepped:Connect(function(deltaTime)
		sinceLast += deltaTime
		if sinceLast >= 1 / UPDATES_PER_SECOND then
			sinceLast = 0
			step(os.clock())
		end
	end)
end

return LeafSway
