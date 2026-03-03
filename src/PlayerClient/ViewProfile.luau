-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")



-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui



-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ProfileHandlerRemotes = RemotesFolder:WaitForChild("ProfileHandler")
local ViewProfileOnClient = ProfileHandlerRemotes:WaitForChild("ViewProfileClient")

local TradeRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
local TradeRemote = TradeRemotesFolder:WaitForChild("TradeUpdate")

local lastinventory = nil
local viewedProfileUserId: number? = nil


-- // MODULES // --
local RarityImage = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local GetLevelModule = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CalculateLevel"))
local GetThumbnail = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))


-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGUI:WaitForChild("Frames")

local PlayerProfileFrame = FramesFolder:WaitForChild("PlayerInfo")
local PlayerInfoContainer = PlayerProfileFrame:WaitForChild("Container")

local ButtonsFrame = PlayerProfileFrame:WaitForChild("Container"):WaitForChild("PlayerFrame"):WaitForChild("Buttons")

local InventoryFrame = PlayerProfileFrame:WaitForChild("Knives")
local InventoryItemsHolder = InventoryFrame:WaitForChild("Scroll")

local BackButton = PlayerProfileFrame:WaitForChild("Back")

local ItemTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InventoryTemplates"):WaitForChild("KnifeInventoryTemplate")


local RoundHistory = PlayerInfoContainer:WaitForChild("RoundHistory")
local RoundHistoryContainer = RoundHistory:WaitForChild("Scroll")
local RoundHistoryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("BattleHistoryPlayerTemplates"):WaitForChild("BattleHistory")


local function CreateHistoryTemplate(data : SharedTable)
	local template = RoundHistoryTemplate:Clone()
	template.Parent = RoundHistoryContainer
	RoundHistory.Visible = true
	RoundHistoryContainer.Visible = true
	local Container  = template:WaitForChild("Container")


	local Stats = Container:WaitForChild("Stats")
	local Kills = Stats:WaitForChild("Kills#")
	local Placement = Stats:WaitForChild("Placement#")
	local PlrImage = Container:WaitForChild("Players"):WaitForChild("PlayerImage")
	local PlrsInRound = Container:WaitForChild("Players"):WaitForChild("OtherPlayers"):WaitForChild("PlayerAmount")

	   local kills = data and data.Kills or 0
	   local placement = data and data.Placement or nil
	   local opponents = data and data.Opponents or 0
	   local userId = data and data.UserId or nil
	   Kills.Text = tostring(kills)
	   if placement and placement > 0 then
		   Placement.Text = "#" .. tostring(placement)
	   else
		   Placement.Text = "-"
	   end
	   PlrsInRound.Text = tostring(opponents)
	   if userId then
		   PlrImage.Image = GetThumbnail.GetThumbnail(userId) or ""
	   end
	   return template
	
end

local function ClearHistory()
	for _, v in pairs(RoundHistoryContainer:GetChildren()) do
		if v:IsA("Frame") then
			v:Destroy()
		end
	end
end




local function ClearInventory()
	for i , v in pairs(InventoryItemsHolder:GetChildren()) do
		if v:IsA("ImageButton") then
			v:Destroy()
		end
	end
end

local function LoadInventory(data : SharedTable)
	if not data then return end
	
	if not PlayerProfileFrame.Visible then
		return
	end

	ClearInventory()
	
	PlayerProfileFrame:WaitForChild("Container").Visible = false
	
	InventoryFrame.Visible = true
	
	BackButton.Visible = true
	
	PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile's Inventory"

	
	
	for knifeName, knifeData in pairs(data) do
		local Item = ItemTemplate:Clone()
		Item.Name = knifeName
		Item.KnifeName.Text = knifeName
		Item.KnifeImage.Image = tostring(knifeData.Image)
		Item.Quantity.Text = tostring(knifeData.Quantity) .. "x"


		local rarityInfo = RarityImage[knifeData.Rarity]
		if rarityInfo then
			Item.Rarity.Image = rarityInfo.Image
			Item.LayoutOrder = -rarityInfo.Priority
			Item.KnifeSkin.Text = knifeData.Rarity
		else
			Item.Rarity.Image = ""
			Item.LayoutOrder = 999 
		end

		if Item:FindFirstChild("Tradable") then
			Item.Tradable.Visible = knifeData.Tradeable == false
		end

		Item.Parent = InventoryItemsHolder
	end
	
	
	
	print(data)
end


BackButton.MouseButton1Up:Connect(function()
	if InventoryFrame.Visible == true then
		BackButton.Visible = false
		InventoryFrame.Visible = false
		PlayerProfileFrame:WaitForChild("Container").Visible = true
		PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile View"
	end
end)


local function ClearProfileUI()
	local PlayerInfo = PlayerInfoContainer:WaitForChild("PlayerFrame")
	PlayerInfo.Username.Text = ""
	PlayerInfo.Level.Text = "level"
	
	local ProfileContainer = PlayerInfo:WaitForChild("ProfileContainer")
	ProfileContainer.ProfileImg.Image = ""
	
	local StatFrame = PlayerInfoContainer:WaitForChild("StatsFrame")
	
	for i , v in pairs(StatFrame:GetDescendants()) do
		if v:IsA("TextLabel") and v.Name ~= "Title" then
			v.Text = ""
		end
	end
	
	
	local LevelBarFrame = PlayerInfo:WaitForChild("LevelBar")
	LevelBarFrame:WaitForChild("NextLevel").Text = ""
	LevelBarFrame:WaitForChild("ProgressBar").Size = UDim2.new(0, 0,1, 0)
end



local function LoadProfileUI(PlayerInfo)
	ClearProfileUI()
	ClearInventory()
	ClearHistory()

	local xp = PlayerInfo.XP or 0
	local level, currentXP, toNext = GetLevelModule.GetLevel(xp)
	local progressRatio = 0
	if toNext > 0 then
		progressRatio = currentXP / toNext
	else
		progressRatio = 0
	end

	local PlayerInfoFrame = PlayerInfoContainer:WaitForChild("PlayerFrame")
	PlayerInfoFrame.Username.Text = PlayerInfo.Name or "N/A"
	PlayerInfoFrame.Level.Text = "Level: " .. tostring(level)

	local ProfileContainer = PlayerInfoFrame:WaitForChild("ProfileContainer")
	ProfileContainer.ProfileImg.Image = GetThumbnail.GetThumbnail(PlayerInfo.UserId)

	local StatFrame = PlayerInfoContainer:WaitForChild("StatsFrame")
	StatFrame.Wins["Win#"].Text = PlayerInfo.Wins or "N/A"
	StatFrame.Deaths["Death#"].Text = PlayerInfo.Deaths or "N/A"
	StatFrame.Kills["Kill#"].Text = PlayerInfo.Kills or "N/A"

	local kdr = 0
	if (PlayerInfo.Deaths or 0) > 0 then
		kdr = (PlayerInfo.Kills or 0) / PlayerInfo.Deaths
	end
	StatFrame.KDR["KDR#"].Text = string.format("%.2f", kdr)

	local LevelFrame = PlayerInfoFrame:WaitForChild("LevelBar")
	local ProgressBar = LevelFrame:WaitForChild("ProgressBar")
	local NextLevelText = LevelFrame:WaitForChild("NextLevel")

	progressRatio = math.clamp(progressRatio, 0, 1)
	ProgressBar.Size = UDim2.new(progressRatio, 0, 1, 0)
	NextLevelText.Text = tostring(level + 1)

	PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile View"

	   if PlayerInfo and type(PlayerInfo.RoundHistory) == "table" and #PlayerInfo.RoundHistory > 0 then
		   -- Show newest rounds on the left (lowest LayoutOrder)
		   for i, roundEntry in ipairs(PlayerInfo.RoundHistory) do
			   if roundEntry.Placement and roundEntry.Placement > 0 then
				   local template = CreateHistoryTemplate({
					   UserId = PlayerInfo.UserId,
					   Kills = roundEntry.Kills,
					   Placement = roundEntry.Placement,
					   Opponents = roundEntry.Opponents,
				   })
				   -- Newest round gets LayoutOrder 0, next 1, etc.
				   template.LayoutOrder = i - 1
			   end
		   end
	   elseif PlayerInfo and PlayerInfo.LastRound and PlayerInfo.LastRound.Placement and PlayerInfo.LastRound.Placement > 0 then
		   CreateHistoryTemplate({
			   UserId = PlayerInfo.UserId,
			   Kills = PlayerInfo.LastRound.Kills,
			   Placement = PlayerInfo.LastRound.Placement,
			   Opponents = PlayerInfo.LastRound.Opponents,
		   })
	   end
end


PlayerProfileFrame.Close.MouseButton1Up:Connect(function()
	PlayerProfileFrame.Visible = false
	Lighting.Blur.Enabled = false
	viewedProfileUserId = nil
end)

for i , v in pairs(ButtonsFrame:GetChildren()) do
	if v:IsA("ImageButton") then
		if v.Name == "Inventory" then
			v.MouseButton1Up:Connect(function()
				LoadInventory(lastinventory)
			end)
		elseif v.Name == "Trade" then
			v.MouseButton1Up:Connect(function()
				if not viewedProfileUserId then
					return
				end
				if viewedProfileUserId == Player.UserId then
					return
				end
				TradeRemote:FireServer("SEND_REQUEST", viewedProfileUserId)
			end)
		end
		
	end
end



ViewProfileOnClient.OnClientEvent:Connect(function(BasicInfo : SharedTable, inventory : SharedTable)
	viewedProfileUserId = tonumber(BasicInfo and BasicInfo.UserId) or nil
	
	if FramesFolder:FindFirstChild("Spinner").Visible == true then return end

	if FramesFolder:FindFirstChild("Trade").Visible == true then return end
	
	for i , v in pairs(FramesFolder:GetChildren()) do
		if v:IsA("Frame") then
			v.Visible = false
		end
	end
	
	PlayerProfileFrame.Visible = true
	InventoryFrame.Visible = false
	BackButton.Visible = false
	PlayerProfileFrame.Container.Visible = true
	
	ClearProfileUI()
	
	for i , v in pairs(BasicInfo) do
		print(i, v)
	end
	
	for i , v in pairs(inventory) do
		print(i, v)
	end
	lastinventory = inventory
	
	task.wait()
	Lighting.Blur.Enabled = true
	
	LoadProfileUI(BasicInfo)
	
	PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile View"
	
	
	
end)




return {}