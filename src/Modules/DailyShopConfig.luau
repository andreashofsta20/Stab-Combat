-- Shared presentation/configuration; only the server decides offers and purchases.
return {
	Enabled = true,
	Version = 2, -- Increment when changing the catalog, slots, prices or reset schedule.
	Seed = 74129,
	ResetSeconds = 86400,
	ResetOffsetSeconds = 0, -- 00:00 UTC; independent of server/player timezone.
	RequestCooldown = 1,
	PurchaseCooldown = 0.75,
	-- Direct purchases cost more than a case because the reward is guaranteed.
	RarityDefaults = {
		Knife = {
			Common = {Price = 650, MinLevel = 0}, Rare = {Price = 2200, MinLevel = 3},
			Epic = {Price = 5500, MinLevel = 8}, Legendary = {Price = 15000, MinLevel = 15},
		},
		Revolver = {
			Common = {Price = 500, MinLevel = 0}, Rare = {Price = 1400, MinLevel = 3},
			Epic = {Price = 3000, MinLevel = 8}, Legendary = {Price = 6500, MinLevel = 15},
		},
	},
	-- Explicit allowlist: new weapon definitions do not silently enter the shop.
	-- Entries may override Price/MinLevel or use Enabled = false.
	Items = {
		Knife = {
			Bowie = {}, ["Gut Knife"] = {}, Karambit = {}, Huntsman = {}, Flip = {},
			Skeleton = {}, Butterfly = {}, Bayonet = {},
		},
		Revolver = {
			["Normal Revolver"] = {}, ["Amber Revolver"] = {}, ["Aurum Revolver"] = {},
			["Azure Revolver"] = {}, ["Berserk Revolver"] = {}, ["Frostbite Revolver"] = {},
			["Glacial Revolver"] = {}, ["Honeyed Revolver"] = {}, ["Onyx Revolver"] = {},
			["Blossom Revolver"] = {}, ["Camo Revolver"] = {}, ["Cosmic Revolver"] = {},
			["Grim Revolver"] = {}, ["Mystic Revolver"] = {}, ["Nebula Revolver"] = {},
			["Radiant Revolver"] = {}, ["Sapphire Revolver"] = {}, ["Seraph Revolver"] = {},
			["Blaze Revolver"] = {}, ["Crimson Revolver"] = {}, ["Dragon Scale Revolver"] = {},
			["Hellfire Revolver"] = {}, ["Phantom Revolver"] = {}, ["Royal Revolver"] = {},
			["Void Revolver"] = {},
		},
	},
	Slots = {
		-- Offers 1..3 use SmallItemTemplate in Daily.Others.
		-- Offers 4..5 use LargeItemTemplate in Daily.Main.
		{ItemType = "Knife", Rarities = {"Common"}},
		{ItemType = "Revolver", Rarities = {"Common", "Rare"}},
		{ItemType = "Knife", Rarities = {"Rare"}},
		{ItemType = "Knife", Rarities = {"Epic", "Legendary"}},
		{ItemType = "Revolver", Rarities = {"Epic", "Legendary"}},
	},
	-- Reuse ShopGUI's existing PurchaseGoldRemote for these tagged messages.
	Protocol = {Request = "REQUEST_DAILY_SHOP", Buy = "BUY_DAILY_ITEM", Response = "DAILY_SHOP"},
	UI = {
		-- The layout and field references are passed explicitly by ShopGUI.
		-- Only look for existing controls here; the client never makes UI.
		BuyNames = {"Buy", "BuyButton", "Purchase"},
		LevelLabels = {"LevelRequirement", "RequiredLevel", "Level"},
		TimerNames = {"ResetTimer", "ResetsIn", "Countdown", "Timer"},
		StatusNames = {"ShopStatus", "Status"},
	},
}
