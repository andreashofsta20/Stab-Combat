--[[
	ProfileManager.luau
	Manages player data profiles using ProfileStore for session-locking and auto-saving.
	Value objects in leaderstats are kept for client replication.
	Profile.Data is synced from Value objects before each save via Profile.OnSave.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local ProfileManager = {}
local KeybindValidation = require(game:GetService("ReplicatedStorage"):WaitForChild("KeyBinds"):WaitForChild("KeybindValidation"))

local STORE_NAME = "PlayerData_v1.0.0_MainData"
local OLD_STORE_NAME = "PlayerData_v1.0.0_OldData"

local TutorialRemotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Tutorial")
local StartTutorialRemote = TutorialRemotes:WaitForChild("StartTutorial")

local PROFILE_TEMPLATE = {
	Name = "",
	DisplayName = "",
	Kills = 0,
	Deaths = 0,
	Wins = 0,
	WinStreak = 0,
	XP = 150,
	Cash = 250,
	EquippedKnife = "Shadow Dagger",
	Settings = {
		MusicSetting = true,
		LobbySetting = false,
		Notifications = true,
		Trades = true,
	},
	Inventory = {},
	Emotes = {},
	KeyBinds = {},
	DailyRewards = {
		LastClaimTime = 0,
		Streak = 0,
	},
	VIP = {
		HasVIP = false,
		ExpiresAt = 0,
	},
	FirstTimePlaying = false,
}

local PlayerStore = ProfileStore.New(STORE_NAME, PROFILE_TEMPLATE)

local Profiles: {[Player]: any} = {}

-- Serialize all Value objects in leaderstats into Profile.Data.
-- Called automatically before every ProfileStore save via Profile.OnSave.
local function syncValueObjectsToProfile(player: Player, profile: any)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	if not profile:IsActive() then return end

	local data = profile.Data

	data.Name = player.Name
	data.DisplayName = player.DisplayName
	data.Kills = leaderstats:FindFirstChild("Kills") and leaderstats.Kills.Value or data.Kills
	data.Deaths = leaderstats:FindFirstChild("Deaths") and leaderstats.Deaths.Value or data.Deaths
	data.Wins = leaderstats:FindFirstChild("Wins") and leaderstats.Wins.Value or data.Wins
	data.WinStreak = leaderstats:FindFirstChild("WinStreak") and leaderstats.WinStreak.Value or data.WinStreak
	data.XP = leaderstats:FindFirstChild("XP") and leaderstats.XP.Value or data.XP
	data.Cash = leaderstats:FindFirstChild("Cash") and leaderstats.Cash.Value or data.Cash
	data.EquippedKnife = leaderstats:FindFirstChild("EquippedKnife") and leaderstats.EquippedKnife.Value or data.EquippedKnife

	-- Settings
	local settingsFolder = leaderstats:FindFirstChild("Settings")
	if settingsFolder then
		data.Settings = {
			MusicSetting = settingsFolder:FindFirstChild("Music") and settingsFolder.Music.Value,
			LobbySetting = settingsFolder:FindFirstChild("LobbyMode") and settingsFolder.LobbyMode.Value,
			Notifications = settingsFolder:FindFirstChild("Notifications") and settingsFolder.Notifications.Value,
			Trades = settingsFolder:FindFirstChild("Trades") and settingsFolder.Trades.Value,
		}
		-- Nil guard for settings (defaults)
		if data.Settings.MusicSetting == nil then data.Settings.MusicSetting = true end
		if data.Settings.LobbySetting == nil then data.Settings.LobbySetting = false end
		if data.Settings.Notifications == nil then data.Settings.Notifications = true end
		if data.Settings.Trades == nil then data.Settings.Trades = true end
	end

	-- Inventory
	local inventoryFolder = leaderstats:FindFirstChild("Inventory")
	local inventoryData = {}
	if inventoryFolder then
		for _, knife in pairs(inventoryFolder:GetChildren()) do
			local quantity = knife:FindFirstChild("Quantity")
			local rarity = knife:FindFirstChild("Rarity")
			local image = knife:FindFirstChild("Image")
			local tradeable = knife:FindFirstChild("Tradeable")
			table.insert(inventoryData, {
				Name = knife.Name,
				Quantity = quantity and quantity.Value or 1,
				Rarity = rarity and rarity.Value or "Common",
				Image = image and image.Value or "1",
				Tradeable = tradeable and tradeable.Value or (knife.Name ~= "Shadow Dagger"),
			})
		end
	end
	data.Inventory = inventoryData

	-- Emotes
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
	data.Emotes = emotesData

	-- KeyBinds
	local keybindsFolder = leaderstats:FindFirstChild("KeyBinds")
	local keybindsData = KeybindValidation.GetDefaults()
	if keybindsFolder then
		local rawKeybinds = {}
		for _, action in ipairs(KeybindValidation.GetActions()) do
			local bind = keybindsFolder:FindFirstChild(action)
			if bind and bind:IsA("StringValue") then
				rawKeybinds[action] = bind.Value
			end
		end
		keybindsData = KeybindValidation.ValidateAndRepair(rawKeybinds)
	end
	data.KeyBinds = keybindsData

	-- DailyRewards
	local drFolder = leaderstats:FindFirstChild("DailyRewards")
	if drFolder then
		local lct = drFolder:FindFirstChild("LastClaimTime")
		local stv = drFolder:FindFirstChild("Streak")
		data.DailyRewards = {
			LastClaimTime = lct and lct.Value or 0,
			Streak = stv and stv.Value or 0,
		}
	end

	-- VIP (from player attributes)
	data.VIP = {
		HasVIP = player:GetAttribute("HasVIP") == true,
		ExpiresAt = tonumber(player:GetAttribute("VIPExpiresAt")) or 0,
	}

	-- LastRound (from player attributes)
	local placement = tonumber(player:GetAttribute("LastRoundPlacement")) or 0
	if placement > 0 then
		data.LastRound = data.LastRound or {}
		data.LastRound.Opponents = tonumber(player:GetAttribute("LastRoundOpponents")) or 0
		data.LastRound.Kills = tonumber(player:GetAttribute("LastRoundKills")) or 0
		data.LastRound.Placement = placement
	end
end

-- Copy fields from old raw DataStore save into Profile.Data
local function migrateOldData(profile: any, oldData: {[string]: any})
	local data = profile.Data

	data.Name = oldData.Name or data.Name
	data.DisplayName = oldData.DisplayName or data.DisplayName
	data.Kills = oldData.Kills or data.Kills
	data.Deaths = oldData.Deaths or data.Deaths
	data.Wins = oldData.Wins or data.Wins
	data.WinStreak = oldData.WinStreak or data.WinStreak
	data.XP = oldData.XP or data.XP
	data.Cash = oldData.Cash or data.Cash
	data.EquippedKnife = oldData.EquippedKnife or data.EquippedKnife

	if type(oldData.Settings) == "table" then
		data.Settings = {
			MusicSetting = if oldData.Settings.MusicSetting ~= nil then oldData.Settings.MusicSetting else true,
			LobbySetting = if oldData.Settings.LobbySetting ~= nil then oldData.Settings.LobbySetting else false,
			Notifications = if oldData.Settings.Notifications ~= nil then oldData.Settings.Notifications else true,
			Trades = if oldData.Settings.Trades ~= nil then oldData.Settings.Trades else true,
		}
	end

	if type(oldData.Inventory) == "table" then
		data.Inventory = oldData.Inventory
	end

	if type(oldData.Emotes) == "table" then
		data.Emotes = oldData.Emotes
	end

	if type(oldData.KeyBinds) == "table" then
		data.KeyBinds = oldData.KeyBinds
	end

	if type(oldData.DailyRewards) == "table" then
		data.DailyRewards = {
			LastClaimTime = oldData.DailyRewards.LastClaimTime or 0,
			Streak = oldData.DailyRewards.Streak or 0,
		}
	end

	if type(oldData.VIP) == "table" then
		data.VIP = {
			HasVIP = oldData.VIP.HasVIP == true,
			ExpiresAt = tonumber(oldData.VIP.ExpiresAt) or 0,
		}
	end

	if type(oldData.LastRound) == "table" then
		data.LastRound = oldData.LastRound
	end

	if type(oldData.RoundHistory) == "table" then
		data.RoundHistory = oldData.RoundHistory
	end

	print("[ProfileManager] Migrated old data for", profile.Key)
end

function ProfileManager.GetProfile(player: Player): any?
	return Profiles[player]
end

function ProfileManager.GetProfileData(player: Player): {[string]: any}?
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

-- Start a profile session. Returns the Profile or nil on failure.
function ProfileManager.LoadProfile(player: Player): any?
	local profile = PlayerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Failed to load your data. Please rejoin.")
		return nil
	end

	profile:AddUserId(player.UserId) -- GDPR compliance
	profile:Reconcile() -- Fill in any missing template fields

	-- One-time migration from old raw DataStore
	if profile.SessionLoadCount == 1 then
		local oldStore = DataStoreService:GetDataStore(OLD_STORE_NAME)
		local success, oldData = pcall(function()
			return oldStore:GetAsync(tostring(player.UserId))
		end)
		if success and type(oldData) == "table" then
			migrateOldData(profile, oldData)
		end
	end

	-- Before every save, sync Value objects → Profile.Data
	profile.OnSave:Connect(function()
		syncValueObjectsToProfile(player, profile)
	end)

	-- If another server steals the session, kick the player
	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your data has been loaded on another server. Please rejoin.")
		end
	end)

	-- Check player hasn't left during the async load
	if player.Parent ~= Players then
		profile:EndSession()
		return nil
	end

	Profiles[player] = profile

	
	return profile
end

-- Force an immediate save (e.g. after developer product purchase or round end)
function ProfileManager.SaveProfile(player: Player)
	local profile = Profiles[player]
	if profile and profile:IsActive() then
		syncValueObjectsToProfile(player, profile)
		profile:Save()
	end
end

-- End session cleanly (call on PlayerRemoving)
function ProfileManager.EndSession(player: Player)
	local profile = Profiles[player]
	if profile then
		-- OnSave will fire during EndSession, syncing Value objects automatically
		profile:EndSession()
		Profiles[player] = nil
	end
end

-- Read-only access to a profile for viewing offline player data.
-- Returns a Profile object with .Data, or nil.
function ProfileManager.GetAsync(userId: number): any?
	return PlayerStore:GetAsync(tostring(userId))
end

-- Read-only fallback: try old DataStore for un-migrated players
function ProfileManager.GetOldDataAsync(userId: number): {[string]: any}?
	local oldStore = DataStoreService:GetDataStore(OLD_STORE_NAME)
	local success, data = pcall(function()
		return oldStore:GetAsync(tostring(userId))
	end)
	if success and type(data) == "table" then
		return data
	end
	return nil
end

-- Get the underlying ProfileStore for advanced operations (VersionQuery, etc.)
function ProfileManager.GetStore()
	return PlayerStore
end


StartTutorialRemote.OnServerEvent:Connect(function(player)
    local profile = Profiles[player]
	print(profile)
	print(profile.Data.FirstTimePlaying)
    if profile and profile.Data.FirstTimePlaying == false then
        profile.Data.FirstTimePlaying = true
        StartTutorialRemote:FireClient(player)
    end
end)

return ProfileManager
