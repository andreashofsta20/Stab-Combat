local VerifiedAdmins = require(script.Parent:WaitForChild("VerifiedAdmins"))
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Commands = {}

function Commands.CheckAdmin(userid: number): boolean
    return VerifiedAdmins.CheckAdmin(userid)
end

Commands.PlayerManagement = {
    Commands = {
        KickPlayer = function(adminUserID: number, targetUserID: number, reason: string?)
            if not Commands.CheckAdmin(adminUserID) then
                warn("No authorization", adminUserID)
                return
            end
            if not targetUserID then return end

            local playerToKick = Players:GetPlayerByUserId(targetUserID)
            if playerToKick then
                playerToKick:Kick(reason or "No reason provided")
            end
        end,

        BanPlayer = function(adminUserID: number, targetUserID: number, reason: string?)
            if not Commands.CheckAdmin(adminUserID) then
                warn("No authorization", adminUserID)
                return
            end
            if not targetUserID then return end

            -- TODO: Implement your ban system using DataStoreService
            -- Example: Save targetUserID to a ban list and check it on PlayerAdded to kick immediately.
            local playerToBan = Players:GetPlayerByUserId(targetUserID)
            if playerToBan then
                playerToBan:Kick(reason or "No reason provided")
            end
        end,

        WipeInventory = function(adminUserID: number, targetUserID: number)
            if not Commands.CheckAdmin(adminUserID) then
                warn("No authorization", adminUserID)
                return
            end
            if not targetUserID then return end

            local player = Players:GetPlayerByUserId(targetUserID)
            if not player then return end

            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local toReset = { "Knives", "Emotes", "Cash", "Wins", "WinStreak" }
                for _, statName in ipairs(toReset) do
                    local stat = leaderstats:FindFirstChild(statName)
                    if stat and stat:IsA("NumberValue") then
                        stat.Value = 0
                    end
                end
            end
        end,
    },
}

Commands.AccountTools = {
    Commands = {
        -- Add account-related tools here
    },
}

Commands.GameTools = {
    Commands = {
        ChangeMinimumPlayerCount = function(adminID: number, newValue: number)
            print("ChangeMinimumPlayerCount called with adminID:", adminID, "newValue:", newValue)
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return
            end
            if type(newValue) ~= "number" then 
                warn("Invalid newValue type:", type(newValue))
                return 
            end
            if newValue < 1 then newValue = 1 end

            print("Setting MinimumPlayers to", newValue)
            local RoundHandler = require(ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            RoundHandler.MinimumPlayers = newValue
            print("MinimumPlayers set successfully to", RoundHandler.MinimumPlayers)
        end,

        ChangeIntermissionTime = function(adminID: number, newValue: number)
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return
            end
            if type(newValue) ~= "number" then return end
            if newValue < 1 then newValue = 1 end

            local RoundHandler = require(ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            RoundHandler.VotingDuration = newValue
            RoundHandler.VotingDurationSTUDIO = newValue
        end,

        TestMode = function(adminID: number)
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return
            end
            local RoundHandler = require(ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            RoundHandler.TestMode = not RoundHandler.TestMode
        end,
    },
}

Commands.Security = {
    Commands = {
        -- Add security-related commands (e.g., trade logs) here
    },
}

return Commands