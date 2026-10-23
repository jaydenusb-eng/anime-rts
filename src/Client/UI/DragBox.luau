--[[
	DragBox
	The rectangle drawn while you drag to select. Its ScreenGui ignores the top-bar inset,
	so its coordinates match UserInputService:GetMouseLocation() exactly.
]]

local Players = game:GetService("Players")

local DragBox = {}

local BOX_COLOR = Color3.fromRGB(90, 255, 140)

local frame: Frame? = nil

local function getFrame(): Frame
	if frame then
		return frame
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RTSDragBox"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundColor3 = BOX_COLOR
	box.BackgroundTransparency = 0.85
	box.BorderSizePixel = 0
	box.Visible = false
	box.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = BOX_COLOR
	stroke.Thickness = 1
	stroke.Parent = box

	frame = box
	return box
end

function DragBox.show(cornerA: Vector2, cornerB: Vector2)
	local box = getFrame()
	box.Position = UDim2.fromOffset(math.min(cornerA.X, cornerB.X), math.min(cornerA.Y, cornerB.Y))
	box.Size = UDim2.fromOffset(math.abs(cornerA.X - cornerB.X), math.abs(cornerA.Y - cornerB.Y))
	box.Visible = true
end

function DragBox.hide()
	if frame then
		frame.Visible = false
	end
end

return DragBox
