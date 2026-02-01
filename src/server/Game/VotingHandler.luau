
local Voting = {}

local RoundHandlerModule = require(game:GetService("ServerScriptService").Game.RoundHandler)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")

local ReceiveVoteRemote = VotingRemotesFolder:WaitForChild("RecieveVote")

local ClearUIRemote = VotingRemotesFolder:WaitForChild("ClearUIVotes")

local Maps = RoundHandlerModule.GetMaps()

local NotificationHandler = require(script.Parent:WaitForChild("SendNotification"))



Voting.Votes = {}

Voting.Options = {}

for mapName, mapData in pairs(Maps) do
	Voting.Options[mapName] = {
		Map = mapData,
		Votecount = 0
	}
end







function Voting.CountVotes()
	return #Voting.Options
end

ReceiveVoteRemote.OnServerEvent:Connect(function(player : Player, mapname : string)
	print(player.Name)
	
	print(mapname)
	
	Voting.SubmitVote(player, mapname)
end)

function Voting.SubmitVote(player : Player, option : string)
	
	if not table.find(RoundHandlerModule.MapsAbleToVoteOn, option) then
		warn("VOTINGHANDLER. Error: Invalid vote option " .. tostring(option))
		NotificationHandler.SendNotification(player, "Invalid voting option: " .. tostring(option), 3, "Error")
		return
	end
	
	if not RoundHandlerModule.TimeToVote then
		print("cant vote right now")
		NotificationHandler.SendNotification(player, "Can't vote at the moment", 3, "Error")
		return
	end
	
	if player:FindFirstChild("leaderstats"):FindFirstChild("Settings"):FindFirstChild("LobbyMode").Value then
		print("Can't vote with lobby mode enabled")
		NotificationHandler.SendNotification(player, "Can't vote with lobby mode enabled", 3, "Error")
		return
	end
	
	print(player.Name)
	print(option)
	
	
	if Voting.Votes[player] then
		print("already voted")
		NotificationHandler.SendNotification(player, "You have already voted", 3, "Error")
		return
	end
	
	if Voting.Options[option] then
		print("Voted")
		Voting.Votes[player] = option
		Voting.Options[option].Votecount += 1
		NotificationHandler.SendNotification(player, "You voted for: " .. tostring(option), 3, "Success")
	else
		warn("couldnt find " .. option)
	end
	
	
	print(Voting.Options)
	
end






function Voting.CheckResults()
	local highest = 0
	local tiedMaps = {}

	for name, data in pairs(Voting.Options) do
		if data.Votecount > highest then
			highest = data.Votecount
			tiedMaps = {name} 
		elseif data.Votecount == highest then
			table.insert(tiedMaps, name)
		end
	end

	local winner
	

	if highest == 0 then
		RoundHandlerModule.ChangeStatus("No votes. Picking a random map")
		local Map = RoundHandlerModule.GetRandomMapFromVoting()
		print(Map)
		winner = Map
		print(winner)
	elseif #tiedMaps > 1 then
		winner = tiedMaps[math.random(1, #tiedMaps)]
		print("VotingHandler. Tied winner is : " .. winner)
		RoundHandlerModule.ChangeStatus("It's a tie. Picking a random map")
		task.wait(2)
	else
		winner = tiedMaps[1]
	end
	print("VotingHandler. Winner is : " .. tostring(winner))
	return winner
end




function Voting.WipeAll()
	for i , v in pairs(Voting.Options) do
		v.Votecount = 0
	end
	
	RoundHandlerModule.MapsAbleToVoteOn = {}
	Voting.Votes = {}
	
	
end

function Voting.StopVoting()
	
	
	
	ClearUIRemote:FireAllClients()
	
	
	RoundHandlerModule.TimeToVote = false
	
	task.wait(0.3)
	
	local result = Voting.CheckResults()
	
	task.wait(0.3)
	
	Voting.WipeAll()
	
	return result


end



return Voting
