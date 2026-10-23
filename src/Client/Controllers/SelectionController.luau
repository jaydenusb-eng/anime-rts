--[[
	SelectionController
	Left-click selects one of your units. Dragging draws a box and selects all of your
	units inside it. Hold Shift to add to the selection instead of replacing it;
	Shift-clicking a unit that is already selected removes it. Clicking empty ground
	without Shift clears the selection.

	Selection only exists on your computer: it decides which unit ids go into your next
	order. The server re-checks ownership when the order arrives.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.InputConfig)

local Client = script.Parent.Parent
local InputGuard = require(script.Parent.InputGuard)
local UnitTracker = require(script.Parent.UnitTracker)
local Hud = require(Client.UI.Hud)
local DragBox = require(Client.UI.DragBox)
local SelectionRings = require(Client.Visuals.SelectionRings)

local SelectionController = {}

local camera = workspace.CurrentCamera
local selected: { [Model]: boolean } = {}
local selectedCount = 0
local dragStart: Vector2? = nil
local isDragging = false
local unitRayParams = RaycastParams.new()
unitRayParams.FilterType = Enum.RaycastFilterType.Include

local function isAddKeyDown(): boolean
	for _, key in InputConfig.AddToSelection do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function add(model: Model)
	if not selected[model] then
		selected[model] = true
		selectedCount += 1
		SelectionRings.show(model)
	end
end

local function remove(model: Model)
	if selected[model] then
		selected[model] = nil
		selectedCount -= 1
		SelectionRings.hide(model)
	end
end

local function clear()
	for model in selected do
		remove(model)
	end
end

-- Where a unit appears on screen, or nil if it is off screen.
local function getScreenPoint(model: Model): Vector2?
	local center = UnitTracker.getCenter(model)
	if not center then
		return nil
	end
	local screen, onScreen = camera:WorldToViewportPoint(center)
	if not onScreen then
		return nil
	end
	return Vector2.new(screen.X, screen.Y)
end

-- Your unit under the mouse: an exact hit first, otherwise the nearest one within a few pixels.
local function pickOwnUnit(screenPoint: Vector2): Model?
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, unitRayParams)
	if hit then
		local model = UnitTracker.getUnitFromPart(hit.Instance)
		if model and UnitTracker.isOwn(model) then
			return model
		end
	end
	local best, bestDistance = nil, InputConfig.ClickPickRadius
	for _, model in UnitTracker.getOwnUnits() do
		local point = getScreenPoint(model)
		if point and (point - screenPoint).Magnitude < bestDistance then
			best, bestDistance = model, (point - screenPoint).Magnitude
		end
	end
	return best
end

local function clickSelect(screenPoint: Vector2, additive: boolean)
	local model = pickOwnUnit(screenPoint)
	if not additive then
		clear()
	end
	if model and additive and selected[model] then
		remove(model)
	elseif model then
		add(model)
	end
end

local function boxSelect(cornerA: Vector2, cornerB: Vector2, additive: boolean)
	local minX, maxX = math.min(cornerA.X, cornerB.X), math.max(cornerA.X, cornerB.X)
	local minY, maxY = math.min(cornerA.Y, cornerB.Y), math.max(cornerA.Y, cornerB.Y)
	if not additive then
		clear()
	end
	for _, model in UnitTracker.getOwnUnits() do
		local point = getScreenPoint(model)
		if point and point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY then
			add(model)
		end
	end
end

-- Ids of the selected units, for building an order.
function SelectionController.getSelectedIds(): { number }
	local ids = {}
	for model in selected do
		local id = model:GetAttribute("UnitId")
		if type(id) == "number" then
			table.insert(ids, id)
		end
	end
	return ids
end

function SelectionController.getCount(): number
	return selectedCount
end

function SelectionController.start()
	unitRayParams.FilterDescendantsInstances = { UnitTracker.getFolder() }

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and InputGuard.worldMayUse(gameProcessed) then
			dragStart = UserInputService:GetMouseLocation()
			isDragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local start = dragStart
		if start and input.UserInputType == Enum.UserInputType.MouseMovement then
			local current = UserInputService:GetMouseLocation()
			if not isDragging and (current - start).Magnitude >= InputConfig.DragThreshold then
				isDragging = true
			end
			if isDragging then
				DragBox.show(start, current)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local start = dragStart
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not start then
			return
		end
		local finish = UserInputService:GetMouseLocation()
		if isDragging then
			boxSelect(start, finish, isAddKeyDown())
		else
			clickSelect(finish, isAddKeyDown())
		end
		dragStart = nil
		isDragging = false
		DragBox.hide()
		Hud.setSelectedCount(selectedCount)
	end)

	-- A unit that leaves the world (removed, or its owner left) drops out of the selection.
	UnitTracker.onRemoved(function(model)
		if selected[model] then
			remove(model)
			Hud.setSelectedCount(selectedCount)
		end
	end)
	Hud.setSelectedCount(0)
end

return SelectionController
