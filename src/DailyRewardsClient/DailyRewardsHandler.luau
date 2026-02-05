-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = game.Players.LocalPlayer



-- Remotes
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:WaitForChild("DailyRewards")
local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")


-- GUI
local MainGui = game.StarterGui:WaitForChild("Main")
local FramesFolder = MainGui:WaitForChild("Frames")
local DailyRewardsFrame = FramesFolder:WaitForChild("DailyRewards")

-- Templates
local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local DailyRewardTemplate = UITemplates:WaitForChild("DailyRewardTemplates")
local DailyRewardKnifeTemplate = DailyRewardTemplate:WaitForChild("DailyRewardKnifeTemplate")
local DailyRewardEmoteTemplate = DailyRewardTemplate:WaitForChild("DailyRewardEmoteTemplate")
local DailyRewardCashTemplate = DailyRewardTemplate:WaitForChild("DailyRewardCashTemplate")
local DailyRewardXPTemplate = DailyRewardTemplate:WaitForChild("DailyRewardXPTemplate")



DailyRewardClientRemote.OnClientEvent:Connect(function(status)

    for _, child in pairs(DailyRewardsFrame.RewardsContainer:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    for dayIndex, rewardInfo in pairs(status.Rewards) do
        local rewardFrame

        if rewardInfo.Item then
            if rewardInfo.Item.Type == "Knife" then
                rewardFrame = DailyRewardKnifeTemplate:Clone()
                rewardFrame.ItemName.Text = rewardInfo.Item.Name
            elseif rewardInfo.Item.Type == "Emote" then
                rewardFrame = DailyRewardEmoteTemplate:Clone()
                rewardFrame.ItemName.Text = rewardInfo.Item.Name
            end
        elseif rewardInfo.Cash then
            rewardFrame = DailyRewardCashTemplate:Clone()
            rewardFrame.CashAmount.Text = tostring(rewardInfo.Cash)
        elseif rewardInfo.XP then
            rewardFrame = DailyRewardXPTemplate:Clone()
            rewardFrame.XPAmount.Text = tostring(rewardInfo.XP)
        end

        if rewardFrame then
            rewardFrame.DayLabel.Text = "Day " .. tostring(dayIndex)
            if dayIndex < status.CurrentDayIndex then
                rewardFrame.StatusLabel.Text = "Claimed"
                rewardFrame.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
            elseif dayIndex == status.CurrentDayIndex then
                if status.ClaimedToday then
                    rewardFrame.StatusLabel.Text = "Claimed"
                    rewardFrame.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
                else
                    rewardFrame.StatusLabel.Text = "Available"
                    rewardFrame.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
                end
            else
                rewardFrame.StatusLabel.Text = "Locked"
                rewardFrame.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
            end

            rewardFrame.Parent = DailyRewardsFrame.RewardsContainer
        end
    end

    DailyRewardsFrame.Visible = true
end)