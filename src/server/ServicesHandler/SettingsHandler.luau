-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MainGameModule = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("MainGame"))

-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings")
local AppliedSettingRemote = RemotesFolder:WaitForChild("ApplySetting")
local AppliedSettingClient = RemotesFolder:WaitForChild("AppliedClient")

-- // MODULES // --
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

-- // REPLICATED STORAGE MODULES // --
local ReplicatedStorageModulesFolder = ReplicatedStorage:WaitForChild("Modules")

-- // FUNCTIONS // --
local function SettingApplied(player: Player, settingname: string, value: boolean)
    AppliedSettingClient:FireClient(player, settingname, value)
    NotificationHandler.SendNotification(player, tostring(settingname) .. " " .. tostring(value), 2, "Checkmark")
end

local function ApplySetting(player: Player, settingname: string)
    local leaderstats = player:WaitForChild("leaderstats")
    local SettingsFolder = leaderstats:WaitForChild("Settings")

    local setting = SettingsFolder:FindFirstChild(settingname)
    if not setting then
        warn("Couldn't find setting:", settingname)
        return
    end

    if settingname == "LobbyMode" and MainGameModule.GameActive then
        NotificationHandler.SendNotification(player, "Wait until game ends.", 2, "Alert")
        return
    end

    setting.Value = not setting.Value
    SettingApplied(player, settingname, setting.Value)
end

-- // REMOTE CONNECTION // --
AppliedSettingRemote.OnServerEvent:Connect(function(player: Player, settingname: string)
    if not player then return end
    if not settingname then return end

    ApplySetting(player, settingname)
end)

return {}
