local controllers = {
	"BottomLeft",
	"DailyRewardsHandler",
	"Emote",
	"FramesHandler",
	"HandleKnifeCombat",
	"HandleRevolverCombat",
	"Hotbar",
	"InventoryGui",
	"KeyBindClient",
	"Leaderboards",
	"MobileHandler",
	"NotificationPopUp",
	"PlayerList",
	"QuestsHandlerClient",
	"RecieveTools",
	"RoundResults",
	"SettingsClient",
	"ShopGUI",
	"StartVoting",
	"TradingClient",
	"TutorialHandler",
	"ViewProfile",
}

require(script:WaitForChild("Modules"):WaitForChild("HandleGameUI"))

for _, controllerName in ipairs(controllers) do
	local controller = script:FindFirstChild(controllerName)
	if controller and controller:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(require, controller)
			if not ok then
				warn(("PlayerClient controller %s failed to start: %s"):format(controllerName, tostring(err)))
			end
		end)
	end
end
