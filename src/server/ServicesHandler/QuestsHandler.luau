local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local Notifications = require(script.Parent.Parent.Game.SendNotification)
local Config = require(RS.Modules.QuestsConfig)
local Math = require(RS.Modules.RewardMath)
-- Read-only migration source. All new quest writes go to the active profile.
local legacyStore = DataStoreService:GetDataStore("DailyQuestsProgress_v1.0")
local remotes = RS:WaitForChild("Remotes"):WaitForChild("Quests")
local update, claimRemote = remotes:WaitForChild("RequestQuests"), remotes:WaitForChild("ClaimQuestReward")
local Quests = {}
local states, loading, pendingProgress, queuedPush = {}, {}, {}, {}
local watchers, nextStatus, nextClaim, playtime = {}, {}, {}, {}
local cachedDay, cachedDefinitions

local function dayKey()
	return os.date("!%Y-%m-%d", os.time())
end
local function definitions(day)
	if day == cachedDay then return cachedDefinitions end
	local rng = Random.new((tonumber(day:gsub("-", "")) or 1) % 2147483647)
	local pool = table.clone(Config.Pool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local selected = {}
	for i = 1, math.min(Config.ActivePerDay, #pool) do selected[i] = pool[i] end
	cachedDay, cachedDefinitions = day, selected
	return selected
end
local function activeProfile(player)
	local profile = Profiles.GetProfile(player)
	return player.Parent == Players and player:GetAttribute("DataReady") == true and profile and profile:IsActive() and profile or nil
end
local function ensureToday(player)
	local state, profile = states[player], activeProfile(player)
	if not state or not profile or profile.Data.DailyQuests ~= state then return nil, {} end
	local day = dayKey()
	if state.DayKey ~= day then state.DayKey, state.Progress, state.Claimed = day, {}, {} end
	return state, definitions(day)
end
local function payload(player)
	local state, daily = ensureToday(player)
	local result = {DayKey = dayKey(), ServerTime = os.time(), ResetAt = Math.NextUtcReset(os.time()), Quests = {}}
	if not state then result.Loading = true; return result end
	for _, quest in ipairs(daily) do
		local progress = math.min(quest.Target, Math.NonnegativeInteger(state.Progress[quest.Id]))
		local claimed, completed = state.Claimed[quest.Id] == true, progress >= quest.Target
		local shown, target = progress, quest.Target
		if quest.Type == "PLAY_TIME_SECONDS" then shown, target = math.floor(shown / 60), math.floor(target / 60) end
		table.insert(result.Quests, {
			Id = quest.Id, Title = quest.Title, RewardGold = quest.RewardGold,
			Progress = progress, Target = quest.Target, Claimed = claimed, Completed = completed,
			Status = claimed and "CLAIMED" or (completed and "CLAIM" or string.format("%d / %d %s", shown, target, quest.ProgressLabel)),
		})
	end
	return result
end
local function push(player)
	if player.Parent == Players then update:FireClient(player, payload(player)) end
end
local function queuePush(player)
	if queuedPush[player] then return end
	local token = {}
	queuedPush[player] = token
	task.delay(Config.PushDelaySeconds, function()
		if queuedPush[player] ~= token then return end
		queuedPush[player] = nil
		push(player)
	end)
end
function Quests.AddProgress(player, questType, amount)
	if type(questType) ~= "string" or not Math.IsFinite(amount) or amount <= 0 or not activeProfile(player) then return end
	local state, daily = ensureToday(player)
	if not state then
		local pending = pendingProgress[player]
		if not pending or pending.DayKey ~= dayKey() then pending = {DayKey = dayKey(), Amounts = {}}; pendingProgress[player] = pending end
		pending.Amounts[questType] = math.min(1000000, (pending.Amounts[questType] or 0) + amount)
		return
	end
	local changed = false
	for _, quest in ipairs(daily) do
		if quest.Type == questType then
			local current = state.Progress[quest.Id]
			current = Math.IsFinite(current) and math.max(0, current) or 0
			local value = math.min(quest.Target, current + amount)
			if value ~= current then state.Progress[quest.Id], changed = value, true end
		end
	end
	if changed then queuePush(player) end
end
local function load(player)
	if loading[player] or states[player] then return end
	local profile = activeProfile(player)
	if not profile then return end
	loading[player] = true
	local existing = profile.Data.DailyQuests
	local ok, data = true, existing
	if type(existing) ~= "table" then ok = false
	elseif existing.MigrationComplete ~= true then
		ok, data = pcall(function() return legacyStore:GetAsync(tostring(player.UserId)) end)
	end
	loading[player] = nil
	if activeProfile(player) ~= profile then return end
	if not ok or (data ~= nil and (type(data) ~= "table"
		or (data.Progress ~= nil and type(data.Progress) ~= "table")
		or (data.Claimed ~= nil and type(data.Claimed) ~= "table"))) then
		warn("[Quests] Quest migration unavailable for", player.Name)
		push(player)
		task.delay(Config.LegacyRetrySeconds, function() if activeProfile(player) == profile then load(player) end end)
		return
	end
	local migrated = existing.MigrationComplete == true
	local state = migrated and existing or {
		Version = 1, MigrationComplete = true,
		DayKey = type(data) == "table" and data.DayKey or dayKey(),
		Progress = {}, Claimed = {},
	}
	if not migrated and type(data) == "table" then
		for id, value in pairs(data.Progress or {}) do
			if type(id) == "string" then state.Progress[id] = Math.NonnegativeInteger(value) end
		end
		for id, value in pairs(data.Claimed or {}) do
			if type(id) == "string" then state.Claimed[id] = value == true end
		end
	end
	state.Progress, state.Claimed = state.Progress or {}, state.Claimed or {}
	profile.Data.DailyQuests, states[player] = state, state
	ensureToday(player)
	local pending = pendingProgress[player]
	pendingProgress[player] = nil
	if pending and pending.DayKey == dayKey() then
		for kind, amount in pairs(pending.Amounts) do Quests.AddProgress(player, kind, amount) end
	end
	if not migrated then Profiles.SaveProfile(player) end
	push(player)
end
local function claim(player, id)
	if type(id) ~= "string" or #id > 64 then return false, "Invalid quest" end
	local state, daily = ensureToday(player)
	if not state then return false, "Your quests are still loading" end
	for _, quest in ipairs(daily) do
		if quest.Id == id then
			if state.Claimed[id] then return false, "Already claimed" end
			if Math.NonnegativeInteger(state.Progress[id]) < quest.Target then return false, "Quest not complete" end
			local stats = player:FindFirstChild("leaderstats")
			local cash = stats and stats:FindFirstChild("Cash")
			if not cash then return false, "Reward unavailable" end
			-- No yield between flag, balance mutation and capturing one profile save.
			state.Claimed[id] = true
			cash.Value += quest.RewardGold
			Profiles.SaveProfile(player)
			return true
		end
	end
	return false, "Quest unavailable"
end
update.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now < (nextStatus[player] or 0) then return end
	nextStatus[player] = now + Config.StatusCooldown
	push(player)
end)
claimRemote.OnServerEvent:Connect(function(player, id)
	if not activeProfile(player) or type(id) ~= "string" or #id > 64 then return end
	local now = os.clock()
	if now < (nextClaim[player] or 0) then return end
	nextClaim[player] = now + Config.ClaimCooldown
	local ok, message = claim(player, id)
	Notifications.SendNotification(player, ok and "Quest reward claimed!" or message, 3, ok and "Success" or "Error")
	push(player)
end)
local function observe(player)
	playtime[player] = os.clock()
	watchers[player] = player:GetAttributeChangedSignal("DataReady"):Connect(function()
		playtime[player] = os.clock()
		if activeProfile(player) then load(player) end
	end)
	if activeProfile(player) then load(player) end
end
Players.PlayerAdded:Connect(observe)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(observe, player) end
Players.PlayerRemoving:Connect(function(player)
	if watchers[player] then watchers[player]:Disconnect() end
	states[player], loading[player], pendingProgress[player], queuedPush[player] = nil, nil, nil, nil
	watchers[player], nextStatus[player], nextClaim[player], playtime[player] = nil, nil, nil, nil
	-- ProfileManager owns autosave and session shutdown; never write a second store.
end)
task.spawn(function()
	while true do
		task.wait(Config.PlaytimeTickSeconds)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local elapsed = math.max(0, now - (playtime[player] or now))
			playtime[player] = now
			local oldDay = states[player] and states[player].DayKey
			Quests.AddProgress(player, "PLAY_TIME_SECONDS", elapsed)
			if oldDay and oldDay ~= dayKey() then queuePush(player) end
		end
	end
end)
Quests.GetStatus, Quests.Claim = payload, claim
return Quests
