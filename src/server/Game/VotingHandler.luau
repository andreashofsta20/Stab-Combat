local Voting = {}

local RoundHandlerModule = require(game:GetService("ServerScriptService").Game.RoundHandler)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")
local ReceiveVoteRemote = VotingRemotesFolder:WaitForChild("RecieveVote")
local ClearUIRemote = VotingRemotesFolder:WaitForChild("ClearUIVotes")
local VoteUpdateRemote = VotingRemotesFolder:FindFirstChild("VoteUpdate")


local Maps = RoundHandlerModule.GetMaps()

local NotificationHandler = require(script.Parent:WaitForChild("SendNotification"))
local VIPService = require(script.Parent.Parent:WaitForChild("ServicesHandler"):WaitForChild("VIPService"))


Voting.Votes = {}
Voting.Options = {}
Voting.Debounce = {}  -- Server-side debounce per player

for mapName, mapData in pairs(Maps) do
    Voting.Options[mapName] = {
        Map = mapData,
        Votecount = 0
    }
end


function Voting.CountVotes()
    local count = 0
    for _ in pairs(Voting.Options) do
        count += 1
    end
    return count
end


ReceiveVoteRemote.OnServerEvent:Connect(function(player : Player, mapname : string)
    if type(mapname) ~= "string" then return end
    -- Server-side debounce check
    if Voting.Debounce[player.UserId] then
        return
    end
    
    Voting.Debounce[player.UserId] = true
    
    Voting.SubmitVote(player, mapname)
    
    -- Reset debounce after 1 second
    task.delay(0.3, function()
        Voting.Debounce[player.UserId] = nil
    end)
end)


function Voting.SubmitVote(player : Player, option : string)
    local voteWeight = VIPService.HasVIPByUserId(player.UserId) and 2 or 1
    
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
    
    local leaderstats = player:FindFirstChild("leaderstats")
    local settings = leaderstats and leaderstats:FindFirstChild("Settings")
    local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
    if lobbyMode and lobbyMode.Value then
        print("Can't vote with lobby mode enabled")
        NotificationHandler.SendNotification(player, "Can't vote with lobby mode enabled", 3, "Error")
        return
    end
    
    -- Check if voting for same option (no change needed)
    if Voting.Votes[player.UserId] == option then
        return
    end
    
    -- Allow changing vote: remove previous vote
    local prevVote = Voting.Votes[player.UserId]
    if prevVote and Voting.Options[prevVote] then
		Voting.Options[prevVote].Votecount -= voteWeight
		if Voting.Options[prevVote].Votecount < 0 then
			Voting.Options[prevVote].Votecount = 0
		end
    end

    if Voting.Options[option] then
        Voting.Votes[player.UserId] = option
		Voting.Options[option].Votecount += voteWeight
        NotificationHandler.SendNotification(player, "You voted for: " .. tostring(option), 3, "Success")
    else
        warn("couldnt find " .. option)
    end

    -- Broadcast live vote counts to all clients
    local voteCounts = {}
    for mapName, mapData in pairs(Voting.Options) do
        voteCounts[mapName] = mapData.Votecount
    end
    VoteUpdateRemote:FireAllClients(voteCounts)
    
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
    Voting.Debounce = {}  -- Clear debounce on wipe
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