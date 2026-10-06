local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage.Modules.KnifeConfig)
local EffectsConfig = require(ReplicatedStorage.Modules.KnifeEffectsConfig)
local KnifeEffects = require(script.Parent.KnifeEffects)
local KnifeVisual = require(script.Parent.KnifeVisual)
local KnifeHint = require(script.Parent.KnifeHint)
local KnifeViewmodel = require(script.Parent.KnifeViewmodel)
local SprintState = require(ReplicatedStorage.Modules.SprintState)
local SoundHandlerModule = require(script.Parent:WaitForChild("SoundHandler"))
local ProjectileMath = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProjectileMath"))
local WeaponRaycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)

local player = Players.LocalPlayer

local touchAimPosition: Vector2? = nil
local mobileShiftLockEnabled = false 
local isMobileInput = false

local COOLDOWN = Config.Throw.Cooldown
local STAB_COOLDOWN = Config.Stab.Cooldown
local MAX_CHARGE_TIME = Config.Throw.MaxChargeTime
local MIN_CHARGE_RATIO = 0
local MAX_CHARGE_RATIO = 1
local MAX_RAYCAST_DISTANCE = ProjectileMath.MAX_DISTANCE
local THROW_THRESHOLD = Config.Throw.HoldThreshold

-- VISUAL SETTINGS (Matching Server for prediction)
local VISUAL_OFFSET = Config.Presentation.VisualOffset
local LIFETIME = Config.Presentation.Lifetime

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
local lastThrow = -math.huge
local lastStab = -math.huge
local lastAction = -math.huge
local characterConnections = {}
local handleVisibility = {}
local animationGeneration = 0
local activeTween
local chargeTween
local charging = false
local chargeStart = 0
local chargeSessionId = 0
local nextShotId = 0
local predictedShots = {}

local chargeTrack = nil
local chargeHoldTrack = nil
local throwTrack = nil
local stabTrack = nil

local currentHumanoid: Humanoid? = nil
local equippedKnife, rootJoint, rightShoulder
local thrownTool, stabbedTool
local firstPersonAction = {} -- reused by the render callback; no frame-by-frame table allocation

local function refreshKnife(character)
    local nextTool
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and KnivesFolder:FindFirstChild(child.Name) then nextTool = child; break end
        end
    end
    if equippedKnife ~= nextTool then KnifeViewmodel.Clear(); equippedKnife = nextTool end
end

local function animationFrame(joint)
    if not joint or not joint.Parent or not joint:IsA("Motor6D") or not joint.Part0 or not joint.Part1 then return nil end
    local basis = joint.C0.Rotation
    return basis * joint.Transform * basis:Inverse()
end

local function isAnyFrameVisible()
    if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return true end
    for _, child in ipairs(FramesFolder:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible == true then
            return true
        end
    end
    local emote = MainUi:FindFirstChild("EmoteFrame")
    local background = emote and emote:FindFirstChild("background")
    return background ~= nil and background.Visible
end

local function removePrediction(id)
    local prediction = predictedShots[id]
    if not prediction then return end
    if prediction.visual then prediction.visual.model:Destroy() end
    predictedShots[id] = nil
end

local function retirePrediction(prediction)
    prediction.retireToken = (prediction.retireToken or 0) + 1
    local token = prediction.retireToken
    local seconds = (prediction.normal ~= nil or not prediction.confirmed)
        and Config.Presentation.StuckSeconds or Config.Presentation.MissSeconds
    task.delay(seconds, function()
        if predictedShots[prediction.id] == prediction and prediction.retireToken == token then removePrediction(prediction.id) end
    end)
end

local function finishImpact(prediction)
    if prediction.normal then
        KnifeVisual.Stick(prediction.visual, prediction.destination, prediction.direction, prediction.normal)
        if not prediction.impacted then
            prediction.impacted = true
            if not prediction.suppressVFX then KnifeEffects.Impact(prediction.destination, prediction.normal, prediction.effects) end
        end
    else
        KnifeVisual.Fly(prediction.visual, prediction.destination, prediction.direction)
    end
end

local function updateKnifeVisuals(now)
    -- All flying knives share the controller's existing Heartbeat. Stuck
    -- knives stop moving and retain only their bounded retirement timer.
    for shotId, prediction in pairs(predictedShots) do
        if not prediction.arrived then
            local visual = prediction.visual
            if not visual.model.Parent or now - prediction.started > LIFETIME then
                removePrediction(shotId)
                continue
            end
            local distance = math.max(0, (prediction.destination - prediction.origin):Dot(prediction.direction))
            local travelled = math.min(distance, VISUAL_OFFSET + prediction.speed * (now - prediction.started))
            KnifeVisual.Fly(visual, prediction.origin + prediction.direction * travelled, prediction.direction)
            if travelled >= distance then
                prediction.arrived = true
                prediction.stopEffects()
                finishImpact(prediction)
                retirePrediction(prediction)
            end
        end
    end
end

local function createKnifeVisual(origin, direction, charge, shotId, knifeName, destination, normal, sourceTool, confirmed, suppressVFX)
    local camera = workspace.CurrentCamera
    if camera and (origin - camera.CFrame.Position).Magnitude > EffectsConfig.MaxEffectDistance
        and destination and (destination - camera.CFrame.Position).Magnitude > EffectsConfig.MaxEffectDistance then return end
    -- Repeated observer packets must replace their visual without orphaning it.
    if predictedShots[shotId] then removePrediction(shotId) end
    local count, oldestId, oldestTime = 0, nil, math.huge
    for id, prediction in pairs(predictedShots) do
        count += 1
        if prediction.started < oldestTime then oldestId, oldestTime = id, prediction.started end
    end
    if count >= Config.Presentation.MaxVisuals and oldestId then removePrediction(oldestId) end
    local stats = player:FindFirstChild("leaderstats")
    local value = stats and stats:FindFirstChild("EquippedKnife")
    local template = sourceTool or KnivesFolder:FindFirstChild(knifeName or (value and value.Value) or "")
    if not template then return end
    local effects = EffectsConfig.Get(template.Name)
    local visual = KnifeVisual.Create(template, effects)
    if not visual then warn("[Knife] No projectile geometry for " .. template.Name); return end
    KnifeVisual.Fly(visual, origin, direction)
    local stopEffects = suppressVFX and function() end or KnifeEffects.Attach(visual.trailAnchor, effects)
    visual.model.Parent = workspace
    local prediction = {
        id = shotId, visual = visual, started = os.clock(), origin = origin, direction = direction,
        destination = destination or ProjectileMath.GetPosition(origin, direction, ProjectileMath.MAX_FLIGHT_TIME, charge),
        speed = ProjectileMath.GetSpeed(charge), normal = normal,
        effects = effects, stopEffects = stopEffects, confirmed = confirmed == true or normal ~= nil,
        suppressVFX = suppressVFX == true,
    }
    predictedShots[shotId] = prediction
    return prediction
end

function CombatController.GetAimScreenPosition()
    local cam = workspace.CurrentCamera
    if not cam then return UserInputService:GetMouseLocation() end
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or mobileShiftLockEnabled then return cam.ViewportSize / 2 end
    if isMobileInput then return touchAimPosition or cam.ViewportSize / 2 end
    return UserInputService:GetMouseLocation()
end
local function getAimRay()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local position = CombatController.GetAimScreenPosition()
    return cam:ViewportPointToRay(position.X, position.Y)
end

local function hasKnifeEquipped()
    return player.Character ~= nil and equippedKnife ~= nil and equippedKnife.Parent == player.Character
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

local function loadAnimationTracks(character, generation)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid or player.Character ~= character or generation ~= animationGeneration then return end
    local animator
    repeat
        animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 2)
    until animator or player.Character ~= character or generation ~= animationGeneration or humanoid.Health <= 0
    if not animator or player.Character ~= character or generation ~= animationGeneration then return end
    -- All character tracks use the server's replicated Animator.
    for attempt = 1, 3 do
        local tracks = {}
        local ok = pcall(function()
            for _, animation in ipairs({ChargeAnimation, ChargeLoopAnimation, ReleaseKnifeAnimation, StabAnimation}) do
                local track = animator:LoadAnimation(animation)
                track.Priority = Enum.AnimationPriority.Action
                table.insert(tracks, track)
            end
        end)
        if ok and player.Character == character and generation == animationGeneration then
            chargeTrack, chargeHoldTrack, throwTrack, stabTrack = tracks[1], tracks[2], tracks[3], tracks[4]
            return
        end
        for _, track in ipairs(tracks) do track:Destroy() end
        if player.Character ~= character or generation ~= animationGeneration then return end
        task.wait(attempt * 0.5)
    end
    warn("[Knife] Combat animations unavailable for this character")
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

    task.delay(chargeTrack.Length > 0 and chargeTrack.Length or Config.Presentation.ChargeTransitionSeconds, function()
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
    activeTween = tweenIn
    local conn1, conn2
    conn1 = tweenIn.Completed:Connect(function(state)
        if conn1 then conn1:Disconnect() end
        if state ~= Enum.PlaybackState.Completed then
            if conn2 then conn2:Disconnect() end
            return
        end
        activeTween = tweenOut
        tweenOut:Play()
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

local function clearCharacter()
    animationGeneration += 1
    CombatController.CancelCharge()
    KnifeViewmodel.Clear()
    equippedKnife, rootJoint, rightShoulder, thrownTool, stabbedTool = nil, nil, nil, nil, nil
    KnifeHint.Update(false, isMobileInput)
    for _, connection in ipairs(characterConnections) do connection:Disconnect() end
    table.clear(characterConnections)
    for _, track in pairs({chargeTrack, chargeHoldTrack, throwTrack, stabTrack}) do track:Stop(0); track:Destroy() end
    chargeTrack, chargeHoldTrack, throwTrack, stabTrack, currentHumanoid = nil, nil, nil, nil, nil
    for id in pairs(predictedShots) do removePrediction(id) end
    for handle, record in pairs(handleVisibility) do
        if handle.Parent then handle.LocalTransparencyModifier = record.original end
    end
    table.clear(handleVisibility)
    if activeTween then activeTween:Cancel(); activeTween = nil end
    lastThrow, lastStab, lastAction = -math.huge, -math.huge, -math.huge
end
local function onCharacterAdded(character)
    clearCharacter()
    local generation, humanoid = animationGeneration, nil
    repeat
        humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 2)
    until humanoid or player.Character ~= character or generation ~= animationGeneration
    if not humanoid or player.Character ~= character or generation ~= animationGeneration then return end
    currentHumanoid = humanoid
    refreshKnife(character)
    local function bindJoints()
        local root, torso = character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Torso")
        rootJoint = root and root:FindFirstChild("RootJoint")
        rightShoulder = torso and torso:FindFirstChild("Right Shoulder")
    end
    bindJoints()
    table.insert(characterConnections, character.DescendantAdded:Connect(function(item)
        if item.Name == "RootJoint" or item.Name == "Right Shoulder" then bindJoints() end
    end))
    table.insert(characterConnections, humanoid.Died:Connect(function()
        CombatController.CancelCharge()
        KnifeViewmodel.Clear()
        KnifeHint.Update(false, isMobileInput)
    end))
    table.insert(characterConnections, character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then refreshKnife(character) end
    end))
    table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            refreshKnife(character)
            CombatController.CancelCharge()
            KnifeHint.Update(false, isMobileInput)
            for part, record in pairs(handleVisibility) do
                if record.tool == child then
                    if part.Parent then part.LocalTransparencyModifier = record.original end
                    handleVisibility[part] = nil
                end
            end
        end
    end))
    task.spawn(loadAnimationTracks, character, animationGeneration)
end

local function throw(chargeRatio)
    if not GameActive.Value then return false end
    if isAnyFrameVisible() then return false end
    if not hasKnifeEquipped() or not currentHumanoid or currentHumanoid.Health <= 0 or player:GetAttribute("InRound") ~= true then return false end
    local now = os.clock()
    if now - lastThrow < COOLDOWN or now - lastAction < Config.ActionMinGap then return false end

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
    rayParams.FilterDescendantsInstances = RagdollQuery.Exclude(character and { character } or {})

    -- 1. Raycast from camera to see where the player is aiming
    local aimOrigin = WeaponRaycast.GetAimOrigin(ray.Origin, ray.Direction, physicalOrigin)
    local camResult = workspace:Raycast(aimOrigin, ray.Direction * MAX_RAYCAST_DISTANCE, rayParams)
    local targetPos = camResult and camResult.Position or (aimOrigin + ray.Direction * MAX_RAYCAST_DISTANCE)

    local trueDirection = ProjectileMath.NormalizeDirection(targetPos - physicalOrigin)
    if not trueDirection then return false end
    nextShotId += 1
    local shotId = string.format("%d_%d", player.UserId, nextShotId)

    playThrowAnimation()
    local throwingTool = equippedKnife
    local effectSettings = EffectsConfig.Get(throwingTool and throwingTool.Name or "")
    KnifeEffects.ThrowSound(physicalOrigin, clampedCharge, effectSettings, SoundHandlerModule.Sounds.ThrowKnife)
    
    -- Instantly hide hand tool for feedback
    local equippedTool = equippedKnife
    if equippedTool then
        for _, toolHandle in ipairs(equippedTool:GetDescendants()) do
            if not toolHandle:IsA("BasePart") then continue end
            local record = handleVisibility[toolHandle] or {
                original = KnifeViewmodel.GetOriginalTransparency(toolHandle), token = 0, tool = equippedTool, hidden = false,
            }
            handleVisibility[toolHandle] = record
            record.token += 1
            local token = record.token
            task.delay(Config.Presentation.HideHandleDelay, function()
                if handleVisibility[toolHandle] == record and record.token == token and equippedTool.Parent == player.Character then
                    record.hidden = true
                    toolHandle.LocalTransparencyModifier = 1
                end
            end)
            task.delay(Config.Presentation.ReturnHandleDelay, function()
                if handleVisibility[toolHandle] == record and record.token == token then
                    -- The camera model may have first hidden this part while
                    -- the thrown weapon was already invisible. Update its
                    -- restore snapshot before the real handle returns.
                    KnifeViewmodel.SetOriginalTransparency(toolHandle, record.original)
                    if toolHandle.Parent then toolHandle.LocalTransparencyModifier = record.original end
                    handleVisibility[toolHandle] = nil
                end
            end)
        end
    end

    local predictedHit = workspace:Raycast(physicalOrigin, trueDirection * MAX_RAYCAST_DISTANCE, rayParams)
    -- Predict visible cover immediately; damage and the impact burst still
    -- require the server. Close walls no longer wait a network round trip.
    createKnifeVisual(physicalOrigin, trueDirection, clampedCharge, shotId, equippedTool.Name,
        predictedHit and predictedHit.Position, nil, equippedTool, false, KnifeViewmodel.IsFirstPerson(equippedTool))
    lastThrow, lastAction = now, now
    thrownTool = equippedTool
    uiAnimation()
    ThrowKnifeRemote:FireServer(shotId, physicalOrigin, trueDirection, clampedCharge, os.clock())
    return true
end

local function stab()
    if not GameActive.Value or player:GetAttribute("InRound") ~= true or isAnyFrameVisible() then return false end
    if not currentHumanoid or currentHumanoid.Health <= 0 then return false end
    local now = os.clock()
    if now - lastStab < STAB_COOLDOWN or now - lastAction < Config.ActionMinGap then return false end
    if not hasKnifeEquipped() then return false end
    lastStab, lastAction = now, now
    stabbedTool = equippedKnife
    playStabAnimation()
    StabKnifeRemote:FireServer()
    return true
end

function CombatController.Init()
    if initialized then return end
    initialized = true
    KnifeHint.Init()
    KnifeViewmodel.Init()

    KnivesFolder.ChildAdded:Connect(function() refreshKnife(player.Character) end)

    player.CharacterRemoving:Connect(clearCharacter)
    UserInputService.WindowFocusReleased:Connect(CombatController.CancelCharge)
    UserInputService.TextBoxFocused:Connect(CombatController.CancelCharge)
    GuiService.MenuOpened:Connect(CombatController.CancelCharge)
    GameActive.Changed:Connect(function()
        if not GameActive.Value then CombatController.CancelCharge(); KnifeHint.Update(false, isMobileInput) end
    end)
    RunService.Heartbeat:Connect(function()
        updateKnifeVisuals(os.clock())
        if charging and (isAnyFrameVisible() or not hasKnifeEquipped()) then CombatController.CancelCharge() end
        KnifeHint.Update(GameActive.Value and player:GetAttribute("InRound") == true
            and player:GetAttribute("DataReady") == true and hasKnifeEquipped()
            and currentHumanoid and currentHumanoid.Health > 0 and not isAnyFrameVisible(),
            isMobileInput, charging and math.clamp((os.clock() - chargeStart) / MAX_CHARGE_TIME, 0, 1) or nil,
            CombatController.GetAimScreenPosition())
    end)
    RunService:BindToRenderStep("KnifeFirstPerson", Enum.RenderPriority.Camera.Value + 3, function(dt)
        local tool = hasKnifeEquipped() and equippedKnife or nil
        local now = os.clock()
        local heldFor = charging and math.max(0, now - chargeStart) or 0
        firstPersonAction.charging = charging and heldFor >= THROW_THRESHOLD
        firstPersonAction.holdingCharge = charging
        firstPersonAction.charge = math.clamp(heldFor / MAX_CHARGE_TIME, 0, 1)
        firstPersonAction.throwElapsed = tool and tool == thrownTool and now - lastThrow or nil
        firstPersonAction.stabElapsed = tool and tool == stabbedTool and now - lastStab or nil
        KnifeViewmodel.Update(tool, currentHumanoid and currentHumanoid.Health > 0
            and not isAnyFrameVisible(), dt, animationFrame(rootJoint), animationFrame(rightShoulder), firstPersonAction)
        -- The camera model restores its original hiding mask when zooming out.
        -- Keep the real knife hidden for its existing temporary throw window.
        for part, record in pairs(handleVisibility) do
            if record.hidden and part.Parent and part.LocalTransparencyModifier ~= 1 then part.LocalTransparencyModifier = 1 end
        end
    end)
    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    end

    ThrewKnifeClient.OnClientEvent:Connect(function(result)
        if typeof(result) ~= "table" or not result.shotId then return end
        if result.visualOnly then
            if result.shooterUserId ~= player.UserId
                and typeof(result.origin) == "Vector3"
                and typeof(result.direction) == "Vector3"
                and typeof(result.charge) == "number"
                and ProjectileMath.IsFiniteVector(result.destination) then
                local shooter = Players:GetPlayerByUserId(result.shooterUserId)
                local tool = shooter and shooter.Character and shooter.Character:FindFirstChild(result.knifeName)
                local visualId = string.format("observer_%s_%s", result.shooterUserId, result.shotId)
                createKnifeVisual(result.origin, result.direction.Unit, result.charge, visualId, result.knifeName, result.destination, result.normal, tool, true)
            end
            return
        end
        local prediction = predictedShots[result.shotId]
        if not prediction then return end
        if not result.accepted then removePrediction(result.shotId); return end
        prediction.confirmed = true
        -- Keep visible flight instead of teleporting to the impact on ack.
        if ProjectileMath.IsFiniteVector(result.position) then
            prediction.destination, prediction.normal = result.position, result.normal
            -- A close impact can arrive before the acknowledgement on a slow
            -- connection. Reconcile the stopped blade and emit its burst once.
            if prediction.arrived then
                finishImpact(prediction)
                retirePrediction(prediction)
            end
        end
    end)
end

function CombatController.BeginCharge()
	KnifeViewmodel.InterruptInspect()
    CombatController.Init()
    if charging or not currentHumanoid or currentHumanoid.Health <= 0 then return false end
    if player:GetAttribute("DataReady") ~= true then return false end
    if not hasKnifeEquipped() then return false end
    if isAnyFrameVisible() then return false end

    charging = true
    chargeStart = os.clock()
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
    local heldFor = os.clock() - chargeStart
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

function CombatController.Stab()
	KnifeViewmodel.InterruptInspect()
    if charging then return false end
    return stab()
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

function CombatController.SetSprintEnabled(enabled)
    SprintState.SetEnabled(enabled == true)
    return SprintState.GetEnabled()
end
function CombatController.ToggleSprint()
    return CombatController.SetSprintEnabled(not SprintState.GetEnabled())
end
function CombatController.GetSprintEnabled()
    return SprintState.GetEnabled()
end
return CombatController
