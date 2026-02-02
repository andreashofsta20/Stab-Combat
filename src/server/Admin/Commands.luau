local Commands = {}
local VerifiedAdmins = require(script.Parent:WaitForChild("VerifiedAdmins"))
local Players = game:GetService("Players")



function Commands.CheckAdmin(userid : string)

    local IsAdmin = VerifiedAdmins.CheckAdmin(userid)
    return IsAdmin
end

Commands.PlayerManagement = {
    Commands = {
        KickPlayer = function(Target: number, AdminUserID: number, Reason: string)
            if not Target then return end

            if not Commands.CheckAdmin(AdminUserID) then
                print("No authorization", AdminUserID)
                return
            end

            local PlayerToKick = Players:GetPlayerByUserId(Target)
            if PlayerToKick then
                PlayerToKick:Kick(Reason or "No reason provided")
            end
        end,

        BanPlayer = function(Target: number, AdminUserID: number, Reason: string)
            if not Target then return end

            if not Commands.CheckAdmin(AdminUserID) then
                print("No authorization", AdminUserID)
                return
            end

            Players:BanAsync({Target}, 0, Reason or "No reason provided")
            
            local PlayerToBan = Players:GetPlayerByUserId(Target)
            if PlayerToBan then
                PlayerToBan:Kick(Reason or "No reason provided")
            end
        end,

        WipeInventory = function(Target: number, AdminUserID: number)
            if not Target then return end

            if not Commands.CheckAdmin(AdminUserID) then
                print("No authorization", AdminUserID)
                return
            end

            local player = Players:GetPlayerByUserId(Target)

            if not player then return end


            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local ToReset = {
                    "Knives",
                    "Emotes",
                    "Cash",
                    "Wins",
                    "WinStreak",
                }

                for _, statname in pairs(ToReset) do
                    local stat = leaderstats:FindFirstChild(statname)
                    if stat then
                        stat.Value = 0
                    end
                end
            end




        end,








    },
}

Commands.AccountTools = {


    Commands = {

        


    },
}



Commands.GameTools = {


    Commands = {


        ChangeMinimumPlayerCount = function(NewValue : number, AdminID : number)

            if not Commands.CheckAdmin(AdminID) then
                print("No authorization", AdminID)
                return
            end

            if NewValue < 1 then
                NewValue = 1
            end

            local RoundHandler = require(game.ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            RoundHandler.MinimumPlayers = NewValue
        end,

        ChangeIntermissionTime = function(NewValue : number, AdminUserID : number)

            if not Commands.CheckAdmin(AdminUserID) then
                print("No authorization", AdminUserID)
                return
            end

            if NewValue < 1 then
                NewValue = 1
            end

            local GameHandler = require(game.ServerScriptService:WaitForChild("Game"):WaitForChild("RoundHandler"))
            GameHandler.VotingDuratation = NewValue
        end,





        


    },
}



Commands.Security = { -- trade logs etc


    Commands = {



        


    },
}







return Commands



