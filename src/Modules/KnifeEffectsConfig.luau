-- Cosmetics only. Damage, range and cooldown belong in KnifeConfig.
-- RGB arrays become evenly spaced ColorSequence keypoints along the trail.
local Config = {}
Config.Default = {
	BladeAxis = "Auto", -- or +X/-X/+Y/-Y/+Z/-Z for a mesh with an unusual orientation
	RotationDegrees = {0, 0, 0},
	StickDepth = 0.15, -- studs of the tip embedded in the surface
	TipDistance = 0, -- 0 = derive from visible parts; override for SpecialMesh bounds
	TrailEnabled = true,
	TrailColors = {{255, 255, 255}},
	TrailWidth = 0.32, -- studs; attachments span across the flight direction
	TrailLifetime = 0.09,
	TrailMaxLength = 18,
	TrailTexture = "", -- blank = solid white rail
	GlowEnabled = true,
	GlowWidth = 0.65,
	GlowLifetime = 0.07,
	GlowColors = {{255, 255, 255}},
	SparkRate = 0,
	SparkColors = {{255, 255, 255}},
	ImpactEnabled = true,
	ImpactSparkCount = 7,
	ImpactColors = {{255, 255, 255}},
	ThrowSoundId = "", -- blank uses Assets.Sounds.ThrowKnife
	ImpactSoundId = "", -- optional rbxassetid://...
	SoundVolume = 0.7,
	SoundRange = 100,
	ThrowPitchMin = 1,
	ThrowPitchMax = 1.12, -- slight charge emphasis; no change to aim/camera
}
Config.Overrides = {
	["Frostbite"] = {
		TrailColors = {{255, 255, 255}, {0, 162, 255}, {255, 64, 64}, {255, 0, 0}},
		GlowColors = {{255, 255, 255}, {255, 255, 0}, {255, 128, 0}},
		SparkRate = 30,
		SparkColors = {{255, 255, 255}, {255, 200, 0}, {255, 100, 0}},
		ImpactColors = {{255, 255, 255}, {0, 162, 255}, {255, 64, 64}},
	},
	-- ["Shadow Dagger"] = {TrailWidth = 0.5, ThrowSoundId = "rbxassetid://YOUR_ID"},
}
Config.MaxEffectDistance = 500

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

function Config.Get(knifeName: string)
	local settings = copy(Config.Default)
	for key, value in pairs(Config.Overrides[knifeName] or {}) do settings[key] = copy(value) end
	assert(settings.BladeAxis == "Auto" or ({["+X"] = true, ["-X"] = true, ["+Y"] = true,
		["-Y"] = true, ["+Z"] = true, ["-Z"] = true})[settings.BladeAxis], "Invalid knife BladeAxis")
	assert(settings.StickDepth >= 0 and settings.StickDepth <= 10
		and settings.TipDistance >= 0 and settings.TipDistance <= 50, "Invalid knife tip/depth settings")
	assert(type(settings.RotationDegrees) == "table" and #settings.RotationDegrees == 3, "Knife rotation needs XYZ degrees")
	for _, angle in ipairs(settings.RotationDegrees) do
		assert(type(angle) == "number" and angle == angle and math.abs(angle) < math.huge, "Invalid knife rotation")
	end
	assert(settings.TrailWidth > 0 and settings.GlowWidth > 0, "Knife trail widths must be positive")
	assert(settings.TrailLifetime > 0 and settings.TrailLifetime <= 1
		and settings.GlowLifetime > 0 and settings.GlowLifetime <= 1, "Knife trail lifetime must be 0..1 seconds")
	assert(settings.TrailMaxLength > 0 and settings.TrailMaxLength <= 100, "Invalid knife trail length")
	assert(settings.SparkRate >= 0 and settings.SparkRate <= 60
		and settings.ImpactSparkCount >= 0 and settings.ImpactSparkCount <= 30, "Invalid knife particle budget")
	return settings
end

return Config
