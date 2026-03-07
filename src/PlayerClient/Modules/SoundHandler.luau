local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer


local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local SoundsFolder = AssetsFolder:WaitForChild("Sounds")

local SoundHandler = {}

SoundHandler.Sounds = {
	
	["HoverTopButtons"] = SoundsFolder:WaitForChild("Hover"),
	
	
}




function SoundHandler.PlaySound()
	
end

return SoundHandler