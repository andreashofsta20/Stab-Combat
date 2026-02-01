-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketPlaceService = game:GetService("MarketplaceService")

-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ProfileHandlerFolder = RemotesFolder:WaitForChild("ProfileHandler")
local RecieveProfileRequest = ProfileHandlerFolder:WaitForChild("RequestViewProfile")
local ViewProfileCliend = ProfileHandlerFolder:WaitForChild("ViewProfileClient")

-- // MODULES // --
local GetPlayerInfo = require(script:WaitForChild("GetPlayerInfo"))
local RoundHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHandler"))



-- // MODULES // --
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))



RecieveProfileRequest.OnServerEvent:Connect(function(player : Player, TargetID)
	if not TargetID then return end
	
	if not player then return end
	
	
	
	
	print(player.Name)
	print(TargetID)
	
	local info = GetPlayerInfo.AllInfo(TargetID)
	
	local Inventory = GetPlayerInfo.Inventory(TargetID)
	
	print(info)
	
	
	ViewProfileCliend:FireClient(player, info, Inventory)
	
	
	
	
end)

return {}
