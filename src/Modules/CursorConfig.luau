-- Weapon cursor images. Empty Image restores the normal Roblox cursor.
-- The existing revolver white dot is a separate HUD element and stays visible.
return {
	Enabled = true,
	HideInMenus = true,
	ShowOnTouch = false,
	-- Size of the GUI cursor used when Roblox hides the native pointer (ADS,
	-- first person or gamepad). Native mouse icon size is controlled by Roblox.
	HiddenMouseSize = 32,
	Knife = {
		Image = "rbxassetid://140476432521467",
	},
	Revolver = {
		Equipped = { Image = "rbxassetid://140476432521467" },
		Aiming = { Image = "rbxassetid://140476432521467" },
	},
}
