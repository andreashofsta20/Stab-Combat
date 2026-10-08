local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.DataConfig)
local Store = game:GetService("DataStoreService"):GetDataStore(Config.ProfileStoreName .. "_Trades_v1")
local Recovery = require(script.Parent.TradeRecovery)
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local Inventory = require(script.Parent.Parent.DataStore.ProfileInventory)
local function player(id) return Players:GetPlayerByUserId(id) end
local engine = Recovery.New({
	Owner = game.JobId .. ":" .. game:GetService("HttpService"):GenerateGUID(false),
	Now = os.time,
	Profile = function(id) local p = player(id); return p and Profiles.GetProfile(p) end,
	Snapshot = function(id) Profiles.SyncProfile(player(id)) end,
	Lock = function(id, locked) local p = player(id); if p then p:SetAttribute("InventoryLocked", locked) end end,
	Publish = function(id, data) local p = player(id); if p and p:GetAttribute("DataReady") == true then Inventory.Publish(p, data) end end,
	Save = function(id, profile, predicate) return Profiles.ConfirmSave(player(id), profile, predicate, 20) end,
	Journal = function(id, transform)
		local ok, value = pcall(function() return Store:UpdateAsync(id, transform) end)
		if not ok then RS:SetAttribute("TradeJournalErrorCount", (RS:GetAttribute("TradeJournalErrorCount") or 0) + 1) end
		return ok, value
	end,
})
local Persistence = {}
function Persistence.Recover(player) return engine.Recover(player.UserId) end
function Persistence.Execute(session)
	local ok, err = engine.Execute(session.TradeId, session.Player1.UserId, session.Player2.UserId, session.Player1Items, session.Player2Items)
	if not ok then
		for _, p in ipairs({session.Player1, session.Player2}) do
			task.spawn(function()
				for _ = 1, 12 do
					local profile = Profiles.GetProfile(p)
					if p.Parent ~= Players or not profile or not profile:IsActive() or not next(profile.Data.TradeJournal or {}) then return end
					task.wait(5)
					local recovered = engine.Recover(p.UserId)
					if recovered then return end
				end
			end)
		end
	end
	return ok, err
end
return Persistence
