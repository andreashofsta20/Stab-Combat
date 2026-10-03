-- Weapon GUI cursor images. A white dot can also display without an image.
-- WhiteDot settings are shared by the knife and revolver HUDs.
return {
	Enabled = true,
	WhiteDotEnabled = true,
	WhiteDotSize = 5,
	HideInMenus = true,
	ShowOnTouch = true,
	-- ShowOnTouch affects image cursors; the knife white dot also appears on touch.
	-- GUI image size. Native pointer is hidden while a weapon cursor is shown.
	HiddenMouseSize = 32,
	Knife = {
		Image = "rbxassetid://92817416767688",
	},
	Revolver = {
		Equipped = { Image = "rbxassetid://92817416767688" },
		Aiming = { Image = "rbxassetid://92817416767688" },
	},
}
