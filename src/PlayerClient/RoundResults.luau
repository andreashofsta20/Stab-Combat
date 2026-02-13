local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local RoundResultsFolder = RemotesFolder:WaitForChild("RoundResults")
local GetRoundResultsRemote = RoundResultsFolder:WaitForChild("GetRoundResults")

local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local GetThumbnail = require(ModulesFolder:WaitForChild("GetThumbnail"))
local Abbreviate = require(ModulesFolder:WaitForChild("Abbreviate"))


local UI = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Main")
local FramesFolder = UI:WaitForChild("Frames")
local RoundResultsFrame = FramesFolder:WaitForChild("RoundResults")

local function setText(label, value)
    if label then
        if value == nil then
            label.Text = ""
        else
            label.Text = tostring(value)
        end
    end
end

local function applyResults(gameResults, playerResults)
    if not RoundResultsFrame then
        return
    end

    local container = RoundResultsFrame:FindFirstChild("Container")

    local function WinnerFrame()
        local winnerFrame = container and container:FindFirstChild("WinnerFrame")
        if not winnerFrame then
            return
        end

        local winnerProfileImage = winnerFrame:FindFirstChild("ProfileFrame") and winnerFrame.ProfileFrame:FindFirstChild("ProfileImage")
        local winnerUsername = winnerFrame:FindFirstChild("Username")
        local mapImg = winnerFrame:FindFirstChild("MapImage")

        if gameResults and type(gameResults.Winners) == "table" and #gameResults.Winners > 0 then
            local winner = gameResults.Winners[1]
            if winner.UserId then
                local player = Players:GetPlayerByUserId(winner.UserId)
                if player and winnerProfileImage then
                    winnerProfileImage.Image = GetThumbnail.GetThumbnail(winner.UserId) or ""
                    setText(winnerUsername, player.Name)
                else
                    if winnerProfileImage then
                        winnerProfileImage.Image = ""
                    end
                    setText(winnerUsername, "Unknown Player")
                end
            else
                if winnerProfileImage then
                    winnerProfileImage.Image = ""
                end
                setText(winnerUsername, winner.Name or "Unknown Player")
            end

            if mapImg then
                mapImg.Image = gameResults.MapImage or "rbxassetid://75611721868704"
            end
        else
            if winnerProfileImage then
                winnerProfileImage.Image = ""
            end
            setText(winnerUsername, "No Winner")
            if mapImg then
                mapImg.Image = "rbxassetid://75611721868704"
            end
        end
    end

    local function YourStats()
        local yourStatsFrame = container and container:FindFirstChild("YourStatsFrame")
        local holder = yourStatsFrame and yourStatsFrame:FindFirstChild("Holder")
        if not holder then
            return
        end

        local goldFromRound = holder:FindFirstChild("Gold") and holder.Gold:FindFirstChild("StatProgress")
        local killsFromRound = holder:FindFirstChild("Kills") and holder.Kills:FindFirstChild("StatProgress")
        local placementFromRound = holder:FindFirstChild("Placement") and holder.Placement:FindFirstChild("StatProgress")
        local xpFromRound = holder:FindFirstChild("XP") and holder.XP:FindFirstChild("StatProgress")

        local localPlayer = Players.LocalPlayer
        local localPlayerResult = nil
        if type(playerResults) == "table" then
            for _, result in ipairs(playerResults) do
                if result.UserId == localPlayer.UserId then
                    localPlayerResult = result
                    break
                end
            end
        end

        local kills = localPlayerResult and localPlayerResult.Kills or localPlayer:GetAttribute("LastRoundKills")
        local placement = localPlayerResult and localPlayerResult.Placement or localPlayer:GetAttribute("LastRoundPlacement")
        local gold = localPlayer:GetAttribute("LastRoundGold")
        local xp = localPlayer:GetAttribute("LastRoundXP")

        setText(killsFromRound, kills or 0)
        if placement == nil then
            setText(placementFromRound, "")
        else
            setText(placementFromRound, "#" .. tostring(placement))
        end

        if type(gold) == "number" then
            setText(goldFromRound, "+" .. Abbreviate.WithCommas(gold))
        else
            setText(goldFromRound, gold or "-")
        end

        if type(xp) == "number" then
            setText(xpFromRound, "+" .. Abbreviate.WithCommas(xp))
        else
            setText(xpFromRound, xp or "-")
        end
    end

    WinnerFrame()
    YourStats()
end

GetRoundResultsRemote.OnClientEvent:Connect(function(gameResults, playerResults)
    applyResults(gameResults, playerResults)
    RoundResultsFrame.Visible = true
end)






RoundResultsFrame.Close.MouseButton1Click:Connect(function()
	RoundResultsFrame.Visible = false
end)



return {}