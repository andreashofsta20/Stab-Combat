-- Local death presentation only; round/respawn timing remains server-owned.
return {
	DeathViewSeconds = 1,
	DeathViewEnabled = true,
	DeathViewDistance = 6,
	DeathViewHeight = 1.75,
	DeathViewFocusHeight = 0.3,
	DeathViewPullbackSeconds = 0.16,
	DeathViewCollisionPadding = 0.35,
	DeathViewMinimumDistance = 0.15, -- relaxed if a wall is closer than this
	DeathReplicationWaitSeconds = 1,
	DeathReplicationRetrySeconds = 0.05,
	BRHandoffWaitSeconds = 4, -- maximum wait for replicated elimination membership
	ButtonTweenSeconds = 0.12,
}
