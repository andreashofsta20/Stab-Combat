local VerifiedAdmins = require(script.Parent:WaitForChild("VerifiedAdmins"))
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
 local MainGameModule = require(ServerScriptService:WaitForChild("Game"):WaitForChild("MainGame"))
local InventoryHandler = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("InventoryHandler"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

local playerDataStore = DataStoreService:GetDataStore("PlayerStats_v2BETA11_")
local adminLogStore = DataStoreService:GetDataStore("AdminActionLogs_v1")
local wipeDebounce = {}
local AdminClientRecieve = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminClientRecieve")

local Commands = {}

local function logAdminAction(action: string, adminUserID: number, targetUserID: number?, details: string?)
    local entry = {
        Action = action,
        AdminUserId = adminUserID,
        TargetUserId = targetUserID,
        Details = details,
        Timestamp = os.time()
    }

    task.spawn(function()
        local success, err = pcall(function()
            adminLogStore:UpdateAsync("Logs", function(old)
                old = old or {}
                table.insert(old, 1, entry)
                if #old > 200 then
                    for i = #old, 201, -1 do
                        table.remove(old, i)
                    end
                end
                return old
            end)
        end)

        if not success then
            warn("Failed to write admin log:", err)
        end
    end)
end

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

            -- Get admin name
            local adminName = Players:GetNameFromUserIdAsync(adminUserID)
            
            -- Create professional kick message
            local kickMessage = "You got kicked.\n\nYou have been kicked from this experience.\n\nKicked by: " .. tostring(adminName) .. "\n\nReason: " .. (reason or "No reason provided")

            local playerToKick = Players:GetPlayerByUserId(targetUserID)
            if playerToKick then
                playerToKick:Kick(kickMessage)
            end

            logAdminAction("Kick", adminUserID, targetUserID, reason or "No reason provided")

            local adminPlayer = Players:GetPlayerByUserId(adminUserID)
            if adminPlayer then
                NotificationHandler.SendNotification(adminPlayer, "Kicked " .. tostring(playerToKick and playerToKick.Name or targetUserID) .. ".", 4, "Success")
            end
        end,

        BanPlayer = function(adminUserID: number, targetUserID: number, reason: string?, banLengthHours: number?)
            if not Commands.CheckAdmin(adminUserID) then
                warn("No authorization", adminUserID)
                return
            end
            if not targetUserID then return end
            
            -- Prevent banning yourself
            if adminUserID == targetUserID then
                warn("Cannot ban yourself")
                return
            end

            -- Calculate duration: -1 for permanent, otherwise convert hours to seconds
            local duration = -1
            local durationText = "Permanent"
            if banLengthHours and banLengthHours > 0 then
                duration = banLengthHours * 3600 -- Convert hours to seconds
                durationText = banLengthHours .. " hour" .. (banLengthHours == 1 and "" or "s")
            end

            -- Get admin name
            local adminName = Players:GetNameFromUserIdAsync(adminUserID)
            
            -- Create professional ban message
            local displayMessage = "You got banned.\n\nYou have been banned from this experience.\n\nDuration: " .. durationText .. "\nBanned by: " .. tostring(adminName) .. "\n\nReason: " .. (reason or "No reason provided")
            
            -- Use Roblox's built-in BanAsync with proper config dictionary
            local config = {
                UserIds = {targetUserID},
                Duration = duration,
                DisplayReason = displayMessage,
                PrivateReason = "Banned by: " .. tostring(adminName) .. " (" .. tostring(adminUserID) .. ") | Reason: " .. (reason or "No reason provided"),
                ExcludeAltAccounts = false,
                ApplyToUniverse = true
            }

            local success, err = pcall(function()
                Players:BanAsync(config)
            end)

            if success then
                local playerToBan = Players:GetPlayerByUserId(targetUserID)
                if playerToBan then
                    playerToBan:Kick(reason or "You have been banned")
                end

                local detail = "Duration: " .. durationText .. " | Reason: " .. (reason or "No reason provided")
                logAdminAction("Ban", adminUserID, targetUserID, detail)

                local adminPlayer = Players:GetPlayerByUserId(adminUserID)
                if adminPlayer then
                    NotificationHandler.SendNotification(adminPlayer, "Banned userId " .. tostring(targetUserID) .. ".", 4, "Success")
                end
            else
                local adminPlayer = Players:GetPlayerByUserId(adminUserID)
                if adminPlayer then
                    NotificationHandler.SendNotification(adminPlayer, "Ban failed: " .. tostring(err), 5, "Error")
                end
            end
        end,

        WipeInventory = function(adminUserID: number, targetUserID: number)
            if not Commands.CheckAdmin(adminUserID) then
                warn("No authorization", adminUserID)
                return
            end
            if not targetUserID then return end

            local now = os.clock()
            if wipeDebounce[targetUserID] and (now - wipeDebounce[targetUserID] < 3) then
                return
            end
            wipeDebounce[targetUserID] = now

            local player = Players:GetPlayerByUserId(targetUserID)
            if not player then return end

            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local inventoryFolder = leaderstats:FindFirstChild("Inventory")
                if inventoryFolder then
                    for _, item in ipairs(inventoryFolder:GetChildren()) do
                        item:Destroy()
                    end
                end

                local emotesFolder = leaderstats:FindFirstChild("Emotes")
                if emotesFolder then
                    for _, emote in ipairs(emotesFolder:GetChildren()) do
                        emote:Destroy()
                    end
                end

                local equippedKnife = leaderstats:FindFirstChild("EquippedKnife")
                if equippedKnife and equippedKnife:IsA("StringValue") then
                    equippedKnife.Value = "Shadow Dagger"
                end

                InventoryHandler.AddKnife(player, "Shadow Dagger")
            end

            local success, err = pcall(function()
                playerDataStore:UpdateAsync(player.UserId, function(oldData)
                    oldData = oldData or {}
                    oldData.Inventory = {}
                    oldData.Emotes = {}
                    oldData.EquippedKnife = "Shadow Dagger"
                    return oldData
                end)
            end)

            if not success then
                warn("Failed to wipe inventory for", player.Name, err)
                NotificationHandler.SendNotification(player, "Inventory wipe failed. Try again later.", 4, "Error")
            else
                local adminName = Players:GetNameFromUserIdAsync(adminUserID)
                NotificationHandler.SendNotification(player, "Your inventory was wiped by " .. tostring(adminName) .. ".", 5, "Skull")
                local adminPlayer = Players:GetPlayerByUserId(adminUserID)
                if adminPlayer then
                    NotificationHandler.SendNotification(adminPlayer, "Wiped inventory for " .. player.Name .. ".", 4, "Success")
                end

                logAdminAction("WipeInventory", adminUserID, targetUserID, "Inventory and emotes wiped")
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
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return
            end
            if type(newValue) ~= "number" then 
                warn("Invalid newValue type:", type(newValue))
                return 
            end
            if newValue < 1 then newValue = 1 end

            local RoundHandler = require(ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            RoundHandler.MinimumPlayers = newValue
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

        ChangeGameRoundTime = function(adminID: number, newValue: number)
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return
            end
            if type(newValue) ~= "number" then return end
            if newValue < 0 then return end

            local MainGame = require(ServerScriptService:WaitForChild("Game"):WaitForChild("MainGame"))
            MainGame.RoundTime = newValue * 60
        end,





        
    },
}

Commands.Security = {
    Commands = {

        AdminLogs = function(adminID: number): {any}
            if not Commands.CheckAdmin(adminID) then
                warn("No authorization", adminID)
                return {}
            end

            local logs = {}
            local success, err = pcall(function()
                logs = adminLogStore:GetAsync("Logs") or {}
            end)

            if not success then
                warn("Failed to retrieve admin logs:", err)
                return {}
            end

            AdminClientRecieve:FireClient(Players:GetPlayerByUserId(adminID), "ReceiveAdminLogs", logs)

            return logs
        end,
    },
}

return Commands