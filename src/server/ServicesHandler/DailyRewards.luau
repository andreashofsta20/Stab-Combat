local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryHandler = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("InventoryHandler"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:FindFirstChild("DailyRewards")

local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")

local REWARD_CYCLE = 14

local Rewards = {
	[1] = { Item = { Type = "Knife", Name = "Bowie" }, XP = 50 },
	[2] = { Cash = 600, XP = 25 },
	[3] = { Cash = 700, XP = 50 },
	[4] = { Item = { Type = "Knife", Name = "Shadow Dagger" }, XP = 50 },
	[5] = { Cash = 800, XP = 75 },
	[6] = { Item = { Type = "Knife", Name = "Gut Knife" }, XP = 75 },
	[7] = { Item = { Type = "Emote", Name = "Griddy" }, XP = 100 },
	[8] = { Cash = 1000, XP = 100 },
	[9] = { Item = { Type = "Knife", Name = "Karambit" }, XP = 125 },
	[10] = { Cash = 1200, XP = 150 },
	[11] = { Item = { Type = "Knife", Name = "Skeleton" }, XP = 150 },
	[12] = { Cash = 1300, XP = 175 },
	[13] = { Item = { Type = "Emote", Name = "emote2" }, XP = 200 },
	[14] = { Item = { Type = "Knife", Name = "Butterfly" }, XP = 250 },
}

local function currentDayIndex()
	return math.floor(os.time() / 86400)
end

local function getStreakData(player)
	local lastClaimDay = player:GetAttribute("DailyLastClaimDay") or 0
	local streak = player:GetAttribute("DailyStreak") or 0
	return lastClaimDay, streak
end

local function setStreakData(player, lastClaimDay, streak, dayIndex)
	player:SetAttribute("DailyLastClaimDay", lastClaimDay)
	player:SetAttribute("DailyStreak", streak)
	player:SetAttribute("DailyDayIndex", dayIndex)
end

local function computeDayIndex(streak, claimedToday)
	if claimedToday then
		return ((math.max(streak, 1) - 1) % REWARD_CYCLE) + 1
	end
	return (streak % REWARD_CYCLE) + 1
end

local function secondsUntilNextClaim()
	local secondsLeft = 86400 - (os.time() % 86400)
	return math.max(0, secondsLeft)
end

local function getStatus(player)
	local today = currentDayIndex()
	local lastClaimDay, streak = getStreakData(player)

	local claimedToday = lastClaimDay == today
	local missedDays = today - lastClaimDay
	if lastClaimDay == 0 then
		missedDays = 0
	end

	if missedDays > 1 then
		streak = 0
	end

	local dayIndex = computeDayIndex(streak, claimedToday)
	setStreakData(player, lastClaimDay, streak, dayIndex)
	local remainingSeconds = secondsUntilNextClaim()

	return {
		CanClaim = not claimedToday,
		DayIndex = dayIndex,
		Streak = streak,
		LastClaimDay = lastClaimDay,
		Reward = Rewards[dayIndex],
		Rewards = Rewards,
		CurrentDayIndex = dayIndex,
		ClaimedToday = claimedToday,
		RemainingSeconds = remainingSeconds,
	}
end

local function applyReward(player, reward)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	if reward.Cash then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash and cash:IsA("IntValue") then
			cash.Value += reward.Cash
		end
	end

	if reward.XP then
		local xp = leaderstats:FindFirstChild("XP")
		if xp and xp:IsA("IntValue") then
			xp.Value += reward.XP
		end
	end

	if reward.Item and reward.Item.Type == "Knife" then
		InventoryHandler.AddKnife(player, reward.Item.Name)
	elseif reward.Item and reward.Item.Type == "Emote" then
		InventoryHandler.AddEmote(player, reward.Item.Name)
	end
end

local function claim(player, requestedDayIndex)
	local today = currentDayIndex()
	local lastClaimDay, streak = getStreakData(player)

	if lastClaimDay == today then
		return false, "Already claimed"
	end

	if lastClaimDay == today - 1 then
		streak += 1
	else
		streak = 1
	end

	local dayIndex = ((streak - 1) % REWARD_CYCLE) + 1
	if requestedDayIndex and requestedDayIndex ~= dayIndex then
		return false, "Not available"
	end
	local reward = Rewards[dayIndex]
	if not reward then
		return false, "No reward configured"
	end

	applyReward(player, reward)
	setStreakData(player, today, streak, dayIndex)

	return true, "Claimed", {
		DayIndex = dayIndex,
		Streak = streak,
		Reward = reward,
	}
end

ClaimDailyRewardRemote.OnServerEvent:Connect(function(player, action, requestedDayIndex)

	if action == "GetStatus" then
		DailyRewardClientRemote:FireClient(player, getStatus(player))
		return
	end

	if action == "Claim" then
		local ok, msg = claim(player, requestedDayIndex)
		if ok then
			NotificationHandler.SendNotification(player, "Daily reward claimed!", 4, "Success")
		else
			NotificationHandler.SendNotification(player, msg, 3, "Error")
		end
		DailyRewardClientRemote:FireClient(player, getStatus(player))
		return
	end
end)


return {}
