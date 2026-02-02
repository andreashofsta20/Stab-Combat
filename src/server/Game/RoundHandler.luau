local RoundHandler = {}
local Players = game:GetService("Players")
local PlayerCount = Players:GetPlayers()
local MapsModule = require(game:GetService("ServerScriptService").Game.Maps)
local PlayerStatusSender = require(game:GetService("ServerScriptService").Game:WaitForChild("PlayerStatusSender"))
local RunService = game:GetService("RunService")



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")

local Testing = RunService:IsStudio()

RoundHandler.MinimumPlayers = 2

if Testing then
	RoundHandler.MinimumPlayers = 1
end




local VotingDuratation = 15
local VotingDuratationSTUDIO = 5

RoundHandler.CurrentMap = nil

RoundHandler.TimeToVote = false

RoundHandler.Status = ""

RoundHandler.StatusMessages = {
	Minimum = function()
		local activePlayers = 0
		for _, player in pairs(Players:GetPlayers()) do
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				local settings = leaderstats:FindFirstChild("Settings")
				if settings then
					local lobbyMode = settings:FindFirstChild("LobbyMode")
					if lobbyMode and lobbyMode.Value == false then
						activePlayers += 1
					end
				end
			end
		end

		local missing = RoundHandler.MinimumPlayers - activePlayers
		missing = math.max(missing, 0) 

		local suffix = missing == 1 and "PLAYER" or "PLAYERS"
		return "WAITING FOR " .. missing .. " " .. suffix .. " TO START THE MATCH"
	end,
	
	Voting = "TIME TO VOTE FOR A MAP!",
	Starting = "Game is starting shortly.",
	Ended = "Game Ended.",
	ERROR1 = "Minimum players not found",
	ERROR2 = "ERROR: Map not found",
	ERROR3 = "Unknown error",
}

RoundHandler.MapsAbleToVoteOn = {}

-- ERROR1 = Minimum players not found during starting a round
-- ERROR2 = Map not found
-- ERROR3 = Unknown error






function RoundHandler.ChangeStatus(var : string)
	local msg = RoundHandler.StatusMessages[var]
	if type(msg) == "function" then
		RoundHandler.Status = msg()
	else
		RoundHandler.Status = msg or var
	end
	
	PlayerStatusSender.EditClientStatus(RoundHandler.Status)
end



function RoundHandler.GetMaps()
	return MapsModule
end


function RoundHandler.StartVoting()
	RoundHandler.MapsAbleToVoteOn = {}
	local MapsToVoteOn = {}

	while #MapsToVoteOn < 3 do
		local RandomMap = RoundHandler.GetRandomMap()
		if not RandomMap then break end

		local alreadyChosen = false
		for _, chosen in ipairs(MapsToVoteOn) do
			if chosen["Name"] == RandomMap["Name"] then
				alreadyChosen = true
				break
			end
		end

		if not alreadyChosen then
			table.insert(MapsToVoteOn, RandomMap)
			table.insert(RoundHandler.MapsAbleToVoteOn, RandomMap["Name"])
		end
	end

	RoundHandler.ChangeStatus("Voting")

	local duration = RunService:IsStudio() and VotingDuratationSTUDIO or VotingDuratation
	StartVotingRemote:FireAllClients(MapsToVoteOn, duration)

	local countdown = duration
	while countdown > 0 do
		RoundHandler.ChangeStatus(string.format("TIME TO VOTE FOR A MAP! (%.1f)", countdown))
		task.wait(0.1)
		countdown -= 0.1
	end

	return
end



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

	return count >= RoundHandler.MinimumPlayers
end




function RoundHandler.GetRandomMap()
	local Maps = RoundHandler.GetMaps()
	local MapsList = {}
	for MapName, MapInfo in pairs(Maps) do
		if MapInfo["Name"] ~= "Intermission Map" then
			table.insert(MapsList, MapInfo)
		end
	end

	local RandomNumber = math.random(1, #MapsList)
	local SelectedMap = MapsList[RandomNumber]
	

	return SelectedMap
end

function RoundHandler.Intermission()
	while not CanStart() do
		RoundHandler.ChangeStatus("Minimum")
		task.wait(0.2)
	end
	
	-- Only proceed if we have enough players
	if not CanStart() then
		return false
	end
	
	task.wait(0.3)
	RoundHandler.ChangeStatus("Loading voting system")
	task.wait(1)
	RoundHandler.TimeToVote = true
	return true
end

function RoundHandler.GetRandomMapFromVoting()
	local RandomNumber = math.random(1, #RoundHandler.MapsAbleToVoteOn)
	local SelectedMap = RoundHandler.MapsAbleToVoteOn[RandomNumber]
	return SelectedMap
end



return RoundHandler

