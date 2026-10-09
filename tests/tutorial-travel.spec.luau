-- Execute the actual travel modules with deterministic network/storage clocks.
return function(load)
	local Tickets = load("TutorialTickets")
	local Travel = load("TutorialTeleport")
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn)
		assert(ok, name .. ": " .. tostring(err))
		passed += 1
		print("PASS " .. name)
	end
	local function equal(a, b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
	local function signal()
		local result = {listeners = {}}
		function result:Connect(fn)
			local listener = {Connected = true, fn = fn}
			function listener:Disconnect() self.Connected = false end
			table.insert(self.listeners, listener)
			return listener
		end
		function result:Fire(...)
			for _, listener in ipairs(table.clone(self.listeners)) do if listener.Connected then listener.fn(...) end end
		end
		return result
	end
	local function options(data, code, job)
		local result = {data = data, ReservedServerAccessCode = code or "", ServerInstanceId = job or "", ShouldReserveServer = false}
		function result:GetTeleportData() return self.data end
		function result:SetTeleportData(value) self.data = value end
		return result
	end
	local function fixture()
		local f = {time = 1000, clock = 0, sequence = 0, records = {}, jobs = {}, timers = {}, calls = {}, failures = {}}
		f.config = {Version = 1, MainPlaceId = 11, TutorialPlaceId = 22, TicketTTLSeconds = 600,
			TicketStoreName = "TutorialTest", Teleport = {MaxAttempts = 4, RetryDelaySeconds = 2, FloodDelaySeconds = 15, WatchdogSeconds = 45}}
		f.game = {PlaceId = 11, GameId = 111, JobId = "main-job", PrivateServerId = "", PrivateServerOwnerId = 0}
		f.players = {PlayerRemoving = signal()}
		f.player = {UserId = 7, Parent = f.players}
		function f.player:GetJoinData() return self.joinData end
		f.http = {GenerateGUID = function() f.sequence += 1; return "12345678-1234-1234-1234-" .. string.format("%012d", f.sequence) end}
		f.store = {}
		function f.store:SetAsync(key, value, ttl)
			if f.storeFailure then error("network failure") end
			f.records[key] = table.clone(value); f.savedTTL = ttl
			if f.afterStore then f.afterStore() end
		end
		function f.store:UpdateAsync(key, callback, ttl)
			if f.storeFailure then error("network failure") end
			local result = callback(f.records[key])
			if f.contend then
				-- Model another destination winning the compare-and-swap after
				-- the first transform, forcing the production transform to rerun.
				f.records[key] = table.clone(f.records[key]); f.records[key].ClaimedJobId = "other-job"
				result = callback(f.records[key])
			end
			if result then f.records[key] = result; f.updatedTTL = ttl end
			return result
		end
		f.teleport = {TeleportInitFailed = signal()}
		function f.teleport:ReserveServerAsync(placeId)
			equal(placeId, 22)
			if f.reserveFailure then error("network failure") end
			if f.afterReserve then f.afterReserve() end
			return "server-secret-code", "tutorial-private-id"
		end
		function f.teleport:TeleportAsync(placeId, players, travelOptions)
			table.insert(f.calls, {placeId = placeId, player = players[1], options = travelOptions})
			if f.onCall then f.onCall(placeId, players[1], travelOptions) end
			if f.requestFailure then error("network failure") end
		end
		f.deps = {Game = f.game, Players = f.players, HttpService = f.http, Store = f.store,
			TeleportService = f.teleport, Now = function() return f.time end,
			NewOptions = function() return options() end, Spawn = function(fn) table.insert(f.jobs, fn) end,
			Delay = function(delay, fn) table.insert(f.timers, {at = f.clock + delay, fn = fn}) end,
			Warn = function() f.warnings = (f.warnings or 0) + 1 end}
		f.tickets = Tickets.New(f.config, f.deps)
		f.travel = Travel.New(f.config, function(player, reason, operation)
			table.insert(f.failures, {player = player, reason = reason, attempts = operation.Attempts})
		end, f.deps)
		function f:flush()
			local jobs = self.jobs; self.jobs = {}
			for _, fn in ipairs(jobs) do fn() end
		end
		function f:step(seconds)
			self.clock += seconds
			local due, remaining = {}, {}
			for _, timer in ipairs(self.timers) do table.insert(timer.at <= self.clock and due or remaining, timer) end
			self.timers = remaining
			for _, timer in ipairs(due) do timer.fn() end
			self:flush()
		end
		function f:arrive(ticket)
			self.game.PlaceId, self.game.JobId = 22, "tutorial-job"
			self.game.PrivateServerId = ticket.PrivateServerId
			self.player.joinData = {SourceGameId = 111, SourcePlaceId = 11,
				TeleportData = {TutorialToken = ticket.Token, TutorialVersion = 1}}
		end
		function f:fail(name, call)
			call = call or self.calls[#self.calls]
			self.teleport.TeleportInitFailed:Fire(self.player, name, "network reason", call.placeId, call.options)
		end
		return f
	end

	test("ticket keeps reservation secret in server API and return route in store", function()
		local f = fixture(); local ticket = assert(f.tickets:Issue(f.player, true))
		equal(ticket.AccessCode, "server-secret-code"); equal(ticket.Replay, true)
		equal(f.records[ticket.Token].AccessCode, nil); equal(f.records[ticket.Token].ReturnJobId, "main-job")
		equal(f.records[ticket.Token].ExpiresAt, 1600); equal(f.savedTTL, 600)
	end)
	test("private source returns through main-place matchmaking", function()
		local f = fixture(); f.game.PrivateServerId = "source-private-id"
		equal(assert(f.tickets:Issue(f.player)).ReturnJobId, "")
	end)
	test("ticket issuance fails safely on bad setup network failure and departure", function()
		for _, mode in ipairs({"setup", "reserve", "store", "leave-reserve", "leave-store"}) do
			local f = fixture()
			if mode == "setup" then f.config.TutorialPlaceId = 0
			elseif mode == "reserve" then f.reserveFailure = true
			elseif mode == "store" then f.storeFailure = true
			elseif mode == "leave-reserve" then f.afterReserve = function() f.player.Parent = nil end
			else f.afterStore = function() f.player.Parent = nil end end
			equal(f.tickets:Issue(f.player), nil)
		end
	end)
	test("valid ticket claim is strictly single-use even in same destination job", function()
		local f = fixture(); local ticket = assert(f.tickets:Issue(f.player)); f:arrive(ticket)
		local claimed = assert(f.tickets:Claim(f.player)); equal(claimed.ClaimedJobId, "tutorial-job")
		equal(claimed.Replay, false); equal(f.tickets:Claim(f.player), nil)
		f.game.JobId = "another-tutorial-job"; equal(f.tickets:Claim(f.player), nil)
	end)
	test("ticket rejects forged source user reservation version expiry and public access", function()
		for _, mode in ipairs({"source-place", "source-universe", "borrowed", "reservation", "version", "expired", "public", "owner", "direct", "unknown"}) do
			local f = fixture(); local ticket = assert(f.tickets:Issue(f.player)); f:arrive(ticket)
			if mode == "source-place" then f.player.joinData.SourcePlaceId = 33
			elseif mode == "source-universe" then f.player.joinData.SourceGameId = 222
			elseif mode == "borrowed" then f.player.UserId = 8
			elseif mode == "reservation" then f.game.PrivateServerId = "another-reservation"
			elseif mode == "version" then f.records[ticket.Token].Version = 0
			elseif mode == "expired" then f.time = 1600
			elseif mode == "public" then f.game.PrivateServerId = ""
			elseif mode == "owner" then f.game.PrivateServerOwnerId = 7
			elseif mode == "direct" then f.player.joinData = {}
			else f.player.joinData.TeleportData.TutorialToken = "12345678-1234-1234-1234-000000009999" end
			equal(f.tickets:Claim(f.player), nil)
		end
	end)
	test("atomic claim loses cleanly to concurrent destination and storage outage", function()
		for _, contend in ipairs({true, false}) do
			local f = fixture(); local ticket = assert(f.tickets:Issue(f.player)); f:arrive(ticket)
			f.contend, f.storeFailure = contend, not contend
			equal(f.tickets:Claim(f.player), nil)
		end
	end)
	test("travel claims busy state before async worker and requires configured reservation", function()
		local f = fixture(); local original = options({TutorialToken = "ticket"}, "access")
		equal(f.travel:Start(f.player, 33, original), false)
		equal(f.travel:Start(f.player, 22, options()), false)
		equal(f.travel:Start(f.player, 22, original), true); equal(#f.calls, 0)
		equal(f.travel:IsPending(f.player), true); equal(f.travel:Start(f.player, 22, original), false)
		f:flush(); equal(#f.calls, 1); equal(original.data.TutorialTravelNonce, nil)
	end)
	test("request failures retry at most four times and release busy once", function()
		local f = fixture(); f.requestFailure = true
		assert(f.travel:Start(f.player, 22, options({TutorialToken = "ticket"}, "access"))); f:flush()
		for _ = 1, 3 do f:step(2) end
		equal(#f.calls, 4); equal(#f.failures, 1); equal(f.failures[1].attempts, 4)
		equal(f.travel:IsPending(f.player), false); f:step(60); equal(#f.failures, 1)
		for _, call in ipairs(f.calls) do equal(call.options.ReservedServerAccessCode, "access") end
	end)
	test("late and duplicate failures cannot retry or cancel newer attempts", function()
		local f = fixture(); assert(f.travel:Start(f.player, 22, options({TutorialToken = "ticket"}, "access"))); f:flush()
		local first = f.calls[1]; f:fail("Failure", first); f:fail("Failure", first); f:step(2)
		equal(#f.calls, 2); assert(first.options.data.TutorialTravelNonce ~= f.calls[2].options.data.TutorialTravelNonce)
		f:fail("GameFull", first); equal(#f.failures, 0); equal(f.travel:IsPending(f.player), true)
		f:fail("GameFull"); equal(#f.failures, 1); equal(f.failures[1].reason, "GameFull")
	end)
	test("Flooded waits longer and an in-flight failure never overlaps requests", function()
		local f = fixture(); local inside = false
		f.onCall = function(place, player, travelOptions)
			assert(not inside); inside = true
			if #f.calls == 1 then f.teleport.TeleportInitFailed:Fire(player, "Flooded", "", place, travelOptions) end
			equal(#f.calls, 1); inside = false
		end
		assert(f.travel:Start(f.player, 22, options({}, "access"))); f:flush()
		f:step(14); equal(#f.calls, 1); f.onCall = nil; f:step(1); equal(#f.calls, 2)
	end)
	test("watchdog releases a player left behind and ignores previous operation failure", function()
		local f = fixture(); assert(f.travel:Start(f.player, 11, options({}, "", "main-job"))); f:flush()
		local first = f.calls[1]; f:step(45); equal(#f.failures, 1); equal(f.failures[1].reason, "TravelTimedOut")
		assert(f.travel:Start(f.player, 11, options())); f:flush(); f:fail("Failure", first); f:step(2)
		equal(#f.calls, 2); equal(#f.failures, 1)
	end)
	test("departure cancellation and destruction stop queued retry callbacks", function()
		for _, mode in ipairs({"leave", "cancel", "destroy"}) do
			local f = fixture(); assert(f.travel:Start(f.player, 22, options({}, "access"))); f:flush(); f:fail("Failure")
			if mode == "leave" then f.player.Parent = nil; f.players.PlayerRemoving:Fire(f.player)
			elseif mode == "cancel" then f.travel:Cancel(f.player)
			else f.travel:Destroy(); f.travel:Destroy() end
			f:step(60); equal(#f.calls, 1); equal(#f.failures, 0); equal(f.travel:IsPending(f.player), false)
		end
	end)
	print("Tutorial travel: " .. passed .. " tests passed")
	return passed
end
