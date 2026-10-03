-- Shared presentation/tuning. The server requires its own copy and owns gameplay.
local Config = {}
Config.Capacity = 3 -- shared across all skins; switching Tools never refills this
Config.ReloadKey = "R"
Config.GamepadReloadKey = "ButtonX"
Config.FirstPersonPhysics = {
	CollisionGroup = "RevolverViewmodels", -- server-owned mask; no physical contacts
	ReadyAttribute = "RevolverViewmodelPhysicsReady",
	GroupRefreshSeconds = 1, -- includes groups registered after startup
}
Config.Default = {
	Damage = 34,
	Range = 350, -- studs measured from the server's firing origin
	FireIntervalMs = 350,
	ReloadDurationMs = 1600,
	HitboxSize = { 4, 6, 4 }, -- separate from the existing knife hitbox
	HitboxOffset = { 0, 0.5, 0 },
	MuzzleAttachmentName = "Muzzle",
	MuzzleOffset = { 0, 0, -0.5 }, -- fallback, local to Handle
	Pose = {
		Enabled = true,
		MinPitchDegrees = -65,
		MaxPitchDegrees = 75,
		MaxYawDegrees = 65,
		FollowSpeed = 22, -- exponential smoothing, independent of frame rate
		BlendSpeed = 18,
		RecoilDegrees = 7,
		RecoilRecovery = 18,
		MinAimDistance = 0.75, -- ignore only degenerate targets almost touching the shoulder
		R6RotationOffset = { 0, 0, 0 }, -- degrees, for unusual grips/meshes
	},
	Aim = {
		Enabled = true, -- hold RMB / gamepad L2; presentation only
		FieldOfView = 60,
		CameraOffset = { 1.5, 0.15, 0 }, -- added to the existing Humanoid offset
		CameraFollowSpeed = 18,
		BodyFollowSpeed = 24,
		MinHorizontalLook = 0.12, -- blend body turning out near vertical camera angles
		PoseBlendSpeed = 16,
		RightArmOffset = { -0.65, -0.1, 0.35 }, -- torso-local, R6 two-hand hold
		SupportHandOffset = { -0.6, -0.9, -0.1 }, -- right-arm-local support point
	},
	FirstPerson = {
		Enabled = true, -- local R6 arms/weapon; never supplies a firing origin
		EnterDistance = 0.55, ExitDistance = 0.6, -- fully zoomed in, with a small tolerance
		BuildRetrySeconds = 0.1, MaxBuildRetrySeconds = 1, -- recover from incomplete replication
		MaxWeaponParts = 64, -- one cached copy of the equipped skin
		ArmThicknessScale = 0.75, -- narrower first-person arms; preserve length/grip
		ArmPosition = { 0.7, -0.9, -0.65 }, -- camera-local right arm centre
		AimOffset = { -0.3, -0.16, 0.1 }, -- move slightly left/lower while aiming
		RotationDegrees = { 0, 0, 0 },
		LeftShoulder = { -0.5, -0.6, -0.3 },
		SupportHandOffset = { -0.6, -0.9, -0.1 },
		TransitionSpeed = 16,
		SwaySpeed = 20, SwayAngleDegrees = 1.4, SwayMaxAngularSpeed = 4,
		BobAmount = 0.025, BobFrequency = 8,
		AimMotionScale = 0.3, -- steady hand during aimed fire
		AnimationFollowSpeed = 18,
		BodyAnimationWeight = 0.65, ArmAnimationWeight = 0.2,
		AnimationAimScale = 0.4, -- retain posture while reducing movement during aim
		MaxAnimationOffset = 0.4, MaxAnimationDegrees = 18,
		RecoilDegrees = 3, RecoilDistance = 0.07, RecoilRecovery = 22,
		ReloadOffset = { -0.06, -0.22, 0.12 }, ReloadRollDegrees = -10,
	},
	Effects = {
		TracerEnabled = true,
		TracerColor = { 255, 224, 150 },
		TracerThickness = 0.12,
		TracerLifetimeMs = 130,
		TracerGlowWidth = 0.38,
		TracerTailLength = 14,
		TracerTipLength = 0.5,
		TracerMinPixels = 1.5, -- grow distant glints slightly so they remain readable
		TracerMaxThickness = 0.6, -- cap the cosmetic growth in world space
		VisualTravelMs = 65, -- cosmetic only; damage remains hitscan
		MuzzleFlashEnabled = true,
		MuzzleFlashSize = 1.3,
		MuzzleFlashLifetimeMs = 60,
		MuzzleColors = {{255, 255, 255}, {255, 218, 120}, {255, 125, 40}},
		MuzzleLightColor = {255, 211, 120},
		CustomMuzzleParticlesEnabled = true,
		SmokeEnabled = true,
		SmokeParticleCount = 3,
		SmokeColor = {155, 148, 136},
		ImpactEnabled = true,
		ImpactSparkCount = 7,
		ImpactColors = {{255, 255, 255}, {255, 165, 65}},
		SoundVolume = 0.7,
		SoundRange = 100,
		SoundPlaybackSpeed = 1,
		MuzzleParticleCount = 8, -- emits ParticleEmitters beneath Muzzle
		FireSoundId = "rbxassetid://134770754233897",
		ReloadSoundId = "rbxassetid://108663305361300",
		EquipSoundId = "rbxassetid://98462055955985",
		EquipSoundVolume = 0.45,
		FireAnimationId = "",
		ReloadAnimationId = "",
	},
}
Config.Overrides = {
	-- Every skin inherits Default. Add only the settings you want to change here.
	-- Example: Effects = {TracerColor = {80, 180, 255}, TracerThickness = 0.2,
	--     MuzzleColors = {{255,255,255},{80,180,255}}, FireSoundId = "rbxassetid://YOUR_ID"},
	["Amber Revolver"] = { Effects = {} },
	["Aurum Revolver"] = { Effects = {} },
	["Azure Revolver"] = { Effects = {} },
	["Berserk Revolver"] = { Effects = {} },
	["Blaze Revolver"] = { Effects = {} },
	["Blossom Revolver"] = { Effects = {} },
	["Camo Revolver"] = { Effects = {} },
	["Cosmic Revolver"] = { Effects = {} },
	["Crimson Revolver"] = { Effects = {} },
	["Divine Revolver"] = { Effects = {} },
	["Dragon Scale Revolver"] = { Effects = {} },
	["Frostbite Revolver"] = { Effects = {} },
	["Glacial Revolver"] = { Effects = {} },
	["Grim Revolver"] = { Effects = {} },
	["Hellfire Revolver"] = { Effects = {} },
	["Honeyed Revolver"] = { Effects = {} },
	["Inferno Revolver"] = { Effects = {} },
	["Jade Revolver"] = { Effects = {} },
	["Love Train Revolver"] = { Effects = {} },
	["Mysterious Revolver"] = { Effects = {} },
	["Mystic Revolver"] = { Effects = {} },
	["Nebula Revolver"] = { Effects = {} },
	["Normal Revolver"] = { Effects = {} },
	["Onyx Revolver"] = { Effects = {} },
	["Permafrost Revolver"] = { Effects = {} },
	["Phantom Revolver"] = { Effects = {} },
	["Radiant Revolver"] = { Effects = {} },
	["Winter Revolver 2"] = { Effects = {} },
	["Winter Revolver"] = { Effects = {} },
	["Void Revolver"] = { Effects = {} },
	["Vermilion Revolver"] = { Effects = {} },
	["Verdant Revolver"] = { Effects = {} },
	["Venom Revolver"] = { Effects = {} },
	["Umbra Revolver"] = { Effects = {} },
	["Twilight Revolver"] = { Effects = {} },
	["Toxic Revolver"] = { Effects = {} },
	["Tidal Revolver"] = { Effects = {} },
	["Tempest Revolver"] = { Effects = {} },
	["Sylvan Revolver"] = { Effects = {} },
	["Sterling Revolver"] = { Effects = {} },
	["Steampunk Revolver"] = { Effects = {} },
	["Spectral Revolver"] = { Effects = {} },
	["Shattered Revolver"] = { Effects = {} },
	["Seraph Revolver"] = { Effects = {} },
	["Scarlet Revolver"] = { Effects = {} },
	["Sapphire Revolver"] = { Effects = {} },
	["Royal Revolver"] = { Effects = {} },
	["Abyssal Tide Revolver"] = { Effects = {} },
	["Bubble Gun Revolver"] = { Effects = {} },
	["White&Black Revolver"] = { Effects = {} },
	["Arcane Revolver"] = { Effects = {} },
	["Amethyst Revolver"] = { Effects = {} },
	["Ethereal Revolver"] = { Effects = {} },
	["Valentine Revolver"] = { Effects = {} },
}
Config.Security = {
	MaxCameraDistance = 32, -- hard server cap; held-gun camera zoom uses 28
	CameraZoomLimit = 20,
	MaxMuzzleDistance = 7, -- fallback to Head if the visual muzzle is implausible
	MaxCoordinate = 1000000,
	RequestBurst = 8,
	RequestsPerSecond = 12,
	MaxPendingShots = 8,
	FutureTimestampToleranceMs = 50,
	TimestampJitterMs = 100,
	MaxPacketAgeMs = 500,
}
Config.LagCompensation = {
	Enabled = true,
	MaxRewindMs = 200,
	InterpolationMs = 50,
	SampleHz = 30,
	MaxHistorySamples = 16,
	TeleportResetDistance = 12,
}
Config.PoseReplication = {
	SendHz = 15,
	SampleHz = 30,
	AngleThresholdDegrees = 0.5,
	KeepAliveMs = 250, -- stationary aim needs only four packets/sec
	TimeoutMs = 650,
	RequestBurst = 4,
	RequestsPerSecond = 20,
}
Config.Presentation = {
	LobbyAimingEnabled = true, -- lobby arm tracking + RMB/L2/touch aim; never permits firing/reloading
	MaxActiveTracers = 64, -- local render budget; cannot change hits/damage
	MaxEffectDistance = 500, -- skip distant shots/impacts on this client
}

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

function Config.Get(weaponName: string)
	local tuning = copy(Config.Default)
	local override = Config.Overrides[weaponName]
	if override then
		for key, value in pairs(override) do
			if key == "Effects" or key == "Pose" or key == "Aim" or key == "FirstPerson" then
				for option, setting in pairs(value) do tuning[key][option] = copy(setting) end
			else
				tuning[key] = copy(value)
			end
		end
	end
	assert(tuning.Range > 0 and tuning.Range <= 1500, "Revolver range must be 0..1500 studs")
	assert(tuning.FireIntervalMs >= 0 and tuning.ReloadDurationMs >= 0, "Negative revolver timing")
	assert(tuning.Damage > 0 and tuning.Damage <= 10000, "Invalid revolver damage")
	for _, extent in ipairs(tuning.HitboxSize) do
		assert(extent > 0 and extent <= 12, "Invalid revolver hitbox size")
	end
	local pose = tuning.Pose
	assert(pose.MinPitchDegrees >= -85 and pose.MaxPitchDegrees <= 85
		and pose.MinPitchDegrees <= pose.MaxPitchDegrees, "Invalid revolver pitch limits")
	assert(pose.MaxYawDegrees >= 0 and pose.MaxYawDegrees <= 90, "Invalid revolver yaw limit")
	assert(pose.FollowSpeed > 0 and pose.BlendSpeed > 0 and pose.RecoilRecovery > 0, "Invalid revolver pose smoothing")
	local aim = tuning.Aim
	assert(aim.FieldOfView >= 20 and aim.FieldOfView <= 120, "Invalid revolver aim FOV")
	assert(aim.CameraFollowSpeed > 0 and aim.BodyFollowSpeed > 0 and aim.PoseBlendSpeed > 0, "Invalid revolver aim smoothing")
	local first = tuning.FirstPerson
	assert(first.EnterDistance > 0 and first.ExitDistance > first.EnterDistance, "Invalid first-person zoom thresholds")
	assert(first.BuildRetrySeconds > 0 and first.MaxBuildRetrySeconds >= first.BuildRetrySeconds, "Invalid first-person retry timing")
	assert(first.MaxWeaponParts >= 1 and first.MaxWeaponParts <= 128 and first.MaxWeaponParts % 1 == 0, "Invalid first-person part budget")
	assert(first.ArmThicknessScale >= 0.5 and first.ArmThicknessScale <= 1, "Invalid first-person arm thickness")
	assert(first.TransitionSpeed > 0 and first.SwaySpeed > 0 and first.RecoilRecovery > 0
		and first.SwayMaxAngularSpeed > 0, "Invalid first-person smoothing")
	assert(first.BobAmount >= 0 and first.BobAmount <= 0.15 and first.SwayAngleDegrees >= 0
		and first.SwayAngleDegrees <= 5 and first.AimMotionScale >= 0 and first.AimMotionScale <= 1, "Invalid first-person motion")
	assert(first.AnimationFollowSpeed > 0 and first.BodyAnimationWeight >= 0 and first.BodyAnimationWeight <= 1
		and first.ArmAnimationWeight >= 0 and first.ArmAnimationWeight <= 1
		and first.AnimationAimScale >= 0 and first.AnimationAimScale <= 1
		and first.MaxAnimationOffset >= 0 and first.MaxAnimationOffset <= 1
		and first.MaxAnimationDegrees >= 0 and first.MaxAnimationDegrees <= 30, "Invalid first-person animation following")
	assert(tuning.Effects.VisualTravelMs >= 0 and tuning.Effects.VisualTravelMs <= 1000
		and tuning.Effects.TracerLifetimeMs >= 0 and tuning.Effects.TracerLifetimeMs <= 1000, "Invalid revolver visual lifetime")
	assert(tuning.Effects.TracerThickness > 0 and tuning.Effects.TracerGlowWidth >= 0
		and tuning.Effects.TracerTailLength > 0, "Invalid revolver tracer dimensions")
	assert(tuning.Effects.SoundPlaybackSpeed > 0 and tuning.Effects.SoundPlaybackSpeed <= 4, "Invalid revolver sound pitch")
	return tuning
end

return Config
