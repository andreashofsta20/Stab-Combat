local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Effects = {}
local animationTracks = {}
local tracers = {}
local reloadSoundAnchor = nil
local effectFolder = Instance.new("Folder")
effectFolder.Name, effectFolder.Parent = "LocalRevolverEffects", workspace
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FLARE = "rbxasset://textures/particles/flare_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function lookAlong(position, direction)
	local up = math.abs(direction.Y) / direction.Magnitude > 0.98 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	return CFrame.lookAt(position, position + direction, up)
end

local function anchor(name, frame, parent)
	local part = Instance.new("Part")
	part.Name, part.Size, part.Transparency = name, Vector3.one * 0.1, 1
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.CastShadow = false
	part.CFrame, part.Parent = frame, parent or effectFolder
	return part
end

local function attachment(parent, position)
	local socket = Instance.new("Attachment")
	socket.Position, socket.Parent = position or Vector3.zero, parent
	return socket
end

local function playSound(id, position, settings)
	if id == "" then return nil end
	local part = anchor("RevolverSound", CFrame.new(position))
	local sound = Instance.new("Sound")
	sound.SoundId, sound.RollOffMaxDistance, sound.Volume, sound.Parent = id, settings.SoundRange, settings.SoundVolume, part
	sound:Play()
	Debris:AddItem(part, 8)
	return part
end

local function animate(character, id, kind)
	if id == "" then return end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local entry = animationTracks[kind]
	if not entry or entry.animator ~= animator or entry.id ~= id then
		if entry then entry.track:Destroy() end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
		animation:Destroy()
		if not ok then return end
		track.Priority = Enum.AnimationPriority.Action4
		entry = { track = track, animator = animator, id = id }
		animationTracks[kind] = entry
	end
	entry.track:Play(0.03)
end

local function emitter(socket, texture, color)
	local particles = Instance.new("ParticleEmitter")
	particles.Texture, particles.Rate, particles.Enabled = texture, 0, false
	particles.Color, particles.LightInfluence = color, 0
	particles.EmissionDirection = Enum.NormalId.Front
	particles.Parent = socket
	return particles
end

local function muzzleBurst(origin, destination, settings)
	if not settings.MuzzleFlashEnabled and not settings.SmokeEnabled then return end
	local direction = destination - origin
	if direction.Magnitude < 0.001 then return end
	local part = anchor("RevolverMuzzleBurst", lookAlong(origin, direction))
	local socket = attachment(part)
	if settings.MuzzleFlashEnabled then
		local warm = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 218, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 125, 40)),
		})
		local flash = emitter(socket, FLARE, warm)
		flash.Lifetime, flash.Speed = NumberRange.new(settings.MuzzleFlashLifetimeMs / 1000), NumberRange.new(0)
		flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, settings.MuzzleFlashSize), NumberSequenceKeypoint.new(1, 0) })
		flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		flash.Rotation, flash.LightEmission = NumberRange.new(0, 360), 1
		flash:Emit(2)
		local sparks = emitter(socket, SPARK, warm)
		sparks.Lifetime, sparks.Speed, sparks.SpreadAngle = NumberRange.new(0.045, 0.12), NumberRange.new(12, 24), Vector2.new(18, 18)
		sparks.Size, sparks.Transparency, sparks.LightEmission = NumberSequence.new(0.12, 0), NumberSequence.new(0, 1), 1
		sparks.Drag = 5
		sparks:Emit(settings.MuzzleParticleCount)
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range, light.Shadows, light.Parent = Color3.fromRGB(255, 211, 120), 2, 9, false, part
		TweenService:Create(light, TweenInfo.new(settings.MuzzleFlashLifetimeMs / 1000), { Brightness = 0 }):Play()
	end
	if settings.SmokeEnabled then
		local smoke = emitter(socket, SMOKE, ColorSequence.new(Color3.fromRGB(155, 148, 136)))
		smoke.Lifetime, smoke.Speed, smoke.SpreadAngle = NumberRange.new(0.25, 0.6), NumberRange.new(1.5, 3), Vector2.new(20, 20)
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.6) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		smoke.Acceleration, smoke.Drag, smoke.Rotation = Vector3.new(0, 2, 0), 3, NumberRange.new(0, 360)
		smoke:Emit(settings.SmokeParticleCount)
	end
	Debris:AddItem(part, 1)
end

local function beam(parent, first, last, color, width, glow)
	local streak = Instance.new("Beam")
	streak.Attachment0, streak.Attachment1 = first, last
	streak.FaceCamera, streak.LightEmission, streak.LightInfluence, streak.Segments = true, 1, 0, 1
	streak.Width0, streak.Width1, streak.Color = width * 0.3, width, color
	streak.Transparency = NumberSequence.new(glow and 0.65 or 0.1)
	if glow then
		streak.Texture, streak.TextureMode, streak.TextureLength = FLARE, Enum.TextureMode.Stretch, 1
	end
	streak.Parent = parent
	return streak
end

local function trail(part, width, lifetime, color, transparency)
	local left, right = attachment(part, Vector3.new(-width / 2, 0, 0)), attachment(part, Vector3.new(width / 2, 0, 0))
	local ribbon = Instance.new("Trail")
	ribbon.Attachment0, ribbon.Attachment1, ribbon.FaceCamera = left, right, true
	ribbon.Lifetime, ribbon.MinLength, ribbon.LightEmission, ribbon.LightInfluence = lifetime, 0.01, 1, 0
	ribbon.Color, ribbon.Transparency = color, NumberSequence.new(transparency, 1)
	ribbon.WidthScale = NumberSequence.new(1, 0)
	ribbon.Parent = part
	return ribbon
end

function Effects.Tracer(origin, destination, settings)
	local vector = destination - origin
	if not settings.TracerEnabled or vector.Magnitude < 0.001 then return nil end
	local model = Instance.new("Folder")
	model.Name, model.Parent = "RevolverShotStreak", effectFolder
	local holder = anchor("Path", CFrame.new(origin), model)
	local first, last = attachment(holder), attachment(holder)
	local color = Color3.fromRGB(table.unpack(settings.TracerColor))
	local gold = ColorSequence.new(Color3.new(1, 1, 1), color)
	local core = beam(holder, first, last, gold, settings.TracerThickness, false)
	local glow = beam(holder, first, last, ColorSequence.new(color), settings.TracerGlowWidth, true)
	local tip = anchor("BulletGlint", lookAlong(origin, vector), model)
	tip.Transparency, tip.Material, tip.Color = 0.15, Enum.Material.Neon, Color3.new(1, 1, 1)
	tip.Size = Vector3.new(settings.TracerThickness, settings.TracerThickness, 0.22)
	local fade = settings.TracerLifetimeMs / 1000
	trail(tip, settings.TracerThickness, fade * 0.7, gold, 0.15)
	trail(tip, settings.TracerGlowWidth, fade, ColorSequence.new(color), 0.7)
	tracers[model] = { model = model, origin = origin, direction = vector.Unit,
		distance = vector.Magnitude, start = os.clock(), travel = math.max(0.001, settings.VisualTravelMs / 1000),
		fade = math.max(0.01, fade), settings = settings, first = first, last = last, core = core, glow = glow, tip = tip }
	last.Position = vector.Unit * math.min(vector.Magnitude, 0.8)
	Debris:AddItem(model, settings.VisualTravelMs / 1000 + fade + 0.5)
	return model
end

function Effects.CorrectTracer(model, destination)
	local state = tracers[model]
	if not state then return end
	local vector = destination - state.origin
	if vector.Magnitude < 0.001 then model:Destroy(); tracers[model] = nil; return end
	state.direction, state.distance = vector.Unit, vector.Magnitude
end

-- One update for all cosmetic shots, rather than one connection per bullet.
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for model, state in pairs(tracers) do
		if not model.Parent then tracers[model] = nil; continue end
		local elapsed = now - state.start
		if elapsed >= state.travel + state.fade then model:Destroy(); tracers[model] = nil; continue end
		local distance = math.min(state.distance, state.distance * elapsed / state.travel)
		state.first.Position = state.direction * math.max(0, distance - state.settings.TracerTailLength)
		state.last.Position = state.direction * distance
		local position = state.origin + state.direction * distance
		state.tip.CFrame = lookAlong(position, state.direction)
		local fade = math.clamp((elapsed - state.travel) / state.fade, 0, 1)
		state.tip.Transparency = elapsed >= state.travel and 1 or 0.15
		state.core.Width0, state.core.Width1 = state.settings.TracerThickness * 0.3 * (1 - fade), state.settings.TracerThickness * (1 - fade)
		state.glow.Width0, state.glow.Width1 = state.settings.TracerGlowWidth * 0.3 * (1 - fade), state.settings.TracerGlowWidth * (1 - fade)
	end
end)

function Effects.Impact(position, normal, settings)
	if not settings.ImpactEnabled or typeof(normal) ~= "Vector3" or normal.Magnitude < 0.5 then return end
	local part = anchor("RevolverImpact", lookAlong(position + normal * 0.025, normal))
	local socket = attachment(part)
	local sparks = emitter(socket, SPARK, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 165, 65)))
	sparks.Lifetime, sparks.Speed, sparks.SpreadAngle = NumberRange.new(0.08, 0.2), NumberRange.new(8, 18), Vector2.new(45, 45)
	sparks.Size, sparks.Transparency, sparks.LightEmission = NumberSequence.new(0.09, 0), NumberSequence.new(0, 1), 1
	sparks.Acceleration, sparks.Drag = Vector3.new(0, -12, 0), 4
	sparks:Emit(settings.ImpactSparkCount)
	Debris:AddItem(part, 0.5)
end

function Effects.Fire(tool, origin, destination, tuning, animateCharacter)
	-- Prefer this client's posed barrel for presentation; this never changes
	-- the server's firing origin or sends cosmetic positions back to it.
	if tool then
		local head = tool.Parent and tool.Parent:FindFirstChild("Head")
		local muzzle = tool:FindFirstChild(tuning.MuzzleAttachmentName, true)
		local visual = muzzle and (muzzle:IsA("Attachment") and muzzle.WorldPosition or muzzle:IsA("BasePart") and muzzle.Position)
		if not visual then
			local handle = tool:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				visual = handle.CFrame:PointToWorldSpace(Vector3.new(table.unpack(tuning.MuzzleOffset)))
			end
		end
		if visual and head and head:IsA("BasePart") and (visual - head.Position).Magnitude <= 7 then origin = visual end
		if muzzle then
			for _, custom in ipairs(muzzle:GetDescendants()) do
				if custom:IsA("ParticleEmitter") then custom:Emit(tuning.Effects.MuzzleParticleCount) end
			end
		end
		if animateCharacter then animate(tool.Parent, tuning.Effects.FireAnimationId, "Fire") end
	end
	muzzleBurst(origin, destination, tuning.Effects)
	playSound(tuning.Effects.FireSoundId, origin, tuning.Effects)
	return Effects.Tracer(origin, destination, tuning.Effects)
end

function Effects.Reload(tool, tuning)
	Effects.StopReload()
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then reloadSoundAnchor = playSound(tuning.Effects.ReloadSoundId, handle.Position, tuning.Effects) end
	animate(tool.Parent, tuning.Effects.ReloadAnimationId, "Reload")
end

function Effects.StopReload()
	if reloadSoundAnchor then reloadSoundAnchor:Destroy(); reloadSoundAnchor = nil end
	local entry = animationTracks.Reload
	if entry then entry.track:Stop(0.05) end
end

function Effects.Clear()
	Effects.StopReload()
	for _, entry in pairs(animationTracks) do entry.track:Destroy() end
	table.clear(animationTracks)
	for model in pairs(tracers) do model:Destroy() end
	table.clear(tracers)
end

return Effects
