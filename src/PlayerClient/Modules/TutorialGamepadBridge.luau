-- Fills tutorial-only controller input gaps using the existing combat APIs
-- and equipment/food remotes. The server still validates every action.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage.Modules.TutorialUIConfig).Gamepad
local FoodConfig = require(ReplicatedStorage.Modules.FoodConfig)
local Bridge = {}

function Bridge.new()
	local self = {}
	local player = Players.LocalPlayer
	local connections, characterConnections, boundActions = {}, {}, {}
	local destroyed, enabled, chargeTool, observedCharacter = false, false, nil, nil
	local lastEquip, lastEat = -math.huge, -math.huge
	local Combat
	local owner = script.Parent.Parent
	local knifeInput = owner and owner:FindFirstChild("HandleKnifeCombat")
	local combatModule = script.Parent:FindFirstChild("CombatController")
	local function combatReady()
		if Combat then return Combat end
		-- The ordinary knife input module has already required/initialized this
		-- controller when Ready. A cached require cannot wait on missing assets.
		if not combatModule or not knifeInput or knifeInput:GetAttribute("StartupState") ~= "Ready" then return nil end
		local ok, result = pcall(require, combatModule)
		if ok then Combat = result end
		return Combat
	end
	local function connect(signal, callback, list) table.insert(list or connections, signal:Connect(callback)) end
	local function disconnect(list)
		for _, connection in ipairs(list) do connection:Disconnect() end
		table.clear(list)
	end
	local function heldTool()
		local character = player.Character
		return character and character:FindFirstChildOfClass("Tool")
	end
	local function category(tool)
		if not tool then return nil end
		if tool:GetAttribute("FoodItem") == FoodConfig.ToolName then return "Food" end
		local knives, revolvers = ReplicatedStorage:FindFirstChild("Knives"), ReplicatedStorage:FindFirstChild("Revolvers")
		if knives and knives:FindFirstChild(tool.Name) then return "Knife" end
		if revolvers and revolvers:FindFirstChild(tool.Name) then return "Revolver" end
		return nil
	end
	local function cancelCharge()
		if not chargeTool then return end
		chargeTool = nil
		Combat.CancelCharge()
	end
	local function allowed()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return not destroyed and Config.Enabled and player:GetAttribute("TutorialActive") == true
			and player:GetAttribute("InRound") == true and player:GetAttribute("DataReady") == true
			and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
			and character == observedCharacter and humanoid and humanoid.Health > 0
	end
	local function blocked()
		if not allowed() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()
			or player:GetAttribute("TutorialTravelPending") == true then return true end
		local gui = player:FindFirstChildOfClass("PlayerGui")
		local main = gui and gui:FindFirstChild("Main")
		local frames = main and main:FindFirstChild("Frames")
		if frames then
			for _, frame in ipairs(frames:GetChildren()) do if frame:IsA("GuiObject") and frame.Visible then return true end end
		end
		local training = gui and gui:FindFirstChild("TrainingGui")
		local safeArea = training and training:FindFirstChild("SafeArea")
		local modal = safeArea and safeArea:FindFirstChild("Modal")
		if modal and modal.Visible then return true end
		local selected = GuiService.SelectedObject
		if training and selected and selected:IsDescendantOf(training) then return true end
		local emote = main and main:FindFirstChild("EmoteFrame")
		local background = emote and emote:FindFirstChild("background")
		return background and background.Visible or false
	end
	local function findRemote(folderName, name)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local folder = remotes and remotes:FindFirstChild(folderName)
		local remote = folder and folder:FindFirstChild(name)
		return remote and remote:IsA("RemoteEvent") and remote or nil
	end
	local function equip(desired)
		if blocked() then return Enum.ContextActionResult.Pass end
		local now = os.clock()
		if category(heldTool()) == desired or now - lastEquip < Config.RequestCooldownSeconds then return Enum.ContextActionResult.Sink end
		if desired == "Food" and (player:GetAttribute("FoodUses") or 0) <= 0 then return Enum.ContextActionResult.Sink end
		local remote = findRemote("HotBar", "Equip")
		if remote then lastEquip = now; cancelCharge(); remote:FireServer(desired) end
		return Enum.ContextActionResult.Sink
	end
	local function eat(tool)
		local now = workspace:GetServerTimeNow()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health >= humanoid.MaxHealth or (player:GetAttribute("FoodUses") or 0) <= 0
			or now < (player:GetAttribute("FoodReadyAt") or 0) or now - lastEat < Config.RequestCooldownSeconds then return end
		local remote = findRemote("Food", "Eat")
		if remote then lastEat = now; remote:FireServer(tool) end
	end
	local function fire(_, state)
		-- An admitted release completes only the charge started by this bridge.
		if chargeTool and (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) then
			local valid = state == Enum.UserInputState.End and not blocked() and heldTool() == chargeTool
			chargeTool = nil
			if valid then Combat.ReleaseCharge() else Combat.CancelCharge() end
			return Enum.ContextActionResult.Sink
		end
		local tool = heldTool()
		local kind = category(tool)
		-- Pass RT through to the existing revolver controller (fire / ADS /
		-- reload). This bridge never invokes that controller a second time.
		if kind == "Revolver" or (kind ~= "Knife" and kind ~= "Food") or blocked() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then
			if kind == "Food" then eat(tool)
			else
				local controller = combatReady()
				if controller and not chargeTool and controller.BeginCharge() then chargeTool = tool end
			end
		end
		return Enum.ContextActionResult.Sink
	end
	local function stab(_, state)
		if blocked() or category(heldTool()) ~= "Knife" then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then local controller = combatReady(); if controller then controller.Stab() end end
		return Enum.ContextActionResult.Sink
	end
	local function unbind()
		cancelCharge()
		for name in pairs(boundActions) do ContextActionService:UnbindAction(name) end
		table.clear(boundActions)
		enabled = false
	end
	local function bind(action, callback)
		local key = Enum.KeyCode[Config.Keys[action]]
		if not key then return end
		local name = "TutorialGamepad" .. action
		ContextActionService:BindActionAtPriority(name, callback, false, Enum.ContextActionPriority.High.Value + Config.PriorityOffset, key)
		boundActions[name] = true
	end
	local function refresh()
		if destroyed then return end
		if not allowed() then if enabled then unbind() end; return end
		if enabled then return end
		enabled = true
		for _, desired in ipairs({"Knife", "Revolver", "Food"}) do
			bind(desired, function(_, state)
				if state == Enum.UserInputState.Begin then return equip(desired) end
				return blocked() and Enum.ContextActionResult.Pass or Enum.ContextActionResult.Sink
			end)
		end
		bind("ThrowEat", fire); bind("Stab", stab)
	end
	local function onCharacter(character)
		disconnect(characterConnections); unbind()
		observedCharacter = character
		if not character then return end
		local observedHumanoid
		local function observeHumanoid()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid ~= observedHumanoid then
				observedHumanoid = humanoid
				connect(humanoid.Died, unbind, characterConnections)
			end
			refresh()
		end
		connect(character.ChildAdded, observeHumanoid, characterConnections)
		connect(character.ChildRemoved, function(child) if child == chargeTool then cancelCharge() end; refresh() end, characterConnections)
		observeHumanoid()
	end
	connect(player:GetAttributeChangedSignal("TutorialActive"), refresh)
	connect(player:GetAttributeChangedSignal("InRound"), refresh)
	connect(player:GetAttributeChangedSignal("DataReady"), refresh)
	connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), refresh)
	connect(UserInputService.WindowFocusReleased, cancelCharge)
	connect(UserInputService.TextBoxFocused, cancelCharge)
	connect(GuiService.MenuOpened, cancelCharge)
	connect(player.CharacterAdded, onCharacter)
	connect(player.CharacterRemoving, function(character) if character == observedCharacter then onCharacter(nil) end end)
	function self.Destroy()
		if destroyed then return end
		destroyed = true; disconnect(connections); disconnect(characterConnections); unbind()
	end
	onCharacter(player.Character)
	return self
end

return Bridge
