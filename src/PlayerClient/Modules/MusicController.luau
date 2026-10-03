local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Config = require(RS.Modules.MusicConfig)
local player = Players.LocalPlayer
local GameActive = RS:WaitForChild("GameActive")
local Settings = player:WaitForChild("leaderstats"):WaitForChild("Settings")
local Controller = {}
local initialized = false
local tracks = {}

local function setPlaying(entry, shouldPlay)
	if entry.wanted == shouldPlay then return end
	entry.wanted = shouldPlay
	-- Cancelled tween completions must not stop a track that has restarted.
	entry.generation += 1
	local generation = entry.generation
	if entry.tween then entry.tween:Cancel() end
	if shouldPlay and not entry.sound.IsPlaying then
		entry.sound.Volume = 0
		entry.sound:Play()
	end
	local tween = TweenService:Create(entry.sound,
		TweenInfo.new(Config.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{Volume = shouldPlay and entry.volume or 0})
	entry.tween = tween
	local connection
	connection = tween.Completed:Connect(function(state)
		connection:Disconnect()
		if entry.generation == generation and state == Enum.PlaybackState.Completed and not entry.wanted then
			entry.sound:Stop()
		end
	end)
	tween:Play()
end

local function update()
	local setting = Settings:FindFirstChild("Music")
	local enabled = not setting or setting.Value == true
	if tracks.Lobby then setPlaying(tracks.Lobby, enabled and not GameActive.Value and player:GetAttribute("InRound") ~= true) end
	if tracks.Round then setPlaying(tracks.Round, enabled and GameActive.Value == true) end
end

local function createTrack(kind, settings, template)
	if settings.SoundId == "" and not template then return end
	local audio = settings.SoundId == "" and template:Clone() or Instance.new("Sound")
	audio.Name = kind .. "Music"
	if settings.SoundId ~= "" then audio.SoundId = settings.SoundId end
	audio.Volume, audio.Looped, audio.PlaybackSpeed = 0, settings.Looped, settings.PlaybackSpeed
	audio:SetAttribute("IsMusic", true)
	audio.Parent = SoundService -- global 2D audio, independent of camera/player distance
	tracks[kind] = {sound = audio, volume = settings.Volume, generation = 0}
	update()
end

function Controller.Init()
	if initialized then return end
	initialized = true
	local setting = Settings:FindFirstChild("Music")
	if setting then setting:GetPropertyChangedSignal("Value"):Connect(update) end
	Settings.ChildAdded:Connect(function(item)
		if item.Name == "Music" then item:GetPropertyChangedSignal("Value"):Connect(update); update() end
	end)
	GameActive.Changed:Connect(update)
	player:GetAttributeChangedSignal("InRound"):Connect(update)
	createTrack("Round", Config.Round)
	task.spawn(function()
		local template
		if Config.Lobby.SoundId == "" then
			template = RS:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("LobbyMusic", 10)
		end
		if template and not template:IsA("Sound") then template = nil end
		createTrack("Lobby", Config.Lobby, template)
	end)
end

return Controller
