-- Other players' accepted weapon sounds use one bounded, reusable point-source pool.
-- This never sends gameplay requests, moves character parts, or runs a frame update.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(ReplicatedStorage.Modules.CombatAudioConfig).Observer
local RevolverConfig = require(ReplicatedStorage.Modules.RevolverConfig)
local KnifeConfig = require(ReplicatedStorage.Modules.KnifeEffectsConfig)
local player = Players.LocalPlayer
local Audio = {}
local initialized, generation = false, 0
local folder
local connections, voices = {}, {}
local recent, recentOrder, recentIndex = {}, {}, 0
local revolverSettings, knifeSettings, preloadRequested = {}, {}, {}

assert(Config.MaxVoices >= 1 and Config.MaxVoices <= 48 and Config.MaxVoices % 1 == 0, "Invalid observer audio voice budget")
assert(Config.RememberedEvents >= Config.MaxVoices and Config.RememberedEvents <= 1024
	and Config.RememberedEvents % 1 == 0, "Invalid observer audio history budget")
local rollOffMode = assert(Enum.RollOffMode[Config.RollOffMode], "Invalid observer audio falloff")
for _, settings in ipairs({Config.Revolver, Config.KnifeThrow}) do
	assert(settings.MinDistance >= 0 and settings.MaxDistance > settings.MinDistance
		and settings.MaxDistance <= 1000 and settings.VolumeScale >= 0 and settings.VolumeScale <= 2,
		"Invalid observer audio distance/volume")
end

local function finite(number)
	return type(number) == "number" and number == number and math.abs(number) < math.huge
end

local function positionValid(position)
	return typeof(position) == "Vector3" and finite(position.X) and finite(position.Y) and finite(position.Z)
		and math.max(math.abs(position.X), math.abs(position.Y), math.abs(position.Z)) <= 1000000
end

local function integerValid(number)
	return finite(number) and math.abs(number) <= 9007199254740991 and number % 1 == 0
end

local function nameValid(name)
	return type(name) == "string" and #name > 0 and #name <= 128
end

local function remember(key)
	if recent[key] then return false end
	recentIndex = recentIndex % Config.RememberedEvents + 1
	local previous = recentOrder[recentIndex]
	if previous then recent[previous] = nil end
	recentOrder[recentIndex], recent[key] = key, true
	return true
end

local function knifeFallback()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local sound = sounds and sounds:FindFirstChild("ThrowKnife")
	return sound and sound:IsA("Sound") and sound or nil
end

local function preload(ids)
	local requested = {}
	for _, id in ipairs(ids) do
		if type(id) == "string" and id ~= "" and not preloadRequested[id] then
			preloadRequested[id] = true
			table.insert(requested, id)
		end
	end
	if #requested == 0 then return end
	-- PreloadAsync yields; it must never delay input, remote handling, or camera work.
	task.spawn(function()
		local assets = {}
		for _, id in ipairs(requested) do
			local sound = Instance.new("Sound"); sound.SoundId = id; table.insert(assets,sound)
		end
		pcall(function() ContentProvider:PreloadAsync(assets) end)
		for _, sound in ipairs(assets) do sound:Destroy() end
	end)
end

local function prepare()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "RemoteWeaponAudio", workspace
	for _ = 1, Config.MaxVoices do
		local part = Instance.new("Part")
		part.Name, part.Size, part.Transparency = "WeaponSoundOrigin", Vector3.new(0.05, 0.05, 0.05), 1
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
		part.Parent = folder
		local socket = Instance.new("Attachment")
		socket.Parent = part -- point-source audio, independent of volumetric BasePart settings
		local sound = Instance.new("Sound")
		sound.Name, sound.Looped, sound.PlayOnRemove, sound.RollOffMode = "RemoteWeaponSound", false, false, rollOffMode
		sound.Parent = socket
		table.insert(voices, {part = part, sound = sound, started = -math.huge})
	end
	local ids = {RevolverConfig.Default.Effects.FireSoundId, KnifeConfig.Default.ThrowSoundId}
	for _, override in pairs(RevolverConfig.Overrides) do
		if override.Effects then table.insert(ids, override.Effects.FireSoundId or "") end
	end
	for _, override in pairs(KnifeConfig.Overrides) do table.insert(ids, override.ThrowSoundId or "") end
	local fallback = knifeFallback()
	if fallback then table.insert(ids, fallback.SoundId) end
	preload(ids)
end

local function play(position, id, settings, volume, pitch, soundGroup)
	if type(id) ~= "string" or id == "" or #voices == 0 then return end
	local camera = workspace.CurrentCamera
	if not camera or (position - camera.CFrame.Position).Magnitude > settings.MaxDistance then return end
	local chosen
	for _, voice in ipairs(voices) do
		if not voice.sound.IsPlaying then chosen = voice; break end
		if not chosen or voice.started < chosen.started then chosen = voice end
	end
	-- Steal only the oldest voice when the entire pool is busy; no instance churn.
	local sound = chosen.sound
	sound:Stop()
	chosen.part.CFrame = CFrame.new(position)
	sound.SoundId, sound.Volume, sound.PlaybackSpeed = id, volume * settings.VolumeScale, pitch
	sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.SoundGroup = settings.MinDistance, settings.MaxDistance, soundGroup
	sound.TimePosition, chosen.started = 0, os.clock()
	sound:Play()
	preload({id}) -- retries are unnecessary; asset permission failures cannot be fixed locally
end

local function revolverShot(data)
	if type(data) ~= "table" or not integerValid(data.ShooterId) or data.ShooterId == player.UserId
		or not nameValid(data.Weapon) or not positionValid(data.Origin) or not integerValid(data.Sequence)
		or data.Sequence < 0 or not nameValid(data.Session) then return end
	local key = string.format("Revolver:%d:%s:%d", data.ShooterId, data.Session, data.Sequence)
	if not remember(key) then return end
	local effects = revolverSettings[data.Weapon]
	if not effects then effects = RevolverConfig.Get(data.Weapon).Effects; revolverSettings[data.Weapon] = effects end
	play(data.Origin, effects.FireSoundId, Config.Revolver, effects.SoundVolume, effects.SoundPlaybackSpeed)
end

local function knifeThrow(data)
	if type(data) ~= "table" or data.visualOnly ~= true or not integerValid(data.shooterUserId)
		or data.shooterUserId == player.UserId or not nameValid(data.shotId) or not nameValid(data.knifeName)
		or not positionValid(data.origin) or not finite(data.charge) then return end
	local key = string.format("KnifeThrow:%d:%s", data.shooterUserId, data.shotId)
	if not remember(key) then return end
	local effects = knifeSettings[data.knifeName]
	if not effects then effects = KnifeConfig.Get(data.knifeName); knifeSettings[data.knifeName] = effects end
	local fallback = effects.ThrowSoundId == "" and knifeFallback() or nil
	local id = fallback and fallback.SoundId or effects.ThrowSoundId
	local pitch = effects.ThrowPitchMin + (effects.ThrowPitchMax - effects.ThrowPitchMin) * math.clamp(data.charge, 0, 1)
	play(data.origin, id, Config.KnifeThrow, effects.SoundVolume, pitch, fallback and fallback.SoundGroup)
end

function Audio.Init()
	if initialized then return end
	initialized, generation = true, generation + 1
	local ticket = generation
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shot = remotes:WaitForChild("Revolver"):WaitForChild("Shot")
	local threw = remotes:WaitForChild("Knife"):WaitForChild("ThrewClient")
	if not initialized or generation ~= ticket then return end
	prepare()
	table.insert(connections, shot.OnClientEvent:Connect(revolverShot))
	table.insert(connections, threw.OnClientEvent:Connect(knifeThrow))
end

function Audio.Destroy()
	initialized, generation = false, generation + 1
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	if folder then folder:Destroy(); folder = nil end
	table.clear(voices)
	table.clear(recent); table.clear(recentOrder); recentIndex = 0
	table.clear(revolverSettings); table.clear(knifeSettings); table.clear(preloadRequested)
end

return Audio
