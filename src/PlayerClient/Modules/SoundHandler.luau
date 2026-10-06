local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer


local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local SoundsFolder = AssetsFolder:WaitForChild("Sounds")
local PlayerGotKilledRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("PlayerGotKilledRemote")

local SoundHandler = {}
local clickConnections = setmetatable({}, {__mode = "k"})

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

function SoundHandler.PlaySound(SoundName: string)
	local sound = SoundHandler.Sounds[SoundName]
	if sound then
		sound:Play()
	end
end

function SoundHandler.BindClickSounds(root: Instance)
	local function bind(instance)
		if not instance:IsA("GuiButton") or clickConnections[instance] then return end
		local topButtons = instance:FindFirstAncestor("Buttons")
		if topButtons and topButtons.Parent and topButtons.Parent.Name == "Top" then return end
		clickConnections[instance] = instance.Activated:Connect(function()
			SoundHandler.PlaySound("ClickTopButtons")
		end)
	end

	for _, descendant in ipairs(root:GetDescendants()) do bind(descendant) end
	root.DescendantAdded:Connect(bind)
end

require(script.Parent.MusicController).Init()

PlayerGotKilledRemote.OnClientEvent:Connect(function(soundname)
	if soundname == "Kill" then
		SoundHandler.PlaySound("Kill")
	end
end)


return SoundHandler