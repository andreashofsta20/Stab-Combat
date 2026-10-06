local NotificationHandler = {}


-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Enabled = false



local NotificationImages = {
	
	["Skull"] = "rbxassetid://14959168083",
	
	["EclamationMark"] = "rbxassetid://14958420275",
	
	["Success"] = "rbxassetid://15082206415",
	
	["HighPing"] = "rbxassetid://14966959092",
	
	["LowPing"] = "rbxassetid://14957777673",
	
	["Error"] = "rbxassetid://14950812155",
	
	["QuestionMark"] = "rbxassetid://14958478605",
	
	["Settings"] = "rbxassetid://15081907270",
}





-- // REMOTE FOLDERS // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ClientRemotesFolder = RemotesFolder:WaitForChild("Client")
local NotificationClientRemotesFolder = ClientRemotesFolder:WaitForChild("NotificationClientRemotes")


-- // REMOTES // --
local SendNotificationRemote = NotificationClientRemotesFolder:WaitForChild("RecieveNotification")

local function notificationsEnabled(player : Player)
	if not player or player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return false end
	local leaderstats = player:FindFirstChild("leaderstats")
	local settings = leaderstats and leaderstats:FindFirstChild("Settings")
	local enabled = settings and settings:FindFirstChild("Notifications")
	return enabled ~= nil and enabled:IsA("BoolValue") and enabled.Value == true
end



function NotificationHandler.SendNotification(player : Player, message : string, duration : number, image : string)
	
	-- Notifications must never suspend a remote handler while profile data loads.
	if not Enabled or not notificationsEnabled(player) then return end
	
	
	if NotificationImages[image] then
		image = NotificationImages[image]
	else
		image = NotificationImages["QuestionMark"]
	end

	if Enabled then
		SendNotificationRemote:FireClient(player, message, duration, image)
	end
	
end


function NotificationHandler.SendNotificationServer(message : string, duration : number, image : string)
	if not Enabled then return end
	if NotificationImages[image] then
		image = NotificationImages[image]
	else
		image = NotificationImages["QuestionMark"]
	end

	if Enabled then
		SendNotificationRemote:FireAllClients(message, duration, image)
	end

end

return NotificationHandler
