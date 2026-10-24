--[[
	ResourceBillboards
	Themed info boards over every resource point (the corner shrines and the centre spring) and
	every resource node (the Ryo and Chakra stations). Ryo boards are gold, Chakra boards are
	blue, and the shrines, which pay both, run from gold into blue. Each board is a hanging scroll:
	wooden rods with gold caps top and bottom, a round emblem with the place's kanji, its name,
	what it pays, its level and status, and an UPGRADE button.

	Boards are made on this computer, in PlayerGui and adorned to each place's LabelAnchor, so the
	button can be clicked; they only show when the camera is within VIEW_DISTANCE studs. They
	update themselves when the place's attributes change (Level, Remaining, OwnerSlot...).

	The button is not wired to anything yet: it fires ResourceBillboards.UpgradeRequested with
	the place's model, for the upgrade system to connect to later.

	For the UI team: to replace the look, design a BillboardGui named "ResourceBillboard" and put
	it in ReplicatedStorage.Assets.UI. Name its parts Body (a Frame; its UIGradient and UIStroke
	get the theme colours), Emblem, Title, Rate, Status (TextLabels) and UpgradeButton (a
	GuiButton). This module then clones yours instead of building this one.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceBillboards = {}

local upgradeRequested = Instance.new("BindableEvent")
-- Fires with the model of the place whose UPGRADE button was pressed.
ResourceBillboards.UpgradeRequested = upgradeRequested.Event

local VIEW_DISTANCE = 170 -- boards appear when the camera is this close (studs)
local WOOD = Color3.fromRGB(74, 46, 26)
local GOLD = Color3.fromRGB(240, 196, 80)

local THEMES = {
	Ryo = {
		top = Color3.fromRGB(255, 226, 128),
		bottom = Color3.fromRGB(198, 138, 36),
		trim = Color3.fromRGB(112, 70, 12),
		text = Color3.fromRGB(58, 32, 6),
		button = Color3.fromRGB(150, 92, 18),
	},
	Chakra = {
		top = Color3.fromRGB(144, 222, 255),
		bottom = Color3.fromRGB(32, 94, 204),
		trim = Color3.fromRGB(14, 40, 112),
		text = Color3.fromRGB(255, 255, 255),
		button = Color3.fromRGB(22, 64, 160),
	},
	Shrine = {
		top = Color3.fromRGB(255, 214, 112),
		bottom = Color3.fromRGB(50, 118, 220),
		trim = Color3.fromRGB(74, 40, 66),
		text = Color3.fromRGB(255, 255, 255),
		button = Color3.fromRGB(96, 52, 104),
	},
}

local boards: { [Instance]: BillboardGui } = {}
local playerGui: PlayerGui

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function rounded(parent: Instance, radius: UDim)
	make("UICorner", { CornerRadius = radius }, parent)
end

-- A wooden scroll rod with gold end caps.
local function rod(parent: Instance, name: string, y: number)
	local bar = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, 12, 0, 9),
		BackgroundColor3 = WOOD,
		ZIndex = 3,
	}, parent)
	rounded(bar, UDim.new(0, 4))
	for _, x in { 0, 1 } do
		local cap = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromOffset(13, 13),
			BackgroundColor3 = GOLD,
			ZIndex = 4,
		}, bar)
		rounded(cap, UDim.new(1, 0))
	end
end

-- The placeholder board, built in code so it works with no setup.
local function buildPlaceholder(): BillboardGui
	local gui = make("BillboardGui", { Name = "ResourceBillboard", Size = UDim2.fromOffset(260, 132) })
	rod(gui, "TopRod", 5)
	rod(gui, "BottomRod", 127)

	local body = make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 1, -12),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, gui)
	rounded(body, UDim.new(0, 6))
	make("UIGradient", { Rotation = 90 }, body)
	make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	-- A thin inner border, like the edge of a painted scroll.
	local inner = make("Frame", {
		Name = "InnerBorder",
		Position = UDim2.fromOffset(5, 8),
		Size = UDim2.new(1, -10, 1, -16),
		BackgroundTransparency = 1,
	}, body)
	rounded(inner, UDim.new(0, 4))
	make("UIStroke", { Name = "InnerStroke", Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)

	-- Round emblem with the place's kanji.
	local emblemBack = make("Frame", {
		Name = "EmblemBack",
		Position = UDim2.fromOffset(12, 14),
		Size = UDim2.fromOffset(50, 50),
	}, body)
	rounded(emblemBack, UDim.new(1, 0))
	make("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, emblemBack)
	make("TextLabel", {
		Name = "Emblem",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
	}, emblemBack)

	local function label(name: string, y: number, height: number, font: Enum.Font)
		return make("TextLabel", {
			Name = name,
			Position = UDim2.fromOffset(72, y),
			Size = UDim2.new(1, -82, 0, height),
			BackgroundTransparency = 1,
			Font = font,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, body)
	end
	label("Title", 10, 26, Enum.Font.Bangers)
	label("Rate", 38, 17, Enum.Font.GothamBold)
	label("Status", 56, 14, Enum.Font.GothamMedium)

	make("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(12, 76),
		Size = UDim2.new(1, -24, 0, 2),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, body)

	-- Level pips (filled up to the place's Level).
	local pips = make("Frame", {
		Name = "LevelPips",
		Position = UDim2.fromOffset(14, 88),
		Size = UDim2.fromOffset(90, 18),
		BackgroundTransparency = 1,
	}, body)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }, pips)
	for i = 1, 3 do
		local pip = make("Frame", { Name = "Pip" .. i, Size = UDim2.fromOffset(12, 12), Rotation = 45, LayoutOrder = i }, pips)
		make("UIStroke", { Color = GOLD, Thickness = 1.5 }, pip)
	end

	local button = make("TextButton", {
		Name = "UpgradeButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 84),
		Size = UDim2.fromOffset(112, 26),
		Font = Enum.Font.GothamBlack,
		Text = "▲ UPGRADE",
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
	}, body)
	rounded(button, UDim.new(0, 6))
	make("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	return gui
end

local function newBoard(): BillboardGui
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local uiFolder = assets and assets:FindFirstChild("UI")
	local template = uiFolder and uiFolder:FindFirstChild("ResourceBillboard")
	return if template and template:IsA("BillboardGui") then template:Clone() else buildPlaceholder()
end

-- Which theme a place uses, its emblem kanji, and the lines of text it shows.
local function describe(model: Instance)
	local level = model:GetAttribute("Level") or 1
	local maxLevel = model:GetAttribute("MaxLevel") or 3
	if CollectionService:HasTag(model, "ResourcePOI") then
		local owner = model:GetAttribute("OwnerSlot") or 0
		return {
			theme = THEMES.Shrine,
			emblem = if model:GetAttribute("PoiId") == "Center" then "泉" else "社",
			title = model:GetAttribute("DisplayName") or model.Name,
			rate = string.format("+%d Ryo   +%d Chakra  / sec", model:GetAttribute("RyoPerSecond") or 0, model:GetAttribute("ChakraPerSecond") or 0),
			status = string.format("Lv %d/%d   %s", level, maxLevel, if owner == 0 then "Unclaimed" else "Held by player " .. owner),
			level = level,
			maxLevel = maxLevel,
		}
	end
	local resource = model:GetAttribute("ResourceType") or "Ryo"
	return {
		theme = THEMES[resource] or THEMES.Ryo,
		emblem = if resource == "Chakra" then "気" else "両",
		title = model:GetAttribute("DisplayName") or model.Name,
		rate = string.format("+%s %s / sec per unit", tostring(model:GetAttribute("GatherRatePerUnit") or 1), resource),
		status = string.format("Lv %d/%d   %d / %d left", level, maxLevel, model:GetAttribute("Remaining") or 0, model:GetAttribute("Capacity") or 0),
		level = level,
		maxLevel = maxLevel,
	}
end

local function refresh(model: Instance, gui: BillboardGui)
	local info = describe(model)
	local theme = info.theme
	local body = gui:FindFirstChild("Body", true)
	if body then
		local gradient = body:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(theme.top, theme.bottom)
		end
		local outline = body:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Color = theme.trim
		end
		local innerStroke = body:FindFirstChild("InnerStroke", true)
		if innerStroke then
			innerStroke.Color = theme.trim
		end
		local divider = body:FindFirstChild("Divider")
		if divider then
			divider.BackgroundColor3 = theme.trim
		end
		local emblemBack = body:FindFirstChild("EmblemBack")
		if emblemBack then
			emblemBack.BackgroundColor3 = theme.trim
		end
		local pips = body:FindFirstChild("LevelPips")
		if pips then
			for i = 1, 3 do
				local pip = pips:FindFirstChild("Pip" .. i)
				if pip then
					pip.Visible = i <= info.maxLevel
					pip.BackgroundColor3 = if i <= info.level then GOLD else theme.trim
				end
			end
		end
	end
	local texts = { Emblem = info.emblem, Title = string.upper(info.title), Rate = info.rate, Status = info.status }
	for name, text in texts do
		local textLabel = gui:FindFirstChild(name, true)
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.Text = text
			if name ~= "Emblem" then
				textLabel.TextColor3 = theme.text
			end
		end
	end
	local button = gui:FindFirstChild("UpgradeButton", true)
	if button and button:IsA("GuiButton") then
		button.BackgroundColor3 = theme.button
		if button:IsA("TextButton") then
			button.Text = if info.level >= info.maxLevel then "MAX LEVEL" else "▲ UPGRADE"
		end
	end
end

local function addBoard(model: Instance)
	local anchor = model:FindFirstChild("LabelAnchor")
	if boards[model] or not (anchor and anchor:IsA("BasePart")) then
		return
	end
	local gui = newBoard()
	gui.Name = "Board_" .. model.Name
	gui.Adornee = anchor
	gui.MaxDistance = VIEW_DISTANCE
	gui.LightInfluence = 0
	gui.Active = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	boards[model] = gui
	refresh(model, gui)
	model.AttributeChanged:Connect(function()
		refresh(model, gui)
	end)
	local button = gui:FindFirstChild("UpgradeButton", true)
	if button and button:IsA("GuiButton") then
		button.Activated:Connect(function()
			upgradeRequested:Fire(model)
		end)
	end
	gui.Parent = playerGui
end

local function removeBoard(model: Instance)
	local gui = boards[model]
	if gui then
		gui:Destroy()
		boards[model] = nil
	end
end

function ResourceBillboards.start()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, tag in { "ResourcePOI", "ResourceNode" } do
		for _, model in CollectionService:GetTagged(tag) do
			addBoard(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(addBoard)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(removeBoard)
	end
end

return ResourceBillboards
