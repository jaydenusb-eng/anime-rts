--[[
	Net
	Names every RemoteEvent the game uses, so the client and server can't disagree
	about spelling.

	A RemoteEvent is a door between a player's computer (the client) and Roblox's
	server. Anything that comes through a door from a client is untrusted: a cheater
	can send any value they like. Server code must check everything it receives
	(see Server/Services/CommandService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Remotes = {
	-- Client -> server: "please give these units this order".
	UnitCommand = "UnitCommand",
	-- Server -> client: short messages about an order ("Can't reach that spot.").
	CommandFeedback = "CommandFeedback",
}

-- Order kinds the server understands. Later milestones add Stop, Attack, AttackMove, Rally...
Net.CommandKind = {
	Move = "Move",
}

local FOLDER_NAME = "Remotes"

-- Server only: creates the RemoteEvents. Call once when the server starts.
function Net.createRemotes()
	assert(RunService:IsServer(), "Net.createRemotes must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Net.Remotes do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

-- Returns a RemoteEvent by name. On clients this waits until the server has created it.
function Net.getRemote(name: string): RemoteEvent
	assert(Net.Remotes[name], "Unknown remote: " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
