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
    Music = true,
    MusicSetting = true,
    Day = true,
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

    -- FIXED: Lobby Mode block logic
    if settingname == "LobbyMode" then
        local isInRound = MainGameModule.PlayersInGame[player.UserId] == true
        local isActiveFFA = MainGameModule.GameActive
            and MainGameModule.CurrentMode
            and MainGameModule.CurrentMode.Id == "FFA"
        local isActiveBattleRoyale = MainGameModule.GameActive
            and MainGameModule.CurrentMode
            and MainGameModule.CurrentMode.Id == "BattleRoyale"

        if isInRound and not (isActiveFFA or isActiveBattleRoyale) then
            NotificationHandler.SendNotification(player, "You can't change Lobby Mode while in a game!", 2, "Alert")
            return
        end

        if MainGameModule.IsLobbyModeLocked() and not MainGameModule.GameActive then
            NotificationHandler.SendNotification(player, "A round is starting! Please wait a moment.", 2, "Alert")
            return
        end
    end

    setting.Value = not setting.Value
    SettingApplied(player, settingname, setting.Value)

    if settingname == "LobbyMode"
        and setting.Value == true
        and MainGameModule.GameActive
        and MainGameModule.CurrentMode
        and MainGameModule.CurrentMode.Id == "FFA" then
        MainGameModule.LeaveRound(player)
    end
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