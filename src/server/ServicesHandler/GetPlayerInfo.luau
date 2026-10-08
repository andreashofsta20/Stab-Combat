local GetPlayerInfo = {}

local Players = game:GetService("Players")
local ProfileManager = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("ProfileManager"))

local function savedInventory(data)
	local inventory = {}
	if type(data) ~= "table" or type(data.Inventory) ~= "table" then return inventory end
	for _, item in pairs(data.Inventory) do
		if type(item) ~= "table" or type(item.Name) ~= "string" or item.Name == "" then continue end
		local quantity = if item.Quantity == nil then 1 else item.Quantity
		if type(quantity) ~= "number" or quantity ~= quantity or quantity <= 0
			or quantity == math.huge or quantity % 1 ~= 0 then continue end
		-- Display only; never repair or rewrite the saved inventory in a view request.
		if inventory[item.Name] then continue end
		inventory[item.Name] = {
			Quantity = quantity,
			Rarity = type(item.Rarity) == "string" and item.Rarity or "Unknown",
			Image = type(item.Image) == "string" and item.Image or "",
			Tradeable = if type(item.Tradeable) == "boolean" then item.Tradeable else item.Name ~= "Bowie",
		}
	end
	return inventory
end

-- Both response sections come from this read; the second return is inventory.
function GetPlayerInfo.AllInfo(UserId : number)
	local InfoTable = {}
	local foundPlayer = Players:GetPlayerByUserId(UserId)

	-- Try to get saved data (for RoundHistory, offline fallback, etc.)
	local dataFromStore = nil
	if foundPlayer then
		if foundPlayer:GetAttribute("DataReady") ~= true then return { UserId = UserId, Name = foundPlayer.Name, Loading = true }, {} end
		-- Local profiles already contain round history. Viewing a local player
		-- must not spend DataStore budget or wait for a stale saved snapshot.
		dataFromStore = ProfileManager.GetProfileData(foundPlayer)
	else
		local ok, profileObj = pcall(ProfileManager.GetAsync, UserId)
		if ok and type(profileObj) == "table" and type(profileObj.Data) == "table" then
			dataFromStore = profileObj.Data
		else
			-- Fallback: player may not have migrated yet.
			local legacyOK, legacy = pcall(ProfileManager.GetOldDataAsync, UserId)
			if legacyOK and type(legacy) == "table" then dataFromStore = legacy end
		end
	end

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
				GameMode = player:GetAttribute("LastRoundGameMode") or "FFA",
			}
			if lastRound.Opponents ~= nil or lastRound.Kills ~= nil or lastRound.Placement ~= nil then
				InfoTable.LastRound = lastRound
			end
			-- Always use DataStore RoundHistory if available
			if dataFromStore and type(dataFromStore.RoundHistory) == "table" then
				InfoTable.RoundHistory = dataFromStore.RoundHistory
			end
			break 
		end
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
					GameMode = dataFromStore.LastRound.GameMode or "FFA",
				}
			end

			if dataFromStore.RoundHistory and type(dataFromStore.RoundHistory) == "table" then
				InfoTable.RoundHistory = dataFromStore.RoundHistory
			end
		else
			InfoTable.UserId = UserId
			InfoTable.Unavailable = true
			local okName, name = pcall(function()
				return Players:GetNameFromUserIdAsync(UserId)
			end)
			InfoTable.Name = okName and name or "Player"
		end
	end

	return InfoTable, if foundPlayer then GetPlayerInfo.Inventory(UserId) else savedInventory(dataFromStore)
end



function GetPlayerInfo.Inventory(UserId : number)
	if not Players:GetPlayerByUserId(UserId) then
		local _, inventory = GetPlayerInfo.AllInfo(UserId)
		return inventory
	end
	local InventoryInfo = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == UserId then
			if player:GetAttribute("DataReady") ~= true then return InventoryInfo end
			local stats = player:FindFirstChild("leaderstats")
			local inventory = stats and stats:FindFirstChild("Inventory")
			if inventory then
				for _, item in ipairs(inventory:GetChildren()) do
					if item:IsA("StringValue") then
						local quantity = item:FindFirstChild("Quantity")
						local rarity = item:FindFirstChild("Rarity")
						local image = item:FindFirstChild("Image")
						local tradeable = item:FindFirstChild("Tradeable")

						InventoryInfo[item.Name] = {
							Quantity = quantity and quantity.Value or 0,
							Rarity = rarity and rarity.Value or "Unknown",
							Image = image and image.Value or "",
							Tradeable = if tradeable and tradeable:IsA("BoolValue") then tradeable.Value else true,
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
