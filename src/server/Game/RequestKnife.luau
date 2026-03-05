local ServerStorage = game:GetService("ServerStorage")
local KnivesFolder = ServerStorage:WaitForChild("Knives")
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RequestKnife = StartGameClientFolder:WaitForChild("RequestKnife")
local WipeToolsServer = StartGameClientFolder:WaitForChild("WipeToolServer")
local NotificationHandler = require(script.Parent:WaitForChild("SendNotification"))

local requestKnifeCooldowns: {[number]: number} = {}
local REQUEST_KNIFE_COOLDOWN = 1.0

local MainGameModule = require(script.Parent:WaitForChild("MainGame"))

RequestKnife.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if requestKnifeCooldowns[player.UserId] and (now - requestKnifeCooldowns[player.UserId]) < REQUEST_KNIFE_COOLDOWN then return end
	requestKnifeCooldowns[player.UserId] = now
	

	if not MainGameModule.GameActive then
		NotificationHandler.SendNotification(player, "Game is not active.", 3, "Error")
		return
	end
	
	local leaderstats = player:FindFirstChild("leaderstats")
	local settings = leaderstats and leaderstats:FindFirstChild("Settings")
	local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
	if lobbyMode and lobbyMode.Value then
		return
	end




print("fafafasfscadad")



	
	
	task.spawn(function()
		
		task.wait(3)
		if player then
			local settings = player:FindFirstChild("leaderstats")
				and player.leaderstats:FindFirstChild("Settings")
			local lobbyMode = settings and settings:FindFirstChild("LobbyMode")

			if not MainGameModule.GameActive then
				return
			end

			if lobbyMode and lobbyMode.Value then
				return
			end

			print("afafasfasfasf")
			MainGameModule.PlayersInGame[player.UserId] = true
		end
	end)
	
	
end)


WipeToolsServer.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if requestKnifeCooldowns[player.UserId] and (now - requestKnifeCooldowns[player.UserId]) < REQUEST_KNIFE_COOLDOWN then return end
	requestKnifeCooldowns[player.UserId] = now

	if MainGameModule.PlayersInGame[player.UserId] then
		MainGameModule.PlayersInGame[player.UserId] = nil
	end


	NotificationHandler.SendNotification(player, "Wiped tools", 2, "Success")
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	requestKnifeCooldowns[player.UserId] = nil
end)

return {}