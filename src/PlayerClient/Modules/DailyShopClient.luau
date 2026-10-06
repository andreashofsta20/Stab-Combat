-- Uses only the five authored SmallItemTemplate/LargeItemTemplate clones.
-- Prepare one card per frame, cache its controls and update it in place.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Modules.DailyShopConfig)
local Catalog = require(RS.Modules.DailyShopCatalog)
local Levels = require(RS.Modules.CalculateLevel)
local Abbreviate = require(RS.Modules.Abbreviate)
local RarityColors = require(RS.Modules.RarityColor)
local Client = {}

local function textObject(item)
	return item and (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox"))
end
local function find(root, names, class)
	for _, name in ipairs(names) do
		local item = root:FindFirstChild(name, true)
		if item and (not class or item:IsA(class)) then return item end
	end
end
local function write(item, property, value)
	if item and item[property] ~= value then item[property] = value end
end
local function path(template, item)
	local names = {}
	while item and item ~= template do table.insert(names, 1, item.Name); item = item.Parent end
	assert(item == template, "Daily shop field must be inside its template")
	return names
end
local function at(root, names)
	for _, name in ipairs(names) do root = root:FindFirstChild(name); if not root then return end end
	return root
end

function Client.New(player, frame, remote, shopFrame, layout, assets, backgrounds, header)
	assert(#layout == 5, "Daily shop needs exactly three small and two large slots")
	local dedicated = type(remote) == "table" and remote.Request ~= nil
	local requestRemote = dedicated and remote.Request or remote
	local purchaseRemote = dedicated and remote.Purchase or remote
	local views, schemas, connections, statConnections, quantityConnections = {}, {}, {}, {}, {}
	for _, slot in ipairs(layout) do
		assert(slot.Parent and slot.Template and slot.Template:IsA("GuiObject"), "Missing authored daily shop template/parent")
		if not schemas[slot.Template] then
			local schema = {}
			for _, name in ipairs({"Owned", "Image", "Name", "Price"}) do
				schema[name] = path(slot.Template, assert(slot.Fields[name], "Missing daily shop " .. name .. " field"))
			end
			assert(textObject(slot.Fields.Name) and textObject(slot.Fields.Price), "Daily ProductName and Price/Text must be text controls")
			local button = slot.Template:IsA("GuiButton") and slot.Template or find(slot.Template, Config.UI.BuyNames, "GuiButton")
			local itemPrice = slot.Template:FindFirstChild("ItemPrice")
			if not button and itemPrice and itemPrice:IsA("GuiButton") then button = itemPrice end
			if not button and slot.Fields.Price:IsA("GuiButton") then button = slot.Fields.Price end
			if not button and slot.Fields.Image:IsA("GuiButton") then button = slot.Fields.Image end
			schema.Button = path(slot.Template, assert(button, "Daily item template needs its authored purchase button"))
			schemas[slot.Template] = schema
		end
	end
	local timer = find(frame, Config.UI.TimerNames)
	local status = find(frame, Config.UI.StatusNames)
	if not textObject(timer) then timer = nil end
	if not textObject(status) then status = nil end
	local snapshot, offers, pending, pendingAt, nextBuyAt = nil, {}, nil, 0, 0
	local destroyed, needsSnapshot, requestInFlight, activated = false, true, false, false
	local nextRequestAt, requestAt, lastSecond, nextBuild, updateCursor = 0, 0, nil, 1, nil
	local stats, cashValue, xpValue, knives, revolvers
	local statsDirty, quantitiesDirty, cooldownPending = true, true, false
	local buildingCard
	local controller = {Frame = frame}
	local function connect(signal, fn, list)
		local c = signal:Connect(fn); table.insert(list or connections, c); return c
	end
	local function disconnect(list)
		for _, c in ipairs(list) do c:Disconnect() end; table.clear(list)
	end
	local function visible() return frame.Visible and shopFrame.Visible end
	local function now() return Workspace:GetServerTimeNow() end
	local function dirty() updateCursor = 1 end
	local function showStatus(message)
		if status then write(status, "Text", message) end
	end
	local function updateHeader()
		if not textObject(header) then return end
		if not visible() then
			write(header, "Text", "Shop")
			return
		end
		local remaining = snapshot and math.max(0, math.ceil(snapshot.ResetsAt - now()))
		if not remaining then
			write(header, "Text", "Daily Shop")
			return
		end
		write(header, "Text", string.format("Daily Shop (%dH %02dM)",
			math.floor(remaining / 3600), math.floor(remaining % 3600 / 60)))
	end
	local function request()
		if destroyed or not activated or not visible() or requestInFlight or os.clock() < nextRequestAt
			or player:GetAttribute("DataReady") ~= true then return end
		if not needsSnapshot and snapshot and now() < snapshot.ResetsAt then return end
		nextRequestAt = os.clock() + math.max(1.2, Config.RequestCooldown)
		requestInFlight, requestAt = true, os.clock()
		if dedicated then requestRemote:FireServer() else requestRemote:FireServer(Config.Protocol.Request) end
	end
	local function updateView(record)
		local offer = offers[record.Index]
		record.Offer = offer
		if not offer then write(record.Card, "Visible", false); write(record.Button, "Active", false); return end
		local inventory = offer.ItemType == "Knife" and knives or revolvers
		local owned = if inventory then Catalog.Owned(inventory, offer.Name) else offer.Owned
		local level = xpValue and Levels.GetLevel(xpValue.Value) or snapshot.Level or 0
		local cash = cashValue and cashValue.Value or snapshot.Cash or 0
		local state = Catalog.PurchaseState(offer, owned, offer.Purchased, level, cash)
		local stale = now() >= snapshot.ResetsAt
		local enabled = snapshot.Enabled and not needsSnapshot and state == "Available" and not stale and not pending
			and os.clock() >= nextBuyAt and player:GetAttribute("DataReady") == true
		local price = Abbreviate.WithCommas(offer.Price) .. " Gold"
		if state == "LevelLocked" then price = price .. " • Level " .. offer.MinLevel .. "+"
		elseif state == "InsufficientGold" then price = price .. " • Not enough Gold" end
		if stale then price = "Refreshing..."
		elseif pending == offer.Id then price = "Purchasing..." end
		-- AlreadyOwned is the existing authored overlay, including today's purchase.
		write(record.Owned, "Visible", owned == true or offer.Purchased == true)
		write(record.Name, "Text", offer.ProductName)
		write(record.Price, "Text", price)
		write(record.Image, "Image", offer.Image)
		write(record.Image, "Rotation", offer.ItemType == "Revolver" and 0 or record.ImageRotation)
		if backgrounds and record.Card:IsA("ImageButton") and backgrounds[offer.Rarity] then
			write(record.Card, "Image", backgrounds[offer.Rarity])
		end
		write(record.Button, "Active", enabled == true)
		write(record.Button, "Selectable", enabled == true)
		write(record.Button, "AutoButtonColor", enabled == true)
		if record.Level then write(record.Level, "Text", offer.MinLevel > 0 and "Level " .. offer.MinLevel .. "+" or "All levels") end
		if record.Rarity then
			if textObject(record.Rarity) then write(record.Rarity, "Text", offer.Rarity)
			elseif record.Rarity:IsA("ImageLabel") or record.Rarity:IsA("ImageButton") then
				write(record.Rarity, "Image", RarityColors[offer.Rarity].Image)
			end
		end
		write(record.Card, "Visible", true)
	end
	local function build(index)
		local slot = layout[index]
		local card = slot.Template:Clone()
		buildingCard = card
		card.Name, card.Position, card.LayoutOrder, card.Visible = "DailyShopSlot" .. index, slot.Position, index, false
		if slot.AnchorPoint then card.AnchorPoint = slot.AnchorPoint end
		card:SetAttribute("DailyShopCard", true)
		local record = {Card = card, Index = index}
		for name, names in pairs(schemas[slot.Template]) do record[name] = assert(at(card, names), "Daily shop template field missing: " .. name) end
		assert(textObject(record.Name) and textObject(record.Price), "Daily ProductName and Price/Text must be text controls")
		record.ImageRotation = record.Image.Rotation
		record.Level, record.Rarity = find(card, Config.UI.LevelLabels), card:FindFirstChild("Rarity", true)
		write(record.Button, "Active", false)
		connect(record.Button.Activated, function()
			local offer = record.Offer
			if destroyed or not offer or pending or not record.Button.Active or not visible() then return end
			if now() >= snapshot.ResetsAt then needsSnapshot = true; dirty(); request(); return end
			pending, pendingAt = offer.Id, os.clock()
			nextBuyAt, cooldownPending = pendingAt + Config.PurchaseCooldown, true
			showStatus("Purchasing " .. offer.ProductName .. "...")
			-- Disable the five existing purchase buttons immediately; update text later.
			for _, view in ipairs(views) do write(view.Button, "Active", false) end
			dirty()
			if dedicated then purchaseRemote:FireServer(snapshot.RotationId, offer.Id)
			else purchaseRemote:FireServer(Config.Protocol.Buy, snapshot.RotationId, offer.Id) end
		end)
		views[index] = record
		local destination = index <= 3 and layout[1].Parent or layout[4].Parent
		assert(destination and destination ~= frame, "Daily shop card destination must be an Others or Main container")
		card.Parent = destination
		if snapshot then updateView(record) end
		buildingCard = nil
		quantitiesDirty = true
	end
	local function bindStats()
		disconnect(statConnections)
		stats = player:FindFirstChild("leaderstats")
		cashValue, xpValue = stats and stats:FindFirstChild("Cash"), stats and stats:FindFirstChild("XP")
		knives, revolvers = stats and stats:FindFirstChild("Inventory"), stats and stats:FindFirstChild("RevolverInventory")
		if stats then
			local function structureChanged() statsDirty, quantitiesDirty = true, true; dirty() end
			connect(stats.ChildAdded, structureChanged, statConnections)
			connect(stats.ChildRemoved, structureChanged, statConnections)
			for _, value in pairs({Cash = cashValue, XP = xpValue}) do connect(value.Changed, dirty, statConnections) end
			for _, inventory in pairs({Knife = knives, Revolver = revolvers}) do
				local function inventoryChanged() quantitiesDirty = true; dirty() end
				connect(inventory.DescendantAdded, inventoryChanged, statConnections)
				connect(inventory.DescendantRemoving, inventoryChanged, statConnections)
			end
		end
		statsDirty, quantitiesDirty = false, true
	end
	local function bindQuantities()
		disconnect(quantityConnections)
		for _, offer in pairs(offers) do
			local inventory = offer.ItemType == "Knife" and knives or revolvers
			local item = inventory and inventory:FindFirstChild(offer.Name)
			local quantity = item and item:FindFirstChild("Quantity")
			if quantity then connect(quantity.Changed, dirty, quantityConnections) end
		end
		quantitiesDirty = false
	end
	local messages = {
		Success = "Item added to your inventory!", Owned = "You already own this item.",
		Purchased = "You already purchased this item today.", LevelLocked = "Your level is too low for this item.",
		InsufficientGold = "You need more Gold for this item.", Expired = "The daily shop has refreshed.",
		Unavailable = "This item is unavailable.", Loading = "Your inventory is still loading...",
		Disabled = "The daily shop is currently closed.", GrantFailed = "Purchase failed. Your Gold was refunded.",
		Error = "Shop unavailable. Retrying...",
	}
	local function receive(payload)
		if destroyed or not activated or type(payload) ~= "table" or payload.Kind ~= Config.Protocol.Response then return end
		requestInFlight = false
		if payload.Code or not pending then pending = nil end
		showStatus(messages[payload.Code] or "")
		if not payload.Ready then needsSnapshot = true; dirty(); return end
		if type(payload.Offers) ~= "table" or type(payload.ResetsAt) ~= "number" or type(payload.RotationId) ~= "string" then return end
		snapshot, needsSnapshot = payload, false
		table.clear(offers)
		for index, offer in ipairs(payload.Offers) do
			local slot = offer.Slot or index
			if slot >= 1 and slot <= #layout then
				offers[slot] = offer
				if assets then assets.QueueImage(offer.Image) end
			end
		end
		quantitiesDirty = true; dirty()
	end
	connect(requestRemote.OnClientEvent, receive)
	if purchaseRemote ~= requestRemote then connect(purchaseRemote.OnClientEvent, receive) end
	connect(player.ChildAdded, function(child) if child.Name == "leaderstats" then statsDirty = true; dirty() end end)
	connect(player:GetAttributeChangedSignal("DataReady"), function() statsDirty = true; dirty(); request() end)
	local function onVisible()
		if visible() then request() end
	end
	connect(frame:GetPropertyChangedSignal("Visible"), onVisible)
	connect(shopFrame:GetPropertyChangedSignal("Visible"), onVisible)
	connect(RunService.Heartbeat, function()
		if destroyed then return end
		if statsDirty then bindStats() end
		if quantitiesDirty then bindQuantities() end
		-- One clone or populated card per frame, never a burst on opening/reply.
		if nextBuild <= #layout then
			local ok, failure = pcall(build, nextBuild)
			if not ok then
				if buildingCard then buildingCard:Destroy(); buildingCard = nil end
				controller.Destroy()
				warn("[DailyShop] Failed to prepare authored template:", failure)
				return
			end
			nextBuild += 1
		elseif updateCursor then
			local view = views[updateCursor]
			if view then updateView(view) end
			updateCursor = updateCursor < #views and updateCursor + 1 or nil
		end
		if cooldownPending and os.clock() >= nextBuyAt then cooldownPending = false; dirty() end
		if pending and os.clock() - pendingAt >= 8 then
			pending, needsSnapshot = nil, true; showStatus("Checking your purchase..."); dirty()
		end
		if requestInFlight and os.clock() - requestAt >= 8 then requestInFlight = false; needsSnapshot = true end
		local time = now()
		if snapshot and time >= snapshot.ResetsAt and not needsSnapshot then
			needsSnapshot = true
			for _, view in ipairs(views) do write(view.Button, "Active", false) end
			dirty()
		end
		local second = math.floor(time)
		if second == lastSecond then return end; lastSecond = second
		updateHeader()
		if visible() and timer and snapshot then
			local remaining = math.max(0, math.ceil(snapshot.ResetsAt - time))
			write(timer, "Text", string.format("Resets in %02d:%02d:%02d", math.floor(remaining/3600), math.floor(remaining%3600/60), remaining%60))
		end
		-- No traffic before the Daily button is clicked; retries stop while hidden.
		if needsSnapshot then request() end
	end)
	-- Only the Daily menu's explicit activation calls Open. Visibility and data
	-- readiness alone never authorize the first request.
	function controller.Open() activated = true; updateHeader(); request() end
	function controller.Refresh() request() end
	function controller.Destroy()
		if destroyed then return end; destroyed = true
		disconnect(connections); disconnect(statConnections); disconnect(quantityConnections)
		for _, view in ipairs(views) do view.Card:Destroy() end; table.clear(views)
	end
	connect(frame.Destroying, controller.Destroy)
	connect(shopFrame.Destroying, controller.Destroy)
	return controller
end

return Client
