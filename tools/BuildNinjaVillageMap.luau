--[[
	BuildNinjaVillageMap
	Builds the 1v1 "Hidden Valley" map (Naruto-style blockout) into Workspace.Map.
	Safe to rerun: the old Workspace.Map is removed first, so the map is never doubled.

	Run from the Studio command bar (Edit mode):
	  require(game.ServerStorage.MapTools.BuildNinjaVillageMap:Clone()).build()
	(:Clone() makes Studio use the newest source instead of a cached copy.)

	Coordinates below are "layout units": the reference top-down picture traced at
	1.2 units per pixel, so the playable area is -270..270 on both axes. SCALE turns
	layout units into studs (2 = twice the width and length). Prop sizes (walls'
	thickness, rocks, buildings) are always written in studs, so they stay unit-sized
	whatever SCALE is. +X is east, -Z is north (the top of the picture). Ground level is Y = 0.
	  Ground     floor plus flush overlays (riverbed, arena, spawn pads, trails)
	  Obstacles  everything units path around (walls, rocks, buildings, statue, groves)
	  Boundary   cliffs and the sealed village gate around the edge
	  Decor      roofs, banners, canopies, cliff-top monuments: no collision, no queries
	  Markers    PlayArea and StartPoints.Slot1 (north compound) / Slot2 (south fortress)
	  POIs       resource point placeholders, one Model each, tagged "ResourcePOI" (see resourcePOI)
	  ResourceNodes  gatherable Ryo / Chakra structures, tagged "ResourceNode" (see resourceNode)
	  CommandBases   each team's headquarters, door and build sockets, tagged "CommandBase" (see commandBase)

	The two halves are balanced as mirror pairs across the river (north <-> south):
	each base has the same number of buildings, lanterns and a large hall, and the
	neutral ground has matching groves, outcrops and ramen stands on both sides.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local BuildNinjaVillageMap = {}

local SCALE = 2 -- studs per layout unit
local EDGE = 270 * SCALE -- studs from the centre to the inner cliff face
local CLIFF_HEIGHT = 30
local CLIFF_THICK = 40

local M = Enum.Material
local C = {
	grass = Color3.fromRGB(118, 132, 78),
	grassDark = Color3.fromRGB(84, 100, 62),
	dirt = Color3.fromRGB(148, 118, 82),
	riverbed = Color3.fromRGB(178, 120, 66),
	scar = Color3.fromRGB(112, 94, 72),
	cliff = Color3.fromRGB(96, 90, 82),
	cliffDark = Color3.fromRGB(76, 72, 68),
	stone = Color3.fromRGB(142, 138, 128),
	ruin = Color3.fromRGB(104, 104, 110),
	wood = Color3.fromRGB(116, 82, 52),
	woodDark = Color3.fromRGB(82, 58, 38),
	bone = Color3.fromRGB(222, 212, 184),
	water = Color3.fromRGB(72, 118, 134),
	leaf = Color3.fromRGB(64, 98, 56),
	leafDark = Color3.fromRGB(48, 76, 46),
	bamboo = Color3.fromRGB(122, 150, 84),
	plaster = Color3.fromRGB(214, 206, 186),
	sandstone = Color3.fromRGB(196, 170, 124),
	sandstoneDark = Color3.fromRGB(170, 144, 104),
	torii = Color3.fromRGB(150, 58, 44),
	gateRoof = Color3.fromRGB(60, 84, 62),
	ramen = Color3.fromRGB(214, 128, 52),
	metal = Color3.fromRGB(150, 154, 160),
	paper = Color3.fromRGB(238, 228, 198),
	windowDark = Color3.fromRGB(58, 46, 38),
	blossom = Color3.fromRGB(240, 172, 192),
	blossomLight = Color3.fromRGB(250, 206, 218),
	flowerYellow = Color3.fromRGB(236, 200, 82),
	shrub = Color3.fromRGB(74, 112, 60),
	shrubDry = Color3.fromRGB(132, 132, 78),
	cactus = Color3.fromRGB(92, 132, 82),
	palm = Color3.fromRGB(86, 128, 64),
	terracotta = Color3.fromRGB(178, 98, 64),
	gold = Color3.fromRGB(232, 190, 70), -- Ryo
	chakra = Color3.fromRGB(96, 196, 255), -- Chakra glow
	chakraDeep = Color3.fromRGB(40, 120, 220),
	sand = Color3.fromRGB(212, 180, 124),
	poi = Color3.fromRGB(240, 200, 90), -- unclaimed resource point
	-- Team accents: muted versions of the GameConfig.Slots colours.
	north = Color3.fromRGB(70, 110, 170),
	northRoof = Color3.fromRGB(58, 72, 96),
	south = Color3.fromRGB(176, 72, 58),
}

-- Leaf tones for layered canopies, darkest (inner, underside) to lightest (top).
local TREE_TONES = { Color3.fromRGB(38, 66, 40), Color3.fromRGB(52, 90, 50), Color3.fromRGB(70, 116, 60), Color3.fromRGB(98, 144, 76) }
local CHERRY_TONES = { Color3.fromRGB(190, 112, 146), Color3.fromRGB(222, 148, 178), Color3.fromRGB(240, 180, 202), Color3.fromRGB(252, 212, 226) }
local BAMBOO_TONES = { Color3.fromRGB(46, 82, 44), Color3.fromRGB(70, 118, 52), Color3.fromRGB(92, 140, 62), Color3.fromRGB(116, 160, 76) }
local GRASS_TONES = { Color3.fromRGB(96, 128, 62), Color3.fromRGB(118, 150, 74), Color3.fromRGB(138, 168, 86) }
local BAMBOO_LEAF_TONES = { Color3.fromRGB(98, 150, 62), Color3.fromRGB(118, 168, 72), Color3.fromRGB(140, 186, 86) }

-- Coordinates -------------------------------------------------------------------------

local function L(v)
	return v * SCALE
end

-- The layout coordinate that lies `studs` inside the cliff face (for props that hug a cliff).
local function inFromEdge(studs)
	return (EDGE - studs) / SCALE
end

-- A stud position from layout x/z and a height in studs.
local function P(x, y, z)
	return Vector3.new(L(x), y, L(z))
end

local function at(x, y, z, yaw)
	return CFrame.new(L(x), y, L(z)) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- Part helpers ----------------------------------------------------------------------

local function part(parent, name, size, cframe, color, material, shape, className)
	local p = Instance.new(className or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Flat ground overlay whose top is `top` studs above ground level. Overlays stay under
-- 0.1 studs so the navigation's level-ground check never sees a step.
local function groundPatch(parent, name, x, z, sx, sz, color, material, top, yaw)
	return part(parent, name, Vector3.new(sx, 0.2, sz), at(x, top - 0.1, z, yaw), color, material)
end

local function groundStrip(parent, name, x1, z1, x2, z2, width, color, material, top)
	local a, b = P(x1, top - 0.1, z1), P(x2, top - 0.1, z2)
	return part(parent, name, Vector3.new(width, 0.2, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material)
end

local function groundDisc(parent, name, x, z, diameter, color, material, top)
	local cframe = CFrame.new(P(x, top - 0.1, z)) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, name, Vector3.new(0.2, diameter, diameter), cframe, color, material, Enum.PartType.Cylinder)
end

-- A straight wall from (x1, z1) to (x2, z2). `extend` (studs) lengthens it so joined walls meet.
local function wall(parent, name, x1, z1, x2, z2, thick, height, color, material, extend, baseY)
	local y = (baseY or 0) + height / 2
	local a, b = P(x1, y, z1), P(x2, y, z2)
	local size = Vector3.new(thick, height, (b - a).Magnitude + (extend or 0))
	return part(parent, name, size, CFrame.lookAt((a + b) / 2, b), color, material)
end

-- Wall segments along a circle around (cx, cz). Degrees: 0 = east, 90 = south.
local function arcWall(parent, name, cx, cz, radius, fromDeg, toDeg, segments, thick, height, color, material)
	for i = 1, segments do
		local a0 = math.rad(fromDeg + (toDeg - fromDeg) * (i - 1) / segments)
		local a1 = math.rad(fromDeg + (toDeg - fromDeg) * i / segments)
		wall(parent, name .. i,
			cx + math.cos(a0) * radius, cz + math.sin(a0) * radius,
			cx + math.cos(a1) * radius, cz + math.sin(a1) * radius,
			thick, height, color, material, 2)
	end
end

-- A boulder sunk 1 stud into the ground, at a stud position.
local function rockAt(parent, name, sx, sz, w, h, d, yaw, color)
	local cframe = CFrame.new(sx, h / 2 - 1, sz) * CFrame.Angles(0, math.rad(yaw), 0)
	return part(parent, name, Vector3.new(w, h, d), cframe, color or C.cliff, M.Slate)
end

local function rock(parent, name, x, z, w, h, d, yaw, color)
	return rockAt(parent, name, L(x), L(z), w, h, d, yaw, color)
end

-- An upright cylinder centred on `pos` (studs).
local function cylinder(parent, name, pos, diameter, height, color, material)
	local cframe = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, name, Vector3.new(height, diameter, diameter), cframe, color, material, Enum.PartType.Cylinder)
end

local function ball(parent, name, pos, diameter, color, material)
	return part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, material, Enum.PartType.Ball)
end

-- Writes `text` across one face of a part (characters on doors, banners and signs).
local function textOn(target, face, text, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	-- Scaled text tops out at 100px, so size the canvas to make that fill the face's short side.
	gui.PixelsPerStud = 100 / math.min(target.Size.X, target.Size.Y)
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
end

-- A simple clustered canopy: one big ball with smaller lumps around its top and sides and a
-- sunlit crown, in tones from shaded (low lumps) to sunlit (crown). All decor.
local function clusterCanopy(deco, name, centre, radius, tones, rng)
	ball(deco, name, centre, radius * 2, tones[2], M.Grass)
	for i = 1, 6 do
		local a = i * math.pi / 3 + rng:NextNumber(-0.3, 0.3)
		local up = rng:NextNumber(0.1, 0.6)
		local dir = Vector3.new(math.cos(a), up, math.sin(a)).Unit
		ball(deco, name .. "Lump" .. i, centre + dir * radius * 0.75, radius * rng:NextNumber(0.9, 1.15), tones[if up > 0.35 then 3 else 1], M.Grass)
	end
	ball(deco, name .. "Crown", centre + Vector3.new(radius * 0.15, radius * 0.7, -radius * 0.1), radius * 1.1, tones[4], M.Grass)
end

-- Groups parts that sway in the wind. The client's LeafSway controller rocks each tagged model
-- gently around its SwayPivot; SwayAmount is the most it leans, in degrees.
local SWAY_TAG = "SwayingLeaves"

local function swayGroup(deco, name, pivot, amount)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("SwayPivot", pivot)
	model:SetAttribute("SwayAmount", amount)
	CollectionService:AddTag(model, SWAY_TAG)
	model.Parent = deco
	return model
end

-- One bamboo culm like real bamboo: a tall thin stalk with a darker joint ring, and sprays of
-- narrow leaves spiralling up its top half (drooping side sprays, then a crown).
local function bambooStalk(parent, name, foot, height, diameter, leafSize, rng)
	cylinder(parent, name, foot + Vector3.new(0, height / 2, 0), diameter, height, C.bamboo, M.SmoothPlastic)
	cylinder(parent, name .. "Joint", foot + Vector3.new(0, height * rng:NextNumber(0.25, 0.45), 0), diameter * 1.25, 0.35, BAMBOO_TONES[2], M.SmoothPlastic)
	local yaw = rng:NextNumber(0, 2 * math.pi)
	for spray, info in { { 0.58, 3 }, { 0.68, 3 }, { 0.78, 3 }, { 0.88, 3 }, { 1, 3 } } do -- { height up the stalk, leaves }
		local origin = foot + Vector3.new(0, height * info[1], 0)
		local isCrown = info[1] == 1
		for i = 1, info[2] do
			local length = leafSize * rng:NextNumber(0.8, 1.15)
			local leafYaw = yaw + spray * 2.4 + (i - 2) * 0.5 + rng:NextNumber(-0.15, 0.15)
			local droop = if isCrown then rng:NextNumber(-0.35, 0.2) else rng:NextNumber(0.35, 0.8)
			local leaf = CFrame.new(origin) * CFrame.Angles(0, leafYaw, 0) * CFrame.Angles(-droop, 0, 0) * CFrame.new(0, 0, -length / 2)
			part(parent, name .. "Leaf" .. spray .. "_" .. i, Vector3.new(length * 0.14, 0.08, length), leaf, BAMBOO_LEAF_TONES[rng:NextInteger(1, #BAMBOO_LEAF_TONES)], M.SmoothPlastic)
		end
	end
end

-- Builders for repeated props ----------------------------------------------------------

-- A tree at a stud position: a trunk forking into two branches, each ending in a clustered
-- canopy. The trunk goes in `solid` (nil for cliff-top trees); everything else is decor.
local function treeAt(solid, deco, name, pos, scale)
	local s = scale or 1
	local rng = Random.new(math.floor(pos.X * 7 + pos.Z * 13))
	local trunkHeight = 10 * s
	cylinder(solid or deco, name .. "Trunk", pos + Vector3.new(0, trunkHeight / 2, 0), 2.4 * s, trunkHeight, C.woodDark, M.Wood)
	local fork = pos + Vector3.new(0, trunkHeight * 0.75, 0)
	local main = pos + Vector3.new(0, trunkHeight + 3.5 * s, 0)
	local side = pos + Vector3.new(4.2 * s, trunkHeight + 1 * s, -2 * s)
	for i, target in { main, side } do
		part(deco, name .. "Branch" .. i, Vector3.new(1.2 * s, 1.2 * s, (target - fork).Magnitude), CFrame.lookAt((fork + target) / 2, target), C.woodDark, M.Wood)
	end
	local leaves = swayGroup(deco, name .. "Leaves", pos + Vector3.new(0, trunkHeight * 0.5, 0), 3.5)
	clusterCanopy(leaves, name .. "Canopy", main, 5.5 * s, TREE_TONES, rng)
	clusterCanopy(leaves, name .. "CanopySide", side, 3.6 * s, TREE_TONES, rng)
end

local function tree(solid, deco, name, x, z, scale)
	treeAt(solid, deco, name, P(x, 0, z), scale)
end

-- A village house: solid plaster body with a gable roof and accent trim (decor).
-- The ridge runs along the house's local X axis.
local function house(solid, deco, name, x, z, sx, sz, height, yaw, accent, roofColor)
	part(solid, name, Vector3.new(sx, height, sz), at(x, height / 2, z, yaw), C.plaster, M.Plaster)
	part(deco, name .. "Trim", Vector3.new(sx + 0.4, 1, sz + 0.4), at(x, height - 1.5, z, yaw), accent, M.WoodPlanks)
	local rise = sz * 0.4
	local half = sz / 2 + 1
	local base = at(x, height + rise / 2, z, yaw)
	part(deco, name .. "RoofFront", Vector3.new(sx + 3, rise, half), base * CFrame.new(0, 0, -half / 2),
		roofColor, M.Slate, nil, "WedgePart")
	part(deco, name .. "RoofBack", Vector3.new(sx + 3, rise, half), base * CFrame.new(0, 0, half / 2) * CFrame.Angles(0, math.pi, 0),
		roofColor, M.Slate, nil, "WedgePart")
end

local function flagpole(solid, deco, name, x, z, color)
	cylinder(solid, name, P(x, 9, z), 0.8, 18, C.woodDark, M.Wood)
	part(deco, name .. "Flag", Vector3.new(0.3, 4, 7), CFrame.new(P(x, 15.5, z) + Vector3.new(0, 0, 3.8)), color, M.Fabric)
end

-- A stone lantern: solid body, glowing lamp and cap (decor). Colours default to grey stone.
local function lanternAt(solid, deco, name, pos, bodyColor, capColor)
	part(solid, name, Vector3.new(4, 5, 4), CFrame.new(pos + Vector3.new(0, 2.5, 0)), bodyColor or C.stone, M.Cobblestone)
	part(deco, name .. "Light", Vector3.new(2.6, 1.8, 2.6), CFrame.new(pos + Vector3.new(0, 5.9, 0)), Color3.fromRGB(240, 214, 150), M.Neon)
	part(deco, name .. "Cap", Vector3.new(6, 1.2, 6), CFrame.new(pos + Vector3.new(0, 7.4, 0)), capColor or C.stone, M.Slate)
end

-- A shrine entrance: a torii gate (solid posts, decor beams) standing `distance` studs out from
-- the shrine centre towards `toward` (a stud position), with a stone lantern either side.
local function shrine(solid, deco, name, x, z, toward, distance)
	local c = P(x, 0, z)
	local gate = CFrame.lookAt(c, Vector3.new(toward.X, 0, toward.Z)) * CFrame.new(0, 0, -distance)
	cylinder(solid, name .. "ToriiPostLeft", (gate * CFrame.new(-6, 6, 0)).Position, 1.8, 12, C.torii, M.Wood)
	cylinder(solid, name .. "ToriiPostRight", (gate * CFrame.new(6, 6, 0)).Position, 1.8, 12, C.torii, M.Wood)
	part(deco, name .. "ToriiBeam", Vector3.new(14, 1.2, 1.4), gate * CFrame.new(0, 10, 0), C.torii, M.Wood)
	part(deco, name .. "ToriiTop", Vector3.new(18, 1.4, 2), gate * CFrame.new(0, 12.4, 0), C.woodDark, M.Wood)
	lanternAt(solid, deco, name .. "LanternLeft", (gate * CFrame.new(-11, 0, 4)).Position)
	lanternAt(solid, deco, name .. "LanternRight", (gate * CFrame.new(11, 0, 4)).Position)
end

-- A ramen stand: a solid hut and counter, an orange roof, and red/white curtains at the front.
-- `facing` is +1 to open towards +Z (south) or -1 to open towards -Z (north).
local function ramenStand(solid, deco, name, x, z, facing)
	local base = P(x, 0, z)
	local front = Vector3.new(0, 0, 5 * facing)
	part(solid, name .. "Hut", Vector3.new(18, 9, 8), CFrame.new(base + Vector3.new(0, 4.5, 0)), C.wood, M.WoodPlanks)
	part(solid, name .. "Counter", Vector3.new(18, 4, 3), CFrame.new(base + front * 1.3 + Vector3.new(0, 2, 0)), C.woodDark, M.Wood)
	part(deco, name .. "Roof", Vector3.new(22, 1.2, 15), CFrame.new(base + front * 0.5 + Vector3.new(0, 10.6, 0)), C.ramen, M.WoodPlanks)
	for i = 0, 3 do
		local color = if i % 2 == 0 then C.plaster else C.south
		part(deco, name .. "Curtain" .. i, Vector3.new(4.2, 2.6, 0.2),
			CFrame.new(base + front * 1.95 + Vector3.new(-6.6 + i * 4.4, 8.6, 0)), color, M.Fabric)
	end
	for i = 0, 2 do
		cylinder(deco, name .. "Stool" .. i, base + front * 2.6 + Vector3.new(-6 + i * 6, 1.25, 0), 1.6, 2.5, C.woodDark, M.Wood)
	end
end

-- A bamboo forest filling the layout rectangle x1..x2 by z1 (cliff side) .. z2 (inner side). It is
-- made of clumps of stalks under leafy canopies; each clump has an invisible collider so units
-- path around it. Clumps are left out along `trails` ({x1, z1, x2, z2, widthStuds}, layout ends)
-- and inside `clear` circles ({x, z, radius}, layout). The same seed with mirrored z gives a
-- mirrored forest, so the north and south forests match.
local function bambooForest(solid, deco, name, x1, z1, x2, z2, trails, clear, seed)
	local rng = Random.new(seed)
	local cell = 22 -- studs between clump centres
	local zSign = math.sign(z2 - z1)
	local function distanceToSegment(p, a, b)
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		return (p - (a + ab * t)).Magnitude
	end
	local index = 0
	for sx = L(x1), L(x2), cell do
		for sz = L(z1), L(z2), zSign * cell do
			local centre = Vector3.new(sx + rng:NextNumber(-5, 5), 0, sz + zSign * rng:NextNumber(-5, 5))
			local radius = rng:NextNumber(8, 12)
			local keep = true
			for _, t in trails do
				if distanceToSegment(centre, P(t[1], 0, t[2]), P(t[3], 0, t[4])) < t[5] / 2 + radius then
					keep = false
				end
			end
			for _, c in clear do
				if (centre - P(c[1], 0, c[2])).Magnitude < L(c[3]) + radius then
					keep = false
				end
			end
			-- Draw the clump's random numbers whether or not it is kept, so the layout stays mirrored.
			local stalks = {}
			for i = 1, math.floor(radius * 0.6) do
				local angle = rng:NextNumber(0, 2 * math.pi)
				local r = math.sqrt(rng:NextNumber()) * (radius - 1)
				stalks[i] = { math.cos(angle) * r, zSign * math.sin(angle) * r, rng:NextNumber(26, 38), rng:NextNumber(0.6, 0.95), rng:NextNumber(5, 6.5) }
			end
			if keep then
				index += 1
				local clumpName = name .. "Clump" .. index
				local collider = cylinder(solid, clumpName, centre + Vector3.new(0, 6, 0), radius * 2, 12, C.leafDark, M.Grass)
				collider.Transparency = 1
				collider.CastShadow = false
				-- Stalks and leaves use their own random stream (seeded by the clump's grid cell), so
				-- they never shift the shared layout stream that keeps the two forests mirrored. The
				-- whole clump sways together from its base.
				local leafRng = Random.new(math.floor(sx) * 7919 + math.floor(math.abs(sz)))
				local clump = swayGroup(deco, clumpName .. "Bamboo", centre, 2.5)
				for i, s in stalks do
					bambooStalk(clump, clumpName .. "Stalk" .. i, centre + Vector3.new(s[1], 0, s[2]), s[3], s[4], s[5], leafRng)
				end
			end
		end
	end
end

-- Base buildings and landscaping ---------------------------------------------------------

-- Rotates a flat direction by `degrees` around the vertical axis.
local function turn(dir, degrees)
	local a = math.rad(degrees)
	return Vector3.new(dir.X * math.cos(a) - dir.Z * math.sin(a), 0, dir.X * math.sin(a) + dir.Z * math.cos(a))
end

-- A paper window with a dark timber frame and lattice, on a wall face. `frame` points
-- local -Z out of the wall; (lx, ly) is the window centre on that face.
local function paperWindow(deco, name, frame, lx, ly, wallOffset, w, h)
	part(deco, name .. "Frame", Vector3.new(w + 0.8, h + 0.8, 0.2), frame * CFrame.new(lx, ly, -wallOffset - 0.1), C.woodDark, M.Wood)
	part(deco, name, Vector3.new(w, h, 0.2), frame * CFrame.new(lx, ly, -wallOffset - 0.2), C.paper, M.SmoothPlastic)
	part(deco, name .. "BarV", Vector3.new(0.25, h, 0.15), frame * CFrame.new(lx, ly, -wallOffset - 0.3), C.woodDark, M.Wood)
	part(deco, name .. "BarH", Vector3.new(w, 0.25, 0.15), frame * CFrame.new(lx, ly, -wallOffset - 0.3), C.woodDark, M.Wood)
end

-- A Leaf-village house whose front faces the flat world direction `front`: plaster walls in a
-- dark timber frame, paper windows, a door with a noren curtain, a veranda, flower boxes,
-- shrubs and a tiled gable roof. `opts.dojo` swaps the front windows for sliding shoji panels
-- and adds a name board and banners.
local function leafHouse(solid, deco, name, x, z, sx, sz, h, front, accent, roofColor, opts)
	opts = opts or {}
	local c = P(x, 0, z)
	local f = CFrame.lookAt(c, c + front) -- local -Z is the front; local X runs along the house
	local function rel(lx, ly, lz)
		return f * CFrame.new(lx, ly, lz)
	end
	part(solid, name, Vector3.new(sx, h, sz), rel(0, h / 2, 0), C.plaster, M.Plaster)
	part(deco, name .. "Footing", Vector3.new(sx + 1, 1.2, sz + 1), rel(0, 0.6, 0), C.stone, M.Cobblestone)
	for _, px in { -1, 1 } do
		for _, pz in { -1, 1 } do
			part(deco, name .. "CornerPost", Vector3.new(1.3, h, 1.3), rel(px * sx / 2, h / 2, pz * sz / 2), C.woodDark, M.Wood)
		end
	end
	part(deco, name .. "BeamFront", Vector3.new(sx, 0.8, 0.5), rel(0, h * 0.8, -sz / 2 - 0.2), C.woodDark, M.Wood)
	part(deco, name .. "BeamBack", Vector3.new(sx, 0.8, 0.5), rel(0, h * 0.8, sz / 2 + 0.2), C.woodDark, M.Wood)
	part(deco, name .. "Trim", Vector3.new(sx + 0.4, 1, sz + 0.4), rel(0, h - 0.5, 0), accent, M.WoodPlanks)

	-- Roof: two tiled slopes with deep eaves over the veranda, and a ridge cap.
	local rise = sz * 0.42
	local half = sz / 2 + 2.5
	local roofBase = rel(0, h + rise / 2, 0)
	part(deco, name .. "RoofFront", Vector3.new(sx + 4, rise, half), roofBase * CFrame.new(0, 0, -half / 2), roofColor, M.Slate, nil, "WedgePart")
	part(deco, name .. "RoofBack", Vector3.new(sx + 4, rise, half), roofBase * CFrame.new(0, 0, half / 2) * CFrame.Angles(0, math.pi, 0), roofColor, M.Slate, nil, "WedgePart")
	part(deco, name .. "RidgeCap", Vector3.new(sx + 4.4, 0.9, 1.4), rel(0, h + rise + 0.2, 0), C.woodDark, M.Wood)
	-- Gable-end emblem (a round crest in the team colour).
	for _, side in { -1, 1 } do
		part(deco, name .. "Crest", Vector3.new(0.3, 2.6, 2.6), rel(side * (sx / 2 + 2.2), h + rise * 0.35, 0), accent, M.SmoothPlastic, Enum.PartType.Cylinder)
	end

	-- Front: door, curtain, veranda and windows.
	local doorX = opts.doorOffset or 0
	part(deco, name .. "DoorFrame", Vector3.new(5.2, 7.6, 0.3), rel(doorX, 3.8, -sz / 2 - 0.15), C.woodDark, M.Wood)
	part(deco, name .. "Door", Vector3.new(4.4, 7, 0.3), rel(doorX, 3.5, -sz / 2 - 0.3), C.wood, M.WoodPlanks)
	part(deco, name .. "Noren", Vector3.new(4.8, 2.2, 0.15), rel(doorX, 6.1, -sz / 2 - 0.55), accent, M.Fabric)
	part(deco, name .. "Veranda", Vector3.new(sx + 1, 0.6, 3.5), rel(0, 0.3, -sz / 2 - 1.75), C.wood, M.WoodPlanks)
	for _, px in { -1, 1 } do
		part(deco, name .. "VerandaPost", Vector3.new(0.7, h - 0.6, 0.7), rel(px * (sx / 2 + 0.2), h / 2 + 0.3, -sz / 2 - 3.2), C.woodDark, M.Wood)
	end
	if opts.dojo then
		-- Sliding shoji panels across the front, a name board over the door and two banners.
		local panels = math.floor((sx - 8) / 4.5)
		for i = 0, panels - 1 do
			local px = -sx / 2 + 2.5 + i * ((sx - 5) / panels) + (sx - 5) / panels / 2
			if math.abs(px - doorX) > 4.5 then
				paperWindow(deco, name .. "Shoji" .. i, f, px, h * 0.36, sz / 2, 3.6, h * 0.55)
			end
		end
		part(deco, name .. "NameBoard", Vector3.new(9, 2.2, 0.4), rel(doorX, h * 0.8 - 1.4, -sz / 2 - 0.5), C.woodDark, M.Wood)
		part(deco, name .. "NameBoardText", Vector3.new(7.6, 1.2, 0.2), rel(doorX, h * 0.8 - 1.4, -sz / 2 - 0.75), C.paper, M.SmoothPlastic)
		for _, px in { -1, 1 } do
			part(deco, name .. "Banner", Vector3.new(2.6, 7, 0.2), rel(doorX + px * 6, h * 0.5, -sz / 2 - 0.45), accent, M.Fabric)
		end
	else
		for _, px in { -0.32, 0.32 } do
			local wx = px * sx
			if math.abs(wx - doorX) > 4.5 then
				paperWindow(deco, name .. "Window", f, wx, h * 0.5, sz / 2, 3.6, 2.8)
				-- Flower box under the window.
				part(deco, name .. "FlowerBox", Vector3.new(4.2, 0.9, 1.1), rel(wx, h * 0.5 - 2.2, -sz / 2 - 0.6), C.wood, M.WoodPlanks)
				for i = -1, 1 do
					ball(deco, name .. "Flower", (rel(wx + i * 1.3, h * 0.5 - 1.5, -sz / 2 - 0.6)).Position, 1.1,
						if i == 0 then C.flowerYellow else C.blossom, M.SmoothPlastic)
				end
			end
		end
	end
	-- Side windows.
	for _, side in { -1, 1 } do
		local sideFrame = f * CFrame.Angles(0, side * math.pi / 2, 0)
		paperWindow(deco, name .. "SideWindow", sideFrame, 0, h * 0.5, sx / 2, 3.2, 2.6)
	end
	-- Shrubs at the front corners and a bench by the door.
	for _, px in { -1, 1 } do
		ball(deco, name .. "Shrub", rel(px * (sx / 2 + 1.5), 1.6, -sz / 2 - 2.5).Position, 3.4, C.shrub, M.Grass)
		ball(deco, name .. "ShrubSmall", rel(px * (sx / 2 + 0.5), 1.1, -sz / 2 - 4.2).Position, 2.2, C.leafDark, M.Grass)
	end
	part(deco, name .. "Bench", Vector3.new(5, 0.5, 1.4), rel(doorX + 6.5, 1.6, -sz / 2 - 1.4), C.woodDark, M.Wood)
end

-- A sand-village building: round sandstone walls, a dome, arched windows with sills, a
-- doorway facing `facePos` (studs) under a cloth awning, clay pots and a plinth.
-- `opts.rows` sets window rows, `opts.spire` adds a rooftop spire, `opts.crest` a round crest.
local function sandHouse(solid, deco, name, x, z, d, h, facePos, accent, opts)
	opts = opts or {}
	local c = P(x, 0, z)
	local dir = Vector3.new(facePos.X - c.X, 0, facePos.Z - c.Z).Unit
	local r = d / 2
	cylinder(solid, name, c + Vector3.new(0, h / 2, 0), d, h, C.sandstone, M.Sandstone)
	cylinder(deco, name .. "Plinth", c + Vector3.new(0, 0.7, 0), d + 1.6, 1.4, C.sandstoneDark, M.Sandstone)
	cylinder(deco, name .. "Band", c + Vector3.new(0, h - 2, 0), d + 0.6, 1.6, accent, M.Fabric)
	cylinder(deco, name .. "Parapet", c + Vector3.new(0, h + 0.4, 0), d + 0.8, 0.8, C.sandstoneDark, M.Sandstone)
	ball(deco, name .. "Dome", c + Vector3.new(0, h, 0), d * 0.85, C.sandstoneDark, M.Sandstone)

	-- Arched windows around the wall (skipping the doorway), in one or two rows.
	local count = math.max(5, math.floor(d / 4.5))
	local rows = opts.rows or 1
	for row = 1, rows do
		local y = if rows == 1 then h * 0.5 else h * (0.3 + 0.36 * (row - 1))
		for i = 1, count - 1 do
			local a = i * 360 / count + (row - 1) * 180 / count
			local f = CFrame.lookAt(c, c + turn(dir, a))
			part(deco, name .. "Window", Vector3.new(2.2, 2.8, 0.5), f * CFrame.new(0, y, -r + 0.1), C.windowDark, M.SmoothPlastic)
			part(deco, name .. "WindowArch", Vector3.new(0.5, 2.2, 2.2), f * CFrame.new(0, y + 1.4, -r + 0.1) * CFrame.Angles(0, math.pi / 2, 0), C.windowDark, M.SmoothPlastic, Enum.PartType.Cylinder)
			part(deco, name .. "Sill", Vector3.new(3, 0.4, 0.9), f * CFrame.new(0, y - 1.6, -r - 0.2), C.sandstoneDark, M.Sandstone)
		end
	end

	-- Doorway with a striped cloth awning, pots either side.
	local f = CFrame.lookAt(c, c + dir)
	part(deco, name .. "Doorway", Vector3.new(4.6, 7, 0.6), f * CFrame.new(0, 3.5, -r + 0.05), C.windowDark, M.SmoothPlastic)
	part(deco, name .. "DoorArch", Vector3.new(0.6, 4.6, 4.6), f * CFrame.new(0, 7, -r + 0.05) * CFrame.Angles(0, math.pi / 2, 0), C.windowDark, M.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 0, 3 do
		part(deco, name .. "Awning" .. i, Vector3.new(1.8, 1.2, 3.4), f * CFrame.new(-2.7 + i * 1.8, math.min(10.2, h - 1), -r - 1.6), if i % 2 == 0 then accent else C.paper, M.Fabric, nil, "WedgePart")
	end
	for _, side in { -1, 1 } do
		local pot = (f * CFrame.new(side * 4, 0, -r - 1.5)).Position
		cylinder(deco, name .. "Pot", pot + Vector3.new(0, 1.1, 0), 2.2, 2.2, C.terracotta, M.Slate)
		ball(deco, name .. "PotPlant", pot + Vector3.new(0, 2.8, 0), 2.2, C.shrubDry, M.Grass)
	end
	if opts.crest then
		part(deco, name .. "CrestRim", Vector3.new(0.4, 5, 5), f * CFrame.new(0, h - 4.5, -r - 0.1) * CFrame.Angles(0, math.pi / 2, 0), accent, M.SmoothPlastic, Enum.PartType.Cylinder)
		part(deco, name .. "Crest", Vector3.new(0.4, 4, 4), f * CFrame.new(0, h - 4.5, -r - 0.3) * CFrame.Angles(0, math.pi / 2, 0), C.paper, M.SmoothPlastic, Enum.PartType.Cylinder)
	end
	if opts.spire then
		local top = c + Vector3.new(0, h + d * 0.425, 0)
		cylinder(deco, name .. "Spire", top + Vector3.new(0, 3, 0), 1.2, 6, C.sandstoneDark, M.Sandstone)
		ball(deco, name .. "SpireTip", top + Vector3.new(0, 6.4, 0), 2, accent, M.SmoothPlastic)
	end
end

-- A cherry-blossom tree: solid trunk, two branches, clustered pink canopies, a carpet of fallen
-- petals with a few loose ones around it, and petals drifting down from the canopy.
local function cherryTree(solid, deco, name, x, z, scale)
	local s = scale or 1
	local base = P(x, 0, z)
	local rng = Random.new(math.floor(x * 31 + z * 17))
	cylinder(solid, name, base + Vector3.new(0, 5 * s, 0), 2 * s, 10 * s, C.woodDark, M.Wood)
	part(deco, name .. "Branch", Vector3.new(6 * s, 1 * s, 1 * s), CFrame.new(base + Vector3.new(1.5 * s, 9 * s, 0)) * CFrame.Angles(0, 0, math.rad(25)), C.woodDark, M.Wood)
	part(deco, name .. "BranchB", Vector3.new(5 * s, 0.9 * s, 0.9 * s), CFrame.new(base + Vector3.new(-1.3 * s, 9.5 * s, -0.8 * s)) * CFrame.Angles(0, math.rad(40), math.rad(-30)), C.woodDark, M.Wood)
	local leaves = swayGroup(deco, name .. "Leaves", base + Vector3.new(0, 5 * s, 0), 3.5)
	clusterCanopy(leaves, name .. "Canopy", base + Vector3.new(0, 12 * s, 0), 5.5 * s, CHERRY_TONES, rng)
	clusterCanopy(leaves, name .. "CanopyA", base + Vector3.new(4 * s, 11 * s, 2 * s), 3.6 * s, CHERRY_TONES, rng)
	clusterCanopy(leaves, name .. "CanopyB", base + Vector3.new(-3.5 * s, 11 * s, -2.5 * s), 3.6 * s, CHERRY_TONES, rng)
	part(deco, name .. "Petals", Vector3.new(0.1, 14 * s, 14 * s), CFrame.new(base + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.blossomLight, M.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 8 do
		local a, r = rng:NextNumber(0, 2 * math.pi), rng:NextNumber(7, 11) * s
		part(deco, name .. "LoosePetal" .. i, Vector3.new(0.1, 0.9, 0.9), CFrame.new(base + Vector3.new(math.cos(a) * r, 0.15, math.sin(a) * r)) * CFrame.Angles(0, 0, math.rad(90)), CHERRY_TONES[3], M.SmoothPlastic, Enum.PartType.Cylinder)
	end
	-- Falling petals: an invisible box under the canopy emits slow, tumbling pink flecks.
	local emitterBox = part(deco, name .. "PetalFall", Vector3.new(12 * s, 1, 12 * s), CFrame.new(base + Vector3.new(0, 9.5 * s, 0)), C.blossom, M.SmoothPlastic)
	emitterBox.Transparency = 1
	local petals = Instance.new("ParticleEmitter")
	petals.Name = "FallingPetals"
	petals.Shape = Enum.ParticleEmitterShape.Box
	petals.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	petals.Color = ColorSequence.new(CHERRY_TONES[4], CHERRY_TONES[2])
	petals.Size = NumberSequence.new(0.45, 0.3)
	petals.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	petals.Lifetime = NumberRange.new(3.5, 5)
	petals.Rate = 5
	petals.Speed = NumberRange.new(0.5, 1.2)
	petals.Acceleration = Vector3.new(0.6, -0.8, 0.3)
	petals.Drag = 0.4
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-120, 120)
	petals.SpreadAngle = Vector2.new(35, 35)
	petals.Parent = emitterBox
end

-- A palm tree: solid trunk, drooping fronds and coconuts.
local function palmTree(solid, deco, name, x, z, scale)
	local s = scale or 1
	local base = P(x, 0, z)
	local height = 16 * s
	cylinder(solid, name, base + Vector3.new(0, height / 2, 0), 1.8 * s, height, C.wood, M.Wood)
	for i = 0, 3 do
		cylinder(deco, name .. "Ring" .. i, base + Vector3.new(0, height * (0.2 + i * 0.2), 0), 2.1 * s, 0.4, C.woodDark, M.Wood)
	end
	local top = base + Vector3.new(0, height, 0)
	local crown = swayGroup(deco, name .. "Crown", top, 4)
	for i = 0, 6 do
		local frond = CFrame.new(top) * CFrame.Angles(0, math.rad(i * 360 / 7), 0) * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, 0, -4.5 * s)
		part(crown, name .. "Frond" .. i, Vector3.new(2.4 * s, 0.4, 9 * s), frond, C.palm, M.Grass)
	end
	for i = 0, 2 do
		ball(crown, name .. "Coconut" .. i, top + turn(Vector3.new(0.9 * s, 0, 0), i * 120) + Vector3.new(0, -0.8, 0), 1.1 * s, C.woodDark, M.Wood)
	end
end

-- A cactus: solid main stem with two arms.
local function cactus(solid, deco, name, x, z, height)
	local base = P(x, 0, z)
	cylinder(solid, name, base + Vector3.new(0, height / 2, 0), 2.4, height, C.cactus, M.Grass)
	ball(deco, name .. "Top", base + Vector3.new(0, height, 0), 2.4, C.cactus, M.Grass)
	for _, side in { -1, 1 } do
		local armY = height * (if side < 0 then 0.45 else 0.6)
		part(deco, name .. "ArmOut", Vector3.new(2.4, 1.6, 1.6), CFrame.new(base + Vector3.new(side * 2, armY, 0)), C.cactus, M.Grass)
		cylinder(deco, name .. "ArmUp", base + Vector3.new(side * 3, armY + 1.6, 0), 1.6, 3.6, C.cactus, M.Grass)
	end
end

-- A round hedge bush units walk around.
local function hedge(solid, deco, name, x, z, diameter)
	ball(solid, name, P(x, diameter * 0.35, z), diameter, C.shrub, M.Grass)
	ball(deco, name .. "Top", P(x, diameter * 0.75, z) + Vector3.new(0.6, 0, -0.4), diameter * 0.6, C.leaf, M.Grass)
end

-- A village well: solid stone ring, a little roof on posts, a bucket.
local function well(solid, deco, name, x, z)
	local base = P(x, 0, z)
	cylinder(solid, name, base + Vector3.new(0, 2, 0), 7, 4, C.stone, M.Cobblestone)
	cylinder(deco, name .. "Water", base + Vector3.new(0, 3.9, 0), 5.4, 0.2, C.water, M.SmoothPlastic)
	for _, side in { -1, 1 } do
		part(deco, name .. "Post", Vector3.new(0.7, 8, 0.7), CFrame.new(base + Vector3.new(side * 3.2, 4, 0)), C.woodDark, M.Wood)
	end
	part(deco, name .. "Crossbar", Vector3.new(7.2, 0.5, 0.5), CFrame.new(base + Vector3.new(0, 7, 0)), C.woodDark, M.Wood)
	local roof = CFrame.new(base + Vector3.new(0, 8.6, 0))
	part(deco, name .. "RoofA", Vector3.new(9, 1.6, 3), roof * CFrame.new(0, 0, -1.5), C.northRoof, M.Slate, nil, "WedgePart")
	part(deco, name .. "RoofB", Vector3.new(9, 1.6, 3), roof * CFrame.new(0, 0, 1.5) * CFrame.Angles(0, math.pi, 0), C.northRoof, M.Slate, nil, "WedgePart")
	cylinder(deco, name .. "Bucket", base + Vector3.new(1.2, 5.2, 0), 1.2, 1.2, C.wood, M.WoodPlanks)
end

-- A market stall: solid counter, striped awning on posts, stacked crates and pots.
local function marketStall(solid, deco, name, x, z, front, accent)
	local c = P(x, 0, z)
	local f = CFrame.lookAt(c, c + front)
	part(solid, name, Vector3.new(14, 4.5, 4), f * CFrame.new(0, 2.25, 0), C.wood, M.WoodPlanks)
	part(deco, name .. "Goods", Vector3.new(12, 0.8, 3), f * CFrame.new(0, 4.9, 0), C.terracotta, M.Fabric)
	for _, px in { -1, 1 } do
		for _, pz in { -1, 1 } do
			part(deco, name .. "Post", Vector3.new(0.6, 9, 0.6), f * CFrame.new(px * 6.8, 4.5, pz * 2.6), C.woodDark, M.Wood)
		end
	end
	for i = 0, 6 do
		part(deco, name .. "Awning" .. i, Vector3.new(2.2, 0.4, 8), f * CFrame.new(-6.6 + i * 2.2, 9.2, -0.8) * CFrame.Angles(math.rad(-12), 0, 0),
			if i % 2 == 0 then accent else C.paper, M.Fabric)
	end
	part(solid, name .. "Crates", Vector3.new(4, 4, 4), f * CFrame.new(9.5, 2, 1) * CFrame.Angles(0, math.rad(12), 0), C.wood, M.WoodPlanks)
	part(deco, name .. "CrateTop", Vector3.new(3, 3, 3), f * CFrame.new(9.3, 5.5, 1.2) * CFrame.Angles(0, math.rad(-20), 0), C.woodDark, M.WoodPlanks)
	for i = 0, 1 do
		cylinder(deco, name .. "Pot" .. i, (f * CFrame.new(-9 - i * 2.2, 1.1, 1)).Position, 2, 2.2, C.terracotta, M.Slate)
	end
end

-- A tall nobori banner on a solid pole.
local function nobori(solid, deco, name, x, z, color)
	local base = P(x, 0, z)
	cylinder(solid, name, base + Vector3.new(0, 8, 0), 0.8, 16, C.woodDark, M.Wood)
	part(deco, name .. "Arm", Vector3.new(3.6, 0.4, 0.4), CFrame.new(base + Vector3.new(1.8, 15.6, 0)), C.woodDark, M.Wood)
	part(deco, name .. "Cloth", Vector3.new(3, 10, 0.2), CFrame.new(base + Vector3.new(1.9, 10.4, 0)), color, M.Fabric)
	part(deco, name .. "ClothStripe", Vector3.new(3, 1, 0.25), CFrame.new(base + Vector3.new(1.9, 13.6, 0)), C.paper, M.Fabric)
end

-- Lanterns along the footpath (x1, z1) -> (x2, z2), one at each fraction of its length, alternating sides.
local function pathLanterns(solid, deco, name, x1, z1, x2, z2, fractions, bodyColor, capColor)
	local a, b = P(x1, 0, z1), P(x2, 0, z2)
	local side = (b - a).Unit:Cross(Vector3.yAxis)
	for i, t in fractions do
		local offset = side * (if i % 2 == 0 then 6 else -6)
		lanternAt(solid, deco, name .. i, a:Lerp(b, t) + offset, bodyColor, capColor)
	end
end

-- A flower garden: dark soil bed, rows of flowers and a low bamboo fence (all decor; units walk through).
local function flowerGarden(deco, name, x, z, sx, sz)
	local c = P(x, 0, z)
	part(deco, name .. "Soil", Vector3.new(sx, 0.3, sz), CFrame.new(c + Vector3.new(0, 0.15, 0)), Color3.fromRGB(96, 72, 52), M.Ground)
	local colors = { C.blossom, C.flowerYellow, C.paper, C.blossomLight }
	local i = 0
	for gx = -sx / 2 + 2, sx / 2 - 2, 2.5 do
		for gz = -sz / 2 + 2, sz / 2 - 2, 3 do
			i += 1
			ball(deco, name .. "Flower" .. i, c + Vector3.new(gx, 0.8, gz), 1.2, colors[i % #colors + 1], M.SmoothPlastic)
			ball(deco, name .. "Leaf" .. i, c + Vector3.new(gx + 0.5, 0.5, gz + 0.6), 1, C.shrub, M.Grass)
		end
	end
	for _, side in { -1, 1 } do
		part(deco, name .. "FenceLong", Vector3.new(sx + 1, 0.3, 0.3), CFrame.new(c + Vector3.new(0, 1.4, side * (sz / 2 + 0.5))), C.bamboo, M.Wood)
		part(deco, name .. "FenceShort", Vector3.new(0.3, 0.3, sz + 1), CFrame.new(c + Vector3.new(side * (sx / 2 + 0.5), 1.4, 0)), C.bamboo, M.Wood)
	end
	for gx = -sx / 2 - 0.5, sx / 2 + 0.5, 3 do
		for _, side in { -1, 1 } do
			part(deco, name .. "FencePost", Vector3.new(0.4, 2, 0.4), CFrame.new(c + Vector3.new(gx, 1, side * (sz / 2 + 0.5))), C.bamboo, M.Wood)
		end
	end
end

-- A desert rock garden: sand bed, small cacti, stones and clay pots (all decor; units walk through).
local function desertGarden(deco, name, x, z, sx, sz)
	local c = P(x, 0, z)
	part(deco, name .. "Bed", Vector3.new(sx, 0.3, sz), CFrame.new(c + Vector3.new(0, 0.15, 0)), C.sandstone, M.Sand)
	local rng = Random.new(#name)
	for i = 1, 10 do
		local pos = c + Vector3.new(rng:NextNumber(-sx / 2 + 2, sx / 2 - 2), 0, rng:NextNumber(-sz / 2 + 2, sz / 2 - 2))
		if i % 3 == 0 then
			ball(deco, name .. "Stone" .. i, pos + Vector3.new(0, 0.6, 0), rng:NextNumber(1.6, 2.6), C.sandstoneDark, M.Slate)
		elseif i % 3 == 1 then
			local h = rng:NextNumber(2, 3.5)
			cylinder(deco, name .. "Cactus" .. i, pos + Vector3.new(0, h / 2, 0), 1, h, C.cactus, M.Grass)
		else
			cylinder(deco, name .. "Pot" .. i, pos + Vector3.new(0, 0.9, 0), 1.6, 1.8, C.terracotta, M.Slate)
			ball(deco, name .. "PotPlant" .. i, pos + Vector3.new(0, 2.1, 0), 1.6, C.shrubDry, M.Grass)
		end
	end
	for _, side in { -1, 1 } do
		part(deco, name .. "BorderLong", Vector3.new(sx + 1, 0.6, 0.8), CFrame.new(c + Vector3.new(0, 0.3, side * (sz / 2 + 0.4))), C.sandstoneDark, M.Sandstone)
		part(deco, name .. "BorderShort", Vector3.new(0.8, 0.6, sz + 1), CFrame.new(c + Vector3.new(side * (sx / 2 + 0.4), 0.3, 0)), C.sandstoneDark, M.Sandstone)
	end
end

-- Resource points of interest --------------------------------------------------------------
-- Placeholders for the capturable points that will give their owner passive resources. Each
-- POI is a Model in Workspace.Map.POIs tagged "ResourcePOI", whose attributes are its settings:
--   PoiId, DisplayName, RyoPerSecond, ChakraPerSecond, CaptureRadius (studs),
--   OwnerSlot (0 = unclaimed; the claim system will set this), Level / MaxLevel (upgrades)
-- Its info board is drawn by the client (Client/UI/ResourceBillboards) over LabelAnchor.
-- Nothing reads them yet. The pedestal is solid (in Obstacles); every part inside the POI
-- model is non-colliding, so a POI never changes how units move.

local POI_TAG = "ResourcePOI"

local function resourcePOI(poiFolder, solid, id, displayName, ryo, chakra, x, z, captureRadius)
	local centre = P(x, 0, z)
	local model = Instance.new("Model")
	model.Name = "POI_" .. id
	model:SetAttribute("PoiId", id)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("RyoPerSecond", ryo)
	model:SetAttribute("ChakraPerSecond", chakra)
	model:SetAttribute("CaptureRadius", captureRadius)
	model:SetAttribute("OwnerSlot", 0)
	model:SetAttribute("Level", 1)
	model:SetAttribute("MaxLevel", 3)

	-- The capture zone: an invisible cylinder over the claim area, plus a faint floor and a
	-- ring of boundary stones so players can see it.
	local zone = cylinder(model, "CaptureZone", centre + Vector3.new(0, 4, 0), captureRadius * 2, 8, C.poi, M.SmoothPlastic)
	zone.Transparency = 1
	model.PrimaryPart = zone
	local zoneFloor = groundDisc(model, "ZoneFloor", x, z, captureRadius * 2, C.poi, M.SmoothPlastic, 0.055)
	zoneFloor.Transparency = 0.75
	for i = 0, 15 do
		local a = i * math.pi / 8
		local pos = centre + Vector3.new(math.cos(a), 0, math.sin(a)) * captureRadius
		part(model, "BoundaryStone" .. i, Vector3.new(1.6, 1.2, 1.6), CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, a, 0), C.stone, M.Slate)
	end

	-- Placeholder centrepiece: a solid stone pedestal and a glowing crystal with a label.
	cylinder(solid, "POIPedestal_" .. id, centre + Vector3.new(0, 2.5, 0), 14, 5, C.stone, M.Cobblestone)
	cylinder(model, "PedestalTop", centre + Vector3.new(0, 5.15, 0), 10, 0.3, C.poi, M.SmoothPlastic)
	local crystal = part(model, "Crystal", Vector3.new(4.5, 4.5, 4.5), CFrame.new(centre + Vector3.new(0, 11, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), C.poi, M.Neon)
	local light = Instance.new("PointLight")
	light.Color = C.poi
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = crystal
	-- Where the client's info board hangs.
	local anchor = part(model, "LabelAnchor", Vector3.new(1, 1, 1), CFrame.new(centre + Vector3.new(0, 18, 0)), C.poi, M.SmoothPlastic)
	anchor.Transparency = 1

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	CollectionService:AddTag(model, POI_TAG)
	model.Parent = poiFolder
end

-- Resource nodes ------------------------------------------------------------------------------
-- Small structures that units are sent to for Ryo or Chakra. Each is a Model in
-- Workspace.Map.ResourceNodes tagged "ResourceNode", whose attributes are its settings:
--   NodeId, Kind, DisplayName, ResourceType ("Ryo" or "Chakra"), GatherRatePerUnit (per second),
--   Capacity, Remaining, GatherRadius (studs; units gather from inside this ring), MaxGatherers
-- Nothing reads them yet; the gathering system will. Each structure's core is solid (in
-- Obstacles) so units walk around it; every part inside the model is non-colliding.

local RESOURCE_TAG = "ResourceNode"
local GATHER_RADIUS = 22

-- Ryo mine: a rock outcrop shot through with gold, a timber-framed tunnel, rails and a cart of ore.
-- Builders draw around the frame `f` (on the ground, local -Z is the front).
local function buildRyoMine(model, solid, f, prefix)
	part(solid, prefix .. "Rock", Vector3.new(18, 11, 14), f * CFrame.new(0, 4.5, 3) * CFrame.Angles(0, 0, math.rad(4)), C.cliff, M.Slate)
	part(solid, prefix .. "RockEast", Vector3.new(10, 8, 10), f * CFrame.new(9, 3, 6) * CFrame.Angles(0, math.rad(25), 0), C.cliffDark, M.Slate)
	part(solid, prefix .. "RockWest", Vector3.new(9, 7, 9), f * CFrame.new(-9, 2.5, 6) * CFrame.Angles(0, math.rad(-20), 0), C.cliffDark, M.Slate)
	for i, g in { { -6, 7, -4 }, { -2, 9.6, -2 }, { 5, 6, -4 }, { 7, 2.5, -4 }, { -7.5, 2.5, -4 }, { 2, 10, 3 }, { -4, 10, 5 }, { 10, 6.5, 2 } } do
		ball(model, "GoldVein" .. i, (f * CFrame.new(g[1], g[2], g[3])).Position, 1.4 + (i % 3) * 0.5, C.gold, M.Metal)
	end
	part(model, "TunnelMouth", Vector3.new(6, 7, 0.4), f * CFrame.new(0, 3.5, -4.2), C.windowDark, M.SmoothPlastic)
	for _, side in { -1, 1 } do
		part(model, "TunnelPost", Vector3.new(1, 8, 1), f * CFrame.new(side * 3.6, 4, -4.6), C.wood, M.Wood)
	end
	part(model, "TunnelLintel", Vector3.new(9, 1.2, 1.4), f * CFrame.new(0, 8.4, -4.6), C.wood, M.Wood)
	part(model, "TunnelLamp", Vector3.new(1, 1.2, 1), f * CFrame.new(0, 7.2, -5.6), Color3.fromRGB(255, 200, 110), M.Neon)
	-- Rails out of the tunnel and a cart heaped with gold ore.
	for _, side in { -1, 1 } do
		part(model, "Rail", Vector3.new(0.4, 0.3, 13), f * CFrame.new(side * 1.4, 0.15, -10.5), C.metal, M.Metal)
	end
	for i = 0, 4 do
		part(model, "Sleeper" .. i, Vector3.new(4.2, 0.25, 0.8), f * CFrame.new(0, 0.1, -5.5 - i * 2.6), C.woodDark, M.Wood)
	end
	part(model, "CartBody", Vector3.new(4.4, 2.6, 5), f * CFrame.new(0, 2.1, -13), C.woodDark, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "CartWheel", Vector3.new(0.5, 1.6, 1.6), f * CFrame.new(sx * 2.4, 0.8, -13 + sz * 1.6), C.metal, M.Metal, Enum.PartType.Cylinder)
		end
	end
	for i, g in { { 0, 0 }, { -1, 1 }, { 1, -1 }, { 0.8, 1.2 }, { -1, -1 } } do
		ball(model, "CartOre" .. i, (f * CFrame.new(g[1], 3.6, -13 + g[2])).Position, 1.8, C.gold, M.Metal)
	end
	-- A pickaxe leaning on the rock.
	part(model, "PickHandle", Vector3.new(0.4, 5, 0.4), f * CFrame.new(5.5, 2.4, -4.6) * CFrame.Angles(0, 0, math.rad(-15)), C.wood, M.Wood)
	part(model, "PickHead", Vector3.new(3.4, 0.5, 0.5), f * CFrame.new(6.1, 4.8, -4.6) * CFrame.Angles(0, 0, math.rad(-15)), C.metal, M.Metal)
end

-- Merchant cache: a cart and strongboxes spilling gold ryo coins, under a striped awning with a
-- 両 (ryo) sign.
local function buildMerchantCache(model, solid, f, prefix)
	part(solid, prefix .. "Cart", Vector3.new(12, 4.5, 6), f * CFrame.new(0, 2.75, 1), C.wood, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Wheel", Vector3.new(0.6, 4, 4), f * CFrame.new(sx * 4, 2, 1 + sz * 3.4) * CFrame.Angles(0, math.rad(90), 0), C.woodDark, M.Wood, Enum.PartType.Cylinder)
		end
	end
	part(model, "CartHandle", Vector3.new(5, 0.5, 0.5), f * CFrame.new(-8, 2.5, 1) * CFrame.Angles(0, 0, math.rad(15)), C.woodDark, M.Wood)
	-- Two open strongboxes on the cart, heaped with coins.
	for i, x in { -3, 3 } do
		part(model, "Box" .. i, Vector3.new(4, 2.4, 3), f * CFrame.new(x, 6.2, 1), C.woodDark, M.WoodPlanks)
		part(model, "BoxBand" .. i, Vector3.new(4.2, 0.4, 3.2), f * CFrame.new(x, 6.6, 1), C.gold, M.Metal)
		part(model, "BoxLid" .. i, Vector3.new(4, 0.4, 3), f * CFrame.new(x, 8.2, 2.9) * CFrame.Angles(math.rad(-70), 0, 0), C.woodDark, M.WoodPlanks)
		for j = 0, 3 do
			ball(model, "Coins" .. i .. j, (f * CFrame.new(x - 1.2 + j * 0.8, 7.5 + (j % 2) * 0.3, 1 + (j % 2 - 0.5))).Position, 1.4, C.gold, M.Metal)
		end
	end
	-- A strongbox and stacks of coins on the ground.
	part(solid, prefix .. "Strongbox", Vector3.new(4, 3, 3), f * CFrame.new(8.5, 1.5, -1) * CFrame.Angles(0, math.rad(20), 0), C.woodDark, M.WoodPlanks)
	part(model, "StrongboxBand", Vector3.new(4.2, 0.5, 3.2), f * CFrame.new(8.5, 2.2, -1) * CFrame.Angles(0, math.rad(20), 0), C.gold, M.Metal)
	for i, s in { { -4, -4.5, 4 }, { -2.5, -5, 6 }, { 3, -4.5, 3 }, { 5, -5.5, 5 } } do
		for k = 0, s[3] - 1 do
			cylinder(model, "CoinStack" .. i .. "_" .. k, (f * CFrame.new(s[1], 0.15 + k * 0.32, s[2])).Position, 1.8, 0.3, C.gold, M.Metal)
		end
	end
	-- Striped awning on four posts, and the sign.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "AwningPost", Vector3.new(0.5, 11, 0.5), f * CFrame.new(sx * 6.5, 5.5, 1 + sz * 3.8), C.woodDark, M.Wood)
		end
	end
	for i = 0, 5 do
		part(model, "Awning" .. i, Vector3.new(2.3, 0.3, 9), f * CFrame.new(-5.75 + i * 2.3, 11.2, 1) * CFrame.Angles(math.rad(8), 0, 0), if i % 2 == 0 then C.gold else C.paper, M.Fabric)
	end
	local sign = part(model, "Sign", Vector3.new(4, 4, 0.4), f * CFrame.new(0, 13.6, -3), C.woodDark, M.Wood)
	textOn(sign, Enum.NormalId.Front, "両", C.gold)
end

-- Chakra crystals: glowing blue crystal shards bursting from a rock, a floating shard and drifting sparks.
local function buildChakraCrystals(model, solid, f, prefix)
	part(solid, prefix .. "Rock", Vector3.new(14, 4, 12), f * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.rad(15), 0), C.cliff, M.Slate)
	part(model, "RockTop", Vector3.new(10, 2, 8), f * CFrame.new(1, 3.8, 0.5) * CFrame.Angles(0, math.rad(-10), math.rad(5)), C.cliffDark, M.Slate)
	local function shard(parent, name, x, z, height, width, tiltX, tiltZ, glowing)
		local color = if glowing then C.chakra else C.chakraDeep
		local material = if glowing then M.Neon else M.Glass
		local base = f * CFrame.new(x, 3, z) * CFrame.Angles(math.rad(tiltX), 0, math.rad(tiltZ))
		local body = part(parent, name, Vector3.new(width, height, width), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.rad(45), 0), color, material)
		local tip = part(model, name .. "Tip", Vector3.new(width * 0.7, width * 0.7, width * 0.7), base * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), color, material)
		if not glowing then
			body.Transparency = 0.2
			tip.Transparency = 0.2
		end
	end
	shard(solid, prefix .. "Core", 0, 0, 13, 3.4, 0, 4, true)
	for i, s in { { 3, 1, 8, 2.4, 0, -22 }, { -3, -1, 9, 2.6, 8, 20 }, { 1, -3.5, 6, 2, 25, -6 }, { -2, 3, 7, 2.2, -22, 10 }, { 4.5, -2, 5, 1.6, 15, -30 }, { -4.5, 1.5, 4.5, 1.6, -10, 32 } } do
		shard(model, "Shard" .. i, s[1], s[2], s[3], s[4], s[5], s[6], i % 2 == 0)
	end
	local floater = part(model, "FloatingShard", Vector3.new(1.6, 1.6, 1.6), f * CFrame.new(0, 19.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), C.chakra, M.Neon)
	local light = Instance.new("PointLight")
	light.Color = C.chakra
	light.Range = 22
	light.Brightness = 2
	light.Parent = floater
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(C.chakra)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.5, 0)
	sparks.Lifetime = NumberRange.new(2, 3)
	sparks.Rate = 6
	sparks.Speed = NumberRange.new(1, 2.5)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, 1, 0)
	sparks.Parent = floater
end

-- Chakra spring: a stone-ringed pool of glowing chakra water with wisps rising off it, a bamboo
-- spout pouring in and two blue-lit lanterns.
local function buildChakraSpring(model, solid, f, prefix)
	local c = f.Position
	cylinder(solid, prefix .. "Rim", c + Vector3.new(0, 1.5, 0), 16, 3, C.stone, M.Cobblestone)
	local water = cylinder(model, "Water", c + Vector3.new(0, 3.05, 0), 13.4, 0.2, C.chakra, M.Neon)
	water.Transparency = 0.1
	local glow = Instance.new("PointLight")
	glow.Color = C.chakra
	glow.Range = 20
	glow.Brightness = 1.5
	glow.Parent = water
	for i = 0, 9 do
		local a = i * math.pi / 5
		ball(model, "RimStone" .. i, c + Vector3.new(math.cos(a) * 7.6, 3.1, math.sin(a) * 7.6), 2 + (i % 3) * 0.4, C.ruin, M.Slate)
	end
	local mist = part(model, "Mist", Vector3.new(11, 0.2, 11), CFrame.new(c + Vector3.new(0, 3.3, 0)), C.chakra, M.SmoothPlastic)
	mist.Transparency = 1
	local wisps = Instance.new("ParticleEmitter")
	wisps.Shape = Enum.ParticleEmitterShape.Box
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	wisps.EmissionDirection = Enum.NormalId.Top
	wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisps.Color = ColorSequence.new(C.chakra)
	wisps.LightEmission = 0.8
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.5) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(2.5, 4)
	wisps.Rate = 4
	wisps.Speed = NumberRange.new(1.5, 3)
	wisps.Parent = mist
	-- Bamboo spout pouring into the pool from the back.
	part(model, "SpoutStand", Vector3.new(0.6, 6, 0.6), f * CFrame.new(0, 3, 9.5), C.bamboo, M.Wood)
	part(model, "Spout", Vector3.new(0.8, 0.8, 5), f * CFrame.new(0, 5.6, 7.6) * CFrame.Angles(math.rad(-14), 0, 0), C.bamboo, M.Wood)
	-- Blue-lit lanterns either side.
	for _, side in { -1, 1 } do
		local name = prefix .. (if side < 0 then "LanternLeft" else "LanternRight")
		lanternAt(solid, model, name, (f * CFrame.new(side * 11, 0, 3)).Position)
		model[name .. "Light"].Color = C.chakra
	end
end

local NODE_KINDS = {
	RyoMine = { display = "Ryo Mine", resource = "Ryo", rate = 1, capacity = 3000, color = C.gold, build = buildRyoMine },
	MerchantCache = { display = "Merchant Cache", resource = "Ryo", rate = 1, capacity = 2000, color = C.gold, build = buildMerchantCache },
	ChakraCrystals = { display = "Chakra Crystals", resource = "Chakra", rate = 1, capacity = 1500, color = C.chakra, build = buildChakraCrystals },
	ChakraSpring = { display = "Chakra Spring", resource = "Chakra", rate = 1, capacity = 1500, color = C.chakra, build = buildChakraSpring },
}

-- Places one resource node of `kindName` at layout (x, z), its front facing `toward` (studs).
local function resourceNode(nodeFolder, solid, kindName, id, x, z, toward)
	local kind = NODE_KINDS[kindName]
	local c = P(x, 0, z)
	local f = CFrame.lookAt(c, Vector3.new(toward.X, 0, toward.Z))
	local model = Instance.new("Model")
	model.Name = "Node_" .. id
	model:SetAttribute("NodeId", id)
	model:SetAttribute("Kind", kindName)
	model:SetAttribute("DisplayName", kind.display)
	model:SetAttribute("ResourceType", kind.resource)
	model:SetAttribute("GatherRatePerUnit", kind.rate)
	model:SetAttribute("Capacity", kind.capacity)
	model:SetAttribute("Remaining", kind.capacity)
	model:SetAttribute("GatherRadius", GATHER_RADIUS)
	model:SetAttribute("MaxGatherers", 6)
	model:SetAttribute("Level", 1)
	model:SetAttribute("MaxLevel", 3)

	-- The gather ring: a faint disc in the resource's colour where units stand to gather.
	local ring = groundDisc(model, "GatherZone", x, z, GATHER_RADIUS * 2, kind.color, M.SmoothPlastic, 0.055)
	ring.Transparency = 0.8
	model.PrimaryPart = ring
	kind.build(model, solid, f, id)

	-- Where the client's info board hangs (see Client/UI/ResourceBillboards).
	local anchor = part(model, "LabelAnchor", Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, 22, 0)), kind.color, M.SmoothPlastic)
	anchor.Transparency = 1

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	ring.CastShadow = false
	CollectionService:AddTag(model, RESOURCE_TAG)
	model.Parent = nodeFolder
end

-- Command bases -------------------------------------------------------------------------------
-- Each team's headquarters, in the spirit of a Halo Wars 2 main base: the HQ building that
-- small units come out of, a ring of build sockets for the structures players will add, and
-- turret sockets either side of the entrance. Each is a Model in Workspace.Map.CommandBases
-- tagged "CommandBase", with its settings as attributes:
--   Team ("North" / "South"), Slot (player slot), Faction, Tier / MaxTier (base upgrades:
--   1 Outpost -> 2 Station -> 3 Fortress), Health / MaxHealth
-- and these children for future systems and UI:
--   Door     the unit door, tagged "UnitDoor". Attachments: ExitPoint (where new units appear),
--            RallyPoint (default gathering spot, can be moved) and UIAnchor (where a production
--            menu or queue display can be adorned). Attribute ProducesUnits = true.
--   Sockets  build plots: SocketIndex, SocketType ("Building" / "Turret"), Occupied = false.
-- Nothing reads them yet. The HQ building is solid (in Obstacles); everything inside the model
-- is non-colliding.

local BASE_TAG = "CommandBase"
local DOOR_TAG = "UnitDoor"
local HQ_START_DISTANCE = 48 -- studs from the HQ centre to where the starting army stands

-- Leaf village headquarters, after the Hokage residence: a round orange tower with tiered blue
-- roofs, a band of windows, a big 火 (fire) plaque and a gabled entrance porch. Builders draw
-- around the frame `f` (HQ centre on the ground, local -Z towards the door) and return the
-- local z of the porch front, where the unit door goes.
local function buildLeafHeadquarters(model, solid, f, prefix)
	local orange = Color3.fromRGB(204, 112, 66)
	local function at3(x, y, z)
		return f * CFrame.new(x, y, z)
	end
	cylinder(solid, prefix .. "Plinth", at3(0, 1, 0).Position, 50, 2, C.stone, M.Cobblestone)
	cylinder(solid, prefix .. "Tower", at3(0, 13, 0).Position, 40, 22, orange, M.Plaster)
	-- A band of windows round the tower, leaving the front clear for the porch.
	for i = 1, 11 do
		local around = f * CFrame.Angles(0, math.rad(i * 30), 0)
		part(model, "WindowFrame" .. i, Vector3.new(3.8, 4.8, 0.2), around * CFrame.new(0, 15, -20.05), C.woodDark, M.Wood)
		part(model, "Window" .. i, Vector3.new(3, 4, 0.2), around * CFrame.new(0, 15, -20.2), C.paper, M.SmoothPlastic)
	end
	-- Tiered roofs with a gold finial.
	cylinder(model, "RoofEave", at3(0, 24.8, 0).Position, 48, 1.6, C.northRoof, M.Slate)
	cylinder(model, "UpperTier", at3(0, 28.6, 0).Position, 32, 6, orange, M.Plaster)
	for i = 0, 7 do
		local around = f * CFrame.Angles(0, math.rad(i * 45 + 22.5), 0)
		part(model, "UpperWindow" .. i, Vector3.new(2.4, 2.6, 0.2), around * CFrame.new(0, 28.6, -16.1), C.paper, M.SmoothPlastic)
	end
	cylinder(model, "UpperEave", at3(0, 32.3, 0).Position, 38, 1.4, C.northRoof, M.Slate)
	cylinder(model, "RoofCap", at3(0, 35, 0).Position, 22, 4, C.northRoof, M.Slate)
	cylinder(model, "Finial", at3(0, 39, 0).Position, 1.2, 4, C.gold, M.Metal)
	-- The 火 plaque on the tower front, above the porch roof.
	part(model, "FirePlaqueFrame", Vector3.new(9.2, 9.2, 0.3), at3(0, 20, -20.2), C.northRoof, M.Slate)
	local plaque = part(model, "FirePlaque", Vector3.new(8, 8, 0.4), at3(0, 20, -20.45), C.paper, M.SmoothPlastic)
	textOn(plaque, Enum.NormalId.Front, "火", C.torii)
	-- Entrance porch with a gable roof, posts and team banners either side.
	part(solid, prefix .. "Porch", Vector3.new(16, 14, 10), at3(0, 7, -24), orange, M.Plaster)
	local roofBase = at3(0, 15.75, -24)
	part(model, "PorchRoofFront", Vector3.new(19, 3.5, 6.5), roofBase * CFrame.new(0, 0, -3.25), C.northRoof, M.Slate, nil, "WedgePart")
	part(model, "PorchRoofBack", Vector3.new(19, 3.5, 6.5), roofBase * CFrame.new(0, 0, 3.25) * CFrame.Angles(0, math.pi, 0), C.northRoof, M.Slate, nil, "WedgePart")
	for _, side in { -1, 1 } do
		part(model, "PorchPost", Vector3.new(1.2, 14, 1.2), at3(side * 8.2, 7, -29.2), C.woodDark, M.Wood)
		local around = f * CFrame.Angles(0, math.rad(side * 40), 0)
		part(model, "Banner", Vector3.new(4, 13, 0.3), around * CFrame.new(0, 12, -20.3), C.north, M.Fabric)
		part(model, "BannerStripe", Vector3.new(4, 1, 0.35), around * CFrame.new(0, 16, -20.35), C.paper, M.Fabric)
	end
	return -29
end

-- Sand village headquarters, after the Kazekage's tower: a broad sandstone drum under a great
-- dome painted with 風 (wind), red bands, arched windows, twin side towers and an arched porch.
local function buildSandHeadquarters(model, solid, f, prefix)
	local function at3(x, y, z)
		return f * CFrame.new(x, y, z)
	end
	cylinder(solid, prefix .. "Plinth", at3(0, 1, 0).Position, 52, 2, C.sandstoneDark, M.Sandstone)
	cylinder(solid, prefix .. "Drum", at3(0, 12, 0).Position, 44, 20, C.sandstone, M.Sandstone)
	cylinder(model, "Band", at3(0, 19, 0).Position, 44.6, 1.8, C.south, M.Fabric)
	cylinder(model, "Parapet", at3(0, 22.5, 0).Position, 45.4, 1, C.sandstoneDark, M.Sandstone)
	ball(model, "Dome", at3(0, 22, 0).Position, 40, C.sandstoneDark, M.Sandstone)
	cylinder(model, "DomeBand", at3(0, 30, 0).Position, 37, 1.2, C.south, M.Fabric)
	cylinder(model, "Spire", at3(0, 45, 0).Position, 1.4, 8, C.sandstoneDark, M.Sandstone)
	ball(model, "SpireTip", at3(0, 49.5, 0).Position, 2.4, C.south, M.SmoothPlastic)
	-- 風 painted on the dome's face, tilted to sit on its curve.
	local up = math.rad(38)
	local onDome = at3(0, 22, 0) * CFrame.Angles(up, 0, 0) * CFrame.new(0, 0, -20.1)
	local wind = part(model, "WindEmblem", Vector3.new(9, 9, 0.3), onDome, C.paper, M.SmoothPlastic)
	textOn(wind, Enum.NormalId.Front, "風", C.south)
	-- Arched windows round the drum, leaving the front clear for the porch.
	for i = 1, 11 do
		local around = f * CFrame.Angles(0, math.rad(i * 30), 0)
		part(model, "Window" .. i, Vector3.new(2.6, 3.4, 0.2), around * CFrame.new(0, 11, -22.15), C.windowDark, M.SmoothPlastic)
		part(model, "WindowArch" .. i, Vector3.new(0.2, 2.6, 2.6), around * CFrame.new(0, 12.7, -22.15) * CFrame.Angles(0, math.pi / 2, 0), C.windowDark, M.SmoothPlastic, Enum.PartType.Cylinder)
		part(model, "WindowSill" .. i, Vector3.new(3.4, 0.4, 0.8), around * CFrame.new(0, 9.1, -22.3), C.sandstoneDark, M.Sandstone)
	end
	-- Twin side towers at the back.
	for _, side in { -1, 1 } do
		local base = at3(side * 20, 0, 10)
		cylinder(solid, prefix .. "SideTower" .. (if side < 0 then "Left" else "Right"), base.Position + Vector3.new(0, 15, 0), 10, 26, C.sandstone, M.Sandstone)
		cylinder(model, "SideTowerBand", base.Position + Vector3.new(0, 24, 0), 10.6, 1.4, C.south, M.Fabric)
		ball(model, "SideTowerDome", base.Position + Vector3.new(0, 28, 0), 9, C.sandstoneDark, M.Sandstone)
	end
	-- Arched porch with a striped awning over the door.
	part(solid, prefix .. "Porch", Vector3.new(16, 16, 10), at3(0, 8, -26), C.sandstone, M.Sandstone)
	part(model, "PorchArch", Vector3.new(0.4, 12, 12), at3(0, 12, -31.1) * CFrame.Angles(0, math.pi / 2, 0), C.sandstoneDark, M.Sandstone, Enum.PartType.Cylinder)
	for i = 0, 5 do
		part(model, "Awning" .. i, Vector3.new(2.4, 1.4, 3.6), at3(-6 + i * 2.4, 15, -32.6), if i % 2 == 0 then C.south else C.paper, M.Fabric, nil, "WedgePart")
	end
	return -31
end

-- Places a team's headquarters on its pad, door facing the middle of the map, with the unit
-- door, build sockets and turret sockets.
local function commandBase(baseFolder, solid, team, slot, pad, buildHeadquarters, accent)
	local c = P(pad.x, 0, pad.z)
	local f = CFrame.lookAt(c, Vector3.zero)
	local model = Instance.new("Model")
	model.Name = "CommandBase_" .. team
	model:SetAttribute("Team", team)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Faction", GameConfig.Slots[slot].faction)
	model:SetAttribute("Tier", 1)
	model:SetAttribute("MaxTier", 3)
	model:SetAttribute("MaxHealth", 6000)
	model:SetAttribute("Health", 6000)

	local doorZ = buildHeadquarters(model, solid, f, "CommandBase" .. team)

	-- The unit door: two leaves with a team stripe, in a frame.
	part(model, "DoorFrame", Vector3.new(11.6, 13, 0.3), f * CFrame.new(0, 6.5, doorZ - 0.15), C.woodDark, M.Wood)
	local door = part(model, "Door", Vector3.new(10, 12, 0.4), f * CFrame.new(0, 6, doorZ - 0.4), C.wood, M.WoodPlanks)
	door:SetAttribute("ProducesUnits", true)
	CollectionService:AddTag(door, DOOR_TAG)
	for name, position in { ExitPoint = Vector3.new(0, -6, -10), RallyPoint = Vector3.new(0, -6, -40), UIAnchor = Vector3.new(0, 8, -1) } do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position -- in the door's space: -Z is out of the door, y = -6 is the ground
		attachment.Parent = door
	end
	part(model, "DoorSeam", Vector3.new(0.4, 12, 0.5), f * CFrame.new(0, 6, doorZ - 0.5), C.woodDark, M.Wood)
	part(model, "DoorStripe", Vector3.new(10, 0.8, 0.5), f * CFrame.new(0, 8.5, doorZ - 0.5), accent, M.Fabric)

	-- Build sockets round the back and sides, turret sockets either side of the entrance.
	local sockets = Instance.new("Folder")
	sockets.Name = "Sockets"
	sockets.Parent = model
	local index = 0
	local function socket(socketType, angle, radius, size)
		index += 1
		local cf = f * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, 0.15, -radius)
		local plot = part(sockets, "Socket" .. index, Vector3.new(size, 0.3, size), cf, C.stone, M.Cobblestone,
			if socketType == "Turret" then Enum.PartType.Cylinder else nil)
		if socketType == "Turret" then
			plot.Size = Vector3.new(0.3, size, size)
			plot.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
			cylinder(sockets, "Socket" .. index .. "Rim", cf.Position + Vector3.new(0, -0.05, 0), size + 1.2, 0.25, accent, M.SmoothPlastic)
		else
			part(sockets, "Socket" .. index .. "Rim", Vector3.new(size + 1.2, 0.25, size + 1.2), cf * CFrame.new(0, -0.05, 0), accent, M.SmoothPlastic)
			for _, cx in { -1, 1 } do
				for _, cz in { -1, 1 } do
					part(sockets, "Socket" .. index .. "Post", Vector3.new(1, 1.4, 1), cf * CFrame.new(cx * size / 2, 0.7, cz * size / 2), C.stone, M.Slate)
				end
			end
		end
		plot:SetAttribute("SocketIndex", index)
		plot:SetAttribute("SocketType", socketType)
		plot:SetAttribute("Occupied", false)
	end
	for _, angle in { 75, 115, 155, 205, 245, 285 } do
		socket("Building", angle, 46, 18)
	end
	for _, angle in { -40, 40 } do
		socket("Turret", angle, 54, 10)
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	CollectionService:AddTag(model, BASE_TAG)
	model.Parent = baseFolder
end

-- Map sections -----------------------------------------------------------------------------

local NORTH_PAD = { x = 204, z = -209 }
local SOUTH_PAD = { x = 206, z = 211 }

local function buildFloor(ground)
	local floorSize = (EDGE + CLIFF_THICK) * 2 + 120
	part(ground, "GrassFloor", Vector3.new(floorSize, 16, floorSize), CFrame.new(0, -8, 0), C.grass, M.Grass)
	-- Dry riverbed running from the training ground to the east cliffs (orange channel).
	groundPatch(ground, "Riverbed", 165, -4, L(210), L(32), C.riverbed, M.Sand, 0.04)
	-- Training ground arena floor around the central crater.
	groundDisc(ground, "ArenaFloor", 22, -2, L(88), C.dirt, M.Ground, 0.05)
	-- Spawn pads (the two light-blue landing pads on the reference's east side).
	groundPatch(ground, "NorthPadBorder", NORTH_PAD.x, NORTH_PAD.z, 64, 48, C.north, M.Slate, 0.06)
	groundPatch(ground, "NorthPad", NORTH_PAD.x, NORTH_PAD.z, 56, 40, C.stone, M.Slate, 0.08)
	groundPatch(ground, "SouthPadBorder", SOUTH_PAD.x, SOUTH_PAD.z, 64, 48, C.south, M.Sandstone, 0.06)
	groundPatch(ground, "SouthPad", SOUTH_PAD.x, SOUTH_PAD.z, 56, 40, C.sandstone, M.Sandstone, 0.08)
	-- Trails from each pad down to the riverbed, through the ridge gaps.
	groundStrip(ground, "NorthTrailA", 214, -192, 228, -70, 12, C.dirt, M.Ground, 0.02)
	groundStrip(ground, "NorthTrailB", 228, -70, 228, -20, 12, C.dirt, M.Ground, 0.02)
	groundStrip(ground, "SouthTrailA", 214, 194, 228, 70, 12, C.dirt, M.Ground, 0.02)
	groundStrip(ground, "SouthTrailB", 228, 70, 228, 14, 12, C.dirt, M.Ground, 0.02)
	-- Trails from the arena's west opening towards both ramen stands.
	groundStrip(ground, "WestTrailNorth", -40, -10, -20, -170, 10, C.dirt, M.Ground, 0.02)
	groundStrip(ground, "WestTrailSouth", -40, 10, -20, 170, 10, C.dirt, M.Ground, 0.02)
	-- Drag scars fanning east from the fallen statue (the scrape lines in the reference).
	groundStrip(ground, "StatueScarA", 150, 112, 262, 50, 6, C.scar, M.Ground, 0.03)
	groundStrip(ground, "StatueScarB", 156, 122, 262, 74, 6, C.scar, M.Ground, 0.03)
	groundStrip(ground, "StatueScarC", 162, 132, 262, 98, 6, C.scar, M.Ground, 0.03)
	-- North base: a stone plaza around the pad and footpaths to each building (they end under the walls).
	groundDisc(ground, "NorthPlaza", NORTH_PAD.x, NORTH_PAD.z, 150, Color3.fromRGB(166, 160, 148), M.Cobblestone, 0.03)
	for i, target in { { 150, -258 }, { 95, -258 }, { 256, -248 }, { 258, -150 }, { 145, -222 }, { 238, -160 } } do
		groundStrip(ground, "NorthFootpath" .. i, NORTH_PAD.x, NORTH_PAD.z, target[1], target[2], 6, C.stone, M.Cobblestone, 0.025)
	end
	-- South base: a sand plaza around the pad, sand paths to each building, a rug at the stall.
	groundDisc(ground, "SouthPlaza", SOUTH_PAD.x, SOUTH_PAD.z, 150, C.sand, M.Sand, 0.03)
	for i, target in { { 150, 258 }, { 95, 258 }, { 256, 248 }, { 258, 150 }, { 145, 222 }, { 238, 160 } } do
		groundStrip(ground, "SouthFootpath" .. i, SOUTH_PAD.x, SOUTH_PAD.z, target[1], target[2], 6, C.sand, M.Sand, 0.025)
	end
	groundPatch(ground, "MarketRug", 172, 184, 8, 12, C.south, M.Fabric, 0.035)
	-- Shrine clearings (the blue circles in the west corners).
	groundDisc(ground, "ShrineClearingNorthWest", -238, -245, 64, C.stone, M.Cobblestone, 0.05)
	groundDisc(ground, "ShrineClearingSouthWest", -234, 238, 64, C.stone, M.Cobblestone, 0.05)
	-- Paved apron and road in front of the village gate.
	groundPatch(ground, "GateApron", -6, -261, 120, 36, C.stone, M.Cobblestone, 0.035)
	groundStrip(ground, "GateRoad", -6, -252, -10, -200, 14, C.stone, M.Cobblestone, 0.025)
end

-- The Sand village's ground: sand spreading out from the south base, around the fallen statue
-- and up to the river ridge, fading into the grass at its edges. It is rows of flat tiles whose
-- colour steps from grass to sand; neighbouring tiles of the same step are merged.
local SAND_PATCHES = { -- { x, z, radius } in studs
	{ 412, 430, 210 },
	{ 200, 330, 190 },
	{ 360, 190, 180 },
	{ 40, 300, 120 },
}

-- How sandy the ground is at (x, z) in studs: 0 = grass, 1 = full sand.
local function sandAmount(x, z)
	local amount = 0
	for _, p in SAND_PATCHES do
		local d = math.sqrt((x - p[1]) ^ 2 + (z - p[2]) ^ 2)
		amount = math.max(amount, (p[3] - d) / 80)
	end
	amount += math.noise(x / 70, z / 70, 3.7) * 0.6 -- ragged, natural-looking edges
	return math.clamp(amount, 0, 1)
end

local function buildSandGround(ground)
	local cell, steps = 8, 8
	local index = 0
	for rowZ = 40, EDGE - cell, cell do
		local runStart, runStep = nil, 0
		local function flush(endX)
			if runStart and runStep > 0 then
				index += 1
				local t = runStep / steps
				local width = endX - runStart
				part(ground, "Sand" .. index, Vector3.new(width, 0.2, cell), CFrame.new(runStart + width / 2, 0.01 - 0.1, rowZ + cell / 2),
					C.grass:Lerp(C.sand, t), if t >= 0.5 then M.Sand else M.Grass)
			end
		end
		for x = -120, EDGE - cell, cell do
			local step = math.round(sandAmount(x + cell / 2, rowZ + cell / 2) * steps)
			if step ~= runStep then
				flush(x)
				runStart, runStep = x, step
			end
		end
		flush(EDGE)
	end
end

local function buildNorthCompound(solid, deco)
	-- Stone compound wall: the L-shaped wall west of the north base.
	wall(solid, "CompoundWallWest", 34, -216, 48, -168, 9, 11, C.stone, M.Cobblestone, 9)
	wall(solid, "CompoundWallSouth", 48, -168, 126, -149, 9, 11, C.stone, M.Cobblestone, 9)
	wall(deco, "CompoundWallWestCap", 34, -216, 48, -168, 11, 1.4, C.northRoof, M.Slate, 11, 11)
	wall(deco, "CompoundWallSouthCap", 48, -168, 126, -149, 11, 1.4, C.northRoof, M.Slate, 11, 11)
	-- Watchtower on the wall corner.
	part(solid, "Watchtower", Vector3.new(13, 20, 13), at(48, 10, -168, 14), C.wood, M.WoodPlanks)
	part(deco, "WatchtowerDeck", Vector3.new(18, 1, 18), at(48, 20.5, -168, 14), C.woodDark, M.Wood)
	part(deco, "WatchtowerRoof", Vector3.new(16, 3.5, 16), at(48, 26, -168, 14), C.northRoof, M.Slate)
	for i, o in { { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } } do
		part(deco, "WatchtowerPost" .. i, Vector3.new(0.9, 4.5, 0.9), at(48, 0, -168, 14) * CFrame.new(o[1], 22.8, o[2]), C.woodDark, M.Wood)
	end
	-- Clan banners on the inner (north) face of the south wall.
	local normal = Vector3.new(0.237, 0, -0.971)
	for i, t in { 0.25, 0.5, 0.75 } do
		local pos = P(48 + 78 * t, 6.5, -168 + 19 * t) + normal * 5.2
		part(deco, "ClanBanner" .. i, Vector3.new(4, 7, 0.3), CFrame.lookAt(pos, pos + normal), C.north, M.Fabric)
	end
	-- Wooden barricade: the dark trench south-west of the north base.
	wall(solid, "WoodenBarricade", 114, -132, 180, -101, 5, 8, C.wood, M.Wood)
	for i = 0, 14 do
		local t = i / 14
		part(deco, "BarricadeStake" .. i, Vector3.new(1.4, 3.5, 1.4),
			at(114 + 66 * t, 9, -132 + 31 * t) * CFrame.Angles(math.rad(20), 0, 0), C.woodDark, M.Wood)
	end
	-- Village buildings, fronts facing into the base (mirrored by the south fortress's sand buildings).
	local north, south, west, east = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0)
	leafHouse(solid, deco, "LeafHouseA", 150, -inFromEdge(12), 40, 22, 13, south, C.north, C.northRoof)
	leafHouse(solid, deco, "LeafHouseB", 95, -inFromEdge(12), 34, 22, 12, south, C.north, C.northRoof)
	leafHouse(solid, deco, "LeafHouseC", inFromEdge(12), -150, 38, 22, 13, west, C.north, C.northRoof)
	leafHouse(solid, deco, "LeafDojo", inFromEdge(18), -248, 60, 34, 16, west, C.north, C.northRoof, { dojo = true })
	leafHouse(solid, deco, "LeafTeaHouse", 145, -222, 24, 16, 10, east, C.north, C.northRoof)
	leafHouse(solid, deco, "LeafStoreShed", 238, -160, 16, 12, 9, north, C.north, C.northRoof)
	-- Landscaping: cherry blossoms, a well, a flower garden, hedges against the cliff.
	cherryTree(solid, deco, "CherryTreeA", 112, -232, 1.2)
	cherryTree(solid, deco, "CherryTreeB", 178, -248, 1.1)
	cherryTree(solid, deco, "CherryTreeC", 246, -195, 1.2)
	cherryTree(solid, deco, "CherryTreeD", 128, -188, 1.1)
	cherryTree(solid, deco, "CherryTreeE", 232, -260, 1.1)
	cherryTree(solid, deco, "CherryTreeF", 102, -180, 1)
	well(solid, deco, "VillageWell", 165, -182)
	flowerGarden(deco, "FlowerGarden", 180, -160, 24, 16)
	hedge(solid, deco, "HedgeA", 120, -264, 6)
	hedge(solid, deco, "HedgeB", 190, -264, 6)
	hedge(solid, deco, "HedgeC", 264, -200, 6)
	-- Banners at the plaza's exit and lanterns along the footpaths.
	nobori(solid, deco, "NoboriWest", 190, -182, C.north)
	nobori(solid, deco, "NoboriEast", 236, -200, C.north)
	for i, path in { { 150, -258, { 0.6 } }, { 95, -258, { 0.4, 0.7 } }, { 256, -248, { 0.65 } }, { 258, -150, { 0.6 } } } do
		pathLanterns(solid, deco, "PathLantern" .. i .. "_", NORTH_PAD.x, NORTH_PAD.z, path[1], path[2], path[3])
	end
end

local function buildSouthFortress(solid, deco)
	-- Toppled giant statue of a ninja (the crashed wreck in the reference), lying on its back with
	-- its head to the west. Its feet still stand on the broken pedestal to the south-east and one
	-- arm lies snapped off to the east. T is the statue's frame on the ground; local +X runs from
	-- the head to the feet and local +Y is up.
	local T = at(80, 0, 168, 30)
	local function S(lx, ly, lz)
		return T * CFrame.new(lx, ly, lz)
	end
	part(solid, "StatueChest", Vector3.new(50, 18, 38), S(-23, 8, 0), C.stone, M.Slate)
	part(solid, "StatueWaist", Vector3.new(24, 14, 32), S(14, 7, 0), C.stone, M.Slate)
	part(deco, "StatueBelt", Vector3.new(6, 14.6, 32.6), S(14, 7, 0), C.ruin, M.Slate)
	part(deco, "StatueVestCollar", Vector3.new(6, 1.6, 30), S(-45, 17.6, 0), C.ruin, M.Slate)
	part(deco, "StatueNeck", Vector3.new(10, 14, 14), S(-51, 10, 0), C.stone, M.Slate, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "Left" else "Right"
		ball(solid, "StatueShoulder" .. tag, S(-40, 9, side * 19).Position, 18, C.stone, M.Slate)
		part(solid, "StatueLeg" .. tag, Vector3.new(30, 12, 15), S(41, 6, side * 9), C.stone, M.Slate)
		-- The legs end in a rough break where the statue snapped off its feet.
		part(deco, "StatueLegBreak" .. tag, Vector3.new(2.4, 11, 13.6), S(56.6, 5.5, side * 9) * CFrame.Angles(math.rad(side * 6), 0, math.rad(10)), C.ruin, M.Slate)
		-- Scroll pouches on the flak vest.
		for i = 0, 1 do
			part(deco, "StatuePouch" .. tag .. i, Vector3.new(7, 1.6, 6), S(-32 + i * 11, 17.6, side * 9), C.ruin, M.Slate)
		end
	end
	-- Head: forehead protector (cloth band and metal plate), closed eyes, nose, spiky hair on the ground.
	ball(solid, "StatueHead", S(-64, 13, 0).Position, 28, C.stone, M.Slate)
	part(deco, "StatueHeadband", Vector3.new(5, 27.6, 27.6), S(-68, 13, 0), Color3.fromRGB(52, 56, 72), M.Fabric, Enum.PartType.Cylinder)
	part(deco, "StatueHeadplate", Vector3.new(5.6, 1.2, 12), S(-68, 26.9, 0), C.metal, M.SmoothPlastic)
	part(deco, "StatueHeadplateMark", Vector3.new(2, 0.3, 3.2), S(-68, 27.6, 0), C.ruin, M.Slate)
	for _, side in { -1, 1 } do
		part(deco, "StatueEye" .. (if side < 0 then "Left" else "Right"), Vector3.new(1, 0.5, 4.5), S(-59, 25, side * 5), C.ruin, M.Slate)
	end
	part(deco, "StatueNose", Vector3.new(4, 2, 2.6), S(-55, 24.6, 0), C.stone, M.Slate)
	for i, a in { -60, -30, 0, 30, 60 } do
		part(deco, "StatueHairSpike" .. i, Vector3.new(7, 7, 15),
			S(-64, 0, 0) * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(-20, 3, 0) * CFrame.Angles(0, math.rad(90), 0),
			C.stone, M.Slate, nil, "WedgePart")
	end
	-- Weathering: moss and cracks on the upturned surfaces.
	for i, m in { { -34, -8, 10, 8, 20, 17 }, { -12, 10, 8, 6, -15, 17 }, { 10, -6, 7, 9, 35, 14 }, { 40, 7, 8, 5, -10, 12 } } do
		part(deco, "StatueMoss" .. i, Vector3.new(m[3], 0.3, m[4]), S(m[1], m[6] + 0.15, m[2]) * CFrame.Angles(0, math.rad(m[5]), 0), C.shrub, M.Grass)
	end
	for i, k in { { -20, 4, 22, 25, 17 }, { -38, -10, 10, -40, 17 }, { 18, 8, 10, 60, 14 } } do
		part(deco, "StatueCrack" .. i, Vector3.new(k[3], 0.25, 0.5), S(k[1], k[5] + 0.1, k[2]) * CFrame.Angles(0, math.rad(k[4]), 0), C.cliffDark, M.Slate)
	end
	-- The snapped-off arm: upper arm, elbow, forearm with a bracer, and an open hand.
	local function limb(name, a, b, thick, height)
		local lift = Vector3.new(0, height / 2 - 1, 0)
		return part(solid, name, Vector3.new(thick, height, (b - a).Magnitude + thick * 0.5), CFrame.lookAt((a + b) / 2 + lift, b + lift), C.stone, M.Slate)
	end
	local shoulderEnd, elbow, wrist = Vector3.new(226, 0, 290), Vector3.new(258, 0, 274), Vector3.new(282, 0, 262)
	local along = (wrist - elbow).Unit
	limb("StatueUpperArm", shoulderEnd, elbow, 13, 12)
	ball(solid, "StatueElbow", elbow + Vector3.new(0, 5, 0), 14, C.stone, M.Slate)
	limb("StatueForearm", elbow, wrist, 11, 10)
	part(deco, "StatueBracer", Vector3.new(11.8, 10.6, 7), CFrame.lookAt(wrist - along * 5 + Vector3.new(0, 4, 0), wrist + Vector3.new(0, 4, 0)), C.ruin, M.Slate)
	part(deco, "StatueArmBreak", Vector3.new(14, 13, 2.4), CFrame.lookAt(shoulderEnd + Vector3.new(0, 5, 0), elbow + Vector3.new(0, 5, 0)) * CFrame.new(0, 0, 3) * CFrame.Angles(0, 0, math.rad(12)), C.ruin, M.Slate)
	local hand = CFrame.lookAt(wrist + along * 8 + Vector3.new(0, 3, 0), wrist + along * 20 + Vector3.new(0, 3, 0))
	part(solid, "StatueHand", Vector3.new(14, 7, 12), hand, C.stone, M.Slate)
	for i = 0, 3 do
		part(deco, "StatueFinger" .. i, Vector3.new(2.8, 2.8, 9), hand * CFrame.new(-4.8 + i * 3.2, 0.6, -9.5) * CFrame.Angles(math.rad(-8), 0, 0), C.stone, M.Slate)
	end
	part(deco, "StatueThumb", Vector3.new(3, 3, 7), hand * CFrame.new(8, 0.6, -2) * CFrame.Angles(0, math.rad(-50), 0), C.stone, M.Slate)
	-- The broken pedestal, with the statue's feet still standing on it.
	local ped = at(120, 0, 196, 30)
	part(deco, "StatuePedestalStep", Vector3.new(30, 1.2, 26), ped * CFrame.new(0, 0.4, 0), C.stone, M.Cobblestone)
	part(solid, "StatuePedestal", Vector3.new(24, 8, 20), ped * CFrame.new(0, 3, 0), C.ruin, M.Cobblestone)
	part(deco, "StatuePedestalCap", Vector3.new(25, 1, 21), ped * CFrame.new(0, 7.3, 0), C.stone, M.Slate)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "Left" else "Right"
		part(deco, "StatueFoot" .. tag, Vector3.new(12, 4, 7), ped * CFrame.new(1, 9.8, side * 5.5), C.stone, M.Slate)
		cylinder(deco, "StatueAnkle" .. tag, (ped * CFrame.new(-2, 13.5, side * 5.5)).Position, 7, 5, C.stone, M.Slate)
		part(deco, "StatueAnkleBreak" .. tag, Vector3.new(7.4, 1, 7.4), ped * CFrame.new(-2, 16, side * 5.5) * CFrame.Angles(math.rad(12), 0, math.rad(-9)), C.ruin, M.Slate)
	end
	local pedestalPlaque = part(deco, "StatuePlaque", Vector3.new(10, 3.4, 0.4), ped * CFrame.new(0, 3.6, 10.2), C.metal, M.Metal)
	textOn(pedestalPlaque, Enum.NormalId.Back, "英雄", C.ruin)
	-- Chunks of stone scattered around the fall.
	local debrisRng = Random.new(5)
	for i = 1, 10 do
		local a = debrisRng:NextNumber(0, 2 * math.pi)
		local r = debrisRng:NextNumber(30, 55)
		local pos = S(-10 + math.cos(a) * r * 1.4, 0, math.sin(a) * r).Position
		local s = debrisRng:NextNumber(1.5, 3.5)
		part(deco, "StatueDebris" .. i, Vector3.new(s * 1.3, s, s), CFrame.new(pos + Vector3.new(0, s / 2 - 0.3, 0)) * CFrame.Angles(debrisRng:NextNumber(0, 1), debrisRng:NextNumber(0, 6), debrisRng:NextNumber(0, 1)), C.stone, M.Slate)
	end
	rock(solid, "StatueRubbleA", 58, 142, 12, 8, 12, 35)
	-- Sand village buildings, doorways facing the pad (mirror of the north compound's houses and dojo).
	local pad = P(SOUTH_PAD.x, 0, SOUTH_PAD.z)
	sandHouse(solid, deco, "SandTowerA", 150, inFromEdge(17), 32, 26, pad, C.south, { rows = 2, spire = true })
	sandHouse(solid, deco, "SandTowerB", 95, inFromEdge(15), 28, 18, pad, C.south)
	sandHouse(solid, deco, "SandTowerC", inFromEdge(17), 150, 32, 22, pad, C.south, { rows = 2 })
	sandHouse(solid, deco, "SandDomeHall", inFromEdge(28), 248, 54, 18, pad, C.south, { crest = true, spire = true })
	sandHouse(solid, deco, "SandHut", 145, 222, 18, 12, pad, C.south)
	sandHouse(solid, deco, "SandStoreHut", 238, 160, 16, 12, pad, C.south)
	-- Landscaping: palms, a market stall, a desert garden, cacti against the cliff.
	palmTree(solid, deco, "PalmA", 112, 232, 1.1)
	palmTree(solid, deco, "PalmB", 178, 248, 1)
	palmTree(solid, deco, "PalmC", 246, 195, 1.1)
	palmTree(solid, deco, "PalmD", 138, 182, 1)
	palmTree(solid, deco, "PalmE", 232, 260, 1)
	palmTree(solid, deco, "PalmF", 102, 180, 1.1)
	marketStall(solid, deco, "MarketStall", 165, 184, Vector3.new(1, 0, 0), C.south)
	desertGarden(deco, "DesertGarden", 180, 160, 24, 16)
	cactus(solid, deco, "CactusA", 120, 264, 8)
	cactus(solid, deco, "CactusB", 190, 262, 7)
	cactus(solid, deco, "CactusC", 262, 200, 9)
	-- Banners at the plaza's exit and sandstone lanterns along the footpaths.
	nobori(solid, deco, "NoboriWest", 190, 182, C.south)
	nobori(solid, deco, "NoboriEast", 236, 200, C.south)
	for i, path in { { 150, 258, { 0.6 } }, { 95, 258, { 0.4, 0.7 } }, { 256, 248, { 0.65 } }, { 258, 150, { 0.6 } } } do
		pathLanterns(solid, deco, "PathLantern" .. i .. "_", SOUTH_PAD.x, SOUTH_PAD.z, path[1], path[2], path[3], C.sandstone, C.south)
	end
end

local function buildTrainingGround(solid, deco)
	-- Two curved bone-white walls around the central crater, open to the east and west.
	arcWall(solid, "BoneArcNorth", 22, -2, 50, -150, -40, 10, 7, 12, C.bone, M.Limestone)
	arcWall(solid, "BoneArcSouth", 22, -2, 50, 35, 140, 10, 7, 12, C.bone, M.Limestone)
	-- The crater itself now holds the centre resource point (see buildPOIs); a stone dais marks it.
	cylinder(deco, "CraterDais", P(22, 0.15, -2), 46, 0.3, C.stone, M.Cobblestone)
	-- Training posts: a row on the north side and a matching row on the south side.
	for i, x in { 4, 14, 24, 34 } do
		cylinder(solid, "TrainingPostNorth" .. i, P(x, 3.5, -32), 3, 7, C.wood, M.Wood)
		cylinder(solid, "TrainingPostSouth" .. i, P(x, 3.5, 28), 3, 7, C.wood, M.Wood)
	end
	part(solid, "MemorialStone", Vector3.new(3.5, 10, 13), at(50, 4, -2, 0), C.ruin, M.Slate)
end

-- A broken rock ridge along the line (x1, z1) -> (x2, z2); `segments` are {fromX, toX}.
local function ridge(solid, name, x1, z1, x2, z2, segments)
	local function zAt(x)
		return z1 + (x - x1) * (z2 - z1) / (x2 - x1)
	end
	for i, s in segments do
		wall(solid, name .. i, s[1], zAt(s[1]), s[2], zAt(s[2]), 14, 10, C.cliff, M.Slate)
		local midX = (s[1] + s[2]) / 2
		rock(solid, name .. i .. "Boulder", midX, zAt(midX), 18, 14, 18, 30 * i, C.cliffDark)
	end
end

local function buildRiverRidges(solid)
	ridge(solid, "RidgeNorth", 96, -48, 270, -36, { { 96, 136 }, { 160, 210 }, { 244, 276 } })
	ridge(solid, "RidgeSouth", 92, 28, 270, 58, { { 92, 136 }, { 160, 210 }, { 244, 276 } })
end

local function buildRuins(solid, deco)
	-- Ruined stone wall (the long dark wreck in the north-west), with one gap.
	wall(solid, "RuinWallWest", -150, -152, -100, -136, 18, 12, C.ruin, M.Cobblestone)
	wall(solid, "RuinWallEast", -84, -131, -36, -116, 18, 12, C.ruin, M.Cobblestone)
	part(deco, "RuinBrokenTopA", Vector3.new(10, 5, 14), at(-130, 13, -146, 17) * CFrame.Angles(0, 0, math.rad(12)), C.ruin, M.Cobblestone)
	part(deco, "RuinBrokenTopB", Vector3.new(14, 4, 14), at(-56, 13, -122, 17), C.ruin, M.Cobblestone)
	-- Fallen tree trunk (the thin spike line west of the ruins).
	wall(solid, "FallenLog", -240, -151, -170, -147, 6, 6, C.woodDark, M.Wood)
	-- Rubble near the north gate.
	rock(solid, "GateRubbleA", -80, -240, 20, 12, 16, 20)
	rock(solid, "GateRubbleC", -38, -248, 16, 10, 14, 40)
	-- Lone boulders in the west field.
	rock(solid, "FieldBoulderA", -72, -68, 14, 10, 12, 25)
	rock(solid, "FieldBoulderB", -80, -44, 11, 8, 11, -10)
end

local function buildWestFort(solid, deco)
	-- Wooden palisade U (the U-shaped wall on the west side), open to the east.
	wall(solid, "FortBackWall", -213, -80, -213, 54, 10, 11, C.wood, M.WoodPlanks, 10)
	wall(solid, "FortNorthWall", -213, -80, -160, -80, 10, 11, C.wood, M.WoodPlanks, 10)
	wall(solid, "FortSouthWall", -213, 54, -160, 54, 10, 11, C.wood, M.WoodPlanks, 10)
	for i = 0, 26 do
		part(deco, "BackStake" .. i, Vector3.new(1.6, 3.5, 1.6), at(-213, 12.5, -80 + i * 134 / 26), C.woodDark, M.Wood)
	end
	for i = 0, 10 do
		local x = -213 + i * 53 / 10
		part(deco, "NorthStake" .. i, Vector3.new(1.6, 3.5, 1.6), at(x, 12.5, -80), C.woodDark, M.Wood)
		part(deco, "SouthStake" .. i, Vector3.new(1.6, 3.5, 1.6), at(x, 12.5, 54), C.woodDark, M.Wood)
	end
	for i, z in { -40, -20, 6, 26 } do
		cylinder(solid, "TrainingDummy" .. i, P(-192, 3, z), 2, 6, C.wood, M.Wood)
	end
	for i, z in { -55, -12, 30 } do
		part(deco, "TargetBoard" .. i, Vector3.new(0.4, 5, 5), CFrame.new(P(-213, 6, z) + Vector3.new(5.2, 0, 0)), C.plaster, M.Fabric)
	end
	house(solid, deco, "ArcheryShed", -201, 44, 16, 12, 8, 0, C.woodDark, C.woodDark)
	rock(solid, "FortMouthOutcrop", -140, -8, 22, 12, 20, 15)
	-- West corridor behind the fort.
	lanternAt(solid, deco, "CorridorLanternNorth", P(-235, 0, -95))
	lanternAt(solid, deco, "CorridorLanternSouth", P(-235, 0, 70))
end

local function buildSouthWestRuins(solid, deco)
	-- Collapsed wooden watchtower (the wreck in the south-west field).
	wall(solid, "CollapsedTowerFrame", -104, 128, -30, 112, 16, 10, C.woodDark, M.Wood)
	part(solid, "CollapsedTowerRoof", Vector3.new(22, 8, 20), at(-114, 4, 134, 20) * CFrame.Angles(0, 0, math.rad(-14)),
		Color3.fromRGB(96, 80, 66), M.Slate)
	for i, p in { { -90, 108, 30 }, { -48, 132, -25 }, { -20, 104, 60 }, { -70, 140, 10 } } do
		part(deco, "ScatteredPlank" .. i, Vector3.new(10, 0.6, 1.6), at(p[1], 0.3, p[2], p[3]), C.wood, M.WoodPlanks)
	end
	rock(solid, "SouthRubbleA", -84, 214, 16, 10, 14, 30)
	-- Mirrors of the north's gate rubble and west-field boulders, so both halves offer the same cover.
	rock(solid, "SouthRubbleC", -38, 248, 16, 10, 14, -40)
	rock(solid, "FieldBoulderC", -72, 68, 14, 10, 12, -25)
	rock(solid, "FieldBoulderD", -80, 44, 11, 8, 11, 10)
end

-- Neutral features added for the bigger map, placed as north/south mirror pairs.
local function buildNeutralPairs(solid, deco)
	-- Ramen stands beside the west trails, opening towards the trail.
	ramenStand(solid, deco, "RamenStandNorth", -20, -180, 1)
	ramenStand(solid, deco, "RamenStandSouth", -20, 180, -1)
	-- Bamboo forests filling the west corners around the shrines. Trails lead through each one
	-- to its shrine: one from the west corridor and one from the east.
	bambooForest(solid, deco, "BambooForestNorth", -258, -232, -100, -170,
		{ { -205, -160, -228, -228, 26 }, { -90, -205, -205, -205, 26 } }, { { -238, -245, 24 } }, 11)
	bambooForest(solid, deco, "BambooForestSouth", -258, 232, -100, 170,
		{ { -205, 160, -228, 228, 26 }, { -90, 205, -205, 205, 26 } }, { { -234, 238, 24 } }, 11)
	-- Rock outcrops on the west flank, between the fort and the centre.
	rock(solid, "OutcropNorthA", -112, -96, 22, 13, 18, 15)
	rock(solid, "OutcropNorthB", -100, -104, 12, 9, 12, -25, C.cliffDark)
	rock(solid, "OutcropSouthA", -112, 92, 22, 13, 18, -15)
	rock(solid, "OutcropSouthB", -100, 100, 12, 9, 12, 25, C.cliffDark)
	-- Lone trees: one per half beside the base approaches.
	tree(solid, deco, "TreeNorthField", 0, -110, 1.4)
	tree(solid, deco, "TreeSouthField", 0, 110, 1.4)
end

local function buildShrines(solid, deco)
	-- The torii gates face the map centre and stand inside each corner POI's capture zone.
	shrine(solid, deco, "ShrineNorthWest", -238, -245, Vector3.zero, 22)
	shrine(solid, deco, "ShrineSouthWest", -234, 238, Vector3.zero, 22)
end

-- Resource POIs: the centre of the training ground and the two west-corner shrines (the
-- corners opposite the spawns).
local function buildPOIs(solid, poiFolder)
	resourcePOI(poiFolder, solid, "Center", "Training Ground Spring", 3, 3, 22, -2, 40)
	resourcePOI(poiFolder, solid, "NorthWestShrine", "North-West Shrine", 2, 2, -238, -245, 30)
	resourcePOI(poiFolder, solid, "SouthWestShrine", "South-West Shrine", 2, 2, -234, 238, 30)
end

-- Resource nodes, as north/south mirror pairs so each half has one of every kind:
--   Ryo mines on the east flank by each base, merchant caches in the west field,
--   chakra crystals out by the north and south cliffs west of centre, chakra springs by the
--   west corridor.
local function buildResourceNodes(solid, nodeFolder)
	local north, south = P(NORTH_PAD.x, 0, NORTH_PAD.z), P(SOUTH_PAD.x, 0, SOUTH_PAD.z)
	resourceNode(nodeFolder, solid, "RyoMine", "RyoMineNorth", 250, -95, north)
	resourceNode(nodeFolder, solid, "RyoMine", "RyoMineSouth", 250, 95, south)
	resourceNode(nodeFolder, solid, "MerchantCache", "MerchantCacheNorth", -125, -50, Vector3.zero)
	resourceNode(nodeFolder, solid, "MerchantCache", "MerchantCacheSouth", -125, 50, Vector3.zero)
	resourceNode(nodeFolder, solid, "ChakraCrystals", "ChakraCrystalsNorth", -60, -228, Vector3.zero)
	resourceNode(nodeFolder, solid, "ChakraCrystals", "ChakraCrystalsSouth", -60, 228, Vector3.zero)
	resourceNode(nodeFolder, solid, "ChakraSpring", "ChakraSpringNorth", -185, -118, Vector3.zero)
	resourceNode(nodeFolder, solid, "ChakraSpring", "ChakraSpringSouth", -185, 118, Vector3.zero)
end

-- One headquarters per team, standing on its spawn pad.
local function buildCommandBases(solid, baseFolder)
	commandBase(baseFolder, solid, "North", 1, NORTH_PAD, buildLeafHeadquarters, C.north)
	commandBase(baseFolder, solid, "South", 2, SOUTH_PAD, buildSandHeadquarters, C.south)
end

local function buildVegetation(solid, deco)
	tree(solid, deco, "TreeWestA", -240, 128, 1.4)
	tree(solid, deco, "TreeWestC", -240, -128, 1.4)
	tree(solid, deco, "TreeNorthWest", -150, -248, 1.3)
	tree(solid, deco, "TreeSouthWest", -150, 248, 1.3)
end

-- A carved stone head for the cliff-top monument above the blue base, facing the map (+Z):
-- jaw, forehead protector, brows, eyes, nose and mouth. `style` picks the hair so the four heads
-- read as different people: 1 long hair falling to the sides, 2 short swept-back spikes, 3 a
-- wide-brimmed hat, 4 big spiky bangs.
local function hokageHead(deco, name, base, style)
	-- Built at a 20-stud head size, then scaled up to monument size around its base.
	local head = Instance.new("Model")
	head.Name = name
	head.Parent = deco
	deco = head
	local stone, hair, dark = Color3.fromRGB(150, 144, 132), Color3.fromRGB(124, 118, 108), Color3.fromRGB(84, 80, 74)
	local function at3(x, y, z)
		return CFrame.new(base) * CFrame.new(x, y, z)
	end
	part(deco, name .. "Base", Vector3.new(16, 4, 14), at3(0, 2, 0), stone, M.Slate)
	part(deco, name .. "Jaw", Vector3.new(12, 7, 10), at3(0, 4.5, 2), stone, M.Slate)
	ball(deco, name, at3(0, 11, 0).Position, 20, stone, M.Slate)
	-- Forehead protector: a band round the head with a metal plate at the front.
	cylinder(deco, name .. "Headband", at3(0, 14, 0).Position, 20.6, 2.6, dark, M.Slate)
	part(deco, name .. "Plate", Vector3.new(6.4, 2.6, 0.8), at3(0, 14, 10.5), C.metal, M.SmoothPlastic)
	part(deco, name .. "PlateMark", Vector3.new(1.6, 1.4, 0.3), at3(0, 14, 11), dark, M.Slate)
	-- Face.
	for _, side in { -1, 1 } do
		part(deco, name .. "Eye", Vector3.new(2.6, 0.8, 0.6), at3(side * 3.5, 11, 9.3), dark, M.Slate)
		part(deco, name .. "Brow", Vector3.new(3.4, 0.9, 1), at3(side * 3.5, 12.3, 9.1) * CFrame.Angles(0, 0, math.rad(side * -10)), dark, M.Slate)
	end
	part(deco, name .. "Nose", Vector3.new(2, 3, 1.6), at3(0, 9, 9.6), stone, M.Slate)
	part(deco, name .. "Mouth", Vector3.new(3.6, 0.5, 0.5), at3(0, 5.6, 7.1), dark, M.Slate)
	-- Hair. A spike is a wedge whose point (local -Z) `tilt` swings up from horizontal.
	local function spike(i, x, y, z, roll, tilt, size)
		part(deco, name .. "Spike" .. i, Vector3.new(size, size * 0.9, size * 2.4), at3(x, y, z) * CFrame.Angles(0, 0, math.rad(roll)) * CFrame.Angles(math.rad(tilt), 0, 0), hair, M.Slate, nil, "WedgePart")
	end
	if style == 1 then
		ball(deco, name .. "Hair", at3(0, 13, -2.5).Position, 21, hair, M.Slate)
		for _, side in { -1, 1 } do
			part(deco, name .. "HairSide", Vector3.new(4, 15, 11), at3(side * 9.2, 8, -1.5), hair, M.Slate)
		end
	elseif style == 2 then
		ball(deco, name .. "Hair", at3(0, 13.5, -2).Position, 20.4, hair, M.Slate)
		for i = -2, 2 do
			spike(i + 3, i * 3.2, 19, -2, i * -10, 55, 3.2)
		end
	elseif style == 3 then
		cylinder(deco, name .. "HatBrim", at3(0, 20.5, 0).Position, 27, 1.2, hair, M.Slate)
		cylinder(deco, name .. "HatCrown", at3(0, 23, 0).Position, 15, 4, hair, M.Slate)
		part(deco, name .. "HatPlate", Vector3.new(5, 3, 0.4), at3(0, 23, 7.6), stone, M.Slate)
	else
		ball(deco, name .. "Hair", at3(0, 13.5, -2).Position, 20.4, hair, M.Slate)
		for i = -3, 3 do
			spike(i + 4, i * 2.8, 18.5, 3, i * -14, 100, 3.4)
		end
	end
	head.WorldPivot = CFrame.new(base)
	head:ScaleTo(1.8)
end

local function buildCliffs(solid, deco)
	local h, t = CLIFF_HEIGHT, CLIFF_THICK
	local outer = EDGE + t
	local mid = EDGE + t / 2
	part(solid, "CliffSouth", Vector3.new(outer * 2, h, t), CFrame.new(0, h / 2, mid), C.cliff, M.Slate)
	part(solid, "CliffWest", Vector3.new(t, h, outer * 2), CFrame.new(-mid, h / 2, 0), C.cliff, M.Slate)
	part(solid, "CliffEast", Vector3.new(t, h, outer * 2), CFrame.new(mid, h / 2, 0), C.cliff, M.Slate)
	part(deco, "CliffTopSouth", Vector3.new(outer * 2, 1, t), CFrame.new(0, h + 0.5, mid), C.grassDark, M.Grass)
	part(deco, "CliffTopWest", Vector3.new(t, 1, outer * 2), CFrame.new(-mid, h + 0.5, 0), C.grassDark, M.Grass)
	part(deco, "CliffTopEast", Vector3.new(t, 1, outer * 2), CFrame.new(mid, h + 0.5, 0), C.grassDark, M.Grass)

	-- The north cliff has a notch for the village gate (the structure on the reference's top edge).
	local gateX, gateHalf, notch = L(-6), 40, 14
	local westEnd, eastStart = gateX - gateHalf, gateX + gateHalf
	part(solid, "CliffNorthWest", Vector3.new(westEnd + outer, h, t), CFrame.new((westEnd - outer) / 2, h / 2, -mid), C.cliff, M.Slate)
	part(solid, "CliffNorthEast", Vector3.new(outer - eastStart, h, t), CFrame.new((outer + eastStart) / 2, h / 2, -mid), C.cliff, M.Slate)
	part(solid, "CliffBehindGate", Vector3.new(gateHalf * 2, h, t - notch), CFrame.new(gateX, h / 2, -(EDGE + notch + (t - notch) / 2)), C.cliff, M.Slate)
	part(deco, "CliffTopNorthWest", Vector3.new(westEnd + outer, 1, t), CFrame.new((westEnd - outer) / 2, h + 0.5, -mid), C.grassDark, M.Grass)
	part(deco, "CliffTopNorthEast", Vector3.new(outer - eastStart, 1, t), CFrame.new((outer + eastStart) / 2, h + 0.5, -mid), C.grassDark, M.Grass)

	-- Rocky strip behind the west fort, narrowing the corridor there.
	local jutZ = L(-15)
	part(solid, "WestCliffJut", Vector3.new(64, 24, 180), CFrame.new(-EDGE + 26, 12, jutZ), C.cliffDark, M.Slate)

	-- Jagged rocks along the inner cliff face, so the edge reads as cliffs, not a box.
	local rng = Random.new(7)
	local index = 0
	for s = -EDGE + 15, EDGE - 15, 30 do
		index += 1
		for _, side in { "North", "South", "West", "East" } do
			local skip = (side == "North" and math.abs(s - gateX) < gateHalf + 30)
				or (side == "West" and math.abs(s - jutZ) < 110)
			if not skip then
				local w, hh, d = rng:NextNumber(14, 26), rng:NextNumber(18, 36), rng:NextNumber(10, 14)
				local inset = d / 2 - rng:NextNumber(3, 7) -- how far the rock's centre sits behind the cliff face
				local along = s + rng:NextNumber(-6, 6)
				local x, z, yaw
				if side == "North" then
					x, z, yaw = along, -EDGE - inset, 0
				elseif side == "South" then
					x, z, yaw = along, EDGE + inset, 0
				elseif side == "West" then
					x, z, yaw = -EDGE - inset, along, 90
				else
					x, z, yaw = EDGE + inset, along, 90
				end
				rockAt(solid, "EdgeRock" .. side .. index, x, z, w, hh, d, yaw + rng:NextNumber(-20, 20),
					if rng:NextNumber() < 0.5 then C.cliff else C.cliffDark)
			end
		end
	end

	-- Village gate, sealed: the great gate in the north cliff notch (the structure on the
	-- reference's top edge). The pillars and doors are solid; everything else is decor.
	local gateZ = -EDGE - 5 -- the pillars' centre line
	local doorZ = -(EDGE + notch - 1.5)
	part(solid, "GateDoors", Vector3.new(gateHalf * 2, 32, 3), CFrame.new(gateX, 16, doorZ), C.wood, M.WoodPlanks)
	part(deco, "GateDoorSeam", Vector3.new(0.8, 30, 0.6), CFrame.new(gateX, 16, doorZ + 1.8), C.woodDark, M.Wood)
	part(deco, "GateDoorHeader", Vector3.new(gateHalf * 2, 2, 1.6), CFrame.new(gateX, 31.5, doorZ + 1.6), C.woodDark, M.Wood)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		local px = gateX + side * (gateHalf + 7)
		-- Pillar: stone plinth, wooden post with metal bands, a paper banner down its face.
		part(solid, "GatePillar" .. tag, Vector3.new(14, 44, 14), CFrame.new(px, 22, gateZ), C.woodDark, M.Wood)
		part(deco, "GatePillarPlinth" .. tag, Vector3.new(18, 6, 18), CFrame.new(px, 3, gateZ), C.stone, M.Cobblestone)
		for i, y in { 14, 30 } do
			part(deco, "GatePillarBand" .. tag .. i, Vector3.new(14.6, 1.4, 14.6), CFrame.new(px, y, gateZ), C.metal, M.Metal)
		end
		local banner = part(deco, "GateBanner" .. tag, Vector3.new(6, 14, 0.3), CFrame.new(px, 22, gateZ + 7.3), C.paper, M.Fabric)
		textOn(banner, Enum.NormalId.Back, if side < 0 then "忍" else "隠", C.torii)
		-- Door leaf: green panel with a big character, iron bands and a ring pull.
		local leafX = gateX + side * gateHalf / 2
		local leaf = part(deco, "GateDoorLeaf" .. tag, Vector3.new(gateHalf - 1.2, 29, 0.4), CFrame.new(leafX, 16, doorZ + 1.7), C.gateRoof, M.WoodPlanks)
		textOn(leaf, Enum.NormalId.Back, if side < 0 then "あ" else "ん", C.torii)
		for i, y in { 4, 28 } do
			part(deco, "GateDoorBand" .. tag .. i, Vector3.new(gateHalf - 1.2, 1.2, 0.3), CFrame.new(leafX, y, doorZ + 2), C.metal, M.Metal)
		end
		part(deco, "GateDoorRing" .. tag, Vector3.new(0.4, 3.4, 3.4), CFrame.new(gateX + side * 3.5, 14, doorZ + 2.1) * CFrame.Angles(0, math.rad(90), 0), C.metal, M.Metal, Enum.PartType.Cylinder)
		-- A tall stone lantern in front of the gate.
		local base = Vector3.new(gateX + side * 62, 0, -EDGE + 10)
		part(solid, "GateLantern" .. tag, Vector3.new(7, 3, 7), CFrame.new(base + Vector3.new(0, 1.5, 0)), C.stone, M.Cobblestone)
		part(deco, "GateLanternShaft" .. tag, Vector3.new(3, 8, 3), CFrame.new(base + Vector3.new(0, 7, 0)), C.stone, M.Cobblestone)
		part(deco, "GateLanternHousing" .. tag, Vector3.new(5.5, 4.5, 5.5), CFrame.new(base + Vector3.new(0, 13.2, 0)), C.stone, M.Cobblestone)
		part(deco, "GateLanternLight" .. tag, Vector3.new(5.7, 2.6, 3.4), CFrame.new(base + Vector3.new(0, 13.2, 0)), Color3.fromRGB(240, 214, 150), M.Neon)
		part(deco, "GateLanternCap" .. tag, Vector3.new(9, 1.4, 9), CFrame.new(base + Vector3.new(0, 16.1, 0)), C.stone, M.Slate)
		part(deco, "GateLanternTop" .. tag, Vector3.new(4, 1.6, 4), CFrame.new(base + Vector3.new(0, 17.6, 0)), C.stone, M.Slate)
	end
	-- Crossbeam and lintel with the village name plaque.
	part(deco, "GateCrossbeam", Vector3.new(gateHalf * 2 + 14, 3, 6), CFrame.new(gateX, 34.5, gateZ), C.woodDark, M.Wood)
	part(deco, "GateLintel", Vector3.new(gateHalf * 2 + 36, 5, 10), CFrame.new(gateX, 41.5, gateZ), C.woodDark, M.Wood)
	part(deco, "GatePlaqueFrame", Vector3.new(27.4, 5.8, 0.4), CFrame.new(gateX, 41.5, gateZ + 5.1), C.poi, M.Metal)
	local plaque = part(deco, "GatePlaque", Vector3.new(26, 4.4, 0.6), CFrame.new(gateX, 41.5, gateZ + 5.3), C.woodDark, M.Wood)
	textOn(plaque, Enum.NormalId.Back, "隠れ谷", C.poi)
	-- Tiled gable roof with deep eaves, a ridge cap and gold ridge ends.
	local roofW, rise, half = gateHalf * 2 + 48, 5, 10
	local roofBase = CFrame.new(gateX, 44 + rise / 2, gateZ)
	part(deco, "GateRoofFront", Vector3.new(roofW, rise, half), roofBase * CFrame.new(0, 0, half / 2) * CFrame.Angles(0, math.pi, 0), C.gateRoof, M.Slate, nil, "WedgePart")
	part(deco, "GateRoofBack", Vector3.new(roofW, rise, half), roofBase * CFrame.new(0, 0, -half / 2), C.gateRoof, M.Slate, nil, "WedgePart")
	part(deco, "GateRidgeCap", Vector3.new(roofW + 1, 1.4, 1.6), CFrame.new(gateX, 44 + rise + 0.3, gateZ), C.woodDark, M.Wood)
	for _, side in { -1, 1 } do
		part(deco, "GateRidgeEnd" .. (if side < 0 then "West" else "East"), Vector3.new(2.6, 3.2, 2.6), CFrame.new(gateX + side * (roofW / 2), 44 + rise + 1.4, gateZ), C.poi, M.Metal)
	end
	for i = 0, 12 do
		part(deco, "GateRafter" .. i, Vector3.new(1, 1, 6), CFrame.new(gateX - roofW / 2 + 4 + i * (roofW - 8) / 12, 43.5, gateZ + 7), C.woodDark, M.Wood)
	end
	-- The gate guard's booth just inside, east of the gate.
	leafHouse(solid, deco, "GateGuardBooth", (gateX + 100) / SCALE, -inFromEdge(6), 16, 10, 9, Vector3.new(0, 0, 1), C.gateRoof, C.gateRoof)

	-- Cliff-top monuments: carved stone heads above the north base, a giant sand gourd above the south base.
	local monumentXs = { L(85), L(125), L(165), L(205) }
	for i, x in monumentXs do
		hokageHead(deco, "HokageHead" .. i, Vector3.new(x, h, -EDGE - 16), i)
	end
	local gourd = Vector3.new(L(150), h, EDGE + 18)
	ball(deco, "SandGourdBase", gourd + Vector3.new(0, 11, 0), 24, C.sandstoneDark, M.Sandstone)
	ball(deco, "SandGourdTop", gourd + Vector3.new(0, 27, 0), 15, C.sandstoneDark, M.Sandstone)
	cylinder(deco, "SandGourdSash", gourd + Vector3.new(0, 21, 0), 11, 2.5, C.south, M.Fabric)
	cylinder(deco, "SandGourdCork", gourd + Vector3.new(0, 35, 0), 4, 3, C.woodDark, M.Wood)

end

-- Trees along the cliff tops, kept clear of the gate and the monuments. `sides` picks which
-- edges to plant, so the work can be split into smaller sections.
local function buildCliffTrees(deco, sides)
	local rng = Random.new(8)
	local gateX, gateHalf = L(-6), 40
	for s = -EDGE, EDGE, 40 do
		for _, side in sides do
			local skip = (side == "North" and (math.abs(s - gateX) < gateHalf + 40 or (s > L(70) and s < L(220))))
				or (side == "South" and math.abs(s - L(150)) < 30)
			local inset = EDGE + 22 + rng:NextNumber(-8, 8)
			local along = s + rng:NextNumber(-8, 8)
			local scale = rng:NextNumber(1, 1.4)
			if not skip then
				local pos = if side == "North" then Vector3.new(along, CLIFF_HEIGHT, -inset)
					elseif side == "South" then Vector3.new(along, CLIFF_HEIGHT, inset)
					elseif side == "West" then Vector3.new(-inset, CLIFF_HEIGHT, along)
					else Vector3.new(inset, CLIFF_HEIGHT, along)
				treeAt(nil, deco, "CliffTree" .. side .. s, pos, scale)
			end
		end
	end
end

-- A small tuft of grass blades (thin wedges, so each blade comes to a point).
local function grassTuft(deco, name, pos, rng)
	for i = 1, 5 do
		local h = rng:NextNumber(2.2, 4.2)
		local spot = pos + Vector3.new(rng:NextNumber(-1.2, 1.2), h / 2, rng:NextNumber(-1.2, 1.2))
		local blade = CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, 0)
		part(deco, name .. "Blade" .. i, Vector3.new(0.2, h, 1.1), blade, GRASS_TONES[rng:NextInteger(1, #GRASS_TONES)], M.SmoothPlastic, nil, "WedgePart")
	end
end

-- Grass tufts along the cliff tops, along the foot of the cliffs and scattered over the open
-- grass (never on sand, the arena, the spawn plazas, the riverbed or the gate apron). Decor.
local function buildGrass(_, deco)
	local rng = Random.new(21)
	local gateX = L(-6)
	local index = 0
	local function tuft(pos)
		index += 1
		grassTuft(deco, "Grass" .. index, pos, rng)
	end
	local function isOpenField(x, z)
		local p = Vector3.new(x, 0, z)
		return sandAmount(x, z) < 0.25
			and (p - P(22, 0, -2)).Magnitude > 100
			and (p - P(NORTH_PAD.x, 0, NORTH_PAD.z)).Magnitude > 80
			and (p - P(SOUTH_PAD.x, 0, SOUTH_PAD.z)).Magnitude > 80
			and not (x > L(55) and math.abs(z - L(-4)) < L(18))
			and not (math.abs(x - gateX) < 70 and z < -EDGE + 45)
	end
	-- A point `inset` studs from the map centre line on one side, `along` that side.
	local function onSide(side, inset, along, y)
		return if side == "North" then Vector3.new(along, y, -inset)
			elseif side == "South" then Vector3.new(along, y, inset)
			elseif side == "West" then Vector3.new(-inset, y, along)
			else Vector3.new(inset, y, along)
	end
	local step = 0
	for s = -EDGE + 8, EDGE - 8, 16 do
		step += 1
		for _, side in { "North", "South", "West", "East" } do
			local top = onSide(side, EDGE + rng:NextNumber(4, CLIFF_THICK - 4), s + rng:NextNumber(-5, 5), CLIFF_HEIGHT + 1)
			if not (side == "North" and math.abs(top.X - gateX) < 60) then
				tuft(top)
			end
			local foot = onSide(side, EDGE - rng:NextNumber(10, 18), s + rng:NextNumber(-5, 5), 0)
			if step % 2 == 0 and isOpenField(foot.X, foot.Z) then
				tuft(foot)
			end
		end
	end
	for _ = 1, 280 do
		local x, z = rng:NextNumber(-EDGE + 20, EDGE - 20), rng:NextNumber(-EDGE + 20, EDGE - 20)
		if isOpenField(x, z) then
			tuft(Vector3.new(x, 0, z))
		end
	end
end

local function marker(parent, name, cframe, size)
	local p = part(parent, name, size, cframe, Color3.new(1, 1, 1), M.SmoothPlastic)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function buildMarkers(markers)
	marker(markers, "PlayArea", CFrame.new(0, 0.5, 0), Vector3.new(EDGE * 2, 1, EDGE * 2))
	local starts = Instance.new("Folder")
	starts.Name = "StartPoints"
	starts.Parent = markers
	-- Each army starts on the plaza just outside its headquarters' door (the HQ stands on the
	-- pad, door facing the middle of the map) and faces the middle of the map.
	local centre = Vector3.new(0, 0.5, 0)
	local function startFor(pad)
		local hq = P(pad.x, 0.5, pad.z)
		return CFrame.lookAt(hq + (centre - hq).Unit * HQ_START_DISTANCE, centre)
	end
	local slot1 = marker(starts, "Slot1", startFor(NORTH_PAD), Vector3.new(6, 1, 6))
	slot1:SetAttribute("Base", "NorthCompound")
	local slot2 = marker(starts, "Slot2", startFor(SOUTH_PAD), Vector3.new(6, 1, 6))
	slot2:SetAttribute("Base", "SouthFortress")
end

-- Entry point ------------------------------------------------------------------------------

function BuildNinjaVillageMap.build(): string
	local old = workspace:FindFirstChild(GameConfig.Map.FolderName)
	if old then
		old:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = GameConfig.Map.FolderName
	map:SetAttribute("GeneratedBy", "ServerStorage.MapTools.BuildNinjaVillageMap")
	map:SetAttribute("Scale", SCALE)
	local folders = {}
	for _, name in { "Ground", "Obstacles", "Boundary", "Decor", "Markers", "POIs", "ResourceNodes", "CommandBases" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = map
		folders[name] = folder
	end
	map.Parent = workspace

	-- Each section is built outside the DataModel, then parented in one go.
	local function section(name: string, parentName: string, build)
		local solid = Instance.new("Folder")
		solid.Name = name
		local deco = Instance.new("Folder")
		deco.Name = name
		build(solid, deco)
		for _, d in deco:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		if #solid:GetChildren() > 0 then
			solid.Parent = folders[parentName]
		else
			solid:Destroy()
		end
		if #deco:GetChildren() > 0 then
			deco.Parent = folders.Decor
		else
			deco:Destroy()
		end
		task.wait()
	end

	section("Floor", "Ground", buildFloor)
	section("SandGround", "Ground", buildSandGround)
	section("NorthCompound", "Obstacles", buildNorthCompound)
	section("SouthFortress", "Obstacles", buildSouthFortress)
	section("TrainingGround", "Obstacles", buildTrainingGround)
	section("RiverRidges", "Obstacles", buildRiverRidges)
	section("Ruins", "Obstacles", buildRuins)
	section("WestFort", "Obstacles", buildWestFort)
	section("SouthWestRuins", "Obstacles", buildSouthWestRuins)
	section("NeutralPairs", "Obstacles", buildNeutralPairs)
	section("Shrines", "Obstacles", buildShrines)
	section("POIs", "Obstacles", function(solid)
		buildPOIs(solid, folders.POIs)
	end)
	section("ResourceNodes", "Obstacles", function(solid)
		buildResourceNodes(solid, folders.ResourceNodes)
	end)
	section("CommandBases", "Obstacles", function(solid)
		buildCommandBases(solid, folders.CommandBases)
	end)
	section("Vegetation", "Obstacles", buildVegetation)
	section("Cliffs", "Boundary", buildCliffs)
	section("CliffTreesNorthSouth", "Boundary", function(_, deco)
		buildCliffTrees(deco, { "North", "South" })
	end)
	section("CliffTreesWestEast", "Boundary", function(_, deco)
		buildCliffTrees(deco, { "West", "East" })
	end)
	section("Grass", "Obstacles", buildGrass)
	buildMarkers(folders.Markers)

	for _, d in folders.Ground:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "GrassFloor" then
			d.CastShadow = false
		end
	end

	local counts = {}
	for name, folder in folders do
		local n = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		table.insert(counts, name .. "=" .. n)
	end
	table.sort(counts)
	return "Built Workspace." .. map.Name .. " (" .. table.concat(counts, ", ") .. ")"
end

return BuildNinjaVillageMap
