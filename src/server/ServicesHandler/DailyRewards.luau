local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryHandler = require(script.Parent.Parent.DataStore.InventoryHandler)
local NotificationHandler = require(script.Parent.Parent.Game.SendNotification)
local OnJoined = require(script.Parent.Parent.DataStore.OnJoined)

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:WaitForChild("DailyRewards")

local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")

local REWARD_CYCLE = 14
local DAY_LENGTH = 86400

-- Server anti-spam
local CLAIM_COOLDOWN = 1
local lastClaimTimes = {}

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
	[13] = { Item = { Type = "Emote", Name = "Godly Dance" }, XP = 200 },
	[14] = { Item = { Type = "Knife", Name = "Butterfly" }, XP = 250 },
}

local function currentDay()
	return math.floor(os.time(os.date("!*t")) / DAY_LENGTH)
end

local function secondsUntilNextClaim()
	local now = os.time(os.date("!*t"))
	local nextDayStart = (math.floor(now / DAY_LENGTH) + 1) * DAY_LENGTH
	return math.max(0, nextDayStart - now)
end

local function getStatus(player)
	local today = currentDay()
	local lastClaimDay = player:GetAttribute("DailyLastClaimDay") or 0
	local streak = player:GetAttribute("DailyStreak") or 0

	local claimedToday = (lastClaimDay == today)

	local lastClaimedIndex = 0
	local nextClaimIndex = 1

	if streak > 0 then
		lastClaimedIndex = ((streak - 1) % REWARD_CYCLE) + 1
		if not claimedToday then
			nextClaimIndex = ((streak) % REWARD_CYCLE) + 1
		else
			nextClaimIndex = lastClaimedIndex + 1
			if nextClaimIndex > REWARD_CYCLE then
				nextClaimIndex = 1
			end
		end
	end

	return {
		Rewards = Rewards,
		CurrentDayIndex = nextClaimIndex,
		LastClaimedIndex = lastClaimedIndex,
		ClaimedToday = claimedToday,
		RemainingSeconds = secondsUntilNextClaim(),
		Streak = streak,
	}
end



local function applyReward(player, reward)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	if reward.Cash then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash then
			cash.Value += reward.Cash
		end
	end

	if reward.XP then
		local xp = leaderstats:FindFirstChild("XP")
		if xp then
			xp.Value += reward.XP
		end
	end

	if reward.Item then
		if reward.Item.Type == "Knife" then
			InventoryHandler.AddKnife(player, reward.Item.Name)
		elseif reward.Item.Type == "Emote" then
			InventoryHandler.AddEmote(player, reward.Item.Name)
		end
	end
end

local function claim(player, requestedDayIndex)

	if typeof(requestedDayIndex) ~= "number" then
		return false, "Invalid request"
	end

	-- server anti-spam
	local nowTick = tick()
	if lastClaimTimes[player] and nowTick - lastClaimTimes[player] < CLAIM_COOLDOWN then
		return false, "Slow down"
	end
	lastClaimTimes[player] = nowTick

	local today = currentDay()
	local lastClaimDay = player:GetAttribute("DailyLastClaimDay") or 0
	local streak = player:GetAttribute("DailyStreak") or 0

	if lastClaimDay == today then
		return false, "Already claimed"
	end

	if lastClaimDay ~= 0 and today - lastClaimDay > 1 then
		streak = 0
	end

	if lastClaimDay == today - 1 then
		streak += 1
	else
		streak = 1
	end

	local correctIndex = ((streak - 1) % REWARD_CYCLE) + 1

	if requestedDayIndex ~= correctIndex then
		return false, "Not available"
	end

	local reward = Rewards[correctIndex]
	if not reward then
		return false, "Invalid reward"
	end

	applyReward(player, reward)

	player:SetAttribute("DailyLastClaimDay", today)
	player:SetAttribute("DailyStreak", streak)

	task.spawn(function()
		OnJoined.SavePlayerData(player)
	end)

	return true
end

ClaimDailyRewardRemote.OnServerEvent:Connect(function(player, action, dayIndex)

	if action == "GetStatus" then
		DailyRewardClientRemote:FireClient(player, getStatus(player))
		return
	end

	if action == "Claim" then
		local ok, msg = claim(player, dayIndex)

		if ok then
			NotificationHandler.SendNotification(player, "Daily reward claimed!", 4, "Success")
		else
			NotificationHandler.SendNotification(player, msg, 3, "Error")
		end

		DailyRewardClientRemote:FireClient(player, getStatus(player))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastClaimTimes[player] = nil
end)

return {
	GetStatus = getStatus,
	Claim = claim,
}
