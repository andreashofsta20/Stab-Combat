-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")


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
local SoundHandlerModule = require(script.Parent:WaitForChild("Modules"):WaitForChild("SoundHandler"))
local CaseViewportPool = require(script.Parent.Modules.CaseViewportPool)
local DailyShopClient = require(script.Parent.Modules.DailyShopClient)
local ShopTransitions = require(script.Parent.Modules.ShopTransitions)
local UITransitions = require(script.Parent.Modules.UITransitions)


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
local ShopHeader = ShopFrameUI:WaitForChild("Top"):WaitForChild("Text")
local CloseButton = ShopFrameUI:WaitForChild("Close")
local GoBackButton = ShopFrameUI:WaitForChild("Back")


-- // CASE OPENING FRAMES // --
local CasesFrame = OtherFramesFolder:FindFirstChild("KnivesCases") or OtherFramesFolder:WaitForChild("Cases")
local CaseTemplate = CaseOpeningTemplatesFolder:WaitForChild("CaseTemplate")
local CasesPopUpFrame = ShopFrameUI:WaitForChild("CasesPopup")


local EmotesFrame = OtherFramesFolder:FindFirstChild("EmotesCases") or OtherFramesFolder:WaitForChild("Emotes")
-- Optional dedicated tab. If you haven't built "RevolverCases" in Studio yet,
-- revolver cases simply show up in the normal Cases frame.
local RevolverCasesFrame = OtherFramesFolder:FindFirstChild("RevolversCases")
	or OtherFramesFolder:FindFirstChild("RevolverCases") or CasesFrame
local CratesTabSelection = ShopFrameUI:FindFirstChild("CratesTabSelection", true)
if CratesTabSelection then CratesTabSelection:SetAttribute("UIAnimationDisabled", true) end
local activeCaseTab = "Revolvers"
local caseButtons = {}
local caseTabTweens = {}
local shopTransition = ShopTransitions.Attach(ShopFrameUI)
local caseReveals = {}
local function getCaseReveal(container)
	if not caseReveals[container] then
		caseReveals[container] = UITransitions.Collection(container)
	end
	return caseReveals[container]
end
getCaseReveal(CasesFrame)
getCaseReveal(EmotesFrame)
getCaseReveal(RevolverCasesFrame)
local DailyFrame = OtherFramesFolder:WaitForChild("Daily")
local DailyOthers = DailyFrame:WaitForChild("Others")
local DailyMain = DailyFrame:WaitForChild("Main")
local DailyTemplates = ClientTemplatesFolder:WaitForChild("DailyShopTemplates")
local SmallItemTemplate = DailyTemplates:WaitForChild("SmallItemTemplate")
local LargeItemTemplate = DailyTemplates:WaitForChild("LargeItemTemplate")
local SmallDivider = SmallItemTemplate:WaitForChild("Divider")
local LargeDivider = LargeItemTemplate:WaitForChild("Divider")
local dailyShopLayout = {
	{
		Parent = DailyOthers,
		Template = SmallItemTemplate,
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Fields = {
			Owned = SmallItemTemplate:WaitForChild("AlreadyOwned"),
			Image = SmallItemTemplate:WaitForChild("ItemImage"),
			Name = SmallDivider:WaitForChild("ProductName"),
			Price = SmallDivider:WaitForChild("Price"),
		},
	},
	{
		Parent = DailyOthers,
		Template = SmallItemTemplate,
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Fields = {
			Owned = SmallItemTemplate:WaitForChild("AlreadyOwned"),
			Image = SmallItemTemplate:WaitForChild("ItemImage"),
			Name = SmallDivider:WaitForChild("ProductName"),
			Price = SmallDivider:WaitForChild("Price"),
		},
	},
	{
		Parent = DailyOthers,
		Template = SmallItemTemplate,
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Fields = {
			Owned = SmallItemTemplate:WaitForChild("AlreadyOwned"),
			Image = SmallItemTemplate:WaitForChild("ItemImage"),
			Name = SmallDivider:WaitForChild("ProductName"),
			Price = SmallDivider:WaitForChild("Price"),
		},
	},
	{
		Parent = DailyMain,
		Template = LargeItemTemplate,
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Fields = {
			Owned = LargeItemTemplate:WaitForChild("AlreadyOwned"),
			Image = LargeItemTemplate:WaitForChild("ItemImage"),
			Name = LargeDivider:WaitForChild("ProductName"),
			Price = LargeItemTemplate:WaitForChild("ItemPrice"):WaitForChild("Text"),
		},
	},
	{
		Parent = DailyMain,
		Template = LargeItemTemplate,
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Fields = {
			Owned = LargeItemTemplate:WaitForChild("AlreadyOwned"),
			Image = LargeItemTemplate:WaitForChild("ItemImage"),
			Name = LargeDivider:WaitForChild("ProductName"),
			Price = LargeItemTemplate:WaitForChild("ItemPrice"):WaitForChild("Text"),
		},
	},
}
local dailyShop = DailyShopClient.New(Player, DailyFrame, PurchaseGoldRemote, ShopFrameUI, dailyShopLayout, nil, nil, ShopHeader)
local robuxReveals = {}
local function getRobuxReveal(frame)
	if not robuxReveals[frame] then
		robuxReveals[frame] = UITransitions.Collection(frame)
	end
	return robuxReveals[frame]
end
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
RobuxShopFrame:SetAttribute("UIAnimationDisabled", true)
ShopTabsSelectionFrame:SetAttribute("UIAnimationDisabled", true)
getRobuxReveal(GoldShopFrame)
getRobuxReveal(PasssesShopFrame)
getRobuxReveal(VIPShopFrame)


-- // Purchase Gold SHOP UI // --
local PurchaseGoldFrame = RobuxShopFrame:WaitForChild("Gold")


local buyConnection

local LastCase
local OpenFrame
local PurchaseGold
local SetRobuxTab
local ActiveRobuxTabName
local spinGeneration = 0
local spinDestroyed = false
local spinRemoteConnection
local spinTween, spinFinishTween, spinRarityTween, spinSkipTimer, spinPreviews
local spinConnections = {}

local function cancelSpin(clearCards)
	spinGeneration += 1
	for _, connection in ipairs(spinConnections) do connection:Disconnect() end
	table.clear(spinConnections)
	if spinSkipTimer then task.cancel(spinSkipTimer); spinSkipTimer = nil end
	if spinPreviews then spinPreviews:Destroy(); spinPreviews = nil end
	for _, animation in pairs({spinTween, spinFinishTween, spinRarityTween}) do animation:Cancel(); animation:Destroy() end
	spinTween, spinFinishTween, spinRarityTween = nil, nil, nil
	SpinnerSkipButton.Visible = false
	if clearCards then SpinFrame:ClearAllChildren() end
end

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

-- True chance of ONE specific item: rarity weight / total weight / items in that rarity.
-- (Weights don't have to sum to 100, so never display the raw weight as a percent.)
local function getItemOddsText(caseInfo, rarity: string): string
	local weights = caseInfo.Percentages
	local total = 0
	for _, w in pairs(weights) do
		if type(w) == "number" and w > 0 then
			total += w
		end
	end
	local count = 0
	for _, skin in pairs(caseInfo.Skins) do
		if skin.Rarity == rarity then
			count += 1
		end
	end
	local weight = weights[rarity]
	if total <= 0 or count == 0 or type(weight) ~= "number" or weight <= 0 then
		return "0%"
	end
	local pct = weight / total / count * 100
	local text = string.format("%.2f", pct):gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
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
				ItemOddFrame.Odds.Text = getItemOddsText(CaseInfo, v.Rarity)
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
			ItemOddFrame.Odds.Text = getItemOddsText(CaseInfo, v.Rarity)
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
	local sorted = {}
	for caseName, caseData in pairs(CaseInfoModule) do
		table.insert(sorted, { Name = caseName, Data = caseData })
	end
	table.sort(sorted, function(a, b)
		local ao, bo = a.Data.Order or 999, b.Data.Order or 999
		if ao ~= bo then return ao < bo end
		return a.Name < b.Name
	end)

	for _, entry in ipairs(sorted) do
		local i, v = entry.Name, entry.Data
		task.wait(0.05)
		local CaseFrame = CaseTemplate:Clone()
		CaseFrame.Name = i
		CaseFrame.CaseImage.Image = v.CaseImage
		CaseFrame.Bottom.CaseName.Text = i
		CaseFrame.Bottom.CaseCost.Text = tostring(AbbreviateModule.WithCommas(v.Price))
		CaseFrame.Visible = true
		CaseFrame.LayoutOrder = v.Order or 999
		CaseFrame:SetAttribute("CaseCategory", v.EmoteCase and "Emotes" or v.ItemType == "Revolver" and "Revolvers" or "Knives")
		CaseFrame.Visible = CaseFrame:GetAttribute("CaseCategory") == activeCaseTab
		table.insert(caseButtons, CaseFrame)
		if v.EmoteCase then
			CaseFrame.Parent = EmotesFrame
		elseif v.ItemType == "Revolver" then
			CaseFrame.Parent = RevolverCasesFrame
		else
			CaseFrame.Parent = CasesFrame
		end
		CaseFrame.Activated:Connect(function()
			CasePopUp(i)
		end)
	end
	
end





local function CloseFrame()
	ShopHeader.Text = "Shop"
	shopTransition.Close(function()
		if not SpinnerFrame.Visible then Lighting.Blur.Enabled = false end
	end)
end

local function BackFrame()
	ShopHeader.Text = "Shop"
	if CratesTabSelection then CratesTabSelection.Visible = false end
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("GuiObject") then
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
	GoBackButton.Activated:Connect(function()
		BackFrame()
	end)
	
	CloseButton.Activated:Connect(function()
		CloseFrame()
	end)
	
end

local function HideAllFrames()
	if CratesTabSelection then CratesTabSelection.Visible = false end
	CasesPopUpFrame.Visible = false
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("GuiObject") then
			v.Visible = false
		end
	end 
	
	
	MenuFrame.Visible = false
	GoBackButton.Visible = true
end



local function SetCaseTab(tabName: string)
	if tabName ~= "Knives" and tabName ~= "Revolvers" and tabName ~= "Emotes" then return end
	activeCaseTab = tabName
	HideAllFrames()
	local selectedFrame = tabName == "Emotes" and EmotesFrame or tabName == "Revolvers" and RevolverCasesFrame or CasesFrame
	selectedFrame.Visible = true
	if CratesTabSelection then
		CratesTabSelection.Visible = true
		for _, button in ipairs(CratesTabSelection:GetDescendants()) do
			if button:IsA("ImageButton") then
				local previous = caseTabTweens[button]
				if previous then previous:Cancel(); previous:Destroy() end
				button.AutoButtonColor = false
				local color = button.Name == tabName and Color3.fromRGB(71, 81, 95) or Color3.fromRGB(46, 53, 63)
				local tween = TweenService:Create(button, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = color})
				caseTabTweens[button] = tween
				tween:Play()
			end
		end
	end
	-- The legacy GUI may share a single scrolling frame for knives/revolvers.
	for _, button in ipairs(caseButtons) do button.Visible = button:GetAttribute("CaseCategory") == tabName end
	ShopTransitions.Attach(selectedFrame).Open()
	local reveal = getCaseReveal(selectedFrame)
	reveal.Cancel()
	task.defer(function()
		if selectedFrame.Visible then reveal.Play() end
	end)
end

OpenFrame = function(FrameName : string)
	if FrameName == "Cases" or FrameName == "Crates" then
		ShopHeader.Text = "Shop"
		SetCaseTab("Revolvers"); return
	elseif FrameName == "KnivesCases" or FrameName == "Knives" then
		ShopHeader.Text = "Shop"
		SetCaseTab("Knives"); return
	elseif FrameName == "RevolverCases" or FrameName == "RevolversCases" or FrameName == "Revolvers" then
		ShopHeader.Text = "Shop"
		SetCaseTab("Revolvers"); return
	elseif FrameName == "Emotes" or FrameName == "EmotesCases" then
		ShopHeader.Text = "Shop"
		SetCaseTab("Emotes"); return
	elseif FrameName == "Daily" or FrameName == "DailyShop" then
		HideAllFrames(); dailyShop.Frame.Visible = true
		ShopTransitions.Attach(dailyShop.Frame).Open()
		dailyShop.Open()
		return
	end
	local Frame : Frame = OtherFramesFolder:FindFirstChild(FrameName)
	if Frame then
		ShopHeader.Text = "Shop"
		HideAllFrames()
		Frame.Visible = true
		if Frame ~= RobuxShopFrame then
			ShopTransitions.Attach(Frame).Open()
		end
		if FrameName == "Robux" and SetRobuxTab then
			SetRobuxTab(ActiveRobuxTabName or getDefaultRobuxTabName(), true)
		end
	else
		--print("couldnt find")
	end
	
end


for i , v in pairs(MenuFrame:GetDescendants()) do
	if v:IsA("GuiButton") then
		v.Activated:Connect(function()
			OpenFrame(v.Name)
		--	print(v.Name)
		end)
	end
end

if CratesTabSelection then
	CratesTabSelection.Visible = false
	for _, button in ipairs(CratesTabSelection:GetDescendants()) do
		if button:IsA("ImageButton") then
			button.Activated:Connect(function() SetCaseTab(button.Name) end)
		end
	end
end

ShopFrameUI.Destroying:Connect(function()
	for _, tween in pairs(caseTabTweens) do tween:Cancel(); tween:Destroy() end
	table.clear(caseTabTweens)
	dailyShop.Destroy()
end)


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



spinRemoteConnection = OpenCaseAnimation.OnClientEvent:Connect(function(KnifeDetails: SharedTable, duration, hasskip, casename)
	if spinDestroyed then return end
	local caseInfo = CaseInfoModule[casename]
	if type(KnifeDetails) ~= "table" or not caseInfo or type(duration) ~= "number"
		or duration ~= duration or duration < 0 or duration == math.huge then return end
	cancelSpin(true)
	local token = spinGeneration
	local function current()
		return spinGeneration == token and SpinnerFrame.Parent ~= nil and SpinnerFrame.Visible
	end
	ShopFrameUI.Visible = false
	SpinnerFrame.Visible = true
	SpinnerOpenAgain.Visible, SpinnerExit.Visible = false, false
	HeaderText.Text = "Opening " .. KnifeDetails.Case
	LastCase = KnifeDetails.Case
	Lighting.Blur.Enabled = true
	SpinFrame.Position = UDim2.new(5, 0, 0.5, 0)
	local currentposition = UDim2.new(-0.991, 0, 0.5, 0)
	local randomXScale = Random.new():NextNumber(-4.055, -3.92)
	local tweenGoal = UDim2.new(randomXScale, 0, 0.5, 0)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local WinnerText
	for index = 1, 150 do
		if not current() then return end
		local itemData
		if index == 139 then
			itemData = KnifeDetails
			WinnerText = tostring(KnifeDetails.Knife)
		else
			itemData = RandomItem.RandomItem(casename)
		end
		local item
		if caseInfo.EmoteCase then
			local sourceWorld
			item, sourceWorld = CaseViewportPool.CloneCard(CaseSpinnerTemplateEmote)
			if not spinPreviews then spinPreviews = CaseViewportPool.New(sourceWorld, SpinnerContainer, current) end
		else
			item = CaseSpinnerTemplate:Clone()
			item.KnifeImage.Image = itemData.Image
		end
		item.Name = tostring(index)
		item.Rarity.Image = RarityColorModule[itemData.Rarity].Image
		item.LayoutOrder = index - 1
		if index > 1 then currentposition = UDim2.new(currentposition.X.Scale + 0.014, 0, 0.5, 0) end
		item.Position = currentposition
		item.Parent = SpinFrame
		if caseInfo.EmoteCase then
			local emote = EmotesModule[tostring(itemData.SkinName)]
			if emote then spinPreviews:Add(item, emote.EmoteId) end
		end
		-- Spread lightweight card creation across frames. The preview world is
		-- excluded before cloning; at most ten visible previews are ever live.
		if index % CaseViewportPool.CardBatchSize == 0 and index < 150 then
			RunService.Heartbeat:Wait()
			if not current() then return end
		end
	end
	if not current() then return end
	spinTween = TweenService:Create(SpinFrame, tweenInfo, {Position = tweenGoal})
	local tween = spinTween
	table.insert(spinConnections, tween.Completed:Connect(function(playbackState)
		if not current() or playbackState ~= Enum.PlaybackState.Completed then return end
		spinFinishTween = TweenService:Create(SpinFrame,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = UDim2.new(-3.99, 0, 0.5, 0)})
		local winnerFrame = SpinFrame:FindFirstChild("139")
		local rarity = winnerFrame and winnerFrame:FindFirstChild("Rarity")
		if rarity then
			spinRarityTween = TweenService:Create(rarity,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0})
			spinRarityTween:Play()
		end
		table.insert(spinConnections, spinFinishTween.Completed:Connect(function(state)
			if not current() or state ~= Enum.PlaybackState.Completed then return end
			SpinnerExit.Visible, SpinnerOpenAgain.Visible = true, true
			SpinnerSkipButton.Visible = false
			HeaderText.Text = "You Unboxed: " .. tostring(WinnerText)
		end))
		spinFinishTween:Play()
	end))
	if not hasskip then
		SoundHandlerModule.PlaySound("CaseOpen")
	end
	tween:Play()
	if not hasskip then
		SpinnerSkipButton.Visible = true
		spinSkipTimer = task.delay(6, function()
			if not current() then return end
			spinSkipTimer = nil
			SpinnerSkipButton.Visible = false
		end)
	end
end)

SpinnerFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if not spinDestroyed and not SpinnerFrame.Visible then cancelSpin(true) end
end)
SpinnerFrame.Destroying:Connect(function()
	spinDestroyed = true
	if spinRemoteConnection then spinRemoteConnection:Disconnect(); spinRemoteConnection = nil end
	cancelSpin(false)
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
	cancelSpin(true)
	ShopFrameUI.Visible = true
	SpinnerFrame.Visible = false
	SpinnerExit.Visible = false
	SpinnerOpenAgain.Visible = false
	SpinFrame.Position = UDim2.new(5, 0,0.5, 0)
end)


local function RobuxShopFrameTabs()
	local selectedColor = Color3.fromRGB(71, 81, 95)
	local defaultColor = Color3.fromRGB(46, 53, 63)

	local function playReveal(tabName: string)
		local selectedFrame = RobuxShopFrame:FindFirstChild(tabName)
		if not selectedFrame then
			return
		end
		local reveal = getRobuxReveal(selectedFrame)
		reveal.Cancel()
		task.defer(function()
			if selectedFrame.Visible and RobuxShopFrame.Visible then
				reveal.Play()
			end
		end)
	end

	local function setTab(tabName: string, replayReveal: boolean?)
		local changed = ActiveRobuxTabName ~= tabName
		if not changed then
			if replayReveal then
				playReveal(tabName)
			end
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
		playReveal(tabName)
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
	local passesFrame = RobuxShopFrame:WaitForChild("Passes")
	for _, button in ipairs(passesFrame:GetDescendants()) do
		if button:IsA("ImageButton") or button:IsA("TextButton") then
			button.MouseButton1Up:Connect(function()
				local passKey = button:GetAttribute("GamePassKey") or button:GetAttribute("GamePassId") or button.Name
				GamePass:FireServer(tostring(passKey))
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
