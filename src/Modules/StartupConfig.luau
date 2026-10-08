return {
	ModulesPerFrame = 2,
	SlowModuleWarningSeconds = 10,
	AssetWaitSeconds = 10,
	ReadyTimeoutSeconds = 30,
	OptionalServerModules = {
		ServicesHandler = {"GetPlayerInfo", "ProfileViewHandler", "VIPHandler", "GameUpdateHandler", "ReceiptMaintenance", "BetaMetrics"},
	},
	RequiredServerGroups = {"DataStore", "CombatHandler", "Game", "ServicesHandler", "Trading"},
}
