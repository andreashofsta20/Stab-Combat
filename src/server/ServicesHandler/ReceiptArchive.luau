-- Durable per-receipt records replace growing per-player dedup tables only
-- after archival is acknowledged. UpdateAsync avoids cached absence on replay.
local Archive = {}
function Archive.Check(store, receiptId)
	local ok, value = pcall(function()
		return store:UpdateAsync(receiptId, function(old) return old end)
	end)
	return ok, value == true or (type(value) == "table" and value.Granted == true)
end
function Archive.Commit(store, receipt)
	local ok, saved = pcall(function()
		return store:UpdateAsync(tostring(receipt.PurchaseId), function(old)
			if old == true then return old end -- original ledger compatibility
			if old then
				assert(type(old) == "table" and old.Granted == true and old.PlayerId == receipt.PlayerId
					and (old.ProductId == receipt.ProductId or old.Historical == true), "Receipt identity mismatch")
				return old
			end
			return {Granted = true, PlayerId = receipt.PlayerId, ProductId = receipt.ProductId, Version = 1}
		end)
	end)
	return ok and (saved == true or type(saved) == "table" and saved.Granted == true)
end
function Archive.Backfill(store, profile, userId, limit)
	local archived = 0
	if not profile or not profile:IsActive() then return archived end
	local saved = profile.LastSavedData and profile.LastSavedData.ProcessedPurchases
	if type(saved) ~= "table" then return archived end
	for id in pairs(profile.Data.ProcessedPurchases or {}) do
		if archived >= (limit or 8) or not profile:IsActive() then break end
		-- Only markers already present in an acknowledged profile may move.
		if saved[id] == true then
			local ok, value = pcall(function()
				return store:UpdateAsync(id, function(old)
					if old then
						assert(old == true or type(old) == "table" and old.Granted == true, "Invalid historical receipt")
						return old
					end
					return {Granted = true, PlayerId = userId, Historical = true, Version = 1}
				end)
			end)
			if not ok or not value then break end
			Archive.PruneProfile(profile, id); archived += 1
		end
	end
	return archived
end
function Archive.PruneProfile(profile, receiptId)
	if profile and profile:IsActive() and type(profile.Data.ProcessedPurchases) == "table" then
		profile.Data.ProcessedPurchases[receiptId] = nil
	end
end
return Archive
