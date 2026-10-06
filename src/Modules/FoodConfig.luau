-- Round supplies are temporary; they never belong in the saved skin inventory.
return table.freeze({
	ToolName = "Burger",
	Capacity = 3,
	HealAmount = 33,
	CooldownMs = 1000,
	RequestBurst = 3,
	RequestsPerSecond = 2,
	Icon = "rbxassetid://111896278734464", -- blank uses ReplicatedStorage.Food.Burger.TextureId
})
