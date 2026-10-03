-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ToolPhysics = require(ReplicatedStorage.Modules.RevolverToolPhysics).New(require(ReplicatedStorage.Modules.KnivesInfo))
for _, player in ipairs(Players:GetPlayers()) do ToolPhysics.BindPlayer(player) end
Players.PlayerAdded:Connect(ToolPhysics.BindPlayer)

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KnivesRemotes = RemotesFolder:WaitForChild("Knife")
local ThrowKnifeRemote = KnivesRemotes:WaitForChild("ThrowKnife")

local StabKnifeRemote = KnivesRemotes:WaitForChild("StabKnife")

-- // MODULES // --
local ThrowKnifeModule = require(script.Parent:WaitForChild("ThrowKnife"))
local StabKnifeModule = require(script.Parent:WaitForChild("StabKnife"))
local Config = require(ReplicatedStorage.Modules.KnifeConfig)
local FoodState = require(script.Parent.FoodState)
local KNIFE_ACTION_MIN_GAP = Config.ActionMinGap
local lastKnifeActionAt: {[number]: number} = {}
local buckets = {}

local function canProcessAction(player: Player)
    local now = os.clock()
    buckets[player] = buckets[player] or { tokens = Config.RequestBurst, time = now }
    if not FoodState.AllowRequest(buckets[player], now, Config.RequestBurst, Config.RequestsPerSecond) then return false, false end
    local prev = lastKnifeActionAt[player.UserId]
    if prev and (now - prev) < KNIFE_ACTION_MIN_GAP then
        return false, true
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
    local allowed, acknowledge = canProcessAction(player)
    if not allowed then
        if acknowledge then KnivesRemotes.ThrewClient:FireClient(player, {shotId = shotId, accepted = false}) end
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

Players.PlayerRemoving:Connect(function(player)
    ToolPhysics.RemovePlayer(player)
    lastKnifeActionAt[player.UserId] = nil
    buckets[player] = nil
end)

return {}
