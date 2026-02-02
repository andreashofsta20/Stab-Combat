-- SERVICES
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")



local plr = game.Players.LocalPlayer
local plrDisplay = game.Players.LocalPlayer.DisplayName
local plrName = plr.Name
local plrID = plr.UserId
local db = false

-- MODULES
local GetThumbnailModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))


local GUI = script.Parent:WaitForChild("Admin")

local AdminPanel = GUI:WaitForChild("AdminPanelFrame")
local TooglePanelFrame = GUI:WaitForChild("TooglePanelFrame")
local TooglePanelButton = TooglePanelFrame:WaitForChild("ToogleButton")




-- Main Frames
local FramesFolder = AdminPanel:WaitForChild("Menu")
local MainFrame = FramesFolder:WaitForChild("AdminOptions")
local BackButton = AdminPanel:WaitForChild("Back")






local function ToogleFrames(FrameName: string)

    for i , v in pairs(FramesFolder:GetChildren()) do
        if v:IsA("Frame") then
            if v.Name == FrameName then
                v.Visible = true
                if v.Name == "AdminOptions" then
                    BackButton.Visible = false
                else
                    BackButton.Visible = true
                end
            else
                v.Visible = false
            end
        end
    end
end


for i , v in pairs(MainFrame:GetChildren()) do
    if v:IsA("ImageButton") or v:IsA("TextButton") then
        v.MouseButton1Click:Connect(function()
            print("Button clicked:", v.Name)
            ToogleFrames(v.Name)
        end)
    end
end















local function SetUpPlayerInfo(plrDisplay, plrID)

    local PlayerFrame = AdminPanel.Container:WaitForChild("PlayerFrame")
    local PlayerContainer = PlayerFrame:WaitForChild("ProfileContainer")
    
    local NameText = PlayerFrame:WaitForChild("Username")
    local RankText = PlayerFrame:WaitForChild("Rank")
    local AvatarImg = PlayerContainer:WaitForChild("ProfileImg")


    NameText.Text = "Welcome, " .. plrDisplay .. "!"

    if plrID == 3353659057 then
        RankText.Text = "Creator"
    else
        RankText.Text = "Admin"
    end

    AvatarImg.Image = GetThumbnailModule.GetThumbnail(plrID)


    
end

local function TooglePanel()
    if db then return end
    db = true
    task.delay(0.3, function()
        db = false
    end)

    if AdminPanel.Visible == false then
        AdminPanel.Visible = true
        TooglePanelFrame.Visible = false
    else
        AdminPanel.Visible = false
        TooglePanelFrame.Visible = true
    end
end


TooglePanelButton.MouseButton1Click:Connect(function()
    if not TooglePanelButton.Visible then return end
    TooglePanel()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.M then
        TooglePanel()
    end
end)


AdminPanel.Close.MouseButton1Click:Connect(function()
    TooglePanel()
end)


BackButton.MouseButton1Click:Connect(function()
    ToogleFrames("AdminOptions")
end)


SetUpPlayerInfo(plrDisplay, plrID)