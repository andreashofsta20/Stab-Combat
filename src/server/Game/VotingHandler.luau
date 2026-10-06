local Voting = {}

local RoundHandlerModule = require(game:GetService("ServerScriptService").Game.RoundHandler)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")
local ReceiveVoteRemote = VotingRemotesFolder:WaitForChild("RecieveVote")
local ClearUIRemote = VotingRemotesFolder:WaitForChild("ClearUIVotes")
local VoteUpdateRemote = VotingRemotesFolder:FindFirstChild("VoteUpdate")



local NotificationHandler = require(script.Parent:WaitForChild("SendNotification"))
local VIPService = require(script.Parent.Parent:WaitForChild("ServicesHandler"):WaitForChild("VIPService"))


Voting.Votes = {}
Voting.VoteWeights = {}
Voting.Options = {}
Voting.Debounce = {} -- Next allowed request time; no delayed task per request.
local REQUEST_INTERVAL = 0.3
local MAX_OPTION_LENGTH = 128

local function validOption(option)
    return type(option) == "string" and #option > 0 and #option <= MAX_OPTION_LENGTH
end

local function BroadcastVotes()
    if not VoteUpdateRemote then return end
    local voteCounts = {}
    for option, data in pairs(Voting.Options) do voteCounts[option] = data.Votecount end
    VoteUpdateRemote:FireAllClients(voteCounts)
end

local function RemoveVote(userId)
    local previous = Voting.Votes[userId]
    local data = previous and Voting.Options[previous]
    if data then
        data.Votecount = math.max(0, data.Votecount - (Voting.VoteWeights[userId] or 1))
    end
    Voting.Votes[userId], Voting.VoteWeights[userId] = nil, nil
    return data ~= nil
end

local function EnsureOptions()
    if next(Voting.Options) then return end
    for _, option in ipairs(RoundHandlerModule.VoteOptions) do
        Voting.Options[option.Id] = { Option = option, Votecount = 0 }
    end
end

function Voting.CountVotes()
    local count = 0
    for _ in pairs(Voting.Options) do
        count += 1
    end
    return count
end


ReceiveVoteRemote.OnServerEvent:Connect(function(player : Player, mapname : string)
    if not validOption(mapname) then return end
    local now = os.clock()
    if now < (Voting.Debounce[player.UserId] or 0) then return end
    Voting.Debounce[player.UserId] = now + REQUEST_INTERVAL
    Voting.SubmitVote(player, mapname)
end)


function Voting.SubmitVote(player : Player, option : string)
    if not validOption(option) or player.Parent ~= Players
        or player:GetAttribute("DataReady") ~= true then return end
    
    if not table.find(RoundHandlerModule.MapsAbleToVoteOn, option) then
        NotificationHandler.SendNotification(player, "Invalid voting option", 3, "Error")
        return
    end
    
    if not RoundHandlerModule.TimeToVote then
   
        NotificationHandler.SendNotification(player, "Can't vote at the moment", 3, "Error")
        return
    end
    
    local leaderstats = player:FindFirstChild("leaderstats")
    local settings = leaderstats and leaderstats:FindFirstChild("Settings")
    local lobbyMode = settings and settings:FindFirstChild("LobbyMode")
    if not lobbyMode or not lobbyMode:IsA("BoolValue") or lobbyMode.Value ~= false then

        NotificationHandler.SendNotification(player, "Can't vote with lobby mode enabled", 3, "Error")
        return
    end
    
    -- Check if voting for same option (no change needed)
    if Voting.Votes[player.UserId] == option then
        return
    end

    EnsureOptions()
    local voteWeight = VIPService.HasVIPByUserId(player.UserId) and 2 or 1
    -- Preserve the actual prior weight if VIP ownership changed during voting.
    RemoveVote(player.UserId)

    if Voting.Options[option] then
        Voting.Votes[player.UserId] = option
		Voting.VoteWeights[player.UserId] = voteWeight
		Voting.Options[option].Votecount += voteWeight
        NotificationHandler.SendNotification(player, "You voted for: " .. tostring(option), 3, "Success")
    else
        warn("couldnt find " .. option)
    end

    BroadcastVotes()
    
end


function Voting.CheckResults()
    EnsureOptions()
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
        RoundHandlerModule.ChangeStatus("NO VOTES. PICKING A RANDOM MAP")
        winner = RoundHandlerModule.GetRandomMapFromVoting()
        task.wait(1.5)
    elseif #tiedMaps > 1 then
        winner = tiedMaps[math.random(1, #tiedMaps)]
    --    print("VotingHandler. Tied winner is : " .. winner)
        RoundHandlerModule.ChangeStatus("IT'S A TIE. PICKING A RANDOM MAP")
        task.wait(1.5)
    else
        winner = tiedMaps[1]
    end
   -- print("VotingHandler. Winner is : " .. tostring(winner))
    return winner
end


function Voting.WipeAll()
    for i , v in pairs(Voting.Options) do
        v.Votecount = 0
    end
    
    RoundHandlerModule.MapsAbleToVoteOn = {}
    Voting.Options = {}
    Voting.Votes = {}
    Voting.VoteWeights = {}
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

function Voting.Begin(options)
    Voting.Options = {}
    Voting.Votes, Voting.VoteWeights, Voting.Debounce = {}, {}, {}
    for _, option in ipairs(options) do
        Voting.Options[option.Id] = { Option = option, Votecount = 0 }
    end
end

Players.PlayerRemoving:Connect(function(player)
    local removed = RemoveVote(player.UserId)
    Voting.Debounce[player.UserId] = nil
    if removed and RoundHandlerModule.TimeToVote then BroadcastVotes() end
end)


return Voting
