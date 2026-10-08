local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.DataConfig)
local Archive = require(script.Parent.ReceiptArchive)
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local VIP = require(script.Parent.VIPService)
local Purchases = require(script.Parent.PurchaseHandler)
local Store = game:GetService("DataStoreService"):GetDataStore(Config.ReceiptStoreName)
-- At most eight acknowledged historical markers/player/minute. An outage
-- preserves the markers and retries later; no new receipt waits on maintenance.
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("DataReady") == true then
				local ok, count = Purchases.Maintain(player.UserId,function()
					local profile = Profiles.GetProfile(player)
					local archived = Archive.Backfill(Store, profile, player.UserId, 8)
					return archived + VIP.ArchiveHistoricalPurchases(player.UserId,Store,8,profile,function(id)
						return Profiles.ConfirmPurchase(player,id)
					end)
				end)
				if ok then player:SetAttribute("ReceiptMarkersArchived", (player:GetAttribute("ReceiptMarkersArchived") or 0) + count) end
			end
		end
	end
end)
return {}
