-- Production bridge with deterministic input/equipment adapters. Existing
-- revolver input is verified by passing RT through without a second fire.
return function(load)
	local function signal()
		local listeners = {}
		local self = {}
		function self:Connect(callback)
			local connection = {Connected = true}
			function connection:Disconnect() self.Connected = false end
			table.insert(listeners, {Callback = callback, Connection = connection})
			return connection
		end
		function self:Fire(...)
			for _, listener in ipairs(listeners) do if listener.Connection.Connected then listener.Callback(...) end end
		end
		function self:Count()
			local count = 0
			for _, listener in ipairs(listeners) do if listener.Connection.Connected then count += 1 end end
			return count
		end
		return self
	end
	local function fixture()
		local f = {Time = 100, Actions = {OrdinaryInput = "preserved"}, EquipRequests = {}, EatRequests = {}}
		local methods = {}
		local function object(class, name)
			return setmetatable({ClassName = class, Name = name, Children = {}, Attributes = {}, AttributeSignals = {},
				ChildAdded = signal(), ChildRemoved = signal(), CharacterAdded = signal(), CharacterRemoving = signal(), Died = signal()}, {__index = methods})
		end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self.Children) do if child.Name == name then return child end end
			return nil
		end
		function methods:FindFirstChildOfClass(class)
			for _, child in ipairs(self.Children) do if child:IsA(class) then return child end end
			return nil
		end
		function methods:GetChildren() return self.Children end
		function methods:IsA(class) return self.ClassName == class or class == "GuiObject" and self.ClassName == "Frame" end
		function methods:GetAttribute(name) return self.Attributes[name] end
		function methods:GetAttributeChangedSignal(name)
			self.AttributeSignals[name] = self.AttributeSignals[name] or signal()
			return self.AttributeSignals[name]
		end
		function methods:SetAttribute(name, value)
			local old = self.Attributes[name]; self.Attributes[name] = value
			if old ~= value and self.AttributeSignals[name] then self.AttributeSignals[name]:Fire() end
		end
		local function child(parent, class, name)
			local instance = object(class, name); instance.Parent = parent; table.insert(parent.Children, instance)
			return instance
		end
		f.Player = object("Player", "Player")
		f.Player:SetAttribute("TutorialActive", false); f.Player:SetAttribute("InRound", true); f.Player:SetAttribute("DataReady", true)
		f.Player:SetAttribute("FoodUses", 3)
		f.Character = object("Model", "Character"); f.Player.Character = f.Character
		f.Humanoid = child(f.Character, "Humanoid", "Humanoid"); f.Humanoid.Health, f.Humanoid.MaxHealth = 50, 100
		f.RS = object("ReplicatedStorage", "ReplicatedStorage")
		f.RS.Modules = {TutorialUIConfig = "UIConfig", FoodConfig = "FoodConfig"}
		child(child(f.RS, "Folder", "Knives"), "Tool", "Knife")
		child(child(f.RS, "Folder", "Revolvers"), "Tool", "Revolver")
		local remotes = child(f.RS, "Folder", "Remotes")
		local equip = child(child(remotes, "Folder", "HotBar"), "RemoteEvent", "Equip")
		function equip:FireServer(value) table.insert(f.EquipRequests, value) end
		local eat = child(child(remotes, "Folder", "Food"), "RemoteEvent", "Eat")
		function eat:FireServer(tool) table.insert(f.EatRequests, tool) end
		f.UI = {PreferredInput = "Gamepad", WindowFocusReleased = signal(), TextBoxFocused = signal(), PreferredChanged = signal(), GetFocusedTextBox = function() return nil end}
		function f.UI:GetPropertyChangedSignal() return self.PreferredChanged end
		f.Gui = {MenuIsOpen = false, MenuOpened = signal()}
		f.CAS = {
			BindActionAtPriority = function(_, name, callback, _, _, key) f.Actions[name] = {Callback = callback, Key = key} end,
			UnbindAction = function(_, name) f.Actions[name] = nil end,
		}
		f.Combat = {
			BeginCharge = function() f.Begins = (f.Begins or 0) + 1; return true end,
			ReleaseCharge = function() f.Releases = (f.Releases or 0) + 1 end,
			CancelCharge = function() f.Cancels = (f.Cancels or 0) + 1 end,
			Stab = function() f.Stabs = (f.Stabs or 0) + 1 end,
		}
		local client = object("LocalScript", "CLIENT")
		local modules = child(client, "Folder", "Modules")
		local combatModule = child(modules, "ModuleScript", "CombatController")
		f.KnifeInput = child(client, "ModuleScript", "HandleKnifeCombat"); f.KnifeInput:SetAttribute("StartupState", "Ready")
		local config = {Enabled = true, PriorityOffset = 3, RequestCooldownSeconds = 0.2,
			Keys = {Knife = "DPadLeft", Revolver = "DPadUp", Food = "DPadRight", Stab = "ButtonR1", ThrowEat = "ButtonR2"}}
		local environment = {
			game = {GetService = function(_, service)
				return ({Players = {LocalPlayer = f.Player}, ReplicatedStorage = f.RS, UserInputService = f.UI, ContextActionService = f.CAS, GuiService = f.Gui})[service]
			end}, script = {Parent = modules},
			require = function(name)
				if name == "UIConfig" then return {Gamepad = config} end
				if name == "FoodConfig" then return {ToolName = "Burger"} end
				assert(name == combatModule)
				f.ControllerLoads = (f.ControllerLoads or 0) + 1
				return f.Combat
			end,
			os = {clock = function() return f.Time end}, workspace = {GetServerTimeNow = function() return f.Time end},
			Enum = {PreferredInput = {Gamepad = "Gamepad"}, UserInputState = {Begin = "Begin", End = "End", Cancel = "Cancel"},
				ContextActionResult = {Pass = "Pass", Sink = "Sink"}, ContextActionPriority = {High = {Value = 100}},
				KeyCode = {DPadLeft = "DPadLeft", DPadUp = "DPadUp", DPadRight = "DPadRight", ButtonR1 = "ButtonR1", ButtonR2 = "ButtonR2"}},
		}
		f.Bridge = load("TutorialGamepadBridge", environment).new()
		function f:SetTool(kind)
			local old = self.Character:FindFirstChildOfClass("Tool")
			if old then old.Parent = nil; table.remove(self.Character.Children, table.find(self.Character.Children, old)); self.Character.ChildRemoved:Fire(old) end
			local tool = child(self.Character, "Tool", kind)
			if kind == "Burger" then tool:SetAttribute("FoodItem", "Burger") end
			self.Character.ChildAdded:Fire(tool)
			return tool
		end
		function f:Input(action, state) return self.Actions["TutorialGamepad" .. action].Callback("", state) end
		return f
	end
	local f = fixture()
	assert(f.Actions.TutorialGamepadThrowEat == nil, "Controller bridge leaked into ordinary gameplay")
	assert(f.ControllerLoads == nil, "Tutorial construction tried to load combat assets")
	f.Player:SetAttribute("TutorialActive", true)
	assert(f.Actions.TutorialGamepadKnife.Key == "DPadLeft" and f.Actions.TutorialGamepadThrowEat.Key == "ButtonR2")
	f:Input("Knife", "Begin"); assert(f.EquipRequests[1] == "Knife")
	f:Input("Revolver", "Begin"); assert(#f.EquipRequests == 1, "Equip input floods were not debounced")
	f.Time += 0.3; f:Input("Revolver", "Begin"); assert(f.EquipRequests[2] == "Revolver")
	f:SetTool("Knife")
	f.KnifeInput:SetAttribute("StartupState", "Loading")
	f:Input("Stab", "Begin"); assert(f.ControllerLoads == nil and f.Stabs == nil)
	f.KnifeInput:SetAttribute("StartupState", "Ready")
	f:Input("Stab", "Begin"); assert(f.Stabs == 1)
	assert(f.ControllerLoads == 1)
	assert(f:Input("ThrowEat", "Begin") == "Sink")
	f:Input("ThrowEat", "End"); f:Input("ThrowEat", "End")
	assert(f.Begins == 1 and f.Releases == 1, "Charge release repeated")
	f:Input("ThrowEat", "Begin"); f.Gui.MenuOpened:Fire(); f:Input("ThrowEat", "End")
	assert(f.Cancels == 1 and f.Releases == 1, "Menu cancellation threw a knife")
	f:SetTool("Revolver")
	assert(f:Input("ThrowEat", "Begin") == "Pass", "Bridge swallowed the existing revolver RT fire binding")
	assert(f.Begins == 2 and f.Releases == 1)
	local burger = f:SetTool("Burger")
	f:Input("ThrowEat", "Begin"); f:Input("ThrowEat", "Begin")
	assert(#f.EatRequests == 1 and f.EatRequests[1] == burger)
	f.Time += 1; f.Humanoid.Health = 100; f:Input("ThrowEat", "Begin"); assert(#f.EatRequests == 1)
	f.Humanoid.Health = 50; f.Player:SetAttribute("FoodReadyAt", f.Time + 3)
	f:Input("ThrowEat", "Begin"); assert(#f.EatRequests == 1)
	f:SetTool("Knife"); f:Input("ThrowEat", "Begin")
	f.UI.PreferredInput = "Keyboard"; f.UI.PreferredChanged:Fire()
	assert(f.Cancels == 2 and f.Actions.TutorialGamepadThrowEat == nil and f.Actions.OrdinaryInput == "preserved")
	f.UI.PreferredInput = "Gamepad"; f.UI.PreferredChanged:Fire()
	f.Player:SetAttribute("TutorialActive", false)
	assert(f.Actions.TutorialGamepadKnife == nil and f.Actions.OrdinaryInput == "preserved")
	f.Player:SetAttribute("TutorialActive", true)
	f.Humanoid.Health = 0; f.Humanoid.Died:Fire()
	assert(f.Actions.TutorialGamepadKnife == nil)
	f.Bridge.Destroy(); f.Bridge.Destroy()
	assert(f.Player:GetAttributeChangedSignal("TutorialActive"):Count() == 0 and f.Player.CharacterAdded:Count() == 0)
	assert(f.Humanoid.Died:Count() == 0 and f.UI.PreferredChanged:Count() == 0 and f.Actions.OrdinaryInput == "preserved")
	print("PASS tutorial gamepad scoped equip knife food passthrough and lifecycle")
end
