local MainGame = {}
local RoundHandlerModule = require(script.Parent.RoundHandler)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")

local TimeToMinutesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeToMinutes"))


-- Remotes to client

local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")
local WipeTools = StartGameClientFolder:WaitForChild("WipeTools")
MainGame.GameActive = false
MainGame.PlayersInGame = {}

local GameActiveBoolean = ReplicatedStorage:WaitForChild("GameActive")


local GameRewardModule = require(script.Parent:WaitForChild("GameReward"))
local SpawnMapModule = require(script.Parent:WaitForChild("SpawnMap"))

MainGame.TestMode = game:GetService("RunService"):IsStudio()



local Players = game:GetService("Players")


function MainGame.OnDeath(player: Player)
	print("1")
	if not player then return end
	print("2")

	local userId = player.UserId
	if MainGame.PlayersInGame[userId] then
		MainGame.PlayersInGame[userId] = nil


		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = workspace:WaitForChild("IntermissionMap"):WaitForChild("Map"):WaitForChild(tostring(math.random(1,6))).CFrame
			end
			
		end
		
		
		local leaderstatsDeaths = player:WaitForChild("leaderstats"):WaitForChild("Deaths")
		local leaderstatsWinStreak = player:WaitForChild("leaderstats"):FindFirstChild("WinStreak")

		if leaderstatsDeaths then
			leaderstatsDeaths.Value += 1
		end
		if leaderstatsWinStreak then
			leaderstatsWinStreak.Value = 0
		end
	else
		print("player isnt in Table PlayersInGame")
	end
	
	

end

local function HealAllPlayers()
	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end
end

local function CountPlayersInGame()
	local n = 0
	for _ in pairs(MainGame.PlayersInGame) do
		n += 1
	end
	return n
end

function MainGame.WipeTools()
	WipeTools:FireAllClients()
end


function MainGame.StartGame(map)


	MainGame.GameActive = true
	GameActiveBoolean.Value = true
	local RoundTime = 0.5 * 60
	local PlayerTotal = CountPlayersInGame()
	
	
	
	task.wait(0.5)
	RecieveTools:FireAllClients()
	
	task.wait(0.5)
	RoundHandlerModule.ChangeStatus("Loading Map")
	
	SpawnMapModule.Spawn(map)
	RoundHandlerModule.ChangeStatus("Map Loaded")
	
	task.wait(3)

	if CountPlayersInGame() == 0 then
		return
	end
		
	
	while RoundTime > 0 do
		task.wait(1)
		



		
		if not MainGame.TestMode then
			if CountPlayersInGame() < 2 then 
				local winnerUserId
				for userId in pairs(MainGame.PlayersInGame) do
					winnerUserId = userId
					break
				end

				local Winner = game.Players:GetPlayerByUserId(winnerUserId)
				if Winner then
					RoundHandlerModule.ChangeStatus(tostring(Winner.Name) .. " won")
					GameRewardModule.XpReward(Winner, "win", PlayerTotal)
					GameRewardModule.CashReward(Winner, "win", PlayerTotal)

					local leaderstatsWins = Winner:WaitForChild("leaderstats"):WaitForChild("Wins")
					local leaderstatsWinStreak = Winner:WaitForChild("leaderstats"):FindFirstChild("WinStreak")

					if leaderstatsWins then
						leaderstatsWins.Value += 1
					end
					if leaderstatsWinStreak then
						leaderstatsWinStreak.Value += 1
					end
				end
				task.wait(4)
				break
			end
		end
		
		if CountPlayersInGame() == 0 then
			break
		end
		
		RoundTime -= 1
		local RoundTimeClean = TimeToMinutesModule.MakeTimeMinute(RoundTime)
		RoundHandlerModule.ChangeStatus(RoundTimeClean)
	end
	
	RoundHandlerModule.ChangeStatus("Game ended")
	
	task.wait(2)
	for i , v in pairs(MainGame.PlayersInGame) do
		
		local player = Players:GetPlayerByUserId(i)
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and not player:FindFirstChild("leaderstats"):WaitForChild("Settings"):FindFirstChild("LobbyMode").Value then
				local spawnPoint = workspace:WaitForChild("IntermissionMap"):WaitForChild("Map"):WaitForChild(tostring(math.random(1,6)))
				hrp.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0) 
			end
		end
	end
	
	task.wait(0.5)
	HealAllPlayers()
	
	
	print(MainGame.PlayersInGame)
	MainGame.WipeTools()
	MainGame.GameActive = false
	GameActiveBoolean.Value = false
	table.clear(MainGame.PlayersInGame)
	
	
end













return MainGame

