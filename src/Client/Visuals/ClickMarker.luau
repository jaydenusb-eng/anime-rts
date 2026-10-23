--[[
	ClickMarker
	A short-lived ring where you right-clicked, so you can see the order was sent.
	Only you see it: it is created on your computer, under the camera.
]]

local TweenService = game:GetService("TweenService")

local ClickMarker = {}

local COLOR = Color3.fromRGB(90, 255, 140)
local DURATION = 0.45

function ClickMarker.play(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "MoveMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Material = Enum.Material.Neon
	marker.Color = COLOR
	marker.Transparency = 0.2
	marker.Size = Vector3.new(0.1, 4, 4)
	-- Cylinders lie along X; tip it so the flat face points up.
	marker.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = workspace.CurrentCamera

	local tweenInfo = TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(marker, tweenInfo, { Size = Vector3.new(0.1, 0.5, 0.5), Transparency = 1 }):Play()
	task.delay(DURATION, marker.Destroy, marker)
end

return ClickMarker
