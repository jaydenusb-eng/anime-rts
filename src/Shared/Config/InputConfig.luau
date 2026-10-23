--[[
	InputConfig
	Key bindings and mouse tuning. Change keys here, not in controller code.
]]

return {
	PanUp = { Enum.KeyCode.W, Enum.KeyCode.Up },
	PanDown = { Enum.KeyCode.S, Enum.KeyCode.Down },
	PanLeft = { Enum.KeyCode.A, Enum.KeyCode.Left },
	PanRight = { Enum.KeyCode.D, Enum.KeyCode.Right },
	-- Hold to add or remove units instead of replacing the selection.
	AddToSelection = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	-- Pixels the mouse must travel with the button held before a click becomes a drag-box.
	DragThreshold = 6,
	-- A click this many pixels from one of your units still selects it.
	ClickPickRadius = 18,
}
