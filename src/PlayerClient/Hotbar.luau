repeat task.wait() until game:IsLoaded()

-- // SERVICES // --
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // PLAYER // --
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Backpack = Player.Backpack

local leaderstats = Player:WaitForChild("leaderstats")
local EquippedKnife = leaderstats:WaitForChild("EquippedKnife")

-- // PLAYERGUI // --
local PlayerGui = Player.PlayerGui
local MainUI = PlayerGui:WaitForChild("Main")


-- // FRAMES // --
local HotbarFrame = MainUI:WaitForChild("Bottom")

-- // REMOTES // --
local RemotesFolder = RS:WaitForChild("Remotes")
local HotBarRemots = RemotesFolder:WaitForChild("HotBar")


local ServerRemote = HotBarRemots:WaitForChild("Equip")
local EquippedClient = HotBarRemots:WaitForChild("EquippedClient")


-- // MODULES // --
local KnivesModule = require(RS:WaitForChild("Modules"):WaitForChild("KnivesInfo"))






local leaderstats = Player:WaitForChild("leaderstats")
local KeyBindsFolder = leaderstats:WaitForChild("KeyBinds")

local Slot1Keybind
local Slot2Keybind
local Slot3Keybind



local function parseInput(inputString)
	if not inputString or inputString == "" then
		return nil
	end

	if inputString:find("Enum.KeyCode.") then
		local keyName = inputString:match("Enum%.KeyCode%.(.+)")
		if keyName and Enum.KeyCode[keyName] then
			return Enum.KeyCode[keyName]
		end
	elseif inputString == "MouseButton1" then
		return "MouseButton1"
	end
	return nil
end


local function initializeKeybinds()
	-- Wait for keybind values to be properly set
	local slot1 = KeyBindsFolder:WaitForChild("Slot1")
	local slot2 = KeyBindsFolder:WaitForChild("Slot2")
	local slot3 = KeyBindsFolder:WaitForChild("Slot3")

	-- Small delay to ensure server has set values
	if slot1.Value == "" or slot1.Value == nil then
		task.wait(0.1)
	end

	-- Parse and set keybinds with fallbacks
	Slot1Keybind = parseInput(slot1.Value) or Enum.KeyCode.One
	Slot2Keybind = parseInput(slot2.Value) or Enum.KeyCode.Two
	Slot3Keybind = parseInput(slot3.Value) or Enum.KeyCode.Three

	print("Initialized keybinds:")
	print("Slot1:", Slot1Keybind)
	print("Slot2:", Slot2Keybind)
	print("Slot3:", Slot3Keybind)
end

initializeKeybinds()








local function TweenSize(guiObject, targetSize, duration)
	local tweenInfo = TweenInfo.new(duration or 0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(guiObject, tweenInfo, {Size = targetSize})
	tween:Play()
end

local function CheckToolEquipped()
	for i , v in pairs(Character:GetChildren()) do
		if v:IsA("Tool") then
			return print(v.Name)
		end
	end
end

local function SetKnifeEquippedUI(equipped)
	local KnifeSlot = HotbarFrame:WaitForChild("1")
	local slotSelected = KnifeSlot:WaitForChild("SlotSelected")
	slotSelected.Visible = equipped

	if equipped then
		TweenSize(KnifeSlot, UDim2.new(0.081, 5, 1.054, 5))
	else
		TweenSize(KnifeSlot, UDim2.new(0.077, 5, 1, 5))
	end
end


local function EquipKnife(SlotEquipped)
	ServerRemote:FireServer("Knife")
end




local function EquipTool(SlotEquipped)
	
	if SlotEquipped == 1 then
		EquipKnife()
		return
	end
	
	if SlotEquipped == 2 then
		return
	end
	
	print(SlotEquipped)


end


UserInputService.InputBegan:Connect(function(key, GameProceed)
	

	if key.UserInputType == Enum.UserInputType.Keyboard then
		if key.KeyCode == Slot1Keybind then
			EquipTool(1)
		elseif key.KeyCode == Slot2Keybind then
			EquipTool(2)
		elseif key.KeyCode == Slot3Keybind then
			EquipTool(3)
		end
	end
	
end)





for i , v in pairs(HotbarFrame:GetChildren()) do
	if v:IsA("ImageButton") then
		v.MouseButton1Up:Connect(function()
			EquipTool(tonumber(v.Name))
		end) 
		v.MouseEnter:Connect(function()
			TweenSize(v, UDim2.new(0.081, 5, 1.054, 5))
		end)

		v.MouseLeave:Connect(function()
			if v:WaitForChild("SlotSelected").Visible then
				return
			end
			TweenSize(v, UDim2.new(0.077, 5, 1, 5))
		end)
	end
end




local function RefreshHotBar()
	local leaderstats = Player:WaitForChild("leaderstats")
	local EquippedKnife = leaderstats:WaitForChild("EquippedKnife")
	
	local KnifeInfo = KnivesModule[EquippedKnife.Value]
	
	if KnifeInfo then
		HotbarFrame:WaitForChild("1").SlotImage.Image = KnifeInfo.Image
	end
	
	
	
end


EquippedClient.OnClientEvent:Connect(function(action, EquippedOrNot)
	if action == "Knife" then
		SetKnifeEquippedUI(EquippedOrNot)
	else
		print("no valid arguments")
	end
end)

-- Reset UI on respawn and when tools are removed without a remote event
local function HookCharacter(char)
	Character = char
	SetKnifeEquippedUI(false)

	Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			SetKnifeEquippedUI(false)
		end
	end)
	Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			SetKnifeEquippedUI(true)
		end
	end)
end

Player.CharacterAdded:Connect(HookCharacter)
if Character then
	HookCharacter(Character)
end


EquippedKnife:GetPropertyChangedSignal("Value"):Connect(RefreshHotBar)










KeyBindsFolder:WaitForChild("Slot1").Changed:Connect(function()
	local newValue = KeyBindsFolder.Slot1.Value
	local newInput = parseInput(newValue)
	if newInput then
		Slot1Keybind = newInput
	else
		print("oops")
	end
end)

KeyBindsFolder:WaitForChild("Slot2").Changed:Connect(function()
	local newValue = KeyBindsFolder.Slot2.Value
	local newInput = parseInput(newValue)
	if newInput then
		Slot2Keybind = newInput
	else
		print("oops")
	end
end)


KeyBindsFolder:WaitForChild("Slot3").Changed:Connect(function()
	local newValue = KeyBindsFolder.Slot3.Value
	local newInput = parseInput(newValue)
	if newInput then
		Slot3Keybind = newInput
	else
		print("oops")
	end
end)





RefreshHotBar()









return {}