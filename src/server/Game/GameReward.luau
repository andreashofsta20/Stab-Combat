local Module = {}
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local IncreasedXPGamepassId = 1733058985
local xpPass = {}
local function ownsXpPass(player)
    if xpPass[player] ~= nil then return xpPass[player] end
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, IncreasedXPGamepassId)
    end)
    if ok and player.Parent == Players then xpPass[player] = xpPass[player] == true or owns == true end
    return xpPass[player] == true or (ok and owns == true)
end
Players.PlayerAdded:Connect(function(player) task.spawn(ownsXpPass, player) end)
Players.PlayerRemoving:Connect(function(player) xpPass[player] = nil end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
    if passId == IncreasedXPGamepassId and purchased then xpPass[player] = true end
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(ownsXpPass, player) end
function Module.XpReward(player: Player, action: string, totalPlayers: number?, rewardMultiplier: number?)
	if not player or player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return 0 end
	local xp = 0
	local xpValue = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("XP")
	if not xpValue then return 0 end

	if action == "kill" then
		xp = 25
		if player:GetAttribute("HasVIP") == true then
			xp += 10
		end
	elseif action == "win" then
		local baseWin = 175
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
	elseif action == "case_open" then
		xp = 20
	end

    if xp <= 0 or (type(rewardMultiplier) == "number" and rewardMultiplier <= 0) then
		return 0
	end
    if ownsXpPass(player) then xp = math.floor(xp * 1.5) end
    if type(rewardMultiplier) == "number" then xp = math.floor(xp * math.max(0, rewardMultiplier)) end
    -- Ownership lookup can yield on a cache miss. Never mutate a departed
    -- player's old leaderstats/session after it returns.
    if player.Parent ~= Players or player:GetAttribute("DataReady") ~= true or not xpValue.Parent then return 0 end
	xpValue.Value += xp
	return xp
end

function Module.CashReward(player: Player, action: string, totalPlayers: number?, rewardMultiplier: number?)
    if not player or player.Parent ~= Players or player:GetAttribute("DataReady") ~= true then return 0 end
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

	if type(rewardMultiplier) == "number" then
		cash = math.floor(cash * math.max(0, rewardMultiplier))
	end

	if cash <= 0 then
		return 0
	end

	cashValue.Value += cash
	return cash
end

return Module
