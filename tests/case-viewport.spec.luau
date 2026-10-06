local function eq(actual, expected, message)
	assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, message)
	assert(math.abs(actual - expected) < 1e-10, (message or "Values differ") .. ": " .. tostring(actual))
end
local function resume(thread, ...)
	local ok, result = coroutine.resume(thread, ...)
	assert(ok, result)
	return result
end
local function signal()
	local s = {listeners = {}, waiters = {}}
	function s:Connect(fn)
		local c = {Connected = true}
		function c:Disconnect() self.Connected = false end
		table.insert(self.listeners, {fn = fn, connection = c})
		return c
	end
	function s:Wait()
		table.insert(self.waiters, coroutine.running())
		return coroutine.yield()
	end
	function s:Fire(...)
		-- A wait registered during this frame resumes on the next heartbeat.
		local waiting = self.waiters
		self.waiters = {}
		local started = {}
		for _, item in ipairs(table.clone(self.listeners)) do
			if item.connection.Connected then
				local thread = coroutine.create(item.fn)
				table.insert(started, thread)
				resume(thread, ...)
			end
		end
		for _, thread in ipairs(waiting) do resume(thread, ...) end
		return started
	end
	function s:Count()
		local count = 0
		for _, item in ipairs(self.listeners) do if item.connection.Connected then count += 1 end end
		return count
	end
	return s
end

local function fixture()
	local f = {worldClones = 0, worldCloneAttempts = 0, cardClones = 0, loadCalls = 0, tracks = {}, animations = {}, worlds = {}, tweens = {}, timers = {}, randomCalls = 0, sounds = {}}
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
			if value then table.insert(value.children, self) end
		else self.props[key] = value end
		local changed = self.signals["Property_" .. key]
		if changed then changed:Fire() end
	end
	local function object(class, name, parent)
		local o = setmetatable({props = {ClassName = class, Name = name or class, Archivable = true, Visible = true, AbsolutePosition = {X = 0, Y = 0}, AbsoluteSize = {X = 80, Y = 80}}, children = {}, signals = {}}, meta)
		for _, key in ipairs({"Destroying", "MouseButton1Up", "OnClientEvent"}) do o.signals[key] = signal() end
		o.Parent = parent
		return o
	end
	f.object = object
	function methods:IsA(class) return self.ClassName == class or class == "Instance" end
	function methods:FindFirstChild(name, recursive)
		for _, child in ipairs(self.children) do if child.Name == name then return child end end
		if recursive then for _, child in ipairs(self.children) do local found = child:FindFirstChild(name, true); if found then return found end end end
	end
	function methods:FindFirstChildOfClass(class)
		for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
	end
	function methods:FindFirstChildWhichIsA(class, recursive)
		local own = self:FindFirstChildOfClass(class)
		if own then return own end
		if recursive then for _, child in ipairs(self.children) do local found = child:FindFirstChildWhichIsA(class, true); if found then return found end end end
	end
	function methods:GetChildren() return table.clone(self.children) end
	function methods:GetPropertyChangedSignal(name)
		self.signals["Property_" .. name] = self.signals["Property_" .. name] or signal()
		return self.signals["Property_" .. name]
	end
	function methods:Destroy()
		if self.Destroyed then return end
		self.Destroying:Fire()
		for _, child in ipairs(self:GetChildren()) do child:Destroy() end
		self.Parent = nil
		self.Destroyed = true
	end
	function methods:ClearAllChildren() for _, child in ipairs(self:GetChildren()) do child:Destroy() end end
	function methods:Clone()
		if self.ClassName == "WorldModel" then f.worldCloneAttempts += 1 end
		if self.FailClone then error("Injected clone failure") end
		if not self.Archivable then return nil end
		if self.ClassName == "WorldModel" then f.worldClones += 1 end
		if self.ClassName == "ImageButton" then f.cardClones += 1 end
		local copy = object(self.ClassName, self.Name)
		for key, value in pairs(self.props) do if key ~= "Parent" then copy[key] = value end end
		for _, child in ipairs(self.children) do local cloned = child:Clone(); if cloned then cloned.Parent = copy end end
		if self.ClassName == "WorldModel" then table.insert(f.worlds, copy) end
		return copy
	end
	function methods:FireServer(...)
		self.ServerCalls = (self.ServerCalls or 0) + 1
		self.LastArgs = {...}
	end
	function methods:LoadAnimation(animation)
		f.loadCalls += 1
		if f.failLoad then error("Injected load failure") end
		local track = {IsPlaying = false, playCount = 0, stopCount = 0, animation = animation}
		function track:Play() assert(not self.Destroyed, "Played a destroyed track"); self.IsPlaying = true; self.playCount += 1 end
		function track:Stop() self.IsPlaying = false; self.stopCount += 1 end
		function track:Destroy() self.Destroyed = true end
		table.insert(f.tracks, track)
		if f.loadHook then f.loadHook(track, animation) end
		return track
	end
	function f:world(parent)
		local world = object("WorldModel", "World", parent)
		object("Camera", "Camera", world)
		local rig = object("Model", "Rig", world)
		local humanoid = object("Humanoid", "Humanoid", rig)
		object("Animator", "Animator", humanoid)
		return world
	end
	function f:card(name, parent, emote)
		local card = object("ImageButton", name, parent)
		local rarity = object("ImageLabel", "Rarity", card)
		rarity.ImageTransparency = 0.75
		if emote then object("ViewportFrame", "EmoteViewport", card) else object("ImageLabel", "KnifeImage", card) end
		return card
	end
	f.heartbeat = signal()
	f.RunService = {Heartbeat = f.heartbeat}
	f.task = {}
	function f.task.delay(seconds, fn)
		local timer = {seconds = seconds, fn = fn, cancelled = false}
		table.insert(f.timers, timer)
		return timer
	end
	function f.task.cancel(timer) timer.cancelled = true end
	f.Enum = {PlaybackState = {Completed = "Completed", Cancelled = "Cancelled"}, EasingStyle = {Quint = "Quint", Quad = "Quad"}, EasingDirection = {Out = "Out"}}
	f.UDim2 = {new = function(xs, xo, ys, yo) return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}} end}
	f.TweenInfo = {new = function(duration, style, direction) return {Time = duration, EasingStyle = style, EasingDirection = direction} end}
	f.TweenService = {}
	function f.TweenService:Create(subject, info, goal)
		local tween = {Subject = subject, Info = info, Goal = goal, Completed = signal()}
		function tween:Play() assert(not self.Destroyed, "Played a destroyed tween"); self.Played = true end
		function tween:Cancel() self.Cancelled = true; self.Completed:Fire(f.Enum.PlaybackState.Cancelled) end
		function tween:Destroy() self.Destroyed = true end
		function tween:Complete(state)
			state = state or f.Enum.PlaybackState.Completed
			if state == f.Enum.PlaybackState.Completed then for key, value in pairs(self.Goal) do self.Subject[key] = value end end
			self.Completed:Fire(state)
		end
		table.insert(f.tweens, tween)
		return tween
	end
	f.env = {
		game = {GetService = function(_, name) assert(name == "RunService"); return f.RunService end},
		Instance = {new = function(class)
			local instance = object(class)
			if class == "Animation" then table.insert(f.animations, instance) end
			return instance
		end},
		RunService = f.RunService, task = f.task, Enum = f.Enum, UDim2 = f.UDim2, TweenInfo = f.TweenInfo, TweenService = f.TweenService,
	}
	return f
end

local function setupPool(load, count)
	local f = fixture()
	f.Pool = load("Pool", f.env)
	f.root = f.object("Folder", "Root")
	f.clip = f.object("Frame", "Clip", f.root)
	f.clip.AbsoluteSize = {X = 500, Y = 100}
	f.source = f:world(nil)
	f.source.Archivable = false
	f.visible = true
	f.pool = f.Pool.New(f.source, f.clip, function() return f.visible end)
	f.cards = {}
	for index = 1, count do
		local card = f:card(tostring(index), f.clip, true)
		table.insert(f.cards, card)
		f.pool:Add(card, "rbxassetid://" .. tostring(index % 2))
	end
	return f
end
local function activeEntries(pool)
	local count = 0
	for _, entry in ipairs(pool.entries) do if entry.slot then count += 1 end end
	return count
end
local function assertCleanup(f)
	eq(f.heartbeat:Count(), 0, "Pool heartbeat disconnected")
	for _, world in ipairs(f.worlds) do assert(world.Destroyed and world.Parent == nil, "Preview world survived teardown") end
	for _, track in ipairs(f.tracks) do assert(track.Destroyed and not track.IsPlaying, "Track survived teardown") end
	for _, animation in ipairs(f.animations) do assert(animation.Destroyed, "Animation survived teardown") end
end

local function setupReel(load)
	local f = fixture()
	local env = f.env
	env.CaseViewportPool = load("Pool", env)
	f.root = f.object("Folder", "Root")
	f.spinner = f.object("Frame", "Spinner", f.root)
	f.spinner.Visible = false
	f.clip = f.object("Frame", "Clip", f.spinner)
	f.clip.AbsoluteSize = {X = 500, Y = 100}
	f.spin = f.object("Frame", "Spin", f.clip)
	f.skip = f.object("TextButton", "Skip", f.spinner)
	f.again = f.object("TextButton", "Again", f.spinner)
	f.exit = f.object("TextButton", "Exit", f.spinner)
	f.header = f.object("TextLabel", "Header", f.spinner)
	f.shop = f.object("Frame", "Shop", f.root)
	f.remote = f.object("RemoteEvent", "OpenCaseAnimation")
	f.openRemote = f.object("RemoteEvent", "OpenCase")
	f.gamePass = f.object("RemoteEvent", "GamePass")
	f.template = f:card("KnifeTemplate", nil, false)
	f.emoteTemplate = f:card("EmoteTemplate", nil, true)
	f.source = f:world(f.emoteTemplate.EmoteViewport)
	env.OpenCaseAnimation, env.OpenCaseRemote, env.GamePass = f.remote, f.openRemote, f.gamePass
	env.SpinnerFrame, env.SpinnerContainer, env.SpinFrame = f.spinner, f.clip, f.spin
	env.SpinnerSkipButton, env.SpinnerOpenAgain, env.SpinnerExit = f.skip, f.again, f.exit
	env.HeaderText, env.ShopFrameUI = f.header, f.shop
	env.CaseSpinnerTemplate, env.CaseSpinnerTemplateEmote = f.template, f.emoteTemplate
	env.Lighting = {Blur = {Enabled = false}}
	env.CaseInfoModule = {Knife = {}, Emote = {EmoteCase = true}}
	env.RarityColorModule = {Common = {Image = "common-rarity"}, Legendary = {Image = "winner-rarity"}}
	env.EmotesModule = {Dance = {EmoteId = "rbxassetid://1"}, WinnerDance = {EmoteId = "rbxassetid://2"}}
	env.RandomItem = {RandomItem = function(casename)
		assert(casename == "Knife" or casename == "Emote")
		f.randomCalls += 1
		return {Knife = "Random " .. tostring(f.randomCalls), Image = "random-image", Rarity = "Common", SkinName = "Dance"}
	end}
	env.Random = {new = function() return {NextNumber = function(_, minimum, maximum)
		near(minimum, -4.055, "Original random tween lower bound")
		near(maximum, -3.92, "Original random tween upper bound")
		return -4.01
	end} end}
	env.SoundHandlerModule = {PlaySound = function(name) table.insert(f.sounds, name) end}
	load("Reel", env)
	function f:open(casename, knife, duration, hasskip)
		local details = {Case = casename, Knife = knife or "Winner", Image = "winner-image", Rarity = "Legendary", SkinName = "WinnerDance"}
		return self.remote.OnClientEvent:Fire(details, duration or 7, hasskip == true, casename)[1]
	end
	function f:buildRemaining()
		for _ = 1, 14 do self.heartbeat:Fire(1 / 30) end
	end
	return f
end

return function(load)
	local passed = 0
	local function test(name, fn)
		fn()
		passed += 1
		print("PASS " .. name)
	end

	test("lightweight card clones exclude world and restore Archivable on success and failure", function()
		local f = fixture()
		local Pool = load("Pool", f.env)
		local template = f:card("Template", nil, true)
		local source = f:world(template.EmoteViewport)
		for _, archivable in ipairs({true, false}) do
			source.Archivable = archivable
			local copy, returned = Pool.CloneCard(template)
			eq(returned, source)
			eq(source.Archivable, archivable)
			assert(copy.EmoteViewport and not copy.EmoteViewport:FindFirstChild("World"))
			assert(copy.Rarity, "Non-preview GUI omitted")
			eq(f.worldClones, 0)
			copy:Destroy()
			template.FailClone = true
			assert(not pcall(function() Pool.CloneCard(template) end), "Clone error should propagate")
			eq(source.Archivable, archivable, "Template flag after clone error")
			template.FailClone = false
		end
	end)

	test("150 slots create at most ten worlds and two clones and loads per refresh", function()
		local f = setupPool(load, 150)
		eq(#f.pool.slots, 150)
		eq(f.worldClones, 0, "Lazy construction")
		eq(f.loadCalls, 0)
		for _ = 1, 8 do
			local clones, loads = f.worldClones, f.loadCalls
			f.pool:Update()
			assert(f.worldClones - clones <= 2, "Unbounded world work in one refresh")
			assert(f.loadCalls - loads <= 2, "Unbounded animation work in one refresh")
			assert(#f.pool.entries <= 10 and activeEntries(f.pool) <= 10)
		end
		eq(f.worldClones, 10)
		eq(f.loadCalls, 10)
		eq(activeEntries(f.pool), 10)
		eq(f.source.Archivable, false, "World cloning restores original flag")
		f.pool:Destroy()
		eq(#f.pool.entries, 0)
		eq(#f.pool.slots, 0)
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("only cards intersecting the visible clip and overscan acquire previews", function()
		local f = setupPool(load, 150)
		for index, card in ipairs(f.cards) do card.AbsolutePosition = {X = (index - 1) * 100, Y = 0} end
		f.cards[2].Visible = false
		f.cards[3].AbsolutePosition = {X = 200, Y = 150}
		f.cards[4].Parent = nil
		f.cards[5].AbsoluteSize = {X = 0, Y = 80}
		for _ = 1, 5 do f.pool:Update() end
		eq(f.worldClones, 2, "Only cards one and six overlap")
		assert(f.pool.slots[1].entry and f.pool.slots[6].entry)
		for index, slot in ipairs(f.pool.slots) do if index ~= 1 and index ~= 6 then assert(not slot.entry, "Offscreen card acquired a preview") end end
		f.visible = false
		f.pool:Update()
		eq(activeEntries(f.pool), 0)
		for _, card in ipairs(f.cards) do eq(card.EmoteViewport.CurrentCamera, nil, "Hidden cards release their camera reference") end
		for _, track in ipairs(f.tracks) do assert(not track.IsPlaying) end
		f.visible = true
		f.pool:Update()
		eq(f.loadCalls, 2, "Hidden and shown cards reuse tracks")
		f.clip.Parent = nil
		f.pool:Update()
		eq(activeEntries(f.pool), 0, "Unparented clip stops previews")
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("scrolling a second cohort reuses rigs and matching tracks", function()
		local f = setupPool(load, 150)
		for index, card in ipairs(f.cards) do card.Visible = index <= 10 end
		for _ = 1, 5 do f.pool:Update() end
		eq(f.loadCalls, 10)
		for index, card in ipairs(f.cards) do card.Visible = index > 10 and index <= 20 end
		f.pool:Update()
		eq(f.worldClones, 10, "Existing world rigs reused")
		eq(f.loadCalls, 10, "Matching animation tracks reused")
		eq(activeEntries(f.pool), 10)
		for _, track in ipairs(f.tracks) do eq(track.playCount, 2); assert(not track.Destroyed) end
		for index = 1, 10 do
			assert(not f.pool.slots[index].entry)
			eq(f.cards[index].EmoteViewport.CurrentCamera, nil, "Previous cohort releases cameras")
		end
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("failed world clones restore flags and failed animation loads do not retry each frame", function()
		local f = setupPool(load, 1)
		f.source.FailClone = true
		f.pool:Update()
		eq(#f.pool.entries, 0)
		eq(f.source.Archivable, false)
		f.source.FailClone = false
		f.failLoad = true
		for _ = 1, 5 do f.pool:Update() end
		eq(f.loadCalls, 1, "Failed animation is remembered")
		eq(#f.tracks, 0)
		eq(#f.animations, 1)
		assert(f.animations[1].Destroyed)
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("failed world clone attempts remain bounded with 150 candidates", function()
		local f = setupPool(load, 150)
		f.source.FailClone = true
		for frame = 1, 5 do
			f.pool:Update()
			eq(f.worldCloneAttempts, frame * 2, "Failure path still observes per-refresh budget")
			eq(f.source.Archivable, false)
		end
		eq(#f.pool.entries, 0)
		eq(f.loadCalls, 0)
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("teardown during a yielding load destroys the late track and animation", function()
		local f = setupPool(load, 1)
		f.loadHook = function() coroutine.yield("asset-loading") end
		local pending = coroutine.create(function() f.pool:Update() end)
		eq(resume(pending), "asset-loading")
		assert(f.pool.entries[1].loading)
		f.pool:Update()
		eq(f.loadCalls, 1, "Overlapping refresh cannot load a second track into the same rig")
		f.pool:Destroy()
		resume(pending)
		eq(coroutine.status(pending), "dead")
		assertCleanup(f)
	end)

	test("a yielding load cannot attach its track to a replacement slot", function()
		local f = setupPool(load, 2)
		f.cards[2].Visible = false
		f.loadHook = function() coroutine.yield("asset-loading") end
		local pending = coroutine.create(function() f.pool:Update() end)
		resume(pending)
		f.cards[1].Visible, f.cards[2].Visible = false, true
		f.pool:Update()
		eq(f.loadCalls, 1)
		resume(pending)
		assert(f.tracks[1].Destroyed and f.animations[1].Destroyed)
		assert(not f.pool.slots[2].entry.track, "Old animation attached to replacement card")
		f.loadHook = nil
		f.pool:Update()
		eq(f.loadCalls, 2)
		eq(f.pool.slots[2].entry.track.animation.AnimationId, f.pool.slots[2].animationId)
		f.pool:Destroy()
		assertCleanup(f)
	end)

	test("production knife reel keeps all 150 cards, winner 139, spacing and tween goals", function()
		local f = setupReel(load)
		local opening = f:open("Knife", "Test Winner", 7, false)
		eq(#f.spin:GetChildren(), 10, "First batch is ten cards")
		eq(#f.tweens, 0, "Tween waits for metadata construction")
		for frame = 1, 14 do
			f.heartbeat:Fire(1 / 30)
			eq(#f.spin:GetChildren(), (frame + 1) * 10, "Ten cards per heartbeat")
		end
		eq(coroutine.status(opening), "dead")
		eq(f.randomCalls, 149, "Winner is never replaced by a random item")
		eq(f.cardClones, 150)
		for index = 1, 150 do
			local card = assert(f.spin:FindFirstChild(tostring(index)))
			eq(card.LayoutOrder, index - 1)
			near(card.Position.X.Scale, -0.991 + (index - 1) * 0.014, "Original card spacing")
			eq(card.Position.X.Offset, 0)
			near(card.Position.Y.Scale, 0.5)
			eq(card.Position.Y.Offset, 0)
			eq(card.KnifeImage.Image, index == 139 and "winner-image" or "random-image")
			eq(card.Rarity.Image, index == 139 and "winner-rarity" or "common-rarity")
		end
		eq(#f.tweens, 1)
		local initial = f.tweens[1]
		eq(initial.Subject, f.spin)
		eq(initial.Info.Time, 7)
		eq(initial.Info.EasingStyle, "Quint")
		eq(initial.Info.EasingDirection, "Out")
		near(initial.Goal.Position.X.Scale, -4.01)
		near(initial.Goal.Position.Y.Scale, 0.5)
		eq(f.sounds[1], "CaseOpen")
		assert(f.skip.Visible and not f.exit.Visible and not f.again.Visible)
		eq(f.timers[1].seconds, 6)
		initial:Complete()
		eq(#f.tweens, 3)
		local finish, rarity = f.tweens[2], f.tweens[3]
		near(finish.Goal.Position.X.Scale, -3.99, "Original winner settling position")
		eq(finish.Info.Time, 0.15)
		eq(finish.Info.EasingStyle, "Quad")
		eq(rarity.Subject, f.spin:FindFirstChild("139").Rarity)
		eq(rarity.Goal.ImageTransparency, 0)
		assert(rarity.Played and finish.Played)
		assert(not f.exit.Visible, "Buttons wait for settling tween")
		finish:Complete()
		assert(f.exit.Visible and f.again.Visible and not f.skip.Visible)
		eq(f.header.Text, "You Unboxed: Test Winner")
		f.again.MouseButton1Up:Fire()
		eq(f.openRemote.LastArgs[1], "Knife")
		f.skip.MouseButton1Up:Fire()
		eq(f.gamePass.LastArgs[1], "1")
		f.exit.MouseButton1Up:Fire()
		assert(not f.spinner.Visible and f.shop.Visible)
		eq(#f.spin:GetChildren(), 0)
		for _, tween in ipairs(f.tweens) do assert(tween.Cancelled and tween.Destroyed); eq(tween.Completed:Count(), 0) end
		assert(f.timers[1].cancelled)
		f.spinner:Destroy()
		eq(f.remote.OnClientEvent:Count(), 0)
	end)

	test("production emote reel excludes source rigs while constructing 150 metadata cards", function()
		local f = setupReel(load)
		f:open("Emote", "Winner", 5, true)
		eq(f.worldClones, 0, "First lightweight batch clones no rigs")
		for _ = 1, 14 do
			local clones, loads = f.worldClones, f.loadCalls
			f.heartbeat:Fire(1 / 30)
			assert(f.worldClones - clones <= 2 and f.loadCalls - loads <= 2)
		end
		eq(#f.spin:GetChildren(), 150)
		eq(f.cardClones, 150)
		eq(f.randomCalls, 149)
		eq(f.worldClones, 10)
		eq(f.source.Archivable, true)
		local worlds = 0
		for _, card in ipairs(f.spin:GetChildren()) do if card.EmoteViewport:FindFirstChild("World") then worlds += 1 end end
		eq(worlds, 10, "World count is independent of card count")
		assert(not f.skip.Visible)
		eq(#f.timers, 0)
		f.spinner.Visible = false
		eq(#f.spin:GetChildren(), 0)
		assertCleanup(f)
		f.spinner:Destroy()
	end)

	test("replacing an opening during its batch yield cancels the old continuation", function()
		local f = setupReel(load)
		local old = f:open("Emote", "Old Winner")
		local discarded = f.spin:GetChildren()
		local replacement = f:open("Knife", "Replacement Winner")
		for _, card in ipairs(discarded) do assert(card.Destroyed) end
		eq(#f.spin:GetChildren(), 10)
		f:buildRemaining()
		eq(coroutine.status(old), "dead")
		eq(coroutine.status(replacement), "dead")
		eq(#f.spin:GetChildren(), 150)
		eq(f.randomCalls, 159, "Old continuation contributes no cards after replacement")
		eq(f.cardClones, 160)
		eq(#f.tweens, 1, "Only replacement starts a tween")
		eq(f.heartbeat:Count(), 0, "Old emote preview scheduler is removed")
		f.tweens[1]:Complete()
		f.tweens[2]:Complete()
		eq(f.header.Text, "You Unboxed: Replacement Winner")
		f.spinner:Destroy()
	end)

	test("cancelled playback cannot finish and stale callbacks cannot alter a new reel", function()
		local f = setupReel(load)
		f:open("Knife", "Old Winner")
		f:buildRemaining()
		local oldTween = f.tweens[1]
		local oldInitialCallback = oldTween.Completed.listeners[1].fn
		local oldTimer = f.timers[1]
		oldTween:Complete(f.Enum.PlaybackState.Cancelled)
		eq(#f.tweens, 1, "Cancelled playback does not create settling tweens")
		assert(not f.exit.Visible and not f.again.Visible)
		oldTween:Complete()
		local oldFinish, oldRarity = f.tweens[2], f.tweens[3]
		local oldFinishCallback = oldFinish.Completed.listeners[1].fn
		oldFinish:Complete(f.Enum.PlaybackState.Cancelled)
		assert(not f.exit.Visible and not f.again.Visible)
		f:open("Knife", "New Winner", 7, false)
		for _, tween in ipairs({oldTween, oldFinish, oldRarity}) do assert(tween.Cancelled and tween.Destroyed); eq(tween.Completed:Count(), 0) end
		assert(oldTimer.cancelled)
		f:buildRemaining()
		assert(f.skip.Visible)
		local before = #f.tweens
		-- Force queued engine callbacks even after disconnection to exercise the
		-- generation checks independently of signal cleanup.
		oldInitialCallback(f.Enum.PlaybackState.Completed)
		oldFinishCallback(f.Enum.PlaybackState.Completed)
		oldTimer.fn()
		eq(#f.tweens, before, "Old completion cannot create a tween")
		eq(f.header.Text, "Opening Knife")
		assert(f.skip.Visible and not f.exit.Visible and not f.again.Visible, "Stale callbacks changed buttons")
		f.timers[2].fn()
		assert(not f.skip.Visible, "Current timer still works")
		f.spinner:Destroy()
	end)

	test("hidden and destroyed spinners stop suspended construction and unsubscribe remote", function()
		local f = setupReel(load)
		local pending = f:open("Emote")
		f.spinner.Visible = false
		eq(#f.spin:GetChildren(), 0)
		f.heartbeat:Fire(1 / 30)
		eq(coroutine.status(pending), "dead")
		eq(f.randomCalls, 10)
		eq(#f.tweens, 0)
		eq(f.heartbeat:Count(), 0)
		pending = f:open("Emote")
		local remoteCallback = f.remote.OnClientEvent.listeners[1].fn
		f.spinner:Destroy()
		eq(f.remote.OnClientEvent:Count(), 0, "Destroyed spinner unsubscribes its remote")
		f.heartbeat:Fire(1 / 30)
		eq(coroutine.status(pending), "dead")
		eq(f.randomCalls, 20)
		remoteCallback({Case = "Knife", Knife = "Stale"}, 5, false, "Knife")
		eq(f.randomCalls, 20, "Queued event cannot restart destroyed spinner")
		assertCleanup(f)
	end)

	test("destroying the production spinner cleans a late preview asset load", function()
		local f = setupReel(load)
		local opening = f:open("Emote")
		f.loadHook = function() coroutine.yield("asset-loading") end
		local pending = f.heartbeat:Fire(1 / 30)[1]
		eq(coroutine.status(pending), "suspended")
		eq(#f.spin:GetChildren(), 20)
		eq(f.loadCalls, 1)
		f.spinner:Destroy()
		resume(pending)
		f.heartbeat:Fire(1 / 30)
		eq(coroutine.status(opening), "dead")
		eq(f.randomCalls, 20, "Construction stops at spinner destruction")
		eq(f.remote.OnClientEvent:Count(), 0)
		assertCleanup(f)
	end)

	test("invalid reel payloads never cancel or replace the active opening", function()
		local f = setupReel(load)
		f:open("Knife", "Valid")
		for _, args in ipairs({
			{false, 5, false, "Knife"},
			{{Case = "Knife"}, -1, false, "Knife"},
			{{Case = "Knife"}, 0 / 0, false, "Knife"},
			{{Case = "Knife"}, math.huge, false, "Knife"},
			{{Case = "Knife"}, "5", false, "Knife"},
			{{Case = "Missing"}, 5, false, "Missing"},
		}) do f.remote.OnClientEvent:Fire(table.unpack(args)) end
		eq(#f.spin:GetChildren(), 10)
		f:buildRemaining()
		eq(f.randomCalls, 149)
		f.tweens[1]:Complete()
		f.tweens[2]:Complete()
		eq(f.header.Text, "You Unboxed: Valid")
		f.spinner:Destroy()
	end)

	print("Case viewport and production reel: " .. tostring(passed) .. " tests passed")
end
