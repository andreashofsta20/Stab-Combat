-- Faster visual flight preserves damage, cooldown, charge controls and straight path.
-- Server hit resolution remains an immediate swept ray; visual flight is cosmetic.
return {
	Throw = {
		MaxDistance = 350, MaxFlightTime = 2,
		MinSpeed = 500, MaxSpeed = 750, Damage = 50, Cooldown = 1,
		MaxOriginDistance = 8, MaxChargeTime = 1, HoldThreshold = 0.2,
	},
	Stab = { Range = 12, Width = 8, Height = 8, Damage = 100, Cooldown = 0.6, DistanceLeeway = 8 },
	ActionMinGap = 0.4,
	RequestBurst = 5,
	RequestsPerSecond = 4,
	Presentation = {
		VisualOffset = 0.8, StuckSeconds = 4, Lifetime = 6,
		MissSeconds = 0.15,
		MaxVisuals = 48, ChargeTransitionSeconds = 0.35,
		HideHandleDelay = 0.15, ReturnHandleDelay = 0.65,
		HintEnabled = true,
		HitMarkerEnabled = true, HitMarkerSeconds = 0.15,
	},
	-- Uses the same inert camera model, skin geometry and zoom gate as revolvers.
	-- These values only move local presentation; the physical throw origin stays
	-- on the character and the server still resolves every stab/throw.
	FirstPerson = {
		Enabled = true, EnterDistance = 0.55, ExitDistance = 0.6,
		BuildRetrySeconds = 0.1, MaxBuildRetrySeconds = 1,
		MaxWeaponParts = 64,
		ArmThicknessScale = 0.75, SupportArmEnabled = false,
		ArmPosition = {0.78, -0.95, -0.7}, AimOffset = {0, 0, 0},
		RotationDegrees = {-8, 0, 0}, R6RotationOffset = {0, 0, 0},
		LeftShoulder = {-0.5, -0.6, -0.3}, SupportHandOffset = {-0.6, -0.9, -0.1},
		TransitionSpeed = 16, SwaySpeed = 20, SwayAngleDegrees = 1.4,
		SwayMaxAngularSpeed = 4, BobAmount = 0.025, BobFrequency = 8,
		AimMotionScale = 1, AnimationFollowSpeed = 18,
		BodyAnimationWeight = 0.65, ArmAnimationWeight = 0.08,
		AnimationAimScale = 1, MaxAnimationOffset = 0.4, MaxAnimationDegrees = 18,
		RecoilDegrees = 0, RecoilDistance = 0, RecoilRecovery = 22,
		ReloadOffset = {0, 0, 0}, ReloadRollDegrees = 0,
		ActionFollowSpeed = 24,
		ChargeOffset = {0.06, 0.18, 0.22}, ChargeRotationDegrees = {-25, 10, 8},
		StabSeconds = 0.28, StabOffset = {-0.08, 0.06, -0.75},
		StabRotationDegrees = {12, -6, -8},
		ThrowSeconds = 0.35, ThrowOffset = {-0.06, 0.12, -0.45},
		ThrowRotationDegrees = {30, -8, -12},
	},
}
