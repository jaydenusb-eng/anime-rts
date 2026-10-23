--[[
	CameraConfig
	Tuning for the overhead RTS camera (Client/Controllers/CameraController).
]]

return {
	FieldOfView = 50,
	-- Degrees the camera looks down from horizontal (90 = straight down).
	Pitch = 56,
	-- Compass direction the camera faces, in degrees. 0 = north (towards -Z).
	Yaw = 0,
	-- Distance (studs) from the camera to the point on the ground it looks at.
	MinZoom = 40,
	MaxZoom = 160,
	DefaultZoom = 100,
	-- Zoom change per mouse-wheel notch.
	ZoomStep = 12,
	-- How quickly the zoom catches up with the wheel. Higher = snappier.
	ZoomSmoothing = 12,
	-- Pan speed as a multiple of the current zoom distance, per second.
	-- (Zoomed out you pan faster, which feels natural.)
	PanSpeed = 1.1,
	-- Lets the camera's focus point go this far past the play-area edge.
	BoundsPadding = 0,
}
