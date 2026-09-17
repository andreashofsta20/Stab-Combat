local HandleGameUI = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Templates UI
local TemplateUI = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InGameUITemplates")
local FFA_Templates = TemplateUI:WaitForChild("FFA")
local BR_Templates = TemplateUI:WaitForChild("BR")

local FFA_PlayerTemplate = FFA_Templates:WaitForChild("PlayerTemplate")
local BR_PlayerTemplate = BR_Templates:WaitForChild("PlayerTemplate")


-- UIS
local PlayerGui = player:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("Main"):WaitForChild("InGame")

local BattleRoyaleUI = MainGui:WaitForChild("BR")
local FFAUI = MainGui:WaitForChild("FFA")



-- Battle Royale UI
local BR_PlayerList = BattleRoyaleUI:WaitForChild("Top"):WaitForChild("PlayerList")


-- FFA UI
local FFA_PlayerList = FFAUI:WaitForChild("Top"):WaitForChild("PlayerList")


local function PlayerTemplate(player, playerkills, gamemode)
    if gamemode == "FFA" then
        local PlayerTemplate = FFA_PlayerTemplate:Clone()
        PlayerTemplate.Name = player.Name
        PlayerTemplate.PlayerName.Text = player.Name
        PlayerTemplate.PlayerKills.Text = playerkills
        PlayerTemplate.ProfileImg.Image = "rbxthumb://type=AvatarHeadShot&id="..player.UserId.."&w=420&h=420"
        PlayerTemplate.Parent = FFA_PlayerList

        if player == Players.LocalPlayer then
            PlayerTemplate.PlayerKills.TextColor3 = Color3.fromRGB(253, 194, 46)
            PlayerTemplate.UiStroke.Color = Color3.fromRGB(253, 194, 46)
        else
            return
        end
    elseif gamemode == "BR" then
        local PlayerTemplate = BR_PlayerTemplate:Clone()
        PlayerTemplate.Name = player.Name
        PlayerTemplate.PlayerName.Text = player.Name
        PlayerTemplate.PlayerKills.Text = playerkills
        PlayerTemplate.ProfileImg.Image = "rbxthumb://type=AvatarHeadShot&id="..player.UserId.."&w=420&h=420"
        PlayerTemplate.Parent = BR_PlayerList

        -- also this is gonna constantly update so if a player is dead on the battle royale UI then this
        -- PlayerTemplate.DeadImg.Visible = true
        -- PlayerTemplate.UiStroke.Transparency = 0.5
        -- PlayerTemplate.UiStroke.Color = Color3.fromRGB(255, 0, 4)
        -- PlayerTemplate.PlayerKills.TextTransparency = 0.53
        -- PlayerTemplate.PlayerName.TextTransparency = 0.89


        
        --

        if player == Players.LocalPlayer then
            PlayerTemplate.PlayerKills.TextColor3 = Color3.fromRGB(253, 194, 46)
            PlayerTemplate.UiStroke.Color = Color3.fromRGB(253, 194, 46)
        else
            return
        end
    end
end


local function FFA()
    BattleRoyaleUI.Visible = false


    FFAUI.Visible = true

end


local function BR()
    BattleRoyaleUI.Visible = true   
    FFAUI.Visible = false
end


local function HideAll()
    BattleRoyaleUI.Visible = false
    FFAUI.Visible = false
end


local function TurnVisible(gamemode)

    if gamemode == "FFA" then
        FFA()
    elseif gamemode == "BR" then
        BR()
    else
        return
    end

end





return HandleGameUI