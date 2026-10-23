--[[
	CommandService
	The only way a player can give orders. Every request from a client goes through
	`onUnitCommand`, which checks, in order:
	  1. the player isn't sending requests faster than any human could (rate limit),
	  2. the request has the right shape and types,
	  3. every unit exists and belongs to that player,
	  4. the destination is a real position (it is then kept inside the play area).
	Requests that fail are dropped and logged, so a modified client can't move other
	players' units, teleport units, or break the server with bad data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local Util = script.Parent.Parent.Util
local RateLimiter = require(Util.RateLimiter)
local Validate = require(Util.Validate)
local UnitService = require(script.Parent.UnitService)
local NavigationService = require(script.Parent.NavigationService)

local SETTINGS = GameConfig.Commands

local CommandService = {}

local limiter = RateLimiter.new(SETTINGS.BurstLimit, SETTINGS.RefillPerSecond)
local feedbackRemote: RemoteEvent
local lastWarning: { [Player]: number } = {}
local stats = { received = 0, accepted = 0, rejected = 0, rateLimited = 0 }

-- Logs why a request was refused, at most once a second per player so spam can't flood the log.
local function reject(player: Player, reason: string)
	stats.rejected += 1
	local now = os.clock()
	if not lastWarning[player] or now - lastWarning[player] > 1 then
		lastWarning[player] = now
		warn(string.format("[CommandService] Rejected a command from %s: %s", player.Name, reason))
	end
end

local function sendFeedback(player: Player, message: string)
	if player.Parent then
		feedbackRemote:FireClient(player, { message = message })
	end
end

local function handleMove(player: Player, payload)
	if not Validate.isFiniteVector3(payload.target) then
		return reject(player, "target is not a valid position")
	end
	local units = {}
	for _, id in payload.unitIds do
		local unit = UnitService.get(id)
		if unit and unit.alive then
			if unit.ownerUserId ~= player.UserId then
				return reject(player, "ordered unit " .. id .. ", which it does not own")
			end
			table.insert(units, unit)
		end
		-- Unknown ids are skipped quietly: the unit may simply have been removed a moment ago.
	end
	if #units == 0 then
		return
	end

	stats.accepted += 1
	NavigationService.moveGroup(units, payload.target, function(summary)
		if summary.unreachable then
			sendFeedback(player, "Can't reach that location.")
		elseif summary.failed > 0 then
			sendFeedback(player, string.format("%d unit(s) couldn't find a way there.", summary.failed))
		elseif summary.adjusted and summary.moved > 0 then
			sendFeedback(player, "Moving to the nearest reachable spot.")
		end
	end)
end

-- Every command kind the server accepts, and the function that handles it.
local handlers = {
	[Net.CommandKind.Move] = handleMove,
}

local function onUnitCommand(player: Player, payload: any)
	stats.received += 1
	if not limiter:allow(player) then
		stats.rateLimited += 1
		return
	end
	if type(payload) ~= "table" then
		return reject(player, "payload is not a table")
	end
	local handler = handlers[payload.kind]
	if not handler then
		return reject(player, "unknown command kind " .. tostring(payload.kind))
	end
	if not Validate.isIdList(payload.unitIds, SETTINGS.MaxUnitsPerCommand) then
		return reject(player, "unit id list is invalid or too long")
	end
	handler(player, payload)
end

function CommandService.getStats()
	return table.clone(stats)
end

function CommandService.resetStats()
	for key in stats do
		stats[key] = 0
	end
end

function CommandService.start()
	feedbackRemote = Net.getRemote(Net.Remotes.CommandFeedback)
	Net.getRemote(Net.Remotes.UnitCommand).OnServerEvent:Connect(onUnitCommand)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
		lastWarning[player] = nil
	end)
end

return CommandService
