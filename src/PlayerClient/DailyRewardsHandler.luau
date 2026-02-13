-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Player = game.Players.LocalPlayer

-- Modules
local RarityColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local KnivesInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))
local EmotesInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Emotes"))

-- Remotes
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")
local DailyRewardsRemotesFolder = RemotesFolder:WaitForChild("DailyRewards")
local ClaimDailyRewardRemote = DailyRewardsRemotesFolder:WaitForChild("ClaimDailyReward")
local DailyRewardClientRemote = DailyRewardsRemotesFolder:WaitForChild("DailyRewardClient")

-- GUI
local PlayerGui = Player:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGui:WaitForChild("Frames")
local DailyRewardsFrame = FramesFolder:WaitForChild("DailyRewards")
local CloseButton = DailyRewardsFrame:WaitForChild("Close")
local DailyRewardsHolder = DailyRewardsFrame:WaitForChild("DailyRewardsHolder")
local RewardsContainer = DailyRewardsHolder:WaitForChild("RewardsContainer", 2)
	or DailyRewardsHolder:WaitForChild("Scroll", 2)
	or DailyRewardsHolder:FindFirstChildWhichIsA("ScrollingFrame")

-- Templates
local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local DailyRewardTemplate = UITemplates:WaitForChild("DailyRewardTemplates")
local DailyRewardKnifeTemplate = DailyRewardTemplate:WaitForChild("DailyRewardKnifeTemplate")
local DailyRewardEmoteTemplate = DailyRewardTemplate:WaitForChild("DailyRewardEmoteTemplate")
local DailyRewardCashTemplate = DailyRewardTemplate:FindFirstChild("DailyRewardCashTemplate")
	or DailyRewardTemplate:FindFirstChild("dailyRewardCashTemplate")
local DailyRewardXPTemplate = DailyRewardTemplate:WaitForChild("DailyRewardXPTemplate")


local IntermissionMap = game.Workspace:WaitForChild("IntermissionMap")
local TouchToMakeDailyRewardsVisible = game.Workspace:WaitForChild("IntermissionMap"):WaitForChild("1_Selection"):WaitForChild("Touch")

local touchMonitorConnection = nil
local isInTouchZone = false


local function MakeDesign(var : string)
	if var == "Blue" then
		for i , v in pairs(IntermissionMap:WaitForChild("1_Selection"):GetDescendants()) do
			if v:IsA("Decal") then
				v.Color3 = Color3.fromRGB(0, 152, 255)
			end
		end
		elseif var == "White" then
		for i , v in pairs(IntermissionMap:WaitForChild("1_Selection"):GetDescendants()) do
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

local function hideDailyRewards()
	MakeDesign("White")
	DailyRewardsFrame.Visible = false
	stopTouchMonitor()
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
			hideDailyRewards()
		end
	end)
end



TouchToMakeDailyRewardsVisible.Touched:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if player and player == Player then
		isInTouchZone = true
		MakeDesign("Blue")
		ClaimDailyRewardRemote:FireServer("GetStatus")
		DailyRewardsFrame.Visible = true
		startTouchMonitor()
	end
end)

TouchToMakeDailyRewardsVisible.TouchEnded:Connect(function(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if player and player == Player then
		isInTouchZone = false
		hideDailyRewards()
	end
end)



local function setText(label, value)
	if label then
		if value == nil then
			label.Text = ""
		else
			label.Text = tostring(value)
		end
	end
end

local function applyRarity(container, rarityName)
	if not container or not rarityName then
		return
	end
	setText(container:FindFirstChild("RarityLabel"), rarityName)
	setText(container:FindFirstChild("ItemRarity"), rarityName)
	setText(container:FindFirstChild("EmoteRarity"), rarityName)
	setText(container:FindFirstChild("KnifeRarity"), rarityName)

	local rarityImage = container:FindFirstChild("Rarity", true) or container:FindFirstChild("RarityImage", true)
	if rarityImage then
		local rarityConfig = RarityColor[rarityName]
		if rarityConfig and rarityConfig.Image then
			rarityImage.Image = rarityConfig.Image
		end
	end
end

local function getRemainingSeconds(status)
	if status and status.RemainingSeconds and status.RemainingSeconds > 0 then
		return status.RemainingSeconds
	end
	local secondsLeft = 86400 - (os.time() % 86400)
	return math.max(0, secondsLeft)
end

local function getRemainingText(remainingSeconds)
	if not remainingSeconds or remainingSeconds <= 0 then
		return ""
	end
	local days = math.floor(remainingSeconds / 86400)
	local hours = math.floor((remainingSeconds % 86400) / 3600)
	local minutes = math.floor((remainingSeconds % 3600) / 60)
	if days > 0 then
		if days == 1 then
			return "1 DAY"
		end
		return tostring(days) .. " DAYS"
	end
	if hours <= 0 then
		return tostring(math.max(1, minutes)) .. " MIN"
	end
	return tostring(hours) .. "H " .. tostring(minutes) .. "M"
end

local function getClaimFrameStatusLabel(frame)
	local claimFrame = frame:FindFirstChild("ClaimFrame")
	if not claimFrame then
		return nil
	end
	return claimFrame:FindFirstChild("StatusLabel")
end

DailyRewardClientRemote.OnClientEvent:Connect(function(status)
	if not status or not status.Rewards then
		return
	end

	if not RewardsContainer then
		warn("DailyRewardsHandler: RewardsContainer not found")
		return
	end

	for _, child in pairs(RewardsContainer:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for dayIndex, rewardInfo in ipairs(status.Rewards) do
		local rewardFrame

		if rewardInfo.Item then
			if rewardInfo.Item.Type == "Knife" then
				rewardFrame = DailyRewardKnifeTemplate:Clone()
				rewardFrame.LayoutOrder = dayIndex

				local ClaimFrame = rewardFrame.ClaimFrame
				if ClaimFrame then
					local ClaimButton = ClaimFrame:FindFirstChild("ClaimButton")
					if ClaimButton then
						ClaimButton.MouseButton1Click:Connect(function()
							ClaimDailyRewardRemote:FireServer("Claim", dayIndex)
						end)
					end
					local dayText = ClaimFrame:FindFirstChild("DayText")
					if dayText then
						dayText.Text = "Day " .. tostring(dayIndex)
					end
				end

				local KnifeInfo = rewardFrame:FindFirstChild("KnifeInventoryTemplate")
				if KnifeInfo then
					local KnifeName = KnifeInfo:FindFirstChild("KnifeName")
					local KnifeImage = KnifeInfo:FindFirstChild("KnifeImage")
					local knifeData = KnivesInfo[rewardInfo.Item.Name]
					local rarityName = rewardInfo.Item.Rarity or (knifeData and knifeData.Rarity)

					setText(KnifeName, rewardInfo.Item.Name)
					applyRarity(KnifeInfo, rarityName)
					if KnifeImage and knifeData and knifeData.Image then
						KnifeImage.Image = knifeData.Image
					end
				end
				setText(rewardFrame.KnifeInventoryTemplate:FindFirstChild("KnifeName"), rewardInfo.Item.Name)
			elseif rewardInfo.Item.Type == "Emote" then
				rewardFrame = DailyRewardEmoteTemplate:Clone()
				local emoteData = EmotesInfo[rewardInfo.Item.Name]
				local rarityName = rewardInfo.Item.Rarity or (emoteData and emoteData.Rarity)
				local emoteInfo = rewardFrame:FindFirstChild("EmoteInventoryTemplate")
				if emoteInfo then
					setText(emoteInfo:FindFirstChild("EmoteName"), rewardInfo.Item.Name)
					setText(emoteInfo:FindFirstChild("EmoteRarity"), rarityName)
					applyRarity(emoteInfo, rarityName)
				else
					applyRarity(rewardFrame, rarityName)
				end

				local viewport = rewardFrame:FindFirstChild("EmoteViewport", true)
				if viewport and emoteData and emoteData.EmoteId then
					local world = viewport:FindFirstChild("World")
					local rig = world and world:FindFirstChild("Rig")
					local humanoid = rig and rig:FindFirstChild("Humanoid")
					if humanoid then
						local animationRig = Instance.new("Animation")
						animationRig.AnimationId = emoteData.EmoteId
						local track = humanoid:LoadAnimation(animationRig)
						track.Looped = true
						track:Play()
					end
				end
			end
		elseif rewardInfo.Cash then
			if DailyRewardCashTemplate then
				rewardFrame = DailyRewardCashTemplate:Clone()
				setText(rewardFrame:WaitForChild("DailyRewardCash"):FindFirstChild("CashAmount"), "+" .. rewardInfo.Cash .. " GOLD")
			end
		elseif rewardInfo.XP then
			rewardFrame = DailyRewardXPTemplate:Clone()
			setText(rewardFrame:waitForChild("DailyRewardXP"):FindFirstChild("XPAmount"), "+" .. rewardInfo.XP .. " XP")
		end

		if rewardFrame then
			rewardFrame.LayoutOrder = dayIndex
			setText(rewardFrame:FindFirstChild("ClaimFrame"):FindFirstChild("DayText"), "Day " .. tostring(dayIndex))
			if dayIndex < status.CurrentDayIndex then
				setText(getClaimFrameStatusLabel(rewardFrame), "CLAIMED")
			elseif dayIndex == status.CurrentDayIndex then
				if status.ClaimedToday then
					setText(getClaimFrameStatusLabel(rewardFrame), "CLAIMED")
				else
					setText(getClaimFrameStatusLabel(rewardFrame), "CLICK TO CLAIM")
				end
			else
				if status.ClaimedToday and dayIndex == status.CurrentDayIndex + 1 then
					local baseSeconds = getRemainingSeconds(status)
					setText(getClaimFrameStatusLabel(rewardFrame), getRemainingText(baseSeconds))
				else
					setText(getClaimFrameStatusLabel(rewardFrame), "LOCKED")
				end
			end
			rewardFrame.Parent = RewardsContainer
		end
	end
end)


CloseButton.mouseButton1Click:Connect(function()
	hideDailyRewards()
end)



return {}