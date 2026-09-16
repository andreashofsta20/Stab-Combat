local ServerStorage = game:GetService("ServerStorage")
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RequestKnife = StartGameClientFolder:WaitForChild("RequestKnife")
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







	
	
	task.spawn(function()
		
		task.wait(3)
		if player and player.Parent then
			local settings = player:FindFirstChild("leaderstats")
				and player.leaderstats:FindFirstChild("Settings")
			local lobbyMode = settings and settings:FindFirstChild("LobbyMode")

			local roundStats = MainGameModule.RoundStats
			if not MainGameModule.GameActive or not roundStats then
				return
			end

			if lobbyMode and lobbyMode.Value then
				return
			end

			-- Round membership is frozen when RoundStats is initialized. Do not
			-- allow late joins or eliminated players to re-enter.
			if not roundStats.players[player.UserId]
				or not MainGameModule.PlayersInGame[player.UserId] then
				return
			end
		end
	end)
	
	
end)


game:GetService("Players").PlayerRemoving:Connect(function(player)
	requestKnifeCooldowns[player.UserId] = nil
end)

return {}