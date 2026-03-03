local Module = {}
local MarketplaceService = game:GetService("MarketplaceService")
local IncreasedXPGamepassId = 1733058985
function Module.XpReward(player: Player, action: string, totalPlayers: number?)
	if not player then return 0 end
	local xp = 0
	local xpValue = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("XP")
	if not xpValue then return 0 end

	if action == "kill" then
		xp = 25
		if player:GetAttribute("HasVIP") == true then
			xp += 10
		end
	elseif action == "win" then
		local baseWin = 100
		if totalPlayers then
			if totalPlayers > 10 then
				xp = baseWin + 300
			elseif totalPlayers > 5 then
				xp = baseWin + 150
			elseif totalPlayers > 2 then
				xp = baseWin + 50
			else
				xp = baseWin
			end
		else
			xp = baseWin
		end
	elseif action == "lose" then
		xp = 15
	end

	if MarketplaceService:UserOwnsGamePassAsync(player.UserId, IncreasedXPGamepassId) then
		xp = math.floor(xp * 1.5)
	end
	xpValue.Value += xp
	return xp
end

function Module.CashReward(player: Player, action: string, totalPlayers: number?)
	if not player then return 0 end
	local cash = 0
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if not cashValue then return 0 end

	if action == "kill" then
		cash = 50
		if player:GetAttribute("HasVIP") == true then
			cash += 10
		end
	elseif action == "win" then
		local baseWin = 200
		if totalPlayers then
			if totalPlayers > 10 then
				cash = baseWin + 500
			elseif totalPlayers > 5 then
				cash = baseWin + 250
			elseif totalPlayers > 2 then
				cash = baseWin + 100
			else
				cash = baseWin
			end
		else
			cash = baseWin
		end
	elseif action == "lose" then
		cash = 25
	end

	cashValue.Value += cash
	return cash
end

return Module
