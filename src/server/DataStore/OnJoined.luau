local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local PlayerResettedRemote = RS:WaitForChild("Remotes"):WaitForChild("StartGameClient"):WaitForChild("PlayerResetted")



local MainGameModule = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("MainGame"))
local test = require(script.Parent:WaitForChild("InventoryHandler"))
local VIPService = require(script.Parent.Parent:WaitForChild("ServicesHandler"):WaitForChild("VIPService"))
local ProfileManager = require(script.Parent:WaitForChild("ProfileManager"))
local Leaderboards = require(script.Parent:WaitForChild("LeaderboardsHandler"))

local DefaultKeybinds = require(RS:WaitForChild("KeyBinds"):WaitForChild("DefaultKeybinds"))
local KeybindValidation = require(RS:WaitForChild("KeyBinds"):WaitForChild("KeybindValidation"))
local RevolversInfo = require(RS:WaitForChild("Modules"):WaitForChild("RevolversInfo"))

local DEFAULT_REVOLVER = "White&Black Revolver"

-- Backward-compatible wrapper so other modules can still call OnJoined.SavePlayerData(player)
local function savePlayerData(player)
	ProfileManager.SaveProfile(player)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.delay(1, function()
			local character = player.Character
			local forceField = character and character:FindFirstChildOfClass("ForceField")
			if forceField then
				forceField:Destroy()
			end
		end)

		if MainGameModule.GameActive then
			PlayerResettedRemote:FireClient(player)
		else
		end
		local character = player.Character
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			MainGameModule.OnDeath(player)
		end)
	end)
	


	-- === leaderstats scaffold ===
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local Kills = Instance.new("IntValue")
	Kills.Name = "Kills"
	Kills.Parent = leaderstats

	local Deaths = Instance.new("IntValue")
	Deaths.Name = "Deaths"
	Deaths.Parent = leaderstats

	local Wins = Instance.new("IntValue")
	Wins.Name = "Wins"
	Wins.Parent = leaderstats

	local WinStreak = Instance.new("IntValue")
	WinStreak.Name = "WinStreak"
	WinStreak.Parent = leaderstats

	local XP = Instance.new("IntValue")
	XP.Name = "XP"
	XP.Parent = leaderstats

	local EquippedKnife = Instance.new("StringValue")
	EquippedKnife.Value = "Shadow Dagger"
	EquippedKnife.Name = "EquippedKnife"
	EquippedKnife.Parent = leaderstats

	local EquippedGun = Instance.new("StringValue")
	EquippedGun.Name = "EquippedGun"
	EquippedGun.Parent = leaderstats

	local Cash = Instance.new("IntValue")
	Cash.Name = "Cash"
	Cash.Parent = leaderstats

	local PlayersInventory = Instance.new("Folder")
	PlayersInventory.Name = "Inventory"
	PlayersInventory.Parent = leaderstats

	local RevolverInventory = Instance.new("Folder")
	RevolverInventory.Name = "RevolverInventory"
	RevolverInventory.Parent = leaderstats

	local Settings = Instance.new("Folder")
	Settings.Name = "Settings"
	Settings.Parent = leaderstats

	local MusicSetting = Instance.new("BoolValue")
	MusicSetting.Name = "Music"
	MusicSetting.Value = true
	MusicSetting.Parent = Settings

	local DaySetting = Instance.new("BoolValue")
	DaySetting.Name = "Day"
	DaySetting.Parent = Settings

	local LobbySetting = Instance.new("BoolValue")
	LobbySetting.Name = "LobbyMode"
	LobbySetting.Parent = Settings

	local Notifications = Instance.new("BoolValue")
	Notifications.Name = "Notifications"
	Notifications.Parent = Settings

	local Trades = Instance.new("BoolValue")
	Trades.Name = "Trades"
	Trades.Parent = Settings


	local Emotes = Instance.new("Folder")
	Emotes.Name = "Emotes"
	Emotes.Parent = leaderstats

	-- DailyRewards folder in leaderstats
	local DailyRewardsFolder = Instance.new("Folder")
	DailyRewardsFolder.Name = "DailyRewards"
	DailyRewardsFolder.Parent = leaderstats

	local LastClaimTimeValue = Instance.new("IntValue")
	LastClaimTimeValue.Name = "LastClaimTime"
	LastClaimTimeValue.Value = 0
	LastClaimTimeValue.Parent = DailyRewardsFolder

	local StreakValue = Instance.new("IntValue")
	StreakValue.Name = "Streak"
	StreakValue.Value = 0
	StreakValue.Parent = DailyRewardsFolder
	
	
	
	
	
	local KeyBinds = Instance.new("Folder")
	KeyBinds.Name = "KeyBinds"
	KeyBinds.Parent = leaderstats
	
	
	for action, keyCode in pairs(DefaultKeybinds) do
		local bind = Instance.new("StringValue")
		bind.Name = action
		bind.Value = keyCode
		bind.Parent = KeyBinds
	end
	


	-- Load player data via ProfileStore (session-locked, auto-saving)
	local profile = ProfileManager.LoadProfile(player)

	if profile then
		local data = profile.Data



		Kills.Value = data.Kills or 0
		Deaths.Value = data.Deaths or 0
		XP.Value = data.XP or 0
		Cash.Value = data.Cash or 0
		Wins.Value = data.Wins or 0
		WinStreak.Value = data.WinStreak or 0
		EquippedKnife.Value = data.EquippedKnife or "Shadow Dagger"
		EquippedGun.Value = data.EquippedGun or DEFAULT_REVOLVER

		local vipExpiresAt = 0
		if data.VIP and type(data.VIP) == "table" then
			vipExpiresAt = tonumber(data.VIP.ExpiresAt) or 0
			VIPService.ApplyToPlayer(player, vipExpiresAt)
			VIPService.SetCachedExpiry(player.UserId, vipExpiresAt)
		else
			VIPService.RefreshPlayer(player)
		end
		
		

		-- Load settings
		if data.Settings and type(data.Settings) == "table" then
			if data.Settings.DaySetting ~= nil then
				DaySetting.Value = data.Settings.DaySetting
			else
				DaySetting.Value = true
			end

			if data.Settings.LobbySetting ~= nil then
				LobbySetting.Value = data.Settings.LobbySetting
			else
				LobbySetting.Value = false
			end

			if data.Settings.Notifications ~= nil then
				Notifications.Value = data.Settings.Notifications
			else
				Notifications.Value = true
			end

			if data.Settings.Trades ~= nil then
				Trades.Value = data.Settings.Trades
			else
				Trades.Value = true
			end
		else
			DaySetting.Value = true
			LobbySetting.Value = false
			Notifications.Value = true
			Trades.Value = true
		end
		
		
		local repairedKeybinds = KeybindValidation.ValidateAndRepair(data.KeyBinds)
		for action, keyName in pairs(repairedKeybinds) do
			local bind = KeyBinds:FindFirstChild(action)
			if bind then
				bind.Value = keyName
			end
		end
		data.KeyBinds = repairedKeybinds
		

		-- Load inventory
		if data.Inventory and type(data.Inventory) == "table" then
			for _, knifeData in pairs(data.Inventory) do
				if knifeData.Name then
					local knife = Instance.new("StringValue")
					knife.Name = knifeData.Name
					knife.Parent = PlayersInventory

					local quantity = Instance.new("IntValue")
					quantity.Name = "Quantity"
					quantity.Value = knifeData.Quantity or 1
					quantity.Parent = knife

					local rarity = Instance.new("StringValue")
					rarity.Name = "Rarity"
					rarity.Value = knifeData.Rarity or "unknown"
					rarity.Parent = knife

					local ImageItem = Instance.new("StringValue")
					ImageItem.Name = "Image"
					ImageItem.Value = knifeData.Image or "422523523"
					ImageItem.Parent = knife

					local tradeable = Instance.new("BoolValue")
					tradeable.Name = "Tradeable"
					if knifeData.Tradeable ~= nil then
						tradeable.Value = knifeData.Tradeable == true
					else
						tradeable.Value = knifeData.Name ~= "Shadow Dagger"
					end
					tradeable.Parent = knife
				end
			end
		end

		local function createRevolverEntry(revolverName: string, revolverData: any)
			if RevolverInventory:FindFirstChild(revolverName) then
				return
			end
			local info = RevolversInfo[revolverName]
			local rarity = (revolverData and revolverData.Rarity) or (info and info.Rarity) or "Common"
			if type(rarity) ~= "string" or rarity == "" then
				rarity = "Common"
			end
			local image = (revolverData and revolverData.Image) or (info and info.Image) or ""
			local tradeable = revolverName ~= DEFAULT_REVOLVER and revolverData and revolverData.Tradeable == true

			local revolver = Instance.new("StringValue")
			revolver.Name = revolverName
			revolver.Parent = RevolverInventory

			local quantity = Instance.new("IntValue")
			quantity.Name = "Quantity"
			quantity.Value = math.max(1, tonumber(revolverData and revolverData.Quantity) or 1)
			quantity.Parent = revolver

			local rarityValue = Instance.new("StringValue")
			rarityValue.Name = "Rarity"
			rarityValue.Value = rarity
			rarityValue.Parent = revolver

			local imageValue = Instance.new("StringValue")
			imageValue.Name = "Image"
			imageValue.Value = image
			imageValue.Parent = revolver

			local tradeableValue = Instance.new("BoolValue")
			tradeableValue.Name = "Tradeable"
			tradeableValue.Value = tradeable
			tradeableValue.Parent = revolver

			revolver:SetAttribute("Rarity", rarity)
			revolver:SetAttribute("Image", image)
			revolver:SetAttribute("Tradeable", tradeable)
		end

		if data.RevolverInventory and type(data.RevolverInventory) == "table" then
			for key, revolverData in pairs(data.RevolverInventory) do
				if type(revolverData) == "table" then
					local revolverName = revolverData.Name or (type(key) == "string" and key or nil)
					if revolverName and revolverName ~= "" then
						createRevolverEntry(revolverName, revolverData)
					end
				end
			end
		end

		if not RevolverInventory:FindFirstChild(DEFAULT_REVOLVER) then
			createRevolverEntry(DEFAULT_REVOLVER, {
				Quantity = 1,
				Rarity = RevolversInfo[DEFAULT_REVOLVER] and RevolversInfo[DEFAULT_REVOLVER].Rarity,
				Image = RevolversInfo[DEFAULT_REVOLVER] and RevolversInfo[DEFAULT_REVOLVER].Image,
				Tradeable = false,
			})
		end

		if EquippedGun.Value == "" or not RevolverInventory:FindFirstChild(EquippedGun.Value) then
			EquippedGun.Value = DEFAULT_REVOLVER
		end

		-- Load emotes
		if data.Emotes and type(data.Emotes) == "table" then
			for _, emoteData in ipairs(data.Emotes) do
				if emoteData.Name then
					local emote = Instance.new("StringValue")
					emote.Name = emoteData.Name
					emote.Value = emoteData.EmoteId or emoteData.Value or "" 
					emote.Parent = Emotes

					local quantity = Instance.new("IntValue")
					quantity.Name = "Quantity"
					quantity.Value = emoteData.Quantity or 1
					quantity.Parent = emote

					local rarity = Instance.new("StringValue")
					rarity.Name = "Rarity"
					rarity.Value = emoteData.Rarity or "Common"
					rarity.Parent = emote

				end

				-- Push freshly loaded stats to leaderboards immediately (avoids initial zero write)
				Leaderboards.UpdatePlayer(player)
			end
		end

		   -- Load daily rewards
			  if data.DailyRewards and type(data.DailyRewards) == "table" then
				  local lastClaimTime = data.DailyRewards.LastClaimTime or 0
				  local streak = data.DailyRewards.Streak or 0
				  player:SetAttribute("DailyLastClaimTime", lastClaimTime)
				  player:SetAttribute("DailyStreak", streak)
				  -- Set IntValues in leaderstats
				  local drFolder = leaderstats:FindFirstChild("DailyRewards")
				  if drFolder then
					  local lct = drFolder:FindFirstChild("LastClaimTime")
					  local stv = drFolder:FindFirstChild("Streak")
					  if lct then lct.Value = lastClaimTime end
					  if stv then stv.Value = streak end
				  end
			  else
				  player:SetAttribute("DailyLastClaimTime", 0)
				  player:SetAttribute("DailyStreak", 0)
				  local drFolder = leaderstats:FindFirstChild("DailyRewards")
				  if drFolder then
					  local lct = drFolder:FindFirstChild("LastClaimTime")
					  local stv = drFolder:FindFirstChild("Streak")
					  if lct then lct.Value = 0 end
					  if stv then stv.Value = 0 end
				  end
			  end

		if data.LastRound and type(data.LastRound) == "table" then
			player:SetAttribute("LastRoundOpponents", data.LastRound.Opponents or 0)
			player:SetAttribute("LastRoundKills", data.LastRound.Kills or 0)
			player:SetAttribute("LastRoundPlacement", data.LastRound.Placement or 0)
		else
			player:SetAttribute("LastRoundOpponents", 0)
			player:SetAttribute("LastRoundKills", 0)
			player:SetAttribute("LastRoundPlacement", 0)
		end

		-- If this is the first session ever (new player with migrated-or-default data),
		-- give the starter knife if inventory is empty
		if #data.Inventory == 0 then
			test.AddKnife(player, "Shadow Dagger", false)
		end
	else
		-- Profile failed to load (player was kicked by ProfileManager)
		return
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ProfileManager.EndSession(player)
	MainGameModule.PlayersInGame[player.UserId] = nil
end)

return {
	SavePlayerData = savePlayerData
}
