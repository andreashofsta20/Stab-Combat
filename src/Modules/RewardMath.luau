local RewardMath = {}
function RewardMath.IsFinite(value): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
function RewardMath.NonnegativeInteger(value): number
	return RewardMath.IsFinite(value) and math.max(0, math.floor(value)) or 0
end
function RewardMath.NextUtcReset(now: number): number
	return (math.floor(now / 86400) + 1) * 86400
end
function RewardMath.DailyStatus(lastClaim, streak, now, daySeconds, cycle)
	lastClaim, streak = RewardMath.NonnegativeInteger(lastClaim), RewardMath.NonnegativeInteger(streak)
	local nextAt = lastClaim > 0 and lastClaim + daySeconds or now
	local lastIndex = streak > 0 and ((streak - 1) % cycle) + 1 or 0
	local nextIndex = (streak % cycle) + 1
	local claimed = now < nextAt
	return {
		CurrentDayIndex = nextIndex, LastClaimedIndex = lastIndex,
		ClaimedToday = claimed, CanClaim = not claimed,
		RemainingSeconds = math.max(0, nextAt - now), NextClaimAt = nextAt,
		ServerTime = now, Streak = streak,
		CycleClaimedCount = claimed and lastIndex or nextIndex - 1,
	}
end
return RewardMath
