local AntiFarm = {}

local MIN_ROUND_PLAYERS_FOR_FULL_REWARDS = 3
local MIN_ROUND_PLAYERS_FOR_WIN_CREDIT = 3

local function clamp(n: number, minV: number, maxV: number): number
	if n < minV then return minV end
	if n > maxV then return maxV end
	return n
end

function AntiFarm.GetRewardPolicy(player: Player, roundParticipants: number, serverPlayerCount: number)
	local rewardMultiplier = 1
	local canReceiveWinCredit = true

	if roundParticipants < MIN_ROUND_PLAYERS_FOR_FULL_REWARDS then
		rewardMultiplier *= 0.25
	end

	if roundParticipants < MIN_ROUND_PLAYERS_FOR_WIN_CREDIT then
		canReceiveWinCredit = false
	end

	local accountAgeDays = tonumber(player.AccountAge) or 0
	if accountAgeDays < 1 then
		rewardMultiplier *= 0
		canReceiveWinCredit = false
	elseif accountAgeDays < 3 then
		rewardMultiplier *= 0.5
		canReceiveWinCredit = false
	elseif accountAgeDays < 7 then
		rewardMultiplier *= 0.8
	end

	if serverPlayerCount > 10 then
		rewardMultiplier *= 1.1
	end

	rewardMultiplier = clamp(rewardMultiplier, 0, 2)

	return {
		RewardMultiplier = rewardMultiplier,
		CanReceiveWinCredit = canReceiveWinCredit,
	}
end

return AntiFarm
