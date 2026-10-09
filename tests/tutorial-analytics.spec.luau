return function(load)
	local Analytics = load("TutorialAnalytics")
	local passed = 0
	local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
	local function test(name, fn)
		local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err))
		passed += 1; print("PASS " .. name)
	end
	local function fixture()
		local f = {calls = {}, jobs = {}}
		f.players = {PlayerRemoving = {}}
		local listeners = {}
		function f.players.PlayerRemoving:Connect(fn)
			local listener = {Connected = true, fn = fn}
			function listener:Disconnect() self.Connected = false end
			table.insert(listeners, listener); return listener
		end
		function f.players.PlayerRemoving:Fire(player)
			for _, listener in ipairs(listeners) do if listener.Connected then listener.fn(player) end end
		end
		f.player = {Parent = f.players, UserId = 7}
		f.config = {Version = 1, Analytics = {Enabled = true, FunnelName = "Tutorial_v1"}}
		f.steps = {{Id = "move", Title = "Move around"}, {Id = "stab", Title = "Stab a bandit"}}
		f.service = {}
		for _, kind in ipairs({"LogOnboardingFunnelStepEvent", "LogFunnelStepEvent", "LogCustomEvent"}) do
			f.service[kind] = function(_, ...)
				if f.fail then error("analytics unavailable") end
				table.insert(f.calls, {kind = kind, args = table.pack(...)})
			end
		end
		f.deps = {Players = f.players, AnalyticsService = f.service, Steps = f.steps,
			IsStudio = function() return f.studio == true end,
			Spawn = function(fn) table.insert(f.jobs, fn) end}
		f.analytics = Analytics.New(f.config, f.deps)
		function f:flush() local jobs = self.jobs; self.jobs = {}; for _, fn in ipairs(jobs) do fn() end end
		function f:complete(id, replay)
			assert(self.analytics:Started(self.player, id, replay))
			assert(self.analytics:Step(self.player, id, 1, "move", replay))
			assert(self.analytics:Step(self.player, id, 2, "Stab a bandit", replay))
			assert(self.analytics:Completed(self.player, id, replay))
			self:flush()
		end
		return f
	end
	test("new tutorial logs contiguous validated onboarding steps", function()
		local f = fixture(); f:complete("server-session", false)
		equal(#f.calls, 4)
		for index, call in ipairs(f.calls) do
			equal(call.kind, "LogOnboardingFunnelStepEvent"); equal(call.args[1], f.player); equal(call.args[2], index)
			equal(call.args[4].CustomField01, "Version - 1"); equal(call.args[4].CustomField02, "Mode - Onboarding")
		end
		equal(f.calls[4].args[3], "Completed")
	end)
	test("replay uses recurring funnel with server session and never onboarding", function()
		local f = fixture(); f:complete("server-replay", true)
		for index, call in ipairs(f.calls) do
			equal(call.kind, "LogFunnelStepEvent"); equal(call.args[2], "Tutorial_v1_Replay")
			equal(call.args[3], "server-replay"); equal(call.args[4], index); equal(call.args[6].CustomField02, "Mode - Replay")
		end
	end)
	test("analytics rejects out-of-order duplicate malformed and foreign progress", function()
		local f = fixture(); assert(f.analytics:Started(f.player, "server-session", false))
		equal(f.analytics:Started(f.player, "server-session", false), false)
		equal(f.analytics:Started(f.player, "replacement-session", false), false)
		equal(f.analytics:Step(f.player, "server-session", 2, "stab", false), false)
		equal(f.analytics:Step(f.player, "wrong-session", 1, "move", false), false)
		equal(f.analytics:Step(f.player, "server-session", 1, "move", true), false)
		equal(f.analytics:Step(f.player, "server-session", 1, "injected-name", false), false)
		equal(f.analytics:Step(f.player, "server-session", 0/0, "move", false), false)
		equal(f.analytics:Completed(f.player, "server-session", false), false)
		assert(f.analytics:Step(f.player, "server-session", 1, "move", false))
		equal(f.analytics:Step(f.player, "server-session", 1, "move", false), false)
		f:flush(); equal(#f.calls, 2)
	end)
	test("skip logs custom outcome without implicitly completing earlier funnel steps", function()
		local f = fixture(); assert(f.analytics:Started(f.player, "server-session", false))
		assert(f.analytics:Step(f.player, "server-session", 1, "move", false))
		assert(f.analytics:Skipped(f.player, "server-session", false))
		equal(f.analytics:Completed(f.player, "server-session", false), false)
		equal(f.analytics:Skipped(f.player, "server-session", false), false)
		f:flush(); equal(#f.calls, 3); equal(f.calls[3].kind, "LogCustomEvent")
		equal(f.calls[3].args[2], "TutorialSkipped"); equal(f.calls[3].args[4].CustomField03, "Last lesson - 1")
	end)
	test("declined invitation has no started or completed onboarding steps", function()
		local f = fixture(); assert(f.analytics:Skipped(f.player)); f:flush()
		equal(#f.calls, 1); equal(f.calls[1].kind, "LogCustomEvent")
		equal(f.calls[1].args[4].CustomField03, "Last lesson - 0")
		assert(f.analytics:Started(f.player, "later-server-session", false)); f:flush(); equal(#f.calls, 2)
	end)
	test("analytics delivery failures never throw or gate lesson advancement", function()
		local f = fixture(); f.fail = true; f:complete("server-session", false)
		equal(#f.calls, 0); equal(f.analytics.Sessions[f.player].LastIndex, 2)
		equal(f.analytics.Sessions[f.player].Terminal, true)
	end)
	test("disabled and Studio analytics never send platform events", function()
		local f = fixture(); f.studio = true
		equal(f.analytics:Started(f.player, "server-session", false), false); f:flush(); equal(#f.calls, 0)
		local disabled = Analytics.New({Version = 1, Analytics = {Enabled = false}}, {})
		equal(disabled:Started(f.player, "server-session", false), false)
	end)
	test("terminal dedupe cleanup departure and destruction cancel queued logging", function()
		local f = fixture(); f:complete("server-session", false)
		equal(f.analytics:Completed(f.player, "server-session", false), false)
		equal(f.analytics:Started(f.player, "server-session", false), false)
		f.analytics:Remove(f.player); equal(f.analytics.Sessions[f.player], nil)
		assert(f.analytics:Started(f.player, "another-session", false))
		f.player.Parent = nil; f.players.PlayerRemoving:Fire(f.player); f:flush()
		equal(f.analytics.Sessions[f.player], nil); equal(#f.calls, 4)
		f.player.Parent = f.players; assert(f.analytics:Started(f.player, "last-session", false))
		f.analytics:Destroy(); f.analytics:Destroy(); f:flush(); equal(#f.calls, 4)
	end)
	print("Tutorial analytics: " .. passed .. " tests passed")
	return passed
end
