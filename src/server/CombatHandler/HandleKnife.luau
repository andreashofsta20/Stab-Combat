-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KnivesRemotes = RemotesFolder:WaitForChild("Knife")
local ThrowKnifeRemote = KnivesRemotes:WaitForChild("ThrowKnife")

local StabKnifeRemote = KnivesRemotes:WaitForChild("StabKnife")

-- // MODULES // --
local ThrowKnifeModule = require(script.Parent:WaitForChild("ThrowKnife"))
local StabKnifeModule = require(script.Parent:WaitForChild("StabKnife"))
local KNIFE_ACTION_MIN_GAP = 0.4
local lastKnifeActionAt: {[number]: number} = {}

local function canProcessAction(player: Player): boolean
    local now = os.clock()
    local prev = lastKnifeActionAt[player.UserId]
    if prev and (now - prev) < KNIFE_ACTION_MIN_GAP then
        return false
    end
    lastKnifeActionAt[player.UserId] = now
    return true
end

-- // THROWING KNIFE // --
local ProjectileMath = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProjectileMath"))

ThrowKnifeRemote.OnServerEvent:Connect(function(player: Player, shotId: string, origin: Vector3, direction: Vector3, chargeRatio: number, clientTimestamp: number?)
    if not (typeof(shotId) == "string" and #shotId <= 64)
        or not ProjectileMath.IsFiniteVector(origin)
        or not ProjectileMath.IsFiniteVector(direction)
        or not ProjectileMath.IsFiniteNumber(chargeRatio) then
        return
    end
    -- The timestamp is advisory only; never use it to rewind or grant distance.
    if clientTimestamp ~= nil and not ProjectileMath.IsFiniteNumber(clientTimestamp) then return end
    if ProjectileMath.NormalizeDirection(direction) == nil then return end
    if not canProcessAction(player) then
        return
    end
    ThrowKnifeModule.Throw(player, shotId, origin, direction, chargeRatio)
end)

-- // STABBING KNIFE // --
StabKnifeRemote.OnServerEvent:Connect(function(player : Player)
    if not canProcessAction(player) then
        return
    end
    StabKnifeModule.Stab(player)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
    lastKnifeActionAt[player.UserId] = nil
end)

return {}