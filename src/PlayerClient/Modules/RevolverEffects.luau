local DebrisService = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local Raycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local Effects = {}
local animationTracks = {}
local tracers = {}
local tracerConnection, tracerCount = nil, 0
local updateTracers
local createTracer
local reloadSoundAnchor = nil
local emptySound
local firstPersonShot
local bulletHoles, bulletHoleCursor, bulletHoleCount = {}, 0, 0
local bulletHoleConnection
local effectFolder = Instance.new("Folder")
effectFolder.Name, effectFolder.Parent = "LocalRevolverEffects", workspace
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FLARE = "rbxasset://textures/particles/flare_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local soundTemplates = {}
local function warmSound(soundId)
	if soundId == "" or soundTemplates[soundId] then return soundTemplates[soundId] end
	local template = Instance.new("Sound")
	template.SoundId, template.Parent = soundId, effectFolder
	soundTemplates[soundId] = template
	task.spawn(function()
		local ok, err = pcall(function() ContentProvider:PreloadAsync({template}) end)
		if not ok then warn("[RevolverEffects] Sound preload failed:", err) end
	end)
	return template
end

warmSound(Config.Default.Effects.EquipSoundId)
task.spawn(function()
	for _, soundId in ipairs({Config.Default.Effects.FireSoundId, Config.Default.Effects.ReloadSoundId}) do
		warmSound(soundId)
	end
end)

local function finiteVector(value, bound)
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) <= bound and math.abs(value.Y) <= bound and math.abs(value.Z) <= bound
end

local function colors(palette)
	if #palette == 1 then return ColorSequence.new(Color3.fromRGB(table.unpack(palette[1]))) end
	local points = {}
	for index, rgb in ipairs(palette) do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#palette - 1), Color3.fromRGB(table.unpack(rgb))))
	end
	return ColorSequence.new(points)
end

local function nearby(position)
	local camera = workspace.CurrentCamera
	return not camera or (position - camera.CFrame.Position).Magnitude <= Config.Presentation.MaxEffectDistance
end

local function removeTracer(key)
	local state = tracers[key]
	if not state then return end
	tracers[key] = nil
	state.key = nil
	tracerCount -= 1
	if state.pooled then
		state.core.Enabled, state.glow.Enabled, state.tip.Transparency = false, false, 1
		for _, ribbon in ipairs(state.ribbons) do ribbon.Enabled = false; ribbon:Clear() end
	else state.model:Destroy() end
	if tracerCount == 0 and tracerConnection then tracerConnection:Disconnect(); tracerConnection = nil end
end

-- A reused model must not let a late server reply correct a newer shot.
-- These local leases keep the existing Parent/Destroy presentation API intact.
local tracerLease = {}
function tracerLease:Destroy() removeTracer(self) end
tracerLease.__index = function(key, property)
	if property == "Parent" then
		local state = tracers[key]
		return state and state.model.Parent
	end
	return tracerLease[property]
end

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

local function playSound(id, position, settings, volume, timePosition)
	if id == "" then return nil end
	local part = anchor("RevolverSound", CFrame.new(position))
	local template = warmSound(id)
	local sound = template:Clone()
	sound.RollOffMaxDistance, sound.Volume, sound.Parent = settings.SoundRange, volume or settings.SoundVolume, part
	sound.PlaybackSpeed, sound.TimePosition = settings.SoundPlaybackSpeed, timePosition or 0
	sound:Play()
	DebrisService:AddItem(part, 8)
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

local function clearFirstPersonShot(destroy)
	local shot = firstPersonShot
	if not shot then return end
	shot.active = false
	shot.flash:Clear(); shot.sparks:Clear()
	for _, sound in ipairs(shot.sounds) do sound:Stop() end
	if destroy then
		for _, slot in ipairs(shot.tracerPool) do
			if slot.key then removeTracer(slot.key) end
			slot.model:Destroy()
		end
		if shot.ownsSocket then shot.socket:Destroy()
		else
			shot.flash:Destroy(); shot.sparks:Destroy()
			for _, sound in ipairs(shot.sounds) do sound:Destroy() end
		end
		firstPersonShot = nil
	end
end

local function updateFirstPersonMuzzle(shot)
	local base = shot.sourceMuzzle and shot.sourceMuzzle.CFrame or shot.baseFrame
	local camera, parent = workspace.CurrentCamera, shot.socket.Parent
	if camera and parent then
		-- Camera up/forward make these controls predictable across rotated skin sockets.
		local offset = parent.CFrame:VectorToObjectSpace(camera.CFrame:VectorToWorldSpace(shot.visualOffset))
		shot.socket.CFrame = CFrame.new(offset) * base
	else shot.socket.CFrame = base * CFrame.new(shot.visualOffset) end
end

function Effects.SetFirstPerson(visualTool, tuning)
	local shot = firstPersonShot
	if not visualTool or not tuning then
		if shot then
			if not shot.tool.Parent or not shot.socket.Parent then clearFirstPersonShot(true)
			elseif shot.active then clearFirstPersonShot(false) end
		end
		return
	end
	if shot and shot.tool == visualTool and shot.tuning == tuning and shot.socket.Parent then
		-- The proxy preserves ownership of the skin's original attachment and follows live edits.
		updateFirstPersonMuzzle(shot)
		shot.active = true; return
	end
	clearFirstPersonShot(true)
	local handle = visualTool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end
	local muzzle = visualTool:FindFirstChild(tuning.MuzzleAttachmentName, true)
	local socket = Instance.new("Attachment")
	socket.Name = "FirstPersonShotMuzzle"
	local visualOffset = Vector3.new(tuning.Effects.MuzzleVisualRight, tuning.Effects.MuzzleVisualUp, -tuning.Effects.MuzzleVisualForward)
	local sourceMuzzle, baseFrame
	-- A local proxy applies tuning even when the skin has an authored attachment.
	-- Never move/destroy that authored attachment: it also defines the real gun.
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		sourceMuzzle = muzzle
		baseFrame, socket.Parent = muzzle.CFrame, muzzle.Parent
	else
		if muzzle and muzzle:IsA("BasePart") then baseFrame, socket.Parent = CFrame.identity, muzzle
		else baseFrame, socket.Parent = CFrame.new(table.unpack(tuning.MuzzleOffset)), handle end
	end
	local settings, palette = tuning.FirstPerson, colors(tuning.Effects.MuzzleColors)
	local flash = emitter(socket, FLARE, palette)
	flash:SetAttribute("FirstPersonShotEffect", true)
	-- Emit at the validated shot origin; moving the barrel afterwards must not
	-- carry the flash through a nearby wall.
	flash.Name, flash.LockedToPart, flash.LightEmission = "FirstPersonShotFlash", false, 1
	flash.Lifetime, flash.Speed = NumberRange.new(settings.ShotFlashLifetimeMs / 1000), NumberRange.new(0)
	flash.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, settings.ShotFlashSize), NumberSequenceKeypoint.new(1, 0)})
	flash.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1)})
	flash.Rotation = NumberRange.new(0, 360)
	local sparks = emitter(socket, SPARK, palette)
	sparks:SetAttribute("FirstPersonShotEffect", true)
	sparks.Name, sparks.LightEmission = "FirstPersonShotSparks", 1
	sparks.Lifetime, sparks.Speed, sparks.SpreadAngle = NumberRange.new(settings.ShotSparkLifetimeMs / 1000), NumberRange.new(3, 7), Vector2.new(12, 12)
	sparks.Size, sparks.Transparency, sparks.Drag = NumberSequence.new(0.065, 0), NumberSequence.new(0, 1), 6
	local sounds = {}
	if tuning.Effects.FireSoundId ~= "" then
		for _ = 1, settings.ShotSoundVoices do
			local sound = Instance.new("Sound")
			sound.Name, sound.SoundId = "FirstPersonShotSound", tuning.Effects.FireSoundId
			sound.RollOffMaxDistance, sound.Volume = tuning.Effects.SoundRange, tuning.Effects.SoundVolume
			sound.PlaybackSpeed, sound.Parent = tuning.Effects.SoundPlaybackSpeed, socket
			table.insert(sounds, sound)
		end
	end
	local tracerPool = {}
	if tuning.Effects.TracerEnabled then
		for _ = 1, settings.ShotTracerSlots do table.insert(tracerPool, createTracer(tuning.Effects, true)) end
	end
	firstPersonShot = {tool = visualTool, tuning = tuning, socket = socket,
		flash = flash, sparks = sparks, sounds = sounds, voice = 0, active = true, ownsSocket = true,
		sourceMuzzle = sourceMuzzle, baseFrame = baseFrame, visualOffset = visualOffset,
		tracerPool = tracerPool, tracerVoice = 0}
	updateFirstPersonMuzzle(firstPersonShot)
end

local function fireFirstPerson(visualTool, tuning, origin, destination)
	Effects.SetFirstPerson(visualTool, tuning)
	local shot = firstPersonShot
	if not shot or not shot.active or shot.tool ~= visualTool then return false end
	local previousFrame = shot.socket.CFrame
	local direction = destination - origin
	if shot.socket.Parent then
		local frame = direction.Magnitude >= 0.001 and lookAlong(origin, direction)
			or CFrame.new(origin) * shot.socket.WorldCFrame.Rotation
		shot.socket.CFrame = shot.socket.Parent.CFrame:ToObjectSpace(frame)
	end
	if #shot.sounds > 0 then
		shot.voice = shot.voice % #shot.sounds + 1
		local sound = shot.sounds[shot.voice]
		sound:Stop(); sound.TimePosition = 0; sound:Play()
	end
	if tuning.FirstPerson.ShotEnabled and tuning.Effects.MuzzleFlashEnabled then
		shot.flash:Emit(2); shot.sparks:Emit(tuning.FirstPerson.ShotSparkCount)
	end
	shot.socket.CFrame = previousFrame
	return shot
end

local function muzzleBurst(origin, destination, settings)
	if not settings.MuzzleFlashEnabled and not settings.SmokeEnabled then return end
	local direction = destination - origin
	if direction.Magnitude < 0.001 then return end
	local part = anchor("RevolverMuzzleBurst", lookAlong(origin, direction))
	local socket = attachment(part)
	if settings.MuzzleFlashEnabled then
		local warm = colors(settings.MuzzleColors)
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
		light.Color, light.Brightness, light.Range, light.Shadows, light.Parent = Color3.fromRGB(table.unpack(settings.MuzzleLightColor)), 2, 9, false, part
		TweenService:Create(light, TweenInfo.new(settings.MuzzleFlashLifetimeMs / 1000), { Brightness = 0 }):Play()
	end
	if settings.SmokeEnabled then
		local smoke = emitter(socket, SMOKE, ColorSequence.new(Color3.fromRGB(table.unpack(settings.SmokeColor))))
		smoke.Lifetime, smoke.Speed, smoke.SpreadAngle = NumberRange.new(0.25, 0.6), NumberRange.new(1.5, 3), Vector2.new(20, 20)
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.6) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		smoke.Acceleration, smoke.Drag, smoke.Rotation = Vector3.new(0, 2, 0), 3, NumberRange.new(0, 360)
		smoke:Emit(settings.SmokeParticleCount)
	end
	DebrisService:AddItem(part, 1)
end

local function beam(parent, first, last, color, width, glow)
	local streak = Instance.new("Beam")
	streak.Attachment0, streak.Attachment1 = first, last
	streak.FaceCamera, streak.LightEmission, streak.LightInfluence, streak.Segments = true, 1, 0, 1
	streak.CurveSize0, streak.CurveSize1 = 0, 0
	streak.Width0, streak.Width1, streak.Color = width * 0.3, width, color
	streak.Transparency = NumberSequence.new(glow and 0.65 or 0.1)
	if glow then
		streak.Texture, streak.TextureMode, streak.TextureLength = FLARE, Enum.TextureMode.Stretch, 1
	end
	streak.Parent = parent
	return streak
end

local function trail(part, width, lifetime, color, transparency, maxLength)
	local left, right = attachment(part, Vector3.new(-width / 2, 0, 0)), attachment(part, Vector3.new(width / 2, 0, 0))
	local ribbon = Instance.new("Trail")
	ribbon.Attachment0, ribbon.Attachment1, ribbon.FaceCamera = left, right, true
	ribbon.Lifetime, ribbon.MinLength, ribbon.LightEmission, ribbon.LightInfluence = lifetime, 0.01, 1, 0
	ribbon.MaxLength = maxLength
	ribbon.Color, ribbon.Transparency = color, NumberSequence.new(transparency, 1)
	ribbon.WidthScale = NumberSequence.new(1, 0)
	ribbon.Parent = part
	return ribbon
end

createTracer = function(settings, pooled)
	local model = Instance.new("Folder")
	model.Name, model.Parent = "RevolverShotStreak", effectFolder
	local holder = anchor("Path", CFrame.identity, model)
	local first, last = attachment(holder), attachment(holder)
	local color = Color3.fromRGB(table.unpack(settings.TracerColor))
	local gold = ColorSequence.new(Color3.new(1, 1, 1), color)
	local core = beam(holder, first, last, gold, settings.TracerThickness, false)
	local glow = beam(holder, first, last, ColorSequence.new(color), settings.TracerGlowWidth, true)
	local tip = anchor("BulletGlint", CFrame.identity, model)
	tip.Transparency, tip.Material, tip.Color = 1, Enum.Material.Neon, Color3.new(1, 1, 1)
	tip.Size = Vector3.new(settings.TracerThickness, settings.TracerThickness, settings.TracerTipLength)
	local fade = settings.TracerLifetimeMs / 1000
	local ribbons = {trail(tip, settings.TracerThickness, fade * 0.7, gold, 0.15, settings.TracerTailLength),
		trail(tip, settings.TracerGlowWidth, fade, ColorSequence.new(color), 0.7, settings.TracerTailLength)}
	core.Enabled, glow.Enabled = false, false
	for _, ribbon in ipairs(ribbons) do ribbon.Enabled = false end
	return {model = model, holder = holder, pooled = pooled,
		travel = math.max(0.001, settings.VisualTravelMs / 1000), fade = math.max(0.01, fade),
		settings = settings, first = first, last = last, core = core, glow = glow, tip = tip, ribbons = ribbons}
end

local function placeTracer(state, elapsed, camera, pixelScale)
	local distance = math.min(state.distance, state.distance * elapsed / state.travel)
	state.first.Position = state.direction * math.max(0, distance - state.settings.TracerTailLength)
	state.last.Position = state.direction * distance
	local position = state.origin + state.direction * distance
	state.tip.CFrame = lookAlong(position, state.direction)
	local settings = state.settings
	pixelScale = pixelScale or (camera and 2 * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(1, camera.ViewportSize.Y) or 0)
	local pixels = camera and (position - camera.CFrame.Position).Magnitude * pixelScale * settings.TracerMinPixels or 0
	local width = math.max(settings.TracerThickness, math.min(settings.TracerMaxThickness, pixels))
	local glowWidth = settings.TracerGlowWidth * width / math.max(0.001, settings.TracerThickness)
	state.tip.Size = Vector3.new(width, width, settings.TracerTipLength)
	local fade = math.clamp((elapsed - state.travel) / state.fade, 0, 1)
	state.tip.Transparency = elapsed >= state.travel and 1 or 0.15
	state.core.Width0, state.core.Width1 = width * 0.3 * (1 - fade), width * (1 - fade)
	state.glow.Width0, state.glow.Width1 = glowWidth * 0.3 * (1 - fade), glowWidth * (1 - fade)
end

local function resetTracerPath(state, elapsed)
	-- Trail stores previous attachment samples. Disable it before teleporting,
	-- then clear after placement so an ack or pooled reuse cannot connect paths.
	for _, ribbon in ipairs(state.ribbons) do ribbon.Enabled = false; ribbon:Clear() end
	state.holder.CFrame = CFrame.new(state.origin)
	placeTracer(state, elapsed, workspace.CurrentCamera)
	for _, ribbon in ipairs(state.ribbons) do
		ribbon:Clear()
		ribbon.Enabled = elapsed < state.travel
	end
end

function Effects.Tracer(origin, destination, settings, slot)
	local vector = destination - origin
	if not settings.TracerEnabled or vector.Magnitude < 0.001 then return nil end
	if slot and slot.key then removeTracer(slot.key) end
	if tracerCount >= Config.Presentation.MaxActiveTracers then
		local oldest, started = nil, math.huge
		for key, state in pairs(tracers) do if state.start < started then oldest, started = key, state.start end end
		if oldest then removeTracer(oldest) end
	end
	local state = slot or createTracer(settings, false)
	local key = slot and setmetatable({}, tracerLease) or state.model
	state.key, state.origin, state.direction = key, origin, vector.Unit
	state.distance, state.start = vector.Magnitude, os.clock()
	resetTracerPath(state, 0)
	state.core.Enabled, state.glow.Enabled = true, true
	tracers[key] = state
	tracerCount += 1
	if not tracerConnection then tracerConnection = RunService.RenderStepped:Connect(updateTracers) end
	if not slot then DebrisService:AddItem(state.model, state.travel + state.fade + 0.5) end
	return key
end

function Effects.CorrectTracer(model, destination)
	local state = tracers[model]
	if not state then return end
	if not finiteVector(destination, Config.Security.MaxCoordinate) then return end
	local vector = destination - state.origin
	if vector.Magnitude < 0.001 then removeTracer(model); return end
	state.direction, state.distance = vector.Unit, vector.Magnitude
	-- Keep the original shot age. A reply during fade must not emit a second
	-- traveling glint or draw a chord between predicted and confirmed endpoints.
	resetTracerPath(state, math.max(0, os.clock() - state.start))
end

-- One shared update, connected only while there are live streaks.
updateTracers = function()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local pixelScale = camera and 2 * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(1, camera.ViewportSize.Y) or 0
	for model, state in pairs(tracers) do
		if not state.model.Parent then removeTracer(model); continue end
		local elapsed = math.max(0, now - state.start)
		if elapsed >= state.travel + state.fade then removeTracer(model); continue end
		placeTracer(state, elapsed, camera, pixelScale)
		for _, ribbon in ipairs(state.ribbons) do ribbon.Enabled = elapsed < state.travel end
	end
end

local function hideBulletHole(state)
	if not state.active then return end
	state.active, state.surface, state.localFrame = false, nil, nil
	state.gui.Enabled = false
	state.visible = false
	bulletHoleCount -= 1
end

local function holeFrame(parent, name, size, position, rotation)
	local frame = Instance.new("Frame")
	frame.Name, frame.BorderSizePixel, frame.BackgroundColor3 = name, 0, Color3.fromRGB(12, 10, 8)
	frame.AnchorPoint, frame.Size, frame.Position = Vector2.new(0.5, 0.5), size, position
	frame.Rotation, frame.Parent = rotation or 0, parent
	return frame
end

local function createBulletHole()
	local part = anchor("RevolverBulletHole", CFrame.identity)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.CanvasSize = "BulletHoleSurface", Enum.NormalId.Front, Vector2.new(64, 64)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.AlwaysOnTop, gui.LightInfluence, gui.Enabled, gui.Parent = false, 1, false, part
	local image = Instance.new("ImageLabel")
	image.Name, image.BackgroundTransparency, image.Size, image.Parent = "Texture", 1, UDim2.fromScale(1, 1), gui
	local fallback = Instance.new("Frame")
	fallback.Name, fallback.BackgroundTransparency, fallback.Size, fallback.Parent = "DrawnPuncture", 1, UDim2.fromScale(1, 1), gui
	local center = holeFrame(fallback, "Puncture", UDim2.fromScale(0.48, 0.48), UDim2.fromScale(0.5, 0.5))
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0.5, 0), center
	local shapes = {center}
	for index, rotation in ipairs({18, 79, 146}) do
		local crack = holeFrame(fallback, "Crack" .. index, UDim2.fromScale(0.87 - index * 0.1, 0.035),
			UDim2.fromScale(0.5, 0.5), rotation)
		table.insert(shapes, crack)
	end
	return {part = part, gui = gui, image = image, fallback = fallback, shapes = shapes, active = false}
end

local function updateBulletHoles()
	local now, camera = os.clock(), workspace.CurrentCamera
	for _, state in ipairs(bulletHoles) do
		if not state.active then continue end
		local settings, elapsed = state.settings, now - state.started
		if elapsed >= settings.BulletHoleLifetime or not state.part.Parent or not state.surface.Parent then
			hideBulletHole(state); continue
		end
		local frame = state.frame
		if state.localFrame and state.surface.CFrame ~= state.sourceFrame then
			state.sourceFrame = state.surface.CFrame
			frame = state.sourceFrame * state.localFrame
			state.frame, state.part.CFrame = frame, frame
		end
		local distance = camera and (frame.Position - camera.CFrame.Position).Magnitude or 0
		local visible = not camera or distance <= settings.BulletHoleMaxDistance
			and distance >= settings.BulletHoleMinCameraDistance
		if visible ~= state.visible then state.visible, state.gui.Enabled = visible, visible end
		local fade = math.clamp((elapsed - settings.BulletHoleLifetime + settings.BulletHoleFadeSeconds)
			/ settings.BulletHoleFadeSeconds, 0, 1)
		if fade ~= state.fade then
			state.fade, state.image.ImageTransparency = fade, fade
			for _, shape in ipairs(state.shapes) do shape.BackgroundTransparency = fade end
		end
	end
	if bulletHoleCount == 0 and bulletHoleConnection then
		bulletHoleConnection:Disconnect(); bulletHoleConnection = nil
	end
end

function Effects.BulletHole(position, normal, surface, settings)
	if not settings.BulletHoleEnabled or not finiteVector(position, Config.Security.MaxCoordinate)
		or not finiteVector(normal, 2) or normal.Magnitude < 0.5 or normal.Magnitude > 1.5
		or typeof(surface) ~= "Instance" or not surface.Parent
		or not (surface:IsA("BasePart") or surface:IsA("Terrain")) then return end
	-- Defensive presentation check: a world ray should never produce a mark on an avatar.
	local ancestor = surface.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return end
		ancestor = ancestor.Parent
	end
	local camera = workspace.CurrentCamera
	if camera and (position - camera.CFrame.Position).Magnitude > settings.BulletHoleMaxDistance then return end
	bulletHoleCursor = bulletHoleCursor % Config.Presentation.MaxBulletHoles + 1
	local state = bulletHoles[bulletHoleCursor]
	if not state then state = createBulletHole(); bulletHoles[bulletHoleCursor] = state end
	if not state.active then bulletHoleCount += 1 end
	state.active, state.surface, state.settings, state.started = true, surface, settings, os.clock()
	state.frame = lookAlong(position + normal.Unit * settings.BulletHoleSurfaceOffset, normal)
	state.localFrame = surface:IsA("BasePart") and surface.CFrame:ToObjectSpace(state.frame) or nil
	state.sourceFrame = surface:IsA("BasePart") and surface.CFrame or nil
	state.part.Size, state.part.CFrame = Vector3.new(settings.BulletHoleSize, settings.BulletHoleSize, 0.005), state.frame
	state.gui.MaxDistance = settings.BulletHoleMaxDistance
	state.image.Image, state.image.ImageTransparency = settings.BulletHoleTextureId, 0
	state.image.Visible, state.fallback.Visible = settings.BulletHoleTextureId ~= "", settings.BulletHoleTextureId == ""
	for _, shape in ipairs(state.shapes) do shape.BackgroundTransparency = 0 end
	state.gui.Enabled = not camera or (position - camera.CFrame.Position).Magnitude >= settings.BulletHoleMinCameraDistance
	state.visible, state.fade = state.gui.Enabled, 0
	if not bulletHoleConnection then bulletHoleConnection = RunService.RenderStepped:Connect(updateBulletHoles) end
	return state.part
end

function Effects.Impact(position, normal, settings, surface, hitPlayer)
	if not finiteVector(position, Config.Security.MaxCoordinate) or not finiteVector(normal, 2)
		or normal.Magnitude < 0.5 or normal.Magnitude > 1.5 or not nearby(position) then return end
	if hitPlayer ~= true then Effects.BulletHole(position, normal, surface, settings) end
	if not settings.ImpactEnabled then return end
	normal = normal.Unit
	local part = anchor("RevolverImpact", lookAlong(position + normal * 0.025, normal))
	local socket = attachment(part)
	local sparks = emitter(socket, SPARK, colors(settings.ImpactColors))
	sparks.Lifetime, sparks.Speed, sparks.SpreadAngle = NumberRange.new(0.08, 0.2), NumberRange.new(8, 18), Vector2.new(45, 45)
	sparks.Size, sparks.Transparency, sparks.LightEmission = NumberSequence.new(0.09, 0), NumberSequence.new(0, 1), 1
	sparks.Acceleration, sparks.Drag = Vector3.new(0, -12, 0), 4
	sparks:Emit(settings.ImpactSparkCount)
	DebrisService:AddItem(part, 0.5)
end

function Effects.GetShotOrigin(tool, origin, tuning, visualTool, firstPerson)
	if firstPerson and visualTool then Effects.SetFirstPerson(visualTool, tuning) end
	local shot = firstPersonShot
	if firstPerson and shot and shot.active and shot.tool == visualTool and shot.tuning == tuning then
		return shot.socket.WorldPosition
	end
	local presented = visualTool or tool
	if not presented then return origin end
	local physical = Raycast.GetMuzzlePosition(presented, tuning)
	local visual = Raycast.GetVisualMuzzleFrame(presented, tuning)
	local head = tool and tool.Parent and tool.Parent:FindFirstChild("Head")
	if visual and (presented == visualTool or head and head:IsA("BasePart")
		and physical and (physical - head.Position).Magnitude <= Config.Security.MaxMuzzleDistance) then
		return visual.Position
	end
	return origin
end

function Effects.ConfirmedTracer(origin, destination, tuning, visualTool, firstPerson)
	if not finiteVector(origin, Config.Security.MaxCoordinate)
		or not finiteVector(destination, Config.Security.MaxCoordinate) then return nil end
	local shot = firstPersonShot
	if firstPerson and shot and shot.active and shot.tool == visualTool and shot.tuning == tuning
		and #shot.tracerPool > 0 then
		shot.tracerVoice = shot.tracerVoice % #shot.tracerPool + 1
		return Effects.Tracer(origin, destination, tuning.Effects, shot.tracerPool[shot.tracerVoice])
	end
	return Effects.Tracer(origin, destination, tuning.Effects)
end

function Effects.Fire(tool, origin, destination, tuning, animateCharacter, visualTool, firstPerson, suppressSound, deferTracer, shotOrigin)
	local player = game:GetService("Players").LocalPlayer
	local stats = player and player:FindFirstChild("leaderstats")
	local settings = stats and stats:FindFirstChild("Settings")
	local reduced = settings and settings:FindFirstChild("ReducedEffects")
	if reduced and reduced.Value then
		if not suppressSound then playSound(tuning.Effects.FireSoundId, origin, tuning.Effects) end
		return nil -- Preserve sound/hit feedback, omit bursts and tracers.
	end
	if not animateCharacter and not nearby(origin) and not nearby(destination) then return nil end
	-- Observer origins are the server's accepted origins, never a replicated
	-- barrel pose. Owners supply their cover-checked cosmetic origin.
	if animateCharacter then
		origin = shotOrigin or Effects.GetShotOrigin(tool, origin, tuning, visualTool, firstPerson)
	end
	if animateCharacter and firstPerson then
		if tool then animate(tool.Parent, tuning.Effects.FireAnimationId, "Fire") end
		local shot = fireFirstPerson(visualTool, tuning, origin, destination)
		if not shot then
			playSound(tuning.Effects.FireSoundId, origin, tuning.Effects)
		end
		if deferTracer then return nil end
		return Effects.ConfirmedTracer(origin, destination, tuning, visualTool, firstPerson)
	end
	if tool then
		local presented = animateCharacter and visualTool or tool
		local _, muzzle = Raycast.GetVisualMuzzleFrame(presented or tool, tuning)
		-- Authored particles are a fallback when the built-in burst is disabled.
		-- Emitting both produces two flashes at different muzzle offsets.
		local authoredPosition = muzzle and (muzzle:IsA("Attachment") and muzzle.WorldPosition or muzzle.Position)
		if muzzle and not tuning.Effects.MuzzleFlashEnabled and not tuning.Effects.SmokeEnabled
			and tuning.Effects.CustomMuzzleParticlesEnabled and authoredPosition
			and (authoredPosition - origin).Magnitude <= 0.02 then
			for _, custom in ipairs(muzzle:GetDescendants()) do
				if custom:IsA("ParticleEmitter") then custom:Emit(tuning.Effects.MuzzleParticleCount) end
			end
		end
		if animateCharacter then animate(tool.Parent, tuning.Effects.FireAnimationId, "Fire") end
	end
	if not suppressSound then playSound(tuning.Effects.FireSoundId, origin, tuning.Effects) end
	muzzleBurst(origin, destination, tuning.Effects)
	if deferTracer then return nil end
	return Effects.Tracer(origin, destination, tuning.Effects)
end

function Effects.Equip(tool, tuning)
	local handle = tool:FindFirstChild("Handle")
	local head = tool.Parent and tool.Parent:FindFirstChild("Head")
	local part = handle or head
	if part and part:IsA("BasePart") then
		playSound(tuning.Effects.EquipSoundId, part.Position, tuning.Effects, tuning.Effects.EquipSoundVolume, 0.13)
	end
end

function Effects.Empty(_, tuning)
	local settings = tuning.Effects
	if settings.EmptySoundId == "" then return end
	if not emptySound then
		emptySound = Instance.new("Sound")
		emptySound.Name, emptySound.Parent = "RevolverEmptySound", effectFolder
	end
	-- A Folder-parented sound is local, non-positional feedback for the owner.
	emptySound:Stop()
	emptySound.SoundId, emptySound.Volume = settings.EmptySoundId, settings.EmptySoundVolume
	emptySound.PlaybackSpeed, emptySound.TimePosition = settings.SoundPlaybackSpeed, 0
	emptySound:Play()
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
	if emptySound then emptySound:Stop(); emptySound:Destroy(); emptySound = nil end
	clearFirstPersonShot(true)
	for _, entry in pairs(animationTracks) do entry.track:Destroy() end
	table.clear(animationTracks)
	for model in pairs(tracers) do removeTracer(model) end
	for _, state in ipairs(bulletHoles) do hideBulletHole(state); state.part:Destroy() end
	table.clear(bulletHoles)
	bulletHoleCursor = 0
	if bulletHoleConnection then bulletHoleConnection:Disconnect(); bulletHoleConnection = nil end
end

return Effects
