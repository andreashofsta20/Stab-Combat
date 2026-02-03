local ServerStorage = game:GetService("ServerStorage")
local KnivesFolder = ServerStorage:WaitForChild("Knives")
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RequestKnife = StartGameClientFolder:WaitForChild("RequestKnife")
local WipeToolsServer = StartGameClientFolder:WaitForChild("WipeToolServer")
local NotificationHandler = require(script.Parent:WaitForChild("SendNotification"))

local MainGameModule = require(script.Parent:WaitForChild("MainGame"))

RequestKnife.OnServerEvent:Connect(function(player)
	print("ddada")
	

	if not MainGameModule.GameActive then
		print("game is NOT active, cannot give tools")
		NotificationHandler.SendNotification(player, "Game is not active.", 3, "Error")
		return
	end
	
	if player:FindFirstChild("leaderstats"):FindFirstChild("Settings"):FindFirstChild("LobbyMode").Value then
		print("Lobby mode enabled")
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


	print("losadosa")

	
	if MainGameModule.PlayersInGame[player.UserId] then
		MainGameModule.PlayersInGame[player.UserId] = nil
	end


	NotificationHandler.SendNotification(player, "Wiped tools", 2, "Success")
end)

return {}