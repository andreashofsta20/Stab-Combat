-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")



-- // PLAYER // --
local Player = game.Players.LocalPlayer
local PlayerBackpack = Player:WaitForChild("Backpack")


-- // REMOTES // --
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")
local CharacterResetted = StartGameClientFolder:WaitForChild("PlayerResetted")

local RequestKnife = StartGameClientFolder:WaitForChild("RequestKnife")


-- // MAIN FUNCTIONS // --

RecieveTools.OnClientEvent:Connect(function()
	--print("ddada 1")
	task.wait(0.5)
	
	if not RequestKnife then
		print("couldnt find")
	end

	RequestKnife:FireServer()
	
end)


CharacterResetted.OnClientEvent:Connect(function()
--	print("ddada 2")
-- print("RESET")
	
	
	
	--task.wait(0.5)
	
	--RequestKnife:FireServer()
	
end)




WipeTools.OnClientEvent:Connect(function()
	local character = Player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end

	for _, child in ipairs(PlayerBackpack:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
end)

return {}
