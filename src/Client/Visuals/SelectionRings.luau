--[[
	SelectionRings
	Draws a ring under each selected unit. Rings are adornments created on your computer
	only (other players never see your selection), and they follow the unit by themselves
	because they are attached to its Root part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.UnitConfig)

local SelectionRings = {}

local RING_COLOR = Color3.fromRGB(90, 255, 140)
local RING_WIDTH = 0.35

local rings: { [Model]: CylinderHandleAdornment } = {}
local container: Folder? = nil

local function getContainer(): Folder
	if not container then
		local folder = Instance.new("Folder")
		folder.Name = "SelectionRings"
		folder.Parent = workspace.CurrentCamera
		container = folder
	end
	return container :: Folder
end

function SelectionRings.show(model: Model)
	local root = model.PrimaryPart
	if rings[model] or not root then
		return
	end
	local def = UnitConfig[model:GetAttribute("UnitType")]
	local radius = (if def then def.radius else 1.5) + 0.6

	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = model.Name
	ring.Adornee = root
	ring.Radius = radius
	ring.InnerRadius = radius - RING_WIDTH
	ring.Height = 0.1
	-- Adornment cylinders point along Z; tip it flat and lift it just above the ground.
	ring.CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Color3 = RING_COLOR
	ring.AlwaysOnTop = false
	ring.Parent = getContainer()
	rings[model] = ring
end

function SelectionRings.hide(model: Model)
	local ring = rings[model]
	if ring then
		ring:Destroy()
		rings[model] = nil
	end
end

return SelectionRings
