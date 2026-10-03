local KnifeModule = {}
-- // SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- // MODULES
local MainGameModule = require(script.Parent.Parent.Game.MainGame)
local PlayerHitbox = require(script.Parent.PlayerHitbox)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)
local ServerStorage = game:GetService("ServerStorage")

-- // ANIMS
local Config = require(ReplicatedStorage.Modules.KnifeConfig).Stab

-- // CONFIG
local STAB_RANGE = Config.Range
local STAB_WIDTH = Config.Width
local STAB_HEIGHT = Config.Height
local DAMAGE = Config.Damage
local COOLDOWN = Config.Cooldown
local Cooldown = {}

local DamageDealtClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("DamageDealtClient")

function KnifeModule.Stab(player: Player)
    if not player or player.ClassName ~= "Player" then return end

    local now = os.clock()
    if Cooldown[player.UserId] and now - Cooldown[player.UserId] < COOLDOWN then
        return
    end
    Cooldown[player.UserId] = now

    if not MainGameModule.GameActive then return end
    if not MainGameModule.PlayersInGame[player.UserId] then return end
    if player:GetAttribute("DataReady") ~= true then return end

    local character = player.Character
    if not character then return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    local equippedTool = character:FindFirstChildWhichIsA("Tool")
    local serverKnives = ServerStorage:FindFirstChild("Knives")
    if not equippedTool or not serverKnives or not serverKnives:FindFirstChild(equippedTool.Name) then return end

    local origin = hrp.Position + hrp.CFrame.LookVector * (STAB_RANGE / 2)
    local hitboxCFrame = CFrame.lookAt(origin, origin + hrp.CFrame.LookVector)
    local hitboxSize = Vector3.new(STAB_WIDTH, STAB_HEIGHT, STAB_RANGE)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = RagdollQuery.Exclude({ character })

    local touchingParts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
    local damagedPlayers = {}

    for _, part in ipairs(touchingParts) do
        local victimPlayer, victimHum = PlayerHitbox.GetPlayerFromHitbox(part)
        local victimId = victimPlayer and victimPlayer.UserId or nil

        if not victimPlayer or not victimHum or victimHum == hum or (victimId and damagedPlayers[victimId]) then
            continue
        end

        if victimPlayer and not MainGameModule.PlayersInGame[victimId] then
            continue
        end

        if victimHum.Health <= 0 or victimHum.Parent:FindFirstChildOfClass("ForceField") then
            continue
        end
        
        -- // ANTI-EXPLOIT: Check if the victim is actually close to the attacker
        local victimHrp = victimHum.Parent:FindFirstChild("HumanoidRootPart")
        if not victimHrp then continue end
        if victimHrp then
            local dist = (hrp.Position - victimHrp.Position).Magnitude
            if dist > (STAB_RANGE + Config.DistanceLeeway) then
                continue 
            end
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = RagdollQuery.Exclude({character, victimHum.Parent})
			local obstruction = workspace:Raycast(hrp.Position, victimHrp.Position - hrp.Position, rayParams)
			if obstruction then
				continue
			end
        end

        if victimId then
            damagedPlayers[victimId] = true
        end

        local dealt = MainGameModule.DamagePlayer(player, victimPlayer, victimHum, DAMAGE,
            { Kind = "KnifeStab", Direction = victimHrp.Position - hrp.Position })
        
        -- Fix applied here: Pass victimHum.Parent so the client knows WHO took damage
        if dealt > 0 and victimHum.Parent then
            DamageDealtClient:FireClient(player, victimHum.Parent, dealt)
        end
    end
end

Players.PlayerRemoving:Connect(function(player)
    Cooldown[player.UserId] = nil
end)

return KnifeModule
