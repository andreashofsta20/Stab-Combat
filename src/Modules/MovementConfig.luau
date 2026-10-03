return {
	WalkSpeed = 16, RunSpeed = 32, CrouchSpeed = 8,
	SlideSpeed = 60, SlideEndSpeed = 12, SlideDuration = 0.7, SlideCooldown = 1,
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
