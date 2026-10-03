local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local Validation = require(RS.Modules.KeybindValidation)
local Combat = require(script.Parent.Modules.CombatController)
local binds = player:WaitForChild("leaderstats"):WaitForChild("KeyBinds")
local throwBind, stabBind = binds:WaitForChild("ThrowKnife"), binds:WaitForChild("Stab")
local heldInput
Combat.Init()

local function cancel()
	heldInput = nil
	Combat.CancelCharge()
end
UIS.InputBegan:Connect(function(input, processed)
	if processed or heldInput or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
	if Validation.Matches(throwBind.Value, input) or Validation.Matches(stabBind.Value, input) then
		if Combat.BeginCharge() then heldInput = input end
	end
end)
-- Always consume the matching release, including releases processed by a menu.
UIS.InputEnded:Connect(function(input)
	if input ~= heldInput then return end
	heldInput = nil
	if input.UserInputState == Enum.UserInputState.Cancel then Combat.CancelCharge() else Combat.ReleaseCharge() end
end)
UIS.WindowFocusReleased:Connect(cancel)
UIS.TextBoxFocused:Connect(cancel)
GuiService.MenuOpened:Connect(cancel)
throwBind.Changed:Connect(cancel)
stabBind.Changed:Connect(cancel)
player.CharacterRemoving:Connect(cancel)
return {}
