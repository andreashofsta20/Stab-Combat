

local Players = game:GetService("Players")
local PlayerCount = Players:GetPlayers()


local SpawnMapModule = require(script.Parent.SpawnMap)
local RoundHandlerModule = require(script.Parent.RoundHandler)
local VotingHandlerModule = require(script.Parent.VotingHandler)
local StartServer = require(script.Parent.StartServer)
local MainGameModule = require(script.Parent.MainGame)
local NotificationHandler = require(script.Parent.SendNotification)



local function CanStart()
	local count = 0
	for _, player in pairs(Players:GetPlayers()) do
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local settings = leaderstats:FindFirstChild("Settings")
			if settings then
				local lobbyMode = settings:FindFirstChild("LobbyMode")
				if lobbyMode and lobbyMode.Value == false then
					count += 1
				end
			end
		end
	end

	return count >= RoundHandlerModule.MinimumPlayers
end


RoundHandlerModule.ChangeStatus("WAITING FOR SERVER")
task.wait(2)

while true do
	
	while not RoundHandlerModule.Intermission() do
		task.wait(0.3)
	end
	
	-- Check again before starting voting
	if not CanStart() then
		continue
	end

	RoundHandlerModule.StartVoting()


	local map = VotingHandlerModule.StopVoting()
	task.wait(0.5)
	
	-- Check again after voting completes
	if not CanStart() then
		RoundHandlerModule.ChangeStatus("Not enough players to start")
		task.wait(3)
		continue
	end


	print(map)
	task.wait(0.5)
	RoundHandlerModule.ChangeStatus(map.. " Won")
	task.wait(3)



	SpawnMapModule.RemoveOtherMapsThen(map)
	RoundHandlerModule.ChangeStatus("")
	
	MainGameModule.StartGame(map)
	


--	RoundHandlerModule.ChangeStatus("Removing map")
	SpawnMapModule.RemoveAllMaps()




	--SpawnMapModule.RemoveAllMaps()
end


return {}
