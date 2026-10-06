-- Keep profile/legacy names unchanged. Each profile namespace gets its own
-- ordered-store scope, so an old leaderboard cannot survive a profile reset.
local Config = {
	ProfileStoreName = "PlayerData_v1.0.2_MainData",
	LegacyStoreName = "PlayerData_v1.0.1_OldData",
	MigrateLegacyData = false,
	LeaderboardVersion = "1", -- increment to start fresh boards within this profile namespace
}
function Config.GetLeaderboardScope()
	local scope = Config.ProfileStoreName .. "_boards_" .. Config.LeaderboardVersion
	assert(#scope <= 50, "Leaderboard scope must be at most 50 characters")
	return scope
end
return Config
