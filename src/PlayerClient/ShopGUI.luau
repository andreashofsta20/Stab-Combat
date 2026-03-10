-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")


-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui


-- // MODULES // --
local CaseInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CasesInfo"))
local AbbreviateModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Abbreviate"))
local RarityColorModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local RandomItem = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RandomItems"))
local KnivesInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))
local ProductINFO = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductIDS"))


local EmotesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Emotes"))


-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ShopRemotesFolder = RemotesFolder:WaitForChild("ShopRemotes")
local PurchaseGoldRemotesFolder = ShopRemotesFolder:WaitForChild("PurchaseGold")
local PurchaseGoldRemote = PurchaseGoldRemotesFolder:WaitForChild("PurchaseGoldRemote")

local CaseOpeningFolder = RemotesFolder:WaitForChild("CaseOpening")
local OpenCaseRemote = CaseOpeningFolder:WaitForChild("OpenCase")

local OpenCaseAnimation = CaseOpeningFolder:WaitForChild("CaseAnimationClient")

local GamePass = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopRemotes"):WaitForChild("Gamepass"):WaitForChild("BuyGamePass")

local VIPRemotesFolder = ShopRemotesFolder:WaitForChild("VIP")
local VIPBuyRemote = VIPRemotesFolder:WaitForChild("BuyVIP")
local VIPStatusRemote = VIPRemotesFolder:WaitForChild("VIPStatus")



-- // TEMPLATES // --
local ClientTemplatesFolder = ReplicatedStorage:WaitForChild("UITemplates")
local CaseOpeningTemplatesFolder = ClientTemplatesFolder:WaitForChild("CaseOpeningTemplates")
local OddsItemTemplate = CaseOpeningTemplatesFolder:WaitForChild("OddsItemTemplate")
local OddsItemTemplateEmote = CaseOpeningTemplatesFolder:WaitForChild("OddsItemTemplateEmote")
local CaseSpinnerTemplate = CaseOpeningTemplatesFolder:WaitForChild("CaseSpinnerTemplate")
local CaseSpinnerTemplateEmote = CaseOpeningTemplatesFolder:WaitForChild("CaseSpinnerTemplateEmote")



-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")

local FramesFolder = MainGUI:WaitForChild("Frames")
local ShopFrameUI = FramesFolder:WaitForChild("Shop")
local MenuFrame = ShopFrameUI:WaitForChild("Menu")
local OtherFramesFolder = ShopFrameUI:WaitForChild("Holders")
local CloseButton = ShopFrameUI:WaitForChild("Close")
local GoBackButton = ShopFrameUI:WaitForChild("Back")


-- // CASE OPENING FRAMES // --
local CasesFrame = OtherFramesFolder:WaitForChild("Cases")
local CaseTemplate = CaseOpeningTemplatesFolder:WaitForChild("CaseTemplate")
local CasesPopUpFrame = ShopFrameUI:WaitForChild("CasesPopup")


local EmotesFrame = OtherFramesFolder:WaitForChild("Emotes")


-- // CASE ANIMATION FRAMES // --
local SpinnerFrame = FramesFolder:WaitForChild("Spinner")
local SpinnerContainer = SpinnerFrame:WaitForChild("Container")
local SpinFrame = SpinnerContainer:WaitForChild("SpinFrame")
local SpinDecoration = SpinnerContainer:WaitForChild("Spinner")

local SpinnerButtonsContainer = SpinnerFrame:WaitForChild("Buttons")
local SpinnerExit = SpinnerButtonsContainer:WaitForChild("Exit")
local SpinnerOpenAgain = SpinnerButtonsContainer:WaitForChild("OpenAgain")
local SpinnerSkipButton = SpinnerButtonsContainer:WaitForChild("Skip")
local HeaderText = SpinnerButtonsContainer:WaitForChild("Header")





-- // ROBUX SHOP UI // --
local RobuxShopFrame = OtherFramesFolder:WaitForChild("Robux")
local GoldShopFrame = RobuxShopFrame:WaitForChild("Gold")
local PasssesShopFrame = RobuxShopFrame:WaitForChild("Passes")
local VIPShopFrame = RobuxShopFrame:WaitForChild("VIP")
local ShopTabsSelectionFrame = RobuxShopFrame:WaitForChild("TabSelection")


-- // Purchase Gold SHOP UI // --
local PurchaseGoldFrame = RobuxShopFrame:WaitForChild("Gold")


local buyConnection

local LastCase
local OpenFrame
local PurchaseGold
local SetRobuxTab
local ActiveRobuxTabName

local function getDefaultRobuxTabName(): string
	for _, button in pairs(ShopTabsSelectionFrame:GetChildren()) do
		if button:IsA("ImageButton") then
			return button.Name
		end
	end
	return "Gold"
end

local function getLocalCashAmount(): number
	local leaderstats = Player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	return cashValue and cashValue.Value or 0
end

local function getBestGoldProductId(requiredGold: number): number?
	local chosenId = nil
	local chosenAmount = math.huge
	local highestId = nil
	local highestAmount = -1

	for productId, goldAmount in pairs(ProductINFO) do
		local idNum = tonumber(productId)
		local amountNum = tonumber(goldAmount)
		if idNum and amountNum then
			if amountNum >= requiredGold and amountNum < chosenAmount then
				chosenAmount = amountNum
				chosenId = idNum
			end
			if amountNum > highestAmount then
				highestAmount = amountNum
				highestId = idNum
			end
		end
	end

	return chosenId or highestId
end

local function openGoldPurchaseFlow(requiredGold: number)
	if CasesPopUpFrame.Visible then
		CasesPopUpFrame.Visible = false
	end

	OpenFrame("Robux")
	if SetRobuxTab then
		SetRobuxTab("Gold")
	else
		GoldShopFrame.Visible = true
		PasssesShopFrame.Visible = false
		VIPShopFrame.Visible = false
	end

	local productId = getBestGoldProductId(requiredGold)
	if productId then
		PurchaseGold(productId)
	end
end

local function tryOpenCase(caseName: string)
	local caseInfo = CaseInfoModule[caseName]
	if not caseInfo then
		return
	end

	local currentCash = getLocalCashAmount()
	if currentCash < caseInfo.Price then
		openGoldPurchaseFlow(caseInfo.Price - currentCash)
		return
	end

	OpenCaseRemote:FireServer(caseName)
end


local function CasePopUp(CaseName : string)
	
	if buyConnection then
		buyConnection:Disconnect()
	end
	
	
	local CaseInfo = CaseInfoModule[CaseName]
	
	if not CaseInfo then
		print("couldnt find case")
		return
	end
	
	
	if CaseInfo.EmoteCase then
		CasesPopUpFrame.Visible = true
		local CasePopUp = CasesPopUpFrame:WaitForChild("Holder")
		local Top = CasePopUp:WaitForChild("Top")
		local TopCaseName = Top:WaitForChild("Header")
		local ContainerFrame = CasePopUp:WaitForChild("Container")
		local OddsContainer = ContainerFrame:WaitForChild("OddsContainer")
		local BuyContainer = ContainerFrame:WaitForChild("BuyContainer")


		local CaseInfo = CaseInfoModule[CaseName]
		local Chances = CaseInfoModule[CaseName].Percentages

		for i , v in pairs(OddsContainer:GetChildren()) do
			if v:IsA("ImageButton") then
				v:Destroy()
			end
		end
		
		
		BuyContainer.Buy.Cost.Text = ""


		if CaseInfoModule[CaseName] then
		--	print("found")
			for i , v in pairs(CaseInfoModule[CaseName].Skins) do
				local ItemOddFrame = OddsItemTemplateEmote:Clone()
				ItemOddFrame.Name = tostring(i)
				ItemOddFrame.Rarity.Image = RarityColorModule[v.Rarity].Image
				ItemOddFrame.LayoutOrder = RarityColorModule[v.Rarity].Priority
				ItemOddFrame.Odds.Text = tostring(Chances[v.Rarity]) .. "%"
				ItemOddFrame.Parent = OddsContainer
				
				
				local ViewportFrame = ItemOddFrame:WaitForChild("EmoteViewport")
				local World = ViewportFrame:WaitForChild("World")
				local Rig = World:WaitForChild("Rig")
				local RigHumanoid = Rig:WaitForChild("Humanoid")

				local AnimationRig:Animation = Instance.new("Animation")
				AnimationRig.AnimationId = EmotesModule[tostring(i)].EmoteId
				
				
			--	print(AnimationRig.AnimationId)

				local AnimationTrack = RigHumanoid:LoadAnimation(AnimationRig)
				AnimationTrack.Looped = true
				AnimationTrack:Play()
				

			end

			BuyContainer.Buy.Cost.Text = tostring(AbbreviateModule.WithCommas(CaseInfo.Price)) .. " Gold"
			TopCaseName.Text = tostring(CaseName)
		else
		--	print("didnt find")
		end


		buyConnection = BuyContainer.Buy.MouseButton1Up:Connect(function()
			tryOpenCase(CaseName)
		end)
		return
	end
	
	CasesPopUpFrame.Visible = true
	local CasePopUp = CasesPopUpFrame:WaitForChild("Holder")
	local Top = CasePopUp:WaitForChild("Top")
	local TopCaseName = Top:WaitForChild("Header")
	local ContainerFrame = CasePopUp:WaitForChild("Container")
	local OddsContainer = ContainerFrame:WaitForChild("OddsContainer")
	local BuyContainer = ContainerFrame:WaitForChild("BuyContainer")
	
	
	local CaseInfo = CaseInfoModule[CaseName]
	local Chances = CaseInfoModule[CaseName].Percentages
	
	for i , v in pairs(OddsContainer:GetChildren()) do
		if v:IsA("ImageButton") then
			v:Destroy()
		end
	end
	BuyContainer.Buy.Cost.Text = ""
	
	
	if CaseInfoModule[CaseName] then
		--print("found")
		for i , v in pairs(CaseInfoModule[CaseName].Skins) do
			local ItemOddFrame = OddsItemTemplate:Clone()
			ItemOddFrame.Name = tostring(i)
			ItemOddFrame.Rarity.Image = RarityColorModule[v.Rarity].Image
			ItemOddFrame.KnifeImage.Image = v.Image
			ItemOddFrame.LayoutOrder = RarityColorModule[v.Rarity].Priority
			ItemOddFrame.Odds.Text = tostring(Chances[v.Rarity]) .. "%"
			ItemOddFrame.Parent = OddsContainer
			


		end
		
		BuyContainer.Buy.Cost.Text = tostring(AbbreviateModule.WithCommas(CaseInfo.Price)) .. " Gold"
		TopCaseName.Text = tostring(CaseName)
	else
	--	print("didnt find")
	end
	
	
	buyConnection = BuyContainer.Buy.MouseButton1Up:Connect(function()
		tryOpenCase(CaseName)
	end)
	
	

	
end


CasesPopUpFrame.Holder.Top.Close.MouseButton1Up:Connect(function()
	if CasesPopUpFrame.Visible == true then
		CasesPopUpFrame.Visible = false
	end
end)

local function LoadCases()
	for i , v in pairs(CaseInfoModule) do
		task.wait(0.3)
		local CaseFrame = CaseTemplate:Clone()
		CaseFrame.Name = i
		CaseFrame.CaseImage.Image = v.CaseImage
		CaseFrame.Bottom.CaseName.Text = i
		CaseFrame.Bottom.CaseCost.Text = tostring(AbbreviateModule.WithCommas(v.Price))
		CaseFrame.Visible = true
		if v.EmoteCase then
			CaseFrame.Parent = EmotesFrame
		else
			CaseFrame.Parent = CasesFrame
		end
		CaseFrame.MouseButton1Up:Connect(function()
			CasePopUp(i)
		end)
	end
	
end





local function CloseFrame()
	ShopFrameUI.Visible = false
	Lighting.Blur.Enabled = false
end

local function BackFrame()
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("Frame") or v:IsA("ScrollingFrame") then 
			v.Visible = false
		end
	end
	MenuFrame.Visible = true
	GoBackButton.Visible = false
	
	if CasesPopUpFrame.Visible then
		CasesPopUpFrame.Visible = false
	end
end

local function basics()
	GoBackButton.MouseButton1Up:Connect(function()
		BackFrame()
	end)
	
	CloseButton.MouseButton1Up:Connect(function()
		CloseFrame()
	end)
	
end

function HideAllFrames()
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("Frame") or v:IsA("ScrollingFrame") then
			v.Visible = false
		end
	end 
	
	
	MenuFrame.Visible = false
	GoBackButton.Visible = true
end



OpenFrame = function(FrameName : string)
	local Frame : Frame = OtherFramesFolder:FindFirstChild(FrameName)
	if Frame then
		HideAllFrames()
		Frame.Visible = true
		if FrameName == "Robux" and SetRobuxTab then
			SetRobuxTab(ActiveRobuxTabName or getDefaultRobuxTabName())
		end
	else
		--print("couldnt find")
	end
	
end


for i , v in pairs(MenuFrame:GetDescendants()) do
	if v:IsA("ImageButton") then
		v.MouseButton1Up:Connect(function()
			OpenFrame(v.Name)
		--	print(v.Name)
		end)
	end
end


PurchaseGold = function(productid : number)
	--print(productid)
	PurchaseGoldRemote:FireServer(productid)
end


local function SetUpGoldPurchase()
	for i , v in pairs(PurchaseGoldFrame:GetDescendants()) do
		if v:IsA("ImageButton") then
			v.MouseButton1Up:Connect(function()
				PurchaseGold(tonumber(v.Name))
			end)
		end
	end
end



OpenCaseAnimation.OnClientEvent:Connect(function(KnifeDetails : SharedTable, duration, hasskip, casename)
	ShopFrameUI.Visible = false
	SpinnerFrame.Visible = true
	for i , v in pairs(SpinFrame:GetChildren()) do
		if v:IsA("ImageButton") then
			v:Destroy()
		end
	end
	
	SpinFrame:ClearAllChildren()
	
	
	
	--print(KnifeDetails)
	HeaderText.Text = "Opening " .. KnifeDetails.Case
	LastCase = KnifeDetails.Case

	local Winner = KnifeDetails["Knife"]
	local currentposition = UDim2.new(-0.991, 0,0.5, 0)
	Lighting.Blur.Enabled = true
	
	local FRAMETOMOVEPOSITION = SpinnerFrame:WaitForChild("Container"):WaitForChild("SpinFrame")
	
	local randomXScale = Random.new():NextNumber(-4.055, -3.92)
	local tweenGoal = UDim2.new(randomXScale, 0, 0.5, 0)
	local tweenInfo = TweenInfo.new(
		duration, 
		Enum.EasingStyle.Quint, 
		Enum.EasingDirection.Out 
	)
	local WinnerText
	local layoutcount = 0
	SpinnerOpenAgain.Visible = false
	SpinnerExit.Visible = false

	
	for i = 1, 150 do
		
		if CaseInfoModule[casename].EmoteCase then
			local ItemTemplate = CaseSpinnerTemplateEmote:Clone()
			local itemData
			
			if i == 139 then
				itemData = KnifeDetails
				WinnerText = tostring(KnifeDetails.Knife)
			else
				itemData = RandomItem.RandomItem(casename)
			end
			
			ItemTemplate.Name = tostring(i)
			ItemTemplate.Rarity.Image = RarityColorModule[itemData.Rarity].Image
			ItemTemplate.LayoutOrder = layoutcount
			layoutcount += 1
			
			
			if i == 1 then
				ItemTemplate.Position = currentposition
			else
				ItemTemplate.Position = UDim2.new((currentposition.X.Scale + 0.014), 0, 0.5, 0)
				currentposition= UDim2.new((currentposition.X.Scale + 0.014), 0, 0.5, 0)
			end

			
			ItemTemplate.Parent = SpinFrame
			local SkinName = itemData.SkinName
			
			
			
			local ViewportFrame1 = ItemTemplate:WaitForChild("EmoteViewport")
			local World1 = ViewportFrame1:WaitForChild("World")
			local Rig1 = World1:WaitForChild("Rig")
			local RigHumanoid1 = Rig1:WaitForChild("Humanoid")

			local AnimationRig1:Animation = Instance.new("Animation")
			AnimationRig1.AnimationId = EmotesModule[tostring(SkinName)].EmoteId



			local AnimationTrack1 = RigHumanoid1:LoadAnimation(AnimationRig1)
			AnimationTrack1.Looped = true
			AnimationTrack1:Play()
		else
			

			local ItemTemplate = CaseSpinnerTemplate:Clone()
			local knifeData

			if i == 139 then
				knifeData = KnifeDetails
				WinnerText = tostring(KnifeDetails.Knife)
			else
				knifeData = RandomItem.RandomItem(casename)
			end


			ItemTemplate.Name = tostring(i)
			ItemTemplate.KnifeImage.Image = knifeData.Image
			ItemTemplate.Rarity.Image = RarityColorModule[knifeData.Rarity].Image
			ItemTemplate.LayoutOrder = layoutcount
			layoutcount += 1
			if i == 1 then
				ItemTemplate.Position = currentposition
			else
				ItemTemplate.Position = UDim2.new((currentposition.X.Scale + 0.014), 0, 0.5, 0)
				currentposition= UDim2.new((currentposition.X.Scale + 0.014), 0, 0.5, 0)
			end

			ItemTemplate.Parent = SpinFrame

		end
	end
	
	FRAMETOMOVEPOSITION.Position = UDim2.new(5, 0,0.5, 0)
	
	
	local tween = TweenService:Create(FRAMETOMOVEPOSITION, tweenInfo, {Position = tweenGoal})
	tween:Play()
	task.spawn(function()
		if hasskip then
			
		else
			SpinnerSkipButton.Visible = true
			task.wait(6)
			SpinnerSkipButton.Visible = false
		end
	end)

	tween.Completed:Connect(function()
		local finishTween = TweenService:Create(
			SpinFrame,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(-3.99, 0, 0.5, 0) }
		)

		local winnerFrame = SpinFrame:FindFirstChild("139")
		local winnerRarityImage = winnerFrame and winnerFrame:FindFirstChild("Rarity")


		local rarityTween, knifeTween

		if winnerRarityImage then
			rarityTween = TweenService:Create(
				winnerRarityImage,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = 0 }
			)
		end



		finishTween:Play()
		if rarityTween then rarityTween:Play() end

		finishTween.Completed:Connect(function()
			SpinnerExit.Visible = true
			HeaderText.Text = "You Unboxed: " .. tostring(WinnerText)
			SpinnerOpenAgain.Visible = true
		end)
	end)
	

	
end)


SpinnerOpenAgain.MouseButton1Up:Connect(function()
	if LastCase then
		OpenCaseRemote:FireServer(LastCase)
	end
end)


SpinnerSkipButton.MouseButton1Up:Connect(function()
	GamePass:FireServer("1")
end)

SpinnerExit.MouseButton1Up:Connect(function()
	ShopFrameUI.Visible = true
	SpinnerFrame.Visible = false
	SpinnerExit.Visible = false
	SpinnerOpenAgain.Visible = false
	SpinFrame.Position = UDim2.new(5, 0,0.5, 0)
	for i , v in pairs(SpinFrame:GetChildren()) do
		if v:IsA("ImageButton") then
			v:Destroy()
		end
	end
	
	SpinFrame:ClearAllChildren()
end)


local function RobuxShopFrameTabs()
	local selectedColor = Color3.fromRGB(71, 81, 95)
	local defaultColor = Color3.fromRGB(46, 53, 63)

	local function setTab(tabName: string)
		if ActiveRobuxTabName == tabName then
			return
		end

		for _, frame in pairs(RobuxShopFrame:GetChildren()) do
			if frame:IsA("ScrollingFrame") and frame.Name ~= "TabSelection" then
				frame.Visible = (frame.Name == tabName)
			end
		end

		for _, button in pairs(ShopTabsSelectionFrame:GetChildren()) do
			if button:IsA("ImageButton") then
				local isSelected = button.Name == tabName
				button.BackgroundColor3 = isSelected and selectedColor or defaultColor
				button.ImageColor3 = isSelected and selectedColor or defaultColor
			end
		end

		ActiveRobuxTabName = tabName
	end

	SetRobuxTab = setTab

	for _, button in pairs(ShopTabsSelectionFrame:GetChildren()) do
		if button:IsA("ImageButton") then
			button.MouseButton1Up:Connect(function()
				setTab(button.Name)
			end)

			if not ActiveRobuxTabName then
				setTab(button.Name)
			end
		end
	end
end

local function HandleRobuxGamepassButtons()
	for i , v in pairs(RobuxShopFrame:WaitForChild("Passes"):GetChildren()) do
		if v:IsA("ImageButton") then
			v.MouseButton1Up:Connect(function()
				GamePass:FireServer(tostring(v.Name))
			end)
		end
	end
end

local function HandleVIPShop()
	local VIPFrame = RobuxShopFrame:WaitForChild("VIP")
	local SubscribeFrame = VIPFrame:WaitForChild("SubscribeFrame")
	local SubscriptionStatus = SubscribeFrame:WaitForChild("SubscriptionStatus")

	local function formatRemaining(secondsLeft: number): string
		secondsLeft = math.max(0, math.floor(secondsLeft))
		local days = math.floor(secondsLeft / 86400)
		local hours = math.floor((secondsLeft % 86400) / 3600)
		local minutes = math.floor((secondsLeft % 3600) / 60)
		return string.format("%dd %dh %dm", days, hours, minutes)
	end

	local function updateStatus(hasVIP: boolean, expiresAt: number, nowTime: number?)
		local now = tonumber(nowTime) or os.time()
		if hasVIP and expiresAt > now then
			SubscriptionStatus.Text = "STATUS : ACTIVE (" .. formatRemaining(expiresAt - now) .. ")"
		else
			SubscriptionStatus.Text = "STATUS : NO SUBSCRIPTION"
		end
	end

	SubscriptionStatus.Text = "STATUS : LOADING..."

	local Subscribe1WeekButton = SubscribeFrame:WaitForChild("3548752161")
	local Subscribe1MonthButton = SubscribeFrame:WaitForChild("3548752035")

	Subscribe1WeekButton.MouseButton1Up:Connect(function()
		VIPBuyRemote:FireServer(3548752161)
	end)

	Subscribe1MonthButton.MouseButton1Up:Connect(function()
		VIPBuyRemote:FireServer(3548752035)
	end)

	VIPStatusRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		local hasVIP = payload.HasVIP == true
		local expiresAt = tonumber(payload.ExpiresAt) or 0
		local now = tonumber(payload.Now) or os.time()
		updateStatus(hasVIP, expiresAt, now)
	end)

	VIPStatusRemote:FireServer("REQUEST_STATUS")


	
end


local function SetUpShop()
	SetUpGoldPurchase()
	HandleVIPShop()
end
basics()
SetUpShop()
LoadCases()
RobuxShopFrameTabs()
HandleRobuxGamepassButtons()











return {} 