-- Client LocalScript (inside the cloned AdminFolder GUI)

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local plr = Players.LocalPlayer
local plrDisplay = plr.DisplayName
local plrID = plr.UserId

-- Modules
local GetThumbnailModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))

-- GUI (ensure names match your UI objects)
local GUI = script.Parent.Parent:WaitForChild("Admin")
local AdminPanel = GUI:WaitForChild("AdminPanelFrame")
local TogglePanelFrame = GUI:WaitForChild("TooglePanelFrame") -- fixed spelling
local TogglePanelButton = TogglePanelFrame:WaitForChild("ToogleButton") -- fixed spelling

-- Main Frames
local FramesFolder = AdminPanel:WaitForChild("Menu")
local MainFrame = FramesFolder:WaitForChild("AdminOptions")
local BackButton = AdminPanel:WaitForChild("Back")

-- Change Value Frame
local ChangeValueFrame = FramesFolder:WaitForChild("EditValue")
local EditValueFrame = ChangeValueFrame:WaitForChild("Container"):WaitForChild("EditValueFrame")
local EditValueInput = EditValueFrame:WaitForChild("NewValueFrame"):WaitForChild("ValueTextBox")
local ConfirmChangeButton = EditValueFrame:WaitForChild("ApplyButton")

-- Game Tools Frame
local GameToolsFrame = FramesFolder:WaitForChild("GameTools")
local GameToolsContainer = GameToolsFrame:WaitForChild("GameToolsOptions")

-- Remotes
local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminRemote")

-- Send command to server: category, command, ...args
local function SendCommand(category, command, ...)
    print("CLIENT: Sending command:", category, command, ...)
    AdminRemote:FireServer(category, command, ...)
end

-- Debounce for panel toggle
local db = false
local function TogglePanel()
    if db then return end
    db = true
    task.delay(0.3, function() db = false end)

    local visible = not AdminPanel.Visible
    AdminPanel.Visible = visible
    TogglePanelFrame.Visible = not visible
end

TogglePanelButton.MouseButton1Click:Connect(function()
    if not TogglePanelButton.Visible then return end
    TogglePanel()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.M then
        TogglePanel()
    end
end)

AdminPanel.Close.MouseButton1Click:Connect(TogglePanel)

local function ToggleFrames(frameName: string)
    for _, v in pairs(FramesFolder:GetChildren()) do
        if v:IsA("Frame") then
            v.Visible = (v.Name == frameName)
        end
    end
    BackButton.Visible = frameName ~= "AdminOptions"
end

BackButton.MouseButton1Click:Connect(function()
    ToggleFrames("AdminOptions")
end)

for _, v in pairs(MainFrame:GetChildren()) do
    if v:IsA("ImageButton") or v:IsA("TextButton") then
        v.MouseButton1Click:Connect(function()
            ToggleFrames(v.Name)
        end)
    end
end

-- Player info
local function SetUpPlayerInfo(display, userId)
    local PlayerFrame = AdminPanel.Container:WaitForChild("PlayerFrame")
    local PlayerContainer = PlayerFrame:WaitForChild("ProfileContainer")
    local NameText = PlayerFrame:WaitForChild("Username")
    local RankText = PlayerFrame:WaitForChild("Rank")
    local AvatarImg = PlayerContainer:WaitForChild("ProfileImg")

    NameText.Text = "Welcome, " .. display .. "!"
    RankText.Text = (userId == 3353659057) and "Creator" or "Admin"
    AvatarImg.Image = GetThumbnailModule.GetThumbnail(userId)
end

SetUpPlayerInfo(plrDisplay, plrID)

-- Edit value flow
local CurrentValueToChange

local function ShowChangeValue()
    if ChangeValueFrame.Visible then return end
    ChangeValueFrame.Visible = true
end

ChangeValueFrame.Exit.MouseButton1Click:Connect(function()
    ChangeValueFrame.Visible = false
    EditValueInput.Text = ""
end)

ConfirmChangeButton.MouseButton1Click:Connect(function()
    print("1")
    local newValue = tonumber(EditValueInput.Text)
    print("2")
    if not newValue then
        warn("Invalid value:", EditValueInput.Text)
        return
    end

    print("current:" .. CurrentValueToChange)

    if CurrentValueToChange == "ChangeMinimumPlayerCount" then
        print("yes1")
        SendCommand("GameTools", "ChangeMinimumPlayerCount", newValue)
    elseif CurrentValueToChange == "ChangeIntermissionTime" then
        print("yes2")
        SendCommand("GameTools", "ChangeIntermissionTime", newValue)
    end

    ChangeValueFrame.Visible = false
    EditValueInput.Text = ""
end)

-- Game tools buttons
local function GameToolsHandler()
    for _, v in pairs(GameToolsContainer:GetChildren()) do
        if v:IsA("ImageButton") then
            v.MouseButton1Click:Connect(function()
                local TypeValue = v:WaitForChild("Type")
                if not TypeValue then
                    warn("Missing Type value on", v.Name)
                    return
                end
				if TypeValue.Value == "ChangeValue" then
					CurrentValueToChange = v.Name
					print(CurrentValueToChange)
                    ShowChangeValue()
                elseif TypeValue.Value == "Boolean" then
					-- Toggle actions like TestMode
					print("d")
                    SendCommand("GameTools", v.Name)
                else
                    warn("Unknown Type value on", v.Name)
                end
            end)
        end
    end
end

GameToolsHandler()