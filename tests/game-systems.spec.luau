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
		or (class == "LayerCollector" and self.ClassName == "ScreenGui")
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

return function(load, testFilter: string?)
	local passed = 0
	local function test(name, fn)
		if testFilter and testFilter ~= "" and not string.find(name, testFilter, 1, true) then return end
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
		f.receiptLedger = {}
		f.DataStore = { GetDataStore = function() return { GetAsync = function() return nil end, UpdateAsync = function(_, key, transform) local value = transform(copyTable(f.receiptLedger[key])); if value ~= nil then f.receiptLedger[key] = copyTable(value) end; return copyTable(value) end } end }
		f.game = { GetService = function(_, name)
			local services = { Players = f.Players, ReplicatedStorage = f.RS, ServerScriptService = f.SSS, ServerStorage = f.SS, MarketplaceService = f.Marketplace, DataStoreService = f.DataStore }
			assert(services[name], "Unknown service " .. name); return services[name]
		end, BindToClose = function(_, fn) f.close = fn end }
		f.workspace = { GetServerTimeNow = function() return f.time end, Raycast = function() return nil end }
		f.env = { game = f.game, workspace = f.workspace, Instance = { new = object },
			typeof = function(v) return getmetatable(v) == objectMeta and "Instance" or type(v) end,
			require = function(mod) assert(f.modules[mod], "Unregistered module " .. tostring(mod and mod.Name)); return f.modules[mod] end,
			os = { clock = function() return f.time end, time = function() return 1700000000 end, date = os.date },
			task = { spawn = function(fn) fn() end, delay = function(delay, fn) table.insert(f.delayed, { delay = delay, at = f.time + delay, fn = fn }) end,
				wait = function(delay) f.time += delay or 0.1; if f.onWait then f.onWait() end end },
			Enum = { ProductPurchaseDecision = { PurchaseGranted = "Granted", NotProcessedYet = "Retry" }, RaycastFilterType = {Exclude = "Exclude"} },
			RaycastParams = {new = function() return {} end},
		}
		f.modulesFolder = child(f.RS, "Folder", "Modules")
		f.modules[child(f.modulesFolder, "ModuleScript", "ZoneConfig")] = load("ZoneConfig", {})
		f.modules[child(f.modulesFolder, "ModuleScript", "RagdollQuery")] = {Exclude = function(ignore) return ignore end, GetFolder = function() return nil end}
		f.remotes = child(f.RS, "Folder", "Remotes")
		f.server = child(f.SSS, "Folder", "server")
		f.gameFolder = child(f.server, "Folder", "Game")
		f.combatFolder = child(f.server, "Folder", "CombatHandler")
		f.dataFolder = child(f.server, "Folder", "DataStore")
		f.servicesFolder = child(f.server, "Folder", "ServicesHandler")
		f.modules[child(f.servicesFolder, "ModuleScript", "ReceiptArchive")] = load("ReceiptArchive", {})
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
	local function foodFixture()
		local f = fixture()
		f.config = f:load("FoodConfig", f.modulesFolder)
		f:load("FoodState", f.combatFolder)
		f.round = { GameActive = true, PlayersInGame = {}, RoundStats = { rewardsApplied = false } }
		f.modules[child(f.gameFolder, "ModuleScript", "MainGame")] = f.round
		f.active = child(f.RS, "BoolValue", "GameActive", true)
		f.template = child(child(f.RS, "Folder", "Food"), "Tool", "Burger")
		f.template.RequiresHandle = true
		child(f.template, "Part", "Handle")
		child(f.template, "Script", "LegacyHealing")
		f.food = f:load("FoodService", f.combatFolder)
		f.player = f:createPlayer(1)
		f.round.PlayersInGame[1] = true
		f.player:SetAttribute("InRound", true)
		f.Players.PlayerAdded:Fire(f.player)
		f.tool = f.food.GetTool(f.player)
		assert(f.tool, "Round must grant a burger")
		f.eat = f.remotes.Food.Eat.OnServerEvent
		return f
	end

	test("burger heals 33, enforces configured cooldown, expires after 3 bites", function()
		local f = foodFixture(); local humanoid = f.player.Character.Humanoid
		f.tool.Parent = f.player.Character
		f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 34); equal(f.player:GetAttribute("FoodUses"), 2)
		local cooldown = f.config.CooldownMs / 1000
		f.time += cooldown - 0.01; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 34)
		f.time += 0.01; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 67)
		f.time += cooldown; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 100)
		equal(f.player:GetAttribute("FoodUses"), 0); equal(f.tool.Parent, nil); equal(f.food.GetTool(f.player), nil)
		f.food.Grant(f.player, f.player.Character); equal(f.food.GetTool(f.player), nil, "Consumed tool must not refill")
	end)
	test("full health consumes no bite; healing never exceeds MaxHealth", function()
		local f = foodFixture(); f.tool.Parent = f.player.Character
		f.player.Character.Humanoid.Health = 100; f.eat:Fire(f.player, f.tool)
		equal(f.player:GetAttribute("FoodUses"), 3)
		f.player.Character.Humanoid.Health = 99; f.eat:Fire(f.player, f.tool)
		equal(f.player.Character.Humanoid.Health, 100); equal(f.player:GetAttribute("FoodUses"), 2)
	end)
	test("backpack, forged tool and another player's requests cannot heal", function()
		local f = foodFixture(); local other = f:createPlayer(2)
		f.eat:Fire(f.player, f.tool)
		f.tool.Parent = f.player.Character
		f.eat:Fire(f.player, f.template:Clone())
		f.eat:Fire(other, f.tool)
		equal(f.player.Character.Humanoid.Health, 1); equal(f.player:GetAttribute("FoodUses"), 3)
	end)
	test("client-edited attributes and extra RPC values cannot change server state", function()
		local f = foodFixture(); f.tool.Parent = f.player.Character
		f.tool:SetAttribute("FoodUses", 999); f.player:SetAttribute("FoodReadyAt", 0)
		f.eat:Fire(f.player, f.tool, 1000, 999)
		equal(f.player.Character.Humanoid.Health, 34); equal(f.player:GetAttribute("FoodUses"), 2)
	end)
	test("inactive, lobby and unready players cannot eat or receive food", function()
		for _, gate in ipairs({ "inactive", "lobby", "unready", "eliminated" }) do
			local f = foodFixture(); f.tool.Parent = f.player.Character
			if gate == "inactive" then f.round.GameActive = false
			elseif gate == "lobby" then child(child(f.player.leaderstats, "Folder", "Settings"), "BoolValue", "LobbyMode", true)
			elseif gate == "unready" then f.player:SetAttribute("DataReady", false)
			else f.round.PlayersInGame[1] = nil end
			f.eat:Fire(f.player, f.tool)
			equal(f.player.Character.Humanoid.Health, 1, gate); equal(f.food.GetTool(f.player), nil, gate)
			equal(f.food.Grant(f.player, f.player.Character), nil, gate)
		end
	end)
	test("FFA death clears food; respawn has 3 fresh bites and rejects old tool", function()
		local f = foodFixture(); f.tool.Parent = f.player.Character
		f.eat:Fire(f.player, f.tool)
		f.player.Character.Humanoid.Health = 0; f.player.Character.Humanoid.Died:Fire()
		equal(f.tool.Parent, nil); equal(f.player:GetAttribute("FoodUses"), 0)
		f:character(f.player)
		local fresh = f.food.GetTool(f.player); assert(fresh and fresh ~= f.tool)
		equal(f.player:GetAttribute("FoodUses"), 3)
		fresh.Parent = f.player.Character; f.time += 2; f.eat:Fire(f.player, f.tool)
		equal(f.player.Character.Humanoid.Health, 1)
	end)
	test("round end and leaving clear food; next round gets a fresh tool", function()
		local f = foodFixture(); f.round.GameActive = false; f.active.Value = false
		equal(f.tool.Parent, nil); equal(f.player:GetAttribute("FoodUses"), 0)
		f.round.RoundStats = { rewardsApplied = false }; f.round.GameActive = true; f.active.Value = true
		local fresh = f.food.GetTool(f.player); assert(fresh and fresh ~= f.tool)
		f.Players.PlayerRemoving:Fire(f.player); equal(fresh.Parent, nil)
	end)
	test("duplicate round notifications preserve remaining bites and cooldown", function()
		local f = foodFixture(); f.tool.Parent = f.player.Character; f.eat:Fire(f.player, f.tool)
		f.player:GetAttributeChangedSignal("InRound"):Fire()
		equal(f.food.GetTool(f.player), f.tool); equal(f.player:GetAttribute("FoodUses"), 2)
		f.eat:Fire(f.player, f.tool); equal(f.player.Character.Humanoid.Health, 34)
	end)
	test("food clone removes legacy scripts and disables physical collisions", function()
		local f = foodFixture(); equal(f.tool:FindFirstChild("LegacyHealing"), nil)
		equal(f.tool.CanBeDropped, false); equal(f.tool.Handle.CanCollide, false); equal(f.tool.Handle.Massless, true)
	end)
	test("RPC spam is bounded by a server bucket and eventually recovers", function()
		local config = load("FoodConfig"); local state = load("FoodState")
		local bucket = { tokens = config.RequestBurst, time = 1 }
		for _ = 1, 3 do equal(state.AllowRequest(bucket, 1, 3, 2), true) end
		equal(state.AllowRequest(bucket, 1, 3, 2), false)
		equal(state.AllowRequest(bucket, 1.49, 3, 2), false)
		equal(state.AllowRequest(bucket, 1.5, 3, 2), true)
	end)
	test("invalid health cannot consume a bite", function()
		local config, state = load("FoodConfig"), load("FoodState")
		for _, health in ipairs({ 0, -1, math.huge, 0 / 0 }) do
			local food = state.New({}, {}, 3)
			equal(state.Eat(food, 1, health, 100, config), nil); equal(food.remaining, 3)
		end
	end)
	test("switching food to a weapon stores the same partially eaten burger", function()
		local f = foodFixture()
		local hotbar = child(f.remotes, "Folder", "HotBar")
		local equip = child(hotbar, "RemoteEvent", "Equip"); child(hotbar, "RemoteEvent", "EquippedClient")
		local knives = child(f.SS, "Folder", "Knives"); child(f.SS, "Folder", "Revolvers")
		child(knives, "Tool", "KnifeA")
		child(f.player.leaderstats, "StringValue", "EquippedKnife", "KnifeA")
		child(child(f.player.leaderstats.Inventory, "Folder", "KnifeA"), "IntValue", "Quantity", 1)
		f:load("Hotbar", f.combatFolder, "HandleHotbar")
		equip.OnServerEvent:Fire(f.player, "Food"); equal(f.tool.Parent, f.player.Character)
		f.eat:Fire(f.player, f.tool); f.time += 0.2
		equip.OnServerEvent:Fire(f.player, "Knife"); equal(f.tool.Parent, f.player.Backpack)
		equal(f.player:GetAttribute("FoodUses"), 2); assert(f.player.Character.KnifeA)
		f.time += 0.2; equip.OnServerEvent:Fire(f.player, "Food")
		equal(f.tool.Parent, f.player.Character); equal(f.player.Character:FindFirstChild("KnifeA"), nil)
		f.time += 0.2; equip.OnServerEvent:Fire(f.player, "Food"); equal(f.tool.Parent, f.player.Backpack)
	end)
	local function foodClientFixture()
		local f = foodFixture()
		f.Players.LocalPlayer = f.player
		local playerGui = child(f.player, "Folder", "PlayerGui")
		f.ui = { TouchEnabled = false, GetFocusedTextBox = function() return f.textBox end }
		f.guiService = { MenuIsOpen = false }
		f.runService = { Heartbeat = signal() }
		local getService = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "UserInputService" then return f.ui elseif name == "GuiService" then return f.guiService elseif name == "RunService" then return f.runService end
			return getService(self, name)
		end
		f.env.Vector2 = { new = function(...) return { ... } end }
		f.env.UDim2 = { new = function(...) return { ... } end, fromScale = function(...) return { ... } end, fromOffset = function(...) return { ... } end }
		f.env.Color3 = { new = function(...) return { ... } end, fromRGB = function(...) return { ... } end }
		f.env.Enum.Font = { GothamBold = "Bold" }
		f:load("FoodClient", f.RS)
		f.hud = playerGui.FoodHUD
		f.label = f.hud:FindFirstChildOfClass("TextLabel")
		return f
	end
	test("equipped food shows remaining bites; unequip hides HUD and removes its ticker", function()
		local f = foodClientFixture(); equal(f.hud.Enabled, false); equal(f.runService.Heartbeat:Count(), 0)
		f.tool.Parent = f.player.Character
		equal(f.hud.Enabled, true); assert(f.label.Text:find("3/3", 1, true)); equal(f.runService.Heartbeat:Count(), 1)
		f.food.Store(f.player, f.tool)
		equal(f.hud.Enabled, false); equal(f.runService.Heartbeat:Count(), 0); equal(f.tool.Activated:Count(), 0)
	end)
	test("food HUD follows server count and cooldown without predicting consumption", function()
		local f = foodClientFixture(); f.tool.Parent = f.player.Character
		f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 1); equal(f.remotes.Food.Eat.LastServerArgs[1], f.tool)
		equal(f.player:GetAttribute("FoodUses"), 3)
		f.eat:Fire(f.player, f.tool)
		assert(f.label.Text:find("2/3", 1, true)); assert(f.label.Text:find("Ready in", 1, true))
		f.time += f.config.CooldownMs / 1000 - 0.01; f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 1)
		f.time += 0.01; f.runService.Heartbeat:Fire(0.1); f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 2)
	end)
	test("food client blocks full health, menus and chat; touch button uses same request", function()
		local f = foodClientFixture(); f.tool.Parent = f.player.Character
		f.player.Character.Humanoid.Health = 100; f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, nil)
		f.player.Character.Humanoid.Health = 1; f.guiService.MenuIsOpen = true; f.tool.Activated:Fire()
		f.guiService.MenuIsOpen = false; f.textBox = {}; f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, nil)
		f.textBox = nil; f.ui.TouchEnabled = true; f.runService.Heartbeat:Fire(0.1)
		local button = f.hud:FindFirstChildOfClass("TextButton"); equal(button.Visible, true)
		button.Activated:Fire(); f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 1, "Touch duplicate suppressed")
	end)
	test("food HUD respawn disconnects old tool and never accumulates tickers", function()
		local f = foodClientFixture(); f.tool.Parent = f.player.Character
		f:character(f.player); equal(f.runService.Heartbeat:Count(), 0); equal(f.tool.Activated:Count(), 0)
		local fresh = f.food.GetTool(f.player); fresh.Parent = f.player.Character
		equal(f.runService.Heartbeat:Count(), 1)
		for _ = 1, 5 do f.food.Store(f.player, fresh); fresh.Parent = f.player.Character end
		equal(f.runService.Heartbeat:Count(), 1); equal(fresh.Activated:Count(), 1)
		f.round.GameActive = false; f.active.Value = false; equal(f.hud.Enabled, false); equal(f.runService.Heartbeat:Count(), 0)
	end)

	local mapVectorMeta = {}
	local function mapVector(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, mapVectorMeta) end
	mapVectorMeta.__sub = function(a, b) return mapVector(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
	mapVectorMeta.__add = function(a, b) return mapVector(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
	mapVectorMeta.__index = function(v, key) if key == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
	local frameMeta = {}
	local function mapFrame(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, Position = mapVector(x,y,z)}, frameMeta) end
	frameMeta.__mul = function(a, b) local result = mapFrame(a.X+b.X, a.Y+b.Y, a.Z+b.Z); result.origin, result.offset = a, b; return result end
	local function mapFixture()
		local f = fixture()
		f.workspace = object("Workspace", "Workspace"); f.env.workspace = f.workspace
		function f.workspace:Raycast() return nil end
		f.game.Players = f.Players
		f.env.CFrame = {new = mapFrame}; f.env.Vector3 = {zero = mapVector(0,0,0), new = mapVector}
		local templates = {}
		for _, name in ipairs({ "MapA", "MapB" }) do
			local template = child(f.SS, "Model", name)
			local spawns = child(child(template, "Folder", "Geometry"), "Folder", "Spawns")
			local spawn = child(spawns, "Part", "1"); spawn.CanQuery, spawn.CFrame = true, f.env.CFrame.new(1, 2, 3)
			templates[name] = { MapFolder = template }
		end
		f.lobby = child(f.workspace, "Model", "IntermissionMap")
		f.other = child(f.workspace, "Model", "UnrelatedScenery")
		f.terrain = child(f.workspace, "Terrain", "Terrain")
		f.legacy = child(f.workspace, "Model", "MapA")
		f.duplicate = child(f.workspace, "Model", "MapA")
		f.nested = child(child(f.workspace, "Folder", "Maps"), "Model", "MapB")
		f.modules[child(f.gameFolder, "ModuleScript", "Maps")] = templates
		local mapConfig = f:load("MapConfig", f.modulesFolder)
		f.mapConfig = mapConfig
		mapConfig.LobbyMap = "MapA"
		mapConfig.MapSwitchDelaySeconds = 1 -- deterministic timing fixture; live config remains editable
		f.maps = f:load("Maps", f.gameFolder, "SpawnMap")
		return f
	end
	test("map startup removes untracked duplicates and nested map copies, preserving lobby", function()
		local f = mapFixture()
		equal(f.legacy.Parent, nil); equal(f.duplicate.Parent, nil); equal(f.nested.Parent, nil)
		equal(f.lobby.Parent, f.workspace); equal(f.other.Parent, f.workspace); equal(f.terrain.Parent, f.workspace)
		equal(f.SS.MapA.Parent, f.SS, "ServerStorage template preserved")
	end)
	test("spawn scorer prefers covered distance and bounds visibility queries",function()
		local f=mapFixture(); local spawns=f.SS.MapA.Geometry.Spawns
		spawns["1"].CFrame=mapFrame(0,0,0)
		child(spawns,"Part","2").CFrame=mapFrame(100,0,0)
		child(spawns,"Part","3").CFrame=mapFrame(120,0,0)
		f.maps.Spawn("MapA")
		local player,enemy=f:createPlayer(1),f:createPlayer(2)
		child(player.Character,"Part","HumanoidRootPart").CFrame=mapFrame(0,0,0)
		enemy:SetAttribute("InRound",true); child(enemy.Character,"Part","HumanoidRootPart").CFrame=mapFrame(30,0,0)
		local calls=0
		function f.workspace:Raycast(origin,direction)
			calls+=1; equal((origin+direction).X,30,"ray must terminate at enemy")
			return origin.X==100 and {Instance={}} or nil
		end
		assert(f.maps.RespawnPlayer(player,"MapA")); equal(player.Character.HumanoidRootPart.Position.X,100)
		assert(calls<=f.mapConfig.SpawnScoring.MaxCandidates)
		assert(f.maps.ScoreSpawn(100,false,false)>f.maps.ScoreSpawn(100,true,false))
		assert(f.maps.ScoreSpawn(100,false,true)<f.maps.ScoreSpawn(100,false,false))
	end)
	test("successive map spawns keep exactly one fresh active gameplay map", function()
		local f = mapFixture()
		equal(f.maps.Spawn("MapA"), true); local first = f.workspace.MapA
		child(f.workspace, "Model", "MapB"); child(f.workspace, "Model", "MapA")
		equal(f.maps.Spawn("MapB"), true); equal(first.Parent, nil); equal(f.workspace:FindFirstChild("MapA"), nil)
		local second = f.workspace.MapB
		equal(f.maps.Spawn("MapB"), true); equal(second.Parent, nil)
		local count = 0; for _, instance in ipairs(f.workspace:GetChildren()) do if instance:GetAttribute("RoundMap") then count += 1 end end
		equal(count, 1); equal(f.lobby.Parent, f.workspace)
	end)
	test("map cleanup removes renamed tracked maps and tagged leftovers but never characters", function()
		local f = mapFixture(); f.maps.Spawn("MapA")
		local map = f.workspace.MapA; map.Name = "RenamedActive"
		local old = child(f.workspace, "Folder", "OldCustomMap"); old:SetAttribute("RoundMap", true)
		local player = f:createPlayer(1); player.Character.Name, player.Character.Parent = "MapA", f.workspace
		f.lobby:SetAttribute("RoundMap", true)
		f.maps.RemoveAllMaps()
		equal(map.Parent, nil); equal(old.Parent, nil); equal(player.Character.Parent, f.workspace)
		equal(f.lobby.Parent, f.workspace)
	end)
	test("invalid map is not published; active map survives a failed replacement", function()
		local f = mapFixture(); f.maps.Spawn("MapA"); local active = f.workspace.MapA
		f.SS.MapB.Geometry.Spawns:Destroy()
		equal(f.maps.Spawn("MapB"), false); equal(f.workspace:FindFirstChild("MapB"), nil)
		equal(active.Parent, f.workspace); equal(f.maps.Spawn("Unknown"), false)
		f.maps.RemoveAllMaps(); equal(active.Parent, nil)
	end)
	test("placements and FFA respawns resolve the active map rather than a stray namesake", function()
		local f = mapFixture(); f.maps.Spawn("MapA")
		local player = f:createPlayer(1); child(player.Character, "Part", "HumanoidRootPart")
		local stray = child(f.workspace, "Model", "MapA")
		equal(f.maps.PlacePlayers("MapA", { player }), 1); assert(player.Character.LastPivot)
		equal(f.maps.RespawnPlayer(player, "MapA"), true); assert(player.Character.HumanoidRootPart.CFrame)
		f.maps.RemoveOtherMapsThen("MapA"); equal(stray.Parent, nil)
		f.maps.RemoveAllMaps(); equal(f.maps.RespawnPlayer(player, "MapA"), false)
	end)
	test("map replacement leaves a one-second gap after removing the old map before publication", function()
		local f = mapFixture(); f.maps.Spawn("MapA"); local old = f.workspace.MapA
		local started, checked = f.time, false
		local player = f:createPlayer(1); child(player.Character, "Part", "HumanoidRootPart")
		f.onWait = function()
			checked = true; equal(old.Parent, nil); equal(f.workspace.MapA, nil); equal(f.workspace.MapB, nil)
			equal(f.maps.RespawnPlayer(player, "MapB"), false)
			equal(f.maps.PlacePlayers("MapB", {player}), 0)
			equal(f.lobby.Parent, f.workspace)
		end
		equal(f.maps.Spawn("MapB"), true); equal(checked, true); equal(f.time - started, 1)
		assert(f.workspace.MapB); equal(f.maps.RespawnPlayer(player, "MapB"), true)
	end)
	test("explicit map removal and later addition respect the remaining configurable gap", function()
		local f = mapFixture(); f.mapConfig.MapSwitchDelaySeconds = 2
		f.maps.RemoveAllMaps(); local removedAt = f.time; f.time += 0.5
		equal(f.maps.Spawn("MapB"), true); equal(f.time - removedAt, 2)
	end)
	test("newer map request cancels an older pending publication without duplicate maps", function()
		local f = mapFixture(); local firstResult, secondResult
		f.env.task.wait = function(seconds) coroutine.yield(seconds) end
		local first = coroutine.create(function() firstResult = f.maps.Spawn("MapA") end)
		local second = coroutine.create(function() secondResult = f.maps.Spawn("MapB") end)
		local start = f.time; local ok, delay = coroutine.resume(first); assert(ok); equal(delay, 1)
		f.time = start + 0.25; ok, delay = coroutine.resume(second); assert(ok); equal(delay, 0.75)
		equal(f.workspace.MapA, nil); equal(f.workspace.MapB, nil)
		f.time = start + 1; assert(coroutine.resume(first)); equal(firstResult, false)
		assert(coroutine.resume(second)); equal(secondResult, true)
		equal(f.workspace.MapA, nil); assert(f.workspace.MapB)
	end)
	test("map cleanup cancels a paused replacement so it cannot reappear afterward", function()
		local f = mapFixture(); local result
		f.env.task.wait = function(seconds) coroutine.yield(seconds) end
		local pending = coroutine.create(function() result = f.maps.Spawn("MapB") end)
		assert(coroutine.resume(pending)); f.maps.RemoveAllMaps(); f.time += 1
		assert(coroutine.resume(pending)); equal(result, false); equal(f.workspace.MapB, nil)
	end)
	test("a stray map during the gap is removed and gets its own settling interval", function()
		local f = mapFixture(); local result
		f.env.task.wait = function(seconds) coroutine.yield(seconds) end
		local pending = coroutine.create(function() result = f.maps.Spawn("MapB") end)
		local start = f.time; assert(coroutine.resume(pending))
		local stray = child(f.workspace, "Model", "MapA"); f.time = start + 1
		local ok, delay = coroutine.resume(pending); assert(ok); equal(delay, 1); equal(stray.Parent, nil)
		equal(f.workspace.MapB, nil); f.time = start + 2
		assert(coroutine.resume(pending)); equal(result, true); assert(f.workspace.MapB)
	end)

	local vector2Meta = { __div = function(v, divisor) return { X = v.X / divisor, Y = v.Y / divisor } end }
	local function cursorFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		f.player.Mouse = { Icon = "original" }
		child(f.player, "Folder", "PlayerGui")
		f.cursorConfig = f:load("CursorConfig", f.modulesFolder)
		f.cursorConfig.Knife.Image, f.cursorConfig.Revolver.Equipped.Image, f.cursorConfig.Revolver.Aiming.Image = "knife", "hip", "aim"
		f.cursorConfig.ShowOnTouch = false
		f.modules[child(f.modulesFolder, "ModuleScript", "KnivesInfo")] = { KnifeA = {} }
		f.modules[child(f.modulesFolder, "ModuleScript", "RevolversInfo")] = { GunA = {} }
		f.clientFolder = child(f.RS, "Folder", "Client")
		local cameraModule = child(child(f.clientFolder, "Folder", "Modules"), "ModuleScript", "RevolverAimCamera")
		f.modules[cameraModule] = { IsAiming = function() return f.aiming == true end }
		f.modules[child(f.clientFolder.Modules, "ModuleScript", "CombatController")] = {GetAimScreenPosition = function()
			if f.knifeAim then return f.knifeAim end
			if f.inputType == f.env.Enum.UserInputType.Touch or f.ui.MouseBehavior == "LockCenter" then return f.workspace.CurrentCamera.ViewportSize / 2 end
			return f.ui:GetMouseLocation()
		end}
		local mouseType, touchType, gamepadType = { Name = "MouseMovement" }, { Name = "Touch" }, { Name = "Gamepad1" }
		f.inputType = mouseType
		f.env.Enum.UserInputType = { MouseMovement = mouseType, Touch = touchType, Gamepad1 = gamepadType }
		f.env.Enum.MouseBehavior = { Default = "Default", LockCenter = "LockCenter" }
		f.env.Enum.RenderPriority = { Camera = { Value = 200 } }
		f.ui = { MouseIconEnabled = true, MouseBehavior = "Default", GetLastInputType = function() return f.inputType end,
			GetFocusedTextBox = function() return f.textBox end, GetMouseLocation = function() return { X = 123, Y = 234 } end }
		f.guiService = { MenuIsOpen = false }
		f.bindings = {}
		local runService = {
			BindToRenderStep = function(_, name, _, fn) f.bindings[name] = fn end,
			UnbindFromRenderStep = function(_, name) f.bindings[name] = nil end,
		}
		local getService = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "UserInputService" then return f.ui elseif name == "GuiService" then return f.guiService elseif name == "RunService" then return runService end
			return getService(self, name)
		end
		f.workspace.CurrentCamera = { ViewportSize = setmetatable({ X = 1000, Y = 600 }, vector2Meta) }
		f.env.Vector2 = { new = function(x, y) return { X = x, Y = y } end }
		f.env.Color3 = {new = function(r, g, b) return {R = r, G = g, B = b} end}
		f.env.UDim2 = { fromOffset = function(x, y) return { X = x, Y = y } end }
		f.visibility = f:load("MouseVisibility", f.modulesFolder, "MouseCursorVisibility")
		f:load("Cursor", f.clientFolder, "HandleWeaponCursor")
		f.cursorGui = f.player.PlayerGui.WeaponCursor
		function f:tick() self.time += 0.1; for _, fn in pairs(self.bindings) do fn() end end
		return f
	end
	test("weapon cursors apply only to equipped knife/revolver and restore for food or no tool", function()
		local f = cursorFixture(); equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		local knife = child(f.player.Character, "Tool", "KnifeA"); equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Cursor.Image, "knife")
		knife.Parent = f.player.Backpack; equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		local burger = child(f.player.Character, "Tool", "Burger"); burger:SetAttribute("FoodItem", "Burger")
		f:tick(); equal(f.player.Mouse.Icon, "original")
		burger:Destroy(); child(f.player.Character, "Tool", "GunA"); equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Cursor.Image, "hip")
	end)
	test("aim cursor appears centered below white-dot HUD without changing mouse lock", function()
		local f = cursorFixture(); child(f.player.Character, "Tool", "GunA")
		equal(f.cursorGui.Enabled, true); equal(f.player.Mouse.Icon, "original"); equal(f.ui.MouseIconEnabled, false)
		f.aiming, f.ui.MouseIconEnabled, f.ui.MouseBehavior = true, false, "LockCenter"; f:tick()
		equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Image, "aim")
		equal(f.cursorGui.Cursor.Position.X, 500); equal(f.cursorGui.Cursor.Position.Y, 300)
		equal(f.cursorGui.DisplayOrder, 19); equal(f.ui.MouseIconEnabled, false); equal(f.ui.MouseBehavior, "LockCenter")
		f.aiming, f.ui.MouseIconEnabled, f.ui.MouseBehavior = false, true, "Default"; f:tick()
		equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Enabled, true); equal(f.ui.MouseIconEnabled, false)
	end)
	test("hidden native knife cursor follows pointer and restores on menu/chat/death", function()
		local f = cursorFixture(); child(f.player.Character, "Tool", "KnifeA"); f.ui.MouseIconEnabled = false; f:tick()
		equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Position.X, 123)
		f.guiService.MenuIsOpen = true; f:tick(); equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Enabled, false)
		f.guiService.MenuIsOpen = false; f.textBox = {}; f:tick(); equal(f.player.Mouse.Icon, "original")
		f.textBox = nil; f:tick(); equal(f.player.Mouse.Icon, "original")
		f.player.Character.Humanoid.Health = 0; f:tick(); equal(f.player.Mouse.Icon, "original")
	end)
	test("weapon cursor respects empty presets, touch setting and respawn cleanup", function()
		local f = cursorFixture(); local gun = child(f.player.Character, "Tool", "GunA")
		f.cursorConfig.Revolver.Equipped.Image = ""; f:tick(); equal(f.player.Mouse.Icon, "original"); equal(f.ui.MouseIconEnabled, false)
		f.cursorConfig.Revolver.Equipped.Image = "hip"; f.inputType = f.env.Enum.UserInputType.Touch; f:tick(); equal(f.cursorGui.Enabled, false)
		f.cursorConfig.ShowOnTouch = true; f:tick(); equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Position.X, 500)
		f:character(f.player); equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		gun.Activated:Fire(); equal(f.cursorGui.Enabled, false)
	end)

	local function playerStartupFixture()
		local f = fixture(); f.Players.CharacterAutoLoads = true
		f.paused = {}
		f.env.task.spawn = function(fn, ...)
			local args = {...}; local thread = coroutine.create(function() fn(table.unpack(args)) end)
			local ok, reason = coroutine.resume(thread); assert(ok, reason)
			if coroutine.status(thread) == "suspended" then table.insert(f.paused, thread) end
			return thread
		end
		local start = child(f.remotes, "Folder", "StartGameClient")
		f.resetRemote = child(start, "RemoteEvent", "PlayerResetted")
		f.characterHooks, f.deaths, f.profileLoads, f.starters, f.boardUpdates = {}, {}, {}, {}, {}
		f.mainModule = child(f.gameFolder, "ModuleScript", "MainGame")
		f.modules[f.mainModule] = {GameActive = false,
			OnCharacterAdded = function(player) f.characterHooks[player] = (f.characterHooks[player] or 0) + 1 end,
			OnDeath = function(player) f.deaths[player] = (f.deaths[player] or 0) + 1 end,
			LeaveRound = function(player) f.left = player end}
		f.modules[child(f.dataFolder, "ModuleScript", "InventoryHandler")] = {AddKnife = function(player)
			f.starters[player] = (f.starters[player] or 0) + 1
		end}
		f.modules[child(f.servicesFolder, "ModuleScript", "VIPService")] = {
			ApplyToPlayer = function() end, SetCachedExpiry = function() end, RefreshPlayer = function() end, ReconcilePlayer = function() return true end}
		f.modules[child(f.dataFolder, "ModuleScript", "ProfileManager")] = {
			LoadProfile = function(player)
				f.profileLoads[player] = (f.profileLoads[player] or 0) + 1
				return {Data = f.savedPlayerData or {Cash = 700, XP = 150, Inventory = {}, KeyBinds = {}}, IsActive = function() return true end}
			end,
			EndSession = function(player) f.ended = player end, SaveProfile = function() end}
		f.modules[child(f.dataFolder, "ModuleScript", "LeaderboardsHandler")] = {UpdatePlayer = function(player)
			assert(player:GetAttribute("DataReady") == true)
			f.boardUpdates[player] = (f.boardUpdates[player] or 0) + 1
		end}
		local defaults = {Stab = "MouseButton1", ThrowKnife = "E"}
		local binds = child(f.RS, "Folder", "KeyBinds")
		f.modules[child(binds, "ModuleScript", "DefaultKeybinds")] = defaults
		f.modules[child(binds, "ModuleScript", "KeybindValidation")] = {ValidateAndRepair = function() return defaults end}
		f.modules[child(f.modulesFolder, "ModuleScript", "RevolversInfo")] = {["White&Black Revolver"] = {Rarity = "Common", Image = "gun"}}
		function f:newPlayer(id)
			local player = self:createPlayer(id); player.leaderstats:Destroy(); player:SetAttribute("DataReady", nil)
			player.Character.Humanoid.Health = 100
			return player
		end
		function f:start()
			self.modules[child(self.modulesFolder, "ModuleScript", "ProfileSchema")] = load("ProfileSchema", {})
			self.modules[child(self.modulesFolder, "ModuleScript", "KnivesInfo")] = {Bowie = {Rarity = "Common", Image = "bowie"}}
			self.modules[child(self.modulesFolder, "ModuleScript", "Emotes")] = {}
			self.joined = self:load("OnJoined", self.dataFolder) end
		return f
	end
	test("player startup backfills players and characters already present after dependency loading", function()
		local f = playerStartupFixture(); local player = f:newPlayer(1); local character = player.Character
		f:start(); equal(f.profileLoads[player], 1); equal(player.leaderstats.Cash.Value, 700)
		equal(player:GetAttribute("DataReady"), true); equal(f.starters[player], 1); equal(f.boardUpdates[player], 1)
		equal(f.characterHooks[player], 1); character.Humanoid.Died:Fire(); equal(f.deaths[player], 1)
		f.Players.PlayerRemoving:Fire(player); equal(f.left, player); equal(f.ended, player)
	end)
	test("player profiles finish independently while map startup and existing-character hooks are still waiting", function()
		local f = playerStartupFixture(); local resolve = f.env.require
		f.env.require = function(mod)
			if mod == f.mainModule then coroutine.yield("waiting for map startup") end
			return resolve(mod)
		end
		local existing = f:newPlayer(1); f:start()
		local player = f:newPlayer(2); f.Players.PlayerAdded:Fire(player)
		for _, joined in ipairs({existing, player}) do
			assert(joined.leaderstats); equal(joined:GetAttribute("DataReady"), true)
			equal(f.profileLoads[joined], 1); equal(f.characterHooks[joined], nil)
		end
		equal(#f.paused, 2)
		f.Players.PlayerRemoving:Fire(player); player.Parent = nil; equal(f.ended, player)
		for _, thread in ipairs(f.paused) do assert(coroutine.resume(thread)); equal(coroutine.status(thread), "dead") end
		equal(f.characterHooks[existing], 1); equal(f.characterHooks[player], nil)
	end)
	test("death while character setup yields is handled when its listener attaches", function()
		local f = playerStartupFixture(); local resolve = f.env.require
		f.env.require = function(mod)
			if mod == f.mainModule then coroutine.yield("delayed character hook") end
			return resolve(mod)
		end
		local player = f:newPlayer(1); f:start()
		player.Character.Humanoid.Health = 0; player.Character.Humanoid.Died:Fire()
		equal(f.deaths[player], nil)
		for _, thread in ipairs(f.paused) do assert(coroutine.resume(thread)) end
		equal(f.deaths[player], 1); equal(player.Character.Humanoid.Died:Count(), 1)
	end)
	test("player setup disconnects prior death hooks on respawn and every player hook on leave", function()
		local f=playerStartupFixture(); local player=f:newPlayer(1); f:start()
		for _=1,30 do
			local old=player.Character; f:character(player)
			equal(old.Humanoid.Died:Count(),0); equal(player.Character.Humanoid.Died:Count(),1)
		end
		f.Players.PlayerRemoving:Fire(player)
		equal(player.CharacterAdded:Count(),0); equal(player.CharacterRemoving:Count(),0)
		equal(player.Character.Humanoid.Died:Count(),0)
	end)
	test("PlayerAdded and startup snapshot overlap cannot duplicate scaffolding or load a profile twice", function()
		local f = playerStartupFixture(); local player = f:newPlayer(1)
		f.Players.GetPlayers = function(self)
			f.Players.PlayerAdded:Fire(player)
			return self:GetChildren()
		end
		f:start(); f.Players.PlayerAdded:Fire(player)
		local count = 0; for _, item in ipairs(player:GetChildren()) do if item.Name == "leaderstats" then count += 1 end end
		equal(count, 1); equal(f.profileLoads[player], 1); equal(f.starters[player], 1)
		equal(player.CharacterAdded:Count(), 1); equal(f.characterHooks[player], 1)
	end)
	test("existing-character setup preserves round protection and only removes the default spawn field", function()
		local f = playerStartupFixture(); local player = f:newPlayer(1)
		local default = child(player.Character, "ForceField", "ForceField")
		local round = child(player.Character, "ForceField", "RoundStartProtection")
		f:start(); f.delayed[1].fn(); equal(default.Parent, nil); equal(round.Parent, player.Character)
		local old = player.Character; f:character(player)
		equal(f.characterHooks[player], 2)
		old.Humanoid.Died:Fire(); equal(f.deaths[player], nil)
		player.Character.Humanoid.Died:Fire(); equal(f.deaths[player], 1)
	end)
	test("unexpected player hydration errors release the session and never publish incomplete data as ready", function()
		local f = playerStartupFixture(); local player = f:newPlayer(1)
		f.modules[f.dataFolder.InventoryHandler].AddKnife = function() error("Broken starter template") end
		f:start(); equal(player:GetAttribute("DataReady"), false); equal(player:GetAttribute("DataLoadState"), "Failed")
		equal(f.ended, player); assert(player.KickMessage); equal(f.boardUpdates[player], nil)
		f.Players.PlayerAdded:Fire(player); equal(f.profileLoads[player], 1)
	end)
	test("losing a profile while VIP hydration yields cannot mark player data ready", function()
		local f = playerStartupFixture(); local player = f:newPlayer(1)
		f.modules[f.dataFolder.ProfileManager].LoadProfile = function()
			return {Data = {Cash = 700, Inventory = {}}, IsActive = function() return false end}
		end
		f:start(); equal(player:GetAttribute("DataReady"), false); equal(f.boardUpdates[player], nil)
	end)
	local function startupFixture()
		local f = fixture(); f.paused, f.warnings = {}, {}
		f.env.warn = function(message) table.insert(f.warnings, message) end
		function f:resume(thread)
			local ok, reason = coroutine.resume(thread); assert(ok, reason)
			if coroutine.status(thread) == "suspended" then
				table.insert(reason == "frame" and self.background or self.paused, thread)
			end
		end
		local function threadFor(fn, ...)
			local args = {...}; return coroutine.create(function() fn(table.unpack(args)) end)
		end
		f.env.task.defer = function(fn, ...) table.insert(f.background, threadFor(fn, ...)) end
		f.env.task.spawn = function(fn, ...) local thread = threadFor(fn, ...); f:resume(thread); return thread end
		f.env.task.wait = function() coroutine.yield("frame") end
		function f:step()
			local ready = table.clone(self.background); table.clear(self.background)
			self.time += 1 / 60
			for _, thread in ipairs(ready) do self:resume(thread) end
		end
		function f:drain()
			for _ = 1, 30 do if #self.background == 0 then return end; self:step() end
			error("Startup queue failed to settle")
		end
		f.config = f:load("StartupConfig", f.modulesFolder)
		f.loader = f:load("StartupLoader", f.modulesFolder)
		function f:job(owner, name, init)
			local mod = child(owner, "ModuleScript", name); self.modules[mod] = {name = name}
			return {Name = name, Module = mod, Init = init}
		end
		return f
	end
	test("server and client startup jobs share a two-per-frame queue across groups", function()
		local f = startupFixture(); local first, second = object("Folder", "First"), object("Folder", "Second")
		local entries, launched = {}, 0
		for index = 1, 5 do table.insert(entries, f:job(first, "Job" .. index, function() launched += 1 end)) end
		local a = f.loader.Start(first, entries)
		local b = f.loader.Start(second, {f:job(second, "Other", function() launched += 1 end)})
		equal(launched, 0); f:step(); equal(launched, 2); equal(a.Ready, false); equal(b.Ready, false)
		f:step(); equal(launched, 4); f:drain(); equal(launched, 6); equal(a.Ready, true); equal(b.Ready, true)
		equal(first:GetAttribute("StartupLoaded"), 5); equal(second:GetAttribute("StartupState"), "Ready")
	end)
	test("a yielding startup dependency cannot block later jobs and only becomes ready after it returns", function()
		local f = startupFixture(); local owner = object("Folder", "Controllers"); local blocked = f:job(owner, "Blocked")
		local requireModule = f.env.require
		f.env.require = function(mod) if mod == blocked.Module then coroutine.yield("dependency") end; return requireModule(mod) end
		f.loader = f:load("StartupLoader", f.modulesFolder, "YieldingLoader")
		local state = f.loader.Start(owner, {blocked, f:job(owner, "Independent")})
		f:drain(); equal(state.Loaded, 1); equal(state.Ready, false); equal(state.Complete, false)
		equal(state.Records[1].State, "Loading"); equal(state.Records[2].State, "Ready")
		f:resume(table.remove(f.paused, 1)); equal(state.Ready, true); equal(owner:GetAttribute("StartupState"), "Ready")
	end)
	test("missing modules and failing Init callbacks do not stop unrelated startup jobs or produce false readiness", function()
		local f = startupFixture(); local owner = object("Folder", "Services"); local initialized = 0
		local state = f.loader.Start(owner, {
			{Name = "Missing"}, f:job(owner, "Broken", function() error("Init failure") end),
			f:job(owner, "Good", function() initialized += 1 end),
		})
		f:drain(); equal(state.Ready, false); equal(state.Complete, true); equal(state.Failed, 2)
		equal(initialized, 1); equal(#f.warnings, 2); assert(string.find(state.Records[1].Error, "Missing ModuleScript"))
		equal(owner:GetAttribute("StartupState"), "Failed"); equal(owner:GetAttribute("StartupLoaded"), 1)
	end)
	test("starting an already registered group cannot run its Init hooks twice", function()
		local f = startupFixture(); local owner = object("Folder", "Controllers"); local initialized = 0
		local entry = f:job(owner, "Once", function() initialized += 1 end)
		local first = f.loader.Start(owner, {entry}); equal(f.loader.Start(owner, {entry}), first)
		f:drain(); equal(initialized, 1); equal(first.Loaded, 1)
		equal(f.loader.Start(owner, {entry}), first); f:drain(); equal(initialized, 1)
	end)
	test("a slow startup warning does not cancel a legitimate load and completed jobs do not warn", function()
		local f = startupFixture(); local owner = object("Folder", "Controllers")
		local state = f.loader.Start(owner, {{Name = "Slow", Start = function() coroutine.yield("dependency") end}, f:job(owner, "Fast")})
		f:drain(); f.delayed[1].fn(); f.delayed[2].fn(); equal(#f.warnings, 1)
		equal(state.Records[1].State, "Loading"); equal(state.Failed, 0)
		f:resume(table.remove(f.paused, 1)); equal(state.Ready, true); equal(#f.warnings, 1)
	end)
	test("server readiness waits for every required group and an optional admin failure cannot block gameplay", function()
		local f = startupFixture(); f.config.RequiredServerGroups = {"DataStore", "Game"}
		local startup = f:load("StartupService", f.server)
		f:job(f.dataFolder, "Profiles"); startup.LoadGroup(f.dataFolder); f:drain()
		equal(f.RS:GetAttribute("ServerReady"), false); equal(f.RS:GetAttribute("ServerStartupPending"), "Game")
		local signal = f.RS:GetAttributeChangedSignal("ServerReady")
		function signal:Wait()
			local thread = coroutine.running(); self:Once(function() assert(coroutine.resume(thread)) end)
			coroutine.yield("readiness")
		end
		local released = false; f.env.task.spawn(function() startup.AwaitReady(); released = true end)
		equal(released, false)
		local admin = child(f.server, "Folder", "Admin")
		startup.LoadGroup(admin, {Priority = {"MissingAdmin"}})
		f:job(f.gameFolder, "Loop"); startup.LoadGroup(f.gameFolder); f:drain()
		equal(f.RS:GetAttribute("ServerReady"), true); equal(f.RS:GetAttribute("ServerStartupState"), "Ready")
		equal(released, true); equal(admin:GetAttribute("StartupState"), "Failed")
	end)
	test("failed core server jobs keep readiness false and identify the failing group and module", function()
		local f = startupFixture(); f.config.RequiredServerGroups = {"Game"}
		local startup = f:load("StartupService", f.server)
		startup.LoadGroup(f.gameFolder, {Priority = {"MissingLoop"}}); f:drain()
		equal(f.RS:GetAttribute("ServerReady"), false); equal(f.RS:GetAttribute("ServerStartupState"), "Failed")
		equal(f.RS:GetAttribute("ServerStartupFailures"), "Game.MissingLoop")
	end)
	test("a required startup timeout publishes failure and a late successful job recovers readiness", function()
		local f = startupFixture(); f.config.RequiredServerGroups = {"Game"}
		local startup = f:load("StartupService", f.server)
		startup.LoadGroup(f.gameFolder, {Tasks = {{Name = "SlowCore", Start = function() coroutine.yield("dependency") end}}})
		f:drain(); equal(f.RS:GetAttribute("ServerReady"), false)
		f.time += f.config.ReadyTimeoutSeconds
		for _, timer in ipairs(f.delayed) do if timer.delay == f.config.ReadyTimeoutSeconds then timer.fn() end end
		equal(f.RS:GetAttribute("ServerStartupState"), "Failed")
		equal(f.RS:GetAttribute("ServerStartupPending"), "Game.SlowCore")
		f:resume(table.remove(f.paused, 1))
		equal(f.RS:GetAttribute("ServerReady"), true); equal(f.RS:GetAttribute("ServerStartupState"), "Ready")
	end)
	test("optional service failure does not hold a ready required service group closed", function()
		local f = startupFixture(); f.config.RequiredServerGroups = {"ServicesHandler"}
		f.config.OptionalServerModules = {ServicesHandler = {"OptionalView"}}
		local startup = f:load("StartupService", f.server)
		f:job(f.servicesFolder, "CorePurchases")
		startup.LoadGroup(f.servicesFolder, {Priority = {"OptionalView"}}); f:drain()
		equal(f.RS:GetAttribute("ServerReady"), true); equal(f.RS:GetAttribute("ServerStartupFailures"), "")
	end)
	test("a server bootstrap that never registers remains unready and emits one actionable diagnostic", function()
		local f = startupFixture(); f.config.RequiredServerGroups = {"Game"}
		f:load("StartupService", f.server); f.delayed[1].fn()
		equal(f.RS:GetAttribute("ServerReady"), false); equal(#f.warnings, 1)
		assert(string.find(f.warnings[1], "never registered: Game"))
	end)
	test("server status persists for late clients and unchanged waiting messages do not spam remotes", function()
		local f = fixture(); local remote = child(f.remotes, "RemoteEvent", "ChangeStatus")
		local sender = f:load("StatusSender", f.gameFolder)
		for _ = 1, 100 do sender.EditClientStatus("WAITING") end
		equal(remote.ClientCalls, 1); equal(f.RS:GetAttribute("GameStatus"), "WAITING")
		sender.EditClientStatus("VOTING"); equal(remote.ClientCalls, 2); equal(f.RS:GetAttribute("GameStatus"), "VOTING")
	end)
	test("startup asset resolution validates classes and fails missing server assets instead of returning placeholders", function()
		local f = startupFixture(); local folder = child(f.SS, "Folder", "Knives")
		equal(f.loader.RequireChild(f.SS, "Knives", "Folder"), folder)
		local ok, err = pcall(f.loader.RequireChild, f.SS, "Missing", "Folder")
		equal(ok, false); assert(string.find(err, "Missing required asset ServerStorage.Missing after 10.0s"))
		ok, err = pcall(f.loader.RequireChild, f.SS, "Knives", "Model")
		equal(ok, false); assert(string.find(err, "must be a Model"))
	end)
	test("map catalog loads validated server templates without a gameplay-map publication delay", function()
		local f = startupFixture()
		for _, name in ipairs({"Tropical Island", "Cargo Port", "Grids", "Classic ROBLOX"}) do child(f.SS, "Model", name) end
		local maps = f:load("MapCatalog", f.gameFolder)
		equal(maps["Cargo Port"].MapFolder, f.SS:FindFirstChild("Cargo Port")); equal(#f.background, 0)
	end)
	test("a missing map template reports the exact asset and cannot leave the catalog silently waiting forever", function()
		local f = startupFixture(); child(f.SS, "Model", "Tropical Island")
		local ok, err = pcall(function() f:load("MapCatalog", f.gameFolder) end)
		equal(ok, false); assert(string.find(err, "ServerStorage.Cargo Port"))
	end)
	local function profileFixture(validation)
		local f = fixture(); f.player = f:createPlayer(1)
		f:load("StartupConfig", f.modulesFolder); f:load("StartupLoader", f.modulesFolder)
		f:load("DataConfig", f.modulesFolder)
		child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")
		f.modules[f.RS.KeyBinds.KeybindValidation] = validation or { GetDefaults = function() return {} end }
		local profileModule = child(child(f.SSS, "Folder", "Packages"), "ModuleScript", "ProfileStore")
		f.profile = { active = true, Data = { MigrationComplete = true, Cash = 500, Inventory = { { Name = "SavedKnife", Quantity = 2 } }, ProcessedPurchases = {} }, LastSavedData = { ProcessedPurchases = {} }, OnSave = signal(), OnSessionEnd = signal(), saveCalls = 0 }
		function f.profile:IsActive() return self.active end
		function f.profile:AddUserId() end
		function f.profile:Reconcile() end
		function f.profile:Save()
			self.OnSave:Fire(); self.saveCalls += 1; self.pending = copyTable(self.Data)
		end
		function f.profile:EndSession() self.OnSave:Fire(); self.active = false; self.OnSessionEnd:Fire() end
		f.modules[profileModule] = { New = function() return { StartSessionAsync = function() return f.profile end } end }
		f.profiles = f:load("Profiles", f.dataFolder, "ProfileManager")
		equal(f.profiles.LoadProfile(f.player), f.profile)
		return f
	end
	test("autosave during hydration does not replace saved cash or inventory with defaults", function()
		local f = profileFixture(); f.player:SetAttribute("DataReady", false)
		f.profile.OnSave:Fire()
		equal(f.profile.Data.Cash, 500); equal(f.profile.Data.Inventory[1].Name, "SavedKnife")
	end)
	test("profile save captures daily-shop marker, cash and inventory in the same player record", function()
		local f = profileFixture(); f.player:SetAttribute("DataReady", true)
		f.profile.Data.DailyShop = {RotationId = "1:20833", Purchased = {["Knife:Bowie"] = true}}
		f.player.leaderstats.Cash.Value = 350
		local item = child(f.player.leaderstats.Inventory, "StringValue", "Bowie")
		child(item, "IntValue", "Quantity", 1); child(item, "StringValue", "Rarity", "Common")
		child(item, "StringValue", "Image", "asset"); child(item, "BoolValue", "Tradeable", true)
		f.profiles.SaveProfile(f.player)
		equal(f.profile.pending.Cash, 350); equal(f.profile.pending.DailyShop.RotationId, "1:20833")
		equal(f.profile.pending.DailyShop.Purchased["Knife:Bowie"], true)
		equal(f.profile.pending.Inventory[1].Name, "Bowie"); equal(f.profile.pending.Inventory[1].Quantity, 1)
	end)
	test("purchase acknowledgement waits for LastSavedData rather than queued Save", function()
		local f = profileFixture(); f.profile.Data.ProcessedPurchases.receipt = true
		equal(f.profiles.ConfirmPurchase(f.player, "receipt", 0.3), false)
		equal(f.profile.saveCalls, 1); equal(f.profile.Data.ProcessedPurchases.receipt, true)
		f.onWait = function() f.profile.LastSavedData = f.profile.pending end
		equal(f.profiles.ConfirmPurchase(f.player, "receipt", 1), true)
		equal(f.profile.LastSavedData.Cash, f.player.leaderstats.Cash.Value)
	end)
	test("durable receipt requires no extra save; missing marker cannot be acknowledged", function()
		local f = profileFixture(); f.profile.LastSavedData.ProcessedPurchases.receipt = true
		equal(f.profiles.ConfirmPurchase(f.player, "receipt"), true); equal(f.profile.saveCalls, 0)
		equal(f.profiles.ConfirmPurchase(f.player, "missing"), false); equal(f.profile.saveCalls, 0)
	end)
	test("profile session loss cancels pending purchase confirmation", function()
		local f = profileFixture(); f.profile.Data.ProcessedPurchases.receipt = true
		f.onWait = function() f.profile:EndSession() end
		equal(f.profiles.ConfirmPurchase(f.player, "receipt", 1), false)
		equal(f.player:GetAttribute("DataReady"), false); equal(f.player:GetAttribute("DataLoadState"), "Failed")
	end)

	local function purchaseFixture()
		local f = profileFixture()
		local shop = child(f.remotes, "Folder", "ShopRemotes")
		child(child(shop, "Folder", "PurchaseGold"), "RemoteEvent", "PurchaseGoldRemote")
		child(child(shop, "Folder", "Gamepass"), "RemoteEvent", "BuyGamePass")
		child(child(shop, "Folder", "VIP"), "RemoteEvent", "VIPStatus")
		f.modules[child(f.modulesFolder, "ModuleScript", "ProductIDS")] = { [100] = 100 }
		f.modules[child(f.servicesFolder, "ModuleScript", "VIPService")] = { HasVIPByUserId = function() return false end }
		f.purchases = f:load("Purchases", f.servicesFolder, "PurchaseHandler")
		f.receipt = { PurchaseId = "receipt", PlayerId = 1, ProductId = 100 }
		return f
	end
	test("receipt timeout and retries grant gold exactly once and acknowledge only persistence", function()
		local f = purchaseFixture()
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry"); equal(f.player.leaderstats.Cash.Value, 100)
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry"); equal(f.player.leaderstats.Cash.Value, 100)
		f.onWait = function() f.profile.LastSavedData = f.profile.pending end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted"); equal(f.player.leaderstats.Cash.Value, 100)
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted"); equal(f.player.leaderstats.Cash.Value, 100)
	end)
	test("unknown product releases its processing lock on every retry", function()
		local f = purchaseFixture(); f.receipt.ProductId = 999
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry")
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry")
		equal(f.notifications, 2, "Both requests must reach unknown-product handling")
	end)
	test("receipt remains locked through archive acknowledgement and historical maintenance", function()
		local f = purchaseFixture(); f.onWait = function() f.profile.LastSavedData = f.profile.pending end
		local archive = f.modules[f.servicesFolder.ReceiptArchive]
		local commit = archive.Commit
		archive.Commit = function(...)
			assert(f.purchases.IsProcessing(1))
			equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry")
			assert(not f.purchases.Maintain(1, function() error("must not run") end))
			return commit(...)
		end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted"); equal(f.player.leaderstats.Cash.Value, 100)
		archive.Commit = commit
		local ok = f.purchases.Maintain(1, function() equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry") end)
		assert(ok and not f.purchases.IsProcessing(1))
		assert(not f.purchases.Maintain(1, function() error("maintenance outage") end))
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted"); equal(f.player.leaderstats.Cash.Value, 100)
	end)
	test("VIP retry with an owned durable profile marker cannot extend duration again", function()
		local f = purchaseFixture(); f.receipt.ProductId = 3548752161
		f.profile.Data.ProcessedPurchases.receipt = true
		f.profile.LastSavedData.ProcessedPurchases.receipt = true
		f.modules[f.servicesFolder.VIPService].GrantDuration = function() error("must not grant again") end
		f.modules[f.servicesFolder.VIPService].ArchivePurchase = function() end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted")
	end)
	test("unexpected receipt error releases its lock and retries without double granting", function()
		local f = purchaseFixture(); local originalSave = f.profile.Save
		f.profile.Save = function() error("Simulated unexpected save error") end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry"); equal(f.player.leaderstats.Cash.Value, 100)
		f.profile.Save = originalSave; f.onWait = function() f.profile.LastSavedData = f.profile.pending end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Granted"); equal(f.player.leaderstats.Cash.Value, 100)
	end)
	test("receipt cannot grant to a player whose profile is still hydrating", function()
		local f = purchaseFixture(); f.player:SetAttribute("DataReady", false)
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry"); equal(f.player.leaderstats.Cash.Value, 0)
	end)
	test("yielding VIP lookup cannot grant after the profile session ends", function()
		local f = purchaseFixture()
		f.modules[f.servicesFolder.VIPService].HasVIPByUserId = function() f.profile:EndSession(); return false end
		equal(f.Marketplace.ProcessReceipt(f.receipt), "Retry"); equal(f.player.leaderstats.Cash.Value, 0)
	end)
	test("viewing a local player uses live profile history with no DataStore reads", function()
		local f = profileFixture(); f.profile.Data.RoundHistory = { { Kills = 5 } }
		local reads = 0
		f.profiles.GetAsync = function() reads += 1; error("Must not read local player from DataStore") end
		local info = f:load("PlayerInfo", f.servicesFolder, "GetPlayerInfo")
		local result = info.AllInfo(1)
		equal(reads, 0); equal(result.RoundHistory[1].Kills, 5); equal(result.Cash, 0)
		f.player:SetAttribute("DataReady", false)
		equal(info.AllInfo(1).Loading, true); equal(next(info.Inventory(1)), nil); equal(reads, 0)
	end)
	test("offline profile read failure safely falls back to legacy data", function()
		local f = profileFixture()
		f.profiles.GetAsync = function() error("Simulated read failure") end
		f.profiles.GetOldDataAsync = function() return { Name = "OfflinePlayer", Cash = 12 } end
		local info = f:load("PlayerInfo", f.servicesFolder, "GetPlayerInfo")
		equal(info.AllInfo(2).Cash, 12)
	end)
	test("offline profile returns saved inventory from one read without modifying saved rows", function()
		local f = profileFixture(); local reads = 0
		local saved = {Name = "Offline", Inventory = {
			{Name = "Bowie", Quantity = 1, Rarity = "Common", Image = "image"},
			{Name = "Cosmetic", Quantity = 3, Rarity = "Rare", Image = "skin", Tradeable = true},
			{Name = "Broken", Quantity = 0/0}, {Name = "Infinite", Quantity = math.huge}, false,
		}}
		f.profiles.GetAsync = function() reads += 1; return {Data = saved} end
		local info = f:load("PlayerInfo", f.servicesFolder, "GetPlayerInfo")
		local basic, inventory = info.AllInfo(2)
		equal(reads, 1); equal(basic.Name, "Offline"); equal(inventory.Cosmetic.Quantity, 3)
		equal(inventory.Cosmetic.Image, "skin"); equal(inventory.Bowie.Tradeable, false)
		equal(inventory.Broken, nil); equal(inventory.Infinite, nil); equal(#saved.Inventory, 5)
		equal(info.Inventory(2).Cosmetic.Quantity, 3); equal(reads, 2)
	end)
	test("unavailable offline profiles return an explicit state and empty inventory", function()
		local f = profileFixture()
		f.profiles.GetAsync = function() error("backend unavailable") end
		f.profiles.GetOldDataAsync = function() error("legacy unavailable") end
		function f.Players:GetNameFromUserIdAsync() return "Offline" end
		local info = f:load("PlayerInfo", f.servicesFolder, "GetPlayerInfo")
		local basic, inventory = info.AllInfo(2)
		equal(basic.Unavailable, true); equal(next(inventory), nil)
	end)
	test("leaderboard writes use loaded current stats and skip unchanged values", function()
		local f = fixture(); f.player = f:createPlayer(1)
		f.dataConfig = f:load("DataConfig", f.modulesFolder)
		child(f.player.leaderstats, "IntValue", "Kills", 5); child(f.player.leaderstats, "IntValue", "XP", 150)
		f.player.leaderstats.Cash.Value = 250
		child(child(f.remotes, "Folder", "Leaderboards"), "RemoteEvent", "RequestLeaderboards")
		f.modules[child(f.modulesFolder, "ModuleScript", "CalculateLevel")] = { GetLevel = function(xp) return math.floor(xp / 100) end }
		f.stores = {}; f.writes = 0
		f.DataStore.GetOrderedDataStore = function(_, name, scope)
			local store = { values = {}, scope = scope }; f.stores[name] = store
			function store:SetAsync(key, value) f.writes += 1; self.values[key] = value end
			return store
		end
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.task.defer = function(fn) fn() end
		local boards = f:load("Leaderboards", f.dataFolder, "LeaderboardsHandler")
		local function update() boards.UpdatePlayer(f.player); f.background[#f.background]() end
		f.player:SetAttribute("DataReady", false); update(); equal(f.writes, 0)
		f.player:SetAttribute("DataReady", true); update(); equal(f.writes, 3)
		equal(f.stores["Leaderboard_Gold_Datastore1.0"].scope, f.dataConfig.GetLeaderboardScope())
		equal(f.stores["Leaderboard_Gold_Datastore1.0"].values["1"], 250)
		update(); equal(f.writes, 3)
		f.player.leaderstats.Cash.Value = 333; update(); equal(f.writes, 4)
		equal(f.stores["Leaderboard_Gold_Datastore1.0"].values["1"], 333)
	end)

	local function questFixture(failRead, legacy, migrated)
		local f = fixture(); f.writes, f.reads, f.legacyWrites, f.failRead = 0, 0, 0, failRead
		f.utc = 1700000000
		f.env.os.time = function() return f.utc end
		local remotes = child(f.remotes, "Folder", "Quests")
		f.request = child(remotes, "RemoteEvent", "RequestQuests")
		f.claim = child(remotes, "RemoteEvent", "ClaimQuestReward")
		f.profile = {active = true, Data = {DailyQuests = migrated or {MigrationComplete = false}}}
		function f.profile:IsActive() return self.active end
		f.profiles = {
			GetProfile = function() return f.profile end,
			SaveProfile = function(player)
				f.writes += 1
				f.saved = {Cash = player.leaderstats.Cash.Value, DailyQuests = copyTable(f.profile.Data.DailyQuests)}
			end,
		}
		f.modules[child(f.dataFolder, "ModuleScript", "ProfileManager")] = f.profiles
		f:load("QuestsConfig", f.modulesFolder); f:load("RewardMath", f.modulesFolder)
		f.DataStore.GetDataStore = function() return {
			GetAsync = function() f.reads += 1; if f.onRead then f.onRead() end; if f.failRead then error("Simulated outage") end; return legacy end,
			UpdateAsync = function() f.legacyWrites += 1; error("Legacy quests must be read-only") end,
		} end
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.Random = { new = function() return { NextInteger = function(_, _, hi) return hi end } end }
		f.quests = f:load("Quests", f.servicesFolder, "QuestsHandler")
		f.player = f:createPlayer(1); f.Players.PlayerAdded:Fire(f.player)
		return f
	end
	test("failed quest read cannot create writable defaults or pay a reward", function()
		local f = questFixture(true)
		f.quests.AddProgress(f.player, "WINS", 10); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 0); equal(f.request.LastClientArgs[2].Loading, true)
		f.Players.PlayerRemoving:Fire(f.player); equal(f.writes, 0)
	end)
	test("nil legacy read migrates once and saves quest claim and cash in one profile", function()
		local f = questFixture(false)
		f.quests.AddProgress(f.player, "WINS", 2); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150); equal(f.writes, 2)
		equal(f.saved.Cash, 150); equal(f.saved.DailyQuests.Claimed.WIN_2_ROUNDS, true); equal(f.legacyWrites, 0)
		f.time += 2; f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150, "No duplicate claim")
	end)
	test("quest data retry recovers without writing during the failed read", function()
		local f = questFixture(true); equal(f.writes, 0)
		f.failRead = false; f.delayed[1].fn()
		equal(f.request.LastClientArgs[2].Loading, nil)
		f.quests.AddProgress(f.player, "WINS", 2); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150); equal(f.writes, 2)
	end)
	test("quest retry preserves progress buffered during a read outage", function()
		local f = questFixture(true); f.quests.AddProgress(f.player, "WINS", 2)
		f.failRead = false; f.delayed[1].fn()
		equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), true); equal(f.player.leaderstats.Cash.Value, 150)
	end)
	test("legacy quest migration preserves same-day progress and claimed flags", function()
		local f = questFixture(false, {DayKey = os.date("!%Y-%m-%d", 1700000000), Progress = {WIN_2_ROUNDS = 2, KILL_5_PLAYERS = 5}, Claimed = {WIN_2_ROUNDS = true}})
		equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), false); equal(f.quests.Claim(f.player, "KILL_5_PLAYERS"), true)
		equal(f.player.leaderstats.Cash.Value, 200); equal(f.legacyWrites, 0)
	end)
	test("already-migrated quests load without another DataStore read", function()
		local f = questFixture(true, nil, {MigrationComplete = true, DayKey = os.date("!%Y-%m-%d", 1700000000), Progress = {WIN_2_ROUNDS = 2}, Claimed = {}})
		equal(f.reads, 0); equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), true)
	end)
	test("quest midnight reset clears old progress and claims without stale rewards", function()
		local f = questFixture(false); f.quests.AddProgress(f.player, "WINS", 2)
		equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), true)
		f.utc = (math.floor(f.utc / 86400) + 1) * 86400
		equal(f.quests.GetStatus(f.player).Quests[1].Progress, 0); equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), false)
		equal(f.player.leaderstats.Cash.Value, 150)
	end)
	test("requesting quest status does not suppress an immediate claim", function()
		local f = questFixture(false); f.quests.AddProgress(f.player, "WINS", 2)
		f.request.OnServerEvent:Fire(f.player); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150)
	end)
	test("quest progress rejects non-finite values and stops after session loss", function()
		local f = questFixture(false); local progress = f.profile.Data.DailyQuests.Progress
		f.quests.AddProgress(f.player, "WINS", 0/0); f.quests.AddProgress(f.player, "WINS", math.huge)
		equal(progress.WIN_2_ROUNDS, nil)
		f.profile.active = false; f.quests.AddProgress(f.player, "WINS", 2)
		equal(f.quests.Claim(f.player, "WIN_2_ROUNDS"), false); equal(f.player.leaderstats.Cash.Value, 0)
	end)
	test("frequent quest changes coalesce updates and rely on profile autosave", function()
		local f = questFixture(false); local initial, pushes = f.writes, f.request.ClientCalls
		for _ = 1, 10 do f.quests.AddProgress(f.player, "PLAY_TIME_SECONDS", 5) end
		equal(f.writes, initial); equal(f.request.ClientCalls, pushes); equal(#f.delayed, 1)
		f.delayed[1].fn(); equal(f.request.ClientCalls, pushes + 1)
	end)
	test("quest playtime preserves fractional elapsed time across updates", function()
		local f = questFixture(false)
		for _ = 1, 8 do f.quests.AddProgress(f.player, "PLAY_TIME_SECONDS", 0.25) end
		equal(f.profile.Data.DailyQuests.Progress.PLAY_20_MIN, 2)
	end)
	test("production ProfileManager captures quest claim flags and cash in the same queued save", function()
		local f = profileFixture()
		f.profile.Data.DailyQuests = {MigrationComplete = false}
		local remotes = child(f.remotes, "Folder", "Quests")
		child(remotes, "RemoteEvent", "RequestQuests"); child(remotes, "RemoteEvent", "ClaimQuestReward")
		f:load("QuestsConfig", f.modulesFolder); f:load("RewardMath", f.modulesFolder)
		f.env.Random = {new = function() return {NextInteger = function(_, _, hi) return hi end} end}
		f.env.task.spawn = function(fn, ...) local args = {...}; table.insert(f.background, function() fn(table.unpack(args)) end) end
		local quests = f:load("Quests", f.servicesFolder, "QuestsHandler")
		f.background[1]()
		quests.AddProgress(f.player, "WINS", 2); equal(quests.Claim(f.player, "WIN_2_ROUNDS"), true)
		equal(f.profile.pending.Cash, 150); equal(f.profile.pending.DailyQuests.Claimed.WIN_2_ROUNDS, true)
	end)
	test("corrupt legacy quest data stays unavailable without replacing it", function()
		local f = questFixture(false, {Progress = "bad", Claimed = {}})
		equal(f.writes, 0); equal(f.quests.GetStatus(f.player).Loading, true)
		equal(f.profile.Data.DailyQuests.MigrationComplete, false)
	end)
	test("lobby preview starts once, cannot spawn participants, and is replaced on same-map round", function()
		local f = mapFixture(); local preview = f.workspace.MapA
		equal(preview:GetAttribute("LobbyPreview"), true)
		local player = f:createPlayer(1); child(player.Character, "Part", "HumanoidRootPart")
		equal(f.maps.PlacePlayers("MapA", {player}), 0); equal(f.maps.RespawnPlayer(player, "MapA"), false)
		equal(f.maps.Spawn("MapA"), true); equal(preview.Parent, nil); equal(f.workspace.MapA:GetAttribute("LobbyPreview"), false)
		local round = f.workspace.MapA
		equal(f.maps.ShowLobbyMap(), true); equal(round.Parent, nil); equal(f.workspace.MapA:GetAttribute("LobbyPreview"), true)
		equal(f.maps.ShowLobbyMap(), true)
		local count = 0; for _, item in ipairs(f.workspace:GetChildren()) do if item:GetAttribute("RoundMap") then count += 1 end end
		equal(count, 1)
	end)
	test("knife white dot shares aim position on desktop and touch and hides in menus", function()
		local f = cursorFixture(); f.cursorConfig.Knife.Image = ""; child(f.player.Character, "Tool", "KnifeA"); f:tick()
		equal(f.cursorGui.WhiteDot.Visible, true); equal(f.cursorGui.WhiteDot.Size.X, 5)
		equal(f.cursorGui.WhiteDot.Position.X, 123); equal(f.cursorGui.Cursor.Visible, false)
		f.inputType = f.env.Enum.UserInputType.Touch; f:tick(); equal(f.cursorGui.WhiteDot.Position.X, 500)
		f.knifeAim = {X = 260, Y = 200}; f:tick(); equal(f.cursorGui.WhiteDot.Position.X, 260)
		f.guiService.MenuIsOpen = true; f:tick(); equal(f.cursorGui.Enabled, false)
	end)
	local rewardMath = load("RewardMath")
	test("daily cooldown boundary and day 14 wrap are consistent", function()
		local waiting = rewardMath.DailyStatus(100, 14, 150, 100, 14)
		equal(waiting.CanClaim, false); equal(waiting.CurrentDayIndex, 1); equal(waiting.CycleClaimedCount, 14)
		local ready = rewardMath.DailyStatus(100, 14, 200, 100, 14)
		equal(ready.CanClaim, true); equal(ready.CurrentDayIndex, 1); equal(ready.CycleClaimedCount, 0)
		equal(rewardMath.NextUtcReset(172800), 259200)
	end)
	local function dailyFixture()
		local f = questFixture(false)
		local remotes = child(f.remotes, "Folder", "DailyRewards")
		f.dailyRequest = child(remotes, "RemoteEvent", "ClaimDailyReward")
		f.dailyResponse = child(remotes, "RemoteEvent", "DailyRewardClient")
		f:load("DailyRewardsConfig", f.modulesFolder)
		child(f.player.leaderstats, "IntValue", "XP", 0); child(f.player.leaderstats, "Folder", "Emotes")
		local daily = child(f.player.leaderstats, "Folder", "DailyRewards")
		child(daily, "IntValue", "LastClaimTime", 0); child(daily, "IntValue", "Streak", 0)
		f.grants = 0
		f.modules[child(f.dataFolder, "ModuleScript", "InventoryHandler")] = {
			AddKnife = function() if f.failGrant then return nil end; f.grants += 1; return true end,
			AddEmote = function() if f.failGrant then return nil end; f.grants += 1; return true end,
		}
		f.profiles.SaveProfile = function(player)
			f.writes += 1
			f.saved = {Cash = player.leaderstats.Cash.Value, XP = player.leaderstats.XP.Value, DailyRewards = copyTable(f.profile.Data.DailyRewards), DailyQuests = copyTable(f.profile.Data.DailyQuests), Grants = f.grants}
		end
		f.daily = f:load("DailyRewards", f.servicesFolder)
		return f
	end
	test("daily status request cannot swallow the following claim; claims grant once", function()
		local f = dailyFixture()
		f.dailyRequest.OnServerEvent:Fire(f.player, "GetStatus"); f.dailyRequest.OnServerEvent:Fire(f.player, "Claim", 1)
		equal(f.grants, 1); equal(f.saved.XP, 50); equal(f.saved.DailyRewards.Streak, 1)
		f.time += 1; f.dailyRequest.OnServerEvent:Fire(f.player, "Claim", 1)
		equal(f.grants, 1); equal(f.player.leaderstats.XP.Value, 50)
	end)
	test("failed daily inventory grant pays no XP and consumes no claim", function()
		local f = dailyFixture(); f.failGrant = true
		equal(f.daily.Claim(f.player, 1), false); equal(f.player.leaderstats.XP.Value, 0); equal(f.player.leaderstats.DailyRewards.Streak.Value, 0)
		f.failGrant = false; f.time += 1; equal(f.daily.Claim(f.player, 1), true); equal(f.grants, 1)
	end)
	test("daily claims require hydrated active profile and reject forged day values", function()
		for _, value in ipairs({0/0, math.huge, -1, 1.5, 2}) do local f = dailyFixture(); equal(f.daily.Claim(f.player, value), false); equal(f.grants, 0) end
		local f = dailyFixture(); f.player:SetAttribute("DataReady", false)
		equal(f.daily.GetStatus(f.player).Loading, true); equal(f.daily.Claim(f.player, 1), false)
		f.time += 1; f.player:SetAttribute("DataReady", true); f.profile.active = false
		equal(f.daily.Claim(f.player, 1), false); equal(f.grants, 0)
	end)
	local function bindingFixture()
		local f = fixture()
		local keys = {}
		for _, name in ipairs({"W","A","S","D","Space","Tab","Slash","Escape","Backspace","Return","KeypadEnter","I","O","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","LeftMeta","RightMeta","Unknown","ButtonR2","DPadUp","Thumbstick1","E","G","LeftShift","LeftControl","C","One","Two","Three","Q","R","T","X","Y","H","J","K","L","U","B","Z","N","M","V","F","P"}) do keys[name] = {Name = name, EnumType = keys} end
		function keys:GetEnumItems() local result = {}; for _, value in pairs(keys) do if type(value) == "table" then table.insert(result, value) end end; return result end
		f.env.Enum.KeyCode, f.env.Enum.UserInputType = keys, {Keyboard = {Name = "Keyboard"}, MouseButton1 = {Name = "MouseButton1"}, MouseButton2 = {Name = "MouseButton2"}, MouseButton3 = {Name = "MouseButton3"}}
		local originalTypeof = f.env.typeof
		f.env.typeof = function(value) return type(value) == "table" and value.EnumType == keys and "EnumItem" or originalTypeof(value) end
		f.validation = f:load("KeybindValidation", f.modulesFolder)
		f.player = f:createPlayer(1)
		local folder = child(f.player.leaderstats, "Folder", "KeyBinds")
		for action, value in pairs(f.validation.GetDefaults()) do child(folder, "StringValue", action, value) end
		return f
	end
	test("keybind repair rejects unknown/reserved/controller keys and unsupported mouse actions", function()
		local f = bindingFixture()
		for _, value in ipairs({"ThisIsNotAKey", "Unknown", "ButtonR2", "DPadUp", "Thumbstick1", "W"}) do equal(f.validation.Normalize(value), nil) end
		equal(f.validation.NormalizeForAction("Sprint", "MouseButton1"), nil)
		equal(f.validation.NormalizeForAction("ThrowKnife", "MouseButton3"), "MouseButton3")
		local repaired = f.validation.ValidateAndRepair({ThrowKnife = "G", Stab = "Q", Emote = "G", Sprint = "MouseButton2"})
		local seen = {}; for action, key in pairs(repaired) do assert(not seen[key], action .. " duplicate"); seen[key] = true end
		equal(f.validation.ToDisplay("MouseButton3"), "MClick")
	end)
	test("keybind server persists supported remaps and rejects duplicate or reserved keys", function()
		local f = bindingFixture()
		f.modules[child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")] = f.validation
		local remote = child(child(f.remotes, "Folder", "Keybinds"), "RemoteEvent", "ChangeKeybind")
		f:load("KeybindServer", f.dataFolder)
		remote.OnServerEvent:Fire(f.player, "Stab", "T"); equal(f.player.leaderstats.KeyBinds.Stab.Value, "T")
		f.time += 1; remote.OnServerEvent:Fire(f.player, "ThrowKnife", "T"); equal(f.player.leaderstats.KeyBinds.ThrowKnife.Value, "E")
		f.time += 1; remote.OnServerEvent:Fire(f.player, "Sprint", "R"); equal(f.player.leaderstats.KeyBinds.Sprint.Value, "LeftShift")
	end)
	test("fixed F inspect cannot collide with saved combat or movement bindings", function()
		local f = bindingFixture()
		for _, action in ipairs(f.validation.GetActions()) do
			equal(f.validation.NormalizeForAction(action, "F"), nil)
		end
		local repaired = f.validation.ValidateAndRepair({ThrowKnife = "F", Reload = "T", ToogleCam = "Q"})
		equal(repaired.Reload, "T"); equal(repaired.ToogleCam, "Q")
		for _, key in pairs(repaired) do assert(key ~= "F") end
		f.modules[child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")] = f.validation
		local remote = child(child(f.remotes, "Folder", "Keybinds"), "RemoteEvent", "ChangeKeybind")
		f:load("KeybindServer", f.dataFolder)
		remote.OnServerEvent:Fire(f.player, "Reload", "F"); equal(f.player.leaderstats.KeyBinds.Reload.Value, "R")
	end)
	test("Reload and ToogleCam defaults migrate old profiles without losing a conflicting saved Q", function()
		local f = bindingFixture(); local defaults = f.validation.GetDefaults()
		equal(defaults.Reload, "R"); equal(defaults.ToogleCam, "Q")
		equal(f.validation.NormalizeForAction("Reload", "R"), "R")
		equal(f.validation.NormalizeForAction("ToogleCam", "MouseButton2"), nil)
		local migrated = f.validation.ValidateAndRepair({ThrowKnife = "Q"})
		equal(migrated.ThrowKnife, "Q"); equal(migrated.Reload, "R"); assert(migrated.ToogleCam ~= "Q")
		local seen = {}; for action, value in pairs(migrated) do assert(not seen[value], action); seen[value] = true end
	end)
	test("new keybind actions use server validation rate limits and the requesting player's values", function()
		local f = bindingFixture(); local other = f:createPlayer(2)
		f.modules[child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")] = f.validation
		local remote = child(child(f.remotes, "Folder", "Keybinds"), "RemoteEvent", "ChangeKeybind")
		f:load("KeybindServer", f.dataFolder)
		remote.OnServerEvent:Fire(f.player, "Reload", "T"); equal(f.player.leaderstats.KeyBinds.Reload.Value, "T")
		remote.OnServerEvent:Fire(f.player, "ToogleCam", "Y"); equal(f.player.leaderstats.KeyBinds.ToogleCam.Value, "Q")
		f.time += 0.25; remote.OnServerEvent:Fire(f.player, "ToogleCam", "Y"); equal(f.player.leaderstats.KeyBinds.ToogleCam.Value, "Y")
		f.time += 1; remote.OnServerEvent:Fire(f.player, "ToogleCam", "T"); equal(f.player.leaderstats.KeyBinds.ToogleCam.Value, "Y")
		f.time += 1; remote.OnServerEvent:Fire(f.player, "ToogleCam", "MouseButton1"); equal(f.player.leaderstats.KeyBinds.ToogleCam.Value, "Y")
		f.time += 1; remote.OnServerEvent:Fire(f.player, "Reload", "W"); equal(f.player.leaderstats.KeyBinds.Reload.Value, "T")
		f.time += 1; f.player:SetAttribute("DataReady", false)
		remote.OnServerEvent:Fire(f.player, "Reload", "R"); equal(f.player.leaderstats.KeyBinds.Reload.Value, "T")
		remote.OnServerEvent:Fire(other, "Reload", "R"); equal(f.player.leaderstats.KeyBinds.Reload.Value, "T")
	end)
	test("repair stays unique even when every previous fallback key is already assigned", function()
		local validation = bindingFixture().validation
		local saved, occupied = {}, {"Q", "T", "Y", "H", "J", "K", "L", "U", "B", "X", "X"}
		for i, action in ipairs(validation.GetActions()) do saved[action] = occupied[i] end
		local repaired, seen = validation.ValidateAndRepair(saved), {}
		for action, value in pairs(repaired) do
			assert(validation.NormalizeForAction(action,value) == value, action .. " unsupported")
			assert(not seen[value], action .. " duplicate"); seen[value] = true
		end
		equal(repaired.ToogleCam, "Z")
	end)
	test("Reload and ToogleCam flow through profile saves and join hydration", function()
		local validation = bindingFixture().validation
		local f = profileFixture(validation)
		local binds = child(f.player.leaderstats, "Folder", "KeyBinds")
		for action, value in pairs(validation.GetDefaults()) do child(binds, "StringValue", action, value) end
		binds.Reload.Value, binds.ToogleCam.Value = "T", "Y"
		f.profiles.SaveProfile(f.player)
		equal(f.profile.pending.KeyBinds.Reload, "T"); equal(f.profile.pending.KeyBinds.ToogleCam, "Y")
		local rejoin = playerStartupFixture(); rejoin.savedPlayerData = copyTable(f.profile.pending)
		rejoin.modules[rejoin.RS.KeyBinds.DefaultKeybinds] = validation.GetDefaults()
		rejoin.modules[rejoin.RS.KeyBinds.KeybindValidation] = validation
		local player = rejoin:newPlayer(1); rejoin:start()
		equal(player.leaderstats.KeyBinds.Reload.Value, "T"); equal(player.leaderstats.KeyBinds.ToogleCam.Value, "Y")
	end)
	test("joining migrates old X defaults once while preserving custom keys and Q conflicts", function()
		local validation = bindingFixture().validation
		for _, case in ipairs({{old = "X", expected = "Q"}, {old = "Y", expected = "Y"},
			{old = "X", version = 1, expected = "X"}, {old = "X", stab = "Q", expected = "X"}}) do
			local f = playerStartupFixture()
			f.savedPlayerData = {Cash = 700, XP = 150, Inventory = {},
				KeyBinds = {ToogleCam = case.old, Stab = case.stab}, KeybindDefaultsVersion = case.version}
			f.modules[f.RS.KeyBinds.DefaultKeybinds] = validation.GetDefaults()
			f.modules[f.RS.KeyBinds.KeybindValidation] = validation
			local player = f:newPlayer(1); f:start()
			equal(player.leaderstats.KeyBinds.ToogleCam.Value, case.expected)
			equal(f.savedPlayerData.KeyBinds.ToogleCam, case.expected); equal(f.savedPlayerData.KeybindDefaultsVersion, 1)
			if case.stab then equal(player.leaderstats.KeyBinds.Stab.Value, case.stab) end
		end
	end)
	local function cameraToggleFixture()
		local f = bindingFixture(); f.Players.LocalPlayer = f.player
		f.ui = {InputBegan = signal(), MouseIconEnabled = true, GetFocusedTextBox = function() return f.focused end}
		f.guiService, f.vr = {MenuIsOpen = false}, {VREnabled = false}
		f.bindings, f.bindCalls, f.nominalZoom = {}, 0, 8
		f.run = {}
		function f.run:BindToRenderStep(name, priority, fn)
			assert(not f.bindings[name]); f.bindings[name] = {priority = priority, fn = fn}; f.bindCalls += 1
		end
		function f.run:UnbindFromRenderStep(name) f.bindings[name] = nil end
		local originalService = f.game.GetService
		f.game.GetService = function(self, name)
			local services = {UserInputService = f.ui, GuiService = f.guiService, RunService = f.run, VRService = f.vr}
			return services[name] or originalService(self, name)
		end
		local positionMeta = {__sub = function(a, b) return {Magnitude = math.abs(a.distance - b.distance)} end}
		f.camera = {CameraType = "Custom", CameraSubject = f.player.Character.Humanoid,
			CFrame = {Position = setmetatable({distance = 8}, positionMeta)}, Focus = {Position = setmetatable({distance = 0}, positionMeta)}}
		f.workspace.CurrentCamera = f.camera
		f.cameraChanged = signal()
		f.workspace.GetPropertyChangedSignal = function() return f.cameraChanged end
		f.env.Enum.CameraMode, f.env.Enum.CameraType = {Classic = "Classic", LockFirstPerson = "LockFirstPerson"}, {Custom = "Custom"}
		f.env.Enum.RenderPriority = {Camera = {Value = 200}}
		f.player.CameraMode, f.player.CameraMinZoomDistance, f.player.CameraMaxZoomDistance = "Classic", 0.5, 16
		f.player.Character.Humanoid.Health = 100
		local function nativeClamp()
			f.nominalZoom = f.player.CameraMode == "LockFirstPerson" and 0.5
				or math.clamp(f.nominalZoom, f.player.CameraMinZoomDistance, f.player.CameraMaxZoomDistance)
		end
		for _, property in ipairs({"CameraMode", "CameraMinZoomDistance", "CameraMaxZoomDistance"}) do
			f.player:GetPropertyChangedSignal(property):Connect(nativeClamp)
		end
		f.config = f:load("CameraToggleConfig", f.modulesFolder)
		f.env.UDim2 = {fromOffset = function(x,y) return {X=x,Y=y} end}
		local client = child(f.RS, "Folder", "ToggleClient")
		f.clientModules = child(client, "Folder", "Modules")
		f:load("MouseVisibility", f.modulesFolder, "MouseCursorVisibility")
		f.menuCamera = f:load("MenuCamera", f.clientModules, "MenuCamera")
		f.toggle = f:load("CameraToggle", f.clientModules, "FirstPersonToggle"); f.toggle.Init()
		function f.press(key, processed)
			f.ui.InputBegan:Fire({UserInputType = f.env.Enum.UserInputType.Keyboard, KeyCode = f.env.Enum.KeyCode[key]}, processed or false)
		end
		function f.step()
			nativeClamp()
			for _, entry in pairs(table.clone(f.bindings)) do entry.fn() end
		end
		return f
	end
	test("camera toggle locks native first person blocks zoom-out and unlocks after exactly half a second", function()
		local f = cameraToggleFixture(); local cameraFrame = f.camera.CFrame
		f.press("Q"); equal(f.player.CameraMode, "LockFirstPerson"); equal(f.nominalZoom, 0.5)
		f.nominalZoom = 16; f.step(); equal(f.nominalZoom, 0.5); equal(f.player.CameraMinZoomDistance, 0.5)
		f.time += 0.499; f.press("Q"); equal(f.player.CameraMode, "LockFirstPerson")
		f.time += 0.001; f.press("Q"); equal(f.player.CameraMode, "Classic"); equal(f.nominalZoom, 8)
		equal(f.bindings.FirstPersonToggleZoomRestore.priority, 204)
		f.step(); equal(f.player.CameraMinZoomDistance, 0.5); equal(next(f.bindings), nil)
		f.nominalZoom = 12; f.step(); equal(f.nominalZoom, 12)
		equal(f.camera.CFrame, cameraFrame); equal(f.bindCalls, 1)
	end)
	test("camera toggle follows saved binding changes immediately while remaining locked", function()
		local f = cameraToggleFixture(); f.press("Q"); f.time += 1
		f.player.leaderstats.KeyBinds.ToogleCam.Value = "Y"
		f.press("Q"); equal(f.player.CameraMode, "LockFirstPerson")
		f.press("Y"); equal(f.player.CameraMode, "Classic"); f.step()
		f.time += 1; f.press("Y"); equal(f.player.CameraMode, "LockFirstPerson")
	end)
	local function cameraMenu(f)
		local gui=f.player.PlayerGui or child(f.player,"PlayerGui","PlayerGui")
		local main=child(gui,"ScreenGui","Main"); main.Enabled=true
		local frames=child(main,"Folder","Frames")
		local menu=child(frames,"Frame","Inventory"); menu.Visible=false
		return main,frames,menu
	end
	test("menus temporarily unlock first person and restore the camera preference on close", function()
		local f=cameraToggleFixture(); local main,_,menu=cameraMenu(f); f.press("Q")
		menu.Visible=true; equal(f.player.CameraMode,"Classic","menu opening"); equal(f.nominalZoom,8)
		-- Roblox can defer property signals until after the assignment returns.
		f.player:GetPropertyChangedSignal("CameraMode"):Fire()
		equal(main.MenuCursorRelease.Visible,true); equal(main.MenuCursorRelease.Modal,true); equal(f.ui.MouseIconEnabled,true)
		f.step(); equal(f.player.CameraMinZoomDistance,.5); f.nominalZoom=12; f.step(); equal(f.nominalZoom,12)
		menu.Visible=false; equal(f.player.CameraMode,"LockFirstPerson"); equal(main.MenuCursorRelease.Visible,false)
		f.time+=1; f.press("Q"); equal(f.player.CameraMode,"Classic","toggle after menu closing")
	end)
	test("manually zoomed first person can zoom out immediately after a menu opens", function()
		local f=cameraToggleFixture(); local _,_,menu=cameraMenu(f)
		f.camera.CFrame.Position.distance=.5; f.nominalZoom=.5; menu.Visible=true
		equal(f.player.CameraMode,"Classic"); equal(f.nominalZoom,8); f.step()
		f.nominalZoom=15; f.step(); equal(f.nominalZoom,15)
		menu.Visible=false; equal(f.player.CameraMode,"Classic"); equal(f.player.CameraMinZoomDistance,.5)
	end)
	test("overlapping and replaced menus keep one listener each and release on teardown", function()
		local f=cameraToggleFixture(); local main,frames,menu=cameraMenu(f); f.press("Q"); menu.Visible=true
		local trade=child(frames,"Frame","Trade"); trade.Visible=true; menu.Visible=false
		equal(f.player.CameraMode,"Classic"); equal(trade:GetPropertyChangedSignal("Visible"):Count(),1)
		main.Enabled=false; equal(f.player.CameraMode,"LockFirstPerson"); main.Enabled=true; equal(f.player.CameraMode,"Classic")
		f.toggle.Destroy(); equal(trade:GetPropertyChangedSignal("Visible"):Count(),0)
		equal(main:FindFirstChild("MenuCursorRelease"),nil); equal(f.player.CameraMinZoomDistance,.5)
	end)
	test("menu cursor visibility wins over weapon cursor owners and restores after release", function()
		local f=cameraToggleFixture(); local _,_,menu=cameraMenu(f)
		local cursor=f.modules[f.modulesFolder.MouseCursorVisibility]
		cursor.Acquire("weapon"); equal(f.ui.MouseIconEnabled,false)
		menu.Visible=true; equal(f.ui.MouseIconEnabled,true)
		cursor.Acquire("aim"); cursor.Release("weapon"); equal(f.ui.MouseIconEnabled,true)
		menu.Visible=false; equal(f.ui.MouseIconEnabled,false); cursor.Release("aim"); equal(f.ui.MouseIconEnabled,true)
	end)
	test("menus leave dead scripted spectator and VR camera zoom limits untouched", function()
		for _,reason in ipairs({"dead","scripted","spectator","vr"}) do
			local f=cameraToggleFixture(); local _,_,menu=cameraMenu(f)
			if reason=="dead" then f.player.Character.Humanoid.Health=0
			elseif reason=="scripted" then f.camera.CameraType="Scriptable"
			elseif reason=="spectator" then f.camera.CameraSubject={}
			else f.vr.VREnabled=true end
			f.player.CameraMode="LockFirstPerson"; menu.Visible=true
			equal(f.player.CameraMode,"LockFirstPerson"); equal(f.player.CameraMinZoomDistance,.5); equal(next(f.bindings),nil)
		end
	end)
	test("camera input ignores chat menus settings capture processed input and unready profiles", function()
		for _, gate in ipairs({"processed", "chat", "menu", "settings", "unready"}) do
			local f = cameraToggleFixture()
			if gate == "chat" then f.focused = {} elseif gate == "menu" then f.guiService.MenuIsOpen = true
			elseif gate == "unready" then f.player:SetAttribute("DataReady", false)
			elseif gate == "settings" then
				local main = child(child(f.player, "PlayerGui", "PlayerGui"), "ScreenGui", "Main")
				child(child(main, "Folder", "Frames"), "Frame", "KeybindEdit").Visible = true
			end
			f.press("Q", gate == "processed"); equal(f.player.CameraMode, "Classic"); equal(f.bindCalls, 0)
		end
	end)
	test("camera toggle leaves VR scripted spectator dead and ragdolled views alone", function()
		for _, gate in ipairs({"vr", "scripted", "spectating", "dead", "ragdoll"}) do
			local f = cameraToggleFixture()
			if gate == "vr" then f.vr.VREnabled = true elseif gate == "scripted" then f.camera.CameraType = "Scriptable"
			elseif gate == "spectating" then f.camera.CameraSubject = {}
			elseif gate == "dead" then f.player.Character.Humanoid.Health = 0
			else f.player.Character:SetAttribute("Ragdolled", true) end
			f.press("Q"); equal(f.player.CameraMode, "Classic"); equal(next(f.bindings), nil)
		end
	end)
	test("native first-person lock persists across respawn and adds no ordinary render work", function()
		local f = cameraToggleFixture(); f.press("Q")
		local root = child(f.player.Character, "Part", "HumanoidRootPart")
		root.CFrame, root.AssemblyLinearVelocity = "original", "original"
		f:character(f.player); f.camera.CameraSubject = f.player.Character.Humanoid
		f.player.Character.Humanoid.Health = 100
		for _ = 1, 100 do f.step() end
		equal(f.player.CameraMode, "LockFirstPerson"); equal(f.bindCalls, 0)
		equal(root.CFrame, "original"); equal(root.AssemblyLinearVelocity, "original")
		f.time += 1; f.press("Q"); equal(f.player.CameraMode, "Classic")
	end)
	test("unlock respects new zoom caps external zoom ownership and manual first-person entry", function()
		local f = cameraToggleFixture(); f.camera.CFrame.Position.distance = 0.5
		f.press("Q"); f.player.CameraMaxZoomDistance = 5; f.time += 1; f.press("Q")
		equal(f.nominalZoom, 5); equal(f.player.CameraMaxZoomDistance, 5)
		f.player.CameraMinZoomDistance = 2; f.step(); equal(f.player.CameraMinZoomDistance, 2)
	end)
	test("camera takeover cleanup and repeated initialization do not fight other camera controllers", function()
		local f = cameraToggleFixture(); f.toggle.Init(); equal(f.ui.InputBegan:Count(), 1)
		f.press("Q"); f.player.CameraMode = "Classic"
		f.toggle.Destroy(); equal(f.ui.InputBegan:Count(), 0); equal(f.player.CameraMode, "Classic")
		f.toggle.Init(); f.press("Q"); equal(f.player.CameraMode, "LockFirstPerson")
		f.toggle.Destroy(); equal(f.player.CameraMode, "Classic"); equal(next(f.bindings), nil)
	end)
	test("camera unlock during spectator takeover changes no scripted camera or zoom limits", function()
		local f = cameraToggleFixture(); f.press("Q"); f.time += 1
		f.camera.CameraType = "Scriptable"; local frame = f.camera.CFrame
		f.press("Q"); equal(f.player.CameraMode, "Classic"); equal(f.camera.CameraType, "Scriptable")
		equal(f.camera.CFrame, frame); equal(f.player.CameraMinZoomDistance, 0.5); equal(next(f.bindings), nil)
	end)
	test("standalone camera toggle initializer starts once and cleans up on destruction", function()
		local f = cameraToggleFixture(); f.toggle.Destroy()
		local initializer = child(f.clientModules.Parent, "LocalScript", "InitializeFirstPersonToggle")
		f.env.script = initializer; load("CameraToggleInitialize", f.env)
		equal(f.ui.InputBegan:Count(), 1); f.press("Q"); equal(f.player.CameraMode, "LockFirstPerson")
		initializer.Destroying:Fire(); equal(f.ui.InputBegan:Count(), 0); equal(f.player.CameraMode, "Classic")
	end)
	test("settings rows display and edit Reload and ToogleCam using the existing remote", function()
		local f = cameraToggleFixture(); f.ui.WindowFocusReleased = signal()
		local main = child(child(f.player, "PlayerGui", "PlayerGui"), "ScreenGui", "Main")
		local frames = child(main, "Folder", "Frames"); child(frames, "Frame", "Settings").Visible = false
		local frame = child(frames, "Frame", "KeybindEdit"); frame.Visible = true
		local container, editor = child(frame, "Frame", "Container"), child(frame, "Frame", "EditKeybindFrame")
		child(frame, "TextButton", "Exit"); child(frame, "TextButton", "Back")
		for _, action in ipairs({"Reload", "ToogleCam"}) do
			local row = child(container, "Frame", action); child(row, "TextButton", "EditKeybind")
			child(child(row, "Frame", "KeybindFrame"), "TextLabel", "TextLabel")
		end
		local remote = child(child(f.remotes, "Folder", "Keybinds"), "RemoteEvent", "ChangeKeybind")
		local originalService = f.game.GetService
		f.game.GetService = function(self, name) if name == "Lighting" then return object("Lighting") end; return originalService(self, name) end
		f.modules[child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")] = f.validation
		f:load("KeybindServer", f.dataFolder)
		remote.OnSend = function(...) remote.OnServerEvent:Fire(f.player, ...) end
		f:load("KeybindClient", f.clientModules.Parent)
		equal(container.Reload.KeybindFrame.TextLabel.Text, "R"); equal(container.ToogleCam.KeybindFrame.TextLabel.Text, "Q")
		container.Reload.EditKeybind.Activated:Fire(); f.press("T")
		equal(f.player.leaderstats.KeyBinds.Reload.Value, "T"); equal(container.Reload.KeybindFrame.TextLabel.Text, "T")
		equal(editor.Visible, false); equal(f.player.CameraMode, "Classic")
		f.time += 1; container.ToogleCam.EditKeybind.Activated:Fire(); f.press("Y")
		equal(f.player.leaderstats.KeyBinds.ToogleCam.Value, "Y"); equal(container.ToogleCam.KeybindFrame.TextLabel.Text, "Y")
		equal(f.player.CameraMode, "Classic"); frame.Visible = false; f.press("Y"); equal(f.player.CameraMode, "LockFirstPerson")
	end)
	test("knife input honors stab bind and processed release; rebinding cancels held charge", function()
		local f = bindingFixture(); f.Players.LocalPlayer = f.player
		f.player.leaderstats.KeyBinds.Stab.Value = "Q"
		f.ui = {InputBegan = signal(), InputEnded = signal(), WindowFocusReleased = signal(), TextBoxFocused = signal(), GetFocusedTextBox = function() end}
		f.guiService = {MenuOpened = signal(), MenuIsOpen = false}
		local original = f.game.GetService
		f.game.GetService = function(self, name) if name == "UserInputService" then return f.ui elseif name == "GuiService" then return f.guiService end; return original(self, name) end
		f.env.Enum.UserInputState = {Cancel = "Cancel", End = "End"}
		local client = child(f.RS, "Folder", "Client")
		f.begins, f.releases, f.cancels = 0, 0, 0
		f.modules[child(child(client, "Folder", "Modules"), "ModuleScript", "CombatController")] = {
			Init = function() end, BeginCharge = function() f.begins += 1; return true end,
			ReleaseCharge = function() f.releases += 1 end, CancelCharge = function() f.cancels += 1 end,
		}
		f:load("KnifeInput", client)
		local left = {UserInputType = f.env.Enum.UserInputType.MouseButton1}
		f.ui.InputBegan:Fire(left, false); equal(f.begins, 0)
		local q = {UserInputType = f.env.Enum.UserInputType.Keyboard, KeyCode = f.env.Enum.KeyCode.Q, UserInputState = "End"}
		f.ui.InputBegan:Fire(q, false); f.ui.InputEnded:Fire(q, true); equal(f.begins, 1); equal(f.releases, 1)
		f.ui.InputBegan:Fire(q, false); f.player.leaderstats.KeyBinds.Stab.Value = "T"; f.ui.InputEnded:Fire(q, false)
		equal(f.releases, 1); equal(f.cancels, 1)
	end)
	test("movement selection covers walk/sprint, crouch, slide, air and death", function()
		local state = load("MovementState")
		equal(state.Select("Running", true, false, false, false), "Walk")
		equal(state.Select("Running", true, true, false, false), "Run")
		equal(state.Select("Running", false, true, false, false), "Idle")
		equal(state.Select("Running", true, true, true, false), "CrouchWalk")
		equal(state.Select("Running", false, false, true, false), "CrouchIdle")
		equal(state.Select("Running", true, true, false, true), "Slide")
		equal(state.Select("Freefall", true, true, false, true), "Fall")
		equal(state.Select("Dead", true, true, false, false), nil)
	end)
	test("old character cleanup cannot erase a new sprint controller", function()
		local sprint = load("SprintState")
		local old, new = function(enabled) return enabled end, function(enabled) return enabled end
		sprint.SetController(old); sprint.SetController(new); sprint.ClearController(old)
		equal(sprint.SetEnabled(true), true); sprint.ClearController(new); equal(sprint.GetEnabled(), false)
	end)
	local vec, vecMeta = {}, {}
	function vec.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vecMeta) end
	function vec:Lerp(other, alpha) return self + (other - self) * alpha end
	vecMeta.__index = function(v, key) if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end; return vec[key] end
	vecMeta.__add = function(a, b) return vec.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
	vecMeta.__sub = function(a, b) return vec.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
	vecMeta.__mul = function(a, b) return vec.new(a.X*b, a.Y*b, a.Z*b) end
	vecMeta.__div = function(a, b) return vec.new(a.X/b, a.Y/b, a.Z/b) end
	vec.zero = vec.new()
	local function interactionFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		local gui = child(child(f.player, "Folder", "PlayerGui"), "ScreenGui", "Main")
		child(gui, "Folder", "Frames")
		f.ui = {InputBegan = signal(), InputEnded = signal(), WindowFocusReleased = signal(), TextBoxFocused = signal(), TouchTapInWorld = signal(), PreferredInput = "Touch", GetFocusedTextBox = function() return f.focused end,
			GetMouseLocation = function() return vec.new(200, 150) end, GetLastInputType = function() return f.inputType end, GetPropertyChangedSignal = function() return signal() end}
		f.guiService = {MenuOpened = signal(), MenuIsOpen = false, GetGuiInset = function() return vec.new(0, 36) end}
		f.events = {RenderStepped = signal(), Heartbeat = signal(), BindToRenderStep = function(_, _, _, fn) f.render = fn end}
		local original = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "UserInputService" then return f.ui elseif name == "GuiService" then return f.guiService elseif name == "RunService" then return f.events
			elseif name == "TweenService" then return {Create = function(_, instance, _, goals) return {Cancel = function() end, Play = function() for key, value in pairs(goals) do instance[key] = value end end} end} end
			return original(self, name)
		end
		f.env.Vector2, f.env.Vector3 = vec, vec
		f.env.Color3 = {new = vec.new, fromRGB = vec.new}
		f.env.UDim2 = {fromOffset = function(x, y) return {X = x, Y = y} end}
		f.env.TweenInfo = {new = function() return {} end}
		f.env.RaycastParams, f.env.OverlapParams = {new = function() return {} end}, {new = function() return {} end}
		f.env.Enum.UserInputType = {MouseButton1 = {Name = "MouseButton1"}, Touch = {Name = "Touch"}}
		f.env.Enum.RaycastFilterType = {Exclude = "Exclude", Include = "Include"}
		f.inputType = f.env.Enum.UserInputType.MouseButton1
		f.workspace = object("Workspace", "Workspace"); f.env.workspace = f.workspace
		f.workspace.CurrentCamera = {ViewportSize = vec.new(800, 600), ViewportPointToRay = function(_, x, y) f.rayPosition = {X = x, Y = y}; return {Origin = vec.zero, Direction = vec.new(0, 0, -1)} end}
		f.workspace.Raycast = function() return f.hit and {Instance = f.hit} end
		return f, gui
	end
	test("status listener connects before UI loading finishes and displays only the latest received status", function()
		local f, gui = interactionFixture(); local label = child(child(gui, "Frame", "SystemTexts"), "TextLabel", "Status")
		local remote = child(f.remotes, "RemoteEvent", "ChangeStatus")
		f.RS:SetAttribute("ServerReady", false)
		f.Players.LocalPlayer = {WaitForChild = function() coroutine.yield("UI"); return gui.Parent end}
		local thread = coroutine.create(function() f:load("StatusClient", child(f.RS, "Folder", "StatusTest")) end)
		local ok, reason = coroutine.resume(thread); assert(ok, reason); equal(reason, "UI")
		equal(remote.OnClientEvent:Count(), 1)
		for index = 1, 20 do remote.OnClientEvent:Fire("Status " .. index) end
		f.RS:SetAttribute("GameStatus", "VOTING"); f.RS:SetAttribute("ServerReady", true)
		assert(coroutine.resume(thread)); equal(label.Text, "VOTING")
	end)
	test("late clients read persisted status and a failed server shows a clear unavailable state", function()
		local f, gui = interactionFixture(); local label = child(child(gui, "Frame", "SystemTexts"), "TextLabel", "Status")
		child(f.remotes, "RemoteEvent", "ChangeStatus")
		f.RS:SetAttribute("GameStatus", "ROUND IN PROGRESS"); f.RS:SetAttribute("ServerReady", true)
		f:load("StatusClient", child(f.RS, "Folder", "StatusTest")); equal(label.Text, "ROUND IN PROGRESS")
		f.RS:SetAttribute("ServerStartupState", "Failed"); f.RS:SetAttribute("ServerReady", false)
		equal(label.Text, "SERVER COULD NOT START")
	end)
	test("tutorial waits for profile and server readiness and requests exactly once without a fixed sleep", function()
		for _, order in ipairs({"profileFirst", "serverFirst"}) do
			local f, gui = interactionFixture(); f.player:SetAttribute("DataReady", false); f.RS:SetAttribute("ServerReady", false)
			local frame = child(gui, "Frame", "TutorialFrame")
			local function buttons(parent)
				local holder = child(child(parent, "Frame", "Options"), "Frame", "Buttons")
				child(child(holder, "Frame", "StartFrame"), "TextButton", "Button")
				return holder
			end
			local options = buttons(child(frame, "Frame", "StartOptions")); child(child(options, "Frame", "DismissFrame"), "TextButton", "Button")
			for index = 1, 3 do buttons(child(frame, "Frame", "Page" .. index)) end
			local remote = child(child(f.remotes, "Folder", "Tutorial"), "RemoteEvent", "StartTutorial")
			f.env.task.wait = function() error("Tutorial must use readiness, not sleep") end
			f:load("TutorialClient", child(f.RS, "Folder", "TutorialTest")); equal(remote.ServerCalls, nil)
			if order == "profileFirst" then f.player:SetAttribute("DataReady", true) else f.RS:SetAttribute("ServerReady", true) end
			equal(remote.ServerCalls, nil)
			f.player:SetAttribute("DataReady", true); f.RS:SetAttribute("ServerReady", true); equal(remote.ServerCalls, 1)
			f.RS:SetAttribute("ServerReady", false); f.RS:SetAttribute("ServerReady", true); equal(remote.ServerCalls, 1)
		end
	end)
	test("tutorial service owns onboarding separately from profiles and only marks hydrated active sessions once", function()
		local f = startupFixture(); local player = f:createPlayer(1)
		local profile = {Data = {FirstTimePlaying = false}, IsActive = function() return true end}
		f.modules[child(f.dataFolder, "ModuleScript", "ProfileManager")] = {GetProfile = function() return profile end}
		local remote = child(child(f.remotes, "Folder", "Tutorial"), "RemoteEvent", "StartTutorial")
		f:load("TutorialService", f.servicesFolder)
		player:SetAttribute("DataReady", false); remote.OnServerEvent:Fire(player); equal(profile.Data.FirstTimePlaying, false)
		player:SetAttribute("DataReady", true); remote.OnServerEvent:Fire(player); remote.OnServerEvent:Fire(player)
		equal(profile.Data.FirstTimePlaying, true); equal(remote.ClientCalls, 1)
	end)
	test("admin panels catch up existing authorized players and cannot clone twice on overlapping startup events", function()
		local f = fixture(); f.env.task.spawn = function(fn, ...) fn(...) end
		local player = f:createPlayer(1); local other = f:createPlayer(2)
		local gui = child(player, "Folder", "PlayerGui"); child(other, "Folder", "PlayerGui")
		local admin = child(f.server, "Folder", "Admin")
		f.modules[child(admin, "ModuleScript", "VerifiedAdmins")] = {CheckAdmin = function(id) return id == 1 end}
		child(f.SS, "ScreenGui", "AdminFolder")
		f:load("AdminPanel", admin); f.Players.PlayerAdded:Fire(player)
		equal(#gui:GetChildren(), 1); equal(#other.PlayerGui:GetChildren(), 0)
	end)
	test("VIP startup catches existing players after hydration without racing extra refresh reads against profile data", function()
		local f = fixture(); f.env.task.spawn = function(fn, ...) fn(...) end
		local player = f:createPlayer(1); player:SetAttribute("DataReady", false)
		f.Marketplace.PromptProductPurchaseFinished = signal()
		local vip = child(child(child(f.remotes, "Folder", "ShopRemotes"), "Folder", "VIP"), "RemoteEvent", "VIPStatus")
		child(vip.Parent, "RemoteEvent", "BuyVIP")
		local reads, refreshes = 0, 0
		f.modules[child(f.servicesFolder, "ModuleScript", "VIPService")] = {
			GetVIPInfoByUserId = function() reads += 1; return false, 0 end,
			RefreshPlayer = function() refreshes += 1 end}
		f:load("VIPHandler", f.servicesFolder); vip.OnServerEvent:Fire(player, "REQUEST_STATUS")
		equal(reads, 0); equal(refreshes, 0)
		f.Players.PlayerAdded:Fire(player); player:SetAttribute("DataReady", true)
		equal(reads, 1); equal(vip.ClientCalls, 1); equal(refreshes, 0)
		f.Players.PlayerRemoving:Fire(player); equal(player:GetAttributeChangedSignal("DataReady"):Count(), 0)
	end)
	test("hitbox startup is idempotent and a delayed old root cannot replace the new character hitbox", function()
		local f = startupFixture(); f.env.Vector3 = vec; f.workspace = object("Workspace", "Workspace"); f.env.workspace = f.workspace
		local tags = {}
		local service = {AddTag = function(_, part) tags[part] = true end, HasTag = function(_, part) return tags[part] == true end}
		local getService = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "CollectionService" then return service elseif name == "RunService" then return {} end
			return getService(self, name)
		end
		local player = f:createPlayer(1); local old = player.Character; old.Parent = f.workspace
		rawset(old, "WaitForChild", function() coroutine.yield("root"); return old.HumanoidRootPart end)
		local hitboxes = f:load("PlayerHitbox", f.combatFolder); hitboxes.Init(); hitboxes.Init()
		equal(player.CharacterAdded:Count(), 1); equal(f.Players.PlayerAdded:Count(), 1); equal(#f.paused, 1)
		local replacement = f:character(player); replacement.Parent = f.workspace
		local root = child(replacement, "Part", "HumanoidRootPart"); root.CFrame = "new-frame"
		-- CharacterAdded ran before the mock root existed; publish it and use the normal hook again.
		player.CharacterAdded:Fire(replacement)
		local current = hitboxes.GetHitbox(player); assert(current); equal(current.Parent, replacement)
		child(old, "Part", "HumanoidRootPart").CFrame = "old-frame"
		f:resume(table.remove(f.paused, 1)); equal(hitboxes.GetHitbox(player), current)
		f.Players.PlayerRemoving:Fire(player); equal(player.CharacterAdded:Count(), 0); equal(hitboxes.GetHitbox(player), nil)
	end)
	local function hoverFixture()
		local f, gui = interactionFixture()
		f.frame = child(gui, "Frame", "PlayerHover"); f.frame.AbsoluteSize = vec.new(180, 75)
		child(f.frame, "TextLabel", "Username"); child(f.frame, "ImageLabel", "ProfileImage")
		local remotes = child(f.remotes, "Folder", "ProfileHandler")
		f.profileRequest = child(remotes, "RemoteEvent", "RequestViewProfile")
		f.active = child(f.RS, "BoolValue", "GameActive", false)
		f.other = f:createPlayer(2); f.other.Character.Parent = f.workspace
		local accessory = child(f.other.Character, "Model", "NestedAccessory")
		f.hit = child(accessory, "Part", "Handle")
		function f.Players:GetPlayerFromCharacter(character) for _, player in ipairs(self:GetPlayers()) do if player.Character == character then return player end end end
		f.thumbnailReads = 0
		function f.Players:GetUserThumbnailAsync(id) f.thumbnailReads += 1; return "thumbnail-" .. id end
		f.env.Enum.HighlightDepthMode = {Occluded = "Occluded"}
		f.env.Enum.ThumbnailType, f.env.Enum.ThumbnailSize = {HeadShot = "HeadShot"}, {Size150x150 = 150}
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.RaycastParams.new = function() f.hoverParams = (f.hoverParams or 0) + 1; return {} end
		local create = f.env.Instance.new; f.hoverCreates = 0
		f.env.Instance.new = function(class)
			if class == "Highlight" then f.hoverCreates += 1 end
			return create(class)
		end
		f:load("HoverConfig", f.modulesFolder, "PlayerHoverConfig"); f:load("Hover", child(f.RS, "Folder", "Client"))
		f.highlight = f.workspace.PlayerHoverHighlight_2
		function f:scan() self.events.Heartbeat:Fire(0.08) end
		return f
	end
	test("hover highlights nested player accessories without moving GUI or requesting thumbnails", function()
		local f = hoverFixture(); child(f.workspace, "Model", "Cargo Port"); f:scan()
		equal(f.highlight.Adornee, f.other.Character); equal(f.highlight.Enabled, true); equal(f.frame.Visible, false)
		for _ = 1, 10 do f:scan() end
		equal(#f.background, 0); equal(f.thumbnailReads, 0); equal(f.frame.Position, nil)
	end)
	test("hover opens a profile only on double-click and clears for combat, menus and death", function()
		local f = hoverFixture(); f:scan()
		local input = {UserInputType = f.env.Enum.UserInputType.MouseButton1}
		f.ui.InputBegan:Fire(input, false); equal(f.profileRequest.ServerCalls, nil)
		f.time += 0.2; f.ui.InputBegan:Fire(input, false); equal(f.profileRequest.ServerCalls, 1)
		f.active.Value = true; equal(f.highlight.Enabled, false); equal(f.frame.Visible, false)
		f.active.Value = false; f:scan(); f.other.Character.Humanoid.Died:Fire(); equal(f.highlight.Enabled, false)
		f.guiService.MenuIsOpen = true; f:scan(); equal(f.frame.Visible, false)
	end)
	test("changing hover targets creates no thumbnail jobs and enables only one prepared highlight", function()
		local f = hoverFixture(); f:scan()
		local third = f:createPlayer(3); third.Character.Parent = f.workspace; f.hit = child(third.Character, "Part", "Head")
		f.Players.PlayerAdded:Fire(third)
		f:scan(); equal(#f.background, 0); equal(f.thumbnailReads, 0)
		equal(f.highlight.Adornee, f.other.Character); equal(f.highlight.Enabled, false)
		equal(f.workspace.PlayerHoverHighlight_3.Adornee, third.Character); equal(f.workspace.PlayerHoverHighlight_3.Enabled, true)
		equal(f.other.Character.Humanoid.Died:Count(), 1)
	end)
	test("reward stand stays open while any limb overlaps and manual dismissal waits until leaving", function()
		local f, gui = interactionFixture()
		local selection = child(f.workspace, "Model", "Selection"); local touch = child(selection, "Part", "Touch")
		local decal = child(selection, "Decal", "Decal"); local frame = child(gui.Frames, "Frame", "Rewards"); frame.Visible = false
		local leg = child(f.player.Character, "Part", "Leg"); f.touching = true; f.opens = 0
		f.workspace.GetPartsInPart = function() return f.touching and {leg} or {} end
		local stand = f:load("RewardStand", child(f.RS, "Folder", "Client"))
		local hide = stand.Bind(selection, frame, function() f.opens += 1 end)
		touch.Touched:Fire(leg); equal(frame.Visible, true); equal(f.opens, 1)
		f.events.Heartbeat:Fire(0.2); equal(frame.Visible, true)
		hide(); touch.Touched:Fire(leg); equal(frame.Visible, false); equal(f.opens, 1)
		f.touching = false; f.events.Heartbeat:Fire(0.2)
		f.touching = true; touch.Touched:Fire(leg); equal(frame.Visible, true); equal(f.opens, 2)
	end)
	local function rewardStandFixture()
		local f, gui = interactionFixture()
		f.gui, f.opens, f.closes, f.ticks, f.queries, f.paramsCreated = gui, 0, 0, 0, 0, 0
		f.frame = child(gui.Frames, "Frame", "Rewards"); f.frame.Visible = false
		f.leg = child(f.player.Character, "Part", "Leg")
		f.env.task.defer = function(fn) table.insert(f.background, fn) end
		f.env.OverlapParams.new = function() f.paramsCreated += 1; return {} end
		f.workspace.GetPartsInPart = function(_, part, params)
			f.queries += 1; f.lastPart, f.lastParams = part, params
			return f.overlapping == part and {f.leg} or {}
		end
		f.stand = f:load("RewardStand", child(f.RS, "Folder", "StandTest"))
		function f:bind(selection)
			self.hide = self.stand.Bind(selection, self.frame, function() self.opens += 1 end,
				function() self.closes += 1 end, function() self.ticks += 1 end)
		end
		function f:bindLobby()
			self.hide = self.stand.BindLobby("1_Selection", self.frame, function() self.opens += 1 end,
				function() self.closes += 1 end, function() self.ticks += 1 end)
		end
		function f:flush()
			while #self.background > 0 do table.remove(self.background, 1)() end
		end
		return f
	end
	test("missing reward trigger never blocks GUI setup and binds a late nested part already overlapping the player", function()
		local f = rewardStandFixture(); local selection = child(f.workspace, "Model", "Selection")
		child(selection, "Part", "Decoration")
		selection.WaitForChild = function() error("Stand binding must not yield") end
		f:bind(selection); equal(type(f.hide), "function"); equal(f.queries, 0)
		f.frame.Visible = true; equal(f.opens, 1)
		f.events.Heartbeat:Fire(1); equal(f.frame.Visible, true); equal(f.ticks, 1); equal(f.queries, 0)
		f.hide(); equal(f.frame.Visible, false)
		local holder = child(selection, "Model", "Holder"); local touch = child(holder, "Part", "Touch")
		f.overlapping = touch; selection.DescendantAdded:Fire(touch)
		equal(f.frame.Visible, true); equal(f.opens, 2); equal(touch.Touched:Count(), 1)
	end)
	test("reward trigger lookup accepts nested BaseParts and skips non-part objects named Touch", function()
		local f = rewardStandFixture(); local selection = child(f.workspace, "Model", "Selection")
		child(selection, "Folder", "Touch")
		local touch = child(child(selection, "Model", "Holder"), "MeshPart", "Touch")
		f:bind(selection); equal(f.lastPart, touch)
		touch.Touched:Fire(f.leg); equal(f.frame.Visible, true)
	end)
	test("a reward selection part itself is the trigger, with a named child taking priority when present", function()
		local f = rewardStandFixture(); local selection = child(f.workspace, "Part", "Selection")
		f:bind(selection); equal(selection.Touched:Count(), 1); equal(f.lastPart, selection)
		selection.Touched:Fire(f.leg); equal(f.frame.Visible, true)
		local touch = child(selection, "Part", "Touch"); selection.DescendantAdded:Fire(touch)
		equal(selection.Touched:Count(), 0); equal(touch.Touched:Count(), 1)
		selection.Touched:Fire(f.leg); equal(f.frame.Visible, false)
		touch.Touched:Fire(f.leg); equal(f.frame.Visible, true)
	end)
	test("streaming out a reward trigger disconnects it and its replacement binds exactly once", function()
		local f = rewardStandFixture(); local selection = child(f.workspace, "Model", "Selection")
		local touch = child(selection, "Part", "Touch"); f:bind(selection)
		touch.Touched:Fire(f.leg); equal(f.frame.Visible, true)
		selection.DescendantRemoving:Fire(touch); touch.Parent = nil
		equal(f.frame.Visible, false); equal(touch.Touched:Count(), 0)
		local replacement = child(selection, "Part", "Touch"); selection.DescendantAdded:Fire(replacement)
		f:flush(); equal(replacement.Touched:Count(), 1)
		touch.Touched:Fire(f.leg); equal(f.frame.Visible, false)
		replacement.Touched:Fire(f.leg); equal(f.frame.Visible, true)
	end)
	test("reward lobby binding follows a delayed lobby and reconnects after the whole stand is replaced", function()
		local f = rewardStandFixture(); f.workspace.WaitForChild = function() error("Lobby binding must not yield") end
		f:bindLobby(); equal(type(f.hide), "function"); equal(f.queries, 0)
		local lobby = child(f.workspace, "Model", "IntermissionMap")
		local selection = child(lobby, "Part", "1_Selection")
		selection.Touched:Fire(f.leg); equal(f.frame.Visible, true); equal(selection.Touched:Count(), 1)
		lobby.Parent = nil; equal(f.frame.Visible, false); equal(selection.Touched:Count(), 0)
		local replacement = child(f.workspace, "Model", "IntermissionMap")
		local newPad = child(replacement, "Part", "1_Selection")
		equal(f.workspace.ChildAdded:Count(), 1); equal(replacement.ChildAdded:Count(), 1)
		selection.Touched:Fire(f.leg); equal(f.frame.Visible, false)
		newPad.Touched:Fire(f.leg); equal(f.frame.Visible, true); equal(f.opens, 2)
	end)
	test("reward overlap monitoring reuses parameters and updates the character filter after respawn", function()
		local f = rewardStandFixture(); local selection = child(f.workspace, "Part", "Selection")
		f:bind(selection); local params = f.lastParams; equal(f.paramsCreated, 1)
		local other = f:createPlayer(2); selection.Touched:Fire(child(other.Character, "Part", "Leg"))
		equal(f.frame.Visible, false)
		f.overlapping = selection; selection.Touched:Fire(f.leg)
		for _ = 1, 10 do f.events.Heartbeat:Fire(0.2) end
		equal(f.paramsCreated, 1); equal(f.lastParams, params); equal(params.FilterDescendantsInstances[1], f.player.Character)
		f:character(f.player); f.leg = child(f.player.Character, "Part", "Leg")
		selection.Touched:Fire(f.leg); f.events.Heartbeat:Fire(0.2)
		equal(f.lastParams, params); equal(params.FilterDescendantsInstances[1], f.player.Character)
	end)
	test("reward binding ignores unrelated Workspace changes and performs no idle overlap queries", function()
		local f = rewardStandFixture(); local lobby = child(f.workspace, "Model", "IntermissionMap")
		local selection = child(lobby, "Model", "1_Selection"); local touch = child(selection, "Part", "Touch")
		f:bindLobby(); local queries = f.queries
		for _ = 1, 100 do f.events.Heartbeat:Fire(0.2) end
		local unrelated = child(f.workspace, "Model", "Unrelated"); unrelated.Parent = nil
		equal(f.queries, queries); equal(touch.Touched:Count(), 1)
		local decal = child(selection, "Decal", "LateDecal"); selection.DescendantAdded:Fire(decal)
		equal(decal.Color3.Y, 205); touch.Touched:Fire(f.leg); equal(decal.Color3.Y, 152)
	end)
	test("destroying a rewards frame disconnects path, trigger and tick listeners and cancels deferred rebinds", function()
		local f = rewardStandFixture(); local lobby = child(f.workspace, "Model", "IntermissionMap")
		local selection = child(lobby, "Model", "1_Selection"); local touch = child(selection, "Part", "Touch")
		f:bindLobby(); touch.Touched:Fire(f.leg)
		selection.DescendantRemoving:Fire(touch); touch.Parent = nil
		f.frame.Destroying:Fire(); f:flush()
		equal(touch.Touched:Count(), 0); equal(f.events.Heartbeat:Count(), 0)
		equal(f.workspace.ChildAdded:Count(), 0); equal(lobby.ChildAdded:Count(), 0)
		equal(selection.DescendantAdded:Count(), 0); equal(f.player.CharacterRemoving:Count(), 0)
		local replacement = child(selection, "Part", "Touch"); selection.DescendantAdded:Fire(replacement)
		equal(replacement.Touched:Count(), 0)
	end)
	test("daily rewards and quests clients finish close-button and refresh setup even without lobby geometry", function()
		for _, name in ipairs({"DailyRewardsClient", "QuestsClient"}) do
			local f = rewardStandFixture(); f.frame:Destroy()
			local client = child(f.RS, "Folder", "Client")
			f.modules[child(child(client, "Folder", "Modules"), "ModuleScript", "RewardStand")] = f.stand
			local templates = child(f.RS, "Folder", "UITemplates")
			local frame, request
			if name == "DailyRewardsClient" then
				for _, info in ipairs({"RarityColor", "KnivesInfo", "Emotes"}) do f.modules[child(f.modulesFolder, "ModuleScript", info)] = {} end
				frame = child(f.gui.Frames, "Frame", "DailyRewards"); frame.Visible = false
				child(child(frame, "Frame", "DailyRewardsHolder"), "ScrollingFrame", "Scroll")
				child(templates, "Folder", "DailyRewardTemplates")
				local remotes = child(f.remotes, "Folder", "DailyRewards")
				request = child(remotes, "RemoteEvent", "ClaimDailyReward"); child(remotes, "RemoteEvent", "DailyRewardClient")
			else
				frame = child(f.gui.Frames, "Frame", "Quests"); frame.Visible = false
				child(child(frame, "Frame", "QuestsHolder"), "ScrollingFrame", "Scroll")
				child(child(frame, "Frame", "Top"), "TextLabel", "Text")
				child(child(templates, "Folder", "QuestTemplates"), "Frame", "QuestTemplate")
				local remotes = child(f.remotes, "Folder", "Quests")
				request = child(remotes, "RemoteEvent", "RequestQuests"); child(remotes, "RemoteEvent", "ClaimQuestReward")
			end
			local close = child(frame, "TextButton", "Close")
			f.player:SetAttribute("DataReady", false)
			f.workspace.WaitForChild = function() error("Reward client must not wait for lobby geometry") end
			f:load(name, client); equal(close.Activated:Count(), 1)
			f:flush(); equal(request.ServerCalls, 1)
			f.time += 1; f.player:SetAttribute("DataReady", true); equal(request.ServerCalls, 2)
			frame.Visible = true; close.Activated:Fire(); equal(frame.Visible, false)
		end
	end)
	local function mobileFixture()
		local f, gui = interactionFixture()
		f.mobileFrame = child(gui, "Frame", "MobileFrame")
		local controls = child(f.mobileFrame, "Frame", "BasicControls")
		for _, name in ipairs({"Throw", "Sprint", "Emote", "Jump"}) do child(child(controls, "ImageButton", name), "ImageLabel", "deco") end
		child(child(f.mobileFrame, "ImageButton", "ShiftLock"), "ImageLabel", "deco")
		child(f.mobileFrame, "ImageLabel", "ShiftLockToogled"); child(f.mobileFrame, "ImageLabel", "MobileCrosshair")
		child(child(gui, "Frame", "EmoteFrame"), "Frame", "background")
		child(f.RS, "BoolValue", "GameActive", true)
		f.player:SetAttribute("InRound", true); child(f.player.Character, "Tool", "KnifeA")
		f.modules[child(f.modulesFolder, "ModuleScript", "KnivesInfo")] = {KnifeA = {}}
		local client = child(f.RS, "Folder", "Client"); local modules = child(client, "Folder", "Modules")
		f.begins, f.releases, f.cancels, f.stabs, f.shots = 0, 0, 0, 0, 0
		f.modules[child(modules, "ModuleScript", "CombatController")] = {
			Init = function() end, BeginCharge = function() f.begins += 1; return true end,
			ReleaseCharge = function() f.releases += 1 end, CancelCharge = function() f.cancels += 1 end,
			SetTouchAimPosition = function(pos) f.aimPosition = pos end,
			SetMobileShiftLock = function(enabled) f.shifted = enabled end, SetInputMode = function(mode) f.touchMode = mode end,
			Stab = function() f.stabs += 1 end,
		}
		f.modules[child(modules, "ModuleScript", "RevolverController")] = {
			HasRevolverEquipped = function() return f.revolverEquipped end,
			SetMobileShiftLock = function() end, IsAiming = function() return false end,
			Fire = function(pos) f.shots += 1; f.shotPosition = pos end,
		}
		f.env.Enum.PreferredInput = {Touch = "Touch", KeyboardAndMouse = "Desktop"}
		f.env.Enum.RenderPriority, f.env.Enum.UserInputState = {Camera = {Value = 200}}, {Cancel = "Cancel"}
		f.preferredChanged = signal(); f.ui.GetPropertyChangedSignal = function() return f.preferredChanged end
		f:load("Mobile", client)
		f.throwButton = controls.Throw
		return f
	end
	test("mobile charge belongs to the THROW button's finger, including release outside the button", function()
		local f = mobileFixture(); equal(f.mobileFrame.Visible, true); equal(f.mobileFrame.MobileCrosshair.Visible, false)
		local finger = {UserInputType = f.env.Enum.UserInputType.Touch}
		f.ui.InputBegan:Fire(finger, false); equal(f.begins, 0, "Camera touches must not charge")
		f.throwButton.InputBegan:Fire(finger); equal(f.begins, 1)
		f.ui.InputEnded:Fire({UserInputType = f.env.Enum.UserInputType.Touch}); equal(f.releases, 0)
		f.ui.InputEnded:Fire(finger); equal(f.releases, 1)
	end)
	test("mobile UI taps cannot shoot; world taps stab/shoot and shift lock uses centered aim", function()
		local f = mobileFixture(); local pos = vec.new(260, 180)
		f.ui.TouchTapInWorld:Fire(pos, true); equal(f.stabs, 0)
		f.ui.TouchTapInWorld:Fire(pos, false); equal(f.stabs, 1)
		f.revolverEquipped = true; f.ui.TouchTapInWorld:Fire(pos, false); equal(f.shots, 1); equal(f.shotPosition, pos)
		f.mobileFrame.ShiftLock.Activated:Fire(); f.ui.TouchTapInWorld:Fire(pos, false)
		equal(f.shifted, true); equal(f.shotPosition, nil)
	end)
	test("mobile/keyboard switching and focus loss cancel charges without firing", function()
		local f = mobileFixture(); local finger = {UserInputType = f.env.Enum.UserInputType.Touch}
		f.throwButton.InputBegan:Fire(finger); f.ui.WindowFocusReleased:Fire(); f.ui.InputEnded:Fire(finger)
		equal(f.releases, 0)
		f.throwButton.InputBegan:Fire(finger); f.ui.PreferredInput = "Desktop"; f.preferredChanged:Fire()
		equal(f.mobileFrame.Visible, false); equal(f.touchMode, false); f.ui.InputEnded:Fire(finger); equal(f.releases, 0)
	end)
	local function movementFixture(unloadedWalk)
		local f, gui = interactionFixture()
		f.events.PreSimulation = signal()
		f:load("MovementConfig", f.modulesFolder); f:load("MovementState", f.modulesFolder, "MovementAnimationState")
		f:load("FirstPersonCameraConfig", f.modulesFolder)
		f.sprint = f:load("SprintState", f.modulesFolder)
		f.modules[child(f.modulesFolder, "ModuleScript", "KeybindValidation")] = {ToEnum = function(value) return value end}
		-- Terrain/constraint behavior is exercised by movement-slide.spec.luau;
		-- this fixture covers the animation/input controller's integration.
		f.modules[child(f.modulesFolder, "ModuleScript", "SlideController")] = {new = function()
			f.slide = {Speed = 32, Active = false}
			function f.slide:Start() self.Active = true; return true end
			function f.slide:Step() return self.Active end
			function f.slide:Stop() self.Active = false end
			function f.slide:Destroy() self.Active, self.Destroyed = false, true end
			return f.slide
		end}
		local binds = child(f.player.leaderstats, "Folder", "KeyBinds")
		child(binds, "StringValue", "Sprint", "LeftShift"); child(binds, "StringValue", "Crouch", "LeftControl"); child(binds, "StringValue", "Slide", "C")
		child(child(child(gui, "Frame", "MobileFrame"), "Frame", "BasicControls"), "ImageButton", "Sprint")
		f.humanoid = f.player.Character.Humanoid
		f.humanoid.Health, f.humanoid.MoveDirection, f.humanoid.FloorMaterial = 100, vec.zero, "Ground"
		function f.humanoid:GetState() return {Name = f.humanoidState or "Running"} end
		f.root = child(f.player.Character, "Part", "HumanoidRootPart"); f.root.AssemblyLinearVelocity = vec.zero
		local animator = child(f.humanoid, "Animator", "Animator")
		f.loaded = {}
		function animator:LoadAnimation(animation)
			local track = {Length = (unloadedWalk and animation.AnimationId == "rbxassetid://79598872056948") and 0 or 1, IsPlaying = false, id = animation.AnimationId, plays = 0}
			function track:Play() self.IsPlaying = true; self.plays += 1 end
			function track:AdjustSpeed(speed) self.PlaybackSpeed = speed end
			function track:Stop() self.IsPlaying = false end
			function track:Destroy() self.IsPlaying, self.destroyed = false, true end
			f.loaded[animation.AnimationId] = track
			return track
		end
		f.actions = {}
		f.cas = {UnbindAction = function(_, name) f.actions[name] = nil end, BindActionAtPriority = function(_, name, fn) f.actions[name] = fn end}
		local original = f.game.GetService
		f.game.GetService = function(self, name) if name == "ContextActionService" then return f.cas end; return original(self, name) end
		f.env.Enum.AnimationPriority = {Idle = "Idle", Movement = "Movement", Action = "Action"}
		f.env.Enum.UserInputState = {Begin = "Begin", End = "End", Cancel = "Cancel"}
		f.env.Enum.ContextActionResult, f.env.Enum.ContextActionPriority, f.env.Enum.Material = {Pass = "Pass", Sink = "Sink"}, {High = {Value = 100}}, {Air = "Air"}
		f:load("Movement", f.player.Character, "Animation")
		return f
	end
	test("movement controller uses replicated animator and recovers stopped walking/sprinting without a new Running event", function()
		local f = movementFixture(); local walk, run = f.loaded["rbxassetid://79598872056948"], f.loaded["rbxassetid://117319187680453"]
		f.humanoid.MoveDirection, f.root.AssemblyLinearVelocity = vec.new(1, 0, 0), vec.new(16, 0, 0)
		f.humanoid.Running:Fire(16); equal(walk.IsPlaying, true); equal(walk.Priority, "Movement")
		f.actions.SprintAction("SprintAction", "Begin"); equal(run.IsPlaying, true); equal(f.humanoid.WalkSpeed, 32)
		run.IsPlaying = false; f.events.Heartbeat:Fire(0.25); equal(run.IsPlaying, true)
		f.humanoid.Died:Fire(); equal(next(f.actions), nil); equal(run.destroyed, true); equal(f.events.Heartbeat:Count(), 0)
		equal(f.slide.Destroyed, true); equal(f.events.PreSimulation:Count(), 0)
	end)
	test("movement publishes crouch and slide camera posture from the selected animation and clears it on air death and focus loss", function()
		local f = movementFixture(); local attribute = "FirstPersonMovementPosture"
		equal(f.player.Character:GetAttribute(attribute), "Stand")
		f.actions.CrouchAction("CrouchAction", "Begin"); equal(f.player.Character:GetAttribute(attribute), "Crouch")
		f.humanoidState = "Freefall"; f.humanoid.FloorMaterial = "Air"; f.humanoid.StateChanged:Fire()
		equal(f.player.Character:GetAttribute(attribute), "Stand")
		f.humanoidState = "Running"; f.humanoid.FloorMaterial = "Ground"; f.humanoid.StateChanged:Fire()
		equal(f.player.Character:GetAttribute(attribute), "Crouch")
		f.ui.WindowFocusReleased:Fire(); equal(f.player.Character:GetAttribute(attribute), "Stand")
		f.actions.SprintAction("SprintAction", "Begin"); f.actions.SlideAction("SlideAction", "Begin")
		equal(f.player.Character:GetAttribute(attribute), "Slide")
		f.humanoidState = "Dead"; f.humanoid.Died:Fire(); equal(f.player.Character:GetAttribute(attribute), "Stand")
	end)
	test("movement blends a small step through Freefall but jump cancels slide immediately", function()
		local f = movementFixture(); local attribute = "FirstPersonMovementPosture"
		f.actions.SprintAction("SprintAction", "Begin"); f.actions.SlideAction("SlideAction", "Begin")
		equal(f.slide.Active, true)
		local track = f.loaded["rbxassetid://75213495477739"]
		equal(track.PlaybackSpeed, track.Length / 0.8)
		f.humanoidState, f.humanoid.FloorMaterial = "Freefall", "Air"; f.humanoid.StateChanged:Fire()
		equal(f.player.Character:GetAttribute(attribute), "Slide")
		f.humanoidState = "Jumping"; f.humanoid.StateChanged:Fire()
		equal(f.slide.Active, false); equal(f.player.Character:GetAttribute(attribute), "Stand")
		equal(f.humanoid.WalkSpeed, 32)
	end)
	test("movement retries unloaded custom assets then uses a bounded R6 fallback", function()
		local f = movementFixture(true)
		f.humanoid.MoveDirection, f.root.AssemblyLinearVelocity = vec.new(1, 0, 0), vec.new(16, 0, 0)
		local original = f.loaded["rbxassetid://79598872056948"]
		f.time += 9; f.events.Heartbeat:Fire(0.25); equal(original.destroyed, true)
		f.time += 9; f.events.Heartbeat:Fire(0.25)
		local fallback = f.loaded["rbxassetid://180426354"]; assert(fallback); equal(fallback.IsPlaying, true)
		f.time += 100; f.events.Heartbeat:Fire(0.25); equal(f.loaded["rbxassetid://180426354"], fallback)
	end)
	local function roundFixture()
		local f = mapFixture()
		f.Players.CharacterAutoLoads, f.Players.RespawnTime = true, 5
		local deathFolder = child(f.server, "Folder", "CharacterDeath")
		f.ragdollCalls, f.impacts = {}, {}
		f.modules[child(deathFolder, "ModuleScript", "RagdollService")] = {
			Prepare = function(character) character.Humanoid.BreakJointsOnDeath = false end,
			SetImpact = function(character, kind, direction) f.impacts[character] = {Kind = kind, Direction = direction} end,
			ClearImpact = function(character) f.impacts[character] = nil end,
			OnDeath = function(character) f.ragdollCalls[character] = (f.ragdollCalls[character] or 0) + 1 end,
		}
		local start = child(f.remotes, "Folder", "StartGameClient")
		child(start, "RemoteEvent", "RecieveTools"); child(start, "RemoteEvent", "WipeTools")
		f.results = child(child(f.remotes, "Folder", "RoundResults"), "RemoteEvent", "GetRoundResults")
		f.killSound = child(child(f.remotes, "Folder", "Knife"), "RemoteEvent", "PlayerGotKilledRemote")
		f.countdown = child(f.remotes, "RemoteEvent", "RoundCountdown")
		f.countdown.OnFireAll = function(phase)
			if phase == "fight" then
				assert(not f.main.GameActive and f.player.Character.LastPivot, "Countdown must follow placement")
				if f.onCountdown then f.onCountdown() end
			end
		end
		f.active = child(f.RS, "BoolValue", "GameActive", false); child(f.RS, "IntValue", "Timer", 0)
		f.modules[child(f.modulesFolder, "ModuleScript", "KnivesInfo")] = {}
		f.modules[child(f.modulesFolder, "ModuleScript", "TimeToMinutes")] = {MakeTimeMinute = tostring}
		f.modes = f:load("Modes", f.modulesFolder, "GameModes"); f.modes.FFA.RoundDuration = 1
		f.handler = {MinimumPlayers = 2, ChangeStatus = function(status) f.status = status end}
		f.modules[child(f.gameFolder, "ModuleScript", "RoundHandler")] = f.handler
		f.zone = {StopZone = function() f.stops = (f.stops or 0) + 1 end, NotifyPlayer = function() end,
			SpawnZone = function() return not f.missingZone end, StartZone = function() end}
		f.modules[child(f.gameFolder, "ModuleScript", "GameZone")] = f.zone
		f.rewards = {XpReward = function() f.rewardCalls = (f.rewardCalls or 0) + 1; return 1 end,
			CashReward = function() f.rewardCalls = (f.rewardCalls or 0) + 1; return 2 end}
		f.modules[child(f.gameFolder, "ModuleScript", "GameReward")] = f.rewards
		f.modules[child(f.gameFolder, "ModuleScript", "AntiFarm")] = {GetRewardPolicy = function() return {RewardMultiplier = 1, CanReceiveWinCredit = true} end}
		f.progress = {}
		f.modules[child(f.servicesFolder, "ModuleScript", "QuestsHandler")] = {AddProgress = function(player, kind, amount)
			f.progress[kind] = (f.progress[kind] or 0) + amount
		end}
		f.profiles = {}
		f.modules[child(f.dataFolder, "ModuleScript", "ProfileManager")] = {GetProfile = function(player) return f.profiles[player] end,
			SaveProfile = function() f.saves = (f.saves or 0) + 1 end}
		local lobbySpawns = child(child(f.lobby, "Folder", "Lobby"), "Folder", "Spawns")
		for index = 1, 4 do child(lobbySpawns, "Part", tostring(index)).CFrame = f.env.CFrame.new(0, 0, 0) end
		f.env.task.spawn = function(fn, ...) local args = {...}; table.insert(f.background, function() fn(table.unpack(args)) end) end
		f.deferred = {}; f.env.task.defer = function(fn) table.insert(f.deferred, fn) end
		f.main = f:load("MainGame", f.gameFolder)
		for id = 1, 3 do
			local player = f:createPlayer(id)
			for _, stat in ipairs({"Kills", "Deaths", "Wins", "WinStreak", "XP"}) do child(player.leaderstats, "IntValue", stat, 0) end
			child(child(player.leaderstats, "Folder", "Settings"), "BoolValue", "LobbyMode", false)
			f.profiles[player] = {Data = {}, IsActive = function() return true end}
			local function configureCharacter(character)
				character.Humanoid.Health = 100
				child(character, "Part", "HumanoidRootPart").CFrame = f.env.CFrame.new(0,0,0)
				function character.Humanoid:TakeDamage(damage)
					if f.blockDamage then return end
					self.Health = math.max(0, self.Health - damage)
					if self.Health == 0 and f.inlineDeath then self.Died:Fire() end
				end
				character.Humanoid.Died:Connect(function() f.main.OnDeath(player, character) end)
			end
			configureCharacter(player.Character)
			player.CharacterAdded:Connect(function(character) f.main.OnCharacterAdded(player); configureCharacter(character) end)
			function player:LoadCharacter() self.loads = (self.loads or 0) + 1; f:character(self) end
		end
		f.player, f.victim, f.third = f.Players:GetPlayerByUserId(1), f.Players:GetPlayerByUserId(2), f.Players:GetPlayerByUserId(3)
		function f.prepare(respawns)
			f.main.RoundId += 1; f.main.GameActive, f.active.Value, f.Players.CharacterAutoLoads = true, true, false
			f.main.CurrentMode = respawns and f.modes.FFA or f.modes.BattleRoyale
			f.main.CurrentMap = "MapA"; f.maps.Spawn("MapA")
			f.main.RoundStats = {startCount = 3, players = {}, mode = f.main.CurrentMode, rewardsApplied = false}
			for _, player in ipairs(f.Players:GetPlayers()) do
				f.main.PlayersInGame[player.UserId] = true
				f.main.RoundStats.players[player.UserId] = {kills = 0, rewardGold = 0, rewardXp = 0}
				player:SetAttribute("InRound", true); player:SetAttribute("CurrentRoundParticipant", true)
			end
		end
		return f
	end
	test("lethal damage commits one kill/death before deferred reward work and duplicate Died", function()
		for _, inline in ipairs({false, true}) do
			local f = roundFixture(); f.prepare(false); f.inlineDeath = inline
			equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100), 100)
			f.victim.Character.Humanoid.Died:Fire()
			equal(f.player.leaderstats.Kills.Value, 1); equal(f.victim.leaderstats.Deaths.Value, 1)
			equal(f.main.RoundStats.players[1].kills, 1); equal(f.main.PlayersInGame[2], nil)
			equal(f.progress.KILLS, 1); equal(f.rewardCalls, nil); equal(#f.deferred, 1); equal(#f.delayed, 1)
		end
	end)
	test("death presentation and quest failures cannot block FFA or BR respawn and killcam", function()
		for _,respawns in ipairs({false,true}) do
			for _,failure in ipairs({"ragdoll","quests"}) do
				local f=roundFixture(); f.prepare(respawns)
				if failure=="ragdoll" then
					f.modules[f.server.CharacterDeath.RagdollService].OnDeath=function() error("simulated ragdoll failure") end
				else
					f.modules[f.servicesFolder.QuestsHandler].AddProgress=function() error("simulated quest failure") end
				end
				f.main.DamagePlayer(f.player,f.victim,f.victim.Character.Humanoid,100)
				equal(#f.delayed,1); equal(f.remotes.KillCam.ClientCalls,1)
				f.delayed[1].fn(); equal(f.victim.loads,1)
			end
		end
	end)
	test("an eliminated player dying again in the lobby still receives one manual respawn", function()
		local f=roundFixture(); f.prepare(false)
		f.main.DamagePlayer(f.player,f.victim,f.victim.Character.Humanoid,100)
		f.delayed[1].fn(); equal(f.victim.loads,1)
		f.victim.Character.Humanoid.Health=0; f.main.OnDeath(f.victim,f.victim.Character)
		f.main.OnDeath(f.victim,f.victim.Character); equal(#f.delayed,2)
		f.delayed[2].fn(); equal(f.victim.loads,2)
	end)
	test("nonlethal, blocked, protected, stale-character and nonparticipant damage cannot grant kills", function()
		local f = roundFixture(); f.prepare(true)
		equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 50), 50)
		equal(f.player.leaderstats.Kills.Value, 0)
		f.blockDamage = true; equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100), 0)
		f.victim.Character.Humanoid.Health = 0; f.main.OnDeath(f.victim, f.victim.Character)
		equal(f.player.leaderstats.Kills.Value, 0, "blocked lethal damage cannot leave pending credit")
		local protected = roundFixture(); protected.prepare(true)
		child(protected.victim.Character, "ForceField", "ForceField")
		equal(protected.main.DamagePlayer(protected.player, protected.victim, protected.victim.Character.Humanoid, 100), 0)
		local old = protected.victim.Character; protected.victim:LoadCharacter()
		equal(protected.main.DamagePlayer(protected.player, protected.victim, old.Humanoid, 100), 0)
		protected.main.PlayersInGame[2] = nil
		equal(protected.main.DamagePlayer(protected.player, protected.victim, protected.victim.Character.Humanoid, 100), 0)
	end)
	test("kill UI identifies the victim immediately and reports only actual deferred XP once", function()
		for _, awarded in ipairs({0, 25, 37}) do
			local f = roundFixture(); f.prepare(true)
			f.rewards.XpReward = function(target, action)
				return target == f.player and action == "kill" and awarded or 0
			end
			f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
			local immediate = f.killSound.LastClientArgs
			equal(immediate[1], f.player); equal(immediate[2], "Kill")
			equal(immediate[3].VictimUserId, f.victim.UserId); equal(immediate[3].VictimUsername, f.victim.Name)
			assert(type(immediate[3].KillId) == "string")
			f.main.OnDeath(f.victim, f.victim.Character); equal(f.killSound.ClientCalls, 1)
			f.deferred[1]()
			local reward = f.killSound.LastClientArgs
			equal(reward[2], "KillReward"); equal(reward[3].KillId, immediate[3].KillId)
			equal(reward[3].XpEarned, awarded); equal(f.killSound.ClientCalls, 2)
		end
	end)
	test("deferred kill XP feedback skips a killer who disconnected after credit", function()
		local f = roundFixture(); f.prepare(true)
		f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
		f.player.Parent = nil
		f.deferred[1]()
		equal(f.killSound.ClientCalls, 1)
	end)
	test("weapon death prepares joints and impact before inline or deferred death handling", function()
		for _, inline in ipairs({false,true}) do
			local f=roundFixture(); f.prepare(true); f.inlineDeath=inline
			local character=f.victim.Character; local impact={Kind="KnifeThrow",Direction={}}
			equal(f.main.DamagePlayer(f.player,f.victim,character.Humanoid,50,impact),50)
			equal(character.Humanoid.BreakJointsOnDeath,false); equal(f.ragdollCalls[character],nil); equal(f.impacts[character],nil)
			equal(f.main.DamagePlayer(f.player,f.victim,character.Humanoid,50,impact),50)
			equal(f.impacts[character].Kind,"KnifeThrow"); assert(f.ragdollCalls[character]>=1)
			equal(f.player.leaderstats.Kills.Value,1); equal(f.victim.leaderstats.Deaths.Value,1)
		end
		local f=roundFixture(); f.prepare(true); f.blockDamage=true; local char=f.victim.Character
		f.main.DamagePlayer(f.player,f.victim,char.Humanoid,100,{Kind="Revolver",Direction={}})
		equal(f.impacts[char],nil); equal(f.ragdollCalls[char],nil)
	end)
	test("FFA respawns once on the active map and old callbacks cannot respawn into a later round", function()
		local f = roundFixture(); f.prepare(true)
		f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
		local delayed = f.delayed[1]; delayed.fn(); equal(f.victim.loads, 1); assert(f.victim.Character.HumanoidRootPart.CFrame)
		f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
		local stale = f.delayed[2]; f.main.CleanupRound(false); f.prepare(true); stale.fn()
		equal(f.victim.loads, 1); equal(f.main.PlayersInGame[2], true)
	end)
	test("Battle Royale lobby return cannot replace a new character or later round character", function()
		local f = roundFixture(); f.prepare(false)
		local old = f.victim.Character; f.main.DamagePlayer(f.player, f.victim, old.Humanoid, 100)
		f.victim:LoadCharacter(); f.delayed[1].fn(); equal(f.victim.loads, 1)
		f.main.OnDeath(f.victim, old); equal(f.victim.leaderstats.Deaths.Value, 1)
	end)
	test("disconnect forfeits placement while keeping kills already credited", function()
		local f = roundFixture(); f.prepare(true)
		f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
		f.main.LeaveRound(f.player, true); equal(f.main.PlayersInGame[1], nil)
		equal(f.main.RoundStats.players[1].forfeited, true); equal(f.main.RoundStats.players[1].placement, 0)
		equal(f.player.leaderstats.Kills.Value, 1); equal(f.player:GetAttribute("InRound"), false)
	end)
	test("round rewards exclude FFA forfeits from top-three quest credit", function()
		local f = roundFixture()
		local progress = {}
		f.modules[f.servicesFolder.QuestsHandler].AddProgress = function(player, kind, amount)
			progress[player] = progress[player] or {}
			progress[player][kind] = (progress[player][kind] or 0) + amount
		end
		f.onWait = function()
			if f.main.GameActive and not f.forfeited then
				f.forfeited = true
				f.main.LeaveRound(f.player)
			end
		end
		equal(f.main.StartGame("MapA", "FFA"), true)
		equal(f.forfeited, true)
		equal(f.player:GetAttribute("LastRoundPlacement"), 0)
		equal(progress[f.player].TOP3_FINISHES, nil, "A forfeit is not a top-three finish")
		equal(progress[f.player].ROUNDS_PLAYED, 1, "Preserve the existing participation reward policy")
		equal(progress[f.victim].TOP3_FINISHES, 1)
		equal(progress[f.third].TOP3_FINISHES, 1)
	end)
	test("round rewards preserve legitimate first second and third place quest credit", function()
		local f = roundFixture()
		local topThree = {}
		f.modules[f.servicesFolder.QuestsHandler].AddProgress = function(player, kind, amount)
			if kind == "TOP3_FINISHES" then topThree[player] = (topThree[player] or 0) + amount end
		end
		equal(f.main.StartGame("MapA", "FFA"), true)
		for placement, player in ipairs({f.player, f.victim, f.third}) do
			equal(player:GetAttribute("LastRoundPlacement"), placement)
			equal(topThree[player], 1, "Each legitimate finisher receives credit exactly once")
		end
	end)
	test("round places players before fight countdown, awards once and cleans attributes/tools", function()
		local f = roundFixture()
		f.mapConfig.RoundStartProtectionSeconds = 0 -- this case isolates kill/reward accounting
		f.onWait = function()
			if f.main.GameActive and not f.killed then
				f.killed = true; f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
			end
		end
		equal(f.main.StartGame("MapA", "FFA"), true)
		equal(f.results.ClientCalls, 1); equal(f.progress.ROUNDS_PLAYED, 3); equal(f.progress.WINS, 1)
		equal(f.player.leaderstats.Kills.Value, 1, "results must not add lifetime kills twice")
		equal(f.main.GameActive, false); equal(f.active.Value, false); equal(next(f.main.PlayersInGame), nil)
		equal(f.main.RoundStats, nil); equal(f.Players.CharacterAutoLoads, true)
		equal(f.player:GetAttribute("CurrentRoundParticipant"), false); equal(f.main.IsLobbyModeLocked(), false)
		equal(#f.background, 3, "exactly one cleanup respawn per player")
	end)
	test("round-start ForceFields are in place before movement releases and block opening weapon damage", function()
		local f = roundFixture(); local release = f.maps.ReleasePlacements
		local checked, fields = false, {}
		f.maps.ReleasePlacements = function()
			if not checked and f.main.RoundStats and not f.main.GameActive then
				for _, player in ipairs(f.Players:GetPlayers()) do
					local field = player.Character.RoundStartProtection
					assert(field); equal(field.ClassName, "ForceField"); equal(field.Visible, true)
					equal(player.Character.HumanoidRootPart.Anchored, true); table.insert(fields, field)
				end
				checked = true
			end
			release()
		end
		f.onCountdown = function()
			for _, player in ipairs(f.Players:GetPlayers()) do equal(player.Character.RoundStartProtection, nil) end
		end
		f.onWait = function()
			if f.main.GameActive then
				equal(checked, true); equal(f.victim.Character.HumanoidRootPart.Anchored, false)
				equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100), 0)
				equal(f.victim.Character.Humanoid.Health, 100); equal(f.player.leaderstats.Kills.Value, 0)
			end
		end
		equal(f.main.StartGame("MapA", "FFA"), true); equal(checked, true); equal(#fields, 3)
		for _, field in ipairs(fields) do equal(field.Parent, nil) end
		for _, job in ipairs(f.delayed) do equal(job.delay, 1.5) end
	end)
	test("round-start protection lasts 1.5 seconds after combat starts then permits damage", function()
		local f = roundFixture(); f.modes.FFA.RoundDuration = 3
		local start, checked
		f.active.Changed:Connect(function(value) if value then start = f.time end end)
		local function expireDue()
			for _, job in ipairs(f.delayed) do
				if not job.ran and job.at <= f.time then job.ran = true; job.fn() end
			end
		end
		f.onWait = function()
			if not f.main.GameActive or checked then return end
			checked = true; f.time = start + 1.49; expireDue()
			assert(f.victim.Character.RoundStartProtection)
			equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 50), 0)
			f.time = start + 1.5; expireDue(); equal(f.victim.Character.RoundStartProtection, nil)
			equal(f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 50), 50)
			equal(f.victim.Character.Humanoid.Health, 50)
		end
		equal(f.main.StartGame("MapA", "FFA"), true); equal(checked, true)
	end)
	test("round-start protection skips lobby spectators and zero duration disables it", function()
		for _, enabled in ipairs({true, false}) do
			local f = roundFixture(); f.third.leaderstats.Settings.LobbyMode.Value = true
			if not enabled then f.mapConfig.RoundStartProtectionSeconds = 0 end
			local checked = false; f.onWait = function()
				if not f.main.GameActive then return end
				checked = true; equal(f.third.Character.RoundStartProtection, nil)
				equal(f.player.Character.RoundStartProtection ~= nil, enabled)
				equal(f.victim.Character.RoundStartProtection ~= nil, enabled)
			end
			equal(f.main.StartGame("MapA", "FFA"), true); equal(checked, true)
		end
	end)
	test("expired old round callbacks cannot remove a later round's protection", function()
		local f = roundFixture(); equal(f.main.StartGame("MapA", "FFA"), true)
		local oldJobs = table.clone(f.delayed); local checked = false
		f.onWait = function()
			if not f.main.GameActive or checked then return end
			checked = true; local field = f.player.Character.RoundStartProtection; assert(field)
			for _, job in ipairs(oldJobs) do job.fn() end
			equal(field.Parent, f.player.Character); equal(f.player.Character.RoundStartProtection, field)
		end
		equal(f.main.StartGame("MapA", "FFA"), true); equal(checked, true)
	end)
	test("round failure removes only its owned ForceFields", function()
		local f = roundFixture(); local custom = child(f.player.Character, "ForceField", "OtherProtection")
		local fields = {}; f.zone.SpawnZone = function()
			for _, player in ipairs(f.Players:GetPlayers()) do table.insert(fields, player.Character.RoundStartProtection) end
			return false
		end
		equal(f.main.StartGame("MapA", "BattleRoyale"), false); equal(#fields, 3)
		for _, field in ipairs(fields) do equal(field.Parent, nil) end
		equal(custom.Parent, f.player.Character)
	end)
	test("failed placements and countdown disconnects abort without phantom participants", function()
		for _, reason in ipairs({"placement", "disconnect", "unready"}) do
			local f = roundFixture()
			if reason == "placement" then f.player.Character.HumanoidRootPart:Destroy(); f.third.Character.HumanoidRootPart:Destroy()
			elseif reason == "disconnect" then f.onCountdown = function() f.player.Parent = nil; f.third.Parent = nil end
			else f.player:SetAttribute("DataReady", false); f.third:SetAttribute("DataReady", false) end
			equal(f.main.StartGame("MapA", "FFA"), true); equal(f.results.ClientCalls, nil, reason)
			equal(f.active.Value, false); equal(next(f.main.PlayersInGame), nil); equal(f.main.IsLobbyModeLocked(), false)
		end
	end)
	test("map errors and missing BR zone recover so the next round can start", function()
		local f = roundFixture(); local spawn = f.maps.Spawn
		f.maps.Spawn = function() error("simulated map error") end
		equal(f.main.StartGame("MapA", "FFA"), false); equal(f.Players.CharacterAutoLoads, true)
		f.maps.Spawn = spawn; f.missingZone = true
		equal(f.main.StartGame("MapA", "BattleRoyale"), false); equal(f.main.GameActive, false)
		f.missingZone = false; equal(f.main.StartGame("MapA", "FFA"), true); equal(f.results.ClientCalls, 1)
	end)
	test("a lobby death still respawns while round-controlled spawning disables auto loads", function()
		local f = roundFixture(); f.prepare(true); f.main.LeaveRound(f.third, true)
		f.third.Character.Humanoid.Health = 0; f.main.OnDeath(f.third, f.third.Character)
		equal(#f.delayed, 1); f.delayed[1].fn(); equal(f.third.loads, 1)
		equal(f.third.leaderstats.Deaths.Value, 0); equal(f.main.PlayersInGame[3], nil)
	end)
	local function musicFixture(roundId, lobbyMissing)
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		local settings = child(f.player.leaderstats, "Folder", "Settings")
		f.setting = child(settings, "BoolValue", "Music", true)
		f.active = child(f.RS, "BoolValue", "GameActive", false)
		local sounds = child(child(f.RS, "Folder", "Assets"), "Folder", "Sounds")
		if not lobbyMissing then child(sounds, "Sound", "LobbyMusic").SoundId = "rbxassetid://lobby" end
		f.config = f:load("MusicConfig", f.modulesFolder); f.config.Round.SoundId = roundId or "rbxassetid://round"
		f.soundService = object("SoundService", "SoundService"); f.tweens = {}
		f.tweenService = {Create = function(_, sound, _, goal)
			local tween = {Completed = signal(), sound = sound, goal = goal}
			function tween:Play() end
			function tween:Cancel() self.cancelled = true; self.Completed:Fire("Cancelled") end
			function tween:Finish() self.sound.Volume = self.goal.Volume; self.Completed:Fire("Completed") end
			table.insert(f.tweens, tween); return tween
		end}
		local getService = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "SoundService" then return f.soundService elseif name == "TweenService" then return f.tweenService end
			return getService(self, name)
		end
		f.env.TweenInfo = {new = function() return {} end}
		f.env.Enum.EasingStyle, f.env.Enum.EasingDirection, f.env.Enum.PlaybackState = {Quad = "Quad"}, {InOut = "InOut"}, {Completed = "Completed"}
		function methods:Play() self.IsPlaying = true; self.plays = (self.plays or 0) + 1 end
		function methods:Stop() self.IsPlaying = false; self.stops = (self.stops or 0) + 1 end
		f.music = f:load("Music", f.modulesFolder); f.music.Init()
		return f
	end
	test("round music starts only during gameplay and lobby music resumes after the round", function()
		local f = musicFixture()
		local lobby, round = f.soundService.LobbyMusic, f.soundService.RoundMusic
		equal(lobby.IsPlaying, true); assert(not round.IsPlaying); equal(lobby.Volume, 0, "publish/start muted before fade")
		f.active.Value = true; equal(round.IsPlaying, true); equal(round.SoundId, "rbxassetid://round")
		f.tweens[#f.tweens - 1]:Finish(); equal(lobby.IsPlaying, false)
		f.tweens[#f.tweens]:Finish(); equal(round.Volume, f.config.Round.Volume)
		f.active.Value = false; equal(lobby.IsPlaying, true)
		f.tweens[#f.tweens]:Finish(); equal(round.IsPlaying, false)
	end)
	test("music toggle mutes both phases and cancelled fades cannot stop restarted tracks", function()
		local f = musicFixture(); f.active.Value = true
		f.tweens[#f.tweens - 1]:Finish() -- advance the lobby's fade-out
		local round = f.soundService.RoundMusic
		f.setting.Value = false; local oldFade = f.tweens[#f.tweens]; equal(oldFade.goal.Volume, 0)
		f.setting.Value = true; equal(oldFade.cancelled, true); equal(round.IsPlaying, true)
		oldFade.Completed:Fire("Completed"); equal(round.IsPlaying, true)
		f.setting.Value = false; f.tweens[#f.tweens]:Finish(); equal(round.IsPlaying, false)
		f.active.Value = false; assert(not f.soundService.LobbyMusic.IsPlaying)
	end)
	test("blank round ID is silent and missing lobby template does not block round music", function()
		local f = musicFixture(""); equal(f.soundService.RoundMusic, nil); f.active.Value = true
		local missing = musicFixture(nil, true); equal(missing.soundService.LobbyMusic, nil)
		missing.active.Value = true; equal(missing.soundService.RoundMusic.IsPlaying, true)
		local count = #missing.soundService:GetChildren(); missing.music.Init(); equal(#missing.soundService:GetChildren(), count)
	end)
	test("XP pass is cached between rewards and a purchase refreshes the cached multiplier", function()
		local f = fixture(); local player = f:createPlayer(1); child(player.leaderstats, "IntValue", "XP", 0)
		f.Marketplace.PromptGamePassPurchaseFinished = signal(); f.passCalls = 0
		f.Marketplace.UserOwnsGamePassAsync = function() f.passCalls += 1; return false end
		f.env.task.spawn = function(fn, ...) fn(...) end
		local rewards = f:load("GameReward", f.gameFolder)
		equal(rewards.XpReward(player, "kill", 3, 1), 25); equal(rewards.XpReward(player, "kill", 3, 1), 25)
		equal(f.passCalls, 1); f.Marketplace.PromptGamePassPurchaseFinished:Fire(player, 1733058985, true)
		equal(rewards.XpReward(player, "kill", 3, 1), 37); equal(f.passCalls, 1)
		f.Players.PlayerRemoving:Fire(player); player.Parent = nil
		equal(rewards.XpReward(player, "kill", 3, 1), 0); equal(rewards.CashReward(player, "kill", 3, 1), 0)
	end)
	test("VIP kill rewards expire without a client refresh and preserve valid bonuses", function()
		local f = fixture(); local player = f:createPlayer(1); child(player.leaderstats, "IntValue", "XP", 0)
		local now = 1700000000
		f.env.os.time = function() return now end
		f.Marketplace.PromptGamePassPurchaseFinished = signal()
		f.Marketplace.UserOwnsGamePassAsync = function() return false end
		local rewards = f:load("GameReward", f.gameFolder)
		player:SetAttribute("HasVIP", true); player:SetAttribute("VIPExpiresAt", now + 1)
		equal(rewards.XpReward(player, "kill"), 35); equal(rewards.CashReward(player, "kill"), 60)
		now += 1
		equal(rewards.XpReward(player, "kill"), 25); equal(rewards.CashReward(player, "kill"), 50)
		equal(player:GetAttribute("HasVIP"), false)
		for _, invalid in ipairs({0/0, math.huge, -math.huge, "forever"}) do
			player:SetAttribute("HasVIP", true); player:SetAttribute("VIPExpiresAt", invalid)
			equal(rewards.CashReward(player, "kill"), 50); equal(rewards.XpReward(player, "kill"), 25)
		end
	end)
	test("VIP expiry during an XP pass lookup cannot grant an expired bonus", function()
		local f = fixture(); local player = f:createPlayer(1); child(player.leaderstats, "IntValue", "XP", 0)
		local now = 1700000000; f.env.os.time = function() return now end
		f.env.task.spawn = function() end -- leave the ownership cache cold
		f.Marketplace.PromptGamePassPurchaseFinished = signal()
		f.Marketplace.UserOwnsGamePassAsync = function() now += 2; return true end
		player:SetAttribute("HasVIP", true); player:SetAttribute("VIPExpiresAt", now + 1)
		local rewards = f:load("GameReward", f.gameFolder)
		equal(rewards.XpReward(player, "kill"), 37)
	end)
	local function votingRoundFixture()
		local f = mapFixture(); f.SSS.Game = f.gameFolder
		f:load("Modes", f.modulesFolder, "GameModes")
		for name, info in pairs(f.modules[f.gameFolder.Maps]) do info.Name = name end
		f.modules[child(f.gameFolder, "ModuleScript", "PlayerStatusSender")] = {EditClientStatus = function(status) f.status = status end}
		child(child(f.RS, "Folder", "VotingRemotes"), "RemoteEvent", "StartVoting")
		local getService = f.game.GetService
		f.game.GetService = function(self, name) if name == "RunService" then return {IsStudio = function() return false end} end; return getService(self, name) end
		f.handler = f:load("RoundHandler", f.gameFolder); f.handler.VotingDuration = 0
		for id = 1, 3 do local player = f:createPlayer(id); child(child(player.leaderstats, "Folder", "Settings"), "BoolValue", "LobbyMode", false) end
		f.player = f.Players:GetPlayerByUserId(1)
		return f
	end
	test("intermission waits for loaded profiles instead of spinning on unready players", function()
		local f = votingRoundFixture(); f.player:SetAttribute("DataReady", false)
		f.handler.ChangeStatus("Minimum"); assert(string.find(f.status, "WAITING FOR 1 PLAYER", 1, true))
		local yielded = false; f.onWait = function() yielded = true; f.player:SetAttribute("DataReady", true) end
		equal(f.handler.Intermission(), true); equal(yielded, true)
	end)
	test("voting supports fewer than three maps and an empty pool without unbounded selection", function()
		local f = votingRoundFixture(); f.handler.StartVoting()
		equal(#f.handler.VoteOptions, 2); assert(f.handler.VoteOptions[1].Map ~= f.handler.VoteOptions[2].Map)
		f.handler.GetMaps = function() return {} end; f.handler.StartVoting()
		equal(#f.handler.VoteOptions, 0); equal(f.handler.GetRandomMap(), nil); equal(f.handler.GetRandomMapFromVoting(), nil)
	end)
	test("leaving FFA while dead still returns to the lobby once", function()
		local f = roundFixture(); f.prepare(true)
		f.main.DamagePlayer(f.player, f.victim, f.victim.Character.Humanoid, 100)
		f.main.LeaveRound(f.victim); equal(#f.delayed, 2)
		f.delayed[1].fn(); f.delayed[2].fn(); equal(f.victim.loads, 1); equal(f.main.PlayersInGame[2], nil)
	end)
	test("Battle Royale with no survivors is a draw without win rewards/credit", function()
		local f = roundFixture()
		f.onWait = function()
			if f.main.GameActive and not f.eliminated then
				f.eliminated = true
				for _, player in ipairs(f.Players:GetPlayers()) do
					player.Character.Humanoid.Health = 0; f.main.OnDeath(player, player.Character)
				end
			end
		end
		equal(f.main.StartGame("MapA", "BattleRoyale"), true)
		equal(f.results.LastClientArgs[1].Draw, true); equal(#f.results.LastClientArgs[1].Winners, 0)
		equal(f.progress.WINS, nil)
		for _, row in ipairs(f.results.LastClientArgs[2]) do assert(row.Placement >= 1 and row.Placement <= 3 and not row.IsWinner) end
	end)
	local function zoneFixture(phased)
		local f = roundFixture(); f.prepare(false)
		f.modules[f.modulesFolder.ZoneConfig].PhasesEnabled = phased == true
		f.SSS.Game, f.game.ServerScriptService = f.gameFolder, f.SSS
		child(child(f.remotes, "Folder", "Zone"), "RemoteEvent", "RecieveClient")
		local template = child(f.SS, "Part", "Zone")
		template.Size, template.CFrame = vec.new(100,1000,100), {PointToObjectSpace = function(_, position) return position end}
		for _, player in ipairs(f.Players:GetPlayers()) do player.Character.HumanoidRootPart.Position = vec.new(1000,0,0) end
		f.tweens = {}
		local tweenService = {Create = function(_, zone, _, goal)
			local tween = {Completed = {Wait = function() coroutine.yield() end}}
			function tween:Play() zone.Size = goal.Size end
			function tween:Cancel() self.cancelled = true end
			table.insert(f.tweens, tween); return tween
		end}
		local getService = f.game.GetService
		f.game.GetService = function(self, name) if name == "TweenService" then return tweenService end; return getService(self, name) end
		f.env.Vector3, f.env.Vector2 = vec, vec; f.env.TweenInfo = {new = function() return {} end}
		f.env.Enum.EasingStyle = {Linear = "Linear"}; f.env.task.wait = function() coroutine.yield() end
		f.zoneActual = f:load("GameZone", f.gameFolder); assert(f.zoneActual.SpawnZone()); f.zoneActual.StartZone()
		return f
	end
	test("old zone jobs cannot resume damage/shrinking after a new zone starts", function()
		local f = zoneFixture(); local shrink, damage = coroutine.create(f.background[1]), coroutine.create(f.background[2])
		assert(coroutine.resume(shrink)); assert(coroutine.resume(damage)); equal(f.victim.Character.Humanoid.Health, 90)
		f.zoneActual.StopZone(); equal(f.tweens[1].cancelled, true)
		f.main.RoundId += 1; assert(f.zoneActual.SpawnZone()); f.zoneActual.StartZone()
		assert(coroutine.resume(shrink)); assert(coroutine.resume(damage))
		equal(coroutine.status(shrink), "dead"); equal(coroutine.status(damage), "dead")
		equal(f.victim.Character.Humanoid.Health, 90); equal(#f.tweens, 1)
	end)
	test("phased BR holds before shrinking and cancels an old hold without publishing a tween",function()
		local f=zoneFixture(true); local shrink=coroutine.create(f.background[1]); local zone=f.workspace.Zone
		assert(coroutine.resume(shrink)); equal(zone:GetAttribute("Phase"),1); equal(zone:GetAttribute("PhaseState"),"Holding"); equal(#f.tweens,0)
		assert(coroutine.resume(shrink)); equal(zone:GetAttribute("PhaseState"),"Shrinking"); equal(zone.Size.X,65)
		assert(coroutine.resume(shrink)); equal(zone:GetAttribute("Phase"),2); equal(zone:GetAttribute("PhaseState"),"Holding")
		f.zoneActual.StopZone(); assert(coroutine.resume(shrink)); equal(coroutine.status(shrink),"dead"); equal(#f.tweens,1)
	end)
	test("phased BR reaches the final core within the configured round budget",function()
		local f=zoneFixture(true); local shrink=coroutine.create(f.background[1]); local schedule=f.modules[f.modulesFolder.ZoneConfig]
		local duration=0; for _, phase in ipairs(schedule.Phases) do duration+=phase.Hold+phase.Shrink end
		assert(duration<=300)
		while coroutine.status(shrink)~="dead" do assert(coroutine.resume(shrink)) end
		equal(#f.tweens,4); equal(f.workspace.Zone.Size.X,4); equal(f.workspace.Zone.Size.Z,4)
	end)
	test("zone deaths clear weapon credit and missing zone templates fail cleanly", function()
		local f = zoneFixture(); f.main.RegisterPendingKill(f.player, 2)
		for _, player in ipairs(f.Players:GetPlayers()) do player.Character.Humanoid.Health = 10 end
		local damage = coroutine.create(f.background[2]); assert(coroutine.resume(damage))
		equal(f.player.leaderstats.Kills.Value, 0); equal(f.victim.leaderstats.Deaths.Value, 1)
		f.zoneActual.StopZone(); f.SS.Zone:Destroy(); equal(f.zoneActual.SpawnZone(), false)
		assert(coroutine.resume(damage)); equal(coroutine.status(damage), "dead")
	end)
	test("zone warnings send on visibility changes instead of every damage tick", function()
		local f=zoneFixture(); local remote=f.remotes.Zone.RecieveClient; local initial=remote.ClientCalls or 0
		for _=1,30 do f.zoneActual.NotifyPlayer(f.player,true) end
		equal(remote.ClientCalls,initial+1)
		f.zoneActual.NotifyPlayer(f.player,false); equal(remote.ClientCalls,initial+2)
		f.zoneActual.StopZone(); f.zoneActual.NotifyPlayer(f.player,false)
		equal(remote.ClientCalls,initial+4)
	end)
	local function hitFixture()
		local f = fixture(); f.audio = f:load("CombatAudioConfig", f.modulesFolder)
		f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		child(f.player, "PlayerGui", "PlayerGui")
		f.victim = f:createPlayer(2).Character; child(f.victim, "Part", "Head")
		local function constructor(...) return {...} end
		f.env.Vector2, f.env.Vector3, f.env.Color3 = vec, vec, {fromRGB = constructor}
		f.env.UDim, f.env.UDim2 = {new = constructor}, {new = constructor, fromScale = constructor, fromOffset = constructor}
		f.env.Enum.Font = {GothamBold = "Bold", GothamBlack = "Black"}
		f.env.Enum.TextXAlignment, f.env.Enum.TextTruncate = {Left = "Left"}, {AtEnd = "AtEnd"}
		f.env.Enum.ZIndexBehavior = {Sibling = "Sibling"}
		f.env.Enum.EasingStyle, f.env.Enum.EasingDirection = {Quad = "Quad", Back = "Back"}, {Out = "Out"}
		f.env.TweenInfo = {new = constructor}
		f.workspace.CurrentCamera = object("Camera", "Camera"); f.workspace.CurrentCamera.ViewportSize = vec.new(1280, 720)
		f.workspace.GetPropertyChangedSignal = function() return signal() end
		f.env.task.delay = function(delay, fn) local job = {delay = delay, fn = fn}; table.insert(f.delayed, job); return job end
		f.env.task.cancel = function(job) job.cancelled = true end
		f:load("CombatFeedbackConfig", f.modulesFolder)
		f.soundService = object("SoundService", "SoundService")
		f.tweenService = {Create = function(_, target, _, goal)
			return {Play = function() for name, value in pairs(goal) do target[name] = value end end, Cancel = function() end, Destroy = function() end}
		end}
		local getService = f.game.GetService
		f.game.GetService = function(self, name)
			if name == "SoundService" then return f.soundService end
			if name == "TweenService" then return f.tweenService end
			return getService(self, name)
		end
		local knife = child(f.remotes, "Folder", "Knife")
		f.damage = child(knife, "RemoteEvent", "DamageDealtClient"); child(knife, "RemoteEvent", "PlayerGotKilledRemote")
		f.hit = f:load("HitFeedback", f.modulesFolder); f.hit.Init()
		return f
	end
	test("confirmed gun and thrown knife damage each play one quiet hit sound", function()
		local f = hitFixture(); f.hit.Init(); equal(f.damage.OnClientEvent:Count(), 1)
		for _, kind in ipairs({"Revolver", "KnifeThrow"}) do f.damage.OnClientEvent:Fire(f.victim, 50, kind) end
		equal(#f.soundService:GetChildren(), f.audio.Hit.MaxActiveSounds)
		local plays = 0
		for _, audio in ipairs(f.soundService:GetChildren()) do
			equal(audio.SoundId, "rbxassetid://79414317792890"); equal(audio.Volume, 0.22); plays += audio.plays or 0
			equal(audio.Looped, false)
		end
		equal(plays, 2)
	end)
	test("misses blocked damage invalid damage and stab do not play throw hit feedback", function()
		local f = hitFixture()
		for _, amount in ipairs({0, -1, math.huge, -math.huge, 0/0, "50"}) do f.damage.OnClientEvent:Fire(f.victim, amount, "KnifeThrow") end
		f.damage.OnClientEvent:Fire(f.victim, 50); f.damage.OnClientEvent:Fire(f.victim, 50, "KnifeStab")
		for _, audio in ipairs(f.soundService:GetChildren()) do equal(audio.plays, nil) end
	end)
	test("hit audio has a bounded voice budget and completed sounds release their slots", function()
		local f = hitFixture()
		for _ = 1, 20 do f.damage.OnClientEvent:Fire(f.victim, 50, "Revolver") end
		equal(#f.soundService:GetChildren(), 12)
		local completed = f.soundService:GetChildren()[1]; completed.IsPlaying = false
		local plays = completed.plays
		f.damage.OnClientEvent:Fire(f.victim, 50, "Revolver"); equal(#f.soundService:GetChildren(), 12)
		equal(completed.plays, plays + 1)
	end)
	test("requested match song uses configured volume and mutes through the Music setting", function()
		local cfg = load("MusicConfig"); equal(cfg.Round.SoundId, "rbxassetid://103700954012183")
		local f = musicFixture(cfg.Round.SoundId); f.active.Value = true
		f.tweens[#f.tweens]:Finish(); equal(f.soundService.RoundMusic.Volume, cfg.Round.Volume)
		f.setting.Value = false; f.tweens[#f.tweens]:Finish(); equal(f.soundService.RoundMusic.IsPlaying, false)
	end)
	local function hintFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		f.gui = child(f.player, "PlayerGui", "PlayerGui")
		f.binds = child(f.player.leaderstats, "Folder", "KeyBinds")
		child(f.binds, "StringValue", "Stab", "MouseButton1"); child(f.binds, "StringValue", "ThrowKnife", "E")
		f.config = f:load("KnifeConfig", f.modulesFolder)
		f.modules[child(f.modulesFolder, "ModuleScript", "KeybindValidation")] = {ToDisplay = function(key) return key == "MouseButton1" and "LClick" or key end}
		f.modules[child(f.modulesFolder, "ModuleScript", "HitFeedback")] = {SetAimPosition = function(position) f.markerPosition = position end}
		local function constructor(...) return {...} end
		f.env.Vector2, f.env.UDim2, f.env.Color3 = {new = constructor}, {fromScale = constructor, fromOffset = constructor}, {new = constructor, fromRGB = constructor}
		f.env.Enum.Font = {GothamBold = "GothamBold"}; f.workspace.CurrentCamera = {ViewportSize = {X = 320}}
		f.hint = f:load("KnifeHint", f.modulesFolder); f.hint.Init()
		f.label = f.gui.KnifeHUD:FindFirstChildOfClass("TextLabel")
		return f
	end
	test("knife hint shares ammo HUD position follows remaps and fits a phone viewport", function()
		local f = hintFixture(); f.hint.Update(true, false)
		equal(f.gui.KnifeHUD.Enabled, true); equal(f.label.Position[1], 0.5); equal(f.label.Position[2], 0.88)
		equal(f.label.Text, "[LClick] TAP STAB  |  [E] HOLD TO THROW"); equal(f.label.Size[1], 288)
		f.binds.ThrowKnife.Value = "Q"; f.hint.Update(true, false)
		equal(f.label.Text, "[LClick] TAP STAB  |  [Q] HOLD TO THROW")
		f.hint.Update(false, false); equal(f.gui.KnifeHUD.Enabled, false)
		f.hint.Init(); equal(#f.gui:GetChildren(), 1)
	end)
	test("knife hint shows tap hold touch instructions and caps charge feedback at 100 percent", function()
		local f = hintFixture(); f.hint.Update(true, true)
		equal(f.label.Text, "TAP TO STAB  |  HOLD THROW, THEN RELEASE")
		f.hint.Update(true, true, 0.1); equal(f.label.Text, "TAP TO STAB  |  HOLD TO CHARGE")
		f.hint.Update(true, true, 0.5); equal(f.label.Text, "THROW CHARGE 50%  |  RELEASE TO THROW")
		f.hint.Update(true, false, 10); equal(f.label.Text, "THROW CHARGE 100%  |  RELEASE TO THROW")
		f.config.Presentation.HintEnabled = false; f.hint.Update(true, false); equal(f.gui.KnifeHUD.Enabled, false)
	end)
	test("knife aim positions reach shared hit feedback even with the hint disabled", function()
		local f = hintFixture()
		f.config.Presentation.HintEnabled = false
		f.hint.Update(true, false, nil, {X = 123, Y = 234})
		equal(f.markerPosition.X, 123); equal(f.markerPosition.Y, 234)
		equal(f.gui.KnifeHUD.Enabled, false); equal(f.label.Visible, false)
		equal(f.gui.KnifeHUD:FindFirstChild("HitMarker"), nil)
	end)
	test("hidden knife hints do not overwrite another weapon's shared aim position", function()
		local f = hintFixture(); f.hint.Update(true, true, nil, {X = 160, Y = 300})
		f.hint.Update(false, true, nil, {X = 999, Y = 999})
		equal(f.markerPosition.X, 160); equal(f.markerPosition.Y, 300)
	end)
	test("map spawn markers remain valid with CanQuery disabled", function()
		local f = mapFixture(); f.SS.MapA.Geometry.Spawns["1"].CanQuery = false
		equal(f.maps.Spawn("MapA"), true)
		local player = f:createPlayer(1); child(player.Character, "Part", "HumanoidRootPart").CFrame = mapFrame(0,0,0)
		equal(f.maps.PlacePlayers("MapA", {player}), 1)
		equal(player.Character.HumanoidRootPart.Anchored, true)
		f.maps.ReleasePlacements(); equal(player.Character.HumanoidRootPart.Anchored, false)
	end)
	test("placement waits for an initially missing character and confirms its new root", function()
		local f = mapFixture(); f.maps.Spawn("MapA"); local player = f:createPlayer(1); player.Character = nil
		local waits = 0; f.onWait = function()
			waits += 1
			if waits == 2 then child(f:character(player), "Part", "HumanoidRootPart").CFrame = mapFrame(0,0,0) end
		end
		local count, characters = f.maps.PlacePlayers("MapA", {player})
		equal(count, 1); equal(characters[1], player.Character); assert(waits >= 3)
		equal(player.Character.HumanoidRootPart.Position.Y, 6)
	end)
	test("placement retries a physics rollback and verification repairs later displacement", function()
		local f = mapFixture(); f.maps.Spawn("MapA"); local player = f:createPlayer(1)
		local root = child(player.Character, "Part", "HumanoidRootPart"); root.CFrame = mapFrame(0,0,0)
		local rolledBack = false; f.onWait = function()
			if not rolledBack then rolledBack = true; root.CFrame = mapFrame(1000,1000,1000) end
		end
		equal(f.maps.PlacePlayers("MapA", {player}), 1); equal(root.Position.X, 1)
		root.CFrame = mapFrame(2000,2000,2000); equal(f.maps.VerifyPlayers("MapA", {player}), 1)
		equal(root.Position.X, 1); f.maps.RemoveAllMaps(); equal(root.Anchored, false)
	end)
	test("streaming placement preloads the destination and a failed request cannot confirm it", function()
		for _, fail in ipairs({false, true}) do
			local f = mapFixture(); f.maps.Spawn("MapA"); f.workspace.StreamingEnabled = true
			local player = f:createPlayer(1); local root = child(player.Character, "Part", "HumanoidRootPart"); root.CFrame = mapFrame(0,0,0)
			local requests = 0; function player:RequestStreamAroundAsync(position, seconds)
				requests += 1; equal(position.Y, 6); equal(seconds, 3); if fail then error("stream request failure") end
			end
			equal(f.maps.PlacePlayers("MapA", {player}), fail and 0 or 1); equal(requests, 1)
			f.maps.ReleasePlacements(); equal(root.Anchored, false)
		end
	end)
	test("a ready player left behind aborts the round even when others meet minimum", function()
		local f = roundFixture(); f.player.Character.HumanoidRootPart:Destroy()
		equal(f.main.StartGame("MapA", "FFA"), true); equal(f.results.ClientCalls, nil)
		equal(f.status, "PLAYER COULD NOT REACH MAP"); equal(f.active.Value, false)
		for _, player in ipairs(f.Players:GetPlayers()) do
			local root = player.Character:FindFirstChild("HumanoidRootPart"); if root then equal(root.Anchored, false) end
		end
	end)
	test("character replacement during countdown is teleported and verified before combat", function()
		local f = roundFixture(); local old = f.player.Character
		f.onCountdown = function() f.player:LoadCharacter(); f.third:LoadCharacter() end
		local verified = false; f.onWait = function()
			if f.main.GameActive then
				assert(f.player.Character ~= old and f.player.Character.LastPivot)
				equal(f.player.Character.HumanoidRootPart.Position.X, 1)
				equal(f.player.Character.HumanoidRootPart.Anchored, false); verified = true
			end
		end
		equal(f.main.StartGame("MapA", "FFA"), true); equal(f.results.ClientCalls, 1); equal(verified, true)
	end)
	test("hover scanning reuses ray parameters and performs no work between scan ticks", function()
		local f = hoverFixture(); local count = 0; local raycast = f.workspace.Raycast
		f.workspace.Raycast = function(...) count += 1; return raycast(...) end
		for _ = 1, 8 do f.events.Heartbeat:Fire(0.001) end; equal(count, 0)
		f:scan(); equal(count, 1)
		local died = f.other.Character.Humanoid.Died:Count()
		for _ = 1, 20 do f:scan() end
		equal(f.hoverParams, 1)
		equal(f.other.Character.Humanoid.Died:Count(), died); equal(#f.background, 0)
		equal(f.frame.Visible, false); equal(f.frame.Position, nil)
	end)
	test("mobile shift-lock indicator starts hidden and resets after character removal", function()
		local f = mobileFixture(); equal(f.mobileFrame.ShiftLockToogled.Visible, false)
		f.mobileFrame.ShiftLock.Activated:Fire(); equal(f.mobileFrame.ShiftLockToogled.Visible, true)
		f.player.CharacterRemoving:Fire(f.player.Character)
		equal(f.mobileFrame.ShiftLockToogled.Visible, false); equal(f.mobileFrame.MobileCrosshair.Visible, false)
		f.ui.PreferredInput = "Desktop"; f.preferredChanged:Fire(); f.mobileFrame.ShiftLock.Activated:Fire()
		equal(f.mobileFrame.ShiftLockToogled.Visible, false); equal(f.shifted, false)
	end)
	test("weapon GUI cursor leaves native pointer changes intact across shift-lock toggles", function()
		local f = cursorFixture(); local knife = child(f.player.Character, "Tool", "KnifeA")
		f.player.Mouse.Icon = "native-unlocked"; f:tick(); equal(f.player.Mouse.Icon, "native-unlocked")
		knife.Parent = f.player.Backpack; equal(f.player.Mouse.Icon, "native-unlocked")
		equal(f.cursorGui.Enabled, false); equal(f.cursorGui.WhiteDot.Visible, false); equal(f.cursorGui.Cursor.Visible, false)
	end)
	test("default knife and revolver cursors use requested image alongside the shared white dot", function()
		local config = load("CursorConfig"); equal(config.Knife.Image, "rbxassetid://92817416767688")
		equal(config.Revolver.Equipped.Image, "rbxassetid://92817416767688")
		equal(config.Revolver.Aiming.Image, config.Revolver.Equipped.Image); equal(config.WhiteDotEnabled, true)
		equal(config.ShowOnTouch, true)
	end)
	test("native pointer stays hidden through ADS release and restores on weapon release", function()
		local f = cursorFixture(); local gun = child(f.player.Character, "Tool", "GunA")
		equal(f.ui.MouseIconEnabled, false); equal(f.cursorGui.Cursor.Visible, true)
		f.visibility.Acquire("RevolverAimCamera"); f.visibility.Release("RevolverAimCamera")
		equal(f.ui.MouseIconEnabled, false)
		gun.Parent = f.player.Backpack; equal(f.ui.MouseIconEnabled, true); equal(f.cursorGui.Enabled, false)
	end)
	test("cursor ownership restores menus and respects originally hidden pointers", function()
		local f = cursorFixture(); f.ui.MouseIconEnabled = false
		local gun = child(f.player.Character, "Tool", "GunA"); gun.Parent = f.player.Backpack
		equal(f.ui.MouseIconEnabled, false)
		f.ui.MouseIconEnabled = true; gun.Parent = f.player.Character
		f.guiService.MenuIsOpen = true; f:tick(); equal(f.ui.MouseIconEnabled, true)
		equal(f.cursorGui.Enabled, false)
		f.guiService.MenuIsOpen = false; f:tick(); equal(f.ui.MouseIconEnabled, false)
		f.player.CharacterRemoving:Fire(f.player.Character); equal(f.ui.MouseIconEnabled, true)
	end)
	test("hover uses a body silhouette Highlight with no remote lookup before double-click", function()
		local f = hoverFixture(); equal(f.highlight.ClassName, "Highlight"); equal(f.highlight.FillTransparency, 1)
		local remoteLookups = 0; local find = f.RS.FindFirstChild
		rawset(f.RS, "FindFirstChild", function(self, name)
			if name == "Remotes" then remoteLookups += 1 end
			return find(self, name)
		end)
		for _ = 1, 50 do f:scan() end
		equal(f.profileRequest.ServerCalls, nil); equal(remoteLookups, 0); equal(#f.background, 0)
		local input = {UserInputType = f.env.Enum.UserInputType.MouseButton1}
		f.ui.InputBegan:Fire(input, false); equal(remoteLookups, 0)
		f.time += 0.2; f.ui.InputBegan:Fire(input, false)
		equal(remoteLookups, 1); equal(f.profileRequest.ServerCalls, 1)
	end)
	test("native cursor visibility releases correctly regardless of ownership order", function()
		for _, releaseAimFirst in ipairs({true, false}) do
			local f = cursorFixture(); local visibility = f.visibility
			visibility.Acquire("aim"); visibility.Acquire("weapon")
			visibility.Release(releaseAimFirst and "aim" or "weapon"); equal(f.ui.MouseIconEnabled, false)
			visibility.Release(releaseAimFirst and "weapon" or "aim"); equal(f.ui.MouseIconEnabled, true)
			visibility.Release("weapon"); equal(f.ui.MouseIconEnabled, true)
		end
	end)
	test("knife cursor shows the configured image and white dot together without a native pointer", function()
		local f = cursorFixture(); f.cursorConfig.Knife.Image = "rbxassetid://92817416767688"
		local knife = child(f.player.Character, "Tool", "KnifeA")
		equal(f.cursorGui.Cursor.Visible, true); equal(f.cursorGui.WhiteDot.Visible, true)
		equal(f.cursorGui.Cursor.Image, f.cursorConfig.Knife.Image); equal(f.ui.MouseIconEnabled, false)
		equal(f.cursorGui.WhiteDot.ZIndex, 2); equal(f.cursorGui.Cursor.ZIndex, 1)
		equal(f.cursorGui.WhiteDot.Position, f.cursorGui.Cursor.Position)
		f.cursorConfig.ShowOnTouch = true; f.inputType = f.env.Enum.UserInputType.Touch; f:tick()
		equal(f.cursorGui.Cursor.Visible, true); equal(f.cursorGui.WhiteDot.Visible, true)
		equal(f.cursorGui.Cursor.Position.X, 500)
		knife.Parent = f.player.Backpack; equal(f.cursorGui.Enabled, false); equal(f.ui.MouseIconEnabled, true)
	end)
	test("GUI crosshairs never overwrite native shift-lock icons or poison the saved unlocked cursor", function()
		local f = cursorFixture(); local nativeIcon, writes = "original", 0
		f.player.Mouse = setmetatable({}, {__index = function(_, key) if key == "Icon" then return nativeIcon end end,
			__newindex = function(_, key, value) if key == "Icon" then writes += 1; nativeIcon = value end end})
		local knife = child(f.player.Character, "Tool", "KnifeA")
		local savedIcon = nativeIcon
		nativeIcon = "rbxasset://textures/MouseLockedCursor.png"; f.ui.MouseBehavior = "LockCenter"; f:tick()
		equal(f.player.Mouse.Icon, nativeIcon); equal(f.ui.MouseIconEnabled, false)
		nativeIcon = savedIcon; f.ui.MouseBehavior = "Default"; f:tick()
		knife.Parent = f.player.Backpack
		equal(writes, 0); equal(f.player.Mouse.Icon, "original"); equal(f.ui.MouseBehavior, "Default")
		equal(f.ui.MouseIconEnabled, true)
	end)
	test("hover switches only Enabled on prepared highlights without creating or retargeting them", function()
		local f = hoverFixture(); equal(f.hoverCreates, 1); equal(f.highlight.Enabled, false)
		local third = f:createPlayer(3); third.Character.Parent = f.workspace; f.Players.PlayerAdded:Fire(third)
		local thirdHighlight = f.workspace.PlayerHoverHighlight_3; equal(f.hoverCreates, 2)
		local otherHit = f.hit; local thirdHit = child(third.Character, "Part", "Head")
		for _ = 1, 25 do
			f.hit = otherHit; f:scan(); equal(f.highlight.Enabled, true); equal(thirdHighlight.Enabled, false)
			f.hit = thirdHit; f:scan(); equal(f.highlight.Enabled, false); equal(thirdHighlight.Enabled, true)
			f.hit = nil; f:scan(); equal(f.highlight.Enabled, false); equal(thirdHighlight.Enabled, false)
		end
		equal(f.hoverCreates, 2); equal(f.highlight.Adornee, f.other.Character); equal(thirdHighlight.Adornee, third.Character)
		equal(f.profileRequest.ServerCalls, nil); equal(f.thumbnailReads, 0)
	end)
	test("prepared hover highlights clean old characters and player connections on respawn and leave", function()
		local f = hoverFixture(); f:scan(); local oldCharacter, oldHighlight = f.other.Character, f.highlight
		f:character(f.other); f.other.Character.Parent = f.workspace; f.hit = child(f.other.Character, "Part", "Head")
		local newHighlight = f.workspace.PlayerHoverHighlight_2; assert(newHighlight ~= oldHighlight)
		equal(oldHighlight.Parent, nil); equal(oldCharacter.Humanoid.Died:Count(), 0)
		f:scan(); equal(newHighlight.Enabled, true); equal(f.hoverCreates, 2)
		f.Players.PlayerRemoving:Fire(f.other); equal(newHighlight.Parent, nil)
		equal(f.other.CharacterAdded:Count(), 0); equal(f.other.CharacterRemoving:Count(), 0)
	end)
	test("hover menu cache follows added and removed frames without scanning GUI children", function()
		local f = hoverFixture(); local frames = f.frame.Parent.Frames
		rawset(frames, "GetChildren", function() error("hover must use its menu cache") end)
		f:scan(); equal(f.highlight.Enabled, true)
		local profile = child(frames, "Frame", "NewProfile"); profile.Visible = true
		f:scan(); equal(f.highlight.Enabled, false)
		profile.Visible = false; f:scan(); equal(f.highlight.Enabled, true)
		profile.Visible = true; f:scan(); equal(f.highlight.Enabled, false)
		profile:Destroy(); f:scan(); equal(f.highlight.Enabled, true)
	end)
	local function leaderboardServerFixture(unready)
		local f = fixture(); f.player = f:createPlayer(1); f.player:SetAttribute("DataReady", not unready)
		child(f.player.leaderstats, "IntValue", "Kills", 5); child(f.player.leaderstats, "IntValue", "XP", 150)
		f.player.leaderstats.Cash.Value = 250
		f.request = child(child(f.remotes, "Folder", "Leaderboards"), "RemoteEvent", "RequestLeaderboards")
		f.dataConfig = f:load("DataConfig", f.modulesFolder)
		f.modules[child(f.modulesFolder, "ModuleScript", "CalculateLevel")] = {GetLevel = function(xp) return math.floor(xp/100) end}
		f.stores, f.nameReads = {}, 0
		function f.Players:GetNameFromUserIdAsync(id) f.nameReads += 1; return "Offline" .. id end
		f.DataStore.GetOrderedDataStore = function(_, name, scope)
			local store = {name = name, scope = scope, values = {}}; table.insert(f.stores, store)
			function store:SetAsync(key, value) self.values[key] = value end
			function store:GetSortedAsync()
				return {GetCurrentPage = function() return scope == nil and {{key = "999", value = 1000000}} or {} end}
			end
			return store
		end
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.task.defer = function(fn) fn() end
		f.env.task.wait = function() coroutine.yield() end
		f.boards = f:load("Leaderboards", f.dataFolder, "LeaderboardsHandler")
		f.loop = f.background[#f.background]
		return f
	end
	test("leaderboards exclude old global-scope players without deleting their records", function()
		local f = leaderboardServerFixture(); local loop = coroutine.create(f.loop); assert(coroutine.resume(loop))
		for _, store in ipairs(f.stores) do equal(store.scope, f.dataConfig.GetLeaderboardScope()) end
		local cache = f.request.LastClientArgs[1]
		for _, name in ipairs({"Gold", "Kills", "Levels"}) do equal(#cache[name], 1); equal(cache[name][1].UserId, 1) end
		equal(cache.Gold[1].Value, 250); equal(f.nameReads, 0)
		local oldScope = f.dataConfig.GetLeaderboardScope(); f.dataConfig.ProfileStoreName = "NewPlayerData"
		assert(f.dataConfig.GetLeaderboardScope() ~= oldScope)
	end)
	test("leaderboard stat listeners bind after hydration and disconnect when leaving", function()
		local f = leaderboardServerFixture(true); equal(f.player.leaderstats.Kills.Changed:Count(), 0)
		f.player:SetAttribute("DataReady", true); equal(f.player.leaderstats.Kills.Changed:Count(), 1)
		f.player.leaderstats.Kills.Value = 15; equal(f.request.LastClientArgs[1].Kills[1].Value, 15)
		f.Players.PlayerRemoving:Fire(f.player); equal(f.player.leaderstats.Kills.Changed:Count(), 0)
	end)
	test("yielding leaderboard writes coalesce updates and disconnect departure hooks before backend completion", function()
		local f=leaderboardServerFixture(); local writes=0
		for _,store in ipairs(f.stores) do
			function store:SetAsync(key,value) writes+=1; coroutine.yield(); self.values[key]=value end
		end
		local first=coroutine.create(f.background[1]); assert(coroutine.resume(first)); equal(writes,1)
		for value=1,20 do
			f.player.leaderstats.Cash.Value=value; f.boards.UpdatePlayer(f.player)
			local latest=coroutine.create(f.background[#f.background]); assert(coroutine.resume(latest)); equal(coroutine.status(latest),"dead")
		end
		equal(writes,1)
		f.Players.PlayerRemoving:Fire(f.player); equal(f.player.leaderstats.Cash.Changed:Count(),0)
		for _=1,8 do if coroutine.status(first)=="suspended" then assert(coroutine.resume(first)) end end
		equal(coroutine.status(first),"dead"); assert(writes<=6)
		for _,store in ipairs(f.stores) do if store.name:find("Gold") then equal(store.values["1"],20) end end
	end)
	local function leaderboardClientFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		f.workspace = object("Workspace", "Workspace"); f.env.workspace = f.workspace
		local boards = child(child(f.workspace, "Model", "IntermissionMap"), "Folder", "Leaderboards")
		f.scrolls = {}
		for _, name in ipairs({"Levels", "Kills", "Gold"}) do
			local surface = child(child(child(boards, "Model", name), "Part", "Bottom"), "SurfaceGui", "Leaderboard")
			f.scrolls[name] = child(surface, "ScrollingFrame", "ScrollingFrame")
			child(f.scrolls[name], "Frame", "OldTopPlayer")
		end
		local templates = child(child(f.RS, "Folder", "UITemplates"), "Folder", "LeaderboardTemplates")
		for _, name in ipairs({"Levels", "Kills", "Gold"}) do for _, suffix in ipairs({"1", "2", "3", "Others"}) do
			local entry = child(templates, "Frame", name .. "Template" .. suffix)
			child(entry, "ImageLabel", "Profile"); local info = child(entry, "Frame", "Info")
			child(child(info, "Frame", "Rank"), "TextLabel", "Rank")
			child(child(info, "Frame", "Username"), "TextLabel", "Username")
			child(child(entry, "Frame", name), "TextLabel", name)
		end end
		f.thumbnails = 0
		f.modules[child(f.modulesFolder, "ModuleScript", "GetThumbnail")] = {GetThumbnail = function(id) f.thumbnails += 1; return "thumb-" .. id end}
		f.modules[child(f.modulesFolder, "ModuleScript", "Abbreviate")] = {Ab = tostring}
		f.request = child(child(f.remotes, "Folder", "Leaderboards"), "RemoteEvent", "RequestLeaderboards")
		f.request.OnSend = function() f.request.OnClientEvent:Fire({Levels = {}, Kills = {}, Gold = {}}) end
		local getService = f.game.GetService
		f.game.GetService = function(self, name) if name == "Workspace" then return f.workspace end; return getService(self, name) end
		local function ctor(...) return {...} end
		f.env.UDim2, f.env.Vector2, f.env.Color3 = {new = ctor}, {new = ctor}, {fromRGB = ctor}
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f:load("LeaderboardsClient", child(f.RS, "Folder", "Client"))
		function f.publish(rows) f.request.OnClientEvent:Fire({Levels = rows, Kills = rows, Gold = rows}) end
		return f
	end
	test("leaderboard client subscribes before requesting and clears preexisting old rows", function()
		local f = leaderboardClientFixture(); equal(f.request.ServerCalls, 1)
		for _, scroll in pairs(f.scrolls) do equal(#scroll:GetChildren(), 0) end
	end)
	test("leaderboard rows survive unchanged updates and portrait fetches coalesce across boards", function()
		local f = leaderboardClientFixture(); local rows = {{UserId = 1, Name = "Current", Value = 10}}
		f.publish(rows); local entry = f.scrolls.Gold:GetChildren()[1]; equal(#f.background, 1)
		f.background[1](); equal(f.thumbnails, 1); equal(entry.Profile.Image, "thumb-1")
		f.publish(rows); equal(f.scrolls.Gold:GetChildren()[1], entry); equal(#f.background, 1)
		rows[1].Value = 20; f.publish(rows); equal(f.scrolls.Gold:GetChildren()[1], entry); equal(entry.Gold.Gold.Text, "20 GOLD")
		f.publish({}); equal(entry.Parent, nil); equal(#f.scrolls.Gold:GetChildren(), 0)
	end)
	test("leaderboard portraits have at most four active fetches and stale rows cannot reappear", function()
		local f = leaderboardClientFixture(); local rows = {}
		for id = 1, 8 do table.insert(rows, {UserId = id, Name = "Player" .. id, Value = 100-id}) end
		f.publish(rows); equal(#f.background, 4)
		f.publish({}); for _, job in ipairs(f.background) do job() end
		equal(f.thumbnails, 8); equal(#f.scrolls.Gold:GetChildren(), 0)
		f.publish(rows); equal(#f.background, 8); equal(#f.scrolls.Gold:GetChildren(), 8)
	end)
	assert(passed > 0, "No game systems tests matched the filter")
	print(string.format("%d game systems tests passed", passed))
end
