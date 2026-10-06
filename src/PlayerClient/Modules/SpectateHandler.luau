-- Event-driven roster/UI with native CameraSubject tracking and camera collision.
local SpectateHandler = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local TimeToMinutes = require(Modules:WaitForChild("TimeToMinutes"))
local KnivesInfo = require(Modules:WaitForChild("KnivesInfo"))
local Config = require(Modules:WaitForChild("SpectateConfig"))
local DeathSpectateTransition = require(script.Parent.DeathSpectateTransition)
local player = Players.LocalPlayer
local GameActive = ReplicatedStorage:WaitForChild("GameActive")
local Timer = ReplicatedStorage:WaitForChild("Timer")
local KillCamRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillCam", 10)
local PlayerGui = player:WaitForChild("PlayerGui")
local MainGui, SpectateFrame, BottomFrame, ExitButton, NameText, BottomNameText
local KillsText, KnifeImage, ArrowLeft, ArrowRight, MatchText, SpectateButton, StatusText, LobbyBottom
local initialUIConnections, onUIRemoved = {}, nil
local function readUI()
	local main = PlayerGui:WaitForChild("Main")
	table.insert(initialUIConnections, main.Destroying:Connect(function() onUIRemoved(true) end))
	local frame = main:WaitForChild("SpectateFrame")
	table.insert(initialUIConnections, frame.Destroying:Connect(function() onUIRemoved(false, main) end))
	local bottom = frame:WaitForChild("Bottom")
	local middle = bottom:WaitForChild("MiddleFrame")
	return {
		main = main, frame = frame, bottom = bottom,
		exit = bottom:WaitForChild("ExitFrame"):WaitForChild("ExitSpectateButton"),
		name = frame:WaitForChild("CurrentlySpectatingUser"), bottomName = bottom:WaitForChild("CurrentlySpectating"),
		kills = middle:WaitForChild("Kills"):WaitForChild("KillsText"),
		knife = middle:WaitForChild("Inventory"):WaitForChild("KnifeEquippedFrame"):WaitForChild("Slot"):WaitForChild("KnifeImage"),
		left = bottom:WaitForChild("ArrowLeft"), right = bottom:WaitForChild("ArrowRight"),
		match = frame:WaitForChild("MatchStats"):WaitForChild("StatsText"),
		button = main:WaitForChild("Top"):WaitForChild("Buttons"):WaitForChild("Spectate"),
		status = main:WaitForChild("SystemTexts"):WaitForChild("Status"), lobbyBottom = main:WaitForChild("Bottom"),
	}
end

local initialized, active, writingCamera = false, false, false
local camera, currentTarget, spectateSubject
local spectateIndex, aliveCount, roundMembers = 1, 0, 0
local previousStatus, previousBottom
local connections, cameraConnections, records, roster, buttonTweens = {}, {}, {}, {}, {}
local replacementConnections, replacementThread, initializing, initGeneration = {}, nil, false, 0
local pendingUIResume
local killCamToken, pendingThread, killCam, brWait, brIntent = 0, nil, nil, nil, nil
local deathTransition = DeathSpectateTransition.New(player)
local rebuildRoster, refreshCamera, tryBRSpectate, runBRSpectate

local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end
local function ownHumanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end
local function writeSubject(subject)
	if not camera or camera.CameraSubject == subject then return end
	writingCamera = true
	camera.CameraSubject = subject
	writingCamera = false
end
local function restoreSubject(subject)
	if camera and camera.CameraType == Enum.CameraType.Custom
		and (camera.CameraSubject == subject or camera.CameraSubject == nil) then
		local humanoid = ownHumanoid()
		if humanoid then writeSubject(humanoid) end
	end
end
local function stopKillTracking(restore)
	local old = killCam
	killCam = nil
	if not old then return end
	if old.thread then task.cancel(old.thread); old.thread = nil end
	if restore then restoreSubject(old.subject) end
end
local function cancelKillCam(preserveBR)
	killCamToken += 1
	if pendingThread then task.cancel(pendingThread); pendingThread = nil end
	if brWait and brWait.thread then task.cancel(brWait.thread) end
	brWait = nil
	if not preserveBR then brIntent = nil end
	if brIntent then brIntent.token = killCamToken end
	stopKillTracking(true)
	deathTransition.Cancel()
end
local function updateButton()
	SpectateButton.Visible = GameActive.Value and player:GetAttribute("InRound") ~= true and roundMembers > 0
end
local function refreshMatch()
	if not active then return end
	local seconds = Timer.Value
	if type(seconds) ~= "number" or seconds ~= seconds or math.abs(seconds) == math.huge then seconds = 0 end
	seconds = math.max(0, math.floor(seconds))
	local mode = player:GetAttribute("CurrentRoundMode")
	mode = (mode == "BR" or mode == "Battle Royale") and "Battle Royale"
		or (mode == "FFA" or mode == "Free For All") and "Free For All" or "Match"
	MatchText.RichText = true
	MatchText.Text = string.format(
		'<font color="#ffffff">%s  |  Players Alive: </font><font color="#6ed378">%d</font><font color="#ffffff">  |  Time Left: </font><font color="#ffe941">%s</font>',
		mode, aliveCount, TimeToMinutes.MakeTimeMinute(seconds))
end
local function refreshTarget()
	if not active or not currentTarget or #roster == 0 then return end
	NameText.RichText, BottomNameText.RichText = false, false
	NameText.Text, BottomNameText.Text = currentTarget.DisplayName, currentTarget.DisplayName
	local kills = currentTarget:GetAttribute("CurrentRoundKills")
	if type(kills) ~= "number" or kills ~= kills or math.abs(kills) == math.huge then kills = 0 end
	KillsText.Text = tostring(math.max(0, math.floor(kills)))
	local record = records[currentTarget]
	local equipped = record and record.equippedKnife
	local info = equipped and KnivesInfo[equipped.Value]
	KnifeImage.Image = info and type(info.Image) == "string" and info.Image or ""
end
local function canUseCamera(subject)
	return camera and camera.CameraType == Enum.CameraType.Custom
		and (camera.CameraSubject == subject or camera.CameraSubject == ownHumanoid() or camera.CameraSubject == nil)
end
local function setTarget(index)
	if not canUseCamera(spectateSubject) then SpectateHandler.StopSpectating(); return end
	if #roster == 0 then
		if roundMembers == 0 then SpectateHandler.StopSpectating(); return end
		-- FFA players remain in the round during their short respawn gap.
		-- Keep the UI open and let CharacterAdded/ChildAdded resume tracking.
		restoreSubject(spectateSubject)
		spectateSubject = nil
		NameText.RichText, BottomNameText.RichText = false, false
		NameText.Text, BottomNameText.Text = "Waiting for player...", "Waiting for player..."
		KillsText.Text, KnifeImage.Image = "0", ""
	else
		spectateIndex = ((index - 1) % #roster) + 1
		currentTarget = roster[spectateIndex]
		spectateSubject = records[currentTarget].humanoid
		writeSubject(spectateSubject)
		refreshTarget()
	end
	refreshMatch()
	ArrowLeft.Visible, ArrowRight.Visible = #roster > 1, #roster > 1
end

function SpectateHandler.StopSpectating()
	local oldSubject = spectateSubject
	active = false
	currentTarget, spectateSubject = nil, nil
	SpectateFrame.Visible = false
	if previousStatus ~= nil then StatusText.Visible = previousStatus; previousStatus = nil end
	if previousBottom ~= nil then LobbyBottom.Visible = previousBottom; previousBottom = nil end
	NameText.Text, BottomNameText.Text, KillsText.Text, KnifeImage.Image = "", "", "0", ""
	ArrowLeft.Visible, ArrowRight.Visible = false, false
	cancelKillCam()
	if oldSubject then restoreSubject(oldSubject) end
end
function SpectateHandler.StartSpectating(preferredTarget: Player?)
	if not initialized or not GameActive.Value or player:GetAttribute("InRound") == true then return end
	cancelKillCam()
	camera = Workspace.CurrentCamera
	if not canUseCamera(spectateSubject) or roundMembers == 0 then return end
	if not active then
		previousStatus, previousBottom = StatusText.Visible, LobbyBottom.Visible
		StatusText.Visible, LobbyBottom.Visible = false, false
	end
	active = true
	SpectateFrame.Visible = true
	currentTarget = preferredTarget
	setTarget(preferredTarget and table.find(roster, preferredTarget) or 1)
end
function SpectateHandler.ToggleFrame()
	if not initialized then SpectateHandler.Init() end
	if active then SpectateHandler.StopSpectating() else SpectateHandler.StartSpectating() end
end
refreshCamera = function()
	if writingCamera or not initialized then return end
	if active then
		if not canUseCamera(spectateSubject) then SpectateHandler.StopSpectating(); return end
		local record = #roster > 0 and currentTarget and records[currentTarget]
		if record and record.humanoid and record.humanoid.Health > 0 then
			spectateSubject = record.humanoid
			writeSubject(spectateSubject)
		end
	elseif killCam then
		local state, record = killCam, records[killCam.killer]
		if state.token ~= killCamToken or os.clock() >= state.endAt or player.Character ~= state.character
			or not GameActive.Value or not canUseCamera(state.subject) then stopKillTracking(true); return end
		if not record or not record.humanoid or record.humanoid.Health <= 0 then stopKillTracking(true); return end
		state.subject = record.humanoid
		writeSubject(state.subject)
	end
end
local function bindCamera()
	disconnect(cameraConnections)
	camera = Workspace.CurrentCamera
	if camera then
		table.insert(cameraConnections, camera:GetPropertyChangedSignal("CameraSubject"):Connect(refreshCamera))
		table.insert(cameraConnections, camera:GetPropertyChangedSignal("CameraType"):Connect(refreshCamera))
	end
	refreshCamera()
end
rebuildRoster = function()
	if not initialized then return end
	table.clear(roster)
	aliveCount, roundMembers = 0, 0
	for other, record in pairs(records) do
		if other.Parent == Players and other:GetAttribute("InRound") == true then
			if other ~= player then roundMembers += 1 end
			if record.character == other.Character and record.humanoid and record.humanoid.Health > 0 then
				aliveCount += 1
				if other ~= player then table.insert(roster, other) end
			end
		end
	end
	table.sort(roster, function(a, b) return a.UserId < b.UserId end)
	updateButton()
	if active then setTarget(table.find(roster, currentTarget) or spectateIndex) end
	if killCam then refreshCamera() end
	if brWait then tryBRSpectate() end
end
local function bindHumanoid(record)
	disconnect(record.humanoidConnections)
	local character = record.character
	record.humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if record.humanoid then
		local alive = record.humanoid.Health > 0
		table.insert(record.humanoidConnections, record.humanoid.HealthChanged:Connect(function(health)
			local nowAlive = health > 0
			if nowAlive ~= alive then alive = nowAlive; rebuildRoster() end
		end))
	end
	rebuildRoster()
	if record.player == player then
		refreshCamera()
		local intent = brIntent
		if intent and intent.resumeCharacter == record.character and record.humanoid and GameActive.Value then
			-- The server's lobby respawn may interrupt the brief death view. Its new
			-- native subject is still ours; finish the intended BR handoff once.
			if camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == intent.subject then
				writeSubject(record.humanoid)
			end
			runBRSpectate(intent.killer, record.character, killCamToken)
		end
	end
end
local function bindCharacter(record, character)
	disconnect(record.characterConnections)
	disconnect(record.humanoidConnections)
	record.character, record.humanoid = character, nil
	if character then
		local function childChanged(child)
			if child:IsA("Humanoid") and record.character == character then bindHumanoid(record) end
		end
		table.insert(record.characterConnections, character.ChildAdded:Connect(childChanged))
		table.insert(record.characterConnections, character.ChildRemoved:Connect(childChanged))
	end
	bindHumanoid(record)
end
local function bindKnife(record)
	disconnect(record.knifeConnections)
	record.equippedKnife = record.leaderstats and record.leaderstats:FindFirstChild("EquippedKnife")
	if record.equippedKnife and not record.equippedKnife:IsA("StringValue") then record.equippedKnife = nil end
	if record.equippedKnife then
		table.insert(record.knifeConnections, record.equippedKnife.Changed:Connect(function()
			if currentTarget == record.player then refreshTarget() end
		end))
	end
	if currentTarget == record.player then refreshTarget() end
end
local function bindLeaderstats(record)
	disconnect(record.statsConnections)
	record.leaderstats = record.player:FindFirstChild("leaderstats")
	if record.leaderstats then
		local function childChanged(child) if child.Name == "EquippedKnife" then bindKnife(record) end end
		table.insert(record.statsConnections, record.leaderstats.ChildAdded:Connect(childChanged))
		table.insert(record.statsConnections, record.leaderstats.ChildRemoved:Connect(childChanged))
	end
	bindKnife(record)
end
local function removePlayer(other)
	local record = records[other]
	if not record then return end
	records[other] = nil
	for _, key in ipairs({"connections", "characterConnections", "humanoidConnections", "statsConnections", "knifeConnections"}) do disconnect(record[key]) end
	rebuildRoster()
end
local function observePlayer(other)
	if records[other] then return end
	local record = {player = other, connections = {}, characterConnections = {}, humanoidConnections = {}, statsConnections = {}, knifeConnections = {}}
	records[other] = record
	local function connect(signal, callback) table.insert(record.connections, signal:Connect(callback)) end
	connect(other:GetAttributeChangedSignal("InRound"), function()
		if other == player then
			if other:GetAttribute("InRound") == true then SpectateHandler.StopSpectating()
			elseif brWait then tryBRSpectate() end
		end
		rebuildRoster()
	end)
	connect(other:GetAttributeChangedSignal("CurrentRoundKills"), function() if currentTarget == other then refreshTarget() end end)
	connect(other:GetPropertyChangedSignal("DisplayName"), function() if currentTarget == other then refreshTarget() end end)
	connect(other.CharacterAdded, function(character)
		if other == player then
			local preserve = brIntent and brIntent.waitingForSpawn and GameActive.Value
			cancelKillCam(preserve)
			if brIntent then brIntent.resumeCharacter = character; brIntent.waitingForSpawn = false end
		end
		bindCharacter(record, character)
	end)
	connect(other.CharacterRemoving, function(character)
		if other == player then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local preserve = brIntent and brIntent.character == character and humanoid and humanoid.Health <= 0
				and GameActive.Value
			cancelKillCam(preserve)
			if brIntent then brIntent.waitingForSpawn = true end
		end
		if record.character == character then bindCharacter(record, nil) end
	end)
	local function childChanged(child) if child.Name == "leaderstats" then bindLeaderstats(record) end end
	connect(other.ChildAdded, childChanged)
	connect(other.ChildRemoved, childChanged)
	bindLeaderstats(record)
	bindCharacter(record, other.Character)
end
local function runFFAKillCam(killer, endAt, character, token)
	local remaining = endAt - os.clock()
	local humanoid = ownHumanoid()
	if remaining <= 0 or not canUseCamera(humanoid) then return end
	killCam = {killer = killer, endAt = endAt, character = character, token = token, subject = humanoid}
	local state = killCam
	state.thread = task.delay(remaining, function()
		state.thread = nil
		if killCam == state then stopKillTracking(true) end
	end)
	refreshCamera()
end
tryBRSpectate = function()
	local wait = brWait
	if not wait or wait.token ~= killCamToken then return end
	if player.Character ~= wait.character or not GameActive.Value then cancelKillCam(); return end
	if player:GetAttribute("InRound") == true then return end
	if roundMembers == 0 then return end -- other round membership may replicate later
	local target = wait.killer
	if not canUseCamera(ownHumanoid()) then cancelKillCam(); return end
	SpectateHandler.StartSpectating(target)
end
runBRSpectate = function(killer, character, token)
	if brWait and brWait.thread then task.cancel(brWait.thread) end
	brWait = {killer = killer, character = character, token = token}
	local wait = brWait
	wait.thread = task.delay(Config.BRHandoffWaitSeconds, function()
		wait.thread = nil
		if brWait == wait then brWait, brIntent = nil, nil end
	end)
	tryBRSpectate()
end
local function beginReplicatedDeath(character, token, onReady)
	local deadline = os.clock() + Config.DeathReplicationWaitSeconds
	local expectedCamera = Workspace.CurrentCamera
	local function abortIntent() if brIntent and brIntent.token == token then brIntent = nil end end
	local function ready()
		if token ~= killCamToken or not initialized then return end
		pendingThread = nil
		if not GameActive.Value or not character or player.Character ~= character
			or Workspace.CurrentCamera ~= expectedCamera or not expectedCamera
			or expectedCamera.CameraType ~= Enum.CameraType.Custom then abortIntent(); return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and expectedCamera.CameraSubject ~= humanoid then abortIntent(); return end
		if not humanoid or humanoid.Health > 0 then
			-- Only this short death window retries: Health/remotes have no ordering guarantee.
			if os.clock() < deadline then pendingThread = task.delay(Config.DeathReplicationRetrySeconds, ready)
			else abortIntent() end
			return
		end
		deathTransition.Begin(character, onReady)
	end
	ready()
end
local function onKillCam(mode, killerUserId, duration, deathCharacter)
	if not GameActive.Value or type(killerUserId) ~= "number" or killerUserId ~= killerUserId
		or math.abs(killerUserId) == math.huge or killerUserId % 1 ~= 0
		or mode ~= "Respawn" and mode ~= "Spectate" then return end
	if deathCharacter ~= nil and deathCharacter ~= player.Character then return end
	local killer = killerUserId > 0 and Players:GetPlayerByUserId(killerUserId) or nil
	if killer == player or mode == "Respawn" and not killer then return end
	SpectateHandler.StopSpectating()
	local token, character = killCamToken, player.Character
	if mode == "Spectate" then brIntent = {killer = killer, character = character, token = token, subject = ownHumanoid()} end
	local seconds = tonumber(duration) or 2
	if seconds ~= seconds or math.abs(seconds) == math.huge then seconds = 2 end
	local endAt = os.clock() + math.clamp(seconds, 0.5, 5)
	beginReplicatedDeath(character, token, function()
		if token ~= killCamToken or not GameActive.Value or player.Character ~= character then return end
		if mode == "Respawn" then runFFAKillCam(killer, endAt, character, token)
		else runBRSpectate(killer, character, token) end
	end)
end
local function animateButton(button, visualTarget)
	local scale = (visualTarget or button):FindFirstChildOfClass("UIScale")
	if not scale then return end
	local info = TweenInfo.new(Config.ButtonTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweens = {
		TweenService:Create(scale, info, {Scale = 1.06}), TweenService:Create(scale, info, {Scale = 1}),
		TweenService:Create(scale, info, {Scale = 0.94}),
	}
	local current
	local function play(index)
		if current then current:Cancel() end
		current = tweens[index]; current:Play()
	end
	for _, tween in ipairs(tweens) do table.insert(buttonTweens, tween) end
	table.insert(connections, button.MouseEnter:Connect(function() play(1) end))
	table.insert(connections, button.MouseLeave:Connect(function() play(2) end))
	table.insert(connections, button.MouseButton1Down:Connect(function() play(3) end))
	table.insert(connections, button.MouseButton1Up:Connect(function() play(1) end))
	scale.Scale = 1
end
onUIRemoved = function(mainRemoved, currentMain)
	local resume = active or pendingUIResume and pendingUIResume.active
	local preferred = currentTarget or pendingUIResume and pendingUIResume.preferred
	SpectateHandler.Destroy()
	pendingUIResume = {active = resume, preferred = preferred}
	local function replaced(child)
		if child.Name ~= (mainRemoved and "Main" or "SpectateFrame") then return end
		disconnect(replacementConnections)
		replacementThread = task.delay(0, function()
			SpectateHandler.Init()
			if resume then SpectateHandler.StartSpectating(preferred) end
			pendingUIResume, replacementThread = nil, nil
		end)
	end
	table.insert(replacementConnections, PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "Main" then mainRemoved = true; replaced(child) end
	end))
	if not mainRemoved then table.insert(replacementConnections, (currentMain or MainGui).ChildAdded:Connect(replaced)) end
end
function SpectateHandler.Init()
	if initialized or initializing then return end
	initializing = true
	initGeneration += 1
	local token = initGeneration
	local ui = readUI()
	if token ~= initGeneration then return end
	disconnect(initialUIConnections)
	if ui.main.Parent ~= PlayerGui or ui.frame.Parent ~= ui.main then initializing = false; return end
	initializing = false
	pendingUIResume = nil
	disconnect(replacementConnections)
	MainGui, SpectateFrame, BottomFrame, ExitButton = ui.main, ui.frame, ui.bottom, ui.exit
	NameText, BottomNameText, KillsText, KnifeImage = ui.name, ui.bottomName, ui.kills, ui.knife
	ArrowLeft, ArrowRight, MatchText, SpectateButton = ui.left, ui.right, ui.match, ui.button
	StatusText, LobbyBottom = ui.status, ui.lobbyBottom
	initialized = true
	table.insert(connections, GameActive.Changed:Connect(function(isActive)
		if not isActive then SpectateHandler.StopSpectating() end
		updateButton()
	end))
	table.insert(connections, Timer.Changed:Connect(refreshMatch))
	table.insert(connections, player:GetAttributeChangedSignal("CurrentRoundMode"):Connect(refreshMatch))
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	table.insert(connections, Players.PlayerAdded:Connect(observePlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	table.insert(connections, ArrowLeft.MouseButton1Click:Connect(function() if active then setTarget(spectateIndex - 1) end end))
	table.insert(connections, ArrowRight.MouseButton1Click:Connect(function() if active then setTarget(spectateIndex + 1) end end))
	table.insert(connections, ExitButton.MouseButton1Click:Connect(SpectateHandler.StopSpectating))
	table.insert(connections, SpectateButton.MouseButton1Up:Connect(function()
		SpectateHandler.ToggleFrame()
		require(script.Parent.SoundHandler).PlaySound("ClickTopButtons")
	end))
	table.insert(connections, SpectateFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if active and not SpectateFrame.Visible then SpectateHandler.StopSpectating() end
	end))
	table.insert(connections, MainGui.Destroying:Connect(function() onUIRemoved(true) end))
	table.insert(connections, SpectateFrame.Destroying:Connect(function() onUIRemoved(false) end))
	if KillCamRemote then table.insert(connections, KillCamRemote.OnClientEvent:Connect(onKillCam)) end
	bindCamera()
	for _, other in ipairs(Players:GetPlayers()) do observePlayer(other) end
	SpectateHandler.StopSpectating(); updateButton()
	animateButton(ArrowLeft); animateButton(ArrowRight); animateButton(ExitButton, ExitButton.Parent)
end
function SpectateHandler.Destroy()
	initGeneration += 1
	initializing = false
	pendingUIResume = nil
	disconnect(initialUIConnections)
	disconnect(replacementConnections)
	if replacementThread then task.cancel(replacementThread); replacementThread = nil end
	if not initialized then return end
	SpectateHandler.StopSpectating()
	initialized = false
	disconnect(connections); disconnect(cameraConnections)
	for other in pairs(records) do removePlayer(other) end
	table.clear(roster)
	for _, tween in ipairs(buttonTweens) do tween:Cancel(); tween:Destroy() end
	table.clear(buttonTweens)
	SpectateButton.Visible = false
end
SpectateHandler.Init()
return SpectateHandler
