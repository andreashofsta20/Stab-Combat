-- Faster visual flight preserves damage, cooldown, charge controls and straight path.
-- Server hit resolution remains an immediate swept ray; visual flight is cosmetic.
return {
	Throw = {
		MaxDistance = 350, MaxFlightTime = 2,
		MinSpeed = 500, MaxSpeed = 750, Damage = 50, HeadshotKills = true, Cooldown = 0.8,
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
		BuildObjectsPerFrame = 8,
		ArmThicknessScale = 0.75, SupportArmEnabled = false,
		ArmPosition = {1.02, -0.95, -0.7}, AimOffset = {0, 0, 0}, -- clear more of the screen center
		RotationDegrees = {-8, 0, 0}, R6RotationOffset = {0, 0, 0},
		LeftShoulder = {-0.5, -0.6, -0.3}, SupportHandOffset = {-0.6, -0.9, -0.1},
		TransitionSpeed = 16, SwaySpeed = 16, SwayAngleDegrees = 0.3,
		SwayMaxAngularSpeed = 4, BobAmount = 0.003, BobFrequency = 6, MaxBobSpeedScale = 1,
		MovementAnimationScale = 0.04, MovementFollowSpeed = 14,
		MaxMovementAnimationOffset = 0.012, MaxMovementAnimationDegrees = 0.6,
		AimMotionScale = 1, AnimationFollowSpeed = 18,
		BodyAnimationWeight = 0.55, ArmAnimationWeight = 0.06,
		AnimationAimScale = 1, MaxAnimationOffset = 0.3, MaxAnimationDegrees = 10,
		MaxUpwardAnimationOffset = 0.035,
		AirAnimationScale = 0.06, AirMaxAnimationDegrees = 2, AirBobScale = 0.06,
		InspectAnimationScale = 0.12, InspectBobScale = 0.18,
		RecoilDegrees = 0, RecoilDistance = 0, RecoilRecovery = 22,
		ReloadOffset = {0, 0, 0}, ReloadRollDegrees = 0,
		ActionFollowSpeed = 24,
		-- Overhand wind-up, held until the actual charge is released/canceled.
		ChargeOffset = {0.08, 1.05, 0.02}, ChargeRotationDegrees = {45, -8, 5},
		-- Camera-space offsets: negative Z drives the whole hand/blade forward.
		-- Fractions end the preparation, extension and brief extended hold. Keep
		-- both grip rotations alike so the thrust is an arm movement, not a flick.
		StabSeconds = 0.42, StabWindupFraction = 0.18, StabThrustFraction = 0.38,
		StabHoldFraction = 0.56,
		StabWindupOffset = {0.1, -0.035, 0.22}, StabWindupRotationDegrees = {-4, -8, -10},
		StabOffset = {-0.34, 0.06, -1.35}, StabRotationDegrees = {-4, -8, -10},
		ThrowSeconds = 0.35, ThrowOffset = {-0.06, 0.12, -0.45},
		ThrowRotationDegrees = {30, -8, -12},
	},
}
