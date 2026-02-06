-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = game.Players.LocalPlayer

-- Modules
local RarityColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local KnivesInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))

-- Remotes
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:WaitForChild("DailyRewards")
local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")

-- GUI
local PlayerGui = Player:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGui:WaitForChild("Frames")
local DailyRewardsFrame = FramesFolder:WaitForChild("DailyRewards")
local DailyRewardsHolder = DailyRewardsFrame:WaitForChild("DailyRewardsHolder")
local RewardsContainer = DailyRewardsHolder:WaitForChild("RewardsContainer", 2)
    or DailyRewardsHolder:WaitForChild("Scroll", 2)
    or DailyRewardsHolder:FindFirstChildWhichIsA("ScrollingFrame")

-- Templates
local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local DailyRewardTemplate = UITemplates:WaitForChild("DailyRewardTemplates")
local DailyRewardKnifeTemplate = DailyRewardTemplate:WaitForChild("DailyRewardKnifeTemplate")
local DailyRewardEmoteTemplate = DailyRewardTemplate:WaitForChild("DailyRewardEmoteTemplate")
local DailyRewardCashTemplate = DailyRewardTemplate:FindFirstChild("DailyRewardCashTemplate")
    or DailyRewardTemplate:FindFirstChild("dailyRewardCashTemplate")
local DailyRewardXPTemplate = DailyRewardTemplate:WaitForChild("DailyRewardXPTemplate")

local function setText(label, value)
    if label then
        if value == nil then
            label.Text = ""
        else
            label.Text = tostring(value)
        end
    end
end

DailyRewardClientRemote.OnClientEvent:Connect(function(status)
    if not status or not status.Rewards then
        return
    end

    if not RewardsContainer then
        warn("DailyRewardsHandler: RewardsContainer not found")
        return
    end

    for _, child in pairs(RewardsContainer:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    for dayIndex, rewardInfo in ipairs(status.Rewards) do
        local rewardFrame

        if rewardInfo.Item then
            if rewardInfo.Item.Type == "Knife" then
                rewardFrame = DailyRewardKnifeTemplate:Clone()
                rewardFrame.LayoutOrder = dayIndex

                local ClaimFrame = rewardFrame.ClaimFrame
                if ClaimFrame then
                    local ClaimButton = ClaimFrame:FindFirstChild("ClaimButton")
                    if ClaimButton then
                        ClaimButton.MouseButton1Click:Connect(function()
                            ClaimDailyRewardRemote:FireServer("Claim", dayIndex)
                        end)
                    end
                    local dayText = ClaimFrame:FindFirstChild("DayText")
                    if dayText then
                        dayText.Text = "Day " .. tostring(dayIndex)
                    end
                end

                local KnifeInfo = rewardFrame:FindFirstChild("KnifeInventoryTemplate")
                if KnifeInfo then
                    local KnifeName = KnifeInfo:FindFirstChild("KnifeName")
                    local KnifeRarity = KnifeInfo:FindFirstChild("KnifeRarity")
                    local RarityImage = KnifeInfo:FindFirstChild("Rarity")
                    local KnifeImage = KnifeInfo:FindFirstChild("KnifeImage")
                    local knifeData = KnivesInfo[rewardInfo.Item.Name]
                    local rarityName = rewardInfo.Item.Rarity or (knifeData and knifeData.Rarity)

                    setText(KnifeName, rewardInfo.Item.Name)
                    setText(KnifeRarity, rarityName)
                    if RarityImage then
                        local rarityConfig = rarityName and RarityColor[rarityName]
                        if rarityConfig and rarityConfig.Image then
                            RarityImage.Image = rarityConfig.Image
                        end
                    end
                    if KnifeImage and knifeData and knifeData.Image then
                        KnifeImage.Image = knifeData.Image
                    end
                end
                setText(rewardFrame.KnifeInventoryTemplate:FindFirstChild("KnifeName"), rewardInfo.Item.Name)
            elseif rewardInfo.Item.Type == "Emote" then
                rewardFrame = DailyRewardEmoteTemplate:Clone()
                setText(rewardFrame:FindFirstChild("ItemName"), rewardInfo.Item.Name)
            end
        elseif rewardInfo.Cash then
            if DailyRewardCashTemplate then
                rewardFrame = DailyRewardCashTemplate:Clone()
                setText(rewardFrame:FindFirstChild("CashAmount"), rewardInfo.Cash)
            end
        elseif rewardInfo.XP then
            rewardFrame = DailyRewardXPTemplate:Clone()
            setText(rewardFrame:FindFirstChild("XPAmount"), rewardInfo.XP)
        end

        if rewardFrame then
            rewardFrame.LayoutOrder = dayIndex
            setText(rewardFrame:FindFirstChild("DayText"), "Day " .. tostring(dayIndex))
            if dayIndex < status.CurrentDayIndex then
                setText(rewardFrame:FindFirstChild("StatusLabel"), "Claimed")
            elseif dayIndex == status.CurrentDayIndex then
                if status.ClaimedToday then
                    setText(rewardFrame:FindFirstChild("StatusLabel"), "Claimed")
                else
                    setText(rewardFrame:FindFirstChild("StatusLabel"), "Available")
                end
            else
                setText(rewardFrame:FindFirstChild("StatusLabel"), "Locked")
            end

            rewardFrame.Parent = RewardsContainer
        end
    end

    DailyRewardsFrame.Visible = true
end)


return {}