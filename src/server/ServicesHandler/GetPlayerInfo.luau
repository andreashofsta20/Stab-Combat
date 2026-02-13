local GetPlayerInfo = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerStats_v2BETA11")

function GetPlayerInfo.AllInfo(UserId : number)
	local InfoTable = {}
	local foundPlayer = nil

	for _, player in pairs(Players:GetPlayers()) do
		if player.UserId == UserId then
			foundPlayer = player
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

			local lastRound = {
				Opponents = player:GetAttribute("LastRoundOpponents"),
				Kills = player:GetAttribute("LastRoundKills"),
				Placement = player:GetAttribute("LastRoundPlacement"),
			}
			if lastRound.Opponents ~= nil or lastRound.Kills ~= nil or lastRound.Placement ~= nil then
				InfoTable.LastRound = lastRound
			end
			
			break 
		end
	end

	local dataFromStore = nil
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync(UserId)
	end)
	if success and type(data) == "table" then
		dataFromStore = data
	end

	if not foundPlayer then
		if dataFromStore then
			InfoTable.UserId = UserId
			InfoTable.Name = dataFromStore.Name
			InfoTable.DisplayName = dataFromStore.DisplayName
			InfoTable.Kills = dataFromStore.Kills
			InfoTable.Deaths = dataFromStore.Deaths
			InfoTable.XP = dataFromStore.XP
			InfoTable.Cash = dataFromStore.Cash
			InfoTable.Wins = dataFromStore.Wins
			InfoTable.WinStreak = dataFromStore.WinStreak
			InfoTable.EquippedKnife = dataFromStore.EquippedKnife

			if dataFromStore.LastRound and type(dataFromStore.LastRound) == "table" then
				InfoTable.LastRound = {
					Opponents = dataFromStore.LastRound.Opponents,
					Kills = dataFromStore.LastRound.Kills,
					Placement = dataFromStore.LastRound.Placement,
				}
			end

			if dataFromStore.RoundHistory and type(dataFromStore.RoundHistory) == "table" then
				InfoTable.RoundHistory = dataFromStore.RoundHistory
			end
		else
			InfoTable.UserId = UserId
			local okName, name = pcall(function()
				return Players:GetNameFromUserIdAsync(UserId)
			end)
			InfoTable.Name = okName and name or "Player"
		end
	else
		if dataFromStore and type(dataFromStore.RoundHistory) == "table" then
			InfoTable.RoundHistory = dataFromStore.RoundHistory
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