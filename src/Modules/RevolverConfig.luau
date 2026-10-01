-- Shared presentation/tuning. The server requires its own copy and owns gameplay.
local Config = {}
Config.Capacity = 3 -- shared across all skins; switching Tools never refills this
Config.ReloadKey = "R"
Config.GamepadReloadKey = "ButtonX"
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
		R6RotationOffset = { 0, 0, 0 }, -- degrees, for unusual grips/meshes
	},
	Aim = {
		Enabled = true, -- hold RMB / gamepad L2; presentation only
		FieldOfView = 60,
		CameraOffset = { 1.5, 0.15, 0 }, -- added to the existing Humanoid offset
		CameraFollowSpeed = 18,
		BodyFollowSpeed = 24,
		PoseBlendSpeed = 16,
		RightArmOffset = { -0.65, -0.1, 0.35 }, -- torso-local, R6 two-hand hold
		SupportHandOffset = { -0.6, -0.9, -0.1 }, -- right-arm-local support point
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
		SmokeEnabled = true,
		SmokeParticleCount = 3,
		ImpactEnabled = true,
		ImpactSparkCount = 7,
		SoundVolume = 0.7,
		SoundRange = 100,
		MuzzleParticleCount = 8, -- emits ParticleEmitters beneath Muzzle
		FireSoundId = "", -- optional rbxassetid://...; blank = no sound
		ReloadSoundId = "",
		FireAnimationId = "",
		ReloadAnimationId = "",
	},
}
Config.Overrides = {
	-- ["Ethereal Revolver"] = {
	--     Range = 400,
	--     FireIntervalMs = 300,
	--     Effects = { TracerColor = { 100, 200, 255 } },
	-- },
}
Config.Security = {
	MaxCameraDistance = 32, -- hard server cap; held-gun camera zoom uses 28
	CameraZoomLimit = 28,
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

function Config.Get(weaponName: string)
	local tuning = table.clone(Config.Default)
	tuning.Effects = table.clone(Config.Default.Effects)
	tuning.Pose = table.clone(Config.Default.Pose)
	tuning.Aim = table.clone(Config.Default.Aim)
	local override = Config.Overrides[weaponName]
	if override then
		for key, value in pairs(override) do
			if key == "Effects" or key == "Pose" or key == "Aim" then
				for option, setting in pairs(value) do tuning[key][option] = setting end
			else
				tuning[key] = value
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
	assert(tuning.Effects.VisualTravelMs >= 0 and tuning.Effects.VisualTravelMs <= 1000
		and tuning.Effects.TracerLifetimeMs >= 0 and tuning.Effects.TracerLifetimeMs <= 1000, "Invalid revolver visual lifetime")
	return tuning
end

return Config
