local Weight = {}

function Weight.PickRarity(percentages)
	local totalWeight = 0

	for _, weight in pairs(percentages) do
		totalWeight += weight
	end

	local randomNumber = math.random() * totalWeight
	local currentWeight = 0

	for rarity, weight in pairs(percentages) do
		currentWeight += weight
		if randomNumber <= currentWeight then
			return rarity
		end
	end
end

return Weight