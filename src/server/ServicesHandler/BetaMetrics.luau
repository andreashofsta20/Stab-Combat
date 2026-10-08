-- Low-frequency diagnostics with counters, no unbounded player histories.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local profileStore = require(game:GetService("ServerScriptService").Packages.ProfileStore)
profileStore.OnError:Connect(function() RS:SetAttribute("ProfileBackendErrorCount",(RS:GetAttribute("ProfileBackendErrorCount") or 0)+1) end)
task.spawn(function()
	while true do
		task.wait(60)
		local largest, pending, receipts, rejections = 0,0,0,0
		for _, player in ipairs(Players:GetPlayers()) do
			local data = Profiles.GetProfileData(player)
			if data then
				local ok, encoded = pcall(Http.JSONEncode,Http,data)
				if ok then largest = math.max(largest,#encoded); player:SetAttribute("ProfileSerializedBytes",#encoded) end
				for _ in pairs(data.TradeJournal or {}) do pending += 1 end
				for _ in pairs(data.ProcessedPurchases or {}) do receipts += 1 end
			end
			rejections += player:GetAttribute("MovementRejectedCount") or 0
		end
		RS:SetAttribute("LargestProfileBytes",largest)
		RS:SetAttribute("PendingTradeReservations",pending)
		RS:SetAttribute("HotReceiptMarkers",receipts)
		RS:SetAttribute("MovementRejectionCount",rejections)
		RS:SetAttribute("ServerMemoryMB",game:GetService("Stats"):GetTotalMemoryUsageMb())
	end
end)
return {}
