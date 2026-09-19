local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local SoundHandlerModule = require(script.Parent:WaitForChild("SoundHandler"))
local ProjectileMath = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProjectileMath"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local touchAimPosition: Vector2? = nil
local mobileShiftLockEnabled = false 
local isMobileInput = false

local COOLDOWN = 0.5
local STAB_COOLDOWN = 0.3
local MAX_CHARGE_TIME = 1
local MIN_CHARGE_RATIO = 0
local MAX_CHARGE_RATIO = 1
local MAX_RAYCAST_DISTANCE = ProjectileMath.MAX_DISTANCE
local THROW_THRESHOLD = 0.2

-- VISUAL SETTINGS (Matching Server for prediction)
local KNIFE_SPEED = ProjectileMath.MAX_SPEED
local VISUAL_OFFSET = 0.8
local MIN_SPEED_MULT = 0.7
local MAX_SPEED_MULT = 1.7
local LIFETIME = 5

local ThrowKnifeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("ThrowKnife")
local ThrewKnifeClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("ThrewClient")
local StabKnifeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("StabKnife")

local MainUi = player.PlayerGui:WaitForChild("Main")
local BottomLeftFrame = MainUi:WaitForChild("BottomLeft")
local StuffContainerFrame = BottomLeftFrame:WaitForChild("StuffContainer")
local AbilityFrame = StuffContainerFrame:WaitForChild("Ability")
local OnClickFrame = AbilityFrame:WaitForChild("OnClick")
local OnClickFrameBar = OnClickFrame:WaitForChild("OnClickFrame")
local FramesFolder = MainUi:WaitForChild("Frames")

local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations")
local KnivesFolder = ReplicatedStorage:WaitForChild("Knives")
local ChargeAnimation = CombatAnimations:WaitForChild("Charge")
local ChargeLoopAnimation = CombatAnimations:WaitForChild("ChargeHold")
local ReleaseKnifeAnimation = CombatAnimations:WaitForChild("Throw")
local StabAnimation = CombatAnimations:WaitForChild("Stab")

local GameActive = ReplicatedStorage:WaitForChild("GameActive")

local CombatController = {}

local initialized = false
local lastThrow = 0
local lastStab = 0
local activeTween
local chargeTween
local charging = false
local chargeStart = 0
local chargeSessionId = 0
local nextShotId = 0
local predictedShots: {[string]: {handle: BasePart, connection: RBXScriptConnection}} = {}

local chargeTrack = nil
local chargeHoldTrack = nil
local throwTrack = nil
local stabTrack = nil

local currentHumanoid: Humanoid? = nil
local defaultWalkSpeed = 16
local sprintWalkSpeed = 24
local sprintEnabled = false

local function isAnyFrameVisible()
    for _, child in ipairs(FramesFolder:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible == true then
            return true
        end
    end
    return false
end

local function addTrail(part)
    local frontAttachment = Instance.new("Attachment", part)
    local backAttachment = Instance.new("Attachment", part)

    frontAttachment.Position = Vector3.new(0, 0, 0.5)
    backAttachment.Position = Vector3.new(0, 0, -0.5)

    local mainTrail = Instance.new("Trail")
    mainTrail.Attachment0 = frontAttachment
    mainTrail.Attachment1 = backAttachment
    mainTrail.Lifetime = 0.3
    mainTrail.MinLength = 0
    mainTrail.FaceCamera = true
    mainTrail.LightEmission = 1
    mainTrail.LightInfluence = 0

    mainTrail.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(0, 162, 255)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 64, 64)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
    }

    mainTrail.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    }

    mainTrail.WidthScale = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(0.5, 0.4),
        NumberSequenceKeypoint.new(1, 0.1)
    }

    mainTrail.Parent = part

    local secondaryTrail = Instance.new("Trail")
    secondaryTrail.Attachment0 = frontAttachment
    secondaryTrail.Attachment1 = backAttachment
    secondaryTrail.Lifetime = 0.15
    secondaryTrail.MinLength = 0
    secondaryTrail.FaceCamera = true
    secondaryTrail.LightEmission = 0.8
    secondaryTrail.LightInfluence = 0.2

    secondaryTrail.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 128, 0))
    }

    secondaryTrail.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.8, 0.7),
        NumberSequenceKeypoint.new(1, 1)
    }

    secondaryTrail.WidthScale = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 0.05)
    }

    secondaryTrail.Parent = part

    local particles = Instance.new("Attachment", part)
    particles.Position = Vector3.new(0, 0, -0.3)

    local sparks = Instance.new("ParticleEmitter")
    sparks.Parent = particles
    sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparks.Lifetime = NumberRange.new(0.1, 0.3)
    sparks.Rate = 100
    sparks.SpreadAngle = Vector2.new(45, 45)
    sparks.Speed = NumberRange.new(2, 8)
    sparks.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
    }
    sparks.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    }
    sparks.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.5, 0.05),
        NumberSequenceKeypoint.new(1, 0.01)
    }
    sparks.LightEmission = 1
    sparks.LightInfluence = 0

    task.spawn(function()
        task.wait(0.5)
        sparks.Enabled = false
        Debris:AddItem(sparks, 2)
    end)

    return frontAttachment, backAttachment
end

local function createKnifeVisual(origin: Vector3, direction: Vector3, charge: number, shotId: string, knifeName: string?, destination: Vector3?)
    local knivesFolder = ReplicatedStorage:FindFirstChild("Knives")
    local leaderstats = player:FindFirstChild("leaderstats")
    local equippedKnifeValue = leaderstats and leaderstats:FindFirstChild("EquippedKnife")
    local equippedKnife = knifeName or (equippedKnifeValue and equippedKnifeValue.Value)
    local template = equippedKnife and knivesFolder and knivesFolder:FindFirstChild(equippedKnife)
    local source = template and template:FindFirstChild("Handle")
    if not source or not source:IsA("BasePart") then return end

    local visualOrigin = origin + direction * VISUAL_OFFSET
    local handle = source:Clone()
    handle.CanCollide = false
    handle.CanQuery = false
    handle.Massless = true
    handle.CFrame = CFrame.lookAt(visualOrigin, visualOrigin + direction)
    handle.Parent = workspace
    addTrail(handle)

    local target = destination or (visualOrigin + direction * ProjectileMath.MAX_DISTANCE)
    local distance = (target - visualOrigin).Magnitude
    local speed = destination and math.max(distance / 0.08, ProjectileMath.GetSpeed(charge)) or ProjectileMath.GetSpeed(charge)
    local startTime = os.clock()
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = os.clock() - startTime
        local progress = math.clamp(speed * elapsed / distance, 0, 1)
        local currentPosition = visualOrigin + direction * math.min(distance, speed * elapsed)
        handle.CFrame = CFrame.lookAt(currentPosition, currentPosition + direction)
        if progress >= 1 then
            connection:Disconnect()
            predictedShots[shotId] = nil
            Debris:AddItem(handle, 2)
        end
    end)

    Debris:AddItem(handle, LIFETIME)
    predictedShots[shotId] = {handle = handle, connection = connection}
end

local function stickKnife(knife, hitPart, pos, normal)
    knife.Anchored = true
    knife.CFrame = CFrame.new(pos, pos + normal) * CFrame.Angles(math.rad(90), 0, 0)

    if hitPart and hitPart:IsA("BasePart") then
        local model = hitPart:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChildOfClass("Humanoid") then
            return
        else
            knife.Anchored = true
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = knife
            weld.Part1 = hitPart
            weld.Parent = knife
        end
    end
end

local function getAimRay()
    local cam = workspace.CurrentCamera
    if not cam then return nil end

    local viewport = cam.ViewportSize
    local shouldLockToCenter = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter

    if shouldLockToCenter or mobileShiftLockEnabled then
        return cam:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
    end

    if isMobileInput then
        if touchAimPosition then
            return cam:ScreenPointToRay(touchAimPosition.X, touchAimPosition.Y)
        else
            return cam:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
        end
    else
        local mouse = player:GetMouse()
        return mouse.UnitRay
    end
end

local function hasKnifeEquipped()
    local character = player.Character
    if not character then return false end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and KnivesFolder:FindFirstChild(child.Name) then
            return true
        end
    end
    return false
end

local function isCharging()
    return (chargeTrack and chargeTrack.IsPlaying) or (chargeHoldTrack and chargeHoldTrack.IsPlaying)
end

local function stopAllAnimations()
    if chargeTrack and chargeTrack.IsPlaying then
        chargeTrack:AdjustSpeed(1)
        chargeTrack:Stop()
    end
    if chargeHoldTrack and chargeHoldTrack.IsPlaying then
        chargeHoldTrack:Stop()
    end
end

local function loadAnimationTracks()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    chargeTrack = animator:LoadAnimation(ChargeAnimation)
    chargeHoldTrack = animator:LoadAnimation(ChargeLoopAnimation)
    throwTrack = animator:LoadAnimation(ReleaseKnifeAnimation)
    stabTrack = animator:LoadAnimation(StabAnimation)

    chargeTrack.Priority = Enum.AnimationPriority.Action4
    chargeHoldTrack.Priority = Enum.AnimationPriority.Action4
    throwTrack.Priority = Enum.AnimationPriority.Action
    stabTrack.Priority = Enum.AnimationPriority.Action
end

local function playStabAnimation()
    if isCharging() then return end
    stopAllAnimations()
    if stabTrack then
        stabTrack.Looped = false
        if stabTrack.IsPlaying then stabTrack:Stop() end
        stabTrack:Play()
        SoundHandlerModule.PlaySound("StabKnife")
    end
end

local function playChargeAnimation()
    stopAllAnimations()
    if not chargeTrack then return end

    local sessionId = chargeSessionId
    chargeTrack.Looped = false
    chargeTrack:AdjustSpeed(1)
    chargeTrack:Play()

    task.delay(chargeTrack.Length, function()
        if chargeSessionId ~= sessionId then return end
        if not charging then return end

        if chargeTrack and chargeTrack.IsPlaying then
            chargeTrack:AdjustSpeed(1)
            chargeTrack:Stop()
        end
        if chargeHoldTrack then
            chargeHoldTrack.Looped = true
            chargeHoldTrack:Play()
        end
    end)
end

local function playThrowAnimation()
    stopAllAnimations()
    if throwTrack then throwTrack:Play() end
    SoundHandlerModule.PlaySound("ThrowKnife")
end

local function uiAnimation()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    OnClickFrameBar.Size = UDim2.new(0, 0, 1, 0)
    local tweenIn = TweenService:Create(
        OnClickFrameBar,
        TweenInfo.new(0.25, Enum.EasingStyle.Linear),
        { Size = UDim2.new(1, 0, 1, 0) }
    )
    local tweenOut = TweenService:Create(
        OnClickFrameBar,
        TweenInfo.new(0.25, Enum.EasingStyle.Linear),
        { Size = UDim2.new(0, 0, 1, 0) }
    )
    activeTween = tweenOut
    local conn1, conn2
    conn1 = tweenIn.Completed:Connect(function(state)
        if state ~= Enum.PlaybackState.Completed then return end
        tweenOut:Play()
        if conn1 then conn1:Disconnect() end
    end)
    conn2 = tweenOut.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and activeTween == tweenOut then
            activeTween = nil
        end
        if conn2 then conn2:Disconnect() end
    end)
    tweenIn:Play()
end

local function startChargeTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    if chargeTween then
        chargeTween:Cancel()
        chargeTween = nil
    end
    OnClickFrameBar.Size = UDim2.new(0, 0, 1, 0)
    chargeTween = TweenService:Create(
        OnClickFrameBar,
        TweenInfo.new(MAX_CHARGE_TIME, Enum.EasingStyle.Linear),
        { Size = UDim2.new(1, 0, 1, 0) }
    )
    chargeTween:Play()
end

local function stopChargeTween()
    if chargeTween then
        chargeTween:Cancel()
        chargeTween = nil
    end
    OnClickFrameBar.Size = UDim2.new(0, 0, 1, 0)
end

local function applySprintToHumanoid()
    local humanoid = currentHumanoid
    if not humanoid then return end

    if sprintEnabled then
        humanoid.WalkSpeed = sprintWalkSpeed
    else
        humanoid.WalkSpeed = defaultWalkSpeed
    end
end

local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    currentHumanoid = humanoid
    defaultWalkSpeed = humanoid.WalkSpeed
    sprintWalkSpeed = math.max(defaultWalkSpeed + 6, math.floor(defaultWalkSpeed * 1.5))
    applySprintToHumanoid()

    loadAnimationTracks()
end

local function throw(chargeRatio)
    if not GameActive.Value then return false end
    if isAnyFrameVisible() then return false end
    if tick() - lastThrow < COOLDOWN then return false end
    lastThrow = tick()

    local clampedCharge = math.clamp(chargeRatio or 0, MIN_CHARGE_RATIO, MAX_CHARGE_RATIO)

    local ray = getAimRay()
    if not ray then return false end

    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    
    -- The server validates this physical origin. The camera is used only to
    -- determine the crosshair point, never as the projectile origin.
    local physicalOrigin = (head and head.Position) or (hrp and hrp.Position) or ray.Origin

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    if character then
        rayParams.FilterDescendantsInstances = { character }
    end

    -- 1. Raycast from camera to see where the player is aiming
    local camResult = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAYCAST_DISTANCE, rayParams)
    local targetPos = camResult and camResult.Position or (ray.Origin + ray.Direction * MAX_RAYCAST_DISTANCE)

    local trueDirection = ProjectileMath.NormalizeDirection(targetPos - physicalOrigin)
    if not trueDirection then return false end
    nextShotId += 1
    local shotId = string.format("%d_%d", player.UserId, nextShotId)

    playThrowAnimation()
    
    -- Instantly hide hand tool for feedback
    local equippedTool = character and character:FindFirstChildWhichIsA("Tool")
    if equippedTool then
        local toolHandle = equippedTool:FindFirstChild("Handle")
        if toolHandle then
            task.delay(0.15, function() if toolHandle then toolHandle.Transparency = 1 end end)
            task.delay(0.65, function() if toolHandle then toolHandle.Transparency = 0 end end)
        end
    end

    -- INSTANT ZERO-DELAY VISUAL PREDICTION
    local KnivesFolder = ReplicatedStorage:FindFirstChild("Knives")
    if KnivesFolder then
        if GameActive.Value == false then return end
        local visualOrigin = physicalOrigin + (trueDirection * VISUAL_OFFSET)
        local leaderstats = player:FindFirstChild("leaderstats")
        local equippedKnifeValue = leaderstats and leaderstats:FindFirstChild("EquippedKnife")
        local EquippedKnife = equippedKnifeValue and equippedKnifeValue.Value

        if EquippedKnife then
            local Template = KnivesFolder:FindFirstChild(EquippedKnife)
            if Template and Template:FindFirstChild("Handle") then
                local handle = Template.Handle:Clone()
                handle.CanCollide = false
                handle.CanQuery = false
                handle.Massless = true
                handle.CFrame = CFrame.lookAt(visualOrigin, visualOrigin + trueDirection)
                handle.Parent = workspace

                addTrail(handle)

                local actualDistance = ProjectileMath.MAX_DISTANCE
                local travelTime = actualDistance / ProjectileMath.GetSpeed(clampedCharge)
                local startTime = os.clock()

                local visualTravelDirection = trueDirection

                local conn
                conn = RunService.Heartbeat:Connect(function()
                    local elapsed = os.clock() - startTime
                    local progress = elapsed / travelTime

                    if progress >= 1 then
                        handle.CFrame = CFrame.lookAt(physicalOrigin + trueDirection * actualDistance, physicalOrigin + trueDirection * (actualDistance + 1))
                        Debris:AddItem(handle, 3)
                        conn:Disconnect()
                        predictedShots[shotId] = nil
                        return
                    end

                    local currentPos = visualOrigin + trueDirection * (ProjectileMath.GetSpeed(clampedCharge) * elapsed)
                    handle.CFrame = CFrame.lookAt(currentPos, currentPos + visualTravelDirection)
                end)

                Debris:AddItem(handle, LIFETIME)
                predictedShots[shotId] = {handle = handle, connection = conn}
            end
        end
    else
        warn("CLIENT PREDICTION FAILED: Please move your 'Knives' folder to ReplicatedStorage!")
    end

    ThrowKnifeRemote:FireServer(shotId, physicalOrigin, trueDirection, clampedCharge, os.clock())
    return true
end

local function stab()
    if tick() - lastStab < STAB_COOLDOWN then return false end
    if not hasKnifeEquipped() then return false end
    lastStab = tick()
    playStabAnimation()
    StabKnifeRemote:FireServer()
    return true
end

function CombatController.Init()
    if initialized then return end
    initialized = true

    -- Hide the server's delayed knife when it spawns so we only see our instant prediction
    CollectionService:GetInstanceAddedSignal("ServerKnife_" .. player.UserId):Connect(function(handle)
        handle.Transparency = 1
        for _, desc in ipairs(handle:GetDescendants()) do
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
                desc.Enabled = false
            elseif desc:IsA("BasePart") or desc:IsA("MeshPart") then
                desc.Transparency = 1
            end
        end
        -- Failsafe for trails that load a frame later
        handle.DescendantAdded:Connect(function(desc)
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
                desc.Enabled = false
            elseif desc:IsA("BasePart") or desc:IsA("MeshPart") then
                desc.Transparency = 1
            end
        end)
    end)
    CollectionService:GetInstanceAddedSignal("ServerKnifeVisual"):Connect(function(handle)
        handle.Transparency = 1
        for _, desc in ipairs(handle:GetDescendants()) do
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
                desc.Enabled = false
            elseif desc:IsA("BasePart") or desc:IsA("MeshPart") then
                desc.Transparency = 1
            end
        end
    end)

    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    end

    ThrewKnifeClient.OnClientEvent:Connect(function(result)
        uiAnimation()
        if typeof(result) ~= "table" or not result.shotId then return end
        if result.visualOnly then
            if result.shooterUserId ~= player.UserId
                and typeof(result.origin) == "Vector3"
                and typeof(result.direction) == "Vector3"
                and typeof(result.charge) == "number" then
                createKnifeVisual(result.origin, result.direction.Unit, result.charge, result.shotId, result.knifeName, result.destination)
            end
            return
        end
        local prediction = predictedShots[result.shotId]
        if not prediction then return end
        if prediction.connection then prediction.connection:Disconnect() end
        predictedShots[result.shotId] = nil
        if not result.accepted then
            prediction.handle:Destroy()
            return
        end
        local position = result.position
        if typeof(position) == "Vector3" then
            prediction.handle.CFrame = CFrame.lookAt(position, position + (result.normal or Vector3.zAxis))
            if result.hit and typeof(result.normal) == "Vector3" then
                stickKnife(prediction.handle, nil, position, result.normal)
            else
                Debris:AddItem(prediction.handle, 2)
            end
        end
    end)
end

function CombatController.BeginCharge()
    CombatController.Init()
    if charging then return false end
    if not hasKnifeEquipped() then return false end
    if isAnyFrameVisible() then return false end

    charging = true
    chargeStart = tick()
    chargeSessionId += 1
    startChargeTween()

    local sessionId = chargeSessionId
    task.delay(THROW_THRESHOLD, function()
        if charging and chargeSessionId == sessionId then
            playChargeAnimation()
        end
    end)

    return true
end

function CombatController.ReleaseCharge()
    CombatController.Init()
    if not charging then return false end

    charging = false
    local heldFor = tick() - chargeStart
    chargeSessionId += 1
    stopChargeTween()
    stopAllAnimations()

    if heldFor < THROW_THRESHOLD then
        return stab()
    end

    local ratio = math.clamp(heldFor / MAX_CHARGE_TIME, 0, 1)
    return throw(ratio)
end

function CombatController.CancelCharge()
    if not charging then return end
    charging = false
    chargeSessionId += 1
    stopChargeTween()
    stopAllAnimations()
end

function CombatController.IsCharging()
    return charging
end

function CombatController.SetTouchAimPosition(pos: Vector2?)
    touchAimPosition = pos
end

function CombatController.SetMobileShiftLock(enabled: boolean)
    mobileShiftLockEnabled = enabled
end

function CombatController.SetInputMode(isMobile: boolean)
    isMobileInput = isMobile
end

function CombatController.SetSprintEnabled(enabled: boolean)
    CombatController.Init()
    sprintEnabled = enabled == true
    applySprintToHumanoid()
    return sprintEnabled
end

function CombatController.ToggleSprint()
    return CombatController.SetSprintEnabled(not sprintEnabled)
end

function CombatController.GetSprintEnabled()
    return sprintEnabled
end

return CombatController