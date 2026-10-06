local function signal()
	local listeners, event = {}, {}
	function event:Connect(fn)
		local connection = {Connected = true, fn = fn}
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, connection); return connection
	end
	function event:Fire(...)
		for _, listener in ipairs(table.clone(listeners)) do if listener.Connected then listener.fn(...) end end
	end
	function event:Count()
		local count = 0; for _, listener in ipairs(listeners) do if listener.Connected then count += 1 end end; return count
	end
	return event
end

local vectorMeta = {}
function vectorMeta.__add(a, b) return setmetatable({X = a.X+b.X, Y = a.Y+b.Y, Z = a.Z+b.Z}, vectorMeta) end
function vectorMeta.__div(a, b) return setmetatable({X = a.X/b, Y = a.Y/b, Z = a.Z/b}, vectorMeta) end
local function vector(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vectorMeta) end
local function dim2(x, xo, y, yo) return {X = {Scale = x, Offset = xo}, Y = {Scale = y, Offset = yo}} end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); passed += 1; print("PASS " .. name)
	end
	local function fixture(skipInit)
		local f = {created = {}, timers = {}, animations = {}, time = 0, plays = 0}
		local methods, meta = {}, {}
		function meta.__index(self, key)
			if methods[key] then return methods[key] end
			if self.props[key] ~= nil then return self.props[key] end
			for _, item in ipairs(self.children) do if item.Name == key then return item end end
		end
		function meta.__newindex(self, key, value)
			if key == "Parent" then
				if self.props.Parent then local index = table.find(self.props.Parent.children, self); if index then table.remove(self.props.Parent.children, index) end end
				if value then table.insert(value.children, self) end
			end
			self.props[key] = value
		end
		local function object(class, name, parent)
			local result = setmetatable({props = {ClassName = class, Name = name or class, Destroying = signal()}, children = {}, signals = {}}, meta)
			if class == "ScreenGui" or class == "BillboardGui" then result.ResetOnSpawn = true end
			result.Parent = parent; table.insert(f.created, result); return result
		end
		function methods:IsA(class) return class == self.ClassName or class == "BasePart" and self.ClassName == "Part" end
		function methods:FindFirstChild(name) for _, item in ipairs(self.children) do if item.Name == name then return item end end end
		function methods:WaitForChild(name) if f.onWait then f.onWait() end; return assert(self:FindFirstChild(name), name) end
		function methods:FindFirstChildOfClass(class) for _, item in ipairs(self.children) do if item:IsA(class) then return item end end end
		function methods:GetPropertyChangedSignal(name) self.signals[name] = self.signals[name] or signal(); return self.signals[name] end
		function methods:Destroy()
			if self.destroyed then return end
			self.destroyed = true; self.Destroying:Fire()
			for _, item in ipairs(table.clone(self.children)) do item:Destroy() end
			self.Parent = nil
		end
		function methods:Play() self.IsPlaying = true; f.plays += 1 end
		function methods:Stop() self.IsPlaying = false end
		local function remote(parent, name) local r = object("RemoteEvent", name, parent); r.OnClientEvent = signal(); return r end
		f.player = object("Player", "Player"); f.playerGui = object("PlayerGui", "PlayerGui", f.player)
		local players, storage, sound = {LocalPlayer = f.player}, object("Folder", "Storage"), object("Folder", "SoundService")
		local modules = object("Folder", "Modules", storage)
		local config, audio = object("ModuleScript", "CombatFeedbackConfig", modules), object("ModuleScript", "CombatAudioConfig", modules)
		local knife = object("Folder", "Knife", object("Folder", "Remotes", storage))
		f.damage, f.kill = remote(knife, "DamageDealtClient"), remote(knife, "PlayerGotKilledRemote")
		f.workspace = object("Workspace", "Workspace"); f.camera = object("Camera", "Camera"); f.camera.ViewportSize = vector(1280, 720)
		f.workspace.CurrentCamera = f.camera
		f.victim = object("Model", "Victim"); object("Part", "Head", f.victim); f.humanoid = object("Humanoid", "Humanoid", f.victim); f.humanoid.Health = 100
		local tweens = {Create = function(_, target, info, goal)
			local animation = {target = target, info = info, goal = goal, start = {}}
			function animation:Play()
				for key, value in pairs(goal) do self.start[key] = target[key]; target[key] = value end
			end
			function animation:Cancel() self.cancelled = true end
			function animation:Destroy() self.destroyed = true end
			table.insert(f.animations, animation)
			return animation
		end}
		f.env = {
			game = {GetService = function(_, name) return assert(({Players = players, ReplicatedStorage = storage, SoundService = sound, TweenService = tweens})[name], name) end},
			workspace = f.workspace, Instance = {new = object}, typeof = function(value) return getmetatable(value) == meta and "Instance" or type(value) end,
			Vector2 = {new = vector}, Vector3 = {new = vector}, UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end},
			UDim2 = {new = dim2, fromOffset = function(x,y) return dim2(0,x,0,y) end, fromScale = function(x,y) return dim2(x,0,y,0) end},
			Color3 = {fromRGB = vector}, TweenInfo = {new = function(seconds, style) return {Seconds = seconds, Style = style} end},
			Enum = {Font = {GothamBold = "Bold", GothamBlack = "Black"}, TextXAlignment = {Left = "Left"}, TextTruncate = {AtEnd = "End"}, EasingStyle = {Quad = "Quad", Back = "Back"}, EasingDirection = {Out = "Out"}, ZIndexBehavior = {Sibling = "Sibling"}},
			task = {delay = function(delay, fn) local timer = {at = f.time+delay, fn = fn}; table.insert(f.timers, timer); return timer end,
				cancel = function(timer) timer.cancelled = true end},
		}
		f.config, f.audio = load("Config", f.env), load("AudioConfig", f.env)
		f.env.require = function(module) if module == config then return f.config elseif module == audio then return f.audio else error("Unknown module") end end
		f.feedback = load("Feedback", f.env)
		function f.init() f.feedback.Init(); f.gui = f.playerGui.CombatFeedback; f.host = f.gui.KillNotifications end
		function f.respawnLocal()
			-- Roblox clears resettable LayerCollectors from PlayerGui on character respawn.
			for _, child in ipairs(table.clone(f.playerGui.children)) do
				if child.ResetOnSpawn ~= false then child:Destroy() end
			end
		end
		function f.respawnVictim()
			f.victim:Destroy()
			f.victim = object("Model", "Victim")
			object("Part", "Head", f.victim)
			f.humanoid = object("Humanoid", "Humanoid", f.victim); f.humanoid.Health = 100
		end
		function f.advance(seconds)
			local limit = f.time + seconds
			while true do
				local nextTimer
				for _, timer in ipairs(f.timers) do if not timer.cancelled and not timer.ran and timer.at <= limit and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end end
				if not nextTimer then break end
				f.time, nextTimer.ran = nextTimer.at, true; nextTimer.fn()
			end
			f.time = limit
		end
		function f.eliminate(id, userId)
			f.kill.OnClientEvent:Fire("Kill", {KillId = tostring(id), VictimUserId = userId or 42, VictimUsername = "User" .. id})
		end
		function f.card(name) for _, card in ipairs(f.host.children) do if card.ClassName == "Frame" and card.Username.Text == name then return card end end end
		function f.animation(target, property)
			for index = #f.animations, 1, -1 do
				local animation = f.animations[index]
				if animation.target == target and animation.goal[property] ~= nil then return animation end
			end
		end
		if not skipInit then f.init() end
		return f
	end
	 test("damage and sound instances stay bounded through 200 server-confirmed hits", function()
		local f = fixture(); local created = #f.created
		for _ = 1, 200 do f.damage.OnClientEvent:Fire(f.victim, 25, "Revolver") end
		assert(#f.created == created and f.plays == 200)
		assert(f.gui.HitConfirmation.Visible and f.playerGui.DamageFeedback1.Amount.Text == "-25")
		f.advance(2); assert(not f.gui.HitConfirmation.Visible)
		for index = 1, f.config.Damage.MaxActive do assert(not f.playerGui["DamageFeedback" .. index].Enabled and not f.playerGui["DamageFeedback" .. index].Adornee) end
	end)
	 test("server headshots are red and body shots stay white for revolver and knife throws", function()
		local f = fixture()
		f.damage.OnClientEvent:Fire(f.victim, 34, "Revolver", "BasicRevolver", false)
		f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver", "BasicRevolver", true)
		f.damage.OnClientEvent:Fire(f.victim, 50, "KnifeThrow", "BasicKnife", false)
		f.humanoid.Health = 0
		f.damage.OnClientEvent:Fire(f.victim, 100, "KnifeThrow", "BasicKnife", true)
		for index, text in ipairs({"-34", "-70", "-50", "-100"}) do
			local amount = f.playerGui["DamageFeedback" .. index].Amount
			local headshot = index % 2 == 0
			assert(amount.Text == text)
			assert(amount.TextColor3 == (headshot and f.config.Damage.HeadshotColor or f.config.Damage.Color))
			assert(amount.TextSize == (headshot and f.config.Damage.HeadshotTextSize or f.config.Damage.TextSize))
		end
		assert(f.plays == 4)
	end)
	 test("legacy events and lethal body hits remain white regardless of amount or humanoid health", function()
		local f = fixture(); f.humanoid.Health = 0
		f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver")
		f.damage.OnClientEvent:Fire(f.victim, 50, "KnifeThrow", "BasicKnife", false)
		f.damage.OnClientEvent:Fire(f.victim, 100, "KnifeThrow", "BasicKnife", "true")
		f.damage.OnClientEvent:Fire(f.victim, 100, "KnifeThrow", "BasicKnife", 1)
		for index = 1, 4 do
			assert(f.playerGui["DamageFeedback" .. index].Amount.TextColor3 == f.config.Damage.Color)
			assert(f.playerGui["DamageFeedback" .. index].Amount.TextSize == f.config.Damage.TextSize)
		end
		assert(f.gui.HitConfirmation.Corner.BackgroundColor3 == f.config.Hit.KillColor)
	end)
	 test("headshots pop from the center and settle upright while floating a little higher", function()
		local f = fixture(); f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver", "BasicRevolver", true)
		local billboard, amount = f.playerGui.DamageFeedback1, f.playerGui.DamageFeedback1.Amount
		assert(amount.AnchorPoint.X == 0.5 and amount.AnchorPoint.Y == 0.5)
		assert(amount.Position.X.Scale == 0.5 and amount.Position.Y.Scale == 0.5)
		local pop = f.animation(amount.PopScale, "Scale")
		assert(pop.start.Scale == f.config.Damage.HeadshotPopScale and pop.goal.Scale == 1)
		assert(pop.info.Seconds == f.config.Damage.PopTime and pop.info.Style == "Back")
		local tilt = f.animation(amount, "Rotation")
		assert(math.abs(tilt.start.Rotation) == f.config.Damage.HeadshotTilt and tilt.goal.Rotation == 0)
		local rise = f.animation(billboard, "StudsOffsetWorldSpace")
		assert(math.abs(rise.goal.StudsOffsetWorldSpace.Y - rise.start.StudsOffsetWorldSpace.Y - f.config.Damage.HeadshotRise) < 1e-6)
		assert(f.config.Damage.HeadshotTextSize > f.config.Damage.TextSize and f.config.Damage.HeadshotRise > f.config.Damage.Rise)
	end)
	 test("recycling a fading headshot resets body style and stale timers cannot hide the new damage", function()
		local f = fixture(); local created = #f.created
		f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver", "BasicRevolver", true)
		f.advance(0.7)
		local billboard, amount = f.playerGui.DamageFeedback1, f.playerGui.DamageFeedback1.Amount
		local oldTimer = f.timers[#f.timers]
		local oldTilt, oldFade = f.animation(amount, "Rotation"), f.animation(amount, "TextTransparency")
		for _ = 2, f.config.Damage.MaxActive do f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver", "BasicRevolver", true) end
		f.damage.OnClientEvent:Fire(f.victim, 34, "Revolver", "BasicRevolver", false)
		assert(amount.Text == "-34" and amount.TextColor3 == f.config.Damage.Color and amount.TextSize == f.config.Damage.TextSize)
		assert(amount.Rotation == 0 and amount.TextTransparency == 0 and amount.TextStrokeTransparency == 0.15)
		assert(f.animation(amount.PopScale, "Scale").start.Scale == f.config.Damage.PopScale)
		assert(oldTilt.cancelled and oldTilt.destroyed and oldFade.cancelled and oldFade.destroyed)
		oldTimer.fn(); assert(billboard.Enabled and billboard.Adornee == f.victim.Head)
		assert(#f.created == created)
		f.advance(2); assert(not billboard.Enabled and not billboard.Adornee)
	end)
	 test("zero configured damage labels still allows hit confirmation and audio", function()
		local f = fixture(true); f.config.Damage.MaxActive = 0; f.init()
		f.damage.OnClientEvent:Fire(f.victim, 70, "Revolver", "BasicRevolver", true)
		assert(f.gui.HitConfirmation.Visible and f.plays == 1 and not f.playerGui.DamageFeedback1)
	end)
	 test("kill pool and reward identity survive rapid kills and stale reward events", function()
		local f = fixture(); local created = #f.created
		for index = 1, 30 do f.eliminate(index) end
		assert(#f.created == created and not f.card("User1") and f.card("User30"))
		local latest = f.card("User30")
		assert(latest.Portrait.Avatar.Image == "rbxthumb://type=AvatarHeadShot&id=42&w=150&h=150")
		f.kill.OnClientEvent:Fire("KillReward", {KillId = "1", XpEarned = 99}); assert(latest.XP.Text == "XP earned ...")
		f.kill.OnClientEvent:Fire("KillReward", {KillId = "30", XpEarned = 37}); assert(latest.XP.Text == "+37 XP earned")
		f.kill.OnClientEvent:Fire("KillReward", {KillId = "29", XpEarned = 0}); assert(f.card("User29").XP.Text == "+0 XP earned")
		f.advance(4); for _, child in ipairs(f.host.children) do if child.ClassName == "Frame" then assert(not child.Visible) end end
	end)
	 test("damage labels survive attacker respawn without rebuilding UI or duplicating listeners", function()
		local f = fixture(); local created = #f.created
		f.damage.OnClientEvent:Fire(f.victim, 25, "Revolver")
		f.respawnLocal()
		for index = 1, f.config.Damage.MaxActive do
			local billboard = assert(f.playerGui["DamageFeedback" .. index], "respawn deleted pooled damage label")
			assert(not billboard.destroyed and billboard.ResetOnSpawn == false)
		end
		f.advance(2)
		f.damage.OnClientEvent:Fire(f.victim, 40, "Revolver")
		assert(f.playerGui.DamageFeedback2.Enabled and f.playerGui.DamageFeedback2.Amount.Text == "-40")
		assert(f.gui.HitConfirmation.Visible and f.plays == 2 and #f.created == created)
		f.eliminate(1); assert(f.card("User1").Visible)
		assert(f.damage.OnClientEvent:Count() == 1 and f.kill.OnClientEvent:Count() == 1)
	end)
	 test("damage after victim respawn attaches to the new character instead of the dead head", function()
		local f = fixture(); local oldHead = f.victim.Head
		f.humanoid.Health = 0; f.damage.OnClientEvent:Fire(f.victim, 100, "KnifeThrow")
		assert(f.playerGui.DamageFeedback1.Adornee == oldHead)
		f.respawnVictim()
		f.damage.OnClientEvent:Fire(f.victim, 35, "Revolver")
		assert(f.playerGui.DamageFeedback2.Adornee == f.victim.Head and f.victim.Head ~= oldHead)
		assert(f.playerGui.DamageFeedback2.Enabled and f.playerGui.DamageFeedback2.Amount.Text == "-35")
		assert(f.playerGui.DamageFeedback2.Amount.TextColor3 == f.config.Damage.Color)
		f.advance(2)
		for index = 1, f.config.Damage.MaxActive do assert(not f.playerGui["DamageFeedback" .. index].Adornee) end
	end)
	 test("repeated attacker and victim respawns reuse a bounded damage pool and ignore stale timers", function()
		local f = fixture(); local pool = {}
		for index = 1, f.config.Damage.MaxActive do pool[index] = f.playerGui["DamageFeedback" .. index] end
		local guiCount = 0
		for _, item in ipairs(f.created) do if item.ClassName == "BillboardGui" then guiCount += 1 end end
		f.damage.OnClientEvent:Fire(f.victim, 25, "Revolver")
		local staleTimer = f.timers[#f.timers]
		for cycle = 1, 30 do
			f.respawnLocal(); f.respawnVictim()
			f.damage.OnClientEvent:Fire(f.victim, cycle, "Revolver")
			local index = cycle % f.config.Damage.MaxActive + 1
			assert(pool[index].Parent == f.playerGui and not pool[index].destroyed)
			assert(pool[index].Enabled and pool[index].Adornee == f.victim.Head)
		end
		staleTimer.fn(); assert(pool[1].Enabled and pool[1].Adornee == f.victim.Head)
		local afterCount = 0
		for _, item in ipairs(f.created) do if item.ClassName == "BillboardGui" then afterCount += 1 end end
		assert(afterCount == guiCount and f.damage.OnClientEvent:Count() == 1 and f.kill.OnClientEvent:Count() == 1)
		f.advance(2)
		for _, billboard in ipairs(pool) do assert(not billboard.Enabled and not billboard.Adornee) end
		f.feedback.Destroy()
		for _, billboard in ipairs(pool) do assert(billboard.destroyed and not billboard.Parent) end
	end)
	 test("recycled-card timers cannot hide a newer elimination", function()
		local f = fixture(); f.eliminate(1); local oldTimer = f.timers[#f.timers]
		f.eliminate(2); f.eliminate(3); f.eliminate(4); oldTimer.fn()
		assert(f.card("User4").Visible); f.advance(4); assert(not f.card("User4").Visible)
	end)
	 test("malformed damage and reward events cannot create feedback or invalid text", function()
		local f = fixture(); f.eliminate(1)
		for _, amount in ipairs({0, -1, math.huge, 0/0}) do f.damage.OnClientEvent:Fire(f.victim, amount, "Revolver"); f.kill.OnClientEvent:Fire("KillReward", {KillId = "1", XpEarned = amount}) end
		assert(f.plays == 0 and not f.gui.HitConfirmation.Visible and f.card("User1").XP.Text == "+0 XP earned")
		f.damage.OnClientEvent:Fire({}, 50, "Revolver"); assert(f.plays == 0)
	end)
	 test("aim tracking and viewport resizing update existing UI only", function()
		local f = fixture(); local created = #f.created
		f.feedback.SetAimPosition(vector(500, 240)); f.damage.OnClientEvent:Fire(f.victim, 10)
		assert(f.gui.HitConfirmation.Position.X.Offset == 500)
		f.feedback.SetAimPosition(vector(620, 350)); assert(f.gui.HitConfirmation.Position.Y.Offset == 350)
		f.camera.ViewportSize = vector(320, 640); f.camera:GetPropertyChangedSignal("ViewportSize"):Fire()
		assert(f.host.ResponsiveScale.Scale < 1 and #f.created == created)
	end)
	 test("Studio test users retain elimination text with an unavailable avatar thumbnail", function()
		local f = fixture(); f.eliminate(1, -2); assert(f.card("User1").Visible and f.card("User1").Portrait.Avatar.Image == "")
	end)
	 test("teardown cancels timers and connections then allows one clean reinitialization", function()
		local f = fixture(); f.eliminate(1); f.damage.OnClientEvent:Fire(f.victim, 25, "KnifeThrow")
		f.feedback.Init(); assert(f.damage.OnClientEvent:Count() == 1 and f.kill.OnClientEvent:Count() == 1)
		f.feedback.Destroy(); assert(f.damage.OnClientEvent:Count() == 0 and f.kill.OnClientEvent:Count() == 0)
		f.advance(10); assert(not f.playerGui.CombatFeedback)
		f.init(); assert(f.damage.OnClientEvent:Count() == 1 and f.kill.OnClientEvent:Count() == 1)
	end)
	 test("a stale initializer cannot duplicate a replacement started during dependency waits", function()
		local f = fixture(true)
		f.onWait = function()
			f.onWait = nil
			f.feedback.Destroy()
			f.init()
		end
		f.feedback.Init()
		assert(f.damage.OnClientEvent:Count() == 1 and f.kill.OnClientEvent:Count() == 1)
		local screens, sounds = 0, 0
		for _, item in ipairs(f.created) do
			if item.ClassName == "ScreenGui" and not item.destroyed then screens += 1 end
			if item.ClassName == "Sound" and not item.destroyed then sounds += 1 end
		end
		assert(screens == 1 and sounds == f.audio.Hit.MaxActiveSounds)
	end)
	print(string.format("%d combat feedback tests passed", passed))
end
