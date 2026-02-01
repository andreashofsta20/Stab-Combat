local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local playerDataStore = DataStoreService:GetDataStore("PlayerStats_v2BETA11")
local PlayerResettedRemote = RS:WaitForChild("Remotes"):WaitForChild("StartGameClient"):WaitForChild("PlayerResetted")

local MainGameModule = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("MainGame"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))
local test = require(script.Parent:WaitForChild("InventoryHandler"))


local DefaultKeybinds = require(RS:WaitForChild("KeyBinds"):WaitForChild("DefaultKeybinds"))

-- Function to save player data
local function savePlayerData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		warn("No leaderstats found for", player.Name)
		return
	end

	-- INVENTORY
	local inventoryFolder = leaderstats:FindFirstChild("Inventory")
	local inventoryData = {}

	if inventoryFolder then
		for _, knife in pairs(inventoryFolder:GetChildren()) do
			local quantity = knife:FindFirstChild("Quantity")
			local rarity = knife:FindFirstChild("Rarity")
			local image = knife:FindFirstChild("Image")

			table.insert(inventoryData, {
				Name = knife.Name,
				Quantity = quantity and quantity.Value or 1,
				Rarity = rarity and rarity.Value or "Common",
				Image = image and image.Value or "1"
			})
		end
	end

	-- SETTINGS
	local settingsFolder = leaderstats:FindFirstChild("Settings")
	local settingsData = {
		MusicSetting = true,
		LobbySetting = false,
		Notifications = true
	}

	if settingsFolder then
		local musicValue = settingsFolder:FindFirstChild("Music")
		local lobbyValue = settingsFolder:FindFirstChild("LobbyMode")
		local notifValue = settingsFolder:FindFirstChild("Notifications")

		if musicValue then settingsData.MusicSetting = musicValue.Value end
		if lobbyValue then settingsData.LobbySetting = lobbyValue.Value end
		if notifValue then settingsData.Notifications = notifValue.Value end
	end

	local emotesFolder = leaderstats:FindFirstChild("Emotes")
	local emotesData = {}

	if emotesFolder then
		for _, emote in ipairs(emotesFolder:GetChildren()) do
			if emote:IsA("StringValue") then
				local quantity = emote:FindFirstChild("Quantity")
				local rarity = emote:FindFirstChild("Rarity")

				table.insert(emotesData, {
					Name = emote.Name,
					EmoteId = emote.Value or "",
					Quantity = quantity and quantity.Value or 1,
					Rarity = rarity and rarity.Value or "Common",
				})
			end
		end
	end
	
	local keybindsFolder = leaderstats:WaitForChild("KeyBinds")
	local keybindsData = {}


	if keybindsFolder then
		for _, bind in ipairs(keybindsFolder:GetChildren()) do
			if bind:IsA("StringValue") then
				keybindsData[bind.Name] = bind.Value
			end
		end
	end



	local dataToSave = {
		Kills = leaderstats:FindFirstChild("Kills") and leaderstats.Kills.Value or 0,
		XP = leaderstats:FindFirstChild("XP") and leaderstats.XP.Value or 0,
		Cash = leaderstats:FindFirstChild("Cash") and leaderstats.Cash.Value or 0,
		Deaths = leaderstats:FindFirstChild("Deaths") and leaderstats.Deaths.Value or 0,
		Wins = leaderstats:FindFirstChild("Wins") and leaderstats.Wins.Value or 0,
		EquippedKnife = leaderstats:FindFirstChild("EquippedKnife") and leaderstats.EquippedKnife.Value or "Shadow Dagger",
		Settings = settingsData,
		Inventory = inventoryData,
		Emotes = emotesData,
		KeyBinds = keybindsData,
	}

	print("Saving data for", player.Name, "Settings:", dataToSave.Settings)

	local success, err = pcall(function()
		playerDataStore:SetAsync(player.UserId, dataToSave)
	end)

	if success then
		print("Successfully saved data for", player.Name)
	else
		warn("Failed to save data for", player.Name, ":", err)
	end
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


	local Emotes = Instance.new("Folder")
	Emotes.Name = "Emotes"
	Emotes.Parent = leaderstats
	
	
	
	
	
	local KeyBinds = Instance.new("Folder")
	KeyBinds.Name = "KeyBinds"
	KeyBinds.Parent = leaderstats
	
	
	for action, keyCode in pairs(DefaultKeybinds) do
		local bind = Instance.new("StringValue")
		bind.Name = action
		bind.Value = keyCode.Name
		bind.Parent = KeyBinds
	end
	


	-- Load player data
	local success, data = pcall(function()
		return playerDataStore:GetAsync(player.UserId)
	end)

	if success and data then
		print("Loading data for", player.Name, "Settings:", data.Settings)



		Kills.Value = data.Kills or 0
		Deaths.Value = data.Deaths or 0
		XP.Value = data.XP or 0
		Cash.Value = data.Cash or 0
		Wins.Value = data.Wins or 0
		EquippedKnife.Value = data.EquippedKnife or "Shadow Dagger"
		
		

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
		else
			MusicSetting.Value = true
			LobbySetting.Value = false
			Notifications.Value = true
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
	else
		-- First time player or data failed to load
		print("Setting default values for", player.Name)
		Kills.Value = 0
		XP.Value = 100
		Cash.Value = 1000
		Deaths.Value = 0
		Wins.Value = 0
		MusicSetting.Value = true
		LobbySetting.Value = false
		Notifications.Value = true
		EquippedKnife.Value = "Shadow Dagger"
		test.AddKnife(player, "Shadow Dagger")
		
		
		

		-- OPTIONAL: give default emotes (uncomment & change ids if you want)
		--[[
		local defaultEmotes = {
			Wave = "rbxassetid://123",
			Laugh = "rbxassetid://456"
		}
		for name, value in pairs(defaultEmotes) do
			local emote = Instance.new("StringValue")
			emote.Name = name
			emote.Value = value
			emote.Parent = Emotes
		end
		]]
	end

	-- Auto-save every 5 minutes
	task.spawn(function()
		while player.Parent do
			task.wait(300)
			if player.Parent then
				savePlayerData(player)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	
	MainGameModule.PlayersInGame[player.UserId] = nil
end)

-- Save all players' data when server is shutting down
game:BindToClose(function()
	for _, player in pairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
	task.wait(3) -- Give time for saves to complete
end)

return {}
