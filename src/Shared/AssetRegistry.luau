--[[
	AssetRegistry
	Turns a unit type into a 3D model. This is the only code that knows where art lives.

	For each unit type it looks for a Model named UnitConfig[type].asset inside
	ReplicatedStorage.Assets.Units. If the art team has put one there (for example a
	Meshy import), that model is used. Otherwise a simple placeholder is built.
	Art can therefore be swapped in without changing any gameplay code.

	Rules for a custom unit model (also in CLAUDE.md, "Adding a unit model"):
	  - A Model containing a part named "Root", centred on the unit's feet.
	  - The unit faces the Root's front (-Z, the "Front" face in Studio).
	  - Parts named "TeamColor" are painted in the owning player's colour.
	  - Roughly the size given by the unit's radius and height in UnitConfig.
	  - No scripts (they are deleted) and no Humanoid (use an AnimationController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetRegistry = {}

local TEAM_COLOR_NAMES = { TeamColor = true, TeamBase = true }

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if color then
		part.Color = color
	end
	return part
end

-- A simple stand-in: a team-coloured body with a dark visor on the front, so you can
-- see which way the unit faces.
local function buildPlaceholder(def): Model
	local model = Instance.new("Model")
	local look = def.placeholder or {}
	local size = look.bodySize or Vector3.new(2, 4, 2)

	local root = newPart("Root", Vector3.new(1, 1, 1), CFrame.new())
	root.Transparency = 1
	root.Parent = model

	local body
	if look.shape == "Cylinder" then
		-- Roblox cylinders lie along their X axis, so stand it upright.
		body = newPart("TeamColor", Vector3.new(size.Y, size.X, size.X),
			CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)))
		body.Shape = Enum.PartType.Cylinder
	else
		body = newPart("TeamColor", size, CFrame.new(0, size.Y / 2, 0))
	end
	body.Parent = model

	local visor = newPart("Visor", Vector3.new(size.X * 0.7, size.Y * 0.15, 0.3),
		CFrame.new(0, size.Y * 0.78, -size.Z / 2 - 0.1), Color3.fromRGB(25, 25, 30))
	visor.Parent = model

	return model
end

-- A thin disc in team colour under every unit, so ownership stays readable even when
-- a unit's own model can't be recoloured (for example, textured meshes).
local function addTeamBase(model: Model, root: BasePart, radius: number)
	local disc = newPart("TeamBase", Vector3.new(0.12, radius * 2, radius * 2),
		root.CFrame * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)))
	disc.Shape = Enum.PartType.Cylinder
	disc.Transparency = 0.35
	disc.CastShadow = false
	disc.Parent = model
end

-- Parts joined by Motor6D joints belong to an animated rig and keep those joints.
-- (Checked by looking at the joints themselves: part:GetJoints() only works once the
-- model is in the world, and models are prepared before that.)
local function getRiggedParts(model: Model): { [BasePart]: boolean }
	local rigged = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") then
			if item.Part0 then
				rigged[item.Part0] = true
			end
			if item.Part1 then
				rigged[item.Part1] = true
			end
		end
	end
	return rigged
end

-- Makes any unit model safe for the movement system: one anchored Root that the
-- server moves, every other part welded to it, and nothing that collides with the
-- world or reacts to physics.
local function prepare(model: Model, def, teamColor: Color3)
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		-- No Root: make one at the bottom-centre of the model.
		local boxCFrame, boxSize = model:GetBoundingBox()
		root = newPart("Root", Vector3.new(1, 1, 1), CFrame.new(boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0)))
		root.Transparency = 1
		root.Parent = model
	end
	model.PrimaryPart = root
	addTeamBase(model, root, def.radius)

	local rigged = getRiggedParts(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = item == root
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = item ~= root -- clicks hit the visible parts, not the invisible Root
			item.Massless = true
			if TEAM_COLOR_NAMES[item.Name] then
				item.Color = teamColor
			end
			-- Animated rigs keep their own joints; everything else is welded to the Root.
			if item ~= root and not rigged[item] then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = item
				weld.Parent = item
			end
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy() -- unit models never carry their own code
		end
	end
end

-- Builds the model for one unit of `unitType`, painted in `teamColor`.
-- The model is not parented; the caller positions it and puts it in the world.
function AssetRegistry.createUnitModel(unitType: string, def, teamColor: Color3): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local unitModels = assets and assets:FindFirstChild("Units")
	local template = unitModels and def.asset and unitModels:FindFirstChild(def.asset)

	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = buildPlaceholder(def)
	end
	model.Name = unitType
	prepare(model, def, teamColor)
	return model
end

return AssetRegistry
