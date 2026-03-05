local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityColor = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))

local Plr = Players.LocalPlayer
local PlrGui = Plr:WaitForChild("PlayerGui")
local MainGui = PlrGui:WaitForChild("Main")

local TradingRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
local TradeRemote = TradingRemotesFolder:WaitForChild("TradeUpdate")

local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local TradingTemplatesFolder = UITemplates:WaitForChild("TradeRequestTemplates")
local RecieveRequestTemplate = TradingTemplatesFolder:WaitForChild("TradeRequest")
local InventoryTemplatesFolder = UITemplates:FindFirstChild("InventoryTemplates")
local TradeItemTemplate = InventoryTemplatesFolder:FindFirstChild("KnifeInventoryTemplate")


if not TradeItemTemplate then
	error("TradingClient: missing TradeItem or InventoryTemplates/KnifeInventoryTemplate UI template")
end

local layoutorder = 0
local TradeRequestsFrame = MainGui:WaitForChild("TradeRequests")
local TradeFrame = MainGui:WaitForChild("Frames"):WaitForChild("Trade")

local requestTemplates = {}
local currentTradeData = nil
local uiRefreshLoopActive = false
local localAcceptReadyAt = 0 -- tick() when accept becomes available (local clock)
local ACCEPT_DELAY = 5 -- seconds after both confirm before accept is allowed

local function getFirstDescendantByName(root: Instance, childName: string)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == childName then
			return descendant
		end
	end
	return nil
end

local function resolveOfferContainer(offerFrame: Instance)
	local itemContainer = offerFrame:FindFirstChild("ItemContainer")
	if itemContainer then
		local skins = itemContainer:FindFirstChild("Skins")
		if skins then
			local holder = skins:FindFirstChild("Holder")
			return holder or skins
		end
	end

	return nil
end

local function resolveInventoryContainer(localOfferFrame: Instance)
	local skins = localOfferFrame:FindFirstChild("Skins")
	if skins then
		local holder = skins:FindFirstChild("Holder")
		return holder or skins
	end

	local fallback = getFirstDescendantByName(localOfferFrame, "Holder")
	if fallback then
		return fallback
	end

	return localOfferFrame
end

local function resolveSidebarInventoryContainer(sideBar: Instance?)
	if not sideBar then
		return nil
	end

	local directScroll = sideBar:FindFirstChild("Scroll")
	if directScroll then
		local holder = directScroll:FindFirstChild("Holder")
		return holder or directScroll
	end

	local directContainer = sideBar:FindFirstChild("Container")
	if directContainer then
		local holder = directContainer:FindFirstChild("Holder")
		return holder or directContainer
	end

	local itemContainer = sideBar:FindFirstChild("ItemContainer")
	if itemContainer then
		local skins = itemContainer:FindFirstChild("Skins")
		if skins then
			local holder = skins:FindFirstChild("Holder")
			return holder or skins
		end
		local holder = itemContainer:FindFirstChild("Holder")
		return holder or itemContainer
	end

	local skins = sideBar:FindFirstChild("Skins")
	if skins then
		local holder = skins:FindFirstChild("Holder")
		return holder or skins
	end

	local fallbackHolder = getFirstDescendantByName(sideBar, "Holder")
	if fallbackHolder then
		return fallbackHolder
	end

	return sideBar
end

local function resolveTradeUi()
	local localOffer = TradeFrame:FindFirstChild("YourOffer")
	local otherOffer = TradeFrame:FindFirstChild("TheirOffer")
	if not localOffer or not otherOffer then
		return nil
	end

	local localTab = localOffer:FindFirstChild("PlayerTab")
	local otherTab = otherOffer:FindFirstChild("PlayerTab")

	local sideBar = TradeFrame:FindFirstChild("SideBar")
	local buttons = sideBar and sideBar:FindFirstChild("Buttons")

	local ui = {
		LocalOffer = localOffer,
		OtherOffer = otherOffer,
		LocalTab = localTab,
		OtherTab = otherTab,
		LocalOfferContainer = resolveOfferContainer(localOffer) or resolveInventoryContainer(localOffer),
		OtherOfferContainer = resolveOfferContainer(otherOffer) or resolveInventoryContainer(otherOffer),
		InventoryContainer = resolveSidebarInventoryContainer(sideBar),
		AcceptButton = buttons and buttons:FindFirstChild("Accept"),
		CancelButton = buttons and buttons:FindFirstChild("Cancel"),
	}

	if localTab then
		ui.LocalConfirmed = localTab:FindFirstChild("Confirmed") and localTab.Confirmed:FindFirstChild("Check")
		ui.LocalAccepted = localTab:FindFirstChild("Accepted") and localTab.Accepted:FindFirstChild("Check")
		ui.LocalUsername = localTab:FindFirstChild("UsernameOffer")
	end

	if otherTab then
		ui.OtherConfirmed = otherTab:FindFirstChild("Confirmed") and otherTab.Confirmed:FindFirstChild("Check")
		ui.OtherAccepted = otherTab:FindFirstChild("Accepted") and otherTab.Accepted:FindFirstChild("Check")
		ui.OtherUsername = otherTab:FindFirstChild("UsernameOffer")
	end

	return ui
end

local function clearItemButtons(container: Instance?)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local function splitTradeData(tradeData)
	if not tradeData or not tradeData.Player1 or not tradeData.Player2 then
		return nil, nil
	end

	if tradeData.Player1.UserId == Plr.UserId then
		return tradeData.Player1, tradeData.Player2
	end

	if tradeData.Player2.UserId == Plr.UserId then
		return tradeData.Player2, tradeData.Player1
	end

	return tradeData.Player1, tradeData.Player2
end

local function setCheckVisible(checkObject: Instance?, visible: boolean)
	if checkObject and checkObject:IsA("GuiObject") then
		checkObject.Visible = visible
	end
end

local function setButtonText(button: Instance?, text: string)
	if not button then
		return
	end

	if button:IsA("TextButton") then
		button.Text = text
		return
	end

	local header = button:FindFirstChild("Header")
	if header and header:IsA("TextLabel") then
		header.Text = text
	end
end

local function getInventoryItems()
	local leaderstats = Plr:FindFirstChild("leaderstats")
	local inventory = leaderstats and leaderstats:FindFirstChild("Inventory")
	if not inventory then
		return {}
	end

	local items = {}
	for _, item in ipairs(inventory:GetChildren()) do
		if item:IsA("StringValue") then
			local tradeableValue = item:FindFirstChild("Tradeable")
			local isTradeable = true
			if not tradeableValue then
				isTradeable = false
			end
			if tradeableValue and tradeableValue:IsA("BoolValue") then
				isTradeable = tradeableValue.Value == true
			end


			table.insert(items, item)
		end
	end
	return items
end

local function getOfferedQuantityByName(items)
	local offered = {}
	for _, item in ipairs(items or {}) do
		if item and item.Name then
			offered[item.Name] = (offered[item.Name] or 0) + (item.Quantity or 1)
		end
	end
	return offered
end

local function countKnifeSlots(items)
	local count = 0
	for _, item in ipairs(items or {}) do
		if item.Type == "Inventory" then
			count += 1
		end
	end
	return count
end

local function buildItemButton(itemName: string, quantity: number, image: string?, rarity: string?)
	local itemClone = TradeItemTemplate:Clone()
	itemClone.Name = itemName

	if itemClone:FindFirstChild("ItemName") then
		itemClone.ItemName.Text = itemName .. " x" .. tostring(quantity)
	end

	if itemClone:FindFirstChild("KnifeName") then
		itemClone.KnifeName.Text = itemName
	end

	if itemClone:FindFirstChild("Quantity") then
		itemClone.Quantity.Text = "x" .. tostring(quantity)
	end

	if itemClone:FindFirstChild("ItemImage") then
		itemClone.ItemImage.Image = image or ""
	end

	if itemClone:FindFirstChild("KnifeImage") then
		itemClone.KnifeImage.Image = image or ""
	end

	if itemClone:FindFirstChild("KnifeSkin") and rarity then
		itemClone.KnifeSkin.Text = rarity
	end

	if rarity then
		local rarityData = RarityColor[rarity]
		if rarityData then
			itemClone.LayoutOrder = -rarityData.Priority
		else
			itemClone.LayoutOrder = 0
		end
	end

	if itemClone:FindFirstChild("Tradable") then
		if itemName == "Shadow Dagger" then
			itemClone.Tradable.Visible = true
			itemClone.LayoutOrder = 999
			itemClone.Interactable = false
		else
			itemClone.Tradable.Visible = false
		end
	end

	if itemClone:FindFirstChild("Rarity") and rarity then
		local rarityModule = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("RarityColor")
		if rarityModule then
			local rarityColors = require(rarityModule)
			local rarityData = rarityColors[rarity]
			if rarityData and rarityData.Image and itemClone.Rarity:IsA("ImageLabel") then
				itemClone.Rarity.Image = rarityData.Image
			end
		end
	end

	return itemClone
end

local function refreshTradeUi()
	if not currentTradeData then
		return
	end

	local ui = resolveTradeUi()
	if not ui then
		return
	end

	local localSide, otherSide = splitTradeData(currentTradeData)
	if not localSide or not otherSide then
		return
	end

	TradeFrame.Visible = true

	if ui.LocalUsername then
		ui.LocalUsername.Text = "Your Offer"
	end

	if ui.OtherUsername then
		ui.OtherUsername.Text = otherSide.Name .. "'s Offer"
	end

	local offeredByName = getOfferedQuantityByName(localSide.Items)
	local knifeSlotsUsed = countKnifeSlots(localSide.Items)
	local knifeSlotsFull = knifeSlotsUsed >= 4
	local localLocked = localSide.Locked == true

	clearItemButtons(ui.InventoryContainer)
	for _, item in ipairs(getInventoryItems()) do
		local quantityValue = item:FindFirstChild("Quantity")
		local ownedQuantity = quantityValue and quantityValue.Value or 1
		local imageValue = item:FindFirstChild("Image")
		local image = imageValue and imageValue.Value or ""
		local rarityValue = item:FindFirstChild("Rarity")
		local rarity = rarityValue and rarityValue.Value or "Common"
		local offeredQuantity = offeredByName[item.Name] or 0
		local remainingQuantity = math.max(0, ownedQuantity - offeredQuantity)

		local isOffered = offeredQuantity > 0
		local canAddKnife = (not knifeSlotsFull) or isOffered

		if remainingQuantity > 0 then
			local itemButton = buildItemButton(item.Name, remainingQuantity, image, rarity)
			itemButton.Parent = ui.InventoryContainer
			if itemButton:IsA("GuiButton") then
				itemButton.Active = not localLocked and canAddKnife
			end
			if not localLocked and canAddKnife then
				itemButton.MouseButton1Click:Connect(function()
					TradeRemote:FireServer("ADD_ITEM", "Inventory", item.Name, 1)
				end)
			end
		end
	end

	clearItemButtons(ui.LocalOfferContainer)
	for _, item in ipairs(localSide.Items or {}) do
		local itemButton = buildItemButton(item.Name, item.Quantity or 1, item.Image, item.Rarity)
		itemButton.Parent = ui.LocalOfferContainer
		if itemButton:IsA("GuiButton") then
			itemButton.Active = not localLocked
		end
		if not localLocked then
			itemButton.MouseButton1Click:Connect(function()
				TradeRemote:FireServer("REMOVE_ITEM", item.Name, 1)
			end)
		end
	end

	clearItemButtons(ui.OtherOfferContainer)
	for _, item in ipairs(otherSide.Items or {}) do
		local itemButton = buildItemButton(item.Name, item.Quantity or 1, item.Image, item.Rarity)
		itemButton.Parent = ui.OtherOfferContainer
		if itemButton:IsA("GuiButton") then
			itemButton.Active = false
		end
	end

	setCheckVisible(ui.LocalConfirmed, localSide.Locked == true)
	setCheckVisible(ui.OtherConfirmed, otherSide.Locked == true)

	setCheckVisible(ui.LocalAccepted, localSide.Accepted == true)
	setCheckVisible(ui.OtherAccepted, otherSide.Accepted == true)

	local tradeComplete = currentTradeData.State == "COMPLETED"
	local bothLocked = localLocked and otherSide.Locked == true
	local localAccepted = localSide.Accepted == true
	local waitRemaining = math.max(0, localAcceptReadyAt - tick())

	if tradeComplete then
		setButtonText(ui.AcceptButton, "DONE")
	elseif not localLocked then
		setButtonText(ui.AcceptButton, "CONFIRM")
	elseif not bothLocked then
		setButtonText(ui.AcceptButton, "UNCONFIRM")
	elseif localAccepted then
		setButtonText(ui.AcceptButton, "WAITING...")
	elseif bothLocked and waitRemaining > 0 then
		setButtonText(ui.AcceptButton, "UNCONFIRM (" .. tostring(math.ceil(waitRemaining)) .. "S)")
	else
		setButtonText(ui.AcceptButton, "ACCEPT")
	end

	if ui.AcceptButton and ui.AcceptButton:IsA("GuiButton") then
		ui.AcceptButton.Active = not tradeComplete
	end
end

local function ensureUiRefreshLoop()
	if uiRefreshLoopActive then
		return
	end

	uiRefreshLoopActive = true
	task.spawn(function()
		while uiRefreshLoopActive do
			task.wait(1)
			if not currentTradeData then
				uiRefreshLoopActive = false
				break
			end

			if currentTradeData.State == "COMPLETED" or currentTradeData.State == "CANCELLED" then
				uiRefreshLoopActive = false
				break
			end

			refreshTradeUi()
		end
		uiRefreshLoopActive = false
	end)
end

local function closeTradeUi()
	local hadTrade = currentTradeData ~= nil
	currentTradeData = nil
	localAcceptReadyAt = 0
	TradeFrame.Visible = false
	-- Always tell the server to clean up, so ActiveTrades can never get stuck
	if hadTrade then
		TradeRemote:FireServer("CANCEL_TRADE")
	end
end

local function bindTradeButtons()
	local ui = resolveTradeUi()
	if not ui then
		return
	end

	if ui.AcceptButton and not ui.AcceptButton:GetAttribute("TradeBound") then
		ui.AcceptButton:SetAttribute("TradeBound", true)
		ui.AcceptButton.MouseButton1Click:Connect(function()
			if not currentTradeData then
				return
			end

			local localSide, otherSide = splitTradeData(currentTradeData)
			if not localSide or not otherSide then
				return
			end

			local localLocked = localSide.Locked == true
			local otherLocked = otherSide.Locked == true
			local bothLocked = localLocked and otherLocked
			local localAccepted = localSide.Accepted == true

			if not localLocked then
				TradeRemote:FireServer("LOCK_TRADE", true)
				return
			end

			if bothLocked then
				if localAccepted then
					TradeRemote:FireServer("ACCEPT_TRADE", false)
					return
				end

				if tick() < localAcceptReadyAt then
					-- Still in countdown, unconfirm instead
					TradeRemote:FireServer("LOCK_TRADE", false)
					return
				end

				TradeRemote:FireServer("ACCEPT_TRADE", true)
				return
			end

			TradeRemote:FireServer("LOCK_TRADE", false)
		end)
	end

	if ui.CancelButton and not ui.CancelButton:GetAttribute("TradeBound") then
		ui.CancelButton:SetAttribute("TradeBound", true)
		ui.CancelButton.MouseButton1Click:Connect(function()
			if not currentTradeData then
				return
			end
			TradeRemote:FireServer("CANCEL_TRADE")
		end)
	end
end

local function removeRequestTemplate(senderUserId: number)
	local template = requestTemplates[senderUserId]
	if template and template.Parent then
		template:Destroy()
	end
	requestTemplates[senderUserId] = nil
end

local function showTradeRequest(tradeData)
	if not tradeData or not tradeData.Sender then
		return
	end

	removeRequestTemplate(tradeData.Sender.UserId)

	layoutorder += 1
	local template = RecieveRequestTemplate:Clone()
	template:WaitForChild("Header").Text = tradeData.Sender.Name .. " has sent you a trade request"
	template.Parent = TradeRequestsFrame
	template.LayoutOrder = layoutorder
	requestTemplates[tradeData.Sender.UserId] = template

	template.Accept.MouseButton1Click:Connect(function()
		TradeRemote:FireServer("ACCEPT_REQUEST")
		removeRequestTemplate(tradeData.Sender.UserId)
	end)

	template.Decline.MouseButton1Click:Connect(function()
		TradeRemote:FireServer("DECLINE_REQUEST")
		removeRequestTemplate(tradeData.Sender.UserId)
	end)
end

local function onTradeEvent(tradeData)
	if not tradeData or type(tradeData.UpdateType) ~= "string" then
		return
	end

	if tradeData.UpdateType == "REQUEST_RECEIVED" then
		showTradeRequest(tradeData)
		return
	end

	currentTradeData = tradeData
	if tradeData.UpdateType == "TRADE_STARTED" then
		localAcceptReadyAt = 0
		for senderUserId in pairs(requestTemplates) do
			removeRequestTemplate(senderUserId)
		end
	end

	-- When both players just locked, start a local 5-second countdown (only once)
	if tradeData.State == "LOCKED" and localAcceptReadyAt == 0 then
		localAcceptReadyAt = tick() + ACCEPT_DELAY
	elseif tradeData.State ~= "LOCKED" then
		localAcceptReadyAt = 0
	end

	bindTradeButtons()
	refreshTradeUi()
	ensureUiRefreshLoop()

	if tradeData.UpdateType == "TRADE_COMPLETED" then
		task.delay(1.25, function()
			closeTradeUi()
		end)
		return
	end

	if tradeData.UpdateType == "TRADE_CANCELLED" or tradeData.UpdateType == "TRADE_FAILED" then
		closeTradeUi()
	end
end

local function onActionResult(payload)
	if not payload then
		return
	end

	if payload.success ~= true then
		warn("Trade action failed:", payload.action, payload.error)
	end

	if payload.action == "CANCEL_TRADE" and payload.success == true then
		closeTradeUi()
	end
end

TradeRemote.OnClientEvent:Connect(function(eventType, payload)
	if eventType == "TRADE_EVENT" then
		onTradeEvent(payload)
		return
	end

	if eventType == "ACTION_RESULT" then
		onActionResult(payload)
	end
end)

bindTradeButtons()

return {}