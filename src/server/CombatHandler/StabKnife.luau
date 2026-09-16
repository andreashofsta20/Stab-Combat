local KnifeModule = {}
-- // SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- // MODULES
local MainGameModule = require(script.Parent.Parent.Game.MainGame)
local PlayerHitbox = require(script.Parent.PlayerHitbox)

-- // ANIMS
local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations") 
local StabAnimation = CombatAnimations:WaitForChild("Stab")

-- // CONFIG
local STAB_RANGE = 12 
local STAB_WIDTH = 8  
local STAB_HEIGHT = 8 
local DAMAGE = 100
local COOLDOWN = 0.6
local Cooldown = {}

local DamageDealtClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("DamageDealtClient")

local function playStabAnim(humanoid)
    if not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    local track = animator:LoadAnimation(StabAnimation)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false
    --track:Play()
end

function KnifeModule.Stab(player: Player)
    if not player or player.ClassName ~= "Player" then return end

    local now = os.clock()
    if Cooldown[player.UserId] and now - Cooldown[player.UserId] < COOLDOWN then
        return
    end
    Cooldown[player.UserId] = now

    if not MainGameModule.GameActive then return end
    if not MainGameModule.PlayersInGame[player.UserId] then return end

    local character = player.Character
    if not character then return end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    if not character:FindFirstChildWhichIsA("Tool") then return end

    playStabAnim(hum)

    local origin = hrp.Position + hrp.CFrame.LookVector * (STAB_RANGE / 2)
    local hitboxCFrame = CFrame.lookAt(origin, origin + hrp.CFrame.LookVector)
    local hitboxSize = Vector3.new(STAB_WIDTH, STAB_HEIGHT, STAB_RANGE)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = { character }

    local touchingParts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
    local damagedPlayers = {}

    for _, part in ipairs(touchingParts) do
        local victimPlayer, victimHum = PlayerHitbox.GetPlayerFromHitbox(part)
        local victimId = victimPlayer and victimPlayer.UserId or nil

        if not victimHum or victimHum == hum or (victimId and damagedPlayers[victimId]) then
            continue
        end

        if victimPlayer and not MainGameModule.PlayersInGame[victimId] then
            continue
        end

        if victimHum.Health <= 0 then
            continue
        end
        
        -- // ANTI-EXPLOIT: Check if the victim is actually close to the attacker
        local victimHrp = victimHum.Parent:FindFirstChild("HumanoidRootPart")
        if victimHrp then
            local dist = (hrp.Position - victimHrp.Position).Magnitude
            if dist > (STAB_RANGE + 8) then -- 8 studs of leeway for player latency/ping
                continue 
            end
        end

        if victimId then
            damagedPlayers[victimId] = true
            if victimHum.Health <= DAMAGE then
                MainGameModule.RegisterPendingKill(player, victimId)
            end
        end

        victimHum:TakeDamage(DAMAGE)
        
        -- Fix applied here: Pass victimHum.Parent so the client knows WHO took damage
        if victimHum.Parent then
            DamageDealtClient:FireClient(player, victimHum.Parent, DAMAGE)
        end
    end
end

Players.PlayerRemoving:Connect(function(player)
    Cooldown[player.UserId] = nil
end)

return KnifeModule