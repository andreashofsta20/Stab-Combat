

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


	local optionId = VotingHandlerModule.StopVoting()
	local option
	for _, candidate in ipairs(RoundHandlerModule.VoteOptions) do
		if candidate.Id == optionId then
			option = candidate
			break
		end
	end
	task.wait(0.5)
	
	-- Check again after voting completes
	if not CanStart() then
		RoundHandlerModule.ChangeStatus("NOT ENOUGH PLAYERS TO START")
		task.wait(3)
		continue
	end


	task.wait(0.5)
	if not option then
		RoundHandlerModule.ChangeStatus("ERROR: Invalid voting result")
		task.wait(2)
		continue
	end
	RoundHandlerModule.ChangeStatus(string.format("%s - %s Won", option.Map, option.ModeName))
	task.wait(2)



	SpawnMapModule.RemoveOtherMapsThen(option.Map)
	RoundHandlerModule.ChangeStatus("")
	
	MainGameModule.StartGame(option.Map, option.Mode)
	


--	RoundHandlerModule.ChangeStatus("Removing map")
	SpawnMapModule.RemoveAllMaps()




	--SpawnMapModule.RemoveAllMaps()
end


return {}
