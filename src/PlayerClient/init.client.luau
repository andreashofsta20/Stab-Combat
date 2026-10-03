local RS = game:GetService("ReplicatedStorage")
local Loader = require(RS:WaitForChild("Modules"):WaitForChild("StartupLoader"))
local modules = script:WaitForChild("Modules")
local controllers = {
	"ChangeStatusMessage", "CountDownText", "FramesHandler",
	"HandleKnifeCombat", "HandleRevolverCombat", "HandleFood", "HandleWeaponCursor",
	"Hotbar", "MobileHandler", "RecieveTools", "RoundResults", "ZoneMessageClient",
	"BottomLeft", "DailyRewardsHandler", "Emote", "InventoryGui", "KeyBindClient",
	"KeybindDisplaying", "Leaderboards", "NotificationPopUp", "PlayerList",
	"PlayerHover", "PlayerOverHead", "QuestsHandlerClient", "SettingsClient",
	"ShopGUI", "StartVoting", "TradingClient", "TutorialHandler", "ViewProfile",
}
local entries = {
	{Name = "HitFeedback", Module = modules:FindFirstChild("HitFeedback"), Init = function(module) module.Init() end},
	{Name = "HandleGameUI", Module = modules:FindFirstChild("HandleGameUI")},
}
for _, name in ipairs(controllers) do
	table.insert(entries, {Name = name, Module = script:FindFirstChild(name)})
end
Loader.Start(script, entries)
