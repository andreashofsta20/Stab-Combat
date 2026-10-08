

local Players = game:GetService("Players")


local SpawnMapModule = require(script.Parent.SpawnMap)
local RoundHandlerModule = require(script.Parent.RoundHandler)
local VotingHandlerModule = require(script.Parent.VotingHandler)
local StartServer = require(script.Parent.StartServer)
local MainGameModule = require(script.Parent.MainGame)



local function CanStart()
	local count = 0
	for _, player in pairs(Players:GetPlayers()) do
		if player:GetAttribute("DataReady") ~= true or player:GetAttribute("PracticeActive") == true then
			continue
		end
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

local started = false
local function runLoop()
	if started then
		return
	end
	started = true
	StartServer.AwaitReady()

	while true do
	
	while not RoundHandlerModule.Intermission() do
		task.wait(0.3)
	end
	
	-- Check again before starting voting
	if not CanStart() then
		continue
	end

	RoundHandlerModule.StartVoting()
	if #RoundHandlerModule.VoteOptions == 0 then
		RoundHandlerModule.TimeToVote = false
		VotingHandlerModule.WipeAll()
		RoundHandlerModule.ChangeStatus("NO MAPS AVAILABLE")
		task.wait(2)
		continue
	end


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



	RoundHandlerModule.ChangeStatus("")
	
	MainGameModule.StartGame(option.Map, option.Mode)
	


--	RoundHandlerModule.ChangeStatus("Removing map")
		SpawnMapModule.ShowLobbyMap()




		--SpawnMapModule.RemoveAllMaps()
	end
end

local function Start()
	task.spawn(runLoop)
end


return {
	Start = Start,
}
