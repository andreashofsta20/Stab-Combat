local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")
local ClearVotesRemote = VotingRemotesFolder:WaitForChild("ClearUIVotes")
local VoteUpdateRemote = VotingRemotesFolder:WaitForChild("VoteUpdate")
local ReceiveVoteRemote = VotingRemotesFolder:WaitForChild("RecieveVote")

local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local VotingTemplatesFolder = UITemplates:WaitForChild("VotingTemplates")
local MapVoteTemplate = VotingTemplatesFolder:WaitForChild("MapVoteTemplate")

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Lighting = game:GetService("Lighting")

local Workspace = game:GetService("Workspace")
local IntermissionMap = Workspace:WaitForChild("IntermissionMap")
local Voting = IntermissionMap:WaitForChild("Voting")

local NrOne = Voting:WaitForChild("1")
local NrOneTouch = Voting:WaitForChild("1_Selection")

local NrTwo = Voting:WaitForChild("2")
local NrTwoTouch = Voting:WaitForChild("2_Selection")

local NrThree = Voting:WaitForChild("3")
local NrThreeTouch = Voting:WaitForChild("3_Selection")

local voteUpdateConnection = nil
local clearVotesConnection = nil
local touchConnections = {}

StartVotingRemote.OnClientEvent:Connect(function(data : SharedTable, VotingTime : number)
    

    if voteUpdateConnection then
        voteUpdateConnection:Disconnect()
    end
    if clearVotesConnection then
        clearVotesConnection:Disconnect()
    end
    for _, conn in pairs(touchConnections) do
        conn:Disconnect()
    end
    touchConnections = {}
    
    local selectionParts = {}
    local voteContainers = {}
    local votingActive = true
    local debounce = false
    
    for mapIndex, mapData in pairs(data) do
        local VoteWorkspace = Workspace:WaitForChild("IntermissionMap"):WaitForChild("Voting"):FindFirstChild(tostring(mapIndex))
        local Container = VoteWorkspace:WaitForChild("Container"):WaitForChild("VotePanel"..mapIndex):WaitForChild("Container")
        Container.MapImage.MapName.MapName.Text = string.format("%s - %s", mapData["Name"], mapData["ModeName"] or "FFA")
        Container.MapImage.GamemodeName.GamemodeName.Text = mapData["ModeName"] or "FFA"
        Container.MapImage.Image = mapData["VotingImage"]
        Container.MapImage.Votes.VoteAmount.Text = "0 votes"
        voteContainers[mapData["Id"]] = Container

        local selectionPart = Workspace:WaitForChild("IntermissionMap"):WaitForChild("Voting"):FindFirstChild(tostring(mapIndex) .. "_Selection")
        if selectionPart and selectionPart:FindFirstChild("Touch") then
            selectionParts[mapIndex] = selectionPart
            local conn = selectionPart.Touch.Touched:Connect(function(hit)
                if not votingActive then return end
                if debounce then return end
                
                local character = hit.Parent
                local plr = Players:GetPlayerFromCharacter(character)
                if plr and plr == Player then
                    debounce = true
                    
                    for idx, part in pairs(selectionParts) do
                        for _, decal in pairs(part:GetDescendants()) do
                            if decal:IsA("Decal") then
                                decal.Color3 = Color3.fromRGB(205, 205, 205)
                            end
                        end
                    end
                    for _, decal in pairs(selectionPart:GetDescendants()) do
                        if decal:IsA("Decal") then
                            decal.Color3 = Color3.fromRGB(0, 152, 255)
                        end
                    end
                    
                    ReceiveVoteRemote:FireServer(mapData["Id"])
                    
                    task.delay(0.3, function()
                        debounce = false
                    end)
                end
            end)
            table.insert(touchConnections, conn)
        end
    end


    voteUpdateConnection = VoteUpdateRemote.OnClientEvent:Connect(function(voteCounts)
        for mapName, count in pairs(voteCounts) do
            if voteContainers[mapName] then
                voteContainers[mapName].MapImage.Votes.VoteAmount.Text = tostring(count) .. " votes"
            end
        end
    end)

    clearVotesConnection = ClearVotesRemote.OnClientEvent:Connect(function()
        votingActive = false
        for idx, part in pairs(selectionParts) do
            for _, decal in pairs(part:GetDescendants()) do
                if decal:IsA("Decal") then
                    decal.Color3 = Color3.fromRGB(205, 205, 205)
                end
            end
        end
    end)
end)


return {}