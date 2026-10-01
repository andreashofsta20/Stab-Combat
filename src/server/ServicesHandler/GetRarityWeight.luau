local Weight = {}

local rng = Random.new()

-- Weighted rarity pick. Ignores zero/negative/non-numeric weights and
-- always returns a rarity that has positive weight (or nil if none do).
function Weight.PickRarity(percentages)
	local totalWeight = 0
	local lastValid = nil

	for rarity, weight in pairs(percentages) do
		if type(weight) == "number" and weight > 0 then
			totalWeight += weight
			lastValid = rarity
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	local current = 0

	for rarity, weight in pairs(percentages) do
		if type(weight) == "number" and weight > 0 then
			current += weight
			if roll < current then
				return rarity
			end
		end
	end

	return lastValid -- floating point safety net
end

return Weight
