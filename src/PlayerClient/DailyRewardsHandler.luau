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
local countdownConnection = nil
local isInTouchZone = false
local lastClaimTime = 0
local CLAIM_COOLDOWN = 0.5


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

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

local function hideDailyRewards()
	MakeDesign("White")
	DailyRewardsFrame.Visible = false
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




local function getRemainingText(remainingSeconds)
	if not remainingSeconds or remainingSeconds <= 0 then
		return "READY"
	end
	local days = math.floor(remainingSeconds / 86400)
	local hours = math.floor((remainingSeconds % 86400) / 3600)
	local minutes = math.floor((remainingSeconds % 3600) / 60)
	local seconds = remainingSeconds % 60
	
	if days > 0 then
		if days == 1 then
			return "1 DAY"
		end
		return tostring(days) .. " DAYS"
	end
	if hours > 0 then
		return tostring(hours) .. "H " .. tostring(minutes) .. "M"
	end
	if minutes > 0 then
		return tostring(minutes) .. " MIN"
	end
	-- For testing with 10 second days, show seconds
	return tostring(seconds) .. " SEC"
end

local function getClaimFrameStatusLabel(frame)
	local claimFrame = frame:FindFirstChild("ClaimFrame")
	if not claimFrame then
		return nil
	end
	return claimFrame:FindFirstChild("StatusLabel")
end

local currentStatus = nil

local function startCountdownTimer()
	stopCountdown()

	if not currentStatus then
		return
	end

	local remainingSeconds = currentStatus.RemainingSeconds
	local lastUpdateTime = tick()

	countdownConnection = RunService.Heartbeat:Connect(function()
		local now = tick()

		if now - lastUpdateTime < 1 then
			return
		end

		lastUpdateTime = now

		if remainingSeconds <= 0 then
			stopCountdown()
			ClaimDailyRewardRemote:FireServer("GetStatus")
			return
		end

		remainingSeconds -= 1

		for _, child in pairs(RewardsContainer:GetChildren()) do
			if child:IsA("Frame") then
				local dayIndex = child.LayoutOrder
				local statusLabel = getClaimFrameStatusLabel(child)

				if statusLabel and currentStatus then
					if currentStatus.ClaimedToday and dayIndex == currentStatus.LastClaimedIndex then
    					setText(statusLabel, getRemainingText(remainingSeconds))
					end
				end
			end
		end
	end)
end


DailyRewardClientRemote.OnClientEvent:Connect(function(status)
	if not status or not status.Rewards then
		return
	end

	local remainingSeconds = status.RemainingSeconds

	currentStatus = status


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
		local isClaimable = false

		if rewardInfo.Item then
			if rewardInfo.Item.Type == "Knife" then
				rewardFrame = DailyRewardKnifeTemplate:Clone()
				rewardFrame.LayoutOrder = dayIndex

				local ClaimFrame = rewardFrame.ClaimFrame
				if ClaimFrame then
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
			rewardFrame = DailyRewardCashTemplate:Clone()
			setText(rewardFrame:WaitForChild("DailyRewardCash"):FindFirstChild("CashAmount"), "+" .. rewardInfo.Cash .. " Cash")
		elseif rewardInfo.XP then
			rewardFrame = DailyRewardXPTemplate:Clone()
			setText(rewardFrame:WaitForChild("DailyRewardXP"):FindFirstChild("XPAmount"), "+" .. rewardInfo.XP .. " XP")
		end

		if rewardFrame then
			rewardFrame.LayoutOrder = dayIndex
			local claimFrame = rewardFrame:FindFirstChild("ClaimFrame")
			if claimFrame then
				setText(claimFrame:FindFirstChild("DayText"), "Day " .. tostring(dayIndex))
			end
			
			-- Determine status and if it's claimable
			local statusText = ""
			if dayIndex < status.CurrentDayIndex then
				-- Days before current = already claimed in this cycle
				statusText = "CLAIMED"
				isClaimable = false
			elseif dayIndex == status.CurrentDayIndex then
				if status.ClaimedToday then
					statusText = getRemainingText(status.RemainingSeconds)
					isClaimable = false
				else
					statusText = "CLICK TO CLAIM"
					isClaimable = true
				end
			else
				statusText = "LOCKED"
				isClaimable = false
			end
			
			setText(getClaimFrameStatusLabel(rewardFrame), statusText)
			
			-- Setup the claim button with proper clickability
			local claimButton = claimFrame and claimFrame:FindFirstChild("ClaimButton")
			if claimButton then
				if isClaimable then
					-- Only connect if this day is claimable
					claimButton.MouseButton1Click:Connect(function()
						-- Prevent spam clicking
						local currentTime = tick()
						if currentTime - lastClaimTime < CLAIM_COOLDOWN then
							print("Claim cooldown active, please wait...")
							return
						end
						lastClaimTime = currentTime
						
						print("Claiming day: " .. tostring(dayIndex))
						ClaimDailyRewardRemote:FireServer("Claim", dayIndex)
						

					end)
				else
					-- Make button visually indicate it's not clickable (optional)
					claimButton.Active = false
					claimButton.AutoButtonColor = false
				end
			end
			
			rewardFrame.Parent = RewardsContainer
		end
	end
	
	-- Start the countdown timer
	startCountdownTimer()
end)


CloseButton.MouseButton1Click:Connect(function()
	hideDailyRewards()
end)



return {}