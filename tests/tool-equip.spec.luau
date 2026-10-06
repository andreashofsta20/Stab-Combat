-- Real hotbar modules, with delayed native equips and independent replication events.
local function signal()
	local listeners = {}
	local event = {}
	function event:Connect(fn)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, {fn = fn, connection = connection})
		return connection
	end
	function event:Fire(...)
		for _, listener in ipairs(table.clone(listeners)) do
			if listener.connection.Connected then listener.fn(...) end
		end
	end
	return event
end
local methods, meta = {}, {}
function meta.__index(self, key)
	if methods[key] then return methods[key] end
	if self.props[key] ~= nil then return self.props[key] end
	if self.signals[key] then return self.signals[key] end
	for _, child in ipairs(self.children) do if child.Name == key then return child end end
end
function meta.__newindex(self, key, value)
	local old = self.props[key]
	if old == value then return end
	if key == "Parent" then
		if old then local index = table.find(old.children, self); if index then table.remove(old.children, index) end end
		self.props.Parent = value
		if old then old.ChildRemoved:Fire(self) end
		if value then table.insert(value.children, self); value.ChildAdded:Fire(self) end
	else self.props[key] = value end
	if self.signals["Property_" .. key] then self.signals["Property_" .. key]:Fire() end
	if key == "Value" then self.Changed:Fire(value) end
end
local function object(class, name, parent)
	local value = setmetatable({props = {ClassName = class, Name = name or class}, children = {}, attributes = {}, signals = {}, attributeSignals = {}}, meta)
	for _, key in ipairs({"ChildAdded", "ChildRemoved", "CharacterAdded", "CharacterRemoving", "PlayerRemoving", "InputBegan", "OnServerEvent", "OnClientEvent", "Changed", "MouseButton1Up", "MouseEnter", "MouseLeave"}) do value.signals[key] = signal() end
	value.Parent = parent
	return value
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance" or class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
	local out = {}
	for _, child in ipairs(self.children) do table.insert(out, child); for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end end
	return out
end
function methods:FindFirstChild(name)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name), "Missing " .. name .. " below " .. self.Name) end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:SetAttribute(name, value)
	self.attributes[name] = value
	if self.attributeSignals[name] then self.attributeSignals[name]:Fire() end
end
function methods:GetAttributeChangedSignal(name)
	self.attributeSignals[name] = self.attributeSignals[name] or signal()
	return self.attributeSignals[name]
end
function methods:GetPropertyChangedSignal(name)
	self.signals["Property_" .. name] = self.signals["Property_" .. name] or signal()
	return self.signals["Property_" .. name]
end
function methods:Destroy()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent, self.Destroyed = nil, true
end
function methods:Clone()
	local copy = object(self.ClassName, self.Name)
	for key, value in pairs(self.props) do if key ~= "Parent" then copy[key] = value end end
	for key, value in pairs(self.attributes) do copy:SetAttribute(key, value) end
	for _, child in ipairs(self.children) do child:Clone().Parent = copy end
	return copy
end
function methods:EquipTool(tool)
	self.EquipCalls = (self.EquipCalls or 0) + 1
	self.EquipStartedInBackpack = tool.Parent and tool.Parent:IsA("Backpack")
	if self.FailEquips and self.FailEquips > 0 then self.FailEquips -= 1; return end
	tool.Parent = self.Parent
end
function methods:FireClient(...) self.ClientArgs = {...}; self.ClientCalls = (self.ClientCalls or 0) + 1 end
function methods:FireServer(...) self.ServerArgs = {...}; self.ServerCalls = (self.ServerCalls or 0) + 1 end
local function child(parent, class, name, value)
	local item = object(class, name, parent)
	if value ~= nil then item.Value = value end
	return item
end
local function equal(actual, expected, label)
	assert(actual == expected, (label or "Value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn)
		if not ok then error(name .. ": " .. tostring(err), 0) end
		passed += 1; print("PASS " .. name)
	end
	local function fixture()
		local f = {time = 100, delayed = {}, modules = {}, sounds = 0}
		f.players, f.rs, f.ss = object("Players", "Players"), object("Folder", "ReplicatedStorage"), object("Folder", "ServerStorage")
		f.player = child(f.players, "Player", "Player"); f.player.UserId = 1; f.players.LocalPlayer = f.player
		f.player:SetAttribute("DataReady", true)
		f.backpack = child(f.player, "Backpack", "Backpack")
		f.stats = child(f.player, "Folder", "leaderstats")
		child(f.stats, "StringValue", "EquippedKnife", "KnifeA"); child(f.stats, "StringValue", "EquippedGun", "GunA")
		f.quantity = child(child(child(f.stats, "Folder", "Inventory"), "Folder", "KnifeA"), "IntValue", "Quantity", 1)
		child(child(child(f.stats, "Folder", "RevolverInventory"), "Folder", "GunA"), "IntValue", "Quantity", 1)
		f.knives, f.guns = child(f.ss, "Folder", "Knives"), child(f.ss, "Folder", "Revolvers")
		f.knifeTemplate, f.gunTemplate = child(f.knives, "Tool", "KnifeA"), child(f.guns, "Tool", "GunA")
		for _, template in ipairs({f.knifeTemplate, f.gunTemplate}) do
			template.RequiresHandle, template.Enabled = true, false
			local handle = child(template, "Part", "Handle")
			handle.Anchored, handle.CanCollide, handle.CanTouch, handle.Massless = true, true, true, false
		end
		f.remotes = child(f.rs, "Folder", "Remotes")
		f.hotbarRemotes = child(f.remotes, "Folder", "HotBar")
		f.equip = child(f.hotbarRemotes, "RemoteEvent", "Equip"); f.equipped = child(f.hotbarRemotes, "RemoteEvent", "EquippedClient")
		f.startRemotes = child(f.remotes, "Folder", "StartGameClient")
		for _, name in ipairs({"WipeTools", "RecieveTools", "RequestKnife", "PlayerResetted"}) do child(f.startRemotes, "RemoteEvent", name) end
		f.combat, f.client = object("Folder", "CombatHandler"), object("Folder", "Client")
		f.modules[child(f.combat, "ModuleScript", "FoodService")] = {Store = function() return false end, GetTool = function() return nil end}
		f.ui = {InputBegan = signal(), GetFocusedTextBox = function() return f.textBox end}
		local services = {Players = f.players, ReplicatedStorage = f.rs, ServerStorage = f.ss, UserInputService = f.ui, Lighting = {}, TweenService = {Create = function() return {Play = function() end} end}}
		f.env = {game = {Players = f.players, ReplicatedStorage = f.rs, IsLoaded = function() return true end, GetService = function(_, name) return assert(services[name], name) end},
			Instance = {new = object}, require = function(module) return assert(f.modules[module], "Unknown module " .. tostring(module and module.Name)) end,
			os = {clock = function() return f.time end}, task = {wait = function() end, delay = function(seconds, fn) table.insert(f.delayed, {at = f.time + seconds, fn = fn}) end},
			UDim2 = {new = function(...) return {...} end, fromScale = function(...) return {...} end},
			Color3 = {new = function(...) return {...} end, fromHex = function(v) return v end, fromRGB = function(...) return {...} end}, TweenInfo = {new = function(...) return {...} end},
			Enum = {Font = {GothamBold = "Bold"}, EasingStyle = {Quad = "Quad"}, EasingDirection = {Out = "Out"}, KeyCode = {One = "One", Two = "Two", Three = "Three"}, UserInputType = {Keyboard = "Keyboard"}}}
		function f:spawn()
			local character = object("Model", "Character")
			local humanoid = child(character, "Humanoid", "Humanoid"); humanoid.Health = 100
			child(character, "Part", "Right Arm")
			self.player.Character = character
			return character
		end
		f:spawn()
		function f:advance(seconds)
			self.time += seconds
			for _, entry in ipairs(table.clone(self.delayed)) do
				if entry.at <= self.time then local index = table.find(self.delayed, entry); if index then table.remove(self.delayed, index); entry.fn() end end
			end
		end
		function f:loadServer()
			self.env.script = child(self.combat, "ModuleScript", "HandleHotbar")
			load("ServerHotbar", self.env)
		end
		function f:loadClient()
			local moduleFolder = child(self.rs, "Folder", "Modules")
			self.modules[child(moduleFolder, "ModuleScript", "KnivesInfo")] = {KnifeA = {Image = "knife"}}
			self.modules[child(moduleFolder, "ModuleScript", "RevolversInfo")] = {GunA = {Image = "gun"}}
			self.modules[child(moduleFolder, "ModuleScript", "FoodConfig")] = {Capacity = 3, ToolName = "Burger"}
			self.modules[child(moduleFolder, "ModuleScript", "KeybindValidation")] = {ToEnum = function(key) return self.env.Enum.KeyCode[key] end}
			local clientModules = child(self.client, "Folder", "Modules")
			self.modules[child(clientModules, "ModuleScript", "SoundHandler")] = {PlaySound = function() self.sounds += 1 end}
			local binds = child(self.stats, "Folder", "KeyBinds")
			for i, key in ipairs({"One", "Two", "Three"}) do child(binds, "StringValue", "Slot" .. i, key) end
			child(self.rs, "BoolValue", "GameActive", true)
			local gui = child(self.player, "Folder", "PlayerGui"); local main = child(gui, "ScreenGui", "Main")
			self.bottom = child(main, "Frame", "Bottom")
			for i = 1, 3 do
				local slot = child(self.bottom, "ImageButton", tostring(i))
				child(slot, "Frame", "SlotSelected").Visible = false
				child(slot, "ImageLabel", "SlotImage")
			end
			self.env.script = child(self.client, "ModuleScript", "Hotbar")
			load("ClientHotbar", self.env)
		end
		return f
	end
	test("native equip uses the current backpack and initializes held physics", function()
		local f = fixture(); f:loadServer(); f.equip.OnServerEvent:Fire(f.player, "Knife")
		local tool, humanoid = f.player.Character.KnifeA, f.player.Character.Humanoid
		assert(tool); equal(humanoid.EquipCalls, 1); equal(humanoid.EquipStartedInBackpack, true)
		equal(tool.Enabled, true); equal(tool.CanBeDropped, false); equal(tool.Handle.Anchored, false)
		equal(tool.Handle.CanCollide, false); equal(tool.Handle.CanTouch, false); equal(tool.Handle.Massless, true)
	end)
	test("brief native equip refusal retries without reset or duplicate clones", function()
		local f = fixture(); f.player.Character.Humanoid.FailEquips = 1; f:loadServer()
		f.equip.OnServerEvent:Fire(f.player, "Knife"); local tool = f.backpack.KnifeA; assert(tool)
		f:advance(0.11); equal(f.player.Character.KnifeA, tool); equal(#f.backpack:GetChildren(), 0)
		equal(f.player.Character.Humanoid.EquipCalls, 2); equal(f.equipped.ClientCalls, 1)
	end)
	test("held knife waits for the spawn arm before native equip", function()
		local f = fixture(); f.player.Character["Right Arm"]:Destroy(); f:loadServer()
		f.equip.OnServerEvent:Fire(f.player, "Knife"); equal(f.player.Character.Humanoid.EquipCalls, nil)
		child(f.player.Character, "Part", "Right Arm"); f:advance(0.11)
		assert(f.player.Character.KnifeA); equal(f.player.Character.Humanoid.EquipCalls, 1)
	end)
	test("native equip retry never overrides a tool supplied by another system", function()
		local f = fixture(); f.player.Character.Humanoid.FailEquips = 1; f:loadServer()
		f.equip.OnServerEvent:Fire(f.player, "Knife"); local external = child(f.player.Character, "Tool", "External")
		f:advance(0.11); equal(external.Parent, f.player.Character); equal(f.player.Character:FindFirstChild("KnifeA"), nil)
		equal(#f.backpack:GetChildren(), 0)
	end)
	test("later accepted slot selection cancels a pending knife", function()
		local f = fixture(); f.player.Character.Humanoid.FailEquips = 1; f:loadServer()
		f.equip.OnServerEvent:Fire(f.player, "Knife"); local pending = f.backpack.KnifeA
		f.time += 0.11; f.equip.OnServerEvent:Fire(f.player, "Revolver")
		f:advance(0.11); assert(f.player.Character.GunA); equal(f.player.Character:FindFirstChild("KnifeA"), nil)
		equal(pending.Destroyed, true); equal(#f.backpack:GetChildren(), 0)
	end)
	test("retry cancellation follows respawn and the replacement backpack", function()
		local f = fixture(); local oldHumanoid = f.player.Character.Humanoid
		oldHumanoid.FailEquips = 1; f:loadServer(); f.equip.OnServerEvent:Fire(f.player, "Knife")
		local pending = f.backpack.KnifeA; f.backpack:Destroy(); f.backpack = child(f.player, "Backpack", "Backpack"); f:spawn()
		f:advance(0.11); equal(oldHumanoid.EquipCalls, 1); equal(pending.Destroyed, true)
		f.equip.OnServerEvent:Fire(f.player, "Knife"); assert(f.player.Character.KnifeA)
	end)
	test("losing ownership during a retry cannot grant the knife", function()
		local f = fixture(); f.player.Character.Humanoid.FailEquips = 1; f:loadServer()
		f.equip.OnServerEvent:Fire(f.player, "Knife"); f.quantity.Value = 0; f:advance(0.11)
		equal(f.player.Character:FindFirstChild("KnifeA"), nil); equal(#f.backpack:GetChildren(), 0)
	end)
	test("failed native equips stop after five attempts and can be retried later", function()
		local f = fixture(); local humanoid = f.player.Character.Humanoid; humanoid.FailEquips = 100
		f:loadServer(); f.equip.OnServerEvent:Fire(f.player, "Knife")
		for _ = 1, 6 do f:advance(0.11) end
		equal(humanoid.EquipCalls, 5); equal(#f.delayed, 0); equal(#f.backpack:GetChildren(), 0)
		humanoid.FailEquips = 0; f.equip.OnServerEvent:Fire(f.player, "Knife"); assert(f.player.Character.KnifeA)
	end)
	test("invalid templates retain the held gun; unready and dead requests are rejected", function()
		local f = fixture(); f:loadServer(); local gun = f.gunTemplate:Clone(); gun.Parent = f.player.Character
		f.knifeTemplate.Handle:Destroy(); f.equip.OnServerEvent:Fire(f.player, "Knife"); equal(gun.Parent, f.player.Character)
		f:advance(0.11); f.player:SetAttribute("DataReady", false); f.equip.OnServerEvent:Fire(f.player, "Revolver"); equal(gun.Parent, f.player.Character)
		f.player:SetAttribute("DataReady", true); f.player.Character.Humanoid.Health = 0; f.equip.OnServerEvent:Fire(f.player, "Revolver"); equal(gun.Parent, f.player.Character)
	end)
	test("cooldown drops duplicate requests without canceling the accepted equip", function()
		local f = fixture(); f:loadServer(); f.equip.OnServerEvent:Fire(f.player, "Knife"); local tool = f.player.Character.KnifeA
		f.equip.OnServerEvent:Fire(f.player, "Knife"); equal(f.player.Character.KnifeA, tool)
		f:advance(0.11); f.equip.OnServerEvent:Fire(f.player, "Knife"); equal(f.player.Character:FindFirstChild("KnifeA"), nil)
	end)
	test("late client wipe never deletes a fresh knife or replacement backpack tool", function()
		local f = fixture(); f.env.script = child(f.client, "ModuleScript", "RecieveTools"); load("RecieveTools", f.env)
		f.backpack:Destroy(); f.backpack = child(f.player, "Backpack", "Backpack")
		local held = f.knifeTemplate:Clone(); held.Parent = f.player.Character
		local stored = f.gunTemplate:Clone(); stored.Parent = f.backpack
		f.startRemotes.WipeTools.OnClientEvent:Fire()
		equal(held.Parent, f.player.Character); equal(stored.Parent, f.backpack); equal(held.Destroyed, nil)
	end)
	test("client recognizes a knife equipped before hotbar initialization", function()
		local f = fixture(); local held = f.knifeTemplate:Clone(); held.Parent = f.player.Character; f:loadClient()
		equal(f.bottom["1"].SlotSelected.Visible, true); equal(f.sounds, 1)
		f.equipped.OnClientEvent:Fire("Knife", true); equal(f.sounds, 1)
	end)
	test("current character tools override stale acknowledgements and unknown tools", function()
		local f = fixture(); f:loadClient(); local knife = f.knifeTemplate:Clone(); knife.Parent = f.player.Character
		knife:Destroy(); local gun = f.gunTemplate:Clone(); gun.Parent = f.player.Character
		f.equipped.OnClientEvent:Fire("Knife", true)
		equal(f.bottom["1"].SlotSelected.Visible, false); equal(f.bottom["2"].SlotSelected.Visible, true)
		child(f.player.Character, "Tool", "Unknown"); equal(f.bottom["1"].SlotSelected.Visible, false)
	end)
	test("respawn recognizes an already equipped knife and disconnects old character events", function()
		local f = fixture(); f:loadClient(); local old = f.player.Character; local current = f:spawn()
		f.knifeTemplate:Clone().Parent = current; f.player.CharacterAdded:Fire(current)
		equal(f.bottom["1"].SlotSelected.Visible, true)
		f.gunTemplate:Clone().Parent = old; equal(f.bottom["2"].SlotSelected.Visible, false)
	end)
	test("keyboard and button inputs share the server cooldown and respect focused text", function()
		local f = fixture(); f:loadClient()
		f.ui.InputBegan:Fire({UserInputType = "Keyboard", KeyCode = "One"}, false)
		f.bottom["2"].MouseButton1Up:Fire(); equal(f.equip.ServerCalls, 1)
		f.time += 0.11; f.bottom["2"].MouseButton1Up:Fire(); equal(f.equip.ServerCalls, 2); equal(f.equip.ServerArgs[1], "Revolver")
		f.time += 0.11; f.textBox = {}; f.ui.InputBegan:Fire({UserInputType = "Keyboard", KeyCode = "One"}, false); equal(f.equip.ServerCalls, 2)
	end)
	print(string.format("Tool equip tests passed: %d", passed))
end
