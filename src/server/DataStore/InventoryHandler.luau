local InventoryHandler = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnivesInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local InventoryRemotesFolder = RemotesFolder:WaitForChild("Inventory")

local EquipKnifeRemote = InventoryRemotesFolder:WaitForChild("EquipKnife")

local EmotesInfo = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Emotes"))


local function CreateItem(player : Player, knifeName : string)
	if not player then return end

	print("sdadas" .. knifeName)

	local rarity = nil
	local image = nil

	for i, v in pairs(KnivesInfoModule) do
		print(i, v)
		if i == knifeName then
			print("found")
			rarity = v.Rarity
			image = v.Image
			break 
		end
	end

	if not rarity then
		print("couldn't find knife: " .. knifeName)
		return
	end

	local inventoryFolder = player.leaderstats:FindFirstChild("Inventory")
	if not inventoryFolder then
		warn("Inventory folder not found for player: " .. player.Name)
		return
	end

	local existing = inventoryFolder:FindFirstChild(knifeName)
	if existing then
		existing.Quantity.Value += 1
		return
	end

	local Knife = Instance.new("StringValue")
	Knife.Name = knifeName
	Knife.Parent = inventoryFolder

	local Quantity = Instance.new("IntValue")
	Quantity.Name = "Quantity"
	Quantity.Value = 1
	Quantity.Parent = Knife

	local Rarity = Instance.new("StringValue")
	Rarity.Name = "Rarity"
	Rarity.Value = rarity
	Rarity.Parent = Knife

	local ImageItem = Instance.new("StringValue")
	ImageItem.Name = "Image"
	ImageItem.Value = image
	ImageItem.Parent = Knife


	return Knife
end







function InventoryHandler.AddEmote(player: Player, emoteName: string)
	if not player or not emoteName then return end

	local leaderstats = player:WaitForChild("leaderstats")
	local emotesInventory = leaderstats:WaitForChild("Emotes")

	local info = EmotesInfo[emoteName]
	if not info then
		warn(("Emote '%s' not found in EmotesInfo"):format(emoteName))
		return
	end

	local existing = emotesInventory:FindFirstChild(emoteName)
	if existing and existing:IsA("StringValue") then
		local qty = existing:FindFirstChild("Quantity")
		if qty then
			qty.Value += 1
		else
			local q = Instance.new("IntValue")
			q.Name = "Quantity"
			q.Value = 2
			q.Parent = existing
		end
		return
	end


	local emote = Instance.new("StringValue")
	emote.Name = emoteName
	emote.Value = info.EmoteId or ""  
	emote.Parent = emotesInventory

	local quantity = Instance.new("IntValue")
	quantity.Name = "Quantity"
	quantity.Value = 1
	quantity.Parent = emote

	local rarity = Instance.new("StringValue")
	rarity.Name = "Rarity"
	rarity.Value = info.Rarity or "Common"
	rarity.Parent = emote

	if info.Image then
		local image = Instance.new("StringValue")
		image.Name = "Image"
		image.Value = info.Image
		image.Parent = emote
	end
end


function InventoryHandler.AdminGiveCash(player : Player, player2 : Player ,Number : number)



end

function InventoryHandler.AddXP(player : Player, Amount : number)



	local leaderstats = player:FindFirstChild("leaderstats")
	local XP = leaderstats:WaitForChild("XP")

	XP.Value += Amount
end


function InventoryHandler.AddCash(player : Player, Amount : number)

	if not player then return end

	if not Amount then return end




	local leaderstats = player:FindFirstChild("leaderstats")
	local Cash = leaderstats:WaitForChild("Cash")

	Cash.Value += Amount

end


function InventoryHandler.ViewInventory(player : Player)

end


function InventoryHandler.AddKnife(player : Player, knifeName : string)
	CreateItem(player, knifeName)
end


function InventoryHandler.WipeInventory(player : Player)

end


function InventoryHandler.RemoveKnife(player : Player, knifeName : string)

end


EquipKnifeRemote.OnServerEvent:Connect(function(player : Player, KnifeName : string)
	if not player then return end

	if not KnivesInfoModule[KnifeName] then
		print("couldnt find")
		return
	end

	local leaderstats = player:WaitForChild("leaderstats")

	local inventoryFolder = leaderstats:FindFirstChild("Inventory")
	if not inventoryFolder then
		warn("inventory folder not found")
		return
	end


	local EquippedKnife = leaderstats:WaitForChild("EquippedKnife")

	if not EquippedKnife then
		warn("couldnt find equipped knife in leaderstats")
		return
	end

	if inventoryFolder:FindFirstChild(KnifeName) then
		EquippedKnife.Value = KnifeName
	else
		warn("knife not found in inventory")
	end









end)


return InventoryHandler