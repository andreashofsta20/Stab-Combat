-- Cosmetics only. Damage, range and cooldown belong in KnifeConfig.
-- RGB arrays become evenly spaced ColorSequence keypoints along the trail.
local Config = {}
Config.Default = {
	BladeAxis = "Auto", -- or +X/-X/+Y/-Y/+Z/-Z for a mesh with an unusual orientation
	RotationDegrees = {0, 0, 0},
	StickFraction = 0.5, -- proportion of the visible knife embedded in a wall/floor
	StickDepth = 0, -- optional minimum depth in studs; fraction scales with each skin
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


	["Ethereal"] = {
	-- Long, thin, lingering icy streak (mirrors the Ethereal Revolver tracer)
		TrailColors = {{255, 255, 255}, {190, 240, 255}, {140, 220, 255}, {90, 175, 255}},
		TrailWidth = 0.26,
		TrailLifetime = 0.16,
		TrailMaxLength = 28,

		GlowColors = {{255, 255, 255}, {150, 215, 255}, {90, 175, 255}},
		GlowWidth = 0.8,
		GlowLifetime = 0.12,

	-- Frosty sparkles shed in flight
		SparkRate = 24,
		SparkColors = {{255, 255, 255}, {190, 240, 255}, {120, 200, 255}},

	-- Ice-spark impact
		ImpactSparkCount = 10,
		ImpactColors = {{255, 255, 255}, {185, 225, 245}, {120, 200, 255}},

		ThrowPitchMin = 1.05,
		ThrowPitchMax = 1.18,
	},

	["Valentine Knife"] = {
	-- Short, soft, glowy pink streak (mirrors the Valentine Revolver tracer)
		TrailColors = {{255, 255, 255}, {255, 205, 225}, {255, 170, 205}, {255, 120, 170}},
		TrailWidth = 0.4,
		TrailLifetime = 0.1,
		TrailMaxLength = 16,

		GlowColors = {{255, 255, 255}, {255, 175, 210}, {255, 120, 170}},
		GlowWidth = 0.9,
		GlowLifetime = 0.08,

	-- Pink sparkles shed in flight
		SparkRate = 20,
		SparkColors = {{255, 255, 255}, {255, 205, 225}, {255, 150, 195}},

	-- Pink-white sparkle impact
		ImpactSparkCount = 9,
		ImpactColors = {{255, 255, 255}, {255, 205, 222}, {255, 150, 195}},

		ThrowPitchMin = 1.03,
		ThrowPitchMax = 1.15,
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
	assert(settings.StickFraction >= 0 and settings.StickFraction <= 0.8, "Invalid knife embed fraction")
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
