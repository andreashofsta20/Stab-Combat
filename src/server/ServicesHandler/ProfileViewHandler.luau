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
local GetPlayerInfo = require(script.Parent:WaitForChild("GetPlayerInfo"))
local RoundHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("RoundHandler"))



-- // MODULES // --
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))



local profileCooldowns: {[number]: number} = {}
local PROFILE_VIEW_COOLDOWN = 1.0

RecieveProfileRequest.OnServerEvent:Connect(function(player : Player, TargetID)
	if not player then return end
	if typeof(TargetID) ~= "number" then return end
	TargetID = math.floor(TargetID)
	if TargetID <= 0 then return end

	local now = os.clock()
	if profileCooldowns[player.UserId] and (now - profileCooldowns[player.UserId]) < PROFILE_VIEW_COOLDOWN then return end
	profileCooldowns[player.UserId] = now
	
	local info = GetPlayerInfo.AllInfo(TargetID)
	
	local Inventory = GetPlayerInfo.Inventory(TargetID)
	
	ViewProfileCliend:FireClient(player, info, Inventory)
end)

Players.PlayerRemoving:Connect(function(player)
	profileCooldowns[player.UserId] = nil
end)

return {}
