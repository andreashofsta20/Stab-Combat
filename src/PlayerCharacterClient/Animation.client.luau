local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SprintState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SprintState"))

local player = Players.LocalPlayer
local leaderstats = player:WaitForChild("leaderstats")
local KeyBindsFolder = leaderstats:WaitForChild("KeyBinds")
local PlayerGui = player:WaitForChild("PlayerGui")
local MainUI = PlayerGui:WaitForChild("Main")
local MobileFrame = MainUI:WaitForChild("MobileFrame")
local MobileControls = MobileFrame:WaitForChild("BasicControls")
local MobileSprintButton = MobileControls:WaitForChild("Sprint")

local function loadCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then
		return
	end
	local anim = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not anim then
		return
	end
	return char, hum, anim
end

local character, humanoid, animator = loadCharacter()
if not character or not humanoid or not animator then return end

local WALKING_ANIMATION = "rbxassetid://79598872056948"
local RUNNING_ANIMATION = "rbxassetid://117319187680453"
local IDLE_ANIMATION   = "rbxassetid://88520413958295"
local CROUCH_IDLE_ANIMATION = "rbxassetid://115606571521361"
local CROUCH_WALK_ANIMATION = "rbxassetid://76062126805596"
local SLIDE_ANIMATION = "rbxassetid://75213495477739"

local WALK_SPEED = 16
local RUN_SPEED = 32
local CROUCH_SPEED = 8
local SLIDE_SPEED = 60 -- Faster initial slide speed
local SLIDE_MAX_DURATION = 0.7
local SLIDE_END_SPEED = 12 -- Slower than walk speed at the end
local SLIDE_COOLDOWN = 1 -- Cooldown time in seconds before you can slide again

local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = WALKING_ANIMATION
local runAnim = Instance.new("Animation")
runAnim.AnimationId = RUNNING_ANIMATION
local idleAnim = Instance.new("Animation")
idleAnim.AnimationId = IDLE_ANIMATION
local slideAnim = Instance.new("Animation")
slideAnim.AnimationId = SLIDE_ANIMATION

local crouchAnim = Instance.new("Animation")
crouchAnim.AnimationId = CROUCH_IDLE_ANIMATION
local crouchWalkAnim = Instance.new("Animation")
crouchWalkAnim.AnimationId = CROUCH_WALK_ANIMATION

local walkTrack = animator:LoadAnimation(walkAnim)
local runTrack = animator:LoadAnimation(runAnim)
local idleTrack:AnimationTrack = animator:LoadAnimation(idleAnim)
idleTrack.Priority = Enum.AnimationPriority.Action

local crouchIdleTrack = animator:LoadAnimation(crouchAnim)
local crouchWalkTrack = animator:LoadAnimation(crouchWalkAnim)
crouchIdleTrack.Priority = Enum.AnimationPriority.Action
crouchWalkTrack.Priority = Enum.AnimationPriority.Action

local slideTrack = animator:LoadAnimation(slideAnim)
slideTrack.Priority = Enum.AnimationPriority.Action

local isSprinting = false
local isMoving = false
local crouching = false
local sliding = false
local mobileSprintToggled = false
local keyboardSprintHeld = false
local slideStartTime = 0
local slideConnection = nil
local lastSlideTime = 0 

local function playIdle()
	if not idleTrack.IsPlaying then
		idleTrack:Play()
	end
end

local function stopIdle()
	if idleTrack.IsPlaying then
		idleTrack:Stop()
	end
end

local function startSprinting()
	if crouching or sliding then
		return false
	end
	isSprinting = true
	humanoid.WalkSpeed = RUN_SPEED

	if isMoving then
		if walkTrack.IsPlaying then walkTrack:Stop() end
		if not runTrack.IsPlaying then runTrack:Play() end
	end

	return true
end

local function stopSprinting()
	isSprinting = false
	humanoid.WalkSpeed = WALK_SPEED

	if isMoving then
		if runTrack.IsPlaying then runTrack:Stop() end
		if not walkTrack.IsPlaying then walkTrack:Play() end
	end

	return false
end

SprintState.SetController(function(enabled: boolean)
	if enabled then
		return startSprinting()
	else
		return stopSprinting()
	end
end)

local function stopSliding()
	if not sliding then return end

	sliding = false
	lastSlideTime = tick()

	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end

	if slideTrack.IsPlaying then slideTrack:Stop() end

	humanoid.WalkSpeed = isSprinting and RUN_SPEED or WALK_SPEED

	if isMoving then
		if isSprinting then
			if not runTrack.IsPlaying then runTrack:Play() end
		else
			if not walkTrack.IsPlaying then walkTrack:Play() end
		end
	else
		playIdle()
	end
end

local function startSliding()
	local currentTime = tick()
	if currentTime - lastSlideTime < SLIDE_COOLDOWN then
		return 
	end

	if not isSprinting or crouching or sliding then return end

	sliding = true
	slideStartTime = currentTime
	humanoid.WalkSpeed = SLIDE_SPEED

	if walkTrack.IsPlaying then walkTrack:Stop() end
	if runTrack.IsPlaying then runTrack:Stop() end
	if idleTrack.IsPlaying then idleTrack:Stop() end

	if not slideTrack.IsPlaying then slideTrack:Play() end

	slideConnection = RunService.Heartbeat:Connect(function()
		if sliding then
			local slideTime = tick() - slideStartTime
			local progress = slideTime / SLIDE_MAX_DURATION

			local currentSpeed = SLIDE_SPEED - (SLIDE_SPEED - SLIDE_END_SPEED) * progress
			humanoid.WalkSpeed = math.max(currentSpeed, SLIDE_END_SPEED)

			if slideTime >= SLIDE_MAX_DURATION then
				stopSliding()
			end
		end
	end)
end

humanoid.Running:Connect(function(speed)
	isMoving = speed > 0.1

	if sliding then
		return 
	end

	if crouching then
		if isMoving then
			if not crouchWalkTrack.IsPlaying then crouchWalkTrack:Play() end
			if crouchIdleTrack.IsPlaying then crouchIdleTrack:Stop() end
		else
			if crouchWalkTrack.IsPlaying then crouchWalkTrack:Stop() end
			if not crouchIdleTrack.IsPlaying then crouchIdleTrack:Play() end
		end
		return
	end

	if isMoving then
		stopIdle()
		if isSprinting then
			if not runTrack.IsPlaying then runTrack:Play() end
			if walkTrack.IsPlaying then walkTrack:Stop() end
		else
			if not walkTrack.IsPlaying then walkTrack:Play() end
			if runTrack.IsPlaying then runTrack:Stop() end
		end
	else
		if walkTrack.IsPlaying then walkTrack:Stop() end
		if runTrack.IsPlaying then runTrack:Stop() end
		playIdle()
	end
end)

local function startCrouching()
	if sliding then return end
	crouching = true
	humanoid.WalkSpeed = CROUCH_SPEED

	if idleTrack.IsPlaying then idleTrack:Stop() end
	if walkTrack.IsPlaying then walkTrack:Stop() end
	if runTrack.IsPlaying then runTrack:Stop() end

	if isMoving then
		if not crouchWalkTrack.IsPlaying then crouchWalkTrack:Play() end
	else
		if not crouchIdleTrack.IsPlaying then crouchIdleTrack:Play() end
	end
end

local function stopCrouching()
	crouching = false
	humanoid.WalkSpeed = isSprinting and RUN_SPEED or WALK_SPEED

	if crouchIdleTrack.IsPlaying then crouchIdleTrack:Stop() end
	if crouchWalkTrack.IsPlaying then crouchWalkTrack:Stop() end

	if isMoving then
		if isSprinting then
			if not runTrack.IsPlaying then runTrack:Play() end
		else
			if not walkTrack.IsPlaying then walkTrack:Play() end
		end
	else
		playIdle()
	end
end

local function crouchAction(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then
		startCrouching()
	elseif inputState == Enum.UserInputState.End then
		stopCrouching()
	end
	return Enum.ContextActionResult.Sink
end

local function slideAction(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then
		startSliding()
	elseif inputState == Enum.UserInputState.End then
		stopSliding()
	end
	return Enum.ContextActionResult.Sink
end

local function updateSprintFromInput()
	local shouldSprint = mobileSprintToggled or keyboardSprintHeld
    print("Updating sprint state. Mobile toggled:", mobileSprintToggled, "Keyboard held:", keyboardSprintHeld, "Should sprint:", shouldSprint)
	SprintState.SetEnabled(shouldSprint)
	MobileSprintButton:SetAttribute("SprintToggled", shouldSprint)
    print("Sprint state updated. Current sprint enabled:", SprintState.GetEnabled())
end

local function sprintAction(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then
		keyboardSprintHeld = true
		updateSprintFromInput()
	elseif inputState == Enum.UserInputState.End then
		keyboardSprintHeld = false
		updateSprintFromInput()
	end
	return Enum.ContextActionResult.Pass
end

MobileSprintButton:SetAttribute("SprintToggled", false)
MobileSprintButton.MouseButton1Up:Connect(function()
    print("Mobile sprint button clicked")
	mobileSprintToggled = not mobileSprintToggled
    print("Mobile sprint toggled:", mobileSprintToggled)
	updateSprintFromInput()
end)

local function parseKeyCode(keycodeString)
	if not keycodeString or keycodeString == "" then
		return nil
	end

	local keyName = keycodeString:match("Enum%.KeyCode%.(.+)")
	if keyName and Enum.KeyCode[keyName] then
		return Enum.KeyCode[keyName]
	end
	return nil
end

local function initializeCrouchKeybind()
	local crouchKeyBind = KeyBindsFolder:WaitForChild("Crouch")

	if crouchKeyBind.Value == "" or crouchKeyBind.Value == nil then
		task.wait(0.1)
	end

	local crouchKey = parseKeyCode(crouchKeyBind.Value) or Enum.KeyCode.LeftControl 

	if crouchKey then
		ContextActionService:BindAction("CrouchAction", crouchAction, false, crouchKey)
	else
	end

	return crouchKey
end

local crouchKey = initializeCrouchKeybind()

local function initializeSlideKeybind()
	local slideKeyBind = KeyBindsFolder:WaitForChild("Slide")

	if slideKeyBind.Value == "" or slideKeyBind.Value == nil then
		task.wait(0.1)
	end

	local slideKey = parseKeyCode(slideKeyBind.Value) or Enum.KeyCode.C

	if slideKey then
		ContextActionService:BindAction("SlideAction", slideAction, false, slideKey)
	else
	end

	return slideKey
end

local slideKey = initializeSlideKeybind()

local SPRINT_PRIORITY = Enum.ContextActionPriority.High.Value + 1

local function initializeSprintKeybind()
	local sprintKeyBind = KeyBindsFolder:WaitForChild("Sprint")

	if sprintKeyBind.Value == "" or sprintKeyBind.Value == nil then
		task.wait(0.1)
	end

	local sprintKey = parseKeyCode(sprintKeyBind.Value) or Enum.KeyCode.LeftShift 

	if sprintKey then
		ContextActionService:BindActionAtPriority(
			"SprintAction",
			sprintAction,
			false,
			SPRINT_PRIORITY,
			sprintKey
		)
	else
	end

	return sprintKey
end

local sprintKey = initializeSprintKeybind()

KeyBindsFolder:WaitForChild("Sprint").Changed:Connect(function()
	local newValue = KeyBindsFolder.Sprint.Value
	local newKey = parseKeyCode(newValue)
	if newKey then
		ContextActionService:UnbindAction("SprintAction")
		ContextActionService:BindActionAtPriority(
			"SprintAction",
			sprintAction,
			false,
			SPRINT_PRIORITY,
			newKey
		)
		sprintKey = newKey
	else
	end
end)

KeyBindsFolder:WaitForChild("Crouch").Changed:Connect(function()
	local newValue = KeyBindsFolder.Crouch.Value
	local newKey = parseKeyCode(newValue)
	if newKey then
		ContextActionService:UnbindAction("CrouchAction")
		ContextActionService:BindAction("CrouchAction", crouchAction, false, newKey)
		crouchKey = newKey
	else
	end
end)

local slideKeyBindValue = KeyBindsFolder:WaitForChild("Slide")
if slideKeyBindValue then
	slideKeyBindValue.Changed:Connect(function()
		local newValue = slideKeyBindValue.Value
		local newKey = parseKeyCode(newValue)
		if newKey then
			ContextActionService:UnbindAction("SlideAction")
			ContextActionService:BindAction("SlideAction", slideAction, false, newKey)
			slideKey = newKey
		else
		end
	end)
end

player.CharacterAdded:Connect(function()
	local char, hum, anim = loadCharacter()
	if not char or not hum or not anim then return end

	character = char
	humanoid = hum
	animator = anim

	walkTrack = animator:LoadAnimation(walkAnim)
	runTrack = animator:LoadAnimation(runAnim)
	idleTrack = animator:LoadAnimation(idleAnim)
	idleTrack.Priority = Enum.AnimationPriority.Action

	crouchIdleTrack = animator:LoadAnimation(crouchAnim)
	crouchWalkTrack = animator:LoadAnimation(crouchWalkAnim)
	crouchIdleTrack.Priority = Enum.AnimationPriority.Action
	crouchWalkTrack.Priority = Enum.AnimationPriority.Action

	slideTrack = animator:LoadAnimation(slideAnim)
	slideTrack.Priority = Enum.AnimationPriority.Action

	lastSlideTime = 0
end)