-- src/server/Admin/HandleAdminPanel.luau

local VerifiedAdmins = require(script.Parent.VerifiedAdmins)
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")





Players.PlayerAdded:Connect(function(player)
    
    local PlayerID = player.UserId

    if not VerifiedAdmins.CheckAdmin(PlayerID) then
        return
    end



    local AdminClientFolder = ServerStorage:FindFirstChild("AdminFolder")

    if AdminClientFolder then
        local AdminClientClone = AdminClientFolder:Clone()
        AdminClientClone.Parent = player:WaitForChild("PlayerGui")
    end





end)


return {}