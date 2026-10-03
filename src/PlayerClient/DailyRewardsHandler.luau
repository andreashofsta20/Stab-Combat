local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Stand = require(script.Parent.Modules.RewardStand)
local Rarity = require(RS.Modules.RarityColor)
local Knives = require(RS.Modules.KnivesInfo)
local Emotes = require(RS.Modules.Emotes)
local remotes = RS:WaitForChild("Remotes"):WaitForChild("DailyRewards")
local request, response = remotes:WaitForChild("ClaimDailyReward"), remotes:WaitForChild("DailyRewardClient")
local frame = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("Frames"):WaitForChild("DailyRewards")
local holder = frame:WaitForChild("DailyRewardsHolder")
local container = holder:FindFirstChild("RewardsContainer") or holder:FindFirstChild("Scroll") or holder:FindFirstChildWhichIsA("ScrollingFrame")
if not container then warn("Daily rewards container is missing"); return {} end
local templates = RS:WaitForChild("UITemplates"):WaitForChild("DailyRewardTemplates")
local rows, tracks, current = {}, {}, nil
local deadline, nextRequest, claimAt, boundaryRequested = 0, 0, 0, false
local function text(label, value) if label then label.Text = tostring(value or "") end end
local function applyRarity(item, rarity)
	if not item or not rarity then return end
	for _, name in ipairs({"RarityLabel", "ItemRarity", "EmoteRarity", "KnifeRarity"}) do text(item:FindFirstChild(name), rarity) end
	local image = item:FindFirstChild("Rarity", true) or item:FindFirstChild("RarityImage", true)
	if image and Rarity[rarity] and Rarity[rarity].Image then image.Image = Rarity[rarity].Image end
end
local function refresh()
	if os.clock() < nextRequest then return end
	nextRequest = os.clock() + 1
	request:FireServer("GetStatus")
end
local function remainingText(seconds)
	if seconds <= 0 then return "READY" end
	if seconds >= 3600 then return string.format("%dH %dM", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
	if seconds >= 60 then return tostring(math.floor(seconds / 60)) .. " MIN" end
	return tostring(seconds) .. " SEC"
end
local function render()
	if not current or current.Loading then refresh(); return end
	local remaining = math.max(0, math.ceil(deadline - os.clock()))
	for day, row in pairs(rows) do
		local claimFrame = row:FindFirstChild("ClaimFrame")
		local button = claimFrame and claimFrame:FindFirstChild("ClaimButton")
		local label = claimFrame and claimFrame:FindFirstChild("StatusLabel")
		local ready = day == current.CurrentDayIndex and current.CanClaim
		local status = day == current.CurrentDayIndex and (current.CanClaim and "CLICK TO CLAIM" or remainingText(remaining))
			or (day <= current.CycleClaimedCount and "CLAIMED" or "LOCKED")
		if label and label.Text ~= status then label.Text = status end
		if button then button.Active, button.AutoButtonColor = ready, ready end
	end
	if remaining == 0 and not current.CanClaim and not boundaryRequested then
		boundaryRequested = true
		refresh()
	end
end
local function create(day, reward)
	local name = reward.Item and (reward.Item.Type == "Knife" and "DailyRewardKnifeTemplate" or "DailyRewardEmoteTemplate")
		or (reward.Cash and "DailyRewardCashTemplate" or "DailyRewardXPTemplate")
	local template = templates:FindFirstChild(name) or (name == "DailyRewardCashTemplate" and templates:FindFirstChild("dailyRewardCashTemplate"))
	if not template then warn("Missing daily reward template:", name); return nil end
	local row = template:Clone()
	row.Name, row.LayoutOrder = "DailyReward_" .. day, day
	if reward.Item then
		local info = reward.Item.Type == "Knife" and Knives[reward.Item.Name] or Emotes[reward.Item.Name]
		local item = row:FindFirstChild(reward.Item.Type == "Knife" and "KnifeInventoryTemplate" or "EmoteInventoryTemplate")
		if item then
			text(item:FindFirstChild(reward.Item.Type == "Knife" and "KnifeName" or "EmoteName"), reward.Item.Name)
			applyRarity(item, info and info.Rarity)
			local image = item:FindFirstChild("KnifeImage")
			if image and info then image.Image = info.Image end
		end
		local viewport = row:FindFirstChild("EmoteViewport", true)
		local world = viewport and viewport:FindFirstChild("World")
		local rig = world and world:FindFirstChild("Rig")
		local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
		if humanoid and info and info.EmoteId then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
			local animation = Instance.new("Animation")
			animation.AnimationId = info.EmoteId
			local ok, track = pcall(animator.LoadAnimation, animator, animation)
			animation:Destroy()
			if ok then track.Looped = true; table.insert(tracks, track); if frame.Visible then track:Play() end end
		end
	elseif reward.Cash then
		text(row:FindFirstChild("CashAmount", true), "+" .. reward.Cash .. " Cash")
	end
	if reward.XP then text(row:FindFirstChild("XPAmount", true), "+" .. reward.XP .. " XP") end
	local claimFrame = row:FindFirstChild("ClaimFrame")
	if claimFrame then
		text(claimFrame:FindFirstChild("DayText"), "Day " .. day)
		local button = claimFrame:FindFirstChild("ClaimButton")
		if button then button.Activated:Connect(function()
			if not current or current.Loading or not current.CanClaim or current.CurrentDayIndex ~= day or os.clock() < claimAt then return end
			claimAt = os.clock() + 0.5
			request:FireServer("Claim", day)
		end) end
	end
	row.Parent = container
	return row
end
response.OnClientEvent:Connect(function(status)
	if type(status) ~= "table" then return end
	current, boundaryRequested = status, false
	if status.Loading then if frame.Visible then render() end; return end
	if type(status.Rewards) ~= "table" then return end
	deadline = os.clock() + math.max(0, status.NextClaimAt - status.ServerTime)
	for day, reward in ipairs(status.Rewards) do
		if not rows[day] then rows[day] = create(day, reward) end
	end
	render()
end)
local hide = Stand.BindLobby("1_Selection", frame, function()
	for _, track in ipairs(tracks) do if not track.IsPlaying then track:Play() end end
	refresh(); render()
end, function() for _, track in ipairs(tracks) do track:Stop() end end, render)
frame:WaitForChild("Close").Activated:Connect(hide)
player:GetAttributeChangedSignal("DataReady"):Connect(function() if player:GetAttribute("DataReady") then refresh() end end)
task.defer(refresh)
return {}
