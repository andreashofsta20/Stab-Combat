local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Combat = require(script.Parent.Modules.CombatController)
local Revolver = require(script.Parent.Modules.RevolverController)
local Knives = require(RS.Modules.KnivesInfo)
local ui = player:WaitForChild("PlayerGui"):WaitForChild("Main")
local frame = ui:WaitForChild("MobileFrame")
local controls = frame:WaitForChild("BasicControls")
local throwButton, shiftButton = controls:WaitForChild("Throw"), frame:WaitForChild("ShiftLock")
local shiftImage = frame:WaitForChild("ShiftLockToogled")
local oldCrosshair = frame:WaitForChild("MobileCrosshair")
local emoteFrame = ui:WaitForChild("EmoteFrame"):WaitForChild("background")
local gameActive = RS:WaitForChild("GameActive")
local mobile, shifted, heldTouch, humanoid = false, false, nil, nil
local connections = {}
oldCrosshair.Visible = false
local customJump = controls:FindFirstChild("Jump")
if customJump then customJump.Visible = false end

local function decorate(button, active)
	local deco = button:FindFirstChild("deco")
	if deco then deco.ImageColor3 = active and Color3.fromRGB(0, 184, 255) or Color3.new(1, 1, 1) end
end
local function cancel()
	heldTouch = nil
	Combat.CancelCharge()
	Combat.SetTouchAimPosition(nil)
	decorate(throwButton, false)
end
local function setShift(enabled)
	shifted = enabled == true and mobile
	local deco = shiftButton:FindFirstChild("deco")
	if deco then deco.Image = shifted and "rbxassetid://13848672949" or "rbxassetid://13848680756" end
	decorate(shiftButton, shifted)
	shiftImage.Visible = mobile and shifted
	Combat.SetMobileShiftLock(shifted)
	Revolver.SetMobileShiftLock(shifted)
	if not shifted and humanoid then humanoid.AutoRotate = true end
end
local function knifeEquipped()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and Knives[tool.Name] ~= nil
end
local function refresh()
	oldCrosshair.Visible = false
	shiftImage.Visible = mobile and shifted
	throwButton.Visible = mobile and knifeEquipped() and gameActive.Value and player:GetAttribute("InRound") == true
end
local function inputMode()
	mobile = UIS.PreferredInput == Enum.PreferredInput.Touch
	frame.Visible = mobile
	Combat.SetInputMode(mobile)
	if not mobile then cancel(); setShift(false) end
	refresh()
end
local function onCharacter(character)
	cancel()
	setShift(false)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	local hum
	repeat hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 2)
	until hum or player.Character ~= character
	if not hum or player.Character ~= character then return end
	humanoid = hum
	table.insert(connections, character.ChildAdded:Connect(refresh))
	table.insert(connections, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then cancel(); refresh() end
	end))
	table.insert(connections, hum.Died:Connect(function() cancel(); setShift(false); refresh() end))
	refresh()
end
throwButton.InputBegan:Connect(function(input)
	if not mobile or heldTouch or input.UserInputType ~= Enum.UserInputType.Touch then return end
	-- The action button aims at the visible center dot; camera/joystick fingers
	-- cannot begin a charge or release a different finger's charge.
	Combat.SetTouchAimPosition(nil)
	if Combat.BeginCharge() then heldTouch = input; decorate(throwButton, true) end
end)
UIS.InputEnded:Connect(function(input)
	if input ~= heldTouch then return end
	heldTouch = nil
	decorate(throwButton, false)
	if input.UserInputState == Enum.UserInputState.Cancel then Combat.CancelCharge() else Combat.ReleaseCharge() end
end)
UIS.TouchTapInWorld:Connect(function(position, processed)
	if not mobile or processed or heldTouch or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() then return end
	if Revolver.HasRevolverEquipped() then
		if shifted then Revolver.Fire() else Revolver.Fire(position) end
	elseif knifeEquipped() then Combat.Stab() end
end)
shiftButton.Activated:Connect(function() setShift(not shifted) end)
controls:WaitForChild("Emote").Activated:Connect(function() emoteFrame.Visible = not emoteFrame.Visible end)
UIS:GetPropertyChangedSignal("PreferredInput"):Connect(inputMode)
UIS.WindowFocusReleased:Connect(cancel)
UIS.TextBoxFocused:Connect(cancel)
GuiService.MenuOpened:Connect(cancel)
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(function() cancel(); setShift(false); humanoid = nil; refresh() end)
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
gameActive.Changed:Connect(function() cancel(); refresh() end)
RunService:BindToRenderStep("MobileShiftLock", Enum.RenderPriority.Camera.Value + 2, function()
	if not mobile or not shifted or Revolver.IsAiming() or not humanoid or humanoid.Health <= 0 then return end
	local character, camera = player.Character, workspace.CurrentCamera
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not camera then return end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then return end
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
end)
Combat.Init()
inputMode()
setShift(false)
if player.Character then onCharacter(player.Character) end
return {}
