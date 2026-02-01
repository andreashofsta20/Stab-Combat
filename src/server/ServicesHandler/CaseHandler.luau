-- // SERVICES // --
local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")



-- // MODULES // --
local CaseInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CasesInfo"))
local AbbreviateModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Abbreviate"))
local RarityColorModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local NotificationHandler = require(script.Parent.Parent:WaitForChild("Game"):WaitForChild("SendNotification"))
local InventoryHandler = require(script.Parent.Parent:WaitForChild("DataStore"):WaitForChild("InventoryHandler"))

local GetRarity = require(script.Parent.GetRarityWeight)



-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local CaseOpeningFolder = RemotesFolder:WaitForChild("CaseOpening")
local OpenCaseRemote = CaseOpeningFolder:WaitForChild("OpenCase")
local CaseAnimationClient = CaseOpeningFolder:WaitForChild("CaseAnimationClient")


local MarketplaceService = game:GetService("MarketplaceService")

-- // DEBOUNCE // --

local OnSpinningAnimation = {
	
	
}




OpenCaseRemote.OnServerEvent:Connect(function(player : Player, CaseName : string)
	
	if OnSpinningAnimation[player] then
		return NotificationHandler.SendNotification(player, "Debounce", 3, "Error")
	end
	
	if not CaseInfoModule[CaseName] then
		NotificationHandler.SendNotification(player, "Couldn't find case info", 3, "Error")
		return
	end
	
	
	if not player then return end
	
	if not CaseName then return end
	
	local CaseInfo = CaseInfoModule[CaseName]
	
	local DURATATION = 10 

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, 1269395072) 
	end)
	
	local HasSkip = false

	if success and ownsPass then
		HasSkip = true
		DURATATION = 3
	end

	
	

	
	if player.leaderstats.Cash then
		if player.leaderstats.Cash.Value >= CaseInfo.Price then
			player.leaderstats.Cash.Value -= CaseInfo.Price
			OnSpinningAnimation[player] = true
		else
			return NotificationHandler.SendNotification(player, "You can't afford this case", 3, "Error")
		end
	else
		NotificationHandler.SendNotification(player, "Couldn't find cash", 3, "Error")
		return
	end
	
	
	
	
	
	local chosenRarity = GetRarity.PickRarity(CaseInfo.Percentages)
	
	if not chosenRarity then
		NotificationHandler.SendNotification(player, "Something wrong happend", 3, "Error")
		return
	end
	
	print(chosenRarity)
	
	
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
		NotificationHandler.SendNotification(player, "No skins found " .. chosenRarity, 3, "Error")
		return
	end
	
	
	local chosenSkin = SkinsPlayerCanRecieve[math.random(1, #SkinsPlayerCanRecieve)]
	
	print(chosenSkin)
	
	

	
	
	CaseAnimationClient:FireClient(player, {
		SkinName = chosenSkin.Data.SkinName;
		Rarity = chosenRarity;
		Image = chosenSkin.Data.Image;
		Knife = chosenSkin.Knife;
		Case = CaseName,
	}, DURATATION, HasSkip, CaseName)

	
	task.wait(DURATATION + 0.8)
	

	
	
	if CaseInfo.EmoteCase == true then
		InventoryHandler.AddEmote(player, tostring(chosenSkin.Knife))
	else
		InventoryHandler.AddKnife(player, tostring(chosenSkin.Knife))
	end
		
		
	
	if OnSpinningAnimation[player] then
		OnSpinningAnimation[player] = nil
	end
	
	
	
	
	
	
end)

return {}