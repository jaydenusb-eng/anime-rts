--[[
	Server entry point. Starts each service in order. Each service is a ModuleScript in
	./Services and owns one job:
	  UnitService        the list of units (create, look up, remove)
	  MovementSystem     moves walking units every frame
	  NavigationService  works out formations and paths for move orders
	  CommandService     receives and checks player orders
	  MatchService       seats players and spawns their starting armies
	  DevBridge          test hooks, only in Studio
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Services = script.Parent.Services
local UnitService = require(Services.UnitService)
local MovementSystem = require(Services.MovementSystem)
local NavigationService = require(Services.NavigationService)
local CommandService = require(Services.CommandService)
local MatchService = require(Services.MatchService)
local DevBridge = require(Services.DevBridge)

Net.createRemotes()
UnitService.init()
MovementSystem.start()
NavigationService.init()
CommandService.start()
DevBridge.start()
MatchService.start() -- last, so players only get units once everything else is ready

print("[Server] Started.")
