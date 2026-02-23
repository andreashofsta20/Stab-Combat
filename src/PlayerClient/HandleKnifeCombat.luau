local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local COOLDOWN = 0.5
local STAB_COOLDOWN = 0.3
local MAX_CHARGE_TIME = 1
local MIN_CHARGE_RATIO = 0
local MAX_CHARGE_RATIO = 1
local lastThrow = 0
local lastStab = 0
local MAX_RAYCAST_DISTANCE = 1000
local THROW_THRESHOLD = 0.2

local ThrowKnifeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("ThrowKnife")
local ThrewKnifeClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("ThrewClient")
local StabKnifeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("StabKnife")

local MainUi = player.PlayerGui:WaitForChild("Main")
local BottomLeftFrame = MainUi:WaitForChild("BottomLeft")
local StuffContainerFrame = BottomLeftFrame:WaitForChild("StuffContainer")
local AbilityFrame = StuffContainerFrame:WaitForChild("Ability")
local OnClickFrame = AbilityFrame:WaitForChild("OnClick")
local OnClickFrameBar = OnClickFrame:WaitForChild("OnClickFrame")

local leaderstats = player:WaitForChild("leaderstats")
local KeyBindFolder = leaderstats:WaitForChild("KeyBinds")

local CurrentKeyBind = nil
local CurrentStabKeybind = nil
local activeTween
local chargeTween
local charging = false
local chargeStart = 0
local chargeSessionId = 0 -- used to cancel stale delayed tasks

local chargeTrack = nil
local chargeHoldTrack = nil
local throwTrack = nil
local stabTrack = nil

local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations")
local ChargeAnimation = CombatAnimations:WaitForChild("Charge")
local ChargeLoopAnimation = CombatAnimations:WaitForChild("ChargeHold")
local ReleaseKnifeAnimation = CombatAnimations:WaitForChild("Throw")
local StabAnimation = CombatAnimations:WaitForChild("Stab")

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

	print("Animation tracks loaded!")
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	task.wait(0.1)
	loadAnimationTracks()
end)

if player.Character then
	loadAnimationTracks()
end

local function playStabAnimation()
	-- Block stab if any charge animation is active
	if isCharging() then return end

	stopAllAnimations()
	if stabTrack then
		stabTrack.Looped = false
		if stabTrack.IsPlaying then stabTrack:Stop() end
		stabTrack:Play()
	end
end

local function playChargeAnimation()
	stopAllAnimations()
	if not chargeTrack then return end

	-- Capture current session so the delayed transition can be cancelled if user releases
	local sessionId = chargeSessionId

	chargeTrack.Looped = false
	chargeTrack:AdjustSpeed(1)
	chargeTrack:Play()

	task.delay(chargeTrack.Length, function()
		-- Only transition if still in the same charge session and still holding
		if chargeSessionId ~= sessionId then return end
		if not charging then return end

		-- Stop charge anim and start hold loop
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
	if throwTrack then
		throwTrack:Play()
	end
end

local function isThrowInput(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return true
	end
	if typeof(CurrentKeyBind) == "EnumItem" and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == CurrentKeyBind then
		return true
	end
	if CurrentKeyBind == "MouseButton2" and input.UserInputType == Enum.UserInputType.MouseButton2 then
		return true
	end
	return false
end

local function UiAnimation()
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

ThrewKnifeClient.OnClientEvent:Connect(function()
	UiAnimation()
end)

local function throw(chargeRatio)
	if tick() - lastThrow < COOLDOWN then return end
	lastThrow = tick()

	local clampedCharge = math.clamp(chargeRatio or 0, MIN_CHARGE_RATIO, MAX_CHARGE_RATIO)
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		rayParams.FilterDescendantsInstances = {player.Character}
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAYCAST_DISTANCE, rayParams)
	local targetPos = result and result.Position or (ray.Origin + ray.Direction * MAX_RAYCAST_DISTANCE)

	playThrowAnimation()
	ThrowKnifeRemote:FireServer(ray.Origin, targetPos, clampedCharge)
end

local function stab()
	if tick() - lastStab < STAB_COOLDOWN then return end
	lastStab = tick()

	playStabAnimation()
	StabKnifeRemote:FireServer()
end

local function parseInput(inputString)
	if not inputString or inputString == "" then return nil end

	if inputString:find("Enum.KeyCode.") then
		local keyName = inputString:match("Enum%.KeyCode%.(.+)")
		if keyName and Enum.KeyCode[keyName] then
			return Enum.KeyCode[keyName]
		end
	elseif inputString == "MouseButton1" then
		return "MouseButton1"
	elseif inputString == "MouseButton2" then
		return "MouseButton2"
	end
	return nil
end

local function initializeKnifeKeybinds()
	local throwKeyBind = KeyBindFolder:WaitForChild("ThrowKnife")
	local stabKeyBind = KeyBindFolder:WaitForChild("Stab")

	if throwKeyBind.Value == "" or throwKeyBind.Value == nil then
		task.wait(0.1)
	end

	CurrentKeyBind = parseInput(throwKeyBind.Value) or Enum.KeyCode.E
	CurrentStabKeybind = parseInput(stabKeyBind.Value) or "MouseButton1"

	print("Initialized knife keybinds:")
	print("Throw:", CurrentKeyBind)
	print("Stab:", CurrentStabKeybind)
end

initializeKnifeKeybinds()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if isThrowInput(input) and not charging then
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
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if charging and isThrowInput(input) then
		charging = false
		local heldFor = tick() - chargeStart
		chargeSessionId += 1 -- invalidate any pending delayed tasks
		stopChargeTween()
		stopAllAnimations()

		if heldFor < THROW_THRESHOLD then
			stab()
		else
			local ratio = math.clamp(heldFor / MAX_CHARGE_TIME, 0, 1)
			throw(ratio)
		end
	end
end)

KeyBindFolder:WaitForChild("ThrowKnife").Changed:Connect(function()
	local newValue = KeyBindFolder.ThrowKnife.Value
	local newInput = parseInput(newValue)
	if newInput then
		CurrentKeyBind = newInput
		print("Updated ThrowKnife bind to", tostring(newInput))
	else
		warn("Invalid ThrowKnife bind:", newValue)
	end
end)

KeyBindFolder:WaitForChild("Stab").Changed:Connect(function()
	local newValue = KeyBindFolder.Stab.Value
	local newInput = parseInput(newValue)
	if newInput then
		CurrentStabKeybind = newInput
		print("Updated Stab bind to", tostring(newInput))
	else
		warn("Invalid Stab bind:", newValue)
	end
end)

return {}