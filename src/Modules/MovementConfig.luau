return {
	TouchControls = {
		Crouch = {Title = "Crouch", Position = {1, -215, 1, -165}},
		Slide = {Title = "Slide", Position = {1, -285, 1, -100}},
	},
	WalkSpeed = 16, RunSpeed = 32, CrouchSpeed = 8,
	SlideSpeed = 60, SlideEndSpeed = 32, SlideDuration = 0.8, SlideCooldown = 1,
	SlideBoostSeconds = 0.1, SlideFadeSeconds = 0.18,
	-- Finite acceleration and ground-tangent motion keep ramps and small seams
	-- smooth without pinning the character vertically or bypassing collisions.
	SlideAcceleration = 260, SlideSteerDegreesPerSecond = 85,
	SlideSurfaceResponse = 18, SlideProbeInterval = 1 / 30,
	SlideGroundTolerance = 0.4, SlideGroundGrace = 0.12,
	SlideMaxSlopeDegrees = 50, SlideStepHeight = 0.85,
	SlideStepMargin = 0.1, SlideStepCooldown = 0.22,
	SlideStepGrace = 0.22, SlideStepProbeDistance = 6.5,
	FadeSeconds = 0.12, RecoveryInterval = 0.25, AssetRetrySeconds = 8,
	Animations = {
		Walk = "rbxassetid://79598872056948", Run = "rbxassetid://117319187680453",
		Idle = "rbxassetid://88520413958295", CrouchIdle = "rbxassetid://115606571521361",
		CrouchWalk = "rbxassetid://76062126805596", Slide = "rbxassetid://75213495477739",
		Jump = "rbxassetid://125750702", Fall = "rbxassetid://180436148",
		Climb = "rbxassetid://180436334", Sit = "rbxassetid://178130996",
	},
	-- Standard R6 fallbacks for unavailable custom assets.
	Fallbacks = {
		Walk = "rbxassetid://180426354", Run = "rbxassetid://180426354",
		Idle = "rbxassetid://180435571", CrouchIdle = "rbxassetid://180435571",
		CrouchWalk = "rbxassetid://180426354", Slide = "rbxassetid://180426354",
	},
}
