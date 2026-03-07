local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CombatController = require(script.Parent:WaitForChild("Modules"):WaitForChild("CombatController"))
local SprintState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SprintState"))

local UI = player:WaitForChild("PlayerGui"):WaitForChild("Main")
local MobileFrame = UI:WaitForChild("MobileFrame")
local EmoteFrame = UI:WaitForChild("EmoteFrame"):WaitForChild("background")

local ShiftLockToggled = false
local ShiftLockImage = MobileFrame:WaitForChild("ShiftLockToogled")

local OtherButtonsFrame = MobileFrame:WaitForChild("BasicControls")
local EmoteButton = OtherButtonsFrame:WaitForChild("Emote")

local JumpButton = OtherButtonsFrame:WaitForChild("Jump")
local SprintButton = OtherButtonsFrame:WaitForChild("Sprint")
local ThrowKnifeButton = OtherButtonsFrame:WaitForChild("Throw")
local ShiftLockButton = MobileFrame:WaitForChild("ShiftLock")

local MobileCrossHairImage = MobileFrame:WaitForChild("MobileCrosshair")

local ShiftLockUnlockedImage = "rbxassetid://13848680756"
local ShiftLockLockedImage = "rbxassetid://13848672949"

local ToggledOrActivatedColor = Color3.fromRGB(0, 184, 255)
local DefaultColor = Color3.fromRGB(255, 255, 255)

local currentHumanoid: Humanoid? = nil
local throwHolding = false
local touchHolding = false
local pendingTouch: InputObject? = nil
local pendingTouchStartPos: Vector2? = nil
local lastTouchAimPos: Vector2? = nil
local shiftLockConnection: RBXScriptConnection? = nil
local decided = false
local isMobile = false
local sprintToggled = false
local walkSpeedConnection: RBXScriptConnection? = nil
local jumpDebounce = false


local function updateMobileCrosshair(isVisible: boolean, pos: Vector2?)
    if isVisible then

        if ShiftLockToggled then
            return
        end

        MobileCrossHairImage.Visible = true
        if pos then
            MobileCrossHairImage.Position = UDim2.fromOffset(pos.X, pos.Y + 60) 
        else
            MobileCrossHairImage.Position = UDim2.fromScale(0.5, 0.5)
        end
    else
        MobileCrossHairImage.Visible = false
    end
end
------------------------------

local function getCharacter(): Model
    return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid(): Humanoid?
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getHrp(character: Model): BasePart?
    return character:FindFirstChild("HumanoidRootPart")
end

local function setButtonToggled(button: GuiObject, toggled: boolean)
    if not button:IsA("ImageButton") then return end
    button:WaitForChild("deco").ImageColor3 = toggled and ToggledOrActivatedColor or DefaultColor
end

local function updateShiftLockVisual()
    ShiftLockButton:WaitForChild("deco").Image = ShiftLockToggled and ShiftLockLockedImage or ShiftLockUnlockedImage
    ShiftLockButton:WaitForChild("deco").ImageColor3 = ShiftLockToggled and ToggledOrActivatedColor or DefaultColor
    ShiftLockButton:WaitForChild("deco").ImageTransparency = 0.5
    ShiftLockImage.Visible = ShiftLockToggled
end

local function updateSprintVisual()
    setButtonToggled(SprintButton, sprintToggled)
end

local function syncSprintStateFromHumanoid()
    sprintToggled = SprintState.GetEnabled()
    updateSprintVisual()
end

local function setSprintState(enabled: boolean)
    SprintState.SetEnabled(enabled)
    syncSprintStateFromHumanoid()
end

local function updateShiftLockLoop(enabled: boolean)
    if shiftLockConnection then
        shiftLockConnection:Disconnect()
        shiftLockConnection = nil
    end

    if not enabled then
        if currentHumanoid then
            currentHumanoid.AutoRotate = true
        end
        return
    end

    shiftLockConnection = RunService.RenderStepped:Connect(function()
        local character = player.Character
        local camera = workspace.CurrentCamera
        local humanoid = currentHumanoid

        if not character or not camera or not humanoid then return end
        local hrp = getHrp(character)
        if not hrp then return end

        local look = camera.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude <= 0.001 then return end

        humanoid.AutoRotate = false
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flatLook.Unit)
    end)
end

local function setShiftLock(enabled: boolean)
    ShiftLockToggled = enabled
    updateShiftLockVisual()
    updateShiftLockLoop(ShiftLockToggled)
    
    updateMobileCrosshair(ShiftLockToggled)

    if UserInputService.MouseEnabled then
        UserInputService.MouseBehavior = ShiftLockToggled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
    end
    
    CombatController.SetMobileShiftLock(ShiftLockToggled)
end

local function toggleEmoteFrame()
    EmoteFrame.Visible = not EmoteFrame.Visible
end

local function onThrowPressed()
    if throwHolding then return end
    throwHolding = true
    CombatController.BeginCharge()
    setButtonToggled(ThrowKnifeButton, true)
end

local function onThrowReleased()
    if not throwHolding then return end
    throwHolding = false
    setButtonToggled(ThrowKnifeButton, false)
    CombatController.ReleaseCharge()
end

local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    currentHumanoid = humanoid

    if walkSpeedConnection then
        walkSpeedConnection:Disconnect()
        walkSpeedConnection = nil
    end

    walkSpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        syncSprintStateFromHumanoid()
    end)

    syncSprintStateFromHumanoid()
    updateShiftLockLoop(ShiftLockToggled)
end

local TOUCH_DRAG_THRESHOLD = 50

local function touchOverGui(position: Vector2): boolean
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return false end

    local uiObjects = playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
    for _, obj in ipairs(uiObjects) do
        if obj:IsA("GuiButton") or obj:IsDescendantOf(MobileFrame) then
            return true
        end
    end
    return false
end

local function detectInputMode()
    if UserInputService.TouchEnabled then
        isMobile = true
        decided = true
        return
    end

    local inputConnection: RBXScriptConnection? = nil
    inputConnection = UserInputService.InputBegan:Connect(function(input)
        if decided then return end
        if input.UserInputType == Enum.UserInputType.Touch then
            isMobile = true
            decided = true
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            isMobile = false
            decided = true
        end

        if decided and inputConnection then
            inputConnection:Disconnect()
            inputConnection = nil
        end
    end)

    while not decided do task.wait() end
end

local function hideJumpButtonInTouchGui(container: Instance)
    local jumpButton = container:FindFirstChild("JumpButton", true)
    if jumpButton and jumpButton:IsA("GuiObject") then
        jumpButton.Visible = false
        jumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
            if jumpButton.Visible then jumpButton.Visible = false end
        end)
    end
end

local function disableRobloxDefaultJumpButton()
    local playerGui = player:WaitForChild("PlayerGui")
    local touchGui = playerGui:FindFirstChild("TouchGui")

    if touchGui then
        hideJumpButtonInTouchGui(touchGui)
        touchGui.DescendantAdded:Connect(function(descendant)
            if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") then
                descendant.Visible = false
                descendant:GetPropertyChangedSignal("Visible"):Connect(function()
                    if descendant.Visible then descendant.Visible = false end
                end)
            end
        end)
    end

    playerGui.ChildAdded:Connect(function(child)
        if child.Name == "TouchGui" then
            task.defer(function() hideJumpButtonInTouchGui(child) end)
            child.DescendantAdded:Connect(function(descendant)
                if descendant.Name == "JumpButton" and descendant:IsA("GuiObject") then
                    descendant.Visible = false
                end
            end)
        end
    end)
end

local function setUp()
    detectInputMode()
    
    CombatController.SetInputMode(isMobile)

    if not isMobile then
        MobileFrame.Visible = false
        return
    end

    MobileFrame.Visible = true
    updateMobileCrosshair(false) 
    
    disableRobloxDefaultJumpButton()
    CombatController.Init()
    updateShiftLockVisual()
    setButtonToggled(ThrowKnifeButton, false)

    EmoteButton.MouseButton1Up:Connect(toggleEmoteFrame)

    local function tryJump()
        if jumpDebounce then return end
        local humanoid = currentHumanoid or getHumanoid()
        if not humanoid then return end

        local state = humanoid:GetState()
        local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
        local canJump = grounded
            or state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.RunningNoPhysics
            or state == Enum.HumanoidStateType.Landed

        if not canJump then return end

        jumpDebounce = true
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        task.delay(0.6, function() jumpDebounce = false end)
    end

    JumpButton.MouseButton1Up:Connect(tryJump)
    JumpButton.Activated:Connect(tryJump)

    ShiftLockButton.MouseButton1Up:Connect(function()
        setShiftLock(not ShiftLockToggled)
    end)

    ThrowKnifeButton.MouseButton1Down:Connect(onThrowPressed)
    ThrowKnifeButton.MouseButton1Up:Connect(onThrowReleased)
    ThrowKnifeButton.MouseLeave:Connect(onThrowReleased)

    UserInputService.TouchStarted:Connect(function(input, _processed)
        if not isMobile or touchHolding or throwHolding then return end
        
        local pos = Vector2.new(input.Position.X, input.Position.Y)
        if touchOverGui(pos) then return end

        pendingTouch = input
        pendingTouchStartPos = pos
        lastTouchAimPos = pos
        CombatController.SetTouchAimPosition(pos)

        task.delay(0.15, function()
            if pendingTouch == input and not touchHolding then
                touchHolding = true
                CombatController.BeginCharge()
                updateMobileCrosshair(true, lastTouchAimPos)
            end
        end)
    end)

    UserInputService.TouchMoved:Connect(function(input, _processed)
        if pendingTouch ~= input then return end

        local currentPos = Vector2.new(input.Position.X, input.Position.Y)

        if touchHolding then
            lastTouchAimPos = currentPos
            CombatController.SetTouchAimPosition(currentPos)
            updateMobileCrosshair(true, currentPos)
            return
        end

        local delta = (currentPos - pendingTouchStartPos).Magnitude
        lastTouchAimPos = currentPos
        CombatController.SetTouchAimPosition(currentPos)

        if delta > TOUCH_DRAG_THRESHOLD then
            pendingTouch = nil
            pendingTouchStartPos = nil
        end
    end)

    UserInputService.TouchEnded:Connect(function(input, _processed)
        if not isMobile or pendingTouch ~= input then return end

        local wasCharging = touchHolding
        pendingTouch = nil
        pendingTouchStartPos = nil
        touchHolding = false

        if wasCharging then
            CombatController.ReleaseCharge()
        end
        
        lastTouchAimPos = nil
        CombatController.SetTouchAimPosition(nil)
        
        updateMobileCrosshair(ShiftLockToggled)
    end)

    UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
        if not isMobile or processedByUI or throwHolding or touchHolding then return end

        local cam = workspace.CurrentCamera
        if cam then
            local screenPos: Vector2?
            if typeof(position) == "Vector3" then
                local vpPos = cam:WorldToViewportPoint(position)
                screenPos = Vector2.new(vpPos.X, vpPos.Y)
            elseif typeof(position) == "Vector2" then
                screenPos = position
            end

            if screenPos then
                lastTouchAimPos = screenPos
                CombatController.SetTouchAimPosition(lastTouchAimPos)
            end
        end
        
        CombatController.BeginCharge()
        task.defer(function()
            CombatController.ReleaseCharge()
            lastTouchAimPos = nil
            CombatController.SetTouchAimPosition(nil)
        end)
    end)

    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    else
        updateSprintVisual()
    end
end

setUp()
return {}