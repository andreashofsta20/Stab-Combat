local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end
return function(load)
	local Rewards, Schema = load("Rewards"), load("Schema")
	local passed = 0
	local function test(name, fn)
		local ok, reason = pcall(fn)
		assert(ok, name .. ": " .. tostring(reason))
		passed += 1
	end
	local config = {Version = 1, Rewards = {XP = 500, Gold = 500, Knife = "Shadow Dagger"}, RewardSaveTimeoutSeconds = 20}
	local function fixture()
		local f = {saved = {XP = 150, Cash = 250, Inventory = {}, Tutorial = {Version = 1, Completed = false}}, writes = 0}
		f.catalog = {Bowie = {Rarity = "Common", Image = "bowie"}, ["Shadow Dagger"] = {Rarity = "Common", Image = "dagger"}}
		f.player = {attributes = {DataReady = true}, present = true, values = {XP = 150, Cash = 250, Inventory = {}}}
		function f.player:GetAttribute(name) return self.attributes[name] end
		function f.player:SetAttribute(name, value) self.attributes[name] = value end
		function f:reload()
			self.profile = {Data = copy(self.saved), LastSavedData = copy(self.saved), active = true}
			function self.profile:IsActive() return self.active end
			self.player.values = copy(self.saved)
			self.player.attributes.InventoryLocked = false
			self.player.attributes.TutorialRewardPublishing = false
			self.engine = Rewards.New({
				Profile = function(player) return player == self.player and self.profile end,
				Present = function(player) return player.present end,
				Knives = self.catalog, Now = function() return 100 end,
				Snapshot = function(player)
					if player:GetAttribute("TutorialRewardPublishing") == true then return end
					self.profile.Data.XP, self.profile.Data.Cash = player.values.XP, player.values.Cash
					self.profile.Data.Inventory = copy(player.values.Inventory)
				end,
				Publish = function(player, data)
					if self.publishFailure then error("Publication failed") end
					if self.partialPublishFailure then player.values.XP = data.XP; self.publishFailure = true; error("Partial publication failed") end
					player.values.XP, player.values.Cash, player.values.Inventory = data.XP, data.Cash, copy(data.Inventory)
				end,
				Save = function(player, profile, predicate)
					self.writes += 1
					if self.onSave then self.onSave(player, profile) end
					if self.failBefore then return false end
					if not self.fakeSuccess then
						self.saved = copy(profile.Data)
						profile.LastSavedData = copy(self.saved)
					end
					if self.failAfter then return false end
					return self.fakeSuccess or predicate(profile.LastSavedData)
				end,
			})
		end
		f:reload()
		return f
	end
	local function earn(f, session)
		return f.engine.MarkEarned(f.player, f.profile, session or "server-session", config)
	end
	local function grant(f, session, terms)
		return f.engine.Commit(f.player, f.profile, session, terms or config)
	end
	local function stock(f)
		for _, row in ipairs(f.profile.Data.Inventory) do if row.Name == "Shadow Dagger" then return row.Quantity end end
		return 0
	end
	test("server completion saves entitlement before return without granting currency", function()
		local f = fixture(); local ok, receipt = earn(f)
		assert(ok and receipt.Id == "tutorial:server-session" and f.writes == 1)
		assert(Rewards.Assess(f.profile) == "Earned" and f.profile.Data.XP == 150 and f.profile.Data.Cash == 250 and stock(f) == 0)
		assert(f.saved.Tutorial.Completed and f.saved.Tutorial.PendingReward)
	end)
	test("main join applies all rewards and marker once across reloads and replays", function()
		local f = fixture(); assert(earn(f)); f:reload()
		assert(f.engine.Recover(f.player, f.profile, config))
		assert(f.saved.XP == 650 and f.saved.Cash == 750 and stock(f) == 1)
		assert(f.saved.Tutorial.PendingReward == nil and f.saved.Tutorial.AppliedReceipt)
		for _ = 1, 4 do f:reload(); assert(f.engine.Recover(f.player, f.profile, config)) end
		assert(f.saved.XP == 650 and f.saved.Cash == 750 and stock(f) == 1)
	end)
	test("incomplete profiles and legacy FirstTimePlaying never authorize a grant", function()
		local f = fixture(); f.profile.Data.FirstTimePlaying = true; f.player.TeleportData = {Completed = true, XP = 99999}
		assert(not grant(f)); assert(f.engine.Recover(f.player, f.profile, config)); assert(f.writes == 0 and stock(f) == 0)
	end)
	test("receipt mismatch and a second tutorial session cannot earn another reward", function()
		local f = fixture(); assert(earn(f)); assert(not grant(f, "forged-session")); assert(not earn(f, "new-session"))
		assert(grant(f, "server-session")); assert(not earn(f, "new-session")); assert(stock(f) == 1)
	end)
	test("frozen reward terms survive settings and catalog presentation changes", function()
		local f = fixture(); assert(earn(f)); f:reload()
		f.catalog["Shadow Dagger"].Rarity, f.catalog["Shadow Dagger"].Image = "Rare", "changed"
		assert(grant(f, nil, {Version = 2, Rewards = {XP = 999, Gold = 999, Knife = "Bowie"}}))
		assert(f.saved.XP == 650 and f.saved.Cash == 750)
		assert(f.saved.Inventory[1].Image == "dagger" and f.saved.Inventory[1].Rarity == "Common")
	end)
	test("earn save failure retains entitlement and retry saves same receipt", function()
		local f = fixture(); f.failBefore = true; assert(not earn(f))
		assert(Rewards.Assess(f.profile) == "Earned" and f.saved.Tutorial.Completed == false)
		f.failBefore = false; assert(earn(f)); assert(grant(f)); assert(stock(f) == 1)
	end)
	test("crash before earned write leaves profile eligible and zero rewards", function()
		local f = fixture(); f.failBefore = true; assert(not earn(f)); f.failBefore = false; f:reload()
		assert(Rewards.Assess(f.profile) == "Eligible" and f.engine.Recover(f.player, f.profile, config))
		assert(f.saved.XP == 150 and stock(f) == 0)
	end)
	test("ambiguous earned save recovers frozen entitlement after reload", function()
		local f = fixture(); f.failAfter = true; assert(not earn(f)); f.failAfter = false; f:reload()
		assert(f.engine.Recover(f.player, f.profile, config)); assert(stock(f) == 1)
	end)
	test("unacknowledged entitlement is never applied", function()
		local f = fixture(); f.failBefore = true; assert(not earn(f)); assert(not grant(f))
		assert(f.profile.Data.XP == 150 and f.profile.Data.Cash == 250 and stock(f) == 0)
	end)
	test("save return value cannot forge backend acknowledgement", function()
		local f = fixture(); f.fakeSuccess = true; assert(not earn(f)); assert(not grant(f))
		assert(f.saved.Tutorial.Completed == false and stock(f) == 0)
	end)
	test("grant save timeout retries marker without repeating economy deltas", function()
		local f = fixture(); assert(earn(f)); f.failBefore = true; assert(not grant(f))
		assert(Rewards.Assess(f.profile) == "Granted" and f.profile.Data.XP == 650 and stock(f) == 1)
		assert(f.player:GetAttribute("InventoryLocked") == false)
		assert(f.player:GetAttribute("TutorialRewardPublishing") == false)
		assert(not grant(f)); assert(f.profile.Data.XP == 650 and stock(f) == 1)
		f.failBefore = false; assert(grant(f)); f:reload(); assert(grant(f)); assert(stock(f) == 1)
	end)
	test("crash before applied save recovers pending reward exactly once", function()
		local f = fixture(); assert(earn(f)); f.failBefore = true; assert(not grant(f))
		f.failBefore = false; f:reload(); assert(grant(f)); assert(f.saved.XP == 650 and stock(f) == 1)
	end)
	test("crash after applied save reloads marker and never repeats grant", function()
		local f = fixture(); assert(earn(f)); f.failAfter = true; assert(not grant(f))
		f.failAfter = false; f:reload(); assert(grant(f)); assert(f.saved.XP == 650 and stock(f) == 1)
	end)
	test("existing canonical inventory stock increments one row and preserves restrictions", function()
		local f = fixture(); f.saved.Inventory = {{Name = "Shadow Dagger", Quantity = 3, Rarity = "Common", Image = "dagger", Tradeable = false}}
		f:reload(); assert(earn(f)); assert(grant(f)); assert(#f.saved.Inventory == 1 and stock(f) == 4)
		assert(f.saved.Inventory[1].Tradeable == false)
	end)
	test("currency and inventory overflow leave pending receipt recoverable", function()
		for _, field in ipairs({"XP", "Cash", "Inventory"}) do
			local f = fixture(); assert(earn(f))
			if field == "Inventory" then f.player.values.Inventory = {{Name = "Shadow Dagger", Quantity = 2147483647}}
			else f.player.values[field] = 2147483647 end
			assert(not grant(f)); assert(Rewards.Assess(f.profile) == "Earned" and f.saved.Tutorial.PendingReward)
		end
	end)
	test("inactive unhydrated replaced and absent player profiles cannot write", function()
		for _, scenario in ipairs({"inactive", "unhydrated", "absent", "replaced", "locked"}) do
			local f = fixture(); assert(earn(f))
			if scenario == "inactive" then f.profile.active = false
			elseif scenario == "unhydrated" then f.player.attributes.DataReady = false
			elseif scenario == "absent" then f.player.present = false
			elseif scenario == "locked" then f.player.attributes.InventoryLocked = true end
			local candidate = scenario == "replaced" and {Data = f.profile.Data, IsActive = function() return true end} or f.profile
			assert(not f.engine.Commit(f.player, candidate, nil, config)); assert(stock(f) == 0)
		end
	end)
	test("ownership loss while waiting for entitlement prevents reward mutation", function()
		local f = fixture(); f.failBefore = true; assert(not earn(f)); f.failBefore = false
		f.onSave = function() f.profile.active = false end
		assert(not grant(f)); assert(f.profile.Data.XP == 150 and stock(f) == 0)
	end)
	test("duplicate calls during a yielding save cannot mutate receipt or stock", function()
		local f = fixture(); local reentrant
		f.onSave = function() reentrant = earn(f) end
		assert(earn(f)); assert(reentrant == false); f.onSave = nil; assert(grant(f)); assert(stock(f) == 1)
	end)
	test("invalid reward settings and unavailable knives never create an entitlement", function()
		for _, change in ipairs({{XP = 0/0}, {Gold = -1}, {Knife = "Missing"}, {XP = math.huge}}) do
			local f = fixture(); local settings = copy(config)
			for key, value in pairs(change) do settings.Rewards[key] = value end
			assert(not f.engine.MarkEarned(f.player, f.profile, "server-session", settings)); assert(Rewards.Assess(f.profile) == "Eligible")
		end
	end)
	test("removed reward catalog entry retains pending entitlement", function()
		local f = fixture(); assert(earn(f)); f.catalog["Shadow Dagger"] = nil
		assert(not grant(f)); assert(Rewards.Assess(f.profile) == "Earned")
	end)
	test("read receipts are defensive copies", function()
		local f = fixture(); assert(earn(f)); local receipt = Rewards.ReadReceipt(f.profile); receipt.XP = 99999
		assert(f.profile.Data.Tutorial.PendingReward.XP == 500); assert(grant(f)); assert(f.saved.XP == 650)
	end)
	test("failed publication rolls back marker and grants before saving", function()
		local f = fixture(); assert(earn(f)); f.publishFailure = true
		assert(not grant(f)); assert(Rewards.Assess(f.profile) == "Earned" and f.profile.Data.XP == 150 and stock(f) == 0)
		assert(f.player:GetAttribute("InventoryLocked") == true)
		assert(f.player:GetAttribute("TutorialRewardPublishing") == true)
	end)
	test("failed partial currency publication cannot overwrite canonical rollback on save", function()
		local f = fixture(); assert(earn(f)); f.partialPublishFailure = true
		assert(not grant(f)); assert(f.player.values.XP == 650 and f.profile.Data.XP == 150)
		assert(f.player:GetAttribute("TutorialRewardPublishing") == true)
		-- Mirror ProfileManager's guarded OnSave; partially published Values are
		-- discarded on next hydration while PendingReward stays recoverable.
		if f.player:GetAttribute("TutorialRewardPublishing") ~= true then f.profile.Data.XP = f.player.values.XP end
		f.saved = copy(f.profile.Data); f.publishFailure, f.partialPublishFailure = false, false; f:reload()
		assert(grant(f)); assert(f.saved.XP == 650 and stock(f) == 1)
	end)
	test("schema defaults tutorial separately from legacy flags", function()
		local f = fixture(); local data = assert(Schema.Validate({FirstTimePlaying = true}, {Inventory = f.catalog, RevolverInventory = {}, Emotes = {}}))
		assert(data.Tutorial.Completed == false and Rewards.Assess({Data = data}) == "Eligible")
	end)
	test("schema rejects corrupt entitlement and dedup records instead of dropping them", function()
		local f = fixture(); assert(earn(f)); local pending = copy(f.profile.Data.Tutorial)
		local invalid = {false, {Version = 1, Completed = true}, {Version = 1, Completed = false, PendingReward = pending.PendingReward},
			{Version = 1, Completed = true, PendingReward = pending.PendingReward, AppliedReceipt = pending.PendingReward}}
		local corrupt = copy(pending); corrupt.PendingReward.XP = 0/0; table.insert(invalid, corrupt)
		corrupt = copy(pending); corrupt.PendingReward.Id = "foreign-id"; table.insert(invalid, corrupt)
		for _, state in ipairs(invalid) do
			assert(Schema.Validate({Tutorial = state}, {Inventory = f.catalog, RevolverInventory = {}, Emotes = {}}) == nil)
			assert(Rewards.Assess({Data = {Tutorial = state}}) == "Invalid")
		end
	end)
	test("schema preserves frozen pending receipt and historical applied receipt", function()
		local f = fixture(); assert(earn(f)); local source = copy(f.saved)
		local data = assert(Schema.Validate(source, {Inventory = f.catalog, RevolverInventory = {}, Emotes = {}}))
		assert(data.Tutorial.PendingReward.XP == 500 and data.Tutorial.PendingReward ~= source.Tutorial.PendingReward)
		assert(grant(f)); f.saved.Inventory = {}; f.catalog["Shadow Dagger"] = nil
		data = assert(Schema.Validate(f.saved, {Inventory = f.catalog, RevolverInventory = {}, Emotes = {}}))
		assert(data.Tutorial.AppliedReceipt.Knife == "Shadow Dagger")
	end)
	print("Tutorial rewards: " .. passed .. " security/recovery tests passed")
end
