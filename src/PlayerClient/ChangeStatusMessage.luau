local RS = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local label
local latest = RS:GetAttribute("GameStatus") or "WAITING FOR SERVER"
local function apply()
	if not label then return end
	if RS:GetAttribute("ServerStartupState") == "Failed" then
		label.Text = "SERVER COULD NOT START"
	elseif RS:GetAttribute("ServerReady") == false then
		label.Text = "WAITING FOR SERVER"
	else
		label.Text = latest
	end
end
-- Subscribe before waiting for UI. Keep only the latest status during loading.
RS:GetAttributeChangedSignal("GameStatus"):Connect(function()
	latest = RS:GetAttribute("GameStatus") or ""
	apply()
end)
RS:GetAttributeChangedSignal("ServerStartupState"):Connect(apply)
RS:GetAttributeChangedSignal("ServerReady"):Connect(apply)
local remote = RS:WaitForChild("Remotes"):WaitForChild("ChangeStatus")
remote.OnClientEvent:Connect(function(value)
	if type(value) == "string" then latest = value; apply() end
end)
label = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("SystemTexts"):WaitForChild("Status")
apply()
return {}
