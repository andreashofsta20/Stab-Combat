-- Local eye-height presentation, shared by the knife and revolver camera models.
-- This never moves the character, changes collision, or owns Humanoid.CameraOffset.
return {
	Enabled = true,
	EnterDistance = 0.55, ExitDistance = 0.6, -- same fully zoomed-in range as the arms
	PostureAttribute = "FirstPersonMovementPosture",
	CrouchDrop = 0.7, SlideDrop = 1, -- studs below the native standing camera
	FollowSpeed = 18, -- exponential smoothing; independent of frame rate
}
