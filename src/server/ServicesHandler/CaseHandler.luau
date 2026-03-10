-- // SERVICES // --
local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")



-- // MODULES // --
local CaseInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CasesInfo"))
local AbbreviateModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Abbreviate"))
local RarityColorModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))
local InventoryHandler = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("InventoryHandler"))
local GameRewardModule = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("GameReward"))

local GetRarity = require(script.Parent.GetRarityWeight)



-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local CaseOpeningFolder = RemotesFolder:WaitForChild("CaseOpening")
local OpenCaseRemote = CaseOpeningFolder:WaitForChild("OpenCase")
local CaseAnimationClient = CaseOpeningFolder:WaitForChild("CaseAnimationClient")


local MarketplaceService = game:GetService("MarketplaceService")

-- // DEBOUNCE // --

local OnSpinningAnimation: {[number]: boolean} = {}
local lastCaseOpenAt: {[number]: number} = {}
local CASE_OPEN_MIN_GAP = 0.35




OpenCaseRemote.OnServerEvent:Connect(function(player : Player, CaseName : string)
	if not player then return end
	if type(CaseName) ~= "string" then return end
	if #CaseName < 1 or #CaseName > 64 then return end

	local now = os.clock()
	local prev = lastCaseOpenAt[player.UserId]
	if prev and (now - prev) < CASE_OPEN_MIN_GAP then
		return
	end
	lastCaseOpenAt[player.UserId] = now
	
	if OnSpinningAnimation[player.UserId] then
		return NotificationHandler.SendNotification(player, "Debounce", 3, "Error")
	end
	
	if not CaseInfoModule[CaseName] then
		NotificationHandler.SendNotification(player, "Couldn't find case info", 3, "Error")
		return
	end
	
	
	if not CaseName then return end
	
	local CaseInfo = CaseInfoModule[CaseName]
	local cashValue = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	local deducted = false

	local function clearDebounce()
		OnSpinningAnimation[player.UserId] = nil
	end

	local function fail(message: string)
		if deducted and cashValue then
			cashValue.Value += CaseInfo.Price
		end
		clearDebounce()
		NotificationHandler.SendNotification(player, message, 3, "Error")
	end
	
	local DURATATION = 10 

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, 1733042964) 
	end)
	
	local HasSkip = false

	if success and ownsPass then
		HasSkip = true
		DURATATION = 0
	end

	
	

	
	if cashValue then
		if cashValue.Value >= CaseInfo.Price then
			cashValue.Value -= CaseInfo.Price
			deducted = true
			OnSpinningAnimation[player.UserId] = true
		else
			fail("You can't afford this case")
			return
		end
	else
		fail("Couldn't find cash")
		return
	end
	
	
	
	
	
	local chosenRarity = GetRarity.PickRarity(CaseInfo.Percentages)
	
	if not chosenRarity then
		fail("Something wrong happend")
		return
	end
	
	
	
	local SkinsPlayerCanRecieve = {}
	
	for knifeName, skinData in pairs(CaseInfo.Skins) do
		if skinData.Rarity == chosenRarity then
			table.insert(SkinsPlayerCanRecieve, {
				Knife = knifeName;
				Data = skinData;
			})
		end
	end
	
	if #SkinsPlayerCanRecieve == 0 then
		fail("No skins found " .. chosenRarity)
		return
	end
	
	
	local chosenSkin = SkinsPlayerCanRecieve[math.random(1, #SkinsPlayerCanRecieve)]

	

	
	
	-- Grant the item IMMEDIATELY (before animation) to prevent loss on disconnect/crash
	if CaseInfo.EmoteCase == true then
		InventoryHandler.AddEmote(player, tostring(chosenSkin.Knife))
	else
		InventoryHandler.AddKnife(player, tostring(chosenSkin.Knife))
	end
	GameRewardModule.XpReward(player, "case_open")

	CaseAnimationClient:FireClient(player, {
		SkinName = chosenSkin.Data.SkinName;
		Rarity = chosenRarity;
		Image = chosenSkin.Data.Image;
		Knife = chosenSkin.Knife;
		Case = CaseName,
	}, DURATATION, HasSkip, CaseName)

	task.wait(DURATATION + 0.8)

	clearDebounce()
	
	
	
	
	
	
end)

	_Players.PlayerRemoving:Connect(function(player)
		OnSpinningAnimation[player.UserId] = nil
		lastCaseOpenAt[player.UserId] = nil
	end)

return {}