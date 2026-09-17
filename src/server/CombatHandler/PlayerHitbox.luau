--]

local PlayerHitbox = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local HITBOX_TAG = "PlayerHitbox"
local HITBOX_SIZE = Vector3.new(6, 7.5, 6) -- Width, Height, Depth
local HEAL_INTERVAL = 3 -- seconds between self-heal checks

local activeHitboxes: {[number]: BasePart} = {}
local characterConnections: {[number]: {RBXScriptConnection}} = {}

-- ─── Core creation ────────────────────────────────────────────────────

local function attachHitbox(player: Player, character: Model)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Already has a valid hitbox
    local existing = activeHitboxes[player.UserId]
    if existing and existing.Parent == character and existing:FindFirstChildOfClass("WeldConstraint") then
        return
    end

    -- Destroy stale reference
    if existing then
        pcall(function() existing:Destroy() end)
        activeHitboxes[player.UserId] = nil
    end

    local hitbox = Instance.new("Part")
    hitbox.Name = "Hitbox"
    hitbox.Size = HITBOX_SIZE
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.CanQuery  = true  -- spatial queries (Spherecast, GetPartBoundsInBox) must find this
    hitbox.CanTouch  = false
    hitbox.Massless  = true
    hitbox.Anchored  = false

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hrp
    weld.Part1 = hitbox
    weld.Parent = hitbox

    hitbox.CFrame = hrp.CFrame
    hitbox.Parent = character

    CollectionService:AddTag(hitbox, HITBOX_TAG)
    activeHitboxes[player.UserId] = hitbox
end

-- Waits for HRP then attaches; guards every yield against character death.
local function safeAttach(player: Player, character: Model)
    -- Wait for HumanoidRootPart (character stream-in can delay it)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        hrp = character:WaitForChild("HumanoidRootPart", 10)
    end
    if not hrp or character.Parent == nil then return end

    attachHitbox(player, character)
end

-- ─── Per-player wiring ────────────────────────────────────────────────

local function cleanupConnections(userId: number)
    local conns = characterConnections[userId]
    if conns then
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        characterConnections[userId] = nil
    end
end

local function onCharacterAdded(player: Player, character: Model)
    cleanupConnections(player.UserId)
    local conns = {}
    characterConnections[player.UserId] = conns

    -- Immediately try to attach (HRP may already exist)
    task.spawn(safeAttach, player, character)

    -- Re-attach if Humanoid respawns inside the same character (custom respawn systems)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        table.insert(conns, humanoid.Died:Connect(function()
            -- Hitbox stays on corpse intentionally — new CharacterAdded will create a fresh one
        end))
    end

    -- If something destroys the hitbox mid-life, recreate it immediately
    table.insert(conns, character.ChildRemoved:Connect(function(child)
        if child.Name == "Hitbox" and CollectionService:HasTag(child, HITBOX_TAG) then
            -- Only re-create if character is still alive
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and character.Parent then
                task.defer(function()
                    if character.Parent then
                        attachHitbox(player, character)
                    end
                end)
            end
        end
    end))
end

local function onPlayerAdded(player: Player)
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)

    -- Handle already-spawned character
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

local function onPlayerRemoving(player: Player)
    cleanupConnections(player.UserId)
    local hitbox = activeHitboxes[player.UserId]
    if hitbox then
        pcall(function() hitbox:Destroy() end)
    end
    activeHitboxes[player.UserId] = nil
end

-- ─── Self-healing loop ────────────────────────────────────────────────
-- Periodically verifies every living character has a valid hitbox.
-- Catches anything the event-driven path missed.

local function healLoop()
    while true do
        task.wait(HEAL_INTERVAL)
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if not character then continue end

            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then continue end

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            local hitbox = activeHitboxes[player.UserId]
            if hitbox and hitbox.Parent == character and hitbox:FindFirstChildOfClass("WeldConstraint") then
                continue -- healthy
            end

            -- Missing or broken — recreate
            attachHitbox(player, character)
        end
    end
end

-- ─── Public API ───────────────────────────────────────────────────────

function PlayerHitbox.GetHitbox(player: Player): BasePart?
    return activeHitboxes[player.UserId]
end

-- Resolves any hit part (hitbox Part or regular body part) to its owning Player + Humanoid.
function PlayerHitbox.GetPlayerFromHitbox(part: BasePart): (Player?, Humanoid?)
    if not part then return nil, nil end

    -- Fast path: hit the hitbox directly
    if CollectionService:HasTag(part, HITBOX_TAG) then
        local character = part.Parent
        if character then
            return Players:GetPlayerFromCharacter(character),
                   character:FindFirstChildOfClass("Humanoid")
        end
    end

    -- Fallback: Safely climb up to find the true Character model (ignores Tool inheritance bugs)
    local current = part
    while current and current ~= workspace do
        local humanoid = current:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return Players:GetPlayerFromCharacter(current), humanoid
        end
        current = current.Parent
    end

    return nil, nil
end

-- ─── Init ─────────────────────────────────────────────────────────────

function PlayerHitbox.Init()
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Start background self-healing
    task.spawn(healLoop)
end

return PlayerHitbox