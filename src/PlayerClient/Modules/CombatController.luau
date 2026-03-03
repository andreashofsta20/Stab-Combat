local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local COOLDOWN = 0.5
local STAB_COOLDOWN = 0.3
local MAX_CHARGE_TIME = 1
local MIN_CHARGE_RATIO = 0
local MAX_CHARGE_RATIO = 1
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

local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations")
local ChargeAnimation = CombatAnimations:WaitForChild("Charge")
local ChargeLoopAnimation = CombatAnimations:WaitForChild("ChargeHold")
local ReleaseKnifeAnimation = CombatAnimations:WaitForChild("Throw")
local StabAnimation = CombatAnimations:WaitForChild("Stab")

local CombatController = {}

local initialized = false
local lastThrow = 0
local lastStab = 0
local activeTween
local chargeTween
local charging = false
local chargeStart = 0
local chargeSessionId = 0

local chargeTrack = nil
local chargeHoldTrack = nil
local throwTrack = nil
local stabTrack = nil

local currentHumanoid: Humanoid? = nil
local defaultWalkSpeed = 16
local sprintWalkSpeed = 24
local sprintEnabled = false

local function hasKnifeEquipped()
	local character = player.Character
	if not character then return false end
	return character:FindFirstChildWhichIsA("Tool") ~= nil
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
	if throwTrack then
		throwTrack:Play()
	end
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
	if not humanoid then
		return
	end

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
	if tick() - lastThrow < COOLDOWN then return false end
	lastThrow = tick()

	local clampedCharge = math.clamp(chargeRatio or 0, MIN_CHARGE_RATIO, MAX_CHARGE_RATIO)
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		rayParams.FilterDescendantsInstances = { player.Character }
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAYCAST_DISTANCE, rayParams)
	local targetPos = result and result.Position or (ray.Origin + ray.Direction * MAX_RAYCAST_DISTANCE)

	playThrowAnimation()
	ThrowKnifeRemote:FireServer(ray.Origin, targetPos, clampedCharge)
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
	if initialized then
		return
	end
	initialized = true

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	ThrewKnifeClient.OnClientEvent:Connect(function()
		uiAnimation()
	end)
end

function CombatController.BeginCharge()
	CombatController.Init()
	if charging then
		return false
	end

	if not hasKnifeEquipped() then
		return false
	end

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
	if not charging then
		return false
	end

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
