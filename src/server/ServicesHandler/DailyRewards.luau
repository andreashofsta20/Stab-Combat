local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryHandler = require(script.Parent.Parent.DataStore.InventoryHandler)
local NotificationHandler = require(script.Parent.Parent.Game.SendNotification)
local ProfileManager = require(script.Parent.Parent.DataStore:WaitForChild("ProfileManager"))
local QuestsHandler = require(script.Parent:WaitForChild("QuestsHandler"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:WaitForChild("DailyRewards")

local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")

local REWARD_CYCLE = 14
local DAY_LENGTH = 86400 -- 1 day

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

local function getNow()
	return os.time(os.date("!*t"))
end

local function secondsUntilNextClaim(lastClaimTime)
	local now = getNow()
	local last = lastClaimTime or 0
	local nextClaim = last + DAY_LENGTH
	return math.max(0, nextClaim - now)
end

local function getStatus(player)
   local now = getNow()
   local leaderstats = player:FindFirstChild("leaderstats")
   local drFolder = leaderstats and leaderstats:FindFirstChild("DailyRewards")
   local lastClaimTime = 0
   local streak = 0
   if drFolder then
	   local lct = drFolder:FindFirstChild("LastClaimTime")
	   local stv = drFolder:FindFirstChild("Streak")
	   lastClaimTime = lct and lct.Value or print("Error: No LastClaimTime for player " .. player.Name)
	   streak = stv and stv.Value or print("Error: No Streak for player " .. player.Name)
   end

   local claimedToday = false
   if lastClaimTime > 0 and now - lastClaimTime < DAY_LENGTH then
	   claimedToday = true
   end

   -- Streak never resets automatically
   local streakReset = false

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

   -- Only allow claiming day 1 if streak was reset
   local canClaim = false
   if not claimedToday then
	   if streakReset then
		   canClaim = (nextClaimIndex == 1)
	   else
		   canClaim = true
	   end
   end

   return {
	   Rewards = Rewards,
	   CurrentDayIndex = nextClaimIndex,
	   LastClaimedIndex = lastClaimedIndex,
	   ClaimedToday = claimedToday,
	   CanClaim = canClaim,
	   RemainingSeconds = secondsUntilNextClaim(lastClaimTime),
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

   local now = getNow()
   local leaderstats = player:FindFirstChild("leaderstats")
   local drFolder = leaderstats and leaderstats:FindFirstChild("DailyRewards")
   local lct = drFolder and drFolder:FindFirstChild("LastClaimTime")
   local stv = drFolder and drFolder:FindFirstChild("Streak")
   local lastClaimTime = lct and lct.Value or 0
   local streak = stv and stv.Value or 0

   -- Streak never resets automatically
   local streakReset = false

   -- Already claimed today
   if lastClaimTime > 0 and now - lastClaimTime < DAY_LENGTH then
	   return false, "Already claimed"
   end

   local correctIndex = 1
   if streakReset then
	   correctIndex = 1
   else
	   if lastClaimTime == 0 then
		   correctIndex = 1
	   elseif now - lastClaimTime >= DAY_LENGTH then
		   correctIndex = ((streak) % REWARD_CYCLE) + 1
	   else
		   return false, "Not available"
	   end
   end


   if requestedDayIndex == 1 and not streakReset and lastClaimTime ~= 0 then
	   return false, "Not available"
   end


   if streakReset then
	   streak = 1
   else
	   streak = streak + 1
   end

   if requestedDayIndex ~= correctIndex then
	   return false, "Not available"
   end

   local reward = Rewards[correctIndex]
   if not reward then
	   return false, "Invalid reward"
   end

   applyReward(player, reward)

   if lct then lct.Value = now end
   if stv then stv.Value = streak end

   task.spawn(function()
	   ProfileManager.SaveProfile(player)
   end)

   return true
end

local dailyRemoteCooldowns: {[number]: number} = {}
local DAILY_REMOTE_COOLDOWN = 1.5

ClaimDailyRewardRemote.OnServerEvent:Connect(function(player, action, dayIndex)
	local now = os.clock()
	if dailyRemoteCooldowns[player.UserId] and (now - dailyRemoteCooldowns[player.UserId]) < DAILY_REMOTE_COOLDOWN then return end
	dailyRemoteCooldowns[player.UserId] = now

	if action == "GetStatus" then
		DailyRewardClientRemote:FireClient(player, getStatus(player))
		return
	end

	if action == "Claim" then
		local ok, msg = claim(player, dayIndex)

		if ok then
			QuestsHandler.AddProgress(player, "DAILY_REWARD_CLAIMS", 1)
			NotificationHandler.SendNotification(player, "Daily reward claimed!", 4, "Success")
		else
			NotificationHandler.SendNotification(player, msg, 3, "Error")
		end

		DailyRewardClientRemote:FireClient(player, getStatus(player))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastClaimTimes[player] = nil
	dailyRemoteCooldowns[player.UserId] = nil
end)

return {
	GetStatus = getStatus,
	Claim = claim,
}
