local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local Catalog = require(ReplicatedStorage.Modules.RevolversInfo)
local Raycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local Effects = require(script.Parent.RevolverEffects)
local AimPose = require(script.Parent.RevolverAimPose)
local player = Players.LocalPlayer
local Controller = {}
local initialized = false
local Action, Snapshot, Shot, gameActive
local session, revision, sequence, acknowledged = nil, -1, 0, 0
local serverAmmo, reloadEnd, nextShot = Config.Capacity, 0, 0
local pending = {}
local predictions = {}
local characterConnections = {}
local touchShiftLock = false
local gamepadMode = false
local touchMode = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local reloadPredicted = false
local reloadSequence = nil
local reloadRequestedAt = 0
local lastSyncAt = 0
local oldZoom = nil
local hitMarkerUntil = 0
local touchAimPosition, touchAimUntil = nil, 0
local gui, ammoLabel, crosshair, hitMarker, shootButton, reloadButton

local function now() return workspace:GetServerTimeNow() end
local function getTool()
	local character = player.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and Catalog[child.Name] then return child end
	end
	return nil
end

local function uiBlocksCombat()
	if UserInputService:GetFocusedTextBox() then return true end
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

local function clearPredictions()
	for _, prediction in pairs(predictions) do
		if prediction.part then prediction.part:Destroy() end
	end
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
	if not screenPosition and (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or touchShiftLock or gamepadMode or touchMode) then
		local center = camera.ViewportSize / 2
		return camera:ViewportPointToRay(center.X, center.Y)
	end
	-- GetMouseLocation/InputObject.Position are viewport coordinates; do not
	-- subtract/add a hardcoded top-bar inset or use ScreenPointToRay here.
	local position = screenPosition or UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(position.X, position.Y)
end

local function predict(tool, ray, tuning)
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
				table.insert(targets, { frame = root.CFrame * CFrame.new(table.unpack(tuning.HitboxOffset)) })
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances, params.IgnoreWater = Enum.RaycastFilterType.Exclude, ignore, true
	local function cast(origin, vector) return workspace:Raycast(origin, vector, params) end
	local muzzle = Raycast.GetMuzzle(tool, head, tuning, Config.Security.MaxMuzzleDistance)
	local vector = muzzle - head.Position
	local wall = cast(head.Position, vector)
	if wall and wall.Distance < vector.Magnitude - 0.02 then muzzle = head.Position end
	return Raycast.Resolve(ray.Origin, ray.Direction.Unit, muzzle, tuning, targets, cast), muzzle
end

function Controller.Fire(screenPosition: Vector2?)
	if not initialized or not canPlay() or uiBlocksCombat() then return false end
	local tool = getTool()
	if not tool then return false end
	if not session then sync(); return false end
	local time = now()
	local ammo, count = predictionAmmo()
	if ammo <= 0 or count >= Config.Security.MaxPendingShots or reloadEnd > 0
		or reloadPredicted or time < nextShot then return false end
	local ray = aimRay(screenPosition)
	if not ray then return false end
	local tuning = Config.Get(tool.Name)
	local result, origin = predict(tool, ray, tuning)
	if not result then return false end
	if screenPosition then touchAimPosition, touchAimUntil = screenPosition, time + 0.6 end
	AimPose.SetLocalAim(tool, result.position, false)
	AimPose.Kick(player, player.Character, tool.Name)
	sequence += 1
	nextShot = time + tuning.FireIntervalMs / 1000
	pending[sequence] = { time = time, nextShot = nextShot }
	predictions[sequence] = {
		part = Effects.Fire(tool, origin, result.position, tuning, true), time = time,
	}
	Action:FireServer("Fire", session, sequence, ray.Origin, ray.Direction.Unit, time)
	return true
end

function Controller.Reload()
	if not initialized or not canPlay() or uiBlocksCombat() then return false end
	local tool = getTool()
	if not tool or not session then sync(); return false end
	local ammo = predictionAmmo()
	if ammo >= Config.Capacity or reloadEnd > 0 or reloadPredicted then return false end
	sequence += 1
	reloadSequence = sequence
	reloadPredicted, reloadRequestedAt = true, now()
	Effects.Reload(tool, Config.Get(tool.Name))
	Action:FireServer("Reload", session, sequence)
	return true
end

function Controller.HasRevolverEquipped() return getTool() ~= nil end
function Controller.SetMobileShiftLock(enabled) touchShiftLock = enabled == true end

local function makeUI()
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "RevolverHUD", false, true, 20
	gui.Parent = player:WaitForChild("PlayerGui")
	ammoLabel = Instance.new("TextLabel")
	ammoLabel.AnchorPoint, ammoLabel.Position = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.88)
	ammoLabel.Size, ammoLabel.BackgroundTransparency = UDim2.fromOffset(260, 34), 1
	ammoLabel.TextColor3, ammoLabel.TextStrokeTransparency = Color3.new(1, 1, 1), 0.4
	ammoLabel.Font, ammoLabel.TextSize, ammoLabel.Parent = Enum.Font.GothamBold, 20, gui
	crosshair = Instance.new("Frame")
	crosshair.AnchorPoint, crosshair.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(5, 5)
	crosshair.BackgroundColor3, crosshair.BorderSizePixel, crosshair.Parent = Color3.new(1, 1, 1), 0, gui
	hitMarker = Instance.new("TextLabel")
	hitMarker.AnchorPoint, hitMarker.Size, hitMarker.BackgroundTransparency = Vector2.new(0.5, 0.5), UDim2.fromOffset(32, 32), 1
	hitMarker.Text, hitMarker.TextColor3, hitMarker.TextSize, hitMarker.Parent = "X", Color3.fromRGB(255, 210, 80), 32, gui
	local function button(text, x)
		local control = Instance.new("TextButton")
		control.AnchorPoint, control.Position, control.Size = Vector2.new(1, 1), UDim2.fromScale(x, 0.63), UDim2.fromOffset(80, 52)
		control.Text, control.TextSize, control.Font = text, 18, Enum.Font.GothamBold
		control.BackgroundColor3, control.TextColor3, control.Parent = Color3.fromRGB(35, 35, 45), Color3.new(1, 1, 1), gui
		return control
	end
	shootButton, reloadButton = button("SHOOT", 0.98), button("RELOAD", 0.85)
	shootButton.Activated:Connect(function()
		-- A dedicated touch button shoots at the displayed center crosshair.
		local camera = workspace.CurrentCamera
		if camera then Controller.Fire(camera.ViewportSize / 2) end
	end)
	reloadButton.Activated:Connect(Controller.Reload)
end

local function onCharacter(character)
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	session, revision, sequence, acknowledged = nil, -1, 0, 0
	serverAmmo, reloadEnd, nextShot, reloadPredicted = Config.Capacity, 0, 0, false
	reloadSequence = nil
	clearPredictions()
	Effects.Clear()
	AimPose.ResetLocal()
	local function toolsChanged(child)
		if not child:IsA("Tool") then return end
		if not getTool() then
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
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Revolver")
	Action, Snapshot, Shot = remotes:WaitForChild("Action"), remotes:WaitForChild("State"), remotes:WaitForChild("Shot")
	gameActive = ReplicatedStorage:WaitForChild("GameActive")
	AimPose.Init(remotes:WaitForChild("Aim"))
	makeUI()
	Snapshot.OnClientEvent:Connect(function(data)
		if data.Character ~= player.Character then return end
		if session ~= data.Session then
			session, revision, sequence, acknowledged = data.Session, -1, 0, 0
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
		if data.ShooterId == player.UserId then
			if data.Session ~= session then return end
			local prediction = predictions[data.Sequence]
			if prediction and prediction.part and prediction.part.Parent then
				Effects.CorrectTracer(prediction.part, data.Position)
			end
			predictions[data.Sequence] = nil
			if data.Hit then hitMarkerUntil = now() + 0.15 end
		else
			local shooter = Players:GetPlayerByUserId(data.ShooterId)
			local tool = shooter and shooter.Character and shooter.Character:FindFirstChild(data.Weapon)
			if shooter then AimPose.Kick(shooter, shooter.Character, data.Weapon) end
			Effects.Fire(tool, data.Origin, data.Position, Config.Get(data.Weapon), false)
		end
		Effects.Impact(data.Position, data.Normal, Config.Get(data.Weapon).Effects)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		gamepadMode = input.UserInputType.Name:match("^Gamepad") ~= nil
		touchMode = input.UserInputType == Enum.UserInputType.Touch
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			Controller.Fire()
		elseif input.KeyCode.Name == Config.ReloadKey or input.KeyCode.Name == Config.GamepadReloadKey then
			Controller.Reload()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		gamepadMode = inputType.Name:match("^Gamepad") ~= nil
		touchMode = inputType == Enum.UserInputType.Touch
	end)
	player.CharacterAdded:Connect(onCharacter)
	gameActive.Changed:Connect(function()
		sync()
		if not gameActive.Value then reloadPredicted = false; Effects.StopReload() end
	end)
	player:GetAttributeChangedSignal("DataReady"):Connect(sync)
	player:GetAttributeChangedSignal("InRound"):Connect(sync)
	if player.Character then onCharacter(player.Character) end
	RunService.RenderStepped:Connect(function()
		local tool = getTool()
		local visible = tool ~= nil and canPlay() and not uiBlocksCombat()
		gui.Enabled = visible == true
		if tool and oldZoom == nil then
			oldZoom = player.CameraMaxZoomDistance
			player.CameraMaxZoomDistance = math.min(oldZoom, Config.Security.CameraZoomLimit)
		elseif not tool and oldZoom ~= nil then
			player.CameraMaxZoomDistance, oldZoom = oldZoom, nil
		end
		local time = now()
		if visible then
			local touchPosition = touchMode and time < touchAimUntil and touchAimPosition or nil
			AimPose.SampleCursor(tool, aimRay(touchPosition), reloadEnd > 0 or reloadPredicted)
		else
			AimPose.SetLocalAim(nil)
		end
		local ammo = predictionAmmo()
		if visible then
			local text = reloadEnd > 0 and string.format("RELOADING %.1fs", math.max(0, reloadEnd - time))
				or (reloadPredicted and "RELOADING" or string.format("%d / %d  |  [%s] RELOAD", ammo, Config.Capacity, Config.ReloadKey))
			ammoLabel.Text = text
			local camera = workspace.CurrentCamera
			local centered = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or touchShiftLock or gamepadMode or touchMode
			local pos = centered and camera and camera.ViewportSize / 2 or UserInputService:GetMouseLocation()
			crosshair.Position, hitMarker.Position = UDim2.fromOffset(pos.X, pos.Y), UDim2.fromOffset(pos.X, pos.Y)
			hitMarker.Visible = time < hitMarkerUntil
			shootButton.Visible, reloadButton.Visible = UserInputService.TouchEnabled, UserInputService.TouchEnabled
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
