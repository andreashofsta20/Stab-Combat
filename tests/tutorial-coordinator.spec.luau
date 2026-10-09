local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function signal()
	local s = {listeners = {}}
	function s:Connect(fn)
		local connection = {active = true, fn = fn}
		function connection:Disconnect() self.active = false end
		table.insert(self.listeners, connection); return connection
	end
	function s:Fire(...)
		for _, connection in ipairs(table.clone(self.listeners)) do if connection.active then connection.fn(...) end end
	end
	return s
end
local vector
local vectorMeta = {
	__sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	__index = function(v, key) if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end end,
}
vector = function(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vectorMeta) end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, reason = pcall(fn); assert(ok, name .. ": " .. tostring(reason)); passed += 1
	end
	local function fixture(options)
		options = options or {}
		local f = {time = 100, jobs = {}, timers = {}, sent = {}, travelCalls = {}, issueCalls = 0, claimCalls = 0,
			earnCalls = 0, rewardSaves = 0, analytics = {}, warnings = {}, arenas = {}}
		f.config = {Enabled = true, Version = 1, MainPlaceId = 11, TutorialPlaceId = 22, StartCooldownSeconds = 10,
			Rewards = {XP = 500, Gold = 500, Knife = "Shadow Dagger"}, RewardSaveTimeoutSeconds = 20,
			AutoReturnSeconds = 8, DataReadyTimeoutSeconds = 3, RequestBurst = 100, RequestsPerSecond = 100,
			SampleSeconds = 0.1, ProgressPushSeconds = 0.25, SuccessPauseSeconds = 0.65, SessionTimeoutSeconds = 1800}
		f.steps = options.Steps or {{Id = "welcome", Kind = "Read", Goal = 1, MinSeconds = 0},
			{Id = "stab", Kind = "KnifeStab", Goal = 1, MinSeconds = 0}, {Id = "finish", Kind = "Read", Goal = 1, MinSeconds = 0}}
		f.players = {PlayerAdded = signal(), PlayerRemoving = signal(), RespawnTime = 2, items = {}}
		function f.players:GetPlayers() return self.items end
		local function character()
			local c = {root = {Position = vector()}, humanoid = {Health = 100, FloorMaterial = "Ground"}}
			function c:FindFirstChild(name) return name == "HumanoidRootPart" and self.root or nil end
			function c:FindFirstChildOfClass(kind)
				if kind == "Humanoid" then return self.humanoid end
				if kind == "Tool" then return self.tool end
			end
			return c
		end
		f.profiles = {}
		function f:newPlayer(id)
			local p = {UserId = id, Parent = self.players, Character = character(), CharacterAdded = signal(),
				attributes = {DataReady = true, MovementAdmitted = true, ServerTeleportVersion = 0}, wallet = {XP = 150, Cash = 250, Inventory = {}}}
			function p:GetAttribute(name) return self.attributes[name] end
			function p:SetAttribute(name, value) self.attributes[name] = value end
			function p:Kick(message) self.kicked = message; self.Parent = nil; f.players.PlayerRemoving:Fire(self) end
			function p:LoadCharacterAsync()
				if f.respawnFailure then error("respawn unavailable") end
				self.respawns = (self.respawns or 0) + 1; self.Character = character(); self.CharacterAdded:Fire(self.Character)
			end
			local data = {XP = 150, Cash = 250, Inventory = {}, Tutorial = {Version = 1, Completed = false}}
			local profile = {Data = data, LastSavedData = copy(data), active = true}
			function profile:IsActive() return self.active end
			self.profiles[p] = profile
			table.insert(self.players.items, p); return p
		end
		f.player = f:newPlayer(7)
		f.rs = {attributes = {ServerReady = true}, GameActive = {Value = false}}
		function f.rs:GetAttribute(name) return self.attributes[name] end
		function f.rs:SetAttribute(name, value) self.attributes[name] = value end
		f.remote = {OnServerEvent = signal()}
		function f.remote:FireClient(p, snapshot) table.insert(f.sent, {Player = p, Snapshot = snapshot}) end
		f.task = {
			spawn = function(fn) table.insert(f.jobs, fn) end,
			delay = function(seconds, fn) table.insert(f.timers, {At = f.time + seconds, Fn = fn}) end,
			wait = function(seconds) f.time += seconds; if f.onWait then f.onWait() end end,
		}
		f.runtime, f.rewardModule, f.state = load("Runtime"), load("Rewards"), load("State")
		local catalog = {["Shadow Dagger"] = {Rarity = "Common", Image = "dagger"}, Bowie = {Rarity = "Common", Image = "bowie"}}
		f.rewardEngine = f.rewardModule.New({
			Profile = function(p) return f.profiles[p] end, Present = function(p) return p.Parent == f.players end,
			Knives = catalog, Now = function() return math.floor(f.time) end,
			Snapshot = function(p)
				if p:GetAttribute("TutorialRewardPublishing") then return end
				local data = f.profiles[p].Data; data.XP, data.Cash, data.Inventory = p.wallet.XP, p.wallet.Cash, copy(p.wallet.Inventory)
			end,
			Publish = function(p, data) p.wallet.XP, p.wallet.Cash, p.wallet.Inventory = data.XP, data.Cash, copy(data.Inventory) end,
			Save = function(_, profile, predicate)
				f.rewardSaves += 1; if f.failRewardSave then return false end
				profile.LastSavedData = copy(profile.Data); return predicate(profile.LastSavedData)
			end,
		})
		f.rewards = {Assess = f.rewardModule.Assess, ReadReceipt = f.rewardModule.ReadReceipt,
			Recover = f.rewardEngine.Recover, MarkEarned = function(...)
				f.earnCalls += 1; if f.onEarn then f.onEarn() end; return f.rewardEngine.MarkEarned(...)
			end}
		f.travel = {pending = {}, callback = nil}
		function f.travel:IsPending(p) return self.pending[p] == true end
		function f.travel:Cancel(p) self.pending[p] = nil end
		function f.travel:Destroy() self.destroyed = true; self.pending = {} end
		function f.travel:Start(p, placeId, travelOptions)
			if f.startFailure then return false end
			table.insert(f.travelCalls, {Player = p, PlaceId = placeId, Options = travelOptions})
			self.pending[p] = true; return true
		end
		function f:failTravel()
			local call = self.travelCalls[#self.travelCalls]; self.travel.pending[call.Player] = nil
			self.travel.callback(call.Player, "GameFull", {PlaceId = call.PlaceId, ServerInstanceId = call.Options.ServerInstanceId})
		end
		local tickets = {}
		function tickets:Claim()
			f.claimCalls += 1; if f.claimFailure then return nil, "Rejected" end
			if f.onClaim then f.onClaim() end
			return {Replay = options.Replay == true, ReturnJobId = options.ReturnJobId or "original-main-job"}
		end
		function tickets:Issue(p, replay)
			f.issueCalls += 1; f.issuedReplay = replay; if f.onIssue then f.onIssue(p) end
			if f.issueFailure then return nil end
			return {Token = "server-ticket", AccessCode = "server-secret"}
		end
		f.run = {Heartbeat = signal()}
		local analytics = {}
		for _, kind in ipairs({"Started", "Step", "Completed", "Skipped", "Remove"}) do
			analytics[kind] = function(_, ...) table.insert(f.analytics, {Kind = kind, Args = {...}}) end
		end
		local arenaClass = {}
		function arenaClass.New(p, session)
			if f.arenaFailure then error("missing map") end
			local a = {Lessons = {}, Session = session}
			function a:SetLesson(lesson)
				if f.lessonFailure then error("lesson floor missing") end
				if f.onLesson then f.onLesson(lesson) end
				self.Current = lesson; table.insert(self.Lessons, lesson)
			end
			function a:Place(c)
				if f.placeFailure then return false end
				if f.onPlace then f.onPlace(c) end
				c.root.Position = vector(); p:SetAttribute("ServerTeleportVersion", (p:GetAttribute("ServerTeleportVersion") or 0) + 1)
				if self.OnPlaced then self.OnPlaced(c) end; return true
			end
			function a:PrepareHealing() self.Healing = (self.Healing or 0) + 1; p.Character.humanoid.Health = 65 end
			function a:Tick()
				if f.tickFailure then error("map deleted") end
				self.Ticks = (self.Ticks or 0) + 1
			end
			function a:Destroy() self.Destroyed = true; if f.destroyFailure then error("already damaged arena") end end
			f.arenas[p] = a; return a
		end
		f.deps = {Players = f.players, RS = f.rs, Remote = f.remote, Profiles = {GetProfile = function(p) return f.profiles[p] end},
			Config = f.config, Steps = f.steps, State = f.state, Runtime = f.runtime, Rewards = f.rewards,
			Role = {IsTutorial = function() return options.Training == true end, IsPreview = function() return options.Preview == true end},
			Travel = {New = function(_, callback) f.travel.callback = callback; return f.travel end}, Tickets = {New = function() return tickets end},
			HttpService = {GenerateGUID = function() f.sequence = (f.sequence or 0) + 1; return "server-session-" .. f.sequence end},
			Arena = arenaClass, Food = {Grant = function() f.foodGrants = (f.foodGrants or 0) + 1 end},
			NewOptions = function()
				local o = {ServerInstanceId = "", ReservedServerAccessCode = ""}
				function o:SetTeleportData(data) self.Data = data end; return o
			end,
			RunService = f.run, NPCConfig = {ThinkSeconds = 0.3}, MovementConfig = {RunSpeed = 32, WalkSpeed = 16},
			Knives = catalog, Revolvers = {["Normal Revolver"] = {}}, Analytics = analytics, DataConfig = {UseMockProfiles = options.Mock == true}}
		function f:flush()
			local count = 0
			while #self.jobs > 0 do
				local jobs = self.jobs; self.jobs = {}; for _, fn in ipairs(jobs) do fn() end
				count += 1; assert(count < 100, "Unexpected runaway task queue")
			end
		end
		function f:step(seconds)
			self.time += seconds; self.run.Heartbeat:Fire(seconds)
			local due, remaining = {}, {}
			for _, timer in ipairs(self.timers) do table.insert(timer.At <= self.time and due or remaining, timer) end
			self.timers = remaining; for _, timer in ipairs(due) do timer.Fn() end; self:flush()
		end
		function f:last(p)
			for index = #self.sent, 1, -1 do if self.sent[index].Player == (p or self.player) then return self.sent[index].Snapshot end end
		end
		function f:handle(action, p) self.controller.Handle(p or self.player, action) end
		function f:action(kind, evidence) self.runtime.Record(self.player, kind, evidence or {}) end
		function f:session() return self.runtime.GetSession(self.player) end
		function f:finish()
			self:handle("Continue"); self:action("KnifeStab"); self:step(0.1); self:step(0.65); self:handle("Continue")
		end
		if options.Before then options.Before(f) end
		local Coordinator = load("Coordinator", {task = f.task, os = {clock = function() return f.time end},
			workspace = {GetServerTimeNow = function() return f.time + 1000 end}, Vector3 = {new = vector}, Enum = {Material = {Air = "Air"}},
			warn = function(message) table.insert(f.warnings, message) end})
		f.controller = Coordinator.New(f.deps)
		return f
	end

	test("lobby offer stays optional and dismiss records no tutorial completion", function()
		local f = fixture(); f:flush(); assert(f:last().Mode == "Offer")
		f:handle("Dismiss"); f:handle("Status"); assert(f:last().Mode == "Hidden")
		assert(f.rewardModule.Assess(f.profiles[f.player]) == "Eligible" and f.earnCalls == 0 and #f.travelCalls == 0)
	end)
	test("legacy tutorial users keep an explicit training entry without another automatic offer", function()
		local f = fixture({Before = function(value) value.profiles[value.player].Data.FirstTimePlaying = true end}); f:flush()
		assert(f:last().Mode == "Hidden" and f.earnCalls == 0)
		f:handle("Replay"); assert(f:last().Mode == "Offer" and f:last().Replay == false)
		f:handle("Start"); assert(f.issueCalls == 1 and f.issuedReplay == false)
	end)
	test("client Continue Return and arbitrary packets cannot earn a lobby reward", function()
		local f = fixture(); f:flush()
		for _, action in ipairs({"Continue", "Return", "Complete", "GrantReward", "Claim", "XP"}) do f:handle(action) end
		f:handle({Completed = true, XP = 99999}); f:handle(string.rep("x", 100))
		assert(f.earnCalls == 0 and f.rewardSaves == 0 and f.player.wallet.XP == 150)
	end)
	test("duplicate Start during ticket creation launches one reserved destination", function()
		local f = fixture(); f:flush(); f.onIssue = function() f:handle("Start") end
		f:handle("Start"); assert(f.issueCalls == 1 and #f.travelCalls == 1)
		assert(f.travelCalls[1].PlaceId == 22 and f.travelCalls[1].Options.ReservedServerAccessCode == "server-secret")
		assert(f.travelCalls[1].Options.Data.TutorialToken == "server-ticket" and f.travelCalls[1].Options.Data.XP == nil)
		f:handle("Start"); assert(f.issueCalls == 1)
	end)
	test("unconfigured busy match and locked inventory profiles cannot start travel", function()
		for _, mode in ipairs({"unconfigured", "match", "inventory", "publishing", "profile", "server"}) do
			local f = fixture(); f:flush()
			if mode == "unconfigured" then f.config.TutorialPlaceId = 0
			elseif mode == "match" then f.player:SetAttribute("InRound", true)
			elseif mode == "inventory" then f.player:SetAttribute("InventoryLocked", true)
			elseif mode == "publishing" then f.player:SetAttribute("TutorialRewardPublishing", true)
			elseif mode == "profile" then f.profiles[f.player].active = false
			else f.rs:SetAttribute("ServerReady", false) end
			f:handle("Start"); assert(f.issueCalls == 0 and #f.travelCalls == 0)
		end
	end)
	test("departure match start profile replacement and inventory locks during Issue cancel travel", function()
		for _, mode in ipairs({"leave", "match", "profile", "inventory", "publishing"}) do
			local f = fixture(); f:flush(); f.onIssue = function()
				if mode == "leave" then f.player.Parent = nil
				elseif mode == "match" then f.player:SetAttribute("InRound", true)
				elseif mode == "inventory" then f.player:SetAttribute("InventoryLocked", true)
				elseif mode == "publishing" then f.player:SetAttribute("TutorialRewardPublishing", true)
				else f.profiles[f.player] = {IsActive = function() return true end} end
			end
			f:handle("Start"); assert(f.issueCalls == 1 and #f.travelCalls == 0)
		end
	end)
	test("failed preparation releases travel flag and cooldown limits retry cost", function()
		local f = fixture(); f:flush(); f.issueFailure = true; f:handle("Start")
		assert(f.player:GetAttribute("TutorialTravelPending") == false and f:last().Mode == "Error")
		f:handle("Start"); assert(f.issueCalls == 1); f:step(10); f.issueFailure = false; f:handle("Start")
		assert(f.issueCalls == 2 and #f.travelCalls == 1)
	end)
	test("replay reuses completed entitlement without exposing a second reward", function()
		local f = fixture({Before = function(value)
			assert(value.rewardEngine.MarkEarned(value.player, value.profiles[value.player], "earlier-server-session", value.config))
			assert(value.rewardEngine.Recover(value.player, value.profiles[value.player], value.config))
		end}); f:flush(); f:handle("Replay"); assert(f:last().Mode == "Offer" and f:last().Replay)
		f:handle("Start"); assert(f.issuedReplay == true and f.player.wallet.XP == 650)
	end)
	test("invalid private admission returns to main before spawning or awarding", function()
		local f = fixture({Training = true, Before = function(value) value.claimFailure = true end}); f:flush()
		assert(f.claimCalls == 1 and f:session() == nil and #f.travelCalls == 1 and f.travelCalls[1].PlaceId == 11)
		assert(f.earnCalls == 0 and f.foodGrants == nil)
	end)
	test("a second player is rejected before claiming the private tutorial", function()
		local f = fixture({Training = true, Before = function(value) value.other = value:newPlayer(8) end}); f:flush()
		assert(f.claimCalls == 1 and f:session() and f.other.kicked and f.runtime.GetSession(f.other) == nil and f.players.CharacterAutoLoads == false)
	end)
	test("profile readiness wait and timeout never start an incomplete tutorial", function()
		local f = fixture({Training = true, Before = function(value)
			value.player:SetAttribute("DataReady", false); value.onWait = function() if value.time >= 100.2 then value.player:SetAttribute("DataReady", true) end end
		end}); f:flush(); assert(f:session() and f.claimCalls == 1)
		local failed = fixture({Training = true, Before = function(value) value.player:SetAttribute("DataReady", false) end}); failed:flush()
		assert(failed:session() == nil and failed:last().Mode == "Error" and failed.earnCalls == 0)
		failed:handle("Return"); assert(#failed.travelCalls == 1)
	end)
	test("gameplay objectives advance automatically only after server evidence", function()
		local f = fixture({Training = true}); f:flush(); f:handle("Continue")
		assert(f:session().Progress.Index == 2); f:handle("Continue"); assert(f:session().Progress.Index == 2)
		f:action("Revolver"); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f:action("KnifeStab"); f:step(0.1); assert(f:session().Progress.Index == 2 and f:last().AutoAdvance)
		f:step(0.65); assert(f:session().Progress.Index == 3 and f.earnCalls == 0)
	end)
	test("yielded startup placement and lesson setup cannot accept progress before analytics starts", function()
		local blocked = 0
		local f = fixture({Training = true, Steps = {{Id = "knife", Kind = "EquipKnife", Goal = 1, MinSeconds = 0}, {Id = "end", Kind = "Read", Goal = 1, MinSeconds = 0}},
			Before = function(value)
				local function interleave()
					local s = value:session(); assert(s.Preparing and value.runtime.IsActive(value.player))
					value.player.Character.tool = {Name = "Bowie"}
					value:action("EquipKnife"); s.OnAction("EquipKnife", {})
					value.time += 0.1; value.run.Heartbeat:Fire(0.1); value:handle("Continue")
					assert(s.Progress.Index == 1 and s.Progress.Progress == 0 and #value.analytics == 0); blocked += 1
				end
				value.onPlace, value.onLesson = interleave, interleave
			end})
		f:flush(); assert(blocked == 2 and not f:session().Preparing and f.analytics[1].Kind == "Started")
		f.onPlace, f.onLesson = nil, nil; f:step(0.1); f:step(0.65)
		assert(f:session().Progress.Index == 2 and f.analytics[2].Kind == "Step")
	end)
	test("yielded next-lesson preparation blocks target kills and resets progress sampling", function()
		local f = fixture({Training = true}); f:flush(); local blocked = false
		f.onLesson = function(lesson)
			if lesson.Kind ~= "KnifeStab" then return end
			local s = f:session(); local hum = {Health = 100, TakeDamage = function(self, amount) self.Health -= amount end}
			local model = {Parent = {}, FindFirstChildOfClass = function(_, kind) return kind == "Humanoid" and hum or nil end}
			assert(s.Preparing and f.runtime.IsActive(f.player)); f.runtime.RegisterTarget(f.player, model)
			assert(f.runtime.Damage(f.player, model, 100, "KnifeStab") == 0 and hum.Health == 100)
			f:action("KnifeStab", model); f.time += 0.1; f.run.Heartbeat:Fire(0.1); f:handle("Continue")
			assert(s.Progress.Index == 2 and s.Progress.Progress == 0 and not s.Advancing); blocked = true
		end
		f:handle("Continue"); assert(blocked and not f:session().Preparing and f:session().Progress.Progress == 0)
		f.onLesson = nil; f:action("KnifeStab"); f:step(0.1); f:step(0.65); assert(f:session().Progress.Index == 3)
	end)
	test("asynchronous initial character placement finishes before startup progress becomes active", function()
		local f = fixture({Training = true, Before = function(value)
			value.player.Character = nil
			value.onLesson = function() assert(value:session().Preparing and #value.analytics == 0) end
		end}); f:flush()
		assert(f.player.respawns == 1 and f:session().CharacterPlaced == f.player.Character and not f:session().Preparing)
		assert(#f.analytics == 1 and f.analytics[1].Kind == "Started")
	end)
	test("yielded preparation timeout stops startup and late work cannot reopen the lesson", function()
		for _, kind in ipairs({"placement", "lesson"}) do
			local f = fixture({Training = true, Before = function(value)
				value.config.PreparationTimeoutSeconds = 1
				local function timeout()
					value.time += 1; value.run.Heartbeat:Fire(0.1)
					assert(value:session().Failed and not value:session().Preparing and value:last().RetryAction == "Return")
				end
				if kind == "placement" then value.onPlace = timeout else value.onLesson = timeout end
			end}); f:flush()
			assert(f:last().Mode == "Error" and not f.runtime.IsActive(f.player) and f.player:GetAttribute("InRound") == false)
			assert(#f.analytics == 0 and f.earnCalls == 0 and f.arenas[f.player].Destroyed)
			f:step(5); assert(#f.warnings == 1); f:handle("Return"); assert(#f.travelCalls == 1)
		end
	end)
	test("saved training completion returns then main join grants once", function()
		local f = fixture({Training = true}); f:flush(); f:finish()
		assert(f:session().Saved and f.earnCalls == 1 and f.rewardModule.Assess(f.profiles[f.player]) == "Earned")
		assert(f.player.wallet.XP == 150 and f:last().Mode == "Complete" and #f.travelCalls == 0)
		f:step(8); assert(#f.travelCalls == 1 and f.travelCalls[1].PlaceId == 11)
		local main = fixture({Before = function(value)
			value.profiles[value.player].Data = copy(f.profiles[f.player].LastSavedData)
			value.profiles[value.player].LastSavedData = copy(value.profiles[value.player].Data)
		end}); main:flush()
		assert(main.player.wallet.XP == 650 and main.player.wallet.Cash == 750 and #main.player.wallet.Inventory == 1)
		assert(main:last().Mode == "Complete" and main:last().RewardGranted); main:handle("Status")
		assert(main.player.wallet.XP == 650 and main.rewardSaves == 1 and main:last().Mode == "Complete")
		assert(main.player:GetAttribute("TutorialTravelPending") == true)
		main:handle("Dismiss"); assert(main:last().Mode == "Hidden" and main.player:GetAttribute("TutorialTravelPending") == false)
	end)
	test("completion save timeout offers safe Continue retry and blocks return while saving", function()
		local f = fixture({Training = true}); f:flush(); f.failRewardSave = true
		f.onEarn = function() f:handle("Continue"); f:handle("Return") end
		f:finish(); assert(f:last().Mode == "Error" and f:last().RetryAction == "Continue" and #f.travelCalls == 0)
		assert(f.earnCalls == 1 and f:session().Progress.Completed and not f:session().Saved)
		f.failRewardSave, f.onEarn = false, nil; f:handle("Continue")
		assert(f:session().Saved and f.earnCalls == 2 and f.player.wallet.XP == 150)
	end)
	test("Return after completion save failure retries durability before scheduling a teleport", function()
		local f = fixture({Training = true}); f:flush(); f.failRewardSave = true; f:finish()
		assert(not f:session().Saved and f.earnCalls == 1)
		f:handle("Return"); assert(not f:session().Saved and f.earnCalls == 2 and #f.travelCalls == 0)
		f.failRewardSave = false; f:handle("Return"); assert(f:session().Saved and f.earnCalls == 3 and #f.travelCalls == 0)
		f:step(8); assert(#f.travelCalls == 1 and f.profiles[f.player].LastSavedData.Tutorial.PendingReward)
	end)
	test("main reward outage retries the marker without a second economy delta", function()
		local f = fixture({Before = function(value)
			assert(value.rewardEngine.MarkEarned(value.player, value.profiles[value.player], "earned-server-session", value.config)); value.failRewardSave = true
		end}); f:flush(); assert(f:last().Mode == "Error" and f.player.wallet.XP == 650)
		f:handle("Status"); assert(f.player.wallet.XP == 650)
		f.failRewardSave = false; f:handle("Status")
		assert(f:last().RewardGranted and f.player.wallet.XP == 650 and #f.player.wallet.Inventory == 1)
	end)
	test("return route falls back once from departed original main server", function()
		local f = fixture({Training = true}); f:flush(); f:handle("Return")
		assert(f.travelCalls[1].Options.ServerInstanceId == "original-main-job"); f:failTravel()
		assert(#f.travelCalls == 2 and f.travelCalls[2].Options.ServerInstanceId == "")
		f:failTravel(); assert(#f.travelCalls == 2 and f:last().Mode == "Error" and f.player:GetAttribute("TutorialTravelPending") == false)
		assert(f.earnCalls == 0)
	end)
	test("movement progress excludes implausible warps rejected motion and spawn teleports", function()
		local f = fixture({Training = true, Steps = {{Id = "move", Kind = "Move", Goal = 24, MinSeconds = 0}, {Id = "end", Kind = "Read", Goal = 1, MinSeconds = 0}}}); f:flush(); f:step(0.1)
		f.player.Character.root.Position = vector(1000); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f.player:SetAttribute("MovementAdmitted", false); f.player.Character.root.Position = vector(1003); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f.player:SetAttribute("MovementAdmitted", true); f:step(0.1)
		f.player:SetAttribute("ServerTeleportVersion", 2); f.player.Character.root.Position = vector(2000); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f.player.Character.root.Position = vector(2003); f:step(0.1); assert(f:session().Progress.Progress == 3)
	end)
	test("sprint requires enough grounded movement and equip checks actual server tools", function()
		local f = fixture({Training = true, Steps = {{Id = "sprint", Kind = "Sprint", Goal = 20, MinSeconds = 0}}}); f:flush(); f:step(0.1)
		f.player.Character.root.Position = vector(1); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f.player.Character.humanoid.FloorMaterial = "Air"; f.player.Character.root.Position = vector(3); f:step(0.1); assert(f:session().Progress.Progress == 0)
		f.player.Character.humanoid.FloorMaterial = "Ground"; f.player.Character.root.Position = vector(5); f:step(0.1); assert(f:session().Progress.Progress == 2)
		local equip = fixture({Training = true, Steps = {{Id = "knife", Kind = "EquipKnife", Goal = 1, MinSeconds = 0}, {Id = "end", Kind = "Read", Goal = 1, MinSeconds = 0}}}); equip:flush()
		equip.player.Character.tool = {Name = "NotOwned"}; equip:step(0.1); assert(equip:session().Progress.Progress == 0)
		equip.player.Character.tool = {Name = "Bowie"}; equip:step(0.1); equip:step(0.65); assert(equip:session().Progress.Index == 2)
	end)
	test("respawn preserves objective progress and prepares healing again", function()
		local f = fixture({Training = true, Steps = {{Id = "heal", Kind = "Heal", Goal = 2, MinSeconds = 0}}}); f:flush()
		f:action("Heal"); assert(f:session().Progress.Progress == 1)
		local before = f.arenas[f.player].Healing or 0; assert(f.runtime.OnDeath(f.player, f.player.Character)); f:step(2)
		assert(f.player.respawns == 1 and f:session().Progress.Progress == 1 and f.arenas[f.player].Healing > before)
		assert(f.player.Character.humanoid.Health == 65 and f.foodGrants >= 2)
	end)
	test("session expiry and player cleanup cancel auto advances and reward work", function()
		local f = fixture({Training = true}); f:flush(); f.config.SessionTimeoutSeconds = 1; f:step(2)
		assert(not f:session().Active and f:last().Mode == "Error"); f:handle("Continue"); assert(f.earnCalls == 0)
		local other = fixture({Training = true}); other:flush(); other:handle("Continue"); other:action("KnifeStab"); other:step(0.1)
		local arena = other.arenas[other.player]; other.player.Parent = nil; other.players.PlayerRemoving:Fire(other.player); other:step(1)
		assert(other:session() == nil and arena.Destroyed and other.earnCalls == 0)
	end)
	test("Studio rehearsal requires isolated mock data and never records reward entitlement", function()
		local denied = fixture({Training = true, Preview = true}); denied:flush(); assert(denied:session() == nil and denied:last().Mode == "Error")
		local f = fixture({Training = true, Preview = true, Mock = true}); f:flush(); f:finish(); f:step(10)
		assert(f:session().Saved and f.earnCalls == 0 and f.rewardSaves == 0 and #f.travelCalls == 0)
	end)
	test("startup arena and spawn failures disable combat and leave an actionable return route", function()
		for _, mode in ipairs({"arena", "lesson", "spawn"}) do
			local f = fixture({Training = true, Before = function(value)
				if mode == "arena" then value.arenaFailure = true
				elseif mode == "lesson" then value.lessonFailure = true
				else value.placeFailure = true end
			end}); f:flush()
			assert(f:session().Failed and not f.runtime.IsActive(f.player) and #f:session().Connections == 0)
			assert(f.player:GetAttribute("TutorialActive") == false and f.player:GetAttribute("InRound") == false)
			assert(f:last().Mode == "Error" and f:last().RetryAction == "Return" and f.earnCalls == 0)
			f:step(5); assert(#f.warnings == 1); f:handle("Return"); assert(#f.travelCalls == 1)
		end
	end)
	test("heartbeat arena faults stop once cancel queued advancement and remove registered targets", function()
		local f = fixture({Training = true}); f:flush(); f:handle("Continue"); f:action("KnifeStab"); f:step(0.1)
		local model = {Parent = {}, FindFirstChildOfClass = function() return {Health = 100} end}
		f.runtime.RegisterTarget(f.player, model); local arena = f.arenas[f.player]
		f.tickFailure, f.destroyFailure = true, true; f:step(0.3)
		assert(f:session().Failed and arena.Destroyed and not f.runtime.IsActive(f.player) and #f.runtime.GetTargets(f.player) == 0)
		assert(f.player.CharacterAdded.listeners[1].active == false and f:last().Mode == "Error")
		f:step(5); f:handle("Continue"); assert(#f.warnings == 1 and f.earnCalls == 0)
		f:handle("Return"); assert(#f.travelCalls == 1)
	end)
	test("delayed NPC respawn failure reaches the session error handler", function()
		local f = fixture({Training = true}); f:flush(); local arena = f.arenas[f.player]
		arena.OnFailure("NPC rig missing after respawn")
		assert(f:session().Failed and arena.Destroyed and f:last().Mode == "Error")
		arena.OnFailure("same fault"); assert(#f.warnings == 1); f:handle("Return"); assert(#f.travelCalls == 1)
	end)
	test("lesson preparation failure after progress never manufactures completion", function()
		local f = fixture({Training = true}); f:flush(); f:handle("Continue"); f:action("KnifeStab"); f:step(0.1)
		f.lessonFailure = true; f:step(0.65)
		assert(f:session().Failed and f:session().Progress.Index == 3 and not f:session().Progress.Completed)
		f:handle("Continue"); assert(f.earnCalls == 0 and f.rewardModule.Assess(f.profiles[f.player]) == "Eligible")
	end)
	test("completion arena cleanup faults preserve verified entitlement and save retries", function()
		local f = fixture({Training = true}); f:flush(); f:handle("Continue"); f:action("KnifeStab"); f:step(0.1); f:step(0.65)
		f.lessonFailure, f.failRewardSave = true, true; f:handle("Continue")
		assert(f:session().Failed and f:session().Progress.Completed and not f:session().Saving and not f:session().Saved)
		assert(f.rewardModule.Assess(f.profiles[f.player]) == "Earned" and f:last().RetryAction == "Continue")
		f.failRewardSave = false; f:handle("Continue"); assert(f:session().Saved and f.earnCalls == 2)
		f:step(8); assert(#f.travelCalls == 1)
	end)
	test("respawn service failure stops the session instead of a repeated death loop", function()
		local f = fixture({Training = true}); f:flush(); f.respawnFailure = true
		assert(f.runtime.OnDeath(f.player, f.player.Character)); f:step(2)
		assert(f:session().Failed and f:last().Mode == "Error" and not f.runtime.OnDeath(f.player, f.player.Character))
		f:step(4); assert(#f.warnings == 1)
	end)
	test("request bucket throttles repeated lobby starts and Destroy removes listeners", function()
		local f = fixture(); f:flush(); f.config.RequestBurst, f.config.RequestsPerSecond = 2, 1
		f:handle("Status"); f:handle("Status"); f:handle("Start"); assert(f.issueCalls == 0)
		f:step(1); f:handle("Start"); assert(f.issueCalls == 1)
		f.controller.Destroy(); f.controller.Destroy(); f.remote.OnServerEvent:Fire(f.player, "Start")
		assert(f.travel.destroyed and f.issueCalls == 1)
	end)
	print("Tutorial coordinator: " .. passed .. " session/security tests passed")
end
