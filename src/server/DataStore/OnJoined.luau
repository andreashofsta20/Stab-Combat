local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local PlayerResettedRemote = RS:WaitForChild("Remotes"):WaitForChild("StartGameClient"):WaitForChild("PlayerResetted")

local MainGameModule = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("MainGame"))
local test = require(script.Parent:WaitForChild("InventoryHandler"))
local VIPService = require(script.Parent.Parent:WaitForChild("ServicesHandler"):WaitForChild("VIPService"))
local ProfileManager = require(script.Parent:WaitForChild("ProfileManager"))

local DefaultKeybinds = require(RS:WaitForChild("KeyBinds"):WaitForChild("DefaultKeybinds"))

-- Backward-compatible wrapper so other modules can still call OnJoined.SavePlayerData(player)
local function savePlayerData(player)
	ProfileManager.SaveProfile(player)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()

		if MainGameModule.GameActive then
			PlayerResettedRemote:FireClient(player)
		else
			print("Game isn't active")
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

	local Cash = Instance.new("IntValue")
	Cash.Name = "Cash"
	Cash.Parent = leaderstats

	local PlayersInventory = Instance.new("Folder")
	PlayersInventory.Name = "Inventory"
	PlayersInventory.Parent = leaderstats

	local Settings = Instance.new("Folder")
	Settings.Name = "Settings"
	Settings.Parent = leaderstats

	local MusicSetting = Instance.new("BoolValue")
	MusicSetting.Name = "Music"
	MusicSetting.Parent = Settings

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
		bind.Value = keyCode.Name
		bind.Parent = KeyBinds
	end
	


	-- Load player data via ProfileStore (session-locked, auto-saving)
	local profile = ProfileManager.LoadProfile(player)

	if profile then
		local data = profile.Data
		print("Loading data for", player.Name, "Settings:", data.Settings)



		Kills.Value = data.Kills or 0
		Deaths.Value = data.Deaths or 0
		XP.Value = data.XP or 0
		Cash.Value = data.Cash or 0
		Wins.Value = data.Wins or 0
		WinStreak.Value = data.WinStreak or 0
		EquippedKnife.Value = data.EquippedKnife or "Shadow Dagger"

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
			if data.Settings.MusicSetting ~= nil then
				MusicSetting.Value = data.Settings.MusicSetting
			else
				MusicSetting.Value = true
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
			MusicSetting.Value = true
			LobbySetting.Value = false
			Notifications.Value = true
			Trades.Value = true
		end
		
		
		if data.KeyBinds and type(data.KeyBinds) == "table" then
			for action, keyName in pairs(data.KeyBinds) do
				local bind = KeyBinds:FindFirstChild(action)
				if bind then
					bind.Value = keyName
				else
					local newBind = Instance.new("StringValue")
					newBind.Name = action
					newBind.Value = keyName
					newBind.Parent = KeyBinds
				end
			end
		end
		

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
