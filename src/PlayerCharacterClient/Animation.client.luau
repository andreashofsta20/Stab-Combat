local Players = game:GetService("Players")
local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.MovementConfig)
local SlideController = require(RS.Modules.SlideController)
local CameraConfig = require(RS.Modules.FirstPersonCameraConfig)
local State = require(RS.Modules.MovementAnimationState)
local Validation = require(RS.Modules.KeybindValidation)
local Sprint = require(RS.Modules.SprintState)
local player, character = Players.LocalPlayer, script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
-- Wait for replication instead of permanently abandoning animation after 5s.
local animator
repeat
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then task.wait(0.1) end
until animator or player.Character ~= character or humanoid.Health <= 0
if not animator or player.Character ~= character then return end
local binds = player:WaitForChild("leaderstats"):WaitForChild("KeyBinds")
local mobileFrame = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("MobileFrame")
local sprintButton = mobileFrame:WaitForChild("BasicControls"):WaitForChild("Sprint")
local tracks, recovery, connections = {}, {}, {}
local sprinting, crouching, sliding, keyboardHeld, mobileToggled = false, false, false, false, false
local lastSlide, elapsed = -math.huge, 0
local alive = true
local currentName
local slide = SlideController.new(character, humanoid, root, Config)

local function connect(signal, callback) table.insert(connections, signal:Connect(callback)) end
local function loadTrack(name, id)
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()
	if not ok then return nil end
	track.Looped = name ~= "Jump" and name ~= "Slide"
	track.Priority = (name == "Idle" or name == "CrouchIdle") and Enum.AnimationPriority.Idle
		or (name == "Slide" and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement)
	return track
end
for name, id in pairs(Config.Animations) do
	tracks[name] = loadTrack(name, id)
	recovery[name] = {nextTry = os.clock() + Config.AssetRetrySeconds, attempts = 0}
end
local function moving()
	local velocity = root.AssemblyLinearVelocity
	return humanoid.MoveDirection.Magnitude > 0.01 and Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.1
end
local function reconcile()
	if not alive then return end
	local humanoidState = humanoid:GetState().Name
	-- Small physical step lifts can briefly report Freefall. The slide
	-- controller owns its bounded ground grace; keep the pose blended through it.
	if sliding and humanoidState == "Freefall" then humanoidState = "Running" end
	local selected = State.Select(humanoidState, moving(), sprinting, crouching, sliding)
	local posture = selected == "Slide" and "Slide"
		or (selected == "CrouchIdle" or selected == "CrouchWalk") and "Crouch" or "Stand"
	if character:GetAttribute(CameraConfig.PostureAttribute) ~= posture then
		character:SetAttribute(CameraConfig.PostureAttribute, posture)
	end
	if selected ~= currentName then
		local fade = (selected == "Slide" or currentName == "Slide") and Config.SlideFadeSeconds or Config.FadeSeconds
		for name, track in pairs(tracks) do if name ~= selected and track.IsPlaying then track:Stop(fade) end end
		currentName = selected
	end
	local track = selected and tracks[selected]
	if track and not track.IsPlaying then
		track:Play(selected == "Slide" and Config.SlideFadeSeconds or Config.FadeSeconds)
		if selected == "Slide" and track.Length > 0 then track:AdjustSpeed(track.Length / Config.SlideDuration) end
	end
end
local function setSpeed()
	humanoid.WalkSpeed = crouching and Config.CrouchSpeed or (sprinting and Config.RunSpeed or Config.WalkSpeed)
end
local function setSprint(enabled)
	if not alive then return false end
	sprinting = enabled == true and not crouching
	if not sliding then setSpeed() end
	reconcile()
	return sprinting
end
local sprintController = setSprint
Sprint.SetController(sprintController)
local function updateSprint()
	Sprint.SetEnabled(keyboardHeld or mobileToggled)
	sprintButton:SetAttribute("SprintToggled", Sprint.GetEnabled())
	local deco = sprintButton:FindFirstChild("deco")
	if deco then deco.ImageColor3 = Sprint.GetEnabled() and Color3.fromRGB(0, 184, 255) or Color3.new(1, 1, 1) end
end
local function endSlide()
	if not sliding then return end
	slide:Stop()
	sliding, lastSlide = false, os.clock()
	setSpeed(); reconcile()
end
local function blocked()
	if not alive or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return true end
	local frames = player.PlayerGui.Main:FindFirstChild("Frames")
	if frames then for _, frame in ipairs(frames:GetChildren()) do if frame:IsA("GuiObject") and frame.Visible then return true end end end
	return false
end
local function cancelHeld()
	keyboardHeld, mobileToggled, crouching = false, false, false
	endSlide(); updateSprint(); setSpeed(); reconcile()
end
local function sprintAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		if blocked() then return Enum.ContextActionResult.Pass end
		keyboardHeld = true; updateSprint()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		keyboardHeld = false; updateSprint()
	end
	return Enum.ContextActionResult.Pass
end
local function crouchAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		if blocked() or sliding then return Enum.ContextActionResult.Pass end
		crouching = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		crouching = false
	else return Enum.ContextActionResult.Pass end
	updateSprint(); setSpeed(); reconcile()
	return Enum.ContextActionResult.Sink
end
local function slideAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin or blocked() then return Enum.ContextActionResult.Pass end
	if sprinting and not crouching and not sliding and humanoid.FloorMaterial ~= Enum.Material.Air
		and os.clock() - lastSlide >= Config.SlideCooldown and slide:Start() then
		sliding = true
		humanoid.WalkSpeed = slide.Speed
		reconcile()
	end
	return Enum.ContextActionResult.Sink
end
local actions = {Sprint = sprintAction, Crouch = crouchAction, Slide = slideAction}
for name, callback in pairs(actions) do
	local bind = binds:WaitForChild(name)
	local function rebind()
		cancelHeld()
		CAS:UnbindAction(name .. "Action")
		local key = Validation.ToEnum(bind.Value)
		if key then CAS:BindActionAtPriority(name .. "Action", callback, false, Enum.ContextActionPriority.High.Value + 1, key) end
	end
	rebind()
	connect(bind.Changed, rebind)
end
connect(sprintButton.Activated, function() if not blocked() then mobileToggled = not mobileToggled; updateSprint() end end)
connect(humanoid.Running, reconcile)
connect(humanoid.StateChanged, function()
	local state = humanoid:GetState().Name
	if state ~= "Running" and state ~= "RunningNoPhysics" and state ~= "Landed" and state ~= "Freefall" then endSlide() end
	reconcile()
end)
connect(UIS.WindowFocusReleased, cancelHeld)
connect(UIS.TextBoxFocused, cancelHeld)
connect(GuiService.MenuOpened, cancelHeld)
connect(RunService.PreSimulation, function(dt)
	if not alive or not sliding then return end
	local exitSpeed = sprinting and Config.RunSpeed or Config.WalkSpeed
	if slide:Step(dt, exitSpeed) then humanoid.WalkSpeed = slide.Speed else endSlide() end
end)
connect(RunService.Heartbeat, function(dt)
	if not alive then return end
	elapsed += dt
	if elapsed < Config.RecoveryInterval then return end
	elapsed = 0
	if blocked() and (keyboardHeld or crouching or sliding) then cancelHeld() end
	-- Restart stopped movement tracks and retry unloaded custom assets with a
	-- bounded schedule. A denied asset gets one standard R6 fallback.
	for name, item in pairs(recovery) do
		local track = tracks[name]
		if (not track or track.Length == 0) and os.clock() >= item.nextTry and item.attempts < 2 then
			item.attempts += 1
			item.nextTry = os.clock() + Config.AssetRetrySeconds
			local id = item.attempts == 2 and Config.Fallbacks[name] or Config.Animations[name]
			if id then
				if track then track:Stop(0); track:Destroy() end
				tracks[name] = loadTrack(name, id)
				if item.attempts == 2 then warn("[Movement] Using R6 fallback for", name, "check animation asset permissions") end
			end
		end
	end
	reconcile()
end)
local function cleanup()
	if not alive then return end
	cancelHeld()
	alive = false
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	for _, track in pairs(tracks) do track:Stop(0); track:Destroy() end
	slide:Destroy()
	for name in pairs(actions) do CAS:UnbindAction(name .. "Action") end
	Sprint.ClearController(sprintController)
end
connect(humanoid.Died, cleanup)
connect(player.CharacterRemoving, function(removed) if removed == character then cleanup() end end)
connect(script.Destroying, cleanup)
setSpeed(); updateSprint(); reconcile()
