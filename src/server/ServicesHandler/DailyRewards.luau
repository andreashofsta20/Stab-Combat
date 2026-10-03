local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Inventory = require(script.Parent.Parent.DataStore.InventoryHandler)
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local Notifications = require(script.Parent.Parent.Game.SendNotification)
local Quests = require(script.Parent.QuestsHandler)
local Config = require(RS.Modules.DailyRewardsConfig)
local Math = require(RS.Modules.RewardMath)
local remotes = RS:WaitForChild("Remotes"):WaitForChild("DailyRewards")
local request, response = remotes:WaitForChild("ClaimDailyReward"), remotes:WaitForChild("DailyRewardClient")
local nextStatus, nextClaim = {}, {}

local function values(player)
	local profile = Profiles.GetProfile(player)
	if player:GetAttribute("DataReady") ~= true or not profile or not profile:IsActive() then return nil end
	local stats = player:FindFirstChild("leaderstats")
	local daily = stats and stats:FindFirstChild("DailyRewards")
	local last, streak = daily and daily:FindFirstChild("LastClaimTime"), daily and daily:FindFirstChild("Streak")
	if not last or not streak then return nil end
	return stats, last, streak, profile
end
local function status(player)
	local stats, last, streak = values(player)
	if not stats then return {Loading = true, CanClaim = false, ServerTime = os.time()} end
	local payload = Math.DailyStatus(last.Value, streak.Value, os.time(), Config.DaySeconds, #Config.Rewards)
	payload.Rewards = Config.Rewards
	return payload
end
local function claim(player, day)
	local now = os.clock()
	if now < (nextClaim[player] or 0) then return false, "Please wait a moment" end
	nextClaim[player] = now + Config.ClaimCooldown
	if not Math.IsFinite(day) or day % 1 ~= 0 then return false, "Invalid reward" end
	local stats, last, streak, profile = values(player)
	if not stats then return false, "Your rewards are still loading" end
	local current = status(player)
	if not current.CanClaim then return false, "Already claimed" end
	if day ~= current.CurrentDayIndex then return false, "Reward unavailable" end
	local reward = Config.Rewards[day]
	if not reward then return false, "Invalid reward" end
	local cash, xp = stats:FindFirstChild("Cash"), stats:FindFirstChild("XP")
	if (reward.Cash and not cash) or (reward.XP and not xp) then return false, "Reward unavailable" end
	-- Validate all prerequisites before granting anything. These inventory calls
	-- do not yield once the already-hydrated folders exist.
	if reward.Item then
		local item = reward.Item
		local folder = stats:FindFirstChild(item.Type == "Knife" and "Inventory" or "Emotes")
		if not folder then return false, "Inventory is still loading" end
		local granted
		if item.Type == "Knife" then granted = Inventory.AddKnife(player, item.Name)
		elseif item.Type == "Emote" then granted = Inventory.AddEmote(player, item.Name) end
		if not granted then return false, "Reward could not be granted" end
	end
	if reward.Cash then cash.Value += reward.Cash end
	if reward.XP then xp.Value += reward.XP end
	last.Value, streak.Value = current.ServerTime, current.Streak + 1
	profile.Data.DailyRewards = {LastClaimTime = last.Value, Streak = streak.Value}
	Quests.AddProgress(player, "DAILY_REWARD_CLAIMS", 1)
	-- Reward, timestamp, inventory and quests are captured in one profile save.
	Profiles.SaveProfile(player)
	return true
end
request.OnServerEvent:Connect(function(player, action, day)
	if action == "GetStatus" then
		local now = os.clock()
		if now < (nextStatus[player] or 0) then return end
		nextStatus[player] = now + Config.StatusCooldown
	elseif action == "Claim" then
		if os.clock() < (nextClaim[player] or 0) then return end
		local ok, message = claim(player, day)
		Notifications.SendNotification(player, ok and "Daily reward claimed!" or message, 3, ok and "Success" or "Error")
	else return end
	response:FireClient(player, status(player))
end)
Players.PlayerRemoving:Connect(function(player) nextClaim[player], nextStatus[player] = nil, nil end)
return {GetStatus = status, Claim = claim}
