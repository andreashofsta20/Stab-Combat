-- Durable escrow protocol. Adapter writes must return the authoritative saved
-- record; queued profile saves are never acknowledgements. No raw profile keys
-- are edited outside their owned ProfileStore sessions.
local Recovery = {}
local MAX = 2147483647

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

local function terms(items)
	if type(items) ~= "table" or #items > 32 then error("Invalid trade terms") end
	local rows, seen = {}, {}
	for _, item in ipairs(items) do
		assert(type(item) == "table" and (item.Type == "Inventory" or item.Type == "Emotes")
			and type(item.Name) == "string" and #item.Name > 0 and #item.Name <= 64
			and type(item.Quantity) == "number" and item.Quantity > 0 and item.Quantity <= MAX
			and item.Quantity % 1 == 0, "Invalid trade row")
		local key = item.Type .. ":" .. item.Name
		assert(not seen[key], "Duplicate trade row")
		seen[key] = true
		table.insert(rows, {Type = item.Type, Name = item.Name, Quantity = item.Quantity,
			Rarity = type(item.Rarity) == "string" and item.Rarity or "Common", Image = type(item.Image) == "string" and item.Image or "",
			EmoteId = type(item.EmoteId) == "string" and item.EmoteId or "", Tradeable = item.Tradeable ~= false})
	end
	return rows
end

-- Prepare complete new tables before changing either inventory or its marker.
function Recovery.Transform(data, items, sign)
	local result = {Inventory = copy(data.Inventory or {}), Emotes = copy(data.Emotes or {})}
	for _, item in ipairs(terms(items)) do
		local rows, index = result[item.Type], nil
		for i, row in ipairs(rows) do if row.Name == item.Name then index = i; break end end
		local original = index and rows[index]
		local quantity = (original and original.Quantity or 0) + sign * item.Quantity
		assert(quantity >= 0 and quantity <= MAX and quantity % 1 == 0, "Trade stock unavailable or overflow")
		if quantity == 0 then
			if index then table.remove(rows, index) end
		elseif original then
			original.Quantity = quantity
		else
			local row = copy(item); row.Type = nil; row.Quantity = quantity
			table.insert(rows, row)
		end
	end
	return result
end

function Recovery.New(io)
	local engine = {}
	local function profile(id)
		local value = io.Profile(id)
		assert(value and value:IsActive(), "Profile session unavailable")
		return value
	end
	local function persist(id, state, transaction)
		local value = profile(id)
		assert(io.Save(id, value, function(saved)
			local marker = saved.TradeJournal and saved.TradeJournal[transaction]
			return marker and marker.State == state
		end), "Trade save not acknowledged")
	end
	local function write(transaction, fn)
		local ok, record = io.Journal(transaction, fn)
		assert(ok and type(record) == "table" and record.Id == transaction, "Trade journal unavailable")
		return record
	end
	local function settle(id, record)
		local value = profile(id)
		local marker = value.Data.TradeJournal and value.Data.TradeJournal[record.Id]
		if not marker then return false end -- This participant never reserved.
		local decision = record.Decision
		assert(decision == "COMMIT" or decision == "ABORT", "Trade decision pending")
		local state = decision == "COMMIT" and "COMMITTED" or "REFUNDED"
		if marker.State == "RESERVED" then
			local index = record.Player1 == id and 1 or 2
			assert(record.Player1 == id or record.Player2 == id, "Participant mismatch")
			local stock = record.Offers[decision == "COMMIT" and (3 - index) or index]
			local changed = Recovery.Transform(value.Data, stock, 1)
			value.Data.Inventory, value.Data.Emotes = changed.Inventory, changed.Emotes
			marker.State = state
			io.Publish(id, value.Data)
		end
		assert(marker.State == state, "Conflicting trade settlement")
		persist(id, state, record.Id)
		record = write(record.Id, function(old)
			assert(old and old.Decision == decision, "Trade decision changed")
			old.Settled = old.Settled or {}; old.Settled[tostring(id)] = true
			if old.Settled[tostring(old.Player1)] and old.Settled[tostring(old.Player2)] then old.State = "COMPLETE" end
			return old
		end)
		-- Removing a settled reference is safe: the durable terminal journal
		-- rejects replay. A later save/rejoin may still contain the old marker.
		value.Data.TradeJournal[record.Id] = nil
		io.Lock(id, false)
		return true
	end
	function engine.Recover(id)
		local ok, err = pcall(function()
			local value = profile(id)
			local pending = value.Data.TradeJournal or {}
			assert(type(pending) == "table", "Invalid recovery references")
			for transaction in pairs(copy(pending)) do
				io.Lock(id, true)
				local record = write(transaction, function(old)
					assert(old and (old.Player1 == id or old.Player2 == id), "Missing trade intent")
					if old.State == "PREPARING" and old.LeaseUntil <= io.Now() then
						old.State, old.Decision = "ABORT_DECIDED", "ABORT"
					end
					return old
				end)
				settle(id, record)
			end
		end)
		return ok, err
	end
	function engine.Execute(transaction, first, second, outgoing1, outgoing2)
		local locked = {}
		local ok, result = pcall(function()
			assert(type(transaction) == "string" and #transaction > 0 and #transaction <= 64 and first ~= second, "Invalid transaction")
			local a, b = terms(outgoing1), terms(outgoing2)
			for _, id in ipairs({first, second}) do
				local value = profile(id)
				assert(next(value.Data.TradeJournal or {}) == nil, "Inventory recovery pending")
				io.Snapshot(id, value)
				io.Lock(id, true); table.insert(locked, id)
			end
			-- Preflight both debits and credits, including empty offers/overflow.
			local debit1 = Recovery.Transform(profile(first).Data, a, -1)
			local debit2 = Recovery.Transform(profile(second).Data, b, -1)
			Recovery.Transform(debit1, b, 1); Recovery.Transform(debit2, a, 1)
			local record = write(transaction, function(old)
				assert(old == nil, "Transaction ID already exists")
				return {Version = 1, Id = transaction, Player1 = first, Player2 = second,
					Owner = io.Owner, LeaseUntil = io.Now() + 120, State = "PREPARING",
					Offers = {a, b}, Settled = {}}
			end)
			for index, id in ipairs({first, second}) do
				record = write(transaction, function(old)
					assert(old.State == "PREPARING" and old.Owner == io.Owner and old.LeaseUntil > io.Now(), "Coordinator fenced")
					old.LeaseUntil = io.Now() + 120; return old
				end)
				local value = profile(id)
				local debit = Recovery.Transform(value.Data, index == 1 and a or b, -1)
				value.Data.Inventory, value.Data.Emotes = debit.Inventory, debit.Emotes
				value.Data.TradeJournal = value.Data.TradeJournal or {}
				value.Data.TradeJournal[transaction] = {State = "RESERVED", Outgoing = index == 1 and a or b, Incoming = index == 1 and b or a}
				io.Publish(id, value.Data)
				persist(id, "RESERVED", transaction)
			end
			record = write(transaction, function(old)
				assert(old.State == "PREPARING" and old.Owner == io.Owner and old.LeaseUntil > io.Now(), "Coordinator fenced")
				old.State, old.Decision = "COMMIT_DECIDED", "COMMIT"; return old
			end)
			settle(first, record); settle(second, record)
			return true
		end)
		if not ok then
			-- A failed call may have durably committed. Resolve via UpdateAsync;
			-- never guess a refund from the local exception/timeout.
			pcall(function()
				write(transaction, function(old)
					if old and old.State == "PREPARING" and old.Owner == io.Owner then
						old.State, old.Decision = "ABORT_DECIDED", "ABORT"
					end
					return old
				end)
			end)
			for _, id in ipairs(locked) do
				local value = io.Profile(id)
				if value and value:IsActive() then
					if next(value.Data.TradeJournal or {}) then engine.Recover(id) else io.Lock(id, false) end
				end
			end
		end
		if ok and result == true then return true end
		return false, tostring(result)
	end
	return engine
end

return Recovery
