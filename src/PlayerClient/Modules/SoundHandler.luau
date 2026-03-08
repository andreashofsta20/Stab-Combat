local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer


local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local SoundsFolder = AssetsFolder:WaitForChild("Sounds")
local PlayerGotKilledRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("PlayerGotKilledRemote")

local SoundHandler = {}

SoundHandler.Sounds = {
	
	["HoverTopButtons"] = SoundsFolder:WaitForChild("Hover"),
	["ClickTopButtons"] = SoundsFolder:WaitForChild("Click"),
	["EquipKnife"] = SoundsFolder:WaitForChild("EquipKnife"),
	["StabKnife"] = SoundsFolder:WaitForChild("Stab"),
	["ThrowKnife"] = SoundsFolder:WaitForChild("ThrowKnife"),
	["Kill"] = SoundsFolder:WaitForChild("EliminatedPlayer"),
	
	
	
}




function SoundHandler.PlaySound(SoundName: string)
	local sound = SoundHandler.Sounds[SoundName]
	if sound then
		sound:Play()
	end
end


PlayerGotKilledRemote.OnClientEvent:Connect(function(soundname)
	if soundname == "Kill" then
		SoundHandler.PlaySound("Kill")
	end
end)


return SoundHandler