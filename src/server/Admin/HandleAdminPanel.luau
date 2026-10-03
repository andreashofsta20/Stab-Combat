-- src/server/Admin/HandleAdminPanel.luau

local VerifiedAdmins = require(script.Parent.VerifiedAdmins)
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")





local initializedPlayers = {}
local function initializePlayer(player)
    if player.Parent ~= Players or initializedPlayers[player] then return end
    initializedPlayers[player] = true
    
    local PlayerID = player.UserId

    if not VerifiedAdmins.CheckAdmin(PlayerID) then
        return
    end



    local AdminClientFolder = ServerStorage:FindFirstChild("AdminFolder")

    if AdminClientFolder then
        local AdminClientClone = AdminClientFolder:Clone()
        local gui = player:WaitForChild("PlayerGui", 10)
        if gui and player.Parent == Players then
            if not gui:FindFirstChild(AdminClientFolder.Name) then AdminClientClone.Parent = gui
            else AdminClientClone:Destroy() end
        else AdminClientClone:Destroy() end
    end





end
Players.PlayerAdded:Connect(initializePlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(initializePlayer, player) end
Players.PlayerRemoving:Connect(function(player) initializedPlayers[player] = nil end)


return {}
