local Debris = game:GetService("Debris")
local Effects = {}
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function colors(rgb)
	if #rgb == 1 then return ColorSequence.new(Color3.fromRGB(table.unpack(rgb[1]))) end
	local points = {}
	for index, color in ipairs(rgb) do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#rgb - 1), Color3.fromRGB(table.unpack(color))))
	end
	return ColorSequence.new(points)
end

local function trail(part, width, lifetime, palette, settings, glow)
	local left, right = Instance.new("Attachment"), Instance.new("Attachment")
	left.Position, right.Position = Vector3.new(-width / 2, 0, 0), Vector3.new(width / 2, 0, 0)
	left.Parent, right.Parent = part, part
	local streak = Instance.new("Trail")
	streak.Name = glow and "KnifeGlow" or "KnifeRail"
	streak.Attachment0, streak.Attachment1 = left, right
	streak.Lifetime, streak.MaxLength, streak.MinLength = lifetime, settings.TrailMaxLength, 0
	streak.FaceCamera, streak.LightEmission, streak.LightInfluence = true, 1, 0
	streak.Color, streak.Texture = colors(palette), settings.TrailTexture
	streak.WidthScale = NumberSequence.new(1, 0)
	streak.Transparency = NumberSequence.new(glow and 0.65 or 0, 1)
	streak.Parent = part
	return streak
end

local function sparks(socket, palette)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture, emitter.Color, emitter.LightEmission, emitter.LightInfluence = SPARK, colors(palette), 1, 0
	emitter.Lifetime, emitter.Speed = NumberRange.new(0.07, 0.18), NumberRange.new(3, 9)
	emitter.Size, emitter.Transparency = NumberSequence.new(0.09, 0), NumberSequence.new(0, 1)
	emitter.SpreadAngle, emitter.Parent = Vector2.new(45, 45), socket
	return emitter
end

function Effects.Attach(part, settings)
	local live = {}
	if settings.TrailEnabled then
		table.insert(live, trail(part, settings.TrailWidth, settings.TrailLifetime, settings.TrailColors, settings, false))
		if settings.GlowEnabled then
			table.insert(live, trail(part, settings.GlowWidth, settings.GlowLifetime, settings.GlowColors, settings, true))
		end
	end
	if settings.SparkRate > 0 then
		local socket = Instance.new("Attachment")
		socket.Parent = part
		local emitter = sparks(socket, settings.SparkColors)
		emitter.Rate = settings.SparkRate
		table.insert(live, emitter)
	end
	return function() -- stop emission on impact; let existing trails fade naturally
		for _, effect in ipairs(live) do if effect.Parent then effect.Enabled = false end end
	end
end

local function anchor(position)
	local part = Instance.new("Part")
	part.Name, part.Size, part.Transparency = "KnifeEffect", Vector3.one * 0.1, 1
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.CFrame, part.Parent = CFrame.new(position), workspace
	return part
end

local function sound(part, id, settings, pitch, fallback)
	if id == "" and not fallback then return end
	local audio = id == "" and fallback:Clone() or Instance.new("Sound")
	if not audio then return end
	if id ~= "" then audio.SoundId = id end
	audio.Looped, audio.Volume, audio.RollOffMaxDistance = false, settings.SoundVolume, settings.SoundRange
	audio.PlaybackSpeed, audio.Parent = pitch, part
	audio:Play()
	return audio
end

function Effects.ThrowSound(position, charge, settings, fallback)
	if settings.ThrowSoundId == "" and not fallback then return end
	local part = anchor(position)
	sound(part, settings.ThrowSoundId, settings,
		settings.ThrowPitchMin + (settings.ThrowPitchMax - settings.ThrowPitchMin) * math.clamp(charge, 0, 1), fallback)
	Debris:AddItem(part, 5)
end

function Effects.Impact(position, normal, settings)
	if typeof(normal) ~= "Vector3" or normal.Magnitude < 0.5 then return end
	local emitParticles = settings.ImpactEnabled and settings.ImpactSparkCount > 0
	if not emitParticles and settings.ImpactSoundId == "" then return end
	local part = anchor(position + normal * 0.025)
	if emitParticles then
		local up = math.abs(normal.Y) > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		part.CFrame = CFrame.lookAt(position + normal * 0.025, position + normal, up)
		local socket = Instance.new("Attachment")
		socket.Parent = part
		local emitter = sparks(socket, settings.ImpactColors)
		emitter.EmissionDirection, emitter.Rate, emitter.Enabled = Enum.NormalId.Front, 0, false
		emitter:Emit(settings.ImpactSparkCount)
	end
	local audio = sound(part, settings.ImpactSoundId, settings, 1)
	-- A burst ends within 0.18 seconds. Retain its anchor longer only if it
	-- owns audio, instead of accumulating five seconds of invisible effects.
	Debris:AddItem(part, audio and 5 or 0.25)
end

return Effects
