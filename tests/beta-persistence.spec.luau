local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for k, v in pairs(value) do result[k] = copy(v) end; return result
end
return function(load)
	local Recovery, Schema, Admission, Archive = load("Recovery"), load("Schema"), load("Admission"), load("Archive")
	local passed = 0
	local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); passed += 1 end
	local a, b = {Type = "Inventory", Name = "A", Quantity = 2, Rarity = "Rare", Image = "a"}, {Type = "Inventory", Name = "B", Quantity = 1, Rarity = "Rare", Image = "b"}
	local function fixture(crash, after)
		local f = {now = 100, calls = 0, saved = {}, profiles = {}, journals = {}, locks = {}, crash = crash, after = after}
		for id, row in pairs({[1] = {Name = "A", Quantity = 3}, [2] = {Name = "B", Quantity = 2}}) do
			f.saved[id] = {Inventory = {row}, Emotes = {}, TradeJournal = {}}
		end
		local function before()
			assert(not f.dead, "Server stopped"); f.calls += 1
			if f.onBefore then f.onBefore(f.calls) end
			if f.calls == f.crash and not f.after then f.dead = true; error("Crash before write") end
		end
		local function afterWrite()
			if f.calls == f.crash and f.after then
				if f.transient then f.crash = nil; error("Ambiguous transient write") end
				f.dead = true; error("Ambiguous write after crash")
			end
		end
		function f:reload(online)
			self.dead, self.crash = false, nil; self.now += 121; self.profiles, self.locks = {}, {}
			for id, data in pairs(self.saved) do
				if not online or online[id] then
					self.profiles[id] = {Data = copy(data), IsActive = function() return true end}
				end
			end
			self.engine = Recovery.New({Owner = "server", Now = function() return self.now end,
				Profile = function(id) return not self.dead and self.profiles[id] or nil end,
				Snapshot = function() end, Lock = function(id, locked) self.locks[id] = locked end, Publish = function() end,
				Save = function(id, profile, predicate)
					before(); self.saved[id] = copy(profile.Data); afterWrite(); return predicate(self.saved[id]) == true
				end,
				Journal = function(id, transform)
					local ok, result = pcall(function()
						before(); local value = transform(copy(self.journals[id]));
						if value ~= nil then self.journals[id] = copy(value) end
						afterWrite(); return copy(value)
					end)
					return ok, result
				end})
		end
		f:reload(); f.crash = crash
		return f
	end
	local function amount(data, name)
		for _, row in ipairs(data.Inventory) do if row.Name == name then return row.Quantity end end
		return 0
	end
	local function recover(f)
		f:reload()
		for _, id in ipairs({2, 1, 2, 1}) do assert(f.engine.Recover(id)) end
		for name, total in pairs({A = 3, B = 2}) do assert(amount(f.profiles[1].Data, name) + amount(f.profiles[2].Data, name) == total, "Stock conserved") end
		local committed = f.journals.trade and f.journals.trade.Decision == "COMMIT"
		assert(amount(f.profiles[1].Data, "A") == (committed and 1 or 3))
		assert(amount(f.profiles[1].Data, "B") == (committed and 1 or 0))
		assert(not f.locks[1] and not f.locks[2])
	end
	test("trade commits and reloads without repeating deltas", function()
		local f = fixture(); assert(f.engine.Execute("trade", 1, 2, {a}, {b})); assert(f.journals.trade.State == "COMPLETE")
		assert(not f.engine.Execute("trade", 1, 2, {a}, {b})); recover(f)
	end)
	test("recovered ambiguous commit reports success only after both durable acknowledgements", function()
		local f = fixture(6, true); f.transient = true
		assert(f.engine.Execute("trade", 1, 2, {a}, {b}))
		assert(f.journals.trade.State == "COMPLETE" and not f.locks[1] and not f.locks[2])
		assert(not f.engine.Execute("trade", 1, 2, {a}, {b}))
		recover(f)
	end)
	local baseline = fixture(); assert(baseline.engine.Execute("trade", 1, 2, {a}, {b}))
	local stages = baseline.calls
	for stage = 1, stages do
		for _, after in ipairs({false, true}) do
			test("crash " .. stage .. (after and " after" or " before") .. " durable write", function()
				local f = fixture(stage, after); f.engine.Execute("trade", 1, 2, {a}, {b}); recover(f)
			end)
		end
	end
	test("committed participant recovers while other participant remains offline", function()
		local f = fixture(7, true); f.engine.Execute("trade", 1, 2, {a}, {b}); assert(f.journals.trade.Decision == "COMMIT")
		f:reload({[2] = true}); assert(f.engine.Recover(2)); assert(amount(f.profiles[2].Data, "A") == 2)
		f:reload(); assert(f.engine.Recover(1)); assert(f.engine.Recover(2))
		assert(amount(f.profiles[2].Data, "A") == 2)
	end)
	test("backend outage retains reservations and inventory locks", function()
		local f = fixture(5, true); f.engine.Execute("trade", 1, 2, {a}, {b}); assert(f.locks[1])
		recover(f)
	end)
	test("unknown preparation cannot refund before durable lease expires", function()
		local f = fixture(3, true); f.engine.Execute("trade", 1, 2, {a}, {b})
		f:reload(); f.now = f.journals.trade.LeaseUntil - 1
		assert(not f.engine.Recover(1)); assert(f.locks[1]); assert(amount(f.profiles[1].Data, "A") == 1)
		f.now += 2; assert(f.engine.Recover(1)); assert(amount(f.profiles[1].Data, "A") == 3)
	end)
	test("duplicate rows invalid terms and overflow never reserve stock", function()
		local f = fixture(); assert(not f.engine.Execute("trade", 1, 2, {a, a}, {b}))
		assert(not f.engine.Execute("other", 1, 2, {{Type = "Inventory", Name = "A", Quantity = 0/0}}, {b}))
		f.profiles[1].Data.Inventory = {{Name = "A", Quantity = 2147483647}, {Name = "B", Quantity = 2147483647}}
		assert(not f.engine.Execute("overflow", 1, 2, {a}, {b})); assert(f.journals.overflow == nil)
	end)
	test("empty offers settle safely", function()
		local f = fixture(); assert(f.engine.Execute("trade", 1, 2, {}, {})); f:reload()
		assert(f.engine.Recover(1)); assert(f.engine.Recover(2)); assert(amount(f.profiles[1].Data, "A") == 3)
	end)
	local catalogs = {Inventory = {Bowie = {Rarity = "Common", Image = "bowie"}, A = {Rarity = "Rare", Image = "a"}}, RevolverInventory = {}, Emotes = {}}
	test("schema quarantines duplicate unknown corrupt rows without summing stock", function()
		local source = {Inventory = {{Name = "A", Quantity = 2}, {Name = "A", Quantity = 7}, {Name = "Legacy", Quantity = 5}, false, {Name = "Bowie", Quantity = math.huge}}}
		local data = assert(Schema.Validate(source, catalogs)); assert(#data.Inventory == 1 and data.Inventory[1].Quantity == 2)
		assert(#data.InventoryQuarantine == 4); assert(#source.Inventory == 5); assert(data.DataSchemaVersion == 1)
		local again = assert(Schema.Validate(data, catalogs)); assert(#again.InventoryQuarantine == 4)
	end)
	test("schema refuses currency receipt and recovery corruption", function()
		for _, data in ipairs({{Cash = 0/0}, {XP = -1}, {ProcessedPurchases = false}, {ProcessedPurchases = {receipt = 1}}, {TradeJournal = "bad"}}) do assert(Schema.Validate(data, catalogs) == nil) end
	end)
	test("schema repairs harmless settings and bad history without mutating source", function()
		local source = {Settings = {Trades = "yes"}, RoundHistory = {false, {Kills = "bad"}, {Kills = 2, Placement = 1, Opponents = 3}}}
		local data = assert(Schema.Validate(source, catalogs)); assert(data.Settings.Trades == true and source.Settings.Trades == "yes")
		assert(#data.RoundHistory == 1 and data.RoundHistory[1].Kills == 2)
	end)
	local function pos(x, z) return {X = x, Y = 0, Z = z or 0} end
	test("movement accepts sustained valid running and slide speed", function()
		local state = {}; assert(Admission.Step(state, pos(0), 0, 32, 0.3, false))
		for i = 1, 100 do assert(Admission.Step(state, pos(i * 3.2), i * 0.1, 32, 0.3, false)) end
		for i = 1, 8 do assert(Admission.Step(state, pos(320 + i * 6), 10 + i * 0.1, 60, 0.3, false)) end
	end)
	test("movement accepts burst replication but rejects sustained excess teleport and cover", function()
		local state = {}; Admission.Step(state, pos(0), 0, 32, 0.1, false)
		assert(Admission.Step(state, pos(9), 0.1, 32, 0.1, false))
		assert(not Admission.Step(state, pos(100), 0.2, 32, 0.1, false))
		assert(not Admission.Step(state, pos(10), 0.3, 32, 0.1, true))
		assert(not Admission.Step(state, {X = 0/0, Y = 0, Z = 0}, 0.4, 32, 0.1, false))
		state = {}; Admission.Step(state, pos(0), 0, 32, 0, false)
		local rejected = false; for i = 1, 100 do if not Admission.Step(state, pos(i * 6), i * 0.1, 32, 0, false) then rejected = true; break end end
		assert(rejected)
	end)
	test("receipt archival acknowledges before pruning and survives replay", function()
		local records = {}; local fail = true
		local store = {UpdateAsync = function(_, id, fn) if fail then error("Outage") end; records[id] = fn(copy(records[id])); return copy(records[id]) end}
		local receipt = {PurchaseId = "r", PlayerId = 1, ProductId = 2}
		local profile = {Data = {ProcessedPurchases = {r = true}}, IsActive = function() return true end}
		assert(not Archive.Commit(store, receipt)); assert(profile.Data.ProcessedPurchases.r)
		fail = false; assert(Archive.Commit(store, receipt)); Archive.PruneProfile(profile, "r"); assert(profile.Data.ProcessedPurchases.r == nil)
		local ok, granted = Archive.Check(store, "r"); assert(ok and granted); assert(Archive.Commit(store, receipt))
		assert(not Archive.Commit(store, {PurchaseId = "r", PlayerId = 9, ProductId = 2}))
	end)
	test("historical archival is bounded and cannot move an unacknowledged marker", function()
		local records = {}
		local store = {UpdateAsync = function(_,id,fn) records[id] = fn(copy(records[id])); return copy(records[id]) end}
		local profile = {Data={ProcessedPurchases={a=true,b=true,c=true,pending=true}},LastSavedData={ProcessedPurchases={a=true,b=true,c=true}},IsActive=function() return true end}
		assert(Archive.Backfill(store,profile,1,2)==2)
		assert(profile.Data.ProcessedPurchases.pending and records.pending==nil)
		assert(Archive.Backfill(store,profile,1,2)==1)
		assert(Archive.Check(store,"a")); local _,granted=Archive.Check(store,"a"); assert(granted)
		assert(Archive.Commit(store,{PurchaseId="a",PlayerId=1,ProductId=2}))
		assert(not Archive.Commit(store,{PurchaseId="a",PlayerId=9,ProductId=2}))
	end)
	test("stale trade coordinator cannot renew another owner's lease", function()
		local f=fixture()
		f.onBefore=function(stage) if stage==4 then f.journals.trade.Owner="other-server" end end
		assert(not f.engine.Execute("trade",1,2,{a},{b})); assert(f.locks[1])
		assert(f.journals.trade.Decision==nil); f.onBefore=nil; recover(f)
	end)
	test("expired reservation cannot turn a durable abort into a commit", function()
		local f=fixture()
		f.onBefore=function(stage) if stage==5 then f.journals.trade.State="ABORT_DECIDED"; f.journals.trade.Decision="ABORT"; f.journals.trade.Owner="other-server" end end
		assert(not f.engine.Execute("trade",1,2,{a},{b})); f.onBefore=nil; recover(f)
		assert(f.journals.trade.Decision=="ABORT")
	end)
	test("mode and weapon counters use fixed keys and cap corrupt or excessive counts", function()
		local Stats=load("Stats"); local data={CompetitiveStats=Stats.Repair({Modes={FFA={Kills=0/0,Wins=-1}},Weapons={Revolver={Hits=2147483647}}})}
		Stats.Hit(data,"Revolver",34); Stats.Kill(data,"FFA","Revolver"); Stats.Death(data,"FFA")
		Stats.Round(data,"FFA",true,true); Stats.Round(data,"BattleRoyale",true,false)
		assert(data.CompetitiveStats.Modes.FFA.Kills==1 and data.CompetitiveStats.Modes.FFA.Deaths==1)
		assert(data.CompetitiveStats.Modes.FFA.Forfeits==1 and data.CompetitiveStats.Modes.FFA.Wins==0)
		assert(data.CompetitiveStats.Modes.BattleRoyale.Wins==1)
		assert(data.CompetitiveStats.Weapons.Revolver.Kills==1 and data.CompetitiveStats.Weapons.Revolver.Damage==34)
		assert(data.CompetitiveStats.Weapons.Revolver.Hits==2147483647)
		Stats.Hit(data,"Forged",100); assert(data.CompetitiveStats.Weapons.Forged==nil)
	end)
	print("Beta persistence/security: " .. passed .. " tests passed; " .. stages .. " durable stages tested before and after failure")
end
