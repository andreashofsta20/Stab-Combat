local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Stand = require(script.Parent.Modules.RewardStand)
local remotes = RS:WaitForChild("Remotes"):WaitForChild("Quests")
local request, claim = remotes:WaitForChild("RequestQuests"), remotes:WaitForChild("ClaimQuestReward")
local frame = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("Frames"):WaitForChild("Quests")
local container = frame:WaitForChild("QuestsHolder"):WaitForChild("Scroll")
local title = frame:WaitForChild("Top"):WaitForChild("Text")
local template = RS:WaitForChild("UITemplates"):WaitForChild("QuestTemplates"):WaitForChild("QuestTemplate")
local rows, current, deadline, nextRequest, claimAt = {}, nil, nil, 0, 0
local function refresh()
	local now = os.clock()
	if now < nextRequest then return end
	nextRequest = now + 1
	request:FireServer()
end
local function tick()
	if not deadline then title.Text = "Daily Quests (loading...)"; refresh(); return end
	local seconds = math.max(0, math.ceil(deadline - os.clock()))
	local text = string.format("Daily Quests (%dH %dM)", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	if title.Text ~= text then title.Text = text end
	if seconds == 0 or (current and current.Loading) then refresh() end
end
request.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.Quests) ~= "table" then return end
	current = data
	deadline = os.clock() + math.max(0, (data.ResetAt or ((math.floor(data.ServerTime / 86400) + 1) * 86400)) - data.ServerTime)
	local seen = {}
	for order, quest in ipairs(data.Quests) do
		seen[quest.Id] = true
		local row = rows[quest.Id]
		if not row then
			row = {frame = template:Clone()}
			rows[quest.Id] = row
			row.frame.Name, row.frame.Parent = "Quest_" .. quest.Id, container
			row.frame.ClaimFrame.ClaimButton.Activated:Connect(function()
				local latest = row.data
				if not latest or latest.Claimed or not latest.Completed or os.clock() < claimAt then return end
				claimAt = os.clock() + 0.5
				claim:FireServer(latest.Id)
			end)
		end
		row.data, row.frame.LayoutOrder = quest, order
		row.frame.QuestInfo.Text = quest.Title
		row.frame.RewardFrame.RewardText.Text = "+" .. tostring(quest.RewardGold) .. " GOLD"
		row.frame.ClaimFrame.Status.Text = quest.Status
		row.frame.ClaimFrame.ClaimButton.Visible = quest.Completed and not quest.Claimed
	end
	for id, row in pairs(rows) do if not seen[id] then row.frame:Destroy(); rows[id] = nil end end
	if frame.Visible then tick() end
end)
local hide = Stand.BindLobby("2_Selection", frame, function() refresh(); tick() end, nil, tick)
frame:WaitForChild("Close").Activated:Connect(hide)
player:GetAttributeChangedSignal("DataReady"):Connect(function() if player:GetAttribute("DataReady") then refresh() end end)
task.defer(refresh)
return {}
