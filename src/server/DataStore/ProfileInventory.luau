-- Publish profile-owned stock after durable escrow/recovery. Caller freezes
-- inventory writers before changing the profile; unrelated stats stay live.
local Inventory = {}
function Inventory.Publish(player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	for _, kind in ipairs({"Inventory", "Emotes"}) do
		local folder = stats:FindFirstChild(kind)
		if not folder then continue end
		for _, item in ipairs(folder:GetChildren()) do item:Destroy() end
		for _, row in ipairs(data[kind] or {}) do
			local item = Instance.new("StringValue")
			item.Name, item.Value = row.Name, kind == "Emotes" and (row.EmoteId or "") or ""
			for _, field in ipairs({"Quantity", "Rarity", "Image", "Tradeable"}) do
				local value = row[field]
				if value ~= nil then
					local child = Instance.new(field == "Quantity" and "IntValue" or field == "Tradeable" and "BoolValue" or "StringValue")
					child.Name, child.Value, child.Parent = field, value, item
				end
			end
			item.Parent = folder
		end
	end
	local equipped = stats:FindFirstChild("EquippedKnife")
	local knives = stats:FindFirstChild("Inventory")
	if equipped and knives and not knives:FindFirstChild(equipped.Value) then equipped.Value = "Bowie" end
end
return Inventory
