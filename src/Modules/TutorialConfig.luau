-- Publish identical source/config to both places in the SAME experience.
-- TutorialPlaceId stays 0 until the new place has been created and published.
return {
	Enabled = true,
	Version = 1,
	MainPlaceId = 119874582058419,
	TutorialPlaceId = 119874582058419,
	MapName = "Grids",
	Rewards = {XP = 500, Gold = 500, Knife = "Shadow Dagger"},
	RewardSaveTimeoutSeconds = 20,
	TicketStoreName = "StabTutorialTickets_v1",
	TicketTTLSeconds = 600,
	SessionTimeoutSeconds = 1800,
	DataReadyTimeoutSeconds = 60,
	PreparationTimeoutSeconds = 30,
	AutoReturnSeconds = 8,
	SuccessPauseSeconds = 0.65,
	RequestsPerSecond = 2,
	RequestBurst = 6,
	StartCooldownSeconds = 10,
	SampleSeconds = 0.1,
	ProgressPushSeconds = 0.25,
	Teleport = {MaxAttempts = 4, RetryDelaySeconds = 2, FloodDelaySeconds = 15, WatchdogSeconds = 90},
	Analytics = {Enabled = true, FunnelName = "Tutorial_v1"},
	-- Offline rehearsal uses mock profiles only. It never issues live rewards.
	Studio = {EnableSoloPreview = false},
}
