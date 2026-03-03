-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Player = game.Players.LocalPlayer


-- Remotes
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local QuestsRemotesFolder = RemotesFolder:WaitForChild("Quests")
local RequestQuestsRemote = QuestsRemotesFolder:WaitForChild("RequestQuests")
local ClaimQuestRewardRemote = QuestsRemotesFolder:WaitForChild("ClaimQuestReward")

-- GUI
local PlayerGui = Player:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGui:WaitForChild("Frames")
local QuestsFrame = FramesFolder:WaitForChild("Quests")
local CloseButton = QuestsFrame:WaitForChild("Close")


local IntermissionMap = game.Workspace:WaitForChild("IntermissionMap")
local TouchToMakeDailyRewardsVisible = game.Workspace:WaitForChild("IntermissionMap"):WaitForChild("2_Selection"):WaitForChild("Touch")

local touchMonitorConnection = nil
local countdownConnection = nil
local stopCountdown

local QuestsTemplateFolder = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("QuestTemplates")
local QuestTemplate = QuestsTemplateFolder:WaitForChild("QuestTemplate")

local TimeLeftText = QuestsFrame:WaitForChild("Top"):WaitForChild("Text")

local function getSecondsUntilUtcReset(nowTimestamp: number?): number
	local now = nowTimestamp or os.time()
	local utc = os.date("!*t", now)
	local nextReset = os.time({
		year = utc.year,
		month = utc.month,
		day = utc.day + 1,
		hour = 0,
		min = 0,
		sec = 0,
	})
	return math.max(0, nextReset - now)
end

local function formatTimeLeft(secondsLeft: number): string
	local hours = math.floor(secondsLeft / 3600)
	local minutes = math.floor((secondsLeft % 3600) / 60)
	return string.format("Daily Quests (%dH %dM)", hours, minutes)
end

local function setTimeLeftText(secondsLeft: number)
	TimeLeftText.Text = formatTimeLeft(math.max(0, math.floor(secondsLeft)))
end

local function startCountdown(startSeconds: number)
	stopCountdown()
	local remaining = math.max(0, math.floor(startSeconds))
	setTimeLeftText(remaining)

	countdownConnection = RunService.Heartbeat:Connect(function(dt)
		remaining = math.max(0, remaining - dt)
		setTimeLeftText(remaining)
	end)
end



local function MakeDesign(var : string)
	if var == "Blue" then
		for i , v in pairs(IntermissionMap:WaitForChild("2_Selection"):GetDescendants()) do
			if v:IsA("Decal") then
				v.Color3 = Color3.fromRGB(0, 152, 255)
			end
		end
	elseif var == "White" then
		for i , v in pairs(IntermissionMap:WaitForChild("2_Selection"):GetDescendants()) do
			if v:IsA("Decal") then
				v.Color3 = Color3.fromRGB(205, 205, 205)
			end
		end
	end
end

local function isLocalPlayerTouching()
	local character = Player.Character
	if not character then
		return false
	end
	for _, part in ipairs(TouchToMakeDailyRewardsVisible:GetTouchingParts()) do
		if part:IsDescendantOf(character) then
			return true
		end
	end
	return false
end

local function stopTouchMonitor()
	if touchMonitorConnection then
		touchMonitorConnection:Disconnect()
		touchMonitorConnection = nil
	end
end

stopCountdown = function()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

local function HideQuestsFrame()
	MakeDesign("White")
	QuestsFrame.Visible = false
	stopTouchMonitor()
	stopCountdown()
end

local function startTouchMonitor()
	if touchMonitorConnection then
		return
	end
	local elapsed = 0
	touchMonitorConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then
			return
		end
		elapsed = 0
		if not isLocalPlayerTouching() then
			HideQuestsFrame()
		end
	end)
end



TouchToMakeDailyRewardsVisible.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if player and player == Player then
		isInTouchZone = true
		MakeDesign("Blue")
		QuestsFrame.Visible = true
        RequestQuestsRemote:FireServer()
		startTouchMonitor()
	end
end)

TouchToMakeDailyRewardsVisible.TouchEnded:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if player and player == Player then
		isInTouchZone = false
		HideQuestsFrame()
	end
end)


local function QuestTemplateClone(data)
    local template = QuestTemplate:Clone()
    template.Name = "Quest_" .. tostring(data.Id)
    template.QuestInfo.Text = data.Title
    template.RewardFrame.RewardText.Text = "+" .. tostring(data.RewardGold) .. " GOLD"
    template.ClaimFrame.Status.Text = data.Status -- for example "1 / 2 WINS" or "3 / 20 MIN" or "CLAIM" OR "CLAIMED"
    local ClaimButton = template.ClaimFrame.ClaimButton

	if data.Claimed == true then
		ClaimButton.Visible = false
	elseif data.Completed == true then
		ClaimButton.Visible = true
		ClaimButton.MouseButton1Up:Connect(function()
			ClaimQuestRewardRemote:FireServer(data.Id)
		end)
	else
		ClaimButton.Visible = false
	end

    return template
    
end

local function ClearQuestsContainer()
    for _, v in pairs(QuestsFrame:WaitForChild("QuestsHolder"):WaitForChild("Scroll"):GetChildren()) do
        if v:IsA("Frame") then
            v:Destroy()
        end
    end
    
end

RequestQuestsRemote.OnClientEvent:Connect(function(questsData)
    local QuestsContainer = QuestsFrame:WaitForChild("QuestsHolder"):WaitForChild("Scroll")
    ClearQuestsContainer()
	if not questsData or type(questsData) ~= "table" then
		return
	end

	local serverTime = tonumber(questsData.ServerTime)
	startCountdown(getSecondsUntilUtcReset(serverTime))

	if type(questsData.Quests) ~= "table" then
		return
	end

	for _, questData in ipairs(questsData.Quests) do
		local template = QuestTemplateClone(questData)
		template.Parent = QuestsContainer
	end


end)









CloseButton.MouseButton1Click:Connect(function()
	HideQuestsFrame()
end)

task.defer(function()
	RequestQuestsRemote:FireServer()
end)



return {}