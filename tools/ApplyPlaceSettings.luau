--[[
	ApplyPlaceSettings.luau
	Run once in any place that should run this game (the shared Team Create place,
	or your own test copy). Sets the place properties the RTS depends on and creates
	the top-level folders the code and art teams use.

	How to run: Studio > View > Command Bar, paste this whole file, press Enter.
	(Or ask Claude to run it through the Studio MCP.)

	Safe to run again: it never deletes anything.
]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Commanders don't have avatars: each player is a camera above the battlefield.
Players.CharacterAutoLoads = false

-- Shift is the "add to selection" key, so Roblox's Shift-lock camera must be off.
StarterPlayer.EnableMouseLockOption = false

-- An RTS camera can look anywhere on the map, so every player needs the whole map.
-- Fine for small maps; revisit for big ones (see ROADMAP.md, "Performance gates").
workspace.StreamingEnabled = false

local function ensureFolder(parent: Instance, name: string): Instance
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

-- Code folders. Script Sync links these to src/Shared, src/Server and src/Client.
ensureFolder(ReplicatedStorage, "Shared")
ensureFolder(ServerScriptService, "Server")
ensureFolder(StarterPlayer:WaitForChild("StarterPlayerScripts"), "Client")

-- Art and UI folders. These live in the place, not in Git (see CLAUDE.md).
local assets = ensureFolder(ReplicatedStorage, "Assets")
ensureFolder(assets, "Units")
ensureFolder(assets, "UI")

print("[ApplyPlaceSettings] Done.")
