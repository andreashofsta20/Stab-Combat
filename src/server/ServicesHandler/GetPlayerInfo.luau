local GetPlayerInfo = {}

local Players = game:GetService("Players")

function GetPlayerInfo.AllInfo(UserId : number)
	local InfoTable = {}

	for _, player in pairs(Players:GetPlayers()) do
		if player.UserId == UserId then
			InfoTable.Name = player.Name
			InfoTable.DisplayName = player.DisplayName
			InfoTable.UserId = player.UserId
			
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				for _, stat in pairs(leaderstats:GetChildren()) do
					if stat:IsA("IntValue") or stat:IsA("StringValue") then
						InfoTable[stat.Name] = stat.Value
					end
				end
			end
			
			break 
		end
	end

	return InfoTable
end



function GetPlayerInfo.Inventory(UserId : number)
	local InventoryInfo = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == UserId then
			local inventory = player:FindFirstChild("leaderstats"):FindFirstChild("Inventory")
			if inventory then
				for _, item in ipairs(inventory:GetChildren()) do
					if item:IsA("StringValue") then
						local quantity = item:FindFirstChild("Quantity")
						local rarity = item:FindFirstChild("Rarity")
						local image = item:FindFirstChild("Image")

						InventoryInfo[item.Name] = {
							Quantity = quantity and quantity.Value or 0,
							Rarity = rarity and rarity.Value or "Unknown",
							Image = image and image.Value or "",
						}
					end
				end
			end
			break
		end
	end

	return InventoryInfo
end


return GetPlayerInfo