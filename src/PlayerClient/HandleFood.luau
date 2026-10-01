local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.FoodConfig)
local player = Players.LocalPlayer
local gameActive = ReplicatedStorage:WaitForChild("GameActive")
local eatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Food"):WaitForChild("Eat")
local character, heldTool, toolConnection, tickConnection
local characterConnections = {}
local lastRequest = 0
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "FoodHUD", false, true, 21
gui.Enabled, gui.Parent = false, player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.AnchorPoint, label.Position, label.Size = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.88), UDim2.fromOffset(340, 58)
label.BackgroundTransparency, label.TextColor3, label.TextStrokeTransparency = 1, Color3.new(1, 1, 1), 0.4
label.Font, label.TextSize, label.Parent = Enum.Font.GothamBold, 20, gui
local button = Instance.new("TextButton")
button.AnchorPoint, button.Position, button.Size = Vector2.new(1, 1), UDim2.new(1, -12, 0.63, 0), UDim2.fromOffset(80, 52)
button.Text, button.Font, button.TextSize = "EAT", Enum.Font.GothamBold, 18
button.BackgroundColor3, button.TextColor3, button.Parent = Color3.fromRGB(35, 35, 45), Color3.new(1, 1, 1), gui

local function canUse()
	if not heldTool or heldTool.Parent ~= character or player.Character ~= character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return gameActive.Value and player:GetAttribute("InRound") == true and player:GetAttribute("DataReady") == true
		and humanoid and humanoid.Health > 0 and (player:GetAttribute("FoodUses") or 0) > 0
end

local function menuOpen()
	if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return true end
	local main = player.PlayerGui:FindFirstChild("Main")
	local frames = main and main:FindFirstChild("Frames")
	if frames then
		for _, frame in ipairs(frames:GetChildren()) do if frame:IsA("GuiObject") and frame.Visible then return true end end
	end
	local emote = main and main:FindFirstChild("EmoteFrame")
	local background = emote and emote:FindFirstChild("background")
	return background and background.Visible
end

local function eat()
	if not canUse() or menuOpen() then return end
	local time = workspace:GetServerTimeNow()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid.Health >= humanoid.MaxHealth or time < (player:GetAttribute("FoodReadyAt") or 0) or time - lastRequest < 0.2 then return end
	lastRequest = time
	eatRemote:FireServer(heldTool)
end
button.Activated:Connect(eat)

local function refresh()
	gui.Enabled = canUse() == true and not menuOpen()
	if not gui.Enabled then return end
	local remaining = player:GetAttribute("FoodUses") or 0
	local cooldown = math.max(0, (player:GetAttribute("FoodReadyAt") or 0) - workspace:GetServerTimeNow())
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local status = cooldown > 0 and string.format("Ready in %.1fs", cooldown)
		or (humanoid.Health >= humanoid.MaxHealth and "Health is full" or string.format("Click to eat  |  +%d health", Config.HealAmount))
	label.Text = string.format("BURGER  %d/%d bites left\n%s", remaining, Config.Capacity, status)
	button.Visible = UserInputService.TouchEnabled
end

local function setHeld(tool)
	if heldTool == tool then return end
	if toolConnection then toolConnection:Disconnect(); toolConnection = nil end
	if tickConnection then tickConnection:Disconnect(); tickConnection = nil end
	heldTool = tool
	if tool then
		toolConnection = tool.Activated:Connect(eat)
		local elapsed = 0
		tickConnection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed >= 0.1 then elapsed = 0; refresh() end
		end)
	end
	refresh()
end

local function onCharacter(newCharacter)
	setHeld(nil)
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	character = newCharacter
	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("FoodItem") == Config.ToolName then setHeld(child) end
	end))
	table.insert(characterConnections, character.ChildRemoved:Connect(function(child) if child == heldTool then setHeld(nil) end end))
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("FoodItem") == Config.ToolName then setHeld(child); break end
	end
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(function() setHeld(nil) end)
player:GetAttributeChangedSignal("FoodUses"):Connect(refresh)
player:GetAttributeChangedSignal("FoodReadyAt"):Connect(refresh)
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
gameActive.Changed:Connect(refresh)
if player.Character then onCharacter(player.Character) end
return {}
