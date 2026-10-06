local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DeathAudioConfig"))
local player = Players.LocalPlayer
local customSound
local characterConnections = {}

local function disableDefaultDeathSound(child)
	if child:IsA("Sound") and (child.Name == "Died" or child.Name == "Death") then
		child:Stop()
		child.Volume = 0
		child.Playing = false
	end
end

local function disconnectCharacter()
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
end

local function setupCharacter(character)
	disconnectCharacter()
	for _, child in ipairs(character:GetDescendants()) do disableDefaultDeathSound(child) end
	table.insert(characterConnections, character.DescendantAdded:Connect(disableDefaultDeathSound))

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	table.insert(characterConnections, humanoid.Died:Connect(function()
		if Config.Enabled and Config.SoundId ~= "" then
			if not customSound then
				customSound = Instance.new("Sound")
				customSound.Name = "CustomDeathSound"
				customSound.Parent = SoundService
			end
			customSound.SoundId = Config.SoundId
			customSound.Volume = Config.Volume
			customSound.PlaybackSpeed = Config.PlaybackSpeed
			customSound:Play()
		end
	end))
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)
