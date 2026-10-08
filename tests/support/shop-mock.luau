local Mock = {}
function Mock.signal()
	local listeners, signal = {}, {}
	function signal:Connect(fn)
		local c = {Connected = true}; function c:Disconnect() self.Connected = false end
		table.insert(listeners, {c = c, fn = fn}); return c
	end
	function signal:Fire(...)
		for _, entry in ipairs(table.clone(listeners)) do if entry.c.Connected then entry.fn(...) end end
	end
	function signal:Count()
		local n = 0; for _, entry in ipairs(listeners) do if entry.c.Connected then n += 1 end end; return n
	end
	function signal:Wait() coroutine.yield() end
	return signal
end
local methods, meta = {}, {}
function meta.__index(self, key)
	if methods[key] then return methods[key] end
	if self.props[key] ~= nil then return self.props[key] end
	return self.signals[key] or self:FindFirstChild(key)
end
local function ancestors(parent, event, child)
	while parent do parent.signals[event]:Fire(child); parent = parent.Parent end
end
function meta.__newindex(self, key, value)
	local old = self.props[key]; if old == value then return end
	if self.metrics then self.metrics.writes = (self.metrics.writes or 0) + 1 end
	if key == "Parent" then
		if old then ancestors(old, "DescendantRemoving", self); table.remove(old.children, table.find(old.children, self)) end
		self.props.Parent = value
		if old then old.ChildRemoved:Fire(self) end
		if value then table.insert(value.children, self); value.ChildAdded:Fire(self); ancestors(value, "DescendantAdded", self) end
	else self.props[key] = value; if key == "Value" then self.Changed:Fire(value) end end
	if self.signals["Property_" .. key] then self.signals["Property_" .. key]:Fire() end
end
local dimMeta = {}
Mock.UDim2 = {new = function(x, xo, y, yo) return setmetatable({X = {Scale=x or 0, Offset=xo or 0}, Y = {Scale=y or 0, Offset=yo or 0}}, dimMeta) end}
dimMeta.__add = function(a,b) return Mock.UDim2.new(a.X.Scale+b.X.Scale,a.X.Offset+b.X.Offset,a.Y.Scale+b.Y.Scale,a.Y.Offset+b.Y.Offset) end
dimMeta.__eq = function(a,b) return a.X.Scale==b.X.Scale and a.X.Offset==b.X.Offset and a.Y.Scale==b.Y.Scale and a.Y.Offset==b.Y.Offset end
Mock.UDim2.fromOffset = function(x, y) return Mock.UDim2.new(0, x, 0, y) end
Mock.UDim2.fromScale = function(x, y) return Mock.UDim2.new(x, 0, y, 0) end
Mock.Color3 = {fromRGB = function(r, g, b) return string.format("%d,%d,%d", r, g, b) end}
Mock.Enum = {
	Font = {GothamMedium = "GothamMedium"}, ScaleType = {Fit = "Fit"},
	AutomaticSize = {Y = "Y"}, SortOrder = {LayoutOrder = "LayoutOrder"},
	EasingStyle = {Quint = "Quint", Quad = "Quad"}, EasingDirection = {In = "In", Out = "Out"},
	PlaybackState = {Completed = "Completed", Cancelled = "Cancelled"},
	ProductPurchaseDecision = {PurchaseGranted = "Granted", NotProcessedYet = "Retry"},
}
function Mock.object(class, name, parent, value)
	local self = setmetatable({props = {ClassName = class, Name = name or class, Visible = false,
		Position = Mock.UDim2.new(), Scale = 1, Value = value or 0, Text = "", BackgroundTransparency = 0},
		children = {}, signals = {}, attributes = {}, metrics = Mock.metrics}, meta)
	for _, key in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Changed", "Destroying", "PlayerRemoving", "OnServerEvent", "OnClientEvent", "Activated", "MouseButton1Up", "MouseEnter", "MouseLeave", "Completed"}) do self.signals[key] = Mock.signal() end
	self.Parent = parent; return self
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance"
		or class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton")
		or class == "GuiObject" and table.find({"Frame", "ScrollingFrame", "ImageButton", "ImageLabel", "TextButton", "TextLabel", "CanvasGroup"}, self.ClassName) ~= nil
end
function methods:FindFirstChild(name, recursive)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
	if recursive then for _, child in ipairs(self.children) do local found = child:FindFirstChild(name, true); if found then return found end end end
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
	local result = {}; for _, child in ipairs(self.children) do table.insert(result, child); for _, item in ipairs(child:GetDescendants()) do table.insert(result, item) end end; return result
end
methods.WaitForChild = methods.FindFirstChild
function methods:GetPropertyChangedSignal(key)
	self.signals["Property_" .. key] = self.signals["Property_" .. key] or Mock.signal(); return self.signals["Property_" .. key]
end
function methods:GetAttributeChangedSignal(key)
	self.signals["Attribute_" .. key] = self.signals["Attribute_" .. key] or Mock.signal(); return self.signals["Attribute_" .. key]
end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:SetAttribute(key, value)
	self.attributes[key] = value; if self.signals["Attribute_" .. key] then self.signals["Attribute_" .. key]:Fire() end
end
function methods:Clone()
	if self:GetAttribute("FailClone") then error("Simulated template clone failure") end
	if self.metrics then self.metrics.clones = (self.metrics.clones or 0) + 1 end
	local clone = Mock.object(self.ClassName, self.Name)
	for key, value in pairs(self.props) do if key ~= "Parent" then clone.props[key] = value end end
	for key, value in pairs(self.attributes) do clone.attributes[key] = value end
	for _, child in ipairs(self.children) do child:Clone().Parent = clone end
	return clone
end
function methods:IsDescendantOf(ancestor)
	local parent = self.Parent; while parent do if parent == ancestor then return true end; parent = parent.Parent end; return false
end
function methods:Destroy()
	self.Destroying:Fire(); for _, child in ipairs(self:GetChildren()) do child:Destroy() end; self.Parent = nil; self.props.Destroyed = true
end
function methods:ClearAllChildren() for _, child in ipairs(self:GetChildren()) do child:Destroy() end end
function methods:FireClient(player, payload)
	self.props.ClientCalls = (self.ClientCalls or 0) + 1; self.props.LastPayload = payload
	if self.OnReply then self.OnReply(player, payload) end
end
function methods:FireServer(...)
	self.props.ServerCalls = (self.ServerCalls or 0) + 1; self.props.LastRequest = table.pack(...)
	if self.OnSend then self.OnSend(...) end
end
function Mock.fixture(load)
	local f = {now = 1800000000, elapsed = 10, modules = {}, saves = 0, prompts = 0, warnings = {}, deferred = {}, tweens = {}, jobs = {}, threads = {}, preloads = {}}
	Mock.metrics = f
	local object = Mock.object
	f.Players, f.RS, f.SS = object("Players"), object("Folder", "ReplicatedStorage"), object("Folder", "ServerStorage")
	function f.Players:GetPlayers() return self:GetChildren() end
	f.player = object("Player", "Tester", f.Players); f.player.UserId = 1; f.Players.LocalPlayer = f.player
	f.player:SetAttribute("DataReady", true)
	f.stats = object("Folder", "leaderstats", f.player)
	f.cash, f.xp = object("IntValue", "Cash", f.stats, 100000), object("IntValue", "XP", f.stats, 535100)
	for _, name in ipairs({"Inventory", "RevolverInventory"}) do object("Folder", name, f.stats) end
	for _, name in ipairs({"Knives", "Revolvers"}) do object("Folder", name, f.SS) end
	f.remotes = object("Folder", "Remotes", f.RS)
	f.shopRemotes = object("Folder", "ShopRemotes", f.remotes)
	f.remote = object("RemoteEvent", "PurchaseGoldRemote", object("Folder", "PurchaseGold", f.shopRemotes))
	object("RemoteEvent", "BuyGamePass", object("Folder", "Gamepass", f.shopRemotes))
	object("RemoteEvent", "VIPStatus", object("Folder", "VIP", f.shopRemotes))
	object("RemoteEvent", "BuyVIP", f.shopRemotes.VIP)
	f.modulesFolder = object("Folder", "Modules", f.RS)
	f.server = object("Folder", "Server")
	f.servicesFolder = object("Folder", "ServicesHandler", f.server)
	f.dataFolder = object("Folder", "DataStore", f.server)
	f.profile = {Data = {}, IsActive = function() return f.active ~= false end}
	local function register(parent, name, module) f.modules[object("ModuleScript", name, parent)] = module; return module end
	f.register = register
	f.profiles = register(f.dataFolder, "ProfileManager", {
		GetProfile = function() return f.profile end,
		SaveProfile = function() f.saves += 1; f.saved = f.profile.Data.DailyShop end,
	})
	f.inventory = register(f.dataFolder, "InventoryHandler", {})
	local function grant(player, name, kind)
		f.grants = (f.grants or 0) + 1
		local folder = player.leaderstats[kind]
		local item = folder:FindFirstChild(name) or object("StringValue", name, folder)
		local quantity = item:FindFirstChild("Quantity") or object("IntValue", "Quantity", item)
		quantity.Value += 1
		if f.failGrant then error("simulated partial grant") end
		return item
	end
	f.inventory.AddKnife = function(player, name) return grant(player, name, "Inventory") end
	f.inventory.AddRevolver = function(player, name) return grant(player, name, "RevolverInventory") end
	f.heartbeat = Mock.signal()
	f.marketplace = {PromptProductPurchase = function() f.prompts += 1 end, PromptGamePassPurchase = function() end}
	f.tweenService = {Create = function(_, target, _, goals)
		local tween = {Completed = Mock.signal(), Target = target, Goals = goals}
		function tween:Play() for key, value in pairs(goals) do target[key] = value end end
		function tween:Cancel() self.cancelled = true; self.Completed:Fire("Cancelled") end
		function tween:Destroy() self.destroyed = true end
		table.insert(f.tweens, tween); return tween
	end}
	f.services = {Players = f.Players, ReplicatedStorage = f.RS, ServerStorage = f.SS, RunService = {Heartbeat = f.heartbeat},
		Workspace = {GetServerTimeNow = function() return f.now end}, TweenService = f.tweenService,
		MarketplaceService = f.marketplace, DataStoreService = {GetDataStore = function() return {} end},
		Lighting = {Blur = {Enabled = false}},
		ContentProvider = {PreloadAsync = function(_, batch) table.insert(f.preloads, table.clone(batch)); if f.failPreload then error("unavailable") end end},
	}
	f.env = {game = {GetService = function(_, name) return assert(f.services[name], name) end}, Instance = {new = function(class) f.instanceCalls=(f.instanceCalls or 0)+1; return object(class) end},
		require = function(module) return assert(f.modules[module], "Missing module " .. tostring(module and module.Name)) end,
		os = {time = function() return f.now end, clock = function() return f.elapsed end},
		task = {wait = function() end, spawn = function(fn) table.insert(f.jobs,fn) end, defer = function(fn) table.insert(f.deferred, fn) end, delay = function(_, fn) table.insert(f.deferred, fn) end, cancel = function() end},
		Enum = Mock.Enum, UDim2 = Mock.UDim2, Color3 = Mock.Color3, UDim = {new = function() return {} end},
		Vector2 = {new = function(x, y) return {X = x, Y = y} end},
		TweenInfo = {new = function() return {} end}, typeof = typeof,
		warn = function(...) table.insert(f.warnings, table.pack(...)) end,
	}
	function f:load(name, parent, key)
		self.env.script = object("ModuleScript", key or name, parent)
		local result = load(name, self.env); self.modules[self.env.script] = result; return result
	end
	function f:step(seconds)
		self.now += seconds; self.elapsed += seconds
		local jobs=self.jobs; self.jobs={}; local threads=self.threads; self.threads={}
		for _, fn in ipairs(jobs) do table.insert(threads,coroutine.create(fn)) end
		for _, thread in ipairs(threads) do local ok,err=coroutine.resume(thread); assert(ok,err); if coroutine.status(thread)=="suspended" then table.insert(self.threads,thread) end end
		local deferred = self.deferred; self.deferred = {}; for _, fn in ipairs(deferred) do fn() end
		self.heartbeat:Fire(seconds)
	end
	function f:tickFrames(count) for _=1,count or 12 do self:step(1/60) end end
	return f
end
return Mock
