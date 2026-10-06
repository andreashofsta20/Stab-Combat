local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(fn)
		local c = {Connected = true}
		function c:Disconnect() self.Connected = false end
		table.insert(listeners, {fn = fn, c = c}); return c
	end
	function s:Fire(...) for _, item in ipairs(table.clone(listeners)) do if item.c.Connected then item.fn(...) end end end
	function s:Count() local n = 0; for _, item in ipairs(listeners) do if item.c.Connected then n += 1 end end; return n end
	return s
end
local metrics
local methods, meta = {}, {}
function meta.__index(self, key)
	if methods[key] then return methods[key] end
	if self.props[key] ~= nil then return self.props[key] end
	if self.signals[key] then return self.signals[key] end
	for _, item in ipairs(self.children) do if item.Name == key then return item end end
end
local function ancestrySignal(parent, name, item)
	while parent do parent.signals[name]:Fire(item); parent = parent.Parent end
end
function meta.__newindex(self, key, value)
	local old = self.props[key]
	if old == value then return end
	if key == "Enabled" and metrics then metrics.enabledWrites = (metrics.enabledWrites or 0) + 1 end
	if key == "Parent" then
		if old then
			ancestrySignal(old, "DescendantRemoving", self)
			for _, nested in ipairs(self:GetDescendants()) do ancestrySignal(old, "DescendantRemoving", nested) end
			local i = table.find(old.children, self); if i then table.remove(old.children, i) end
		end
		self.props.Parent = value
		if old then old.ChildRemoved:Fire(self) end
		if value then
			table.insert(value.children, self); value.ChildAdded:Fire(self)
			ancestrySignal(value, "DescendantAdded", self)
			for _, nested in ipairs(self:GetDescendants()) do ancestrySignal(value, "DescendantAdded", nested) end
		end
	else self.props[key] = value; if key == "Value" then self.Changed:Fire(value) end end
	if self.signals["Property_" .. key] then self.signals["Property_" .. key]:Fire() end
end
local function object(class, name, parent, value)
	local o = setmetatable({props = {ClassName = class, Name = name or class, Visible = false, Health = class=="Humanoid" and 100 or nil, MaxHealth = class=="Humanoid" and 100 or nil}, children = {}, signals = {}, attributes = {}}, meta)
	for _, key in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Changed", "Destroying", "MouseButton1Click", "MouseButton1Up", "MouseEnter", "MouseLeave", "Activated", "InputBegan", "InputEnded", "PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "HealthChanged", "Died", "Running", "OnClientEvent", "Completed"}) do o.signals[key] = signal() end
	o.signals.AncestryChanged = signal()
	if value ~= nil then o.Value = value
	elseif class == "StringValue" then o.Value = ""
	elseif class == "IntValue" then o.Value = 0
	elseif class == "BoolValue" then o.Value = false end
	o.Parent = parent; return o
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance"
		or class == "ValueBase" and self.ClassName:match("Value$") ~= nil
		or class == "GuiButton" and (self.ClassName == "ImageButton" or self.ClassName == "TextButton")
		or class == "GuiObject" and table.find({"Frame", "ScrollingFrame", "CanvasGroup", "ImageButton", "ImageLabel", "TextButton", "TextLabel"}, self.ClassName) ~= nil
end
function methods:GetChildren() metrics.scans += 1; return table.clone(self.children) end
function methods:GetDescendants() local all = {}; for _, item in ipairs(self.children) do table.insert(all, item); for _, nested in ipairs(item:GetDescendants()) do table.insert(all, nested) end end; return all end
function methods:FindFirstChild(name, recursive)
	for _, item in ipairs(self.children) do if item.Name == name then return item end end
	if recursive then for _, item in ipairs(self.children) do local found = item:FindFirstChild(name, true); if found then return found end end end
end
function methods:FindFirstChildOfClass(class) for _, item in ipairs(self.children) do if item:IsA(class) then return item end end end
function methods:WaitForChild(name)
	if metrics.waitHook then metrics.waitHook(self,name) end
	return assert(self:FindFirstChild(name), "Missing fixture: " .. self.Name .. "." .. name)
end
function methods:GetPropertyChangedSignal(name) self.signals["Property_" .. name] = self.signals["Property_" .. name] or signal(); return self.signals["Property_" .. name] end
function methods:SetAttribute(name, value) self.attributes[name] = value end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:GetAttributeChangedSignal(name) self.signals["Attribute_"..name]=self.signals["Attribute_"..name] or signal(); return self.signals["Attribute_"..name] end
function methods:Destroy() if self.Destroyed then return end; self.Destroying:Fire(); for _, item in ipairs(self:GetChildren()) do item:Destroy() end; self.Parent = nil; self.Destroyed = true end
function methods:Clone()
	metrics.clones += 1
	local o = object(self.ClassName, self.Name)
	for key, value in pairs(self.props) do if key ~= "Parent" then o[key] = value end end
	for _, item in ipairs(self.children) do item:Clone().Parent = o end
	return o
end
function methods:FireServer(...) self.ServerCalls = (self.ServerCalls or 0) + 1; self.LastArgs = {...} end
function methods:GetFocusedTextBox() return self.Focused end
function methods:LoadAnimation()
	local track = {IsPlaying = false, playCount = 0}
	function track:Play() self.IsPlaying = true; self.playCount += 1 end
	function track:Stop() self.IsPlaying = false end
	function track:AdjustSpeed(speed) self.Speed = speed end
	function track:Destroy() self.Destroyed = true end
	table.insert(metrics.tracks, track); return track
end
local function scheduler()
	local s = {now = 0, queue = {}}
	local function resume(entry)
		if entry.cancelled or entry.dead then return end
		local ok, seconds = coroutine.resume(entry.co)
		assert(ok, seconds)
		if coroutine.status(entry.co) == "dead" then entry.dead = true else entry.at = s.now + (seconds or 0); table.insert(s.queue, entry) end
	end
	local function make(fn, ...)
		local args = {...}; return {co = coroutine.create(function() fn(table.unpack(args)) end), fn = fn}
	end
	s.task = {}
	function s.task.spawn(fn, ...) local e = make(fn, ...); resume(e); return e end
	function s.task.delay(seconds, fn, ...) local e = make(fn, ...); e.at = s.now + seconds; table.insert(s.queue, e); return e end
	function s.task.defer(fn, ...) return s.task.delay(0, fn, ...) end
	function s.task.wait(seconds) return coroutine.yield(seconds or 0) end
	function s.task.cancel(e) e.cancelled = true end
	function s:step(seconds)
		local target = self.now + seconds
		for _ = 1, 1000 do
			table.sort(self.queue, function(a, b) return a.at < b.at end)
			if not self.queue[1] or self.queue[1].at > target then self.now = target; return end
			local e = table.remove(self.queue, 1); self.now = e.at; resume(e)
		end
		error("Fixture scheduler failed to settle")
	end
	return s
end
local function base()
	metrics = {clones = 0, scans = 0, tracks = {}}
	local f = {metrics = metrics, clock = scheduler()}
	f.rs, f.players, f.lighting, f.uis = object("Folder", "RS"), object("Players", "Players"), object("Lighting", "Lighting"), object("UIS", "UIS")
	f.blur = object("BlurEffect", "Blur", f.lighting); f.blur.Enabled = false
	f.player = object("Player", "Owner", f.players); f.player.UserId = 1; f.players.LocalPlayer = f.player
	f.playerGui = object("PlayerGui", "PlayerGui", f.player)
	f.main = object("ScreenGui", "Main", f.playerGui)
	f.frames = object("Folder", "Frames", f.main)
	f.modules = object("Folder", "Modules", f.rs)
	for _, name in ipairs({"GetThumbnail", "CalculateLevel", "Abbreviate", "RarityColor", "RevolversInfo"}) do object("ModuleScript", name, f.modules) end
	f.remotes = object("Folder", "Remotes", f.rs); f.templates = object("Folder", "UITemplates", f.rs)
	f.stats = object("Folder", "leaderstats", f.player)
	f.xp = object("IntValue", "XP", f.stats, 10)
	function f.players:GetPlayers() local players = {}; for _, p in ipairs(self.children) do if p:IsA("Player") then table.insert(players, p) end end; return players end
	function f.players:GetPlayerByUserId(id) for _, p in ipairs(self:GetPlayers()) do if p.UserId == id then return p end end end
	local tween = {}
	function tween:Create(target, _, goals)
		local t = {Completed = signal()}
		function t:Play() for key, value in pairs(goals) do target[key] = value end end
		function t:Cancel() self.Cancelled = true end
		function t:Destroy() self.Destroyed = true end
		return t
	end
	local services = {Players = f.players, ReplicatedStorage = f.rs, Lighting = f.lighting, UserInputService = f.uis, TweenService = tween}
	f.services = services
	f.env = {game = {GetService = function(_, key) return services[key] end}, task = f.clock.task, os = {clock = function() return f.clock.now end},
		Enum = {UserInputType = {Keyboard = "Keyboard"}, KeyCode = {Tab = "Tab"}, EasingStyle = {Quad = "Quad"}, EasingDirection = {Out = "Out"}},
		Color3 = {fromRGB = function(...) return {...} end}, TweenInfo = {new = function(...) return {...} end},
		UDim2 = {new = function(...) return {...} end}}
	f.env.game.Players, f.env.game.ReplicatedStorage = f.players, f.rs
	f.env.Instance = {new = function(class, parent) return object(class, class, parent) end}
	f.env.require = function(module)
		if module.Name == "GetThumbnail" then return {GetThumbnail = function(id) if f.thumbnailDelay then f.clock.task.wait(f.thumbnailDelay) end; return "head-" .. id end}
		elseif module.Name == "CalculateLevel" then return {GetLevel = function(xp) return math.floor(xp / 10) end}
		elseif module.Name == "Abbreviate" then return {WithCommas = tostring}
		elseif module.Name == "RarityColor" then return {Common = {Image = "common", Priority = 1}}
		elseif module.Name == "RevolversInfo" then return {} end
		error("Unexpected require: " .. module.Name)
	end
	return f
end
local function resultsFixture(load)
	local f = base()
	local remotes = object("Folder", "RoundResults", f.remotes); f.remote = object("RemoteEvent", "GetRoundResults", remotes)
	f.results = object("Frame", "RoundResults", f.frames); f.close = object("TextButton", "Close", f.results)
	local container = object("Frame", "Container", f.results)
	object("Folder", "Holder", object("Frame", "OtherPlayers", container))
	local winner = object("Frame", "WinnerFrame", container)
	f.image = object("ImageLabel", "ProfileImage", object("Frame", "ProfileFrame", winner))
	f.username = object("TextLabel", "Username", winner); object("ImageLabel", "MapImage", winner)
	object("Folder", "RoundResults", f.templates)
	f.menu = object("Frame", "Settings", f.frames)
	f.emote = object("Frame", "background", object("Frame", "EmoteFrame", f.main))
	load("Results", f.env)
	function f:show(id) self.remote.OnClientEvent:Fire({Winners = {{UserId = id or 1}}, Mode = "FFA"}, {}) end
	return f
end
local function playerListFixture(load)
	local f = base()
	f.profile = object("RemoteEvent", "RequestViewProfile", object("Folder", "ProfileHandler", f.remotes))
	f.container = object("Frame", "Container", object("Frame", "PlayerList", f.main)); f.rows = object("Folder", "Players", f.container)
	local row = object("ImageButton", "Player", object("Folder", "PlayerListTemplates", f.templates))
	for _, name in ipairs({"PlayerImage", "Level", "PlayerName", "Gradient"}) do object(name == "Gradient" and "Frame" or "TextLabel", name, row) end
	load("PlayerList", f.env); return f
end
local function inventoryFixture(load)
	local f = base()
	f.inventory, f.revolvers, f.emotes = object("Folder", "Inventory", f.stats), object("Folder", "RevolverInventory", f.stats), object("Folder", "Emotes", f.stats)
	f.equippedKnife = object("StringValue", "EquippedKnife", f.stats, "A"); object("StringValue", "EquippedGun", f.stats, "Gun")
	local remotes = object("Folder", "Inventory", f.remotes); object("RemoteEvent", "EquipKnife", remotes); object("RemoteEvent", "EquipRevolver", remotes)
	f.frame = object("Frame", "Inventory", f.frames); object("Frame", "Menu", f.frame); object("TextButton", "Close", f.frame); object("TextButton", "Back", f.frame)
	local holders = object("Folder", "Holders", f.frame)
	f.emotesPage = object("Frame", "Emotes", holders); f.emotesPage.Visible = true
	f.emoteRows = object("ScrollingFrame", "Scroll", f.emotesPage); f.emoteRows.Visible = true
	f.knifeRows = object("ScrollingFrame", "Scroll", object("Frame", "Knives", holders))
	f.gunRows = object("ScrollingFrame", "Scroll", object("Frame", "GunSkins", holders))
	local templates = object("Folder", "InventoryTemplates", f.templates)
	local knife = object("ImageButton", "KnifeInventoryTemplate", templates)
	for _, name in ipairs({"KnifeName", "KnifeSkin", "KnifeImage", "Quantity", "KnifeSelected", "Tradable", "Rarity"}) do object("ImageLabel", name, knife) end
	local gun = object("ImageButton", "RevolverInventoryTemplate", templates)
	for _, name in ipairs({"RevolverName", "KnifeSkin", "RevolverImage", "Quantity", "RevolverSelected", "Tradable", "Rarity"}) do object("ImageLabel", name, gun) end
	local emote = object("ImageButton", "EmoteInventoryTemplate", templates)
	for _, name in ipairs({"EmoteName", "EmoteRarity", "Quantity"}) do object("TextLabel", name, emote) end
	local rig = object("Model", "Rig", object("WorldModel", "World", object("ViewportFrame", "EmoteViewport", object("ImageLabel", "Rarity", emote))))
	object("Animator", "Animator", object("Humanoid", "Humanoid", rig))
	f.knifeA = object("StringValue", "A", f.inventory, "asset"); f.quantity = object("IntValue", "Quantity", f.knifeA, 1)
	object("StringValue", "B", f.inventory, "asset"); object("StringValue", "Gun", f.revolvers, "asset"); object("StringValue", "Dance", f.emotes, "asset")
	load("Inventory", f.env); return f
end
local function healthFixture(load)
	local f = base()
	f.character = object("Model", "Character"); f.player.Character = f.character
	f.hum = object("Humanoid", "Humanoid", f.character)
	f.script = object("LocalScript", "HealthBar", f.character); f.env.script = f.script
	f.bar = object("Frame", "HealthBar", object("Frame", "Container", object("Frame", "Health", object("Frame", "BarContainer", object("Frame", "TopUI", f.main)))))
	f.flash = object("Frame", "HitFrame", f.main)
	load("Health", f.env)
	function f:hit(value) self.hum.Health = value; self.hum.HealthChanged:Fire(value) end
	return f
end
local function tradeFixture(load)
	local f = base()
	f.remote = object("RemoteEvent", "TradeUpdate", object("Folder", "Trading", f.remotes))
	local requests = object("Folder", "TradeRequestTemplates", f.templates); object("Frame", "TradeRequest", requests)
	local template = object("ImageButton", "KnifeInventoryTemplate", object("Folder", "InventoryTemplates", f.templates))
	object("TextLabel", "KnifeName", template)
	object("Frame", "TradeRequests", f.main)
	f.frame = object("Frame", "Trade", f.frames)
	f.mine = object("Folder", "YourOffer", f.frame); f.theirs = object("Folder", "TheirOffer", f.frame)
	local sidebar = object("Frame", "SideBar", f.frame); f.inventoryRows = object("Folder", "Scroll", sidebar)
	local buttons = object("Frame", "Buttons", sidebar)
	f.accept = object("TextButton", "Accept", buttons); object("TextButton", "Cancel", buttons)
	local inventory = object("Folder", "Inventory", f.stats)
	object("BoolValue", "Tradeable", object("StringValue", "A", inventory, "asset"), true)
	load("Trading", f.env)
	function f:show(kind, state)
		local data = {UpdateType = kind or "TRADE_STARTED", State = state or "LOCKED", Player1 = {UserId = 1, Name = "Owner", Locked = true, Items = {{Name = "B", Quantity = 1}}}, Player2 = {UserId = 2, Name = "Other", Locked = true, Items = {{Name = "C", Quantity = 1}}}}
		self.remote.OnClientEvent:Fire("TRADE_EVENT", data)
	end
	return f
end

local function tradeListFixture(load)
	local f = base(); f.xp.Value = 100
	object("RemoteEvent", "TradeUpdate", object("Folder", "Trading", f.remotes))
	f.frame = object("Frame", "TradeRequesting", f.frames)
	f.rows = object("Folder", "Container", f.frame); object("TextButton", "Exit", f.frame)
	local templates = object("Folder", "TradeRequestTemplates", f.templates)
	object("Frame", "LevelRequirement", templates); object("Frame", "NoPlayers", templates)
	local row = object("Frame", "PlayerTemplate", templates)
	for _, name in ipairs({"PlayerImage", "Username", "SentOrNot"}) do object("TextLabel", name, row) end
	object("TextLabel", "Header", object("TextButton", "SendTrade", row))
	f.other = object("Player", "Other", f.players); f.other.UserId = 2
	local stats = object("Folder", "leaderstats", f.other)
	f.otherXP = object("IntValue", "XP", stats, 120)
	f.trades = object("BoolValue", "Trades", object("Folder", "Settings", stats), true)
	load("TradeList", f.env); return f
end

local function emoteFixture(load)
	local f = base()
	f.emotes = object("Folder", "Emotes", f.stats)
	object("StringValue", "Dance", f.emotes, "dance")
	object("StringValue", "Wave", f.emotes, "wave")
	object("StringValue", "Emote", object("Folder", "KeyBinds", f.stats), "G")
	local replicated = object("Folder", "Emotes", f.rs); f.sharedAnimation = object("Animation", "Dance", replicated)
	object("ModuleScript", "Emotes", f.modules); object("ModuleScript", "KeybindValidation", f.modules)
	f.frame = object("Frame", "background", object("Frame", "EmoteFrame", f.main))
	f.rows = object("Folder", "container", f.frame)
	for _, name in ipairs({"Dance", "Wave"}) do
		local row = object("ImageButton", name, f.rows)
		local rig = object("Model", "Rig", object("WorldModel", "World", object("ViewportFrame", "EmoteViewport", row)))
		object("Humanoid", "Humanoid", rig)
	end
	function f:character(name)
		local character = object("Model", name)
		local hum = object("Humanoid", "Humanoid", character); hum.MoveDirection = {Magnitude = 0}
		object("Animator", "Animator", hum)
		self.player.Character = character; return character, hum
	end
	f.char, f.hum = f:character("FirstCharacter")
	local originalRequire = f.env.require
	f.env.require = function(module)
		if module.Name == "Emotes" then return {Dance = {Rarity = "Common"}, Wave = {Rarity = "Common"}} end
		if module.Name == "KeybindValidation" then return {ToEnum = function() return "G" end} end
		return originalRequire(module)
	end
	f.created = {}
	f.env.Instance.new = function(class) local item = object(class); table.insert(f.created,item); return item end
	f.env.Enum.AnimationPriority = {Action3 = "Action3"}
	f.clock.task.spawn(function() load("Emote", f.env) end)
	f.uis.InputBegan:Fire({UserInputType = f.env.Enum.UserInputType.Keyboard})
	f.clock:step(0)
	function f:play(name) self.rows[name or "Dance"].MouseButton1Up:Fire(); return self.metrics.tracks[#self.metrics.tracks] end
	return f
end
local function overheadFixture(load)
	local f=base()
	f.workspace=object("Workspace", "Workspace")
	f.camera=object("Camera", "Camera", f.workspace); f.workspace.CurrentCamera=f.camera
	f.camera.CameraType="Custom"; f.player.CameraMode="Classic"
	local vectorMeta={}
	vectorMeta.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},vectorMeta) end
	vectorMeta.__index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
	f.env.Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end}
	f.env.Vector3.zero=f.env.Vector3.new(0,0,0)
	f.env.workspace=f.workspace
	f.env.Enum.CameraType={Custom="Custom",Scriptable="Scriptable"}
	f.env.Enum.CameraMode={Classic="Classic",LockFirstPerson="LockFirstPerson"}
	f.env.Enum.RenderPriority={Camera={Value=200}}
	f.run={bindings={},bindCalls=0}
	function f.run:BindToRenderStep(name,_,fn) self.bindings[name]=fn; self.bindCalls+=1 end
	function f.run:UnbindFromRenderStep(name) self.bindings[name]=nil end
	f.services.RunService=f.run
	function f:render(distance)
		self.camera.CFrame={Position=self.env.Vector3.new(0,0,distance or 10)}
		self.camera.Focus={Position=self.env.Vector3.zero}
		for _,fn in pairs(self.run.bindings) do fn() end
	end
	f:render(10)
	object("ModuleScript","WinStreakImages",f.modules)
	local resolve=f.env.require
	f.env.require=function(module) if module.Name=="WinStreakImages" then return {[0]="fire",[5]="fire5",[10]="fire10"} end; return resolve(module) end
	local template=object("BillboardGui","Overhead",object("Folder","OverheadTemplates",f.templates))
	local container=object("Frame","Container",template)
	object("TextLabel","PlayerName",container); object("ImageLabel","PlayerMembership",container)
	local streak=object("Frame","Streak",container); object("ImageLabel","FireEmoji",streak); object("TextLabel","StreakValue",streak)
	object("Frame","HealthBar",object("Frame","Container",object("Frame","Health",container)))
	object("BoolValue","LobbyMode",object("Folder","Settings",f.stats),false); object("IntValue","WinStreak",f.stats,0)
	function f:character()
		if self.player.Character then self.player.CharacterRemoving:Fire(self.player.Character) end
		local char=object("Model","Character"); local hum=object("Humanoid","Humanoid",char); object("Part","Head",char)
		self.camera.CameraSubject=hum
		self.player.Character=char; self.player.CharacterAdded:Fire(char); return char,hum
	end
	f:character(); load("Overhead",f.env)
	return f
end

local function lightingFixture(load)
	local f=base()
	f.env.Color3.new=function(r,g,b) return {R=r,G=g,B=b} end
	f.lighting.Ambient=f.env.Color3.new(0.04,0.06,0.08)
	f.lighting.OutdoorAmbient=f.env.Color3.new(0.08,0.10,0.12)
	f.lighting.ExposureCompensation=-0.15
	f.baseline={Ambient=f.lighting.Ambient,OutdoorAmbient=f.lighting.OutdoorAmbient,ExposureCompensation=-0.15}
	f.day=object("BoolValue","Day",f.stats,false)
	f.active=object("BoolValue","GameActive",f.rs,false)
	f.workspace=object("Workspace","Workspace"); f.env.workspace=f.workspace
	f.camera=object("Camera","Camera",f.workspace); f.workspace.CurrentCamera=f.camera
	f.character=object("Model","Character"); f.hum=object("Humanoid","Humanoid",f.character)
	f.player.Character=f.character; f.camera.CameraSubject=f.hum; f.camera.CameraType="Custom"
	f.env.Enum.CameraType={Custom="Custom",Scriptable="Scriptable"}
	f.env.Enum.EasingDirection.InOut="InOut"
	f.tweens={}
	local tweenService={}
	function tweenService:Create(target,_,goals)
		local tween={Completed=signal()}
		function tween:Play() for key,value in pairs(goals) do target[key]=value end end
		function tween:Cancel() self.Cancelled=true end
		function tween:Destroy() self.Destroyed=true end
		table.insert(f.tweens,tween); return tween
	end
	f.services.TweenService=tweenService
	f.controller=load("LobbyLighting",f.env).New(f.player,f.day)
	return f
end

return function(load)
	local total = 0
	local function check(value, message) total += 1; assert(value, message) end
	local f = resultsFixture(load)
	f:show(); check(f.results.Visible, "Results open immediately")
	f.clock:step(4.99); check(f.results.Visible, "Results stay visible before five seconds")
	f.clock:step(0.01); check(not f.results.Visible, "Results close at five seconds")
	f = resultsFixture(load); f:show(); f.clock:step(3); f:show(); f.clock:step(2)
	check(f.results.Visible, "Earlier results timer cannot close replacement results")
	f.clock:step(3); check(not f.results.Visible, "Replacement results get their full five seconds")
	f = resultsFixture(load); f:show(); f.clock:step(1); f.close.MouseButton1Click:Fire(); check(not f.results.Visible, "Manual close is immediate")
	f:show(); f.clock:step(4); check(f.results.Visible, "Manual close timer cannot hide a later result")
	f = resultsFixture(load); f:show(); f.clock:step(1); f.results.Visible = false; f.menu.Visible = true; f.blur.Enabled = true; f.clock:step(4)
	check(f.menu.Visible and f.blur.Enabled, "External menu switch cancels result timer and keeps menu blur")
	f:show(); f.clock:step(5); check(f.menu.Visible and f.blur.Enabled, "Result timeout preserves another visible menu")
	f.menu.Visible = false; f.emote.Visible = true; f:show(); f.clock:step(5); check(f.blur.Enabled, "Result timeout preserves emote modal blur")
	f.emote.Visible = false; f:show(); f.clock:step(5); check(not f.blur.Enabled, "Last results modal releases blur")
	f = resultsFixture(load); f.thumbnailDelay = 10; f:show(); f.clock:step(5); check(not f.results.Visible, "Slow thumbnail cannot delay close")
	f.clock:step(5); check(f.image.Image == "", "Late thumbnail cannot redraw hidden results")
	f = resultsFixture(load); f.thumbnailDelay = 2; f:show(); f.clock:step(1); f.remote.OnClientEvent:Fire({Winners = {{Name = "New winner"}}}, {}); f.clock:step(1)
	check(f.image.Image == "" and f.username.Text == "New winner", "Old thumbnail cannot overwrite new winner")
	f.results:Destroy(); check(f.remote.OnClientEvent:Count() == 0, "Destroying result UI removes remote subscription")
	f.clock:step(10); check(f.results.Destroyed, "Destroyed result UI has no late work")
	f = playerListFixture(load); local row = f.rows:FindFirstChild("Owner")
	check(row and row.Level.Text == "1", "Player list shows current level")
	check(f.xp:GetPropertyChangedSignal("Value"):Count() == 1, "One XP subscription per row")
	local clones = f.metrics.clones; f.clock:step(300); check(f.metrics.clones == clones and f.rows.Owner == row, "Player list never periodically rebuilds rows")
	f.xp.Value = 40; check(row.Level.Text == "4" and row.LayoutOrder == -4, "XP update changes existing row")
	f.players.PlayerAdded:Fire(f.player); check(f.xp:GetPropertyChangedSignal("Value"):Count() == 1, "Duplicate player event does not duplicate subscriptions")
	local p = object("Player", "New", f.players); p.UserId = 2; f.players.PlayerAdded:Fire(p)
	local stats = object("Folder", "leaderstats", p); local xp = object("IntValue", "XP", stats, 50)
	check(f.rows.New.Level.Text == "5", "Late leaderstats replication updates row")
	f.players.PlayerRemoving:Fire(p); check(not f.rows:FindFirstChild("New") and xp:GetPropertyChangedSignal("Value"):Count() == 0, "Departing row disconnects XP listener")
	f.container:Destroy(); check(f.xp:GetPropertyChangedSignal("Value"):Count() == 0 and f.uis.InputBegan:Count() == 0, "Player list UI teardown removes listeners")
	f = inventoryFixture(load); clones = f.metrics.clones; f.clock:step(30)
	check(f.metrics.clones == clones and #f.metrics.tracks == 0, "Hidden inventory builds no rows or animated rigs")
	f.frame.Visible = true; f.clock:step(0)
	check(f.knifeRows.A and f.knifeRows.B and f.gunRows.Gun and f.emoteRows.Dance, "Opening inventory builds current rows")
	check(f.knifeRows.A.KnifeSelected.Visible and not f.knifeRows.B.KnifeSelected.Visible, "Only equipped knife is selected")
	check(f.metrics.tracks[1].IsPlaying, "Visible emote page animates viewport")
	clones = f.metrics.clones; local rowA = f.knifeRows.A; f.quantity.Value = 2; f.quantity.Value = 3; f.clock:step(0)
	check(rowA.Quantity.Text == "x3" and f.metrics.clones == clones, "Inventory burst updates existing row without cloning")
	f.equippedKnife.Value = "B"; f.clock:step(0); check(not rowA.KnifeSelected.Visible and f.knifeRows.B.KnifeSelected.Visible, "Server equip update clears old selection")
	f.emotesPage.Visible = false; check(not f.metrics.tracks[1].IsPlaying, "Leaving emote page stops hidden animation")
	f.emotesPage.Visible = true; f.frame.Visible = false; check(not f.metrics.tracks[1].IsPlaying, "Closing inventory stops all viewport animation")
	clones = f.metrics.clones; f.quantity.Value = 9; f.clock:step(30); check(rowA.Quantity.Text == "x3" and f.metrics.clones == clones, "Hidden inventory change defers UI work")
	f.frame.Visible = true; f.clock:step(0); check(rowA.Quantity.Text == "x9", "Reopening catches hidden inventory changes")
	local track = f.metrics.tracks[1]; f.emotes.Dance:Destroy(); f.clock:step(0)
	check(track.Destroyed and not f.emoteRows:FindFirstChild("Dance"), "Removed emote destroys its track and row")
	f.frame:Destroy(); check(f.quantity.Changed:Count() == 0 and f.inventory.DescendantAdded:Count() == 0, "Inventory teardown disconnects source listeners")
	f = healthFixture(load); check(f.bar.Size[1] == 1, "Character health appears immediately without six-second delay")
	check(f.player.CharacterAdded:Count() == 0, "Character-scoped health controller does not subscribe to later spawns")
	f:hit(70); check(f.flash.Visible and f.bar.Size[1] == 0.7, "Hit flash and health update immediately")
	f.clock:step(0.2); f:hit(60); f.clock:step(0.06); check(f.flash.Visible, "Second hit extends flash instead of old timer hiding it")
	f.clock:step(0.19); check(not f.flash.Visible, "Hit flash ends after last hit")
	f:hit(50); f.player.CharacterRemoving:Fire(f.character); check(f.hum.HealthChanged:Count() == 0, "Character removal disconnects health events")
	f.flash.Visible = true; f.player.Character = object("Model", "NewCharacter"); f.clock:step(1)
	check(f.flash.Visible, "Old character timer cannot hide new character flash")
	f = tradeFixture(load); f:show(); local offerRow, inventoryRow = f.mine.B, f.inventoryRows.A; clones = f.metrics.clones
	f.clock:step(4); check(f.metrics.clones == clones and f.mine.B == offerRow and f.inventoryRows.A == inventoryRow, "Trade countdown keeps item buttons and callbacks")
	check(f.accept.Text == "UNCONFIRM (1S)", "Trade countdown still updates accept status")
	f.clock:step(1); check(f.accept.Text == "ACCEPT", "Accept becomes available at deadline")
	f:show("TRADE_COMPLETED", "COMPLETED"); f.clock:step(0.5); f:show("TRADE_STARTED", "OPEN"); f.clock:step(0.75)
	check(f.frame.Visible and not f.remote.ServerCalls, "Old completed-trade timer cannot close or cancel a new trade")
	f = tradeListFixture(load)
	check(f.otherXP:GetPropertyChangedSignal("Value"):Count() == 1 and f.trades:GetPropertyChangedSignal("Value"):Count() == 1,
		"Trade list subscribes once to each player's XP and trades preference")
	local staleRow = f.rows:FindFirstChild("2"); f.other.Parent = nil; f.clock:step(30)
	check(staleRow.Destroyed and f.otherXP:GetPropertyChangedSignal("Value"):Count() == 0 and f.trades:GetPropertyChangedSignal("Value"):Count() == 0,
		"Trade refresh fallback releases every stale row subscription")
	f = tradeListFixture(load); local otherRow = f.rows:FindFirstChild("2")
	f.players.PlayerRemoving:Fire(f.other)
	check(otherRow.Destroyed and f.otherXP:GetPropertyChangedSignal("Value"):Count() == 0 and f.trades:GetPropertyChangedSignal("Value"):Count() == 0,
		"Normal trade row removal uses the same complete cleanup")
	f = tradeListFixture(load); f.xp.Value = 0
	check(not f.rows:FindFirstChild("2") and f.otherXP:GetPropertyChangedSignal("Value"):Count() == 0 and f.trades:GetPropertyChangedSignal("Value"):Count() == 0,
		"Losing the trade level requirement disconnects all player row watchers")
	f = emoteFixture(load); local firstTrack = f:play("Dance"); f.clock:step(0.4)
	local replacement = f:play("Wave")
	check(firstTrack.Destroyed and not firstTrack.IsPlaying, "Replacing an avatar emote destroys its loaded track")
	f.clock:step(0.4); check(f.hum.Running:Count() == 0, "Old emote delay cannot attach a running listener to its replacement")
	f.clock:step(0.4); check(f.hum.Running:Count() == 1, "The current stationary emote owns one running listener")
	local currentTrack = f:play("Dance")
	check(replacement.Destroyed and f.hum.Running:Count() == 0, "Switching a stationary emote immediately releases its previous running listener")
	f.clock:step(0.8); f.hum.Running:Fire(16)
	check(currentTrack.Destroyed and f.hum.Running:Count() == 0, "Movement ends the current emote and releases track and listener")
	f = emoteFixture(load); local pending = f:play(); f.clock:step(0.2)
	f.player.CharacterRemoving:Fire(f.char)
	check(pending.Destroyed and f.hum.Died:Count() == 0, "Character removal cancels avatar emote state and death ownership")
	local _, nextHum = f:character("SecondCharacter"); f.player.CharacterAdded:Fire(f.player.Character); f.clock:step(1)
	check(nextHum.Running:Count() == 0 and f.hum.Running:Count() == 0, "Old delayed emotes cannot subscribe to a new avatar")
	local dyingTrack = f:play(); f.clock:step(0.8); nextHum.Died:Fire()
	check(dyingTrack.Destroyed and nextHum.Running:Count() == 0, "Death releases the current emote track and running listener")
	f = emoteFixture(load); local sharedPreview, ownedPreview = f.metrics.tracks[1], f.metrics.tracks[2]
	local ownedAnimation = f.created[1]; f.emotes.Wave.Value = "new-wave"
	check(ownedPreview.Destroyed and ownedAnimation.Destroyed, "Replacing an emote preview destroys its track and locally created animation")
	f.emotes.Dance:Destroy()
	check(sharedPreview.Destroyed and not f.sharedAnimation.Destroyed, "Removing a preview destroys its track and preserves shared replicated assets")
	f=overheadFixture(load)
	local overhead=f.player.Character.Head.OverheadUI_Owner
	check(overhead.Enabled,"Own overhead remains visible in third person")
	check(overhead.LightInfluence==0 and overhead.Brightness==2 and not overhead.AlwaysOnTop,"Overheads ignore environment light while retaining wall occlusion")
	check(overhead.StudsOffset.Y==0 and overhead.StudsOffsetWorldSpace.Y>0 and overhead.StudsOffsetWorldSpace.Y<=1.4,"Overhead sits closer to the head and stays vertical at every camera angle")
	check(overhead.Container.BackgroundTransparency==1 and overhead.Container.PlayerName.TextStrokeTransparency==0.12,"Overhead background is fully transparent while text retains its dark outline")
	f:render(0.5); check(not overhead.Enabled,"Fully zoomed-in view hides the local overhead")
	f:render(0.95); check(not overhead.Enabled,"Zoom hysteresis prevents own overhead flicker")
	f:render(1.2); check(overhead.Enabled,"Zooming out restores the local overhead")
	f.player.CameraMode="LockFirstPerson"; f:render(10); check(not overhead.Enabled,"Explicit first person also hides overhead before zoom settles")
	f.player.CameraMode="Classic"; f:render(10)
	local writes=f.metrics.enabledWrites
	for _=1,200 do f:render(10) end
	check(f.metrics.enabledWrites==writes,"Unchanged camera state does not rewrite or invalidate billboard rendering")
	f.camera.CameraSubject=object("Humanoid","SpectatedHumanoid"); f:render(0.5)
	check(overhead.Enabled,"Spectating a close camera does not hide own avatar overhead")
	f.camera.CameraSubject=f.player.Character.Humanoid
	f.stats.Settings.LobbyMode.Value=true; f.stats.WinStreak.Value=7
	f.player:SetAttribute("HasVIP",true); f.player:GetAttributeChangedSignal("HasVIP"):Fire()
	f.player.Character.Humanoid.HealthChanged:Fire(50)
	check(overhead.Container.PlayerName.Text=="Owner [AFK]" and overhead.Container.Streak.StreakValue.Text=="7"
		and overhead.Container.PlayerMembership.Visible and overhead.Container.Health.Container.HealthBar.Size[1]==0.5,"Visibility styling preserves AFK, streak, VIP and health updates")
	f.player.CameraMode="LockFirstPerson"; f:render(0.5); f:character()
	check(not f.player.Character.Head.OverheadUI_Owner.Enabled,"Respawning while locked first person creates a hidden local overhead")
	f.player.CameraMode="Classic"; f:render(10)
	local oldCharacter, pendingCharacter = f.player.Character
	f.metrics.waitHook=function(parent,name)
		if parent.Name=="Health" and name=="Container" then
			f.metrics.waitHook=nil
			pendingCharacter=f.player.Character
			f:character()
		end
	end
	f:character()
	check(pendingCharacter and pendingCharacter~=f.player.Character
		and not pendingCharacter.Head:FindFirstChild("OverheadUI_Owner")
		and pendingCharacter.Humanoid.HealthChanged:Count()==0,"A template wait finishing after respawn cannot attach stale overhead instances or listeners")
	check(f.player.Character.Head.OverheadUI_Owner and oldCharacter.Humanoid.HealthChanged:Count()==0
		and f.player:GetAttributeChangedSignal("HasVIP"):Count()==1,"Template wait race leaves only the current character's overhead ownership")
	for _=1,30 do
		local old=f.player.Character; f:character()
		check(old.Humanoid.HealthChanged:Count()==0 and old.Head:FindFirstChild("OverheadUI_Owner")==nil,"Respawn releases old overhead health hooks and instances")
	end
	check(f.player:GetAttributeChangedSignal("HasVIP"):Count()==1,"Overhead VIP listener count remains constant across respawns")
	f.players.PlayerRemoving:Fire(f.player)
	check(f.player.CharacterAdded:Count()==0 and f.player.CharacterRemoving:Count()==0,"Departure releases overhead player listeners")
	check(f.player:GetAttributeChangedSignal("HasVIP"):Count()==0 and f.player.Character.Humanoid.HealthChanged:Count()==0,"Departure releases overhead stat and health listeners")
	check(next(f.run.bindings)==nil,"Departure removes the local overhead render binding")
	f=lightingFixture(load)
	check(f.lighting.ClockTime==20,"Night preference retains a night sky")
	check(f.lighting.Ambient.R>=76/255 and f.lighting.Ambient.B>=108/255
		and f.lighting.OutdoorAmbient.R>=98/255 and f.lighting.ExposureCompensation==0.18,"Night lobby gains readable shadow fill and modest exposure")
	local previousTween=f.tweens[#f.tweens]
	f.player:SetAttribute("InRound",true); f.player:GetAttributeChangedSignal("InRound"):Fire()
	check(f.lighting.Ambient==f.baseline.Ambient and f.lighting.OutdoorAmbient==f.baseline.OutdoorAmbient
		and f.lighting.ExposureCompensation==f.baseline.ExposureCompensation,"Entering combat restores authored lighting")
	check(previousTween.Cancelled and previousTween.Destroyed and previousTween.Completed:Count()==0,"Changing lighting cancels and destroys the previous tween and completion hook")
	f.player:SetAttribute("InRound",false); f.player:GetAttributeChangedSignal("InRound"):Fire()
	f.active.Value=true; check(f.lighting.ExposureCompensation==0.18,"Players still in the lobby keep readability during an active round")
	f.camera.CameraSubject=object("Humanoid","OtherHumanoid")
	check(f.lighting.Ambient==f.baseline.Ambient,"Spectating another player restores combat lighting")
	f.camera.CameraSubject=f.hum; f.camera.CameraType="Scriptable"
	check(f.lighting.Ambient==f.baseline.Ambient,"Scripted death camera keeps combat lighting")
	f.camera.CameraType="Custom"; f.day.Value=true
	check(f.lighting.ClockTime==14.5 and f.lighting.Ambient.R>=88/255 and f.lighting.ExposureCompensation==0,"Day preference stays day with clear lobby shadows")
	local count=#f.tweens
	f.player:GetAttributeChangedSignal("InRound"):Fire(); f.player.CharacterAdded:Fire(f.character)
	check(#f.tweens==count,"Repeated same-state signals do not create redundant lighting tweens")
	local oldCamera=f.camera; f.camera=object("Camera","ReplacementCamera",f.workspace)
	f.camera.CameraType="Custom"; f.camera.CameraSubject=f.hum; f.workspace.CurrentCamera=f.camera
	check(oldCamera:GetPropertyChangedSignal("CameraSubject"):Count()==0 and oldCamera:GetPropertyChangedSignal("CameraType"):Count()==0,"Camera replacement releases old lighting camera listeners")
	check(f.camera:GetPropertyChangedSignal("CameraSubject"):Count()==1,"New camera owns exactly one subject listener")
	f.day.Value=false; previousTween=f.tweens[#f.tweens]; previousTween.Completed:Fire()
	check(previousTween.Destroyed and previousTween.Completed:Count()==0,"A completed lighting tween releases its object and connection")
	f.controller.Destroy(); f.controller.Destroy()
	check(f.day:GetPropertyChangedSignal("Value"):Count()==0 and f.active:GetPropertyChangedSignal("Value"):Count()==0
		and f.player.CharacterAdded:Count()==0 and f.workspace:GetPropertyChangedSignal("CurrentCamera"):Count()==0
		and f.camera:GetPropertyChangedSignal("CameraSubject"):Count()==0,"Lighting teardown disconnects all player, setting, round and camera listeners")
	check(f.lighting.Ambient==f.baseline.Ambient and f.lighting.ExposureCompensation==f.baseline.ExposureCompensation,"Lighting teardown restores authored lighting")
	f=lightingFixture(load); f.controller.Destroy()
	local settings=object("Folder","Settings",f.stats); f.day.Parent=settings
	local frame=object("Frame","Settings",f.frames); local settingsContainer=object("Frame","Container",frame)
	object("TextButton","Exit",frame)
	object("Frame","ButtonThingy",object("TextButton","SettingsButton",object("Frame","Day",settingsContainer)))
	local settingsRemotes=object("Folder","Settings",f.remotes)
	object("RemoteEvent","ApplySetting",settingsRemotes); object("RemoteEvent","AppliedClient",settingsRemotes)
	local client=object("Folder","CLIENT"); object("ModuleScript","FramesHandler",client)
	object("ModuleScript","LobbyLighting",object("Folder","Modules",client))
	f.env.script=object("ModuleScript","SettingsClient",client)
	f.env.require=function(module)
		if module.Name=="FramesHandler" then return {OpenFrame=function() end} end
		if module.Name=="LobbyLighting" then return load("LobbyLighting",f.env) end
		error("Unexpected settings require: "..module.Name)
	end
	load("Settings",f.env)
	check(f.active:GetPropertyChangedSignal("Value"):Count()==1,"Settings client owns one lighting controller")
	f.env.script:Destroy()
	check(f.active:GetPropertyChangedSignal("Value"):Count()==0
		and f.camera:GetPropertyChangedSignal("CameraSubject"):Count()==0,"Destroying SettingsClient releases its lighting controller's round and camera subscriptions")
	check(f.lighting.Ambient==f.baseline.Ambient,"Destroying SettingsClient restores authored ambient lighting")
	f.env.script=object("ModuleScript","SettingsClientReplacement",client)
	f.metrics.waitHook=function(parent,name)
		if parent==f.rs and name=="GameActive" then
			f.metrics.waitHook=nil
			f.env.script:Destroy()
		end
	end
	load("Settings",f.env)
	check(f.env.script.Destroyed and f.active:GetPropertyChangedSignal("Value"):Count()==0
		and f.camera:GetPropertyChangedSignal("CameraSubject"):Count()==0
		and f.workspace:GetPropertyChangedSignal("CurrentCamera"):Count()==0,"Settings teardown during replicated-state wait cannot orphan lighting subscriptions")
	check(f.tweens[#f.tweens].Destroyed and f.tweens[#f.tweens].Completed:Count()==0
		and f.lighting.Ambient==f.baseline.Ambient,"A lighting controller completing startup after teardown releases its tween and restores baseline")
	print(string.format("Client UI lifecycle: %d checks passed", total))
end
