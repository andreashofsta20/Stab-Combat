return {
	LobbyMap = "Cargo Port",
	-- Templates retain their Studio position. Adjust only if your lobby needs it.
	LobbyOffset = { X = 0, Y = 0, Z = 0 },
	MapSwitchDelaySeconds = 3,
	PlacementTimeoutSeconds = 8,
	PlacementRetrySeconds = 0.1,
	SpawnHeight = 4,
	PlacementTolerance = 2,
	StreamingTimeoutSeconds = 3,
	RoundStartProtectionSeconds = 1.5,
	SpawnScoring = {Enabled = true, MaxCandidates = 6, MaxEnemies = 16, DistanceCap = 250, ReuseSeconds = 10},
}
