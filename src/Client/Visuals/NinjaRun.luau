--[[
	NinjaRun
	Animates units whose UnitConfig entry has animation = "NinjaRun": while a unit moves it
	sprints Naruto-style (body leaned forward, head up, both arms swept straight back, legs
	pumping), and it eases back to standing when it stops. The pose is set on this computer
	only, through each rig joint's Motor6D.Transform, so nothing is uploaded or replicated and
	the server's positions are never touched. Only units near the camera's focus are posed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.UnitConfig)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local NinjaRun = {}

local ANIMATION = "NinjaRun"
local RANGE = 260 -- studs from the camera focus within which units are posed
local RUN_SPEED = 2 -- studs per second; moving faster than this counts as running
local BLEND_RATE = 8 -- how quickly the pose eases between standing and running
local STRIDES_PER_STUD = 0.3 -- leg cycles per stud travelled

-- Running pose, in degrees, in the torso's own axes (X right, Y up, -Z forward).
local LEAN = 40 -- whole body tips forward
local HEAD_UP = 32 -- head tilts back so the face looks ahead
local ARMS_BACK = 70 -- arms swept straight back
local ARMS_OUT = 12
local LEG_FORWARD = 30 -- keeps the feet under the leaning body
local LEG_SWING = 50

local JOINTS = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

type Rig = {
	root: BasePart,
	motors: { [string]: Motor6D },
	frames: { [string]: CFrame }, -- each joint's C0 rotation, so poses can be written in torso axes
	lastPosition: Vector3,
	speed: number,
	blend: number,
	phase: number,
}

local rigs: { [Model]: Rig } = {}
local waiting: { [Model]: boolean } = {} -- models whose parts haven't all arrived yet

local function usesNinjaRun(model: Instance): boolean
	local def = UnitConfig[model:GetAttribute("UnitType")]
	return def ~= nil and def.animation == ANIMATION
end

-- Collects the rig's joints. Returns false if some haven't replicated yet.
local function tryAdd(model: Model): boolean
	local root = model.PrimaryPart
	if not root then
		return false
	end
	local motors, frames, found = {}, {}, 0
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and table.find(JOINTS, item.Name) and not motors[item.Name] then
			motors[item.Name] = item
			frames[item.Name] = item.C0.Rotation
			found += 1
		end
	end
	if found < #JOINTS then
		return false
	end
	rigs[model] = {
		root = root,
		motors = motors,
		frames = frames,
		lastPosition = root.Position,
		speed = 0,
		blend = 0,
		phase = 0,
	}
	return true
end

local function onUnitAdded(model: Instance)
	if model:IsA("Model") and usesNinjaRun(model) and not tryAdd(model) then
		waiting[model] = true
	end
end

-- Turns `offset` (a pose in the joint's parent part's axes, about the joint) into the
-- joint's Transform.
local function pose(rig: Rig, joint: string, offset: CFrame)
	local frame = rig.frames[joint]
	rig.motors[joint].Transform = frame:Inverse() * offset * frame
end

local function step(deltaTime: number)
	if deltaTime <= 0 then
		return
	end
	for model in waiting do
		if model.Parent == nil or tryAdd(model) then
			waiting[model] = nil
		end
	end

	local focus = CameraController.getFocus()
	local rad = math.rad
	for _, rig in rigs do
		local position = rig.root.Position
		local moved = Vector3.new(position.X - rig.lastPosition.X, 0, position.Z - rig.lastPosition.Z).Magnitude
		rig.lastPosition = position
		-- Smoothed, because replicated positions arrive in small uneven steps.
		rig.speed += (moved / deltaTime - rig.speed) * math.min(1, deltaTime * 12)
		local target = if rig.speed > RUN_SPEED then 1 else 0
		rig.blend += (target - rig.blend) * math.min(1, deltaTime * BLEND_RATE)
		rig.phase = (rig.phase + moved * STRIDES_PER_STUD) % 1

		local dx, dz = position.X - focus.X, position.Z - focus.Z
		if dx * dx + dz * dz < RANGE * RANGE then
			local b = rig.blend
			local swing = math.sin(rig.phase * math.pi * 2)
			local bob = math.abs(math.cos(rig.phase * math.pi * 2)) * 0.15
			pose(rig, "RootJoint", CFrame.new(0, (bob - 0.35) * b, -0.25 * b) * CFrame.Angles(rad(-LEAN) * b, 0, 0))
			pose(rig, "Neck", CFrame.Angles(rad(HEAD_UP) * b, 0, 0))
			pose(rig, "Right Shoulder", CFrame.Angles(rad(-ARMS_BACK + 4 * swing) * b, 0, rad(ARMS_OUT) * b))
			pose(rig, "Left Shoulder", CFrame.Angles(rad(-ARMS_BACK - 4 * swing) * b, 0, rad(-ARMS_OUT) * b))
			pose(rig, "Right Hip", CFrame.Angles(rad(LEG_FORWARD + LEG_SWING * swing) * b, 0, 0))
			pose(rig, "Left Hip", CFrame.Angles(rad(LEG_FORWARD - LEG_SWING * swing) * b, 0, 0))
		end
	end
end

function NinjaRun.start()
	local unitsFolder = workspace:WaitForChild("Units")
	for _, model in unitsFolder:GetChildren() do
		onUnitAdded(model)
	end
	unitsFolder.ChildAdded:Connect(onUnitAdded)
	unitsFolder.ChildRemoved:Connect(function(model)
		rigs[model] = nil
		waiting[model] = nil
	end)
	RunService.PreSimulation:Connect(step)
end

return NinjaRun
