-- Preload only UI image IDs, in a bounded background queue. Menu input never
-- waits for an asset request; failed/unavailable images do not block the shop.
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Modules.UIAnimationConfig)
local Assets = {}

function Assets.New(root)
	local seen, queue, head, scanning = {}, {}, 1, {root}
	local destroyed, running, connection = false, false, nil
	local controller = {}
	local function run()
		if running or destroyed or head > #queue then return end
		running = true
		task.spawn(function()
			while not destroyed and head <= #queue do
				local batch = {}
				for _ = 1, Config.AssetBatchSize do
					if head > #queue then break end
					table.insert(batch, queue[head]); head += 1
				end
				pcall(function() ContentProvider:PreloadAsync(batch) end)
				if not destroyed and head <= #queue then RunService.Heartbeat:Wait() end
			end
			running = false
			if not destroyed then table.clear(queue); head = 1 end
		end)
	end
	function controller.QueueImage(id)
		if destroyed or type(id) ~= "string" or id == "" or seen[id] then return end
		seen[id] = true; table.insert(queue, id); run()
	end
	connection = RunService.Heartbeat:Connect(function()
		for _ = 1, Config.AssetScanNodesPerFrame do
			local item = table.remove(scanning)
			if not item then connection:Disconnect(); connection = nil; return end
			if item:IsA("ImageLabel") or item:IsA("ImageButton") then controller.QueueImage(item.Image) end
			if not item:IsA("WorldModel") and not item:IsA("ViewportFrame") then
				for _, child in ipairs(item:GetChildren()) do table.insert(scanning, child) end
			end
		end
	end)
	function controller.Destroy()
		if destroyed then return end; destroyed = true
		if connection then connection:Disconnect(); connection = nil end
		table.clear(scanning); table.clear(queue); table.clear(seen)
	end
	return controller
end

return Assets
