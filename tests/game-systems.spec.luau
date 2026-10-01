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
		if key == "Value" then self.Changed:Fire(value) end
	end
end
local function object(class, name, parent)
	local result = setmetatable({ _props = { ClassName = class, Name = name or class }, _children = {}, _attributes = {}, _signals = {}, _attributeSignals = {} }, objectMeta)
	for _, key in ipairs({ "ChildAdded", "ChildRemoved", "Changed", "CharacterAdded", "CharacterRemoving", "PlayerAdded", "PlayerRemoving", "OnServerEvent", "OnClientEvent", "Died", "Activated" }) do result._signals[key] = signal() end
	result.Parent = parent
	return result
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance" or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
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
function methods:FireServer(...) self.LastServerArgs = { ... }; self.ServerCalls = (self.ServerCalls or 0) + 1 end
function methods:FireAllClients(...) self.LastClientArgs = { ... }; self.ClientCalls = (self.ClientCalls or 0) + 1 end
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
			task = { spawn = function(fn) fn() end, delay = function(delay, fn) table.insert(f.delayed, { delay = delay, fn = fn }) end,
				wait = function(delay) f.time += delay or 0.1; if f.onWait then f.onWait() end end },
			Enum = { ProductPurchaseDecision = { PurchaseGranted = "Granted", NotProcessedYet = "Retry" } },
		}
		f.modulesFolder = child(f.RS, "Folder", "Modules")
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

	test("burger heals 33, enforces 2 seconds, expires after 3 bites", function()
		local f = foodFixture(); local humanoid = f.player.Character.Humanoid
		f.tool.Parent = f.player.Character
		f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 34); equal(f.player:GetAttribute("FoodUses"), 2)
		f.time += 1.99; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 34)
		f.time += 0.01; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 67)
		f.time += 2; f.eat:Fire(f.player, f.tool); equal(humanoid.Health, 100)
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
		f.time += 1; f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 1)
		f.time += 1; f.runService.Heartbeat:Fire(0.1); f.tool.Activated:Fire(); equal(f.remotes.Food.Eat.ServerCalls, 2)
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

	local frameMeta = { __mul = function(a, b) return { origin = a, offset = b } end }
	local function mapFixture()
		local f = fixture()
		f.workspace = object("Workspace", "Workspace"); f.env.workspace = f.workspace
		f.game.Players = f.Players
		f.env.CFrame = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, frameMeta) end }
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
		f.maps = f:load("Maps", f.gameFolder, "SpawnMap")
		return f
	end
	test("map startup removes untracked duplicates and nested map copies, preserving lobby", function()
		local f = mapFixture()
		equal(f.legacy.Parent, nil); equal(f.duplicate.Parent, nil); equal(f.nested.Parent, nil)
		equal(f.lobby.Parent, f.workspace); equal(f.other.Parent, f.workspace); equal(f.terrain.Parent, f.workspace)
		equal(f.SS.MapA.Parent, f.SS, "ServerStorage template preserved")
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

	local vector2Meta = { __div = function(v, divisor) return { X = v.X / divisor, Y = v.Y / divisor } end }
	local function cursorFixture()
		local f = fixture(); f.player = f:createPlayer(1); f.Players.LocalPlayer = f.player
		f.player.Mouse = { Icon = "original" }
		child(f.player, "Folder", "PlayerGui")
		f.cursorConfig = f:load("CursorConfig", f.modulesFolder)
		f.cursorConfig.Knife.Image, f.cursorConfig.Revolver.Equipped.Image, f.cursorConfig.Revolver.Aiming.Image = "knife", "hip", "aim"
		f.modules[child(f.modulesFolder, "ModuleScript", "KnivesInfo")] = { KnifeA = {} }
		f.modules[child(f.modulesFolder, "ModuleScript", "RevolversInfo")] = { GunA = {} }
		f.clientFolder = child(f.RS, "Folder", "Client")
		local cameraModule = child(child(f.clientFolder, "Folder", "Modules"), "ModuleScript", "RevolverAimCamera")
		f.modules[cameraModule] = { IsAiming = function() return f.aiming == true end }
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
		f.env.UDim2 = { fromOffset = function(x, y) return { X = x, Y = y } end }
		f:load("Cursor", f.clientFolder, "HandleWeaponCursor")
		f.cursorGui = f.player.PlayerGui.WeaponCursor
		function f:tick() self.time += 0.1; for _, fn in pairs(self.bindings) do fn() end end
		return f
	end
	test("weapon cursors apply only to equipped knife/revolver and restore for food or no tool", function()
		local f = cursorFixture(); equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		local knife = child(f.player.Character, "Tool", "KnifeA"); equal(f.player.Mouse.Icon, "knife")
		knife.Parent = f.player.Backpack; equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		local burger = child(f.player.Character, "Tool", "Burger"); burger:SetAttribute("FoodItem", "Burger")
		f:tick(); equal(f.player.Mouse.Icon, "original")
		burger:Destroy(); child(f.player.Character, "Tool", "GunA"); equal(f.player.Mouse.Icon, "hip")
	end)
	test("aim cursor appears centered below white-dot HUD without changing mouse lock", function()
		local f = cursorFixture(); child(f.player.Character, "Tool", "GunA")
		equal(f.cursorGui.Enabled, false); equal(f.player.Mouse.Icon, "hip")
		f.aiming, f.ui.MouseIconEnabled, f.ui.MouseBehavior = true, false, "LockCenter"; f:tick()
		equal(f.player.Mouse.Icon, "aim"); equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Image, "aim")
		equal(f.cursorGui.Cursor.Position.X, 500); equal(f.cursorGui.Cursor.Position.Y, 300)
		equal(f.cursorGui.DisplayOrder, 19); equal(f.ui.MouseIconEnabled, false); equal(f.ui.MouseBehavior, "LockCenter")
		f.aiming, f.ui.MouseIconEnabled, f.ui.MouseBehavior = false, true, "Default"; f:tick()
		equal(f.player.Mouse.Icon, "hip"); equal(f.cursorGui.Enabled, false)
	end)
	test("hidden native knife cursor follows pointer and restores on menu/chat/death", function()
		local f = cursorFixture(); child(f.player.Character, "Tool", "KnifeA"); f.ui.MouseIconEnabled = false; f:tick()
		equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Position.X, 123)
		f.guiService.MenuIsOpen = true; f:tick(); equal(f.player.Mouse.Icon, "original"); equal(f.cursorGui.Enabled, false)
		f.guiService.MenuIsOpen = false; f.textBox = {}; f:tick(); equal(f.player.Mouse.Icon, "original")
		f.textBox = nil; f:tick(); equal(f.player.Mouse.Icon, "knife")
		f.player.Character.Humanoid.Health = 0; f:tick(); equal(f.player.Mouse.Icon, "original")
	end)
	test("weapon cursor respects empty presets, touch setting and respawn cleanup", function()
		local f = cursorFixture(); local gun = child(f.player.Character, "Tool", "GunA")
		f.cursorConfig.Revolver.Equipped.Image = ""; f:tick(); equal(f.player.Mouse.Icon, "original")
		f.cursorConfig.Revolver.Equipped.Image = "hip"; f.inputType = f.env.Enum.UserInputType.Touch; f:tick(); equal(f.cursorGui.Enabled, false)
		f.cursorConfig.ShowOnTouch = true; f:tick(); equal(f.cursorGui.Enabled, true); equal(f.cursorGui.Cursor.Position.X, 500)
		f:character(f.player); equal(f.player.Mouse.Icon, "original"); equal(next(f.bindings), nil)
		gun.Activated:Fire(); equal(f.cursorGui.Enabled, false)
	end)

	local function profileFixture()
		local f = fixture(); f.player = f:createPlayer(1)
		child(child(f.RS, "Folder", "KeyBinds"), "ModuleScript", "KeybindValidation")
		f.modules[f.RS.KeyBinds.KeybindValidation] = { GetDefaults = function() return {} end }
		child(child(f.remotes, "Folder", "Tutorial"), "RemoteEvent", "StartTutorial")
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
	end)

	local function purchaseFixture()
		local f = profileFixture()
		local shop = child(f.remotes, "Folder", "ShopRemotes")
		child(child(shop, "Folder", "PurchaseGold"), "RemoteEvent", "PurchaseGoldRemote")
		child(child(shop, "Folder", "Gamepass"), "RemoteEvent", "BuyGamePass")
		child(child(shop, "Folder", "VIP"), "RemoteEvent", "VIPStatus")
		f.modules[child(f.modulesFolder, "ModuleScript", "ProductIDS")] = { [100] = 100 }
		f.modules[child(f.servicesFolder, "ModuleScript", "VIPService")] = { HasVIPByUserId = function() return false end }
		f:load("Purchases", f.servicesFolder, "PurchaseHandler")
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
	test("leaderboard writes use loaded current stats and skip unchanged values", function()
		local f = fixture(); f.player = f:createPlayer(1)
		child(f.player.leaderstats, "IntValue", "Kills", 5); child(f.player.leaderstats, "IntValue", "XP", 150)
		f.player.leaderstats.Cash.Value = 250
		child(child(f.remotes, "Folder", "Leaderboards"), "RemoteEvent", "RequestLeaderboards")
		f.modules[child(f.modulesFolder, "ModuleScript", "CalculateLevel")] = { GetLevel = function(xp) return math.floor(xp / 100) end }
		f.stores = {}; f.writes = 0
		f.DataStore.GetOrderedDataStore = function(_, name)
			local store = { values = {} }; f.stores[name] = store
			function store:SetAsync(key, value) f.writes += 1; self.values[key] = value end
			return store
		end
		f.env.task.spawn = function(fn) table.insert(f.background, fn) end
		f.env.task.defer = function(fn) fn() end
		local boards = f:load("Leaderboards", f.dataFolder, "LeaderboardsHandler")
		local function update() boards.UpdatePlayer(f.player); f.background[#f.background]() end
		f.player:SetAttribute("DataReady", false); update(); equal(f.writes, 0)
		f.player:SetAttribute("DataReady", true); update(); equal(f.writes, 3)
		equal(f.stores["Leaderboard_Gold_Datastore1.0"].values["1"], 250)
		update(); equal(f.writes, 3)
		f.player.leaderstats.Cash.Value = 333; update(); equal(f.writes, 4)
		equal(f.stores["Leaderboard_Gold_Datastore1.0"].values["1"], 333)
	end)

	local function questFixture(failRead)
		local f = fixture(); f.writes = 0; f.failRead = failRead
		local remotes = child(f.remotes, "Folder", "Quests")
		f.request = child(remotes, "RemoteEvent", "RequestQuests")
		f.claim = child(remotes, "RemoteEvent", "ClaimQuestReward")
		f.DataStore.GetDataStore = function() return {
			GetAsync = function() if f.failRead then error("Simulated outage") end; return nil end,
			UpdateAsync = function(_, _, transform) f.writes += 1; f.saved = transform() end,
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
	test("successful nil quest read creates a new writable record", function()
		local f = questFixture(false)
		f.quests.AddProgress(f.player, "WINS", 2); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150); equal(f.writes, 1)
		f.time += 2; f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150, "No duplicate claim")
	end)
	test("quest data retry recovers without writing during the failed read", function()
		local f = questFixture(true); equal(f.writes, 0)
		f.failRead = false; f.delayed[1].fn()
		equal(f.request.LastClientArgs[2].Loading, nil)
		f.quests.AddProgress(f.player, "WINS", 2); f.claim.OnServerEvent:Fire(f.player, "WIN_2_ROUNDS")
		equal(f.player.leaderstats.Cash.Value, 150); equal(f.writes, 1)
	end)
	print(string.format("%d game systems tests passed", passed))
end
