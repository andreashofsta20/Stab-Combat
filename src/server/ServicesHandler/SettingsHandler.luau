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
local ALLOWED_SETTINGS = {
    MusicSetting = true,
    LobbySetting = true,
    LobbyMode = true,
    Notifications = true,
    Trades = true,
}
local settingCooldowns: {[number]: number} = {}
local SETTING_COOLDOWN = 0.5

local function SettingApplied(player: Player, settingname: string, value: boolean)
    AppliedSettingClient:FireClient(player, settingname, value)
    NotificationHandler.SendNotification(player, tostring(settingname) .. " " .. tostring(value), 2, "Checkmark")
end

local function ApplySetting(player: Player, settingname: string)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end
    local SettingsFolder = leaderstats:FindFirstChild("Settings")
    if not SettingsFolder then return end

    local setting = SettingsFolder:FindFirstChild(settingname)
    if not setting then
        warn("Couldn't find setting:", settingname)
        return
    end

    if settingname == "LobbyMode" and MainGameModule.IsLobbyModeLocked() then
        NotificationHandler.SendNotification(player, "Lobby Mode is locked right now.", 2, "Alert")
        return
    end

    setting.Value = not setting.Value
    SettingApplied(player, settingname, setting.Value)
end

-- // REMOTE CONNECTION // --
AppliedSettingRemote.OnServerEvent:Connect(function(player: Player, settingname: string)
    if not player then return end
    if type(settingname) ~= "string" then return end
    if not ALLOWED_SETTINGS[settingname] then return end
    local now = os.clock()
    if settingCooldowns[player.UserId] and (now - settingCooldowns[player.UserId]) < SETTING_COOLDOWN then return end
    settingCooldowns[player.UserId] = now

    ApplySetting(player, settingname)
end)

Players.PlayerRemoving:Connect(function(player)
    settingCooldowns[player.UserId] = nil
end)

return {}
