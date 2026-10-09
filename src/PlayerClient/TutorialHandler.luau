-- One controller and one remote subscription across character respawns.
-- Progress / eligibility / rewards arrive only in server snapshots.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Modules.TutorialUIConfig)
local Validation = require(ReplicatedStorage.Modules.KeybindValidation)
local TutorialUI = require(script.Parent.Modules.TutorialUI)
local TutorialGuidance = require(script.Parent.Modules.TutorialGuidance)
local TutorialGamepadBridge = require(script.Parent.Modules.TutorialGamepadBridge)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 20)
local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
local tutorialRemotes = remotes and remotes:WaitForChild("Tutorial", 20)
local remote = tutorialRemotes and tutorialRemotes:WaitForChild("StartTutorial", 20)
if not playerGui or not remote or not remote:IsA("RemoteEvent") then
	warn("[Tutorial] Tutorial UI could not start: required player GUI or tutorial remote is unavailable.")
	return {}
end
local Controller = {}
local connections, bindConnections = {}, {}
local destroyed, requested, pending = false, false, false
local requestGeneration, lastRequest = 0, -math.huge
local keybindFolder, statsFolder
local defaults = Validation.GetDefaults()
local view, guidance, gamepadBridge

local function connect(signal, callback, list)
	table.insert(list or connections, signal:Connect(callback))
end

local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

local function hintFor(step)
	local action = type(step.HintAction) == "string" and step.HintAction or nil
	local hint = type(step.Hint) == "string" and step.Hint or ""
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		local template = Config.GamepadHints and (Config.GamepadHints[action] or Config.GamepadHints[step.Kind])
		if not template then return hint end
		return (template:gsub("{(%w+)}", function(name)
			local key = Config.Gamepad.Keys[name]
			return Config.Gamepad.Display[key] or key or name
		end))
	end
	if not action then return hint end
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return Config.TouchHints[action] or hint
	end
	local template = Config.KeyboardHints[action]
	if not template then return hint end
	if not template:find("{key}", 1, true) then return template end
	local stored = keybindFolder and keybindFolder:FindFirstChild(action)
	local raw = stored and stored:IsA("StringValue") and stored.Value or defaults[action]
	local display = Validation.ToDisplay(raw)
	if display == "" then return hint end
	return (template:gsub("{key}", function() return display end))
end

local function lobbyVisibility()
	if not view then return end
	view.SetLobbyVisible(player:GetAttribute("DataReady") == true
		and ReplicatedStorage:GetAttribute("ServerReady") == true
		and ReplicatedStorage:GetAttribute("TutorialAvailable") == true
		and player:GetAttribute("InRound") ~= true
		and player:GetAttribute("TutorialActive") ~= true)
end

local function request(action)
	if destroyed or pending or os.clock() - lastRequest < Config.ActionDebounceSeconds then return end
	local leaving = action=="Return" and ReplicatedStorage:GetAttribute("TutorialPlace")==true
	if not leaving and (player:GetAttribute("DataReady") ~= true or ReplicatedStorage:GetAttribute("ServerReady") ~= true) then return end
	lastRequest, pending = os.clock(), true
	requestGeneration += 1
	local generation = requestGeneration
	view.SetBusy(true)
	remote:FireServer(action)
	-- Bounded timer per explicit request, never a polling/render-loop remote.
	task.delay(Config.ResponseTimeoutSeconds, function()
		if destroyed or not pending or requestGeneration ~= generation then return end
		pending = false
		view.ShowRecovery(Config.Text.Timeout, "Status")
		lobbyVisibility()
	end)
end

view = TutorialUI.new(playerGui, request, hintFor)
guidance = TutorialGuidance.new(playerGui, view.SetGuidance, view.PulseCompletion)
gamepadBridge = TutorialGamepadBridge.new()

local function observeKeybinds()
	if destroyed then return end
	disconnect(bindConnections)
	statsFolder = player:FindFirstChild("leaderstats")
	keybindFolder = statsFolder and statsFolder:FindFirstChild("KeyBinds")
	if statsFolder then
		connect(statsFolder.ChildAdded, observeKeybinds, bindConnections)
		connect(statsFolder.ChildRemoved, observeKeybinds, bindConnections)
	end
	if keybindFolder then
		connect(keybindFolder.ChildAdded, observeKeybinds, bindConnections)
		connect(keybindFolder.ChildRemoved, observeKeybinds, bindConnections)
		for _, value in ipairs(keybindFolder:GetChildren()) do
			if value:IsA("StringValue") then connect(value.Changed, view.RefreshHints, bindConnections) end
		end
	end
	view.RefreshHints()
end

local modes = {Offer = true, Loading = true, Active = true, Complete = true, Error = true, Hidden = true}
connect(remote.OnClientEvent, function(snapshot)
	if destroyed or type(snapshot) ~= "table" or not modes[snapshot.Mode] then return end
	requestGeneration += 1
	pending = false
	if snapshot.Mode == "Loading" and snapshot.Message == "Preparing travel..." then
		view.HideTravelLoading()
		lobbyVisibility()
		return
	end
	view.Update(snapshot)
	guidance.Update(snapshot)
	lobbyVisibility()
end)

local function requestWhenReady()
	if destroyed then return end
	lobbyVisibility()
	if requested or player:GetAttribute("DataReady") ~= true
		or ReplicatedStorage:GetAttribute("ServerReady") ~= true then return end
	requested = true
	request("Status")
end

function Controller.Destroy()
	if destroyed then return end
	destroyed = true
	requestGeneration += 1
	disconnect(connections); disconnect(bindConnections)
	gamepadBridge.Destroy()
	guidance.Destroy()
	view.Destroy()
end

connect(player:GetAttributeChangedSignal("DataReady"), requestWhenReady)
connect(ReplicatedStorage:GetAttributeChangedSignal("ServerReady"), requestWhenReady)
connect(ReplicatedStorage:GetAttributeChangedSignal("TutorialAvailable"), lobbyVisibility)
connect(player:GetAttributeChangedSignal("InRound"), lobbyVisibility)
connect(player:GetAttributeChangedSignal("TutorialActive"), lobbyVisibility)
connect(player.ChildAdded, function(child) if child.Name == "leaderstats" then observeKeybinds() end end)
connect(player.ChildRemoved, function(child) if child == statsFolder then observeKeybinds() end end)
connect(script.Destroying, Controller.Destroy)
observeKeybinds(); requestWhenReady()
return Controller
