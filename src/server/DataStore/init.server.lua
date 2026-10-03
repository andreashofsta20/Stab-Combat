require(script.Parent.StartupService).LoadGroup(script, {
	Priority = {"ProfileManager", "OnJoined", "InventoryHandler", "KeyBindHandler", "LeaderboardsHandler"},
})
