--[[
	InputGuard
	One place that decides whether an input should reach the game world.
	An input is kept away from the world when:
	  - Roblox already used it for UI ("gameProcessed"): clicking a button, clicking a HUD
	    panel that has Active = true, typing in chat, using the Roblox menu;
	  - the player is typing (in Roblox's chat bar or one of our own text boxes), so
	    typing "wasd" in chat doesn't pan the camera.
	Every world controller asks InputGuard instead of checking these itself.
]]

local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local InputGuard = {}

function InputGuard.isTyping(): boolean
	if UserInputService:GetFocusedTextBox() then
		return true
	end
	-- Roblox's chat bar belongs to Roblox, not to our UI, so we ask the chat service instead.
	local chatBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	return chatBar ~= nil and chatBar.IsFocused
end

-- `gameProcessed` is the second value Roblox passes to InputBegan and InputChanged.
function InputGuard.worldMayUse(gameProcessed: boolean): boolean
	return not gameProcessed and not InputGuard.isTyping()
end

return InputGuard
