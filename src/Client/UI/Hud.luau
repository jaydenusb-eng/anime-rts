--[[
	Hud
	Placeholder heads-up display: the selected-unit count, a controls hint, and a message
	line for feedback from the server. It is built in code so it works with no setup.

	For the UI team: to replace the look, design a ScreenGui named "RTSHud" in Studio and
	put it in ReplicatedStorage.Assets.UI. It needs TextLabels named "SelectedCount" and
	"Message" somewhere inside it. This module then clones yours instead of building this one.
	Any panel that should stop clicks from reaching the world must have Active = true.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = {}

local TEXT_COLOR = Color3.fromRGB(235, 240, 248)
local HINT_COLOR = Color3.fromRGB(150, 160, 178)
local MESSAGE_COLOR = Color3.fromRGB(255, 196, 90)

local selectedLabel: TextLabel? = nil
local messageLabel: TextLabel? = nil
local messageVersion = 0

local function makeLabel(name: string, text: string, textSize: number, color: Color3, order: number, parent: Instance)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.BuilderSansMedium
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
end

local function buildPlaceholder(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RTSHud"

	local panel = Instance.new("Frame")
	panel.Name = "SelectionPanel"
	panel.Active = true -- swallows clicks so they don't also reach the world (see InputGuard)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	makeLabel("SelectedCount", "Selected: 0", 22, TEXT_COLOR, 1, panel)
	makeLabel("Hint", "Left-click or drag: select   Shift: add/remove\nRight-click: move   WASD: pan   Wheel: zoom",
		14, HINT_COLOR, 2, panel)
	makeLabel("Message", "", 16, MESSAGE_COLOR, 3, panel)
	return gui
end

function Hud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local uiFolder = assets and assets:FindFirstChild("UI")
	local template = uiFolder and uiFolder:FindFirstChild("RTSHud")
	local gui = if template and template:IsA("ScreenGui") then template:Clone() else buildPlaceholder()
	gui.ResetOnSpawn = false
	selectedLabel = gui:FindFirstChild("SelectedCount", true) :: TextLabel?
	messageLabel = gui:FindFirstChild("Message", true) :: TextLabel?
	gui.Parent = playerGui
end

function Hud.setSelectedCount(count: number)
	if selectedLabel then
		selectedLabel.Text = "Selected: " .. count
	end
end

-- Shows `text` on the message line for a few seconds.
function Hud.showMessage(text: string, seconds: number?)
	local label = messageLabel
	if not label then
		return
	end
	messageVersion += 1
	local version = messageVersion
	label.Text = text
	task.delay(seconds or 3, function()
		if messageVersion == version then
			label.Text = ""
		end
	end)
end

return Hud
