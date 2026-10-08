-- Executes production modules with deterministic Roblox services and async saves.
local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(fn)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, { fn = fn, connection = connection })
		return connection
	end
	function s:Fire(...)
		for _, listener in ipairs(table.clone(listeners)) do
			if listener.connection.Connected then listener.fn(...) end
		end
	end
	function s:Once(fn)
		local connection
		connection = self:Connect(function(...) connection:Disconnect(); fn(...) end)
		return connection
	end
	function s:Count()
		local total = 0; for _, listener in ipairs(listeners) do if listener.connection.Connected then total += 1 end end; return total
	end
	return s
end

local methods = {}
local objectMeta = {}
function objectMeta.__index(self, key)
	if methods[key] then return methods[key] end
	if self._props[key] ~= nil then return self._props[key] end
	if key == "Position" and self._props.CFrame and self._props.CFrame.Position then return self._props.CFrame.Position end
	if self._signals[key] then return self._signals[key] end
	for _, child in ipairs(self._children) do if child.Name == key then return child end end
	return nil
end
function objectMeta.__newindex(self, key, value)
	local old = self._props[key]
	if old == value then return end
	if key == "Parent" then
		if old then
			local index = table.find(old._children, self)
			if index then table.remove(old._children, index) end
		end
		self._props.Parent = value
		if old then old.ChildRemoved:Fire(self) end
		if value then table.insert(value._children, self); value.ChildAdded:Fire(self) end
	else
		self._props[key] = value
		if key == "CFrame" then self._props.Position = nil end
		if key == "Value" then self.Changed:Fire(value) end
	end
	if self._signals["Property_" .. key] then self._signals["Property_" .. key]:Fire() end
end
local function object(class, name, parent)
	local result = setmetatable({ _props = { ClassName = class, Name = name or class }, _children = {}, _attributes = {}, _signals = {}, _attributeSignals = {} }, objectMeta)
	for _, key in ipairs({ "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Changed", "CharacterAdded", "CharacterRemoving", "PlayerAdded", "PlayerRemoving", "OnServerEvent", "OnClientEvent", "Died", "Activated", "Touched", "AncestryChanged", "Destroying", "InputBegan", "Running", "StateChanged", "Ended" }) do result._signals[key] = signal() end
	result.Parent = parent
	return result
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance" or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
		or (class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton"))
		or (class == "GuiObject" and (self.ClassName == "Frame" or self.ClassName == "ImageLabel"))
end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
	local out = {}
	for _, child in ipairs(self._children) do table.insert(out, child); for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end end
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, child in ipairs(self._children) do if child.Name == name then return child end end
	if recursive then for _, child in ipairs(self._children) do local found = child:FindFirstChild(name, true); if found then return found end end end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self._children) do if child:IsA(class) then return child end end
	return nil
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:SetAttribute(name, value)
	local old = self._attributes[name]
	self._attributes[name] = value
	if old ~= value and self._attributeSignals[name] then self._attributeSignals[name]:Fire() end
end
function methods:GetAttributeChangedSignal(name)
	self._attributeSignals[name] = self._attributeSignals[name] or signal()
	return self._attributeSignals[name]
end
function methods:GetPropertyChangedSignal(name)
	self._signals["Property_" .. name] = self._signals["Property_" .. name] or signal()
	return self._signals["Property_" .. name]
end
function methods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do if parent == ancestor then return true end; parent = parent.Parent end
	return false
end
function methods:Destroy()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
	self.Destroyed = true
end
function methods:Clone()
	local copy = object(self.ClassName, self.Name)
	for key, value in pairs(self._props) do if key ~= "Parent" then copy[key] = value end end
	for key, value in pairs(self._attributes) do copy:SetAttribute(key, value) end
	for _, child in ipairs(self._children) do child:Clone().Parent = copy end
	return copy
end
function methods:EquipTool(tool) tool.Parent = self.Parent end
function methods:FireClient(...) self.LastClientArgs = { ... }; self.ClientCalls = (self.ClientCalls or 0) + 1 end
function methods:FireServer(...)
	self.LastServerArgs = { ... }; self.ServerCalls = (self.ServerCalls or 0) + 1
	if self.OnSend then self.OnSend(...) end
end
function methods:FireAllClients(...)
	self.LastClientArgs = { ... }; self.ClientCalls = (self.ClientCalls or 0) + 1
	if self.OnFireAll then self.OnFireAll(...) end
end
function methods:Kick(message) self.KickMessage = message end
function methods:PivotTo(frame) self.LastPivot = frame end
function methods:GetMouse() return self.Mouse end
local function child(parent, class, name, value)
	local item = object(class, name, parent)
	if value ~= nil then item.Value = value end
	return item
end
local function copyTable(value)
	if type(value) ~= "table" then return value end
	local out = {}; for k, v in pairs(value) do out[k] = copyTable(v) end; return out
end
local function equal(actual, expected, context)
	assert(actual == expected, (context or "Unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn)
		if not ok then error(name .. ": " .. tostring(err), 0) end
		passed += 1
		print("PASS " .. name)
	end
	local function fixture()
		local f = { time = 100, modules = {}, delayed = {}, background = {}, notifications = 0 }
		f.Players = object("Players", "Players")
		function f.Players:GetPlayers() return self:GetChildren() end
		function f.Players:GetPlayerByUserId(id) for _, player in ipairs(self:GetPlayers()) do if player.UserId == id then return player end end end
		f.RS, f.SSS, f.SS = object("Folder", "ReplicatedStorage"), object("Folder", "ServerScriptService"), object("Folder", "ServerStorage")
		f.Marketplace = {}
		f.DataStore = { GetDataStore = function() return { GetAsync = function() return nil end } end }
		f.game = { GetService = function(_, name)
			local services = { Players = f.Players, ReplicatedStorage = f.RS, ServerScriptService = f.SSS, ServerStorage = f.SS, MarketplaceService = f.Marketplace, DataStoreService = f.DataStore }
			assert(services[name], "Unknown service " .. name); return services[name]
		end, BindToClose = function(_, fn) f.close = fn end }
		f.workspace = { GetServerTimeNow = function() return f.time end }
		f.env = { game = f.game, workspace = f.workspace, Instance = { new = object },
			typeof = function(v) return getmetatable(v) == objectMeta and "Instance" or type(v) end,
			require = function(mod) assert(f.modules[mod], "Unregistered module " .. tostring(mod and mod.Name)); return f.modules[mod] end,
			os = { clock = function() return f.time end, time = function() return 1700000000 end, date = os.date },
			task = { spawn = function(fn, ...) fn(...) end, delay = function(delay, fn) table.insert(f.delayed, { delay = delay, at = f.time + delay, fn = fn }) end,
				wait = function(delay) f.time += delay or 0.1; if f.onWait then f.onWait() end end },
			Enum = { ProductPurchaseDecision = { PurchaseGranted = "Granted", NotProcessedYet = "Retry" } },
		}
		f.modulesFolder = child(f.RS, "Folder", "Modules")
		f.modules[child(f.modulesFolder, "ModuleScript", "RagdollQuery")] = {Exclude = function(ignore) return ignore end, GetFolder = function() return nil end}
		f.remotes = child(f.RS, "Folder", "Remotes")
		f.server = child(f.SSS, "Folder", "server")
		f.gameFolder = child(f.server, "Folder", "Game")
		f.combatFolder = child(f.server, "Folder", "CombatHandler")
		f.dataFolder = child(f.server, "Folder", "DataStore")
		f.servicesFolder = child(f.server, "Folder", "ServicesHandler")
		local notification = child(f.gameFolder, "ModuleScript", "SendNotification")
		f.modules[notification] = { SendNotification = function() f.notifications += 1 end }
		function f:load(name, parent, moduleName)
			local mod = child(parent, "ModuleScript", moduleName or name)
			self.env.script = mod
			local result = load(name, self.env)
			self.modules[mod] = result
			return result
		end
		function f:createPlayer(id)
			local player = object("Player", "Player" .. id, self.Players)
			player.UserId, player.DisplayName = id, player.Name
			child(player, "Backpack", "Backpack")
			child(player, "Folder", "leaderstats")
			child(player.leaderstats, "IntValue", "Cash", 0)
			child(player.leaderstats, "Folder", "Inventory")
			player:SetAttribute("DataReady", true)
			self:character(player)
			return player
		end
		function f:character(player)
			if player.Character then player.CharacterRemoving:Fire(player.Character) end
			local char = object("Model", player.Name .. "Character")
			local humanoid = child(char, "Humanoid", "Humanoid")
			humanoid.Health, humanoid.MaxHealth = 1, 100
			player.Character = char
			player.CharacterAdded:Fire(char)
			return char
		end
		return f
	end

	local function vipFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.prompts, f.reads = 0, 0
		local vip = child(child(f.remotes, "Folder", "ShopRemotes"), "Folder", "VIP")
		f.buy, f.status = child(vip, "RemoteEvent", "BuyVIP"), child(vip, "RemoteEvent", "VIPStatus")
		f.modules[child(f.servicesFolder, "ModuleScript", "VIPService")] = {GetVIPInfoByUserId = function() f.reads += 1; return false, 0 end}
		f.Marketplace.PromptProductPurchaseFinished = signal()
		function f.Marketplace:PromptProductPurchase() f.prompts += 1 end
		f:load("VIPHandler", f.servicesFolder)
		return f
	end
	test("VIP purchase prompts are bounded and recover after cooldown", function()
		local f = vipFixture()
		for _ = 1, 100 do f.buy.OnServerEvent:Fire(f.player, "1_WEEK") end
		equal(f.prompts, 1); f.time += 0.75; f.buy.OnServerEvent:Fire(f.player, "1_MONTH"); equal(f.prompts, 2)
	end)
	test("VIP rejects malformed requests and loading players without backend work", function()
		local f = vipFixture()
		for _, value in ipairs({{}, string.rep("x", 10000), 0/0, math.huge, -1, "wrong"}) do f.buy.OnServerEvent:Fire(f.player, value) end
		equal(f.prompts, 0); f.player:SetAttribute("DataReady", false)
		f.buy.OnServerEvent:Fire(f.player, "1_WEEK"); equal(f.prompts, 0)
	end)
	test("VIP status spam is bounded and disconnect clears owned listeners", function()
		local f = vipFixture(); local baseline = f.reads
		for _ = 1, 100 do f.status.OnServerEvent:Fire(f.player, "REQUEST_STATUS") end
		equal(f.reads, baseline + 1); f.time += 1
		f.status.OnServerEvent:Fire(f.player, "REQUEST_STATUS"); equal(f.reads, baseline + 2)
		f.Players.PlayerRemoving:Fire(f.player); equal(f.player:GetAttributeChangedSignal("DataReady"):Count(), 0)
	end)
	test("failed VIP persistence cannot grant attributes or replace verified cached expiry", function()
		local f = fixture(); local player = f:createPlayer(1)
		f.DataStore.GetDataStore = function() return {UpdateAsync = function() error("backend unavailable") end} end
		local vip = load("VIPService", f.env)
		vip.ApplyToPlayer(player, 1700000100)
		equal(vip.SetVIPExpiry(1, 1700001000), false)
		equal(player:GetAttribute("VIPExpiresAt"), 1700000100); equal(vip.GetVIPExpiry(1), 1700000100)
		vip.SetCachedExpiry(1, 0/0); equal(vip.GetVIPExpiry(1), 0)
		vip.SetCachedExpiry(1, math.huge); equal(vip.GetVIPExpiry(1), 0)
	end)

	local function adminFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.admin = child(f.server, "Folder", "Admin"); f.executed, f.warnings = 0, 0
		f.remote = child(child(f.remotes, "Folder", "Admin"), "RemoteEvent", "AdminRemote")
		f.env.warn = function() f.warnings += 1 end
		f.modules[child(f.admin, "ModuleScript", "Commands")] = {
			CheckAdmin = function(id) return id == 1 end,
			Game = {Commands = {Set = function(...) f.executed += 1; f.args = table.pack(...) end}},
		}
		f:load("Admin", f.admin); return f
	end
	test("unauthorized admin packets cannot execute or amplify server logs", function()
		local f = adminFixture(); local stranger = f:createPlayer(2)
		for _ = 1, 100 do f.remote.OnServerEvent:Fire(stranger, "Game", "Set", string.rep("x", 10000)) end
		equal(f.executed, 0); equal(f.warnings, 0)
	end)
	test("admin commands bound requests and preserve optional nil arguments", function()
		local f = adminFixture()
		for _ = 1, 100 do f.remote.OnServerEvent:Fire(f.player, "Game", "Set", 1, nil, "ok") end
		equal(f.executed, 1); equal(f.args.n, 4); equal(f.args[4], "ok")
		f.time += 0.25; f.remote.OnServerEvent:Fire(f.player, "Game", "Set", 2); equal(f.executed, 2)
	end)
	test("admin argument validation covers holes, oversized packets and nonfinite numbers", function()
		local f = adminFixture()
		for _, value in ipairs({0/0, math.huge, -math.huge, {}, string.rep("x", 257)}) do
			f.time += 1; f.remote.OnServerEvent:Fire(f.player, "Game", "Set", nil, value)
		end
		f.time += 1; f.remote.OnServerEvent:Fire(f.player, "Game", "Set", 1,2,3,4,5,6,7,8,9)
		equal(f.executed, 0)
	end)

	local function tradesFixture()
		local f = fixture(); f.player, f.other = f:createPlayer(1), f:createPlayer(2)
		f.folder = child(f.server, "Folder", "Trading"); f.remote = child(child(f.remotes, "Folder", "Trading"), "RemoteEvent", "TradeUpdate")
		f.calls = 0
		f.manager = {
			RegisterCancelCallback = function() end,
			GetPendingRequest = function() return nil end,
			AddItemToTrade = function() f.calls += 1; return true end,
			RemoveItemFromTrade = function() f.calls += 1; return true end,
			GetTradeSession = function() return nil end,
		}
		f.modules[child(f.folder, "ModuleScript", "TradeManager")] = f.manager
		f.modules[child(f.modulesFolder, "ModuleScript", "CalculateLevel")] = {GetLevel = function() return 10 end}
		f.handler = f:load("Trades", f.folder, "TradeRequestsHandler"); f.handler.Init(); f.handler.Init(); return f
	end
	test("trade remote initialization is idempotent and unknown actions are silent", function()
		local f = tradesFixture(); equal(f.remote.OnServerEvent:Count(), 1)
		for _ = 1, 100 do f.remote.OnServerEvent:Fire(f.player, string.rep("x", 10000)) end
		equal(f.remote.ClientCalls, nil)
	end)
	test("trade items reject excessive strings, nonfinite values and untrusted types", function()
		local f = tradesFixture()
		for _, amount in ipairs({0/0, math.huge, -math.huge, -1, 0, 1.5, 2147483648}) do
			f.handler.OnAddItem(f.player, "Inventory", "Knife", amount)
			f.handler.OnRemoveItem(f.player, "Knife", amount)
		end
		f.handler.OnAddItem(f.player, "Other", "Knife", 1)
		f.handler.OnAddItem(f.player, "Inventory", string.rep("x", 65), 1)
		f.handler.OnRemoveItem(f.player, string.rep("x", 65))
		equal(f.calls, 0); f.handler.OnAddItem(f.player, "Inventory", "Knife", 1); equal(f.calls, 1)
	end)
	test("trade target IDs reject NaN, infinity, fractions and overflow before player lookup", function()
		local f = tradesFixture(); local lookups = 0
		function f.Players:GetPlayerByUserId() lookups += 1 end
		for _, id in ipairs({0/0, math.huge, -math.huge, 0, -1, 1.5, 9007199254740992}) do f.handler.OnSendRequest(f.player, id) end
		equal(lookups, 0)
	end)

	local function inventoryItem(folder, name, quantity, kind)
		local item = child(folder, kind or "StringValue", name, "server-value")
		if quantity ~= nil then child(item, "IntValue", "Quantity", quantity) end
		child(item, "StringValue", "Rarity", "Rare"); child(item, "StringValue", "Image", "asset")
		return item
	end
	local function transactionFixture()
		local f = fixture(); f.p1, f.p2 = f:createPlayer(1), f:createPlayer(2)
		child(f.p1.leaderstats, "Folder", "Emotes"); child(f.p2.leaderstats, "Folder", "Emotes")
		f.a, f.b = inventoryItem(f.p1.leaderstats.Inventory, "A", 3), inventoryItem(f.p2.leaderstats.Inventory, "B", 2)
		f.validator = load("TradeValidator", f.env)
		f.session = {
			Player1 = f.p1, Player2 = f.p2, State = "LOCKED",
			Player1Items = {{Type = "Inventory", Name = "A", Quantity = 2, Rarity = "Rare", Image = "asset"}},
			Player2Items = {{Type = "Inventory", Name = "B", Quantity = 1, Rarity = "Rare", Image = "asset"}},
			BothPlayersLocked = function() return true end,
		}
		return f
	end
	test("trade transaction conserves both inventories and rejects repeated execution", function()
		local f = transactionFixture(); equal(f.validator.ExecuteTrade(f.session), true)
		equal(f.p1.leaderstats.Inventory.A.Quantity.Value, 1); equal(f.p1.leaderstats.Inventory.B.Quantity.Value, 1)
		equal(f.p2.leaderstats.Inventory.A.Quantity.Value, 2); equal(f.p2.leaderstats.Inventory.B.Quantity.Value, 1)
		equal(f.validator.ExecuteTrade(f.session), false); equal(f.p2.leaderstats.Inventory.A.Quantity.Value, 2)
	end)
	test("failure preparing the second destination restores no incoming grant on either side", function()
		local f = transactionFixture(); local invalid = inventoryItem(f.p2.leaderstats.Inventory, "A", nil, "Folder")
		equal(f.validator.ExecuteTrade(f.session), false)
		equal(f.p1.leaderstats.Inventory.A, f.a); equal(f.a.Quantity.Value, 3)
		equal(f.p1.leaderstats.Inventory.B, nil); equal(f.p2.leaderstats.Inventory.B, f.b); equal(f.b.Quantity.Value, 2)
		equal(f.p2.leaderstats.Inventory.A, invalid)
	end)
	test("trade checks destination quantity overflow before changing either player", function()
		local f = transactionFixture(); local a = inventoryItem(f.p2.leaderstats.Inventory, "A", 2147483647)
		equal(f.validator.ExecuteTrade(f.session), false); equal(a.Quantity.Value, 2147483647)
		equal(f.a.Quantity.Value, 3); equal(f.b.Quantity.Value, 2)
	end)
	test("trade preparation failure disposes staged clones and preserves originals", function()
		local f = transactionFixture(); local original = f.env.Instance.new
		f.env.Instance.new = function(class) if class == "BoolValue" then error("simulated allocation failure") end; return original(class) end
		equal(f.validator.ExecuteTrade(f.session), false)
		equal(f.p1.leaderstats.Inventory.A, f.a); equal(f.p2.leaderstats.Inventory.B, f.b)
		equal(#f.p1.leaderstats.Inventory:GetChildren(), 1); equal(#f.p2.leaderstats.Inventory:GetChildren(), 1)
	end)
	test("legacy items without quantities and duplicate offers conserve the final total", function()
		local f = transactionFixture(); f.a.Quantity:Destroy()
		f.session.Player1Items[1].Quantity = 1; f.session.Player2Items[2] = table.clone(f.session.Player2Items[1])
		equal(f.validator.ExecuteTrade(f.session), true)
		equal(f.p1.leaderstats.Inventory.A, nil); equal(f.p1.leaderstats.Inventory.B.Quantity.Value, 2)
		equal(f.p2.leaderstats.Inventory.A.Quantity.Value, 1); equal(f.p2.leaderstats.Inventory.B, nil)
	end)
	test("an interrupted second-side commit restores originals on both sides", function()
		local f = transactionFixture(); local originalWrite = objectMeta.__newindex; local failed = false
		objectMeta.__newindex = function(self, key, value)
			if not failed and key == "Parent" and value == f.p2.leaderstats.Inventory and self.Name == "A" then
				failed = true; error("simulated second inventory failure")
			end
			return originalWrite(self, key, value)
		end
		local ok, result = pcall(f.validator.ExecuteTrade, f.session)
		objectMeta.__newindex = originalWrite
		assert(ok); equal(result, false); equal(failed, true)
		equal(f.p1.leaderstats.Inventory.A, f.a); equal(f.p2.leaderstats.Inventory.B, f.b)
		equal(f.p1.leaderstats.Inventory.B, nil); equal(f.p2.leaderstats.Inventory.A, nil)
		equal(f.a.Quantity.Value, 3); equal(f.b.Quantity.Value, 2)
	end)
	test("malformed offers and unconfirmed sessions cannot mutate inventory", function()
		local f = transactionFixture(); f.session.Player1Items[1].Quantity = 0/0
		equal(f.validator.ExecuteTrade(f.session), false); equal(f.a.Quantity.Value, 3)
		f.session.Player1Items[1].Quantity = 1; f.session.BothPlayersLocked = function() return false end
		equal(f.validator.ExecuteTrade(f.session), false); equal(f.b.Quantity.Value, 2)
	end)

	test("trade manager honors disabled settings and expires requests before timer callbacks", function()
		local f = fixture(); local p1, p2 = f:createPlayer(1), f:createPlayer(2)
		local folder = child(f.server, "Folder", "Trading"); local service = f.game.GetService
		f.game.GetService = function(self, name) if name == "HttpService" then return {GenerateGUID = function() return "trade-id" end} end; return service(self, name) end
		f:load("TradeSession", folder); f:load("TradeValidator", folder)
		local manager = f:load("TradeManager", folder)
		local enabled = child(child(p2.leaderstats, "Folder", "Settings"), "BoolValue", "Trades", false)
		equal(manager.SendRequest(p1, p2), false)
		enabled.Value = true; equal(manager.SendRequest(p1, p2), true)
		f.time += 15; equal(manager.AcceptRequest(p2), false)
		equal(manager.SendRequest(p1, p2), true)
		enabled.Value = false; equal(manager.AcceptRequest(p2), false)
	end)

	test("leaderboard changes from many players coalesce into one global snapshot", function()
		local f = fixture(); local p1, p2 = f:createPlayer(1), f:createPlayer(2)
		for _, p in ipairs({p1,p2}) do child(p.leaderstats, "IntValue", "XP", 100); child(p.leaderstats, "IntValue", "Kills", 1) end
		f.modules[child(f.modulesFolder, "ModuleScript", "DataConfig")] = {GetLeaderboardScope = function() return "test" end}
		f.modules[child(f.modulesFolder, "ModuleScript", "CalculateLevel")] = {GetLevel = function(xp) return xp/100 end}
		f.DataStore.GetOrderedDataStore = function() return {SetAsync = function() end} end
		local remote = child(child(f.remotes, "Folder", "Leaderboards"), "RemoteEvent", "RequestLeaderboards")
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.task.defer = function(fn) fn() end
		local boards = f:load("Leaderboards", f.dataFolder, "LeaderboardsHandler")
		local initial = remote.ClientCalls
		for i = 1, 30 do p1.leaderstats.Cash.Value = i; p2.leaderstats.Kills.Value = i end
		equal(remote.ClientCalls, initial); equal(#f.delayed, 1)
		f.time += 0.25; f.delayed[1].fn(); equal(remote.ClientCalls, initial + 1)
		local gold = remote.LastClientArgs[1].Gold; local found
		for _, row in ipairs(gold) do if row.UserId == 1 then found = row.Value end end
		equal(found, 30)
	end)

	local function profileFixture(info)
		local f = fixture(); f.player = f:createPlayer(1)
		f.player:SetAttribute("DataReady", true)
		local folder = child(f.remotes, "Folder", "ProfileHandler")
		f.request, f.response = child(folder, "RemoteEvent", "RequestViewProfile"), child(folder, "RemoteEvent", "ViewProfileClient")
		f.modules[child(f.servicesFolder, "ModuleScript", "GetPlayerInfo")] = info
		f.modules[child(f.gameFolder, "ModuleScript", "RoundHandler")] = {}
		f:load("ProfileView", f.servicesFolder, "ProfileViewHandler"); return f
	end
	test("offline profile lookup has at most one yielding request per player", function()
		local reads = 0
		local f = profileFixture({AllInfo = function(id) reads += 1; coroutine.yield(); return {UserId=id} end, Inventory = function() return {} end})
		local running = coroutine.create(function() f.request.OnServerEvent:Fire(f.player, 2) end)
		assert(coroutine.resume(running)); f.time += 5; f.request.OnServerEvent:Fire(f.player, 3)
		equal(reads, 1); assert(coroutine.resume(running)); equal(f.response.ClientCalls, 1)
	end)
	test("failed profile lookup releases the guard; departed players receive no stale response", function()
		local fails = true
		local f = profileFixture({AllInfo = function() if fails then error("offline unavailable") end; return {} end, Inventory = function() return {} end})
		f.request.OnServerEvent:Fire(f.player, 2); equal(f.response.ClientCalls, nil)
		f.time += 1; fails = false; f.request.OnServerEvent:Fire(f.player, 2); equal(f.response.ClientCalls, 1)
		f.player.Parent = nil; f.time += 1; f.request.OnServerEvent:Fire(f.player, 2); equal(f.response.ClientCalls, 1)
	end)
	test("profile requests reject malformed IDs and loading players before any backend read", function()
		local reads=0; local f=profileFixture({AllInfo=function() reads+=1; return {} end, Inventory=function() return {} end})
		for _,id in ipairs({{},"2",0,-1,.5,0/0,math.huge,-math.huge,9007199254740992}) do
			f.request.OnServerEvent:Fire(f.player,id)
		end
		f.player:SetAttribute("DataReady",false); f.request.OnServerEvent:Fire(f.player,2); equal(reads,0)
	end)
	test("random offline IDs have a shared server budget and a bounded concurrent read count", function()
		local reads=0; local f=profileFixture({AllInfo=function(id) reads+=1; coroutine.yield(); return {UserId=id} end, Inventory=function() return {} end})
		local threads={}
		for id=1,20 do
			local player=id==1 and f.player or f:createPlayer(id); player:SetAttribute("DataReady",true)
			local thread=coroutine.create(function() f.request.OnServerEvent:Fire(player,1000+id) end)
			assert(coroutine.resume(thread)); if coroutine.status(thread)=="suspended" then table.insert(threads,thread) end
		end
		equal(reads,2); for _,thread in ipairs(threads) do assert(coroutine.resume(thread)) end
		-- Completing slow work does not create new tokens or a backlog.
		for id=21,30 do
			local p=f:createPlayer(id); p:SetAttribute("DataReady",true)
			local thread=coroutine.create(function() f.request.OnServerEvent:Fire(p,1000+id) end)
			assert(coroutine.resume(thread)); if coroutine.status(thread)=="suspended" then assert(coroutine.resume(thread)) end
		end
		equal(reads,4)
	end)
	test("offline profile cache coalesces repeat IDs and expires without hiding live profiles", function()
		local reads=0; local f=profileFixture({AllInfo=function(id) reads+=1; return {UserId=id} end, Inventory=function() return {} end})
		f.request.OnServerEvent:Fire(f.player,99); f.time+=1; f.request.OnServerEvent:Fire(f.player,99); equal(reads,1)
		f.time+=31; f.request.OnServerEvent:Fire(f.player,99); equal(reads,2)
		local target=f:createPlayer(99); target:SetAttribute("DataReady",true)
		f.time+=1; f.request.OnServerEvent:Fire(f.player,99); equal(reads,3)
	end)
	test("a yielding admin command cannot accumulate overlapping command executions", function()
		local calls=0; local f=adminFixture()
		f.modules[f.admin.Commands].Game.Commands.Set=function() calls+=1; coroutine.yield() end
		local thread=coroutine.create(function() f.remote.OnServerEvent:Fire(f.player,"Game","Set") end)
		assert(coroutine.resume(thread)); f.time+=1; f.remote.OnServerEvent:Fire(f.player,"Game","Set"); equal(calls,1)
		assert(coroutine.resume(thread))
	end)
	test("profile remote returns both snapshot sections and retries unavailable data without caching it", function()
		local reads, unavailable = 0, true
		local inventory = {Bowie = {Quantity = 2}}
		local f = profileFixture({
			AllInfo = function(id) reads += 1; return {UserId = id, Unavailable = unavailable}, inventory end,
			Inventory = function() error("Must not make a second profile read") end,
		})
		f.request.OnServerEvent:Fire(f.player, 99)
		equal(f.response.LastClientArgs[3], inventory)
		f.time += 1; unavailable = false; f.request.OnServerEvent:Fire(f.player, 99); equal(reads, 2)
		f.time += 1; f.request.OnServerEvent:Fire(f.player, 99); equal(reads, 2)
		equal(f.response.LastClientArgs[3].Bowie.Quantity, 2)
	end)
	print(string.format("Passed %d services/security checks", passed))
end
