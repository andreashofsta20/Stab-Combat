
local LocalizationService = game:GetService("LocalizationService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Player info
local localPlayer = Players.LocalPlayer
local LOCAL_DISPLAY = localPlayer.DisplayName
local LOCAL_USERID = localPlayer.UserId

-- Colors
local BLUE = Color3.fromRGB(32, 133, 217)
local GREY = Color3.fromRGB(78, 90, 109)

-- Modules
local GetThumbnail = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))

-- GUI
local GUI = script.Parent.Parent
local AdminPanel = GUI:WaitForChild("AdminPanelFrame")
local TogglePanelFrame = GUI:WaitForChild("TooglePanelFrame")
local TogglePanelButton = TogglePanelFrame:WaitForChild("ToogleButton")

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

-- Player Management Frames
local PlayerManagementFrame = FramesFolder:WaitForChild("PlayerManagement")
local PlayerManagementOptions = PlayerManagementFrame:WaitForChild("PlayerManagementOptions")
local BanFrame = PlayerManagementFrame:WaitForChild("BanFrame")
local KickFrame = PlayerManagementFrame:WaitForChild("KickFrame")
local WipeInventoryFrame = PlayerManagementFrame:WaitForChild("WipeInventoryFrame")


-- Security Frames
local SecurityFrame = FramesFolder:WaitForChild("Security")
local SecurityOptionsFrame = SecurityFrame:WaitForChild("SecurityOptions")
local AdminLogsFrame = SecurityFrame:WaitForChild("AdminLogs")
local AdminLogsContainer = AdminLogsFrame:WaitForChild("LogsHolder"):WaitForChild("ScrollingFrameAdminLogs")
local AdminLogTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("AdminPanelTemplates"):WaitForChild("AdminLogTemplate")

-- Remotes
local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminRemote")
local AdminClientRecieve = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminClientRecieve")
-- State
local currentValueToChange = nil
local debounce = false



local function AdminLog()
    
end



-- Utilities
local function sendCommand(category, command, ...)
    AdminRemote:FireServer(category, command, ...)
end

local function togglePanel()
    if debounce then return end
    debounce = true
    task.delay(0.3, function() debounce = false end)

    local visible = not AdminPanel.Visible
    AdminPanel.Visible = visible
    TogglePanelFrame.Visible = not visible
end

local function toggleFrames(frameName: string)
    if BanFrame.Visible or KickFrame.Visible or WipeInventoryFrame.Visible then
        BanFrame.Visible = false
        KickFrame.Visible = false
        WipeInventoryFrame.Visible = false
        PlayerManagementOptions.Visible = true
        PlayerManagementFrame.Visible = true
        return
    end

    if AdminLogsFrame.Visible then
        AdminLogsFrame.Visible = false
        SecurityFrame.Visible = true
        SecurityOptionsFrame.Visible = true
        return
    end



    MainFrame.Visible = (frameName == "AdminOptions")
    for _, child in pairs(FramesFolder:GetChildren()) do
        if child:IsA("GuiObject") and child ~= MainFrame then
            child.Visible = (child.Name == frameName)
        end
    end
    BackButton.Visible = frameName ~= "AdminOptions"
end

local function setupPlayerInfo(display, userId)
    local PlayerFrame = AdminPanel.Container:WaitForChild("PlayerFrame")
    local PlayerContainer = PlayerFrame:WaitForChild("ProfileContainer")
    local NameText = PlayerFrame:WaitForChild("Username")
    local RankText = PlayerFrame:WaitForChild("Rank")
    local AvatarImg = PlayerContainer:WaitForChild("ProfileImg")

    NameText.Text = "Welcome, " .. display .. "!"
    RankText.Text = (userId == 3353659057) and "Creator" or "Admin"
    if userId == 9304217232 then
        RankText.Text = "Friend / Admin"
    end
    AvatarImg.Image = GetThumbnail.GetThumbnail(userId)
end

local function showChangeValue()
    if ChangeValueFrame.Visible then return end
    ChangeValueFrame.Visible = true
    ChangeValueFrame.Active = true
end

-- Generic player list builder for Ban/Kick/Wipe
local function buildPlayerListHandler(config)
    -- config: {
    --   frame: Frame,
    --   listFrameName: string,
    --   panelName: string,
    --   confirmButtonName: string,
    --   reasonInputPath: { ... } or nil,
    --   lengthInputPath: { ... } or nil,
    --   onConfirm = function(selectedUserId, reason, length)
    -- }
    local parentFrame = config.frame
    local Panel = parentFrame:WaitForChild(config.panelName)
    local PlayerListFrame = parentFrame:WaitForChild(config.listFrameName)
    local PlayerListContainer = PlayerListFrame:WaitForChild("PlayerList")
    local PlayerTemplate = ReplicatedStorage:WaitForChild("UITemplates")
        :WaitForChild("PlayerListTemplates")
        :WaitForChild("PlayerListTemplateAdmin")

    local selectedUserId = nil
    local entries = {}

    local function addPlayer(player)
        if entries[player.UserId] then return end

        local entry = PlayerTemplate:Clone()
        entry.Name = tostring(player.UserId)
        entry.PlayerName.Text = player.DisplayName
        entry.ProfileImgFrame.ProfileImg.Image = GetThumbnail.GetThumbnail(player.UserId)
        entry.Parent = PlayerListContainer
        entries[player.UserId] = entry

        entry.SelectPlayer.MouseButton1Click:Connect(function()
            for _, e in pairs(entries) do
                e.UIStroke.Color = GREY
            end
            entry.UIStroke.Color = BLUE
            selectedUserId = player.UserId
        end)
    end

    local function removePlayer(userId)
        if entries[userId] then
            entries[userId]:Destroy()
            entries[userId] = nil
            if selectedUserId == userId then
                selectedUserId = nil
            end
        end
    end

    local function refresh()
        for _, player in pairs(Players:GetPlayers()) do
            addPlayer(player)
        end
        for userId in pairs(entries) do
            if not Players:GetPlayerByUserId(userId) then
                removePlayer(userId)
            end
        end
    end

    refresh()
    Players.PlayerAdded:Connect(addPlayer)
    Players.PlayerRemoving:Connect(function(player)
        removePlayer(player.UserId)
    end)

    local reasonInput = nil
    if config.reasonInputPath then
        reasonInput = Panel
        for _, name in ipairs(config.reasonInputPath) do
            reasonInput = reasonInput:WaitForChild(name)
        end
    end

    local lengthInput = nil
    if config.lengthInputPath then
        lengthInput = Panel
        for _, name in ipairs(config.lengthInputPath) do
            lengthInput = lengthInput:WaitForChild(name)
        end
    end

    local confirmButton = Panel:WaitForChild(config.confirmButtonName)
    confirmButton.MouseButton1Click:Connect(function()
        if not selectedUserId then
            warn("No player selected")
            return
        end

        local reason = reasonInput and reasonInput.Text
        local length = lengthInput and tonumber(lengthInput.Text)
        config.onConfirm(selectedUserId, reason, length)

        if reasonInput then reasonInput.Text = "" end
        if lengthInput then lengthInput.Text = "" end
        selectedUserId = nil
    end)
end

-- Wiring

-- Toggle panel via button and hotkey
TogglePanelButton.MouseButton1Click:Connect(function()
    if not TogglePanelButton.Visible then return end
    togglePanel()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.M then
        togglePanel()
    end
end)

AdminPanel.Close.MouseButton1Click:Connect(togglePanel)

-- Back button
BackButton.MouseButton1Click:Connect(function()
    toggleFrames("AdminOptions")
end)

-- Main menu buttons
for _, btn in pairs(MainFrame:GetChildren()) do
    if btn:IsA("ImageButton") or btn:IsA("TextButton") then
        btn.MouseButton1Click:Connect(function()
            toggleFrames(btn.Name)
        end)
    end
end

-- Player info
setupPlayerInfo(LOCAL_DISPLAY, LOCAL_USERID)

-- Edit value flow
ConfirmChangeButton.MouseButton1Click:Connect(function()
    local newValue = tonumber(EditValueInput.Text)
    if not newValue then
        warn("Invalid value:", EditValueInput.Text)
        return
    end

    if currentValueToChange == "ChangeMinimumPlayerCount" then
        sendCommand("GameTools", "ChangeMinimumPlayerCount", newValue)
    elseif currentValueToChange == "ChangeIntermissionTime" then
        sendCommand("GameTools", "ChangeIntermissionTime", newValue)
    elseif currentValueToChange == "ChangeGameRoundTime" then
        sendCommand("GameTools", "ChangeGameRoundTime", newValue)
    else
        warn("Unknown value type")
        return
    end

    ChangeValueFrame.Visible = false
    EditValueInput.Text = ""
end)

ChangeValueFrame.Exit.MouseButton1Click:Connect(function()
    ChangeValueFrame.Visible = false
    EditValueInput.Text = ""
end)

-- Game tools buttons
local function setupGameTools()
    for _, btn in pairs(GameToolsContainer:GetChildren()) do
        if btn:IsA("ImageButton") then
            btn.MouseButton1Click:Connect(function()
                local typeValue = btn:FindFirstChild("Type")
                if not typeValue then
                    warn("Missing Type value on", btn.Name)
                    return
                end

                if typeValue.Value == "ChangeValue" then
                    currentValueToChange = btn.Name
                    showChangeValue()
                elseif typeValue.Value == "Boolean" then
                    sendCommand("GameTools", btn.Name)
                else
                    warn("Unknown Type value on", btn.Name)
                end
            end)
        end
    end
end

-- Player management options routing
local function setupPlayerManagementOptions()
    for _, btn in pairs(PlayerManagementOptions:GetChildren()) do
        if btn:IsA("ImageButton") then
            btn.MouseButton1Click:Connect(function()
                for _, frame in pairs(PlayerManagementFrame:GetChildren()) do
                    if frame:IsA("GuiObject") then
                        frame.Visible = (frame.Name == btn.Name)
                    end
                end
            end)
        end
    end
end

-- Security options routing
local function setupSecurityOptions()
    for _, btn in pairs(SecurityOptionsFrame:GetChildren()) do
        if btn:IsA("ImageButton") then
            btn.MouseButton1Click:Connect(function()
                for _, frame in pairs(SecurityFrame:GetChildren()) do
                    if frame:IsA("GuiObject") then
                        frame.Visible = (frame.Name == btn.Name)
                    end
                end
                if btn.Name == "AdminLogs" then
                    for i , v in pairs(AdminLogsContainer:GetChildren()) do
                        if v:IsA("Frame") then
                            v:Destroy()
                        end
                    end
                    sendCommand("Security", "AdminLogs")
                end
            end)
        end
    end
end


AdminClientRecieve.OnClientEvent:Connect(function(action: string, data: any)
    if action == "ReceiveAdminLogs" then
        local logs = data
        for _, log in ipairs(logs) do
            local logEntry = AdminLogTemplate:Clone()
            local LogInfo = logEntry:WaitForChild("LogInfo")

            local AdminContainerInfo = logEntry:WaitForChild("ProfileContainer")

            AdminContainerInfo:WaitForChild("ProfileImg").Image = GetThumbnail.GetThumbnail(log.AdminUserId)
            logEntry:WaitForChild("AdminUser").Text = Players:GetNameFromUserIdAsync(log.AdminUserId)
            logEntry:WaitForChild("AdminRank").Text = "Admin"

            LogInfo.Action.Text = "Action: " .. tostring(log.Action)
            LogInfo.AdminID.Text = "Admin UserId: " .. tostring(log.AdminUserId)

            local targetIdText = tostring(log.TargetUserId)
            if log.TargetUserId == nil or targetIdText == "nan" or targetIdText == "nil" or targetIdText == "" then
                LogInfo.TargetID.Visible = false
            else
                LogInfo.TargetID.Visible = true
                LogInfo.TargetID.Text = "Target UserId: " .. targetIdText
            end

            if log.Details ~= nil and tostring(log.Details) ~= "" then
                LogInfo.Details.Visible = true
                LogInfo.Details.Text = "Details: " .. tostring(log.Details)
            else
                LogInfo.Details.Visible = false
            end
            local timestamp = os.date("*t", log.Timestamp)
            LogInfo.Timestamp.Text = string.format("Time: %02d/%02d/%04d %02d:%02d:%02d", timestamp.day, timestamp.month, timestamp.year, timestamp.hour, timestamp.min, timestamp.sec)
            logEntry.Parent = AdminLogsContainer
        end
    end
end)



-- Panels
buildPlayerListHandler({
    frame = BanFrame,
    panelName = "BanPanel",
    listFrameName = "PlayerListFrame",
    confirmButtonName = "BanPlayer",
    reasonInputPath = { "BanReasonFrame", "ValueTextBox" },
    lengthInputPath = { "BanLengthFrame", "ValueTextBox" },
    onConfirm = function(userId, reason, hours)
        local banReason = (reason and reason ~= "" and reason) or "No reason provided"
        local banLengthHours = tonumber(hours) or 0
        sendCommand("PlayerManagement", "BanPlayer", userId, banReason, banLengthHours)
    end,
})

buildPlayerListHandler({
    frame = KickFrame,
    panelName = "KickPanel",
    listFrameName = "PlayerListFrame",
    confirmButtonName = "KickPlayer",
    reasonInputPath = { "KickReasonFrame", "ValueTextBox" },
    onConfirm = function(userId, reason)
        local kickReason = (reason and reason ~= "" and reason) or "No reason provided"
        sendCommand("PlayerManagement", "KickPlayer", userId, kickReason)
    end,
})

buildPlayerListHandler({
    frame = WipeInventoryFrame,
    panelName = "WipeInventoryPanel",
    listFrameName = "PlayerListFrame",
    confirmButtonName = "WipeInventory",
    onConfirm = function(userId)
        sendCommand("PlayerManagement", "WipeInventory", userId)
    end,
})

-- Init
setupGameTools()
setupPlayerManagementOptions()
setupSecurityOptions()