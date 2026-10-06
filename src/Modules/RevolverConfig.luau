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
	HeadshotDamage = 70,
	Range = 350, -- studs measured from the server's firing origin
	FireIntervalMs = 350,
	ReloadDurationMs = 1600,
	HitboxSize = { 4, 6, 4 }, -- separate from the existing knife hitbox
	HitboxOffset = { 0, 0.5, 0 },
	MuzzleAttachmentName = "Muzzle",
	MuzzleOffset = { 0, 0.18, -0.7 }, -- visual barrel tip, local to Handle; gameplay fires from the head
	Pose = {
		Enabled = true,
		MinPitchDegrees = -65,
		MaxPitchDegrees = 75,
		MaxYawDegrees = 65,
		VerticalYawFadeStart = 0.08, VerticalYawFadeEnd = 0.25,
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
		BuildObjectsPerFrame = 8, -- build outside rendering in bounded batches
		ArmThicknessScale = 0.7, -- narrower first-person arms; preserve length/grip
		ArmPosition = { 0.7, -0.9, -0.65 }, -- camera-local right arm centre
		AimOffset = { -0.3, -0.16, 0.1 }, -- move slightly left/lower while aiming
		RotationDegrees = { 0, 0, 0 },
		LeftShoulder = { -0.5, -0.6, -0.3 },
		SupportHandOffset = { -0.6, -0.9, -0.1 },
		TransitionSpeed = 16,
		SwaySpeed = 16, SwayAngleDegrees = 0.3, SwayMaxAngularSpeed = 4,
		BobAmount = 0.003, BobFrequency = 6, MaxBobSpeedScale = 1,
		MovementAnimationScale = 0.04, MovementFollowSpeed = 14,
		MaxMovementAnimationOffset = 0.012, MaxMovementAnimationDegrees = 0.6,
		AimMotionScale = 0.3, -- steady hand during aimed fire
		AnimationFollowSpeed = 18,
		BodyAnimationWeight = 0.55, ArmAnimationWeight = 0.1,
		AnimationAimScale = 0.4, -- retain posture while reducing movement during aim
		MaxAnimationOffset = 0.3, MaxAnimationDegrees = 10,
		MaxUpwardAnimationOffset = 0.035,
		AirAnimationScale = 0.06, AirMaxAnimationDegrees = 2, AirBobScale = 0.06,
		InspectAnimationScale = 0.12, InspectBobScale = 0.18,
		RecoilDegrees = 3, RecoilDistance = 0.07, RecoilRecovery = 22,
		ReloadOffset = { -0.06, -0.22, 0.12 }, ReloadRollDegrees = -10,
		ShotEnabled = true, -- reusable local muzzle feedback; decorative skin VFX stay hidden
		ShotFlashSize = 0.6, ShotFlashLifetimeMs = 55,
		ShotSparkCount = 4, ShotSparkLifetimeMs = 80, ShotSoundVoices = 3,
		ShotTracerSlots = 2, -- reused camera-muzzle streaks, sharing the world tracer budget/update
	},
	Effects = {
		-- Cosmetic muzzle only. First person uses CAMERA axes so Up/Forward stay predictable
		-- even on a skin with a rotated Muzzle. World guns use authored Muzzle/Handle axes.
		-- Positive Up raises the flash/streak; positive Forward moves it away from the hand.
		-- These also apply to authored attachments and never move the server firing origin.
		MuzzleVisualRight = 0, MuzzleVisualUp = 0.5, MuzzleVisualForward = 1.1,
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
		BulletHoleEnabled = true,
		BulletHoleTextureId = "", -- rbxassetid://IMAGE_ID; empty uses the built-in drawn puncture/cracks
		BulletHoleSize = 0.38, -- studs; the texture should have a transparent background
		BulletHoleLifetime = 8, BulletHoleFadeSeconds = 1,
		BulletHoleSurfaceOffset = 0.018, -- separate the mark from the surface to prevent flicker
		BulletHoleMaxDistance = 140, BulletHoleMinCameraDistance = 0.15,
		SoundVolume = 1.3,
		SoundRange = 100,
		SoundPlaybackSpeed = 1,
		MuzzleParticleCount = 8, -- emits ParticleEmitters beneath Muzzle
		FireSoundId = "rbxassetid://134770754233897",
		ReloadSoundId = "rbxassetid://108663305361300",
		EquipSoundId = "rbxassetid://98462055955985",
		EquipSoundVolume = 0.7,
		EmptySoundId = "", -- rbxassetid://YOUR_ID; owner's click when firing with no bullets
		EmptySoundVolume = 0.7,
		EmptySoundCooldownMs = 250,
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
	["Ethereal Revolver"] = {
	Effects = {
		TracerColor = {140, 220, 255},
		TracerThickness = 0.09,
		TracerGlowWidth = 0.55,
		TracerTailLength = 22,
		TracerTipLength = 0.8,
		TracerLifetimeMs = 220,
		VisualTravelMs = 85,
		TracerMaxThickness = 0.5,

		MuzzleColors = {{255, 255, 255}, {190, 240, 255}, {90, 175, 255}},
		MuzzleLightColor = {150, 215, 255},
		MuzzleFlashSize = 1.5,
		MuzzleFlashLifetimeMs = 70,
		MuzzleParticleCount = 12,

		SmokeColor = {185, 225, 245},
		SmokeParticleCount = 4,

		ImpactColors = {{255, 255, 255}, {120, 200, 255}},
		ImpactSparkCount = 9,

		SoundPlaybackSpeed = 1.08,
	},
},
	["Valentine Revolver"] = {
	Effects = {
		TracerColor = {255, 170, 205},
		TracerThickness = 0.14,
		TracerGlowWidth = 0.6,
		TracerTailLength = 12,
		TracerTipLength = 0.6,
		TracerLifetimeMs = 160,
		VisualTravelMs = 70,
		TracerMaxThickness = 0.6,

		MuzzleColors = {{255, 255, 255}, {255, 205, 225}, {255, 120, 170}},
		MuzzleLightColor = {255, 175, 210},
		MuzzleFlashSize = 1.45,
		MuzzleFlashLifetimeMs = 65,
		MuzzleParticleCount = 10,

		SmokeColor = {255, 205, 222},
		SmokeParticleCount = 4,

		ImpactColors = {{255, 255, 255}, {255, 150, 195}},
		ImpactSparkCount = 8,
		SoundPlaybackSpeed = 1.05,
	},
},


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
	MaxBulletHoles = 24, -- reusable local surface marks; oldest slot is recycled
	MaxEffectDistance = 500, -- skip distant shots/impacts on this client
}

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
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
	assert(finite(tuning.Damage) and tuning.Damage > 0 and tuning.Damage <= 10000, "Invalid revolver damage")
	assert(finite(tuning.HeadshotDamage) and tuning.HeadshotDamage > 0 and tuning.HeadshotDamage <= 10000,
		"Invalid revolver headshot damage")
	for _, extent in ipairs(tuning.HitboxSize) do
		assert(extent > 0 and extent <= 12, "Invalid revolver hitbox size")
	end
	local pose = tuning.Pose
	assert(pose.MinPitchDegrees >= -85 and pose.MaxPitchDegrees <= 85
		and pose.MinPitchDegrees <= pose.MaxPitchDegrees, "Invalid revolver pitch limits")
	assert(pose.MaxYawDegrees >= 0 and pose.MaxYawDegrees <= 90, "Invalid revolver yaw limit")
	assert(type(pose.VerticalYawFadeStart) == "number" and type(pose.VerticalYawFadeEnd) == "number"
		and pose.VerticalYawFadeStart >= 0 and pose.VerticalYawFadeEnd <= 1
		and pose.VerticalYawFadeStart < pose.VerticalYawFadeEnd, "Invalid revolver vertical yaw fade")
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
	assert(first.MovementAnimationScale >= 0 and first.MovementAnimationScale <= 1
		and first.MovementFollowSpeed > 0 and first.MaxBobSpeedScale >= 0 and first.MaxBobSpeedScale <= 1.5
		and first.MaxMovementAnimationOffset >= 0 and first.MaxMovementAnimationOffset <= first.MaxAnimationOffset
		and first.MaxMovementAnimationDegrees >= 0 and first.MaxMovementAnimationDegrees <= first.MaxAnimationDegrees,
		"Invalid first-person movement suppression")
	assert(first.ShotFlashSize > 0 and first.ShotFlashSize <= 2
		and first.ShotFlashLifetimeMs > 0 and first.ShotFlashLifetimeMs <= 150
		and first.ShotSparkLifetimeMs > 0 and first.ShotSparkLifetimeMs <= 150
		and first.ShotSparkCount >= 0 and first.ShotSparkCount <= 8 and first.ShotSparkCount % 1 == 0
		and first.ShotSoundVoices >= 1 and first.ShotSoundVoices <= 4 and first.ShotSoundVoices % 1 == 0
		and first.ShotTracerSlots >= 1 and first.ShotTracerSlots <= 4 and first.ShotTracerSlots % 1 == 0,
		"Invalid first-person shot budget")
	assert(tuning.Effects.VisualTravelMs >= 0 and tuning.Effects.VisualTravelMs <= 1000
		and tuning.Effects.TracerLifetimeMs >= 0 and tuning.Effects.TracerLifetimeMs <= 1000, "Invalid revolver visual lifetime")
	assert(tuning.Effects.TracerThickness > 0 and tuning.Effects.TracerGlowWidth >= 0
		and tuning.Effects.TracerTailLength > 0, "Invalid revolver tracer dimensions")
	assert(tuning.Effects.SoundPlaybackSpeed > 0 and tuning.Effects.SoundPlaybackSpeed <= 4, "Invalid revolver sound pitch")
	local effects = tuning.Effects
	assert(type(effects.EmptySoundId) == "string" and #effects.EmptySoundId <= 200, "Invalid revolver empty sound")
	assert(finite(effects.EmptySoundVolume) and effects.EmptySoundVolume >= 0 and effects.EmptySoundVolume <= 10,
		"Invalid revolver empty sound volume")
	assert(finite(effects.EmptySoundCooldownMs) and effects.EmptySoundCooldownMs >= 50 and effects.EmptySoundCooldownMs <= 5000,
		"Invalid revolver empty sound cooldown")
	assert(Config.Presentation.MaxBulletHoles >= 1 and Config.Presentation.MaxBulletHoles <= 64
		and Config.Presentation.MaxBulletHoles % 1 == 0, "Invalid bullet hole pool budget")
	for _, offset in ipairs({effects.MuzzleVisualRight, effects.MuzzleVisualUp, effects.MuzzleVisualForward}) do
		assert(type(offset) == "number" and offset == offset and math.abs(offset) <= 2, "Invalid cosmetic muzzle offset")
	end
	assert(type(effects.BulletHoleTextureId) == "string" and #effects.BulletHoleTextureId <= 200,
		"Invalid bullet hole texture")
	assert(effects.BulletHoleSize >= 0.05 and effects.BulletHoleSize <= 2
		and effects.BulletHoleLifetime > 0 and effects.BulletHoleLifetime <= 30
		and effects.BulletHoleFadeSeconds > 0 and effects.BulletHoleFadeSeconds <= effects.BulletHoleLifetime
		and effects.BulletHoleSurfaceOffset >= 0.005 and effects.BulletHoleSurfaceOffset <= 0.1
		and effects.BulletHoleMinCameraDistance >= 0 and effects.BulletHoleMaxDistance > effects.BulletHoleMinCameraDistance
		and effects.BulletHoleMaxDistance <= 500, "Invalid bullet hole presentation limits")
	return tuning
end

return Config
