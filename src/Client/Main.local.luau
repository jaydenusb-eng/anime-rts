--[[
	Client entry point. Starts each controller in order. Client code only handles input,
	the camera, UI and visuals; anything that changes the game is sent to the server
	as a request, and the server decides.
]]

local Client = script.Parent
local Controllers = Client:WaitForChild("Controllers")
local UI = Client:WaitForChild("UI")
local Visuals = Client:WaitForChild("Visuals")

local Hud = require(UI.Hud)
local ResourceBillboards = require(UI.ResourceBillboards)
local UnitTracker = require(Controllers.UnitTracker)
local CameraController = require(Controllers.CameraController)
local SelectionController = require(Controllers.SelectionController)
local CommandController = require(Controllers.CommandController)
local TeamController = require(Controllers.TeamController)
local LeafSway = require(Visuals.LeafSway)
local NinjaRun = require(Visuals.NinjaRun)

Hud.start()
ResourceBillboards.start()
UnitTracker.start()
CameraController.start()
SelectionController.start()
CommandController.start()
TeamController.start()
LeafSway.start()
NinjaRun.start()
