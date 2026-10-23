--[[
	CameraController
	Overhead RTS camera. The camera looks at a "focus" point on the ground from a fixed
	angle. WASD or the arrow keys move the focus, the mouse wheel zooms, and the focus is
	kept inside the map's play area. Tuning lives in Shared/Config/CameraConfig.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)
local InputConfig = require(Shared.Config.InputConfig)
local MapInfo = require(Shared.MapInfo)
local InputGuard = require(script.Parent.InputGuard)

local CameraController = {}

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local focus = Vector3.zero
local zoom = CameraConfig.DefaultZoom
local targetZoom = CameraConfig.DefaultZoom
-- Keys held down that the game world may use. Keys Roblox already used (for example
-- typing in chat) never get in here, so they can't pan the camera.
local heldKeys: { [Enum.KeyCode]: boolean } = {}

local function isAnyKeyHeld(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if heldKeys[key] then
			return true
		end
	end
	return false
end

-- Flat directions for "up" and "right" on screen, from the camera's compass direction.
local function getPanAxes(): (Vector3, Vector3)
	local yaw = math.rad(CameraConfig.Yaw)
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	return forward, Vector3.new(-forward.Z, 0, forward.X)
end

local function clampFocus(point: Vector3): Vector3
	local minCorner, maxCorner = MapInfo.getPlayArea()
	local padding = CameraConfig.BoundsPadding
	return Vector3.new(
		math.clamp(point.X, minCorner.X - padding, maxCorner.X + padding),
		minCorner.Y,
		math.clamp(point.Z, minCorner.Z - padding, maxCorner.Z + padding)
	)
end

local function update(deltaTime: number)
	if not InputGuard.isTyping() then
		local forward, right = getPanAxes()
		local direction = Vector3.zero
		if isAnyKeyHeld(InputConfig.PanUp) then
			direction += forward
		end
		if isAnyKeyHeld(InputConfig.PanDown) then
			direction -= forward
		end
		if isAnyKeyHeld(InputConfig.PanRight) then
			direction += right
		end
		if isAnyKeyHeld(InputConfig.PanLeft) then
			direction -= right
		end
		if direction.Magnitude > 0 then
			focus += direction.Unit * (CameraConfig.PanSpeed * zoom * deltaTime)
		end
	end
	focus = clampFocus(focus)
	zoom += (targetZoom - zoom) * math.min(1, deltaTime * CameraConfig.ZoomSmoothing)

	local pitch = math.rad(CameraConfig.Pitch)
	local forward = getPanAxes()
	local offset = -forward * (math.cos(pitch) * zoom) + Vector3.new(0, math.sin(pitch) * zoom, 0)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end

local function focusOnStart()
	local slot = localPlayer:GetAttribute("Slot")
	local start = if type(slot) == "number" and slot > 0 then MapInfo.getStartCFrame(slot) else nil
	focus = clampFocus(if start then start.Position else MapInfo.getCenter())
end

function CameraController.getFocus(): Vector3
	return focus
end

function CameraController.getZoom(): number
	return zoom
end

-- Points the camera at `point` (for the minimap and "jump to base" later).
function CameraController.setFocus(point: Vector3)
	focus = clampFocus(point)
end

function CameraController.start()
	MapInfo.waitForMap()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CameraConfig.FieldOfView
	focusOnStart()
	localPlayer:GetAttributeChangedSignal("Slot"):Connect(focusOnStart)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard and InputGuard.worldMayUse(gameProcessed) then
			heldKeys[input.KeyCode] = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		heldKeys[input.KeyCode] = nil
	end)
	-- Keys released while the game window is in the background never report it, so forget them.
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(heldKeys)
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and InputGuard.worldMayUse(gameProcessed) then
			local zoomed = targetZoom - input.Position.Z * CameraConfig.ZoomStep
			targetZoom = math.clamp(zoomed, CameraConfig.MinZoom, CameraConfig.MaxZoom)
		end
	end)

	-- Runs right after Roblox's own camera code each frame, so this camera has the final say.
	RunService:BindToRenderStep("RTSCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
