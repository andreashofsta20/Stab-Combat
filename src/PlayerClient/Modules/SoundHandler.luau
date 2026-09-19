local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer


local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local SoundsFolder = AssetsFolder:WaitForChild("Sounds")
local PlayerGotKilledRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("PlayerGotKilledRemote")
local GameActive = ReplicatedStorage:WaitForChild("GameActive")
local SettingsFolder = player:WaitForChild("leaderstats"):WaitForChild("Settings")

local SoundHandler = {}
local musicVolumes = {}
local lobbyMusic
local lobbyMusicTween
local MUSIC_FADE_TIME = 0.6

SoundHandler.Sounds = {
	
	["HoverTopButtons"] = SoundsFolder:WaitForChild("Hover"),
	["ClickTopButtons"] = SoundsFolder:WaitForChild("Click"),
	["EquipKnife"] = SoundsFolder:WaitForChild("EquipKnife"),
	["StabKnife"] = SoundsFolder:WaitForChild("Stab"),
	["ThrowKnife"] = SoundsFolder:WaitForChild("ThrowKnife"),
	["Kill"] = SoundsFolder:WaitForChild("EliminatedPlayer"),
	["NormalTick"] = SoundsFolder:WaitForChild("NormalTick"),
	["3sec"] = SoundsFolder:WaitForChild("sec3"),
	["2sec"] = SoundsFolder:WaitForChild("sec2"),
	["1sec"] = SoundsFolder:WaitForChild("sec1"),
	["Fight"] = SoundsFolder:WaitForChild("FightSound"),	
	["CaseOpen"] = SoundsFolder:WaitForChild("SpinSoundAnimation"),
	
	
	
}

local function isMusicSound(sound: Sound)
	local soundGroup = sound.SoundGroup
	return sound:GetAttribute("IsMusic") == true
		or string.find(string.lower(sound.Name), "music", 1, true) ~= nil
		or (soundGroup and string.lower(soundGroup.Name) == "music")
end

local function applyMusicSetting(isEnabled: boolean)
	for sound, originalVolume in pairs(musicVolumes) do
		if sound.Parent then
			TweenService:Create(
				sound,
				TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Volume = isEnabled and originalVolume or 0 }
			):Play()
		else
			musicVolumes[sound] = nil
		end
	end

	for _, descendant in ipairs(SoundService:GetDescendants()) do
		if descendant:IsA("Sound") and isMusicSound(descendant) then
			if musicVolumes[descendant] == nil then
				musicVolumes[descendant] = descendant.Volume
			end
			TweenService:Create(
				descendant,
				TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Volume = isEnabled and musicVolumes[descendant] or 0 }
			):Play()
		end
	end
end

local function updateLobbyMusic()
	if not lobbyMusic then return end

	local musicSetting = SettingsFolder:FindFirstChild("Music")
	local musicEnabled = not musicSetting or musicSetting.Value == true
	local inLobby = not GameActive.Value and player:GetAttribute("InRound") ~= true

	if musicEnabled and inLobby then
		if lobbyMusicTween then lobbyMusicTween:Cancel() end
		if not lobbyMusic.IsPlaying then
			lobbyMusic.Volume = 0
			lobbyMusic:Play()
		end
		lobbyMusicTween = TweenService:Create(
			lobbyMusic,
			TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Volume = 0.35 }
		)
		lobbyMusicTween:Play()
	else
		if lobbyMusicTween then lobbyMusicTween:Cancel() end
		lobbyMusicTween = TweenService:Create(
			lobbyMusic,
			TweenInfo.new(MUSIC_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Volume = 0 }
		)
		local fade = lobbyMusicTween
		fade.Completed:Connect(function()
			if lobbyMusicTween == fade then
				lobbyMusic:Stop()
			end
		end)
		fade:Play()
	end
end




function SoundHandler.PlaySound(SoundName: string)
	local sound = SoundHandler.Sounds[SoundName]
	if sound then
		sound:Play()
	end
end

local function initializeLobbyMusic()
	local soundsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds", 10)
	local lobbyMusicTemplate = soundsFolder and soundsFolder:WaitForChild("LobbyMusic", 10)
	if not lobbyMusicTemplate or not lobbyMusicTemplate:IsA("Sound") then
		warn("SoundHandler: ReplicatedStorage.Assets.Sounds.LobbyMusic was not found")
		return
	end

	lobbyMusic = lobbyMusicTemplate:Clone()
	lobbyMusic.Name = "LobbyMusic"
	lobbyMusic.Volume = 0.35
	lobbyMusic.Looped = true
	lobbyMusic.Parent = SoundService
	applyMusicSetting(SettingsFolder:FindFirstChild("Music") == nil or SettingsFolder.Music.Value)
	updateLobbyMusic()
end

local musicSetting = SettingsFolder:FindFirstChild("Music")
if musicSetting then
	musicSetting:GetPropertyChangedSignal("Value"):Connect(function()
		applyMusicSetting(musicSetting.Value)
		updateLobbyMusic()
	end)
end
SoundService.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Sound") and isMusicSound(descendant) then
		applyMusicSetting(musicSetting == nil or musicSetting.Value)
	end
end)
GameActive.Changed:Connect(updateLobbyMusic)
player:GetAttributeChangedSignal("InRound"):Connect(updateLobbyMusic)
task.spawn(initializeLobbyMusic)


PlayerGotKilledRemote.OnClientEvent:Connect(function(soundname)
	if soundname == "Kill" then
		SoundHandler.PlaySound("Kill")
	end
end)


return SoundHandler