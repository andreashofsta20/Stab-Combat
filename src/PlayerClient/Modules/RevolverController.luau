local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local CursorConfig = require(ReplicatedStorage.Modules.CursorConfig)
local KeybindValidation = require(ReplicatedStorage.Modules.KeybindValidation)
local Catalog = require(ReplicatedStorage.Modules.RevolversInfo)
local ToolPhysics = require(ReplicatedStorage.Modules.RevolverToolPhysics).New(Catalog)
local Raycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)
local Effects = require(script.Parent.RevolverEffects)
local AimPose = require(script.Parent.RevolverAimPose)
local AimCamera = require(script.Parent.RevolverAimCamera)
local Viewmodel = require(script.Parent.RevolverViewmodel)
local Feedback = require(script.Parent.HitFeedback)
local player = Players.LocalPlayer
local Controller = {}
local initialized = false
local Action, Snapshot, Shot, gameActive
local session, revision, sequence, acknowledged = nil, -1, 0, 0
local serverAmmo, reloadEnd, nextShot = Config.Capacity, 0, 0
local nextEmptySound = 0
local pending = {}
local predictions = {}
local presentedShots = {}
local characterConnections = {}
local touchShiftLock = false
local gamepadMode = false
local touchMode = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local reloadPredicted = false
local reloadSequence = nil
local reloadRequestedAt = 0
local lastSyncAt = 0
local oldZoom = nil
local touchAimPosition, touchAimUntil = nil, 0
local gui, ammoLabel, crosshair, shootButton, reloadButton, aimButton
local aimRequested = false
local aimInput
local equippedTool, equippedTuning
local toolScanDirty = true
local boundCharacter
local reloadKey, reloadDisplay = Config.ReloadKey, KeybindValidation.ToDisplay(Config.ReloadKey)

local function now() return workspace:GetServerTimeNow() end
local function finiteVector(value)
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) <= Config.Security.MaxCoordinate
		and math.abs(value.Y) <= Config.Security.MaxCoordinate and math.abs(value.Z) <= Config.Security.MaxCoordinate
end
local function getTool()
	local character = player.Character
	if not character or character ~= boundCharacter then return nil end
	if equippedTool and equippedTool.Parent == character then return equippedTool end
	equippedTool, equippedTuning = nil, nil
	if not toolScanDirty then return nil end
	toolScanDirty = false
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and Catalog[child.Name] then
			equippedTool, equippedTuning = child, Config.Get(child.Name)
			Effects.Equip(child, equippedTuning)
			return child
		end
	end
	return nil
end

local function stopAim(immediate)
	aimRequested = false
	aimInput = nil
	AimCamera.Stop(immediate)
end

local function uiBlocksCombat()
	if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return true end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local main = playerGui and playerGui:FindFirstChild("Main")
	local frames = main and main:FindFirstChild("Frames")
	if frames then
		for _, frame in ipairs(frames:GetChildren()) do
			if frame:IsA("GuiObject") and frame.Visible then return true end
		end
	end
	local emote = main and main:FindFirstChild("EmoteFrame")
	local background = emote and emote:FindFirstChild("background")
	return background ~= nil and background.Visible
end

local function canPlay()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return gameActive and gameActive.Value and player:GetAttribute("InRound") == true
		and player:GetAttribute("DataReady") == true and humanoid and humanoid.Health > 0
end

local function canPresent()
	if canPlay() then return true end
	if Config.Presentation.LobbyAimingEnabled ~= true or player:GetAttribute("InRound") == true
		or player:GetAttribute("DataReady") ~= true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function canAim()
	if aimInput then
		if aimInput.UserInputType == Enum.UserInputType.MouseButton2 then
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return false end
		elseif aimInput.UserInputState == Enum.UserInputState.End or aimInput.UserInputState == Enum.UserInputState.Cancel then
			return false
		end
	end
	return getTool() ~= nil and canPresent() and not uiBlocksCombat()
end

function Controller.SetAiming(enabled, heldInput)
	if not initialized then return false end
	if not enabled then stopAim(); return true end
	Viewmodel.InterruptInspect()
	aimInput = heldInput
	if not canAim() then stopAim(); return false end
	local tool = getTool()
	aimRequested = AimCamera.Start(tool, equippedTuning.Aim, canAim)
	return aimRequested
end

local function discardPrediction(id)
	local prediction = predictions[id]
	if prediction and prediction.part then prediction.part:Destroy() end
	predictions[id] = nil
end

local function clearPredictions()
	for id in pairs(predictions) do discardPrediction(id) end
	table.clear(predictions)
	table.clear(pending)
end

local function sync()
	if not Action or now() - lastSyncAt < 0.1 then return end
	lastSyncAt = now()
	Action:FireServer("Sync", session, sequence)
end

local function predictionAmmo()
	local count = 0
	for _ in pairs(pending) do count += 1 end
	return math.max(0, serverAmmo - count), count
end

local function aimRay(screenPosition)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	if AimCamera.IsAiming() or (not screenPosition and (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or touchShiftLock or gamepadMode or touchMode)) then
		local center = camera.ViewportSize / 2
		return camera:ViewportPointToRay(center.X, center.Y)
	end
	-- GetMouseLocation/InputObject.Position are viewport coordinates; do not
	-- subtract/add a hardcoded top-bar inset or use ScreenPointToRay here.
	local position = screenPosition or UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(position.X, position.Y)
end

local function worldCast(ignore)
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater = Enum.RaycastFilterType.Exclude, RagdollQuery.Exclude(ignore), true
	return function(origin, vector) return workspace:Raycast(origin, vector, params) end
end

local function pathStillClear(origin, destination, cast)
	local vector = destination - origin
	if vector.Magnitude < 0.001 then return true end
	local cover = cast(origin, vector)
	return not cover or cover.Distance >= vector.Magnitude - 0.02
end

local function predict(ray, tuning)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return nil end
	local ignore, targets = {}, {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then table.insert(ignore, other.Character) end
		if other ~= player and other:GetAttribute("InRound") == true then
			local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				local target = Raycast.GetCharacterGeometry(other.Character)
				target.frame = root.CFrame * CFrame.new(table.unpack(tuning.HitboxOffset))
				table.insert(targets, target)
			end
		end
	end
	local cast = worldCast(ignore)
	-- Match authority: recoil, bob, arm poses and skin offsets cannot move
	-- the gameplay ray down into cover beneath an otherwise clear cursor.
	local origin = head.Position
	return Raycast.Resolve(ray.Origin, ray.Direction.Unit, origin, tuning, targets, cast), origin, cast
end

function Controller.Fire(screenPosition: Vector2?)
	Viewmodel.InterruptInspect()
	if not initialized or not canPlay() or uiBlocksCombat() then return false end
	local tool = getTool()
	if not tool then return false end
	if not session then sync(); return false end
	local time = now()
	local ammo, count = predictionAmmo()
	if count >= Config.Security.MaxPendingShots or reloadEnd > 0
		or reloadPredicted or time < nextShot then return false end
	if ammo <= 0 then
		if time >= nextEmptySound then
			nextEmptySound = time + equippedTuning.Effects.EmptySoundCooldownMs / 1000
			Effects.Empty(tool, equippedTuning)
		end
		return false
	end
	local ray = aimRay(screenPosition)
	if not ray then return false end
	local tuning = equippedTuning
	local result, origin, cast = predict(ray, tuning)
	if not result then return false end
	local firstPerson = Viewmodel.IsFirstPerson(tool, tuning)
	local visualTool = Viewmodel.GetVisualTool(tool)
	local cosmeticOrigin = Effects.GetShotOrigin(tool, origin, tuning, visualTool, firstPerson)
	local safeOrigin = Raycast.GetVisualShotOrigin(origin, cosmeticOrigin, result.position, cast)
	if screenPosition then touchAimPosition, touchAimUntil = screenPosition, time + 0.6 end
	AimPose.SetLocalAim(tool, result.position, false, AimCamera.IsAiming())
	AimPose.Kick(player, player.Character, tool.Name)
	sequence += 1
	nextShot = time + tuning.FireIntervalMs / 1000
	pending[sequence] = { time = time, nextShot = nextShot }
	-- Immediate feedback keeps input responsive; only authority starts a traveling streak.
	predictions[sequence] = {
		time = time, origin = cosmeticOrigin, physicalOrigin = origin, tuning = tuning,
		visualTool = visualTool, firstPerson = firstPerson, cast = cast,
	}
	Effects.Fire(tool, origin, result.position, tuning, true, visualTool, firstPerson, false, true, safeOrigin)
	Viewmodel.Kick(tool)
	Action:FireServer("Fire", session, sequence, ray.Origin, ray.Direction.Unit, time)
	return true
end

function Controller.Reload()
	Viewmodel.InterruptInspect()
	if not initialized or not canPlay() or uiBlocksCombat() then return false end
	local tool = getTool()
	if not tool or not session then sync(); return false end
	local ammo = predictionAmmo()
	if ammo >= Config.Capacity or reloadEnd > 0 or reloadPredicted then return false end
	sequence += 1
	reloadSequence = sequence
	reloadPredicted, reloadRequestedAt = true, now()
	Effects.Reload(tool, equippedTuning)
	Action:FireServer("Reload", session, sequence)
	return true
end

function Controller.HasRevolverEquipped() return getTool() ~= nil end
function Controller.IsAiming() return AimCamera.IsAiming() end
function Controller.SetMobileShiftLock(enabled)
	touchShiftLock = enabled == true
	AimCamera.SetExternalShiftLock(touchShiftLock)
end

local function makeUI()
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "RevolverHUD", false, true, 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ammoLabel = Instance.new("TextLabel")
	ammoLabel.AnchorPoint, ammoLabel.Position = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.88)
	ammoLabel.Size, ammoLabel.BackgroundTransparency = UDim2.fromOffset(260, 34), 1
	ammoLabel.TextColor3, ammoLabel.TextStrokeTransparency = Color3.new(1, 1, 1), 0.4
	ammoLabel.Font, ammoLabel.TextSize, ammoLabel.Parent = Enum.Font.GothamBold, 20, gui
	crosshair = Instance.new("Frame")
	crosshair.Visible = false
	crosshair.AnchorPoint, crosshair.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(CursorConfig.WhiteDotSize, CursorConfig.WhiteDotSize)
	crosshair.BackgroundColor3, crosshair.BorderSizePixel, crosshair.Parent = Color3.new(1, 1, 1), 0, gui
	local function button(text, offset)
		local control = Instance.new("TextButton")
		control.AnchorPoint, control.Position, control.Size = Vector2.new(1, 1), UDim2.new(1, offset, 0.63, 0), UDim2.fromOffset(80, 52)
		control.Text, control.TextSize, control.Font = text, 18, Enum.Font.GothamBold
		control.BackgroundColor3, control.TextColor3, control.Parent = Color3.fromRGB(35, 35, 45), Color3.new(1, 1, 1), gui
		return control
	end
	shootButton, reloadButton, aimButton = button("SHOOT", -12), button("RELOAD", -100), button("AIM", -188)
	shootButton.Activated:Connect(function()
		-- A dedicated touch button shoots at the displayed center crosshair.
		local camera = workspace.CurrentCamera
		if camera then Controller.Fire(camera.ViewportSize / 2) end
	end)
	reloadButton.Activated:Connect(Controller.Reload)
	aimButton.Activated:Connect(function() Controller.SetAiming(not AimCamera.IsAiming()) end)
end

local function onCharacter(character)
	boundCharacter = character
	gui.Enabled = false
	stopAim(true)
	equippedTool, equippedTuning = nil, nil
	toolScanDirty = true
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	session, revision, sequence, acknowledged = nil, -1, 0, 0
	serverAmmo, reloadEnd, nextShot, reloadPredicted = Config.Capacity, 0, 0, false
	nextEmptySound = 0
	reloadSequence = nil
	clearPredictions()
	Effects.Clear()
	Viewmodel.Clear()
	AimPose.ResetLocal()
	local function toolsChanged(child)
		if not child:IsA("Tool") then return end
		toolScanDirty = true
		if child == equippedTool and child.Parent ~= character then
			stopAim(true)
			Viewmodel.Clear()
			equippedTool, equippedTuning = nil, nil
		end
		if not getTool() then
			gui.Enabled, crosshair.Visible = false, false
			reloadPredicted = false
			reloadSequence = nil
			Effects.StopReload()
		end
		sync()
	end
	table.insert(characterConnections, character.ChildAdded:Connect(toolsChanged))
	table.insert(characterConnections, character.ChildRemoved:Connect(toolsChanged))
	sync()
end

function Controller.Init()
	if initialized then return end
	initialized = true
	local reloadBind = player:WaitForChild("leaderstats"):WaitForChild("KeyBinds"):WaitForChild("Reload")
	local function updateReloadKey()
		reloadKey = KeybindValidation.NormalizeForAction("Reload", reloadBind.Value) or Config.ReloadKey
		reloadDisplay = KeybindValidation.ToDisplay(reloadKey)
	end
	updateReloadKey()
	reloadBind.Changed:Connect(updateReloadKey)
	ToolPhysics.BindPlayer(player)
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Revolver")
	Action, Snapshot, Shot = remotes:WaitForChild("Action"), remotes:WaitForChild("State"), remotes:WaitForChild("Shot")
	gameActive = ReplicatedStorage:WaitForChild("GameActive")
	AimPose.Init(remotes:WaitForChild("Aim"))
	makeUI()
	Snapshot.OnClientEvent:Connect(function(data)
		if data.Character ~= player.Character then return end
		if session ~= data.Session then
			session, revision, sequence, acknowledged = data.Session, -1, 0, 0
			nextEmptySound = 0
			AimPose.SetSession(session)
			reloadPredicted, reloadSequence = false, nil
			clearPredictions()
		end
		if data.Revision <= revision then return end
		revision, acknowledged = data.Revision, data.AckSequence
		sequence = math.max(sequence, acknowledged)
		serverAmmo, reloadEnd = data.Ammo, data.ReloadEnd
		nextShot = data.NextShot
		local resolved = math.max(acknowledged, data.SyncSequence or 0)
		local prediction = predictions[acknowledged]
		if prediction then
			if data.Reason == "Fired" then prediction.accepted = true
			elseif data.Reason ~= "Sync" and not prediction.accepted then discardPrediction(acknowledged) end
		end
		for id, request in pairs(pending) do
			if id <= resolved then pending[id] = nil
			else nextShot = math.max(nextShot, request.nextShot) end
		end
		if reloadSequence and reloadSequence <= resolved then
			reloadPredicted, reloadSequence = false, nil
		end
		if reloadEnd == 0 and not reloadPredicted then Effects.StopReload() end
	end)
	Shot.OnClientEvent:Connect(function(data)
		-- Local prediction supplies flash/recoil once; authority supplies the one streak and impact.
		if type(data) ~= "table" or not Catalog[data.Weapon]
			or not finiteVector(data.Origin) or not finiteVector(data.Position)
			or type(data.ShooterId) ~= "number" or data.ShooterId ~= data.ShooterId
			or math.abs(data.ShooterId) > 9007199254740991 or data.ShooterId % 1 ~= 0
			or type(data.Session) ~= "string" or #data.Session == 0 or #data.Session > 64
			or type(data.Sequence) ~= "number" or data.Sequence ~= data.Sequence
			or data.Sequence < 0 or data.Sequence > 2147483647 or data.Sequence % 1 ~= 0 then return end
		if data.ShooterId == player.UserId and data.Session ~= session then return end
		if type(data.Sequence) == "number" and type(data.Session) == "string" then
			local previous = presentedShots[data.ShooterId]
			if previous and previous.session == data.Session and data.Sequence <= previous.sequence then return end
			presentedShots[data.ShooterId] = {session = data.Session, sequence = data.Sequence}
		end
		if data.ShooterId == player.UserId then
			if data.Session ~= session then return end
			local prediction = predictions[data.Sequence]
			if prediction then
				-- Moving cover may have entered the path during the round trip.
				-- Suppress stale flight rather than drawing through it or inventing a second hit.
				if pathStillClear(data.Origin, data.Position, prediction.cast) then
					local origin = Raycast.GetVisualShotOrigin(data.Origin, prediction.origin, data.Position, prediction.cast)
					Effects.ConfirmedTracer(origin, data.Position, prediction.tuning, prediction.visualTool, prediction.firstPerson)
				end
				discardPrediction(data.Sequence)
			end
		else
			local shooter = Players:GetPlayerByUserId(data.ShooterId)
			local tool = shooter and shooter.Character and shooter.Character:FindFirstChild(data.Weapon)
			if shooter then AimPose.Kick(shooter, shooter.Character, data.Weapon) end
			local ignore = {}
			for _, other in ipairs(Players:GetPlayers()) do
				if other.Character then table.insert(ignore, other.Character) end
			end
			local blocked = not pathStillClear(data.Origin, data.Position, worldCast(ignore))
			Effects.Fire(tool, data.Origin, data.Position, Config.Get(data.Weapon), false, nil, false, true, blocked)
		end
		Effects.Impact(data.Position, data.Normal, Config.Get(data.Weapon).Effects, data.Surface, data.Hit)
	end)
	Players.PlayerRemoving:Connect(function(leaving) presentedShots[leaving.UserId] = nil end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		gamepadMode = input.UserInputType.Name:match("^Gamepad") ~= nil
		touchMode = input.UserInputType == Enum.UserInputType.Touch
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			Controller.Fire()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			Controller.SetAiming(true, input)
		elseif KeybindValidation.Matches(reloadKey, input) or input.KeyCode.Name == Config.GamepadReloadKey then
			Controller.Reload()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then stopAim() end
	end)
	UserInputService.WindowFocusReleased:Connect(function() stopAim(true) end)
	UserInputService.TextBoxFocused:Connect(function() stopAim(true) end)
	GuiService.MenuOpened:Connect(function() stopAim(true) end)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		gamepadMode = inputType.Name:match("^Gamepad") ~= nil
		touchMode = inputType == Enum.UserInputType.Touch
	end)
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function(character)
		if character ~= boundCharacter then return end
		boundCharacter, equippedTool, equippedTuning = nil, nil, nil
		nextEmptySound = 0
		Viewmodel.Clear()
		gui.Enabled, crosshair.Visible = false, false
		stopAim(true)
	end)
	gameActive.Changed:Connect(function()
		sync()
		if not gameActive.Value then stopAim(true); reloadPredicted = false; Effects.StopReload() end
	end)
	player:GetAttributeChangedSignal("DataReady"):Connect(sync)
	player:GetAttributeChangedSignal("InRound"):Connect(sync)
	if player.Character then onCharacter(player.Character) end
	RunService:BindToRenderStep("RevolverHUD", Enum.RenderPriority.Camera.Value + 3, function(dt)
		local tool = getTool()
		local visible = tool ~= nil and canPresent() and not uiBlocksCombat()
		local combat = visible and canPlay()
		gui.Enabled = visible == true
		crosshair.Visible = visible == true and CursorConfig.Enabled and CursorConfig.WhiteDotEnabled
		ammoLabel.Visible = combat == true
		if aimRequested and (not visible or not canAim() or not AimCamera.IsAiming()) then stopAim(not visible) end
		if tool and oldZoom == nil then
			oldZoom = player.CameraMaxZoomDistance
			player.CameraMaxZoomDistance = math.min(oldZoom, Config.Security.CameraZoomLimit)
		elseif not tool and oldZoom ~= nil then
			player.CameraMaxZoomDistance, oldZoom = oldZoom, nil
		end
		local time = now()
		if visible then
			local touchPosition = touchMode and time < touchAimUntil and touchAimPosition or nil
			AimPose.SampleCursor(tool, aimRay(touchPosition), combat and (reloadEnd > 0 or reloadPredicted), AimCamera.IsAiming())
		else
			AimPose.SetLocalAim(nil)
		end
		local bodyAnimation, armAnimation = AimPose.GetLocalAnimation()
		Viewmodel.Update(tool, equippedTuning, visible, AimCamera.IsAiming(), combat and (reloadEnd > 0 or reloadPredicted), dt,
			bodyAnimation, armAnimation)
		Effects.SetFirstPerson(Viewmodel.GetVisualTool(tool), equippedTuning)
		local ammo = predictionAmmo()
		if visible then
			local text = reloadEnd > 0 and string.format("RELOADING %.1fs", math.max(0, reloadEnd - time))
				or (reloadPredicted and "RELOADING" or string.format("%d / %d  |  [%s] RELOAD", ammo, Config.Capacity, reloadDisplay))
			ammoLabel.Text = text
			local camera = workspace.CurrentCamera
			local centered = AimCamera.IsAiming() or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or touchShiftLock or gamepadMode or touchMode
			local pos = centered and camera and camera.ViewportSize / 2 or UserInputService:GetMouseLocation()
			crosshair.Position = UDim2.fromOffset(pos.X, pos.Y)
			Feedback.SetAimPosition(pos)
			shootButton.Visible, reloadButton.Visible = combat and UserInputService.TouchEnabled, combat and UserInputService.TouchEnabled
			aimButton.Visible = UserInputService.TouchEnabled
			aimButton.Text = AimCamera.IsAiming() and "AIM ON" or "AIM"
		end
		for id, prediction in pairs(predictions) do
			if time - prediction.time > 2 then predictions[id] = nil end
		end
		for _, request in pairs(pending) do if time - request.time > 1 then sync(); break end end
		if reloadPredicted and time - reloadRequestedAt > 1 then sync() end
		if visible and not session then sync() end
	end)
end

return Controller
