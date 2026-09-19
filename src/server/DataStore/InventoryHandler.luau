local InventoryHandler = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KnivesInfoModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KnivesInfo"))
local RevolversInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RevolversInfo"))
local RevolversFolder = ServerStorage:WaitForChild("Revolvers")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local InventoryRemotesFolder = RemotesFolder:WaitForChild("Inventory")

local EquipKnifeRemote = InventoryRemotesFolder:WaitForChild("EquipKnife")

local EmotesInfo = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Emotes"))

local DEFAULT_UNTRADEABLE_KNIVES = {
	["Shadow Dagger"] = true,
}


local function CreateItem(player : Player, knifeName : string, tradeable: boolean?)
	if not player then return end

	if not knifeName then return end

	local rarity = nil
	local image = nil

	for i, v in pairs(KnivesInfoModule) do
		if i == knifeName then
			rarity = v.Rarity
			image = v.Image
			break 
		end
	end

	if not rarity then
		warn("Rarity not found for knife: " .. knifeName)
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
		local tradeableFlag = existing:FindFirstChild("Tradeable")
		if not tradeableFlag then
			tradeableFlag = Instance.new("BoolValue")
			tradeableFlag.Name = "Tradeable"
			tradeableFlag.Value = tradeable ~= nil and tradeable or not DEFAULT_UNTRADEABLE_KNIVES[knifeName]
			tradeableFlag.Parent = existing
		elseif tradeable ~= nil then
			tradeableFlag.Value = tradeable
		end
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

	local Tradeable = Instance.new("BoolValue")
	Tradeable.Name = "Tradeable"
	Tradeable.Value = tradeable ~= nil and tradeable or not DEFAULT_UNTRADEABLE_KNIVES[knifeName]
	Tradeable.Parent = Knife


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


function InventoryHandler.AddKnife(player : Player, knifeName : string, tradeable: boolean?)
	CreateItem(player, knifeName, tradeable)
end

function InventoryHandler.AddRevolver(player: Player, revolverName: string, quantity: number?)
	if not player or type(revolverName) ~= "string" or revolverName == "" then return end
	if not RevolversFolder:FindFirstChild(revolverName) then
		warn("Revolver not found: " .. revolverName)
		return
	end
	local revolverInfo = RevolversInfo[revolverName]
	if not revolverInfo then
		warn("Revolver info not found: " .. revolverName)
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local inventory = leaderstats and leaderstats:FindFirstChild("RevolverInventory")
	if not inventory then return end

	local existing = inventory:FindFirstChild(revolverName)
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = revolverName
		existing:SetAttribute("Rarity", revolverInfo.Rarity or "Common")
		existing:SetAttribute("Image", revolverInfo.Image or "")
		existing:SetAttribute("Tradeable", revolverInfo.Tradeable == true)
		existing.Parent = inventory

		local amount = Instance.new("IntValue")
		amount.Name = "Quantity"
		amount.Value = 0
		amount.Parent = existing
	end

	local amount = existing:FindFirstChild("Quantity")
	if amount and amount:IsA("IntValue") then
		amount.Value += math.max(1, math.floor(quantity or 1))
	end
end


function InventoryHandler.WipeInventory(player : Player)

end


function InventoryHandler.RemoveKnife(player : Player, knifeName : string)

end


local equipCooldowns: {[number]: number} = {}
local EQUIP_KNIFE_COOLDOWN = 0.3

EquipKnifeRemote.OnServerEvent:Connect(function(player : Player, KnifeName : string)
	if not player then return end
	if type(KnifeName) ~= "string" then return end
	if #KnifeName < 1 or #KnifeName > 64 then return end

	local now = os.clock()
	if equipCooldowns[player.UserId] and (now - equipCooldowns[player.UserId]) < EQUIP_KNIFE_COOLDOWN then return end
	equipCooldowns[player.UserId] = now

	if not KnivesInfoModule[KnifeName] then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local inventoryFolder = leaderstats:FindFirstChild("Inventory")
	if not inventoryFolder then
		return
	end

	local EquippedKnife = leaderstats:FindFirstChild("EquippedKnife")
	if not EquippedKnife then
		return
	end

	if inventoryFolder:FindFirstChild(KnifeName) then
		EquippedKnife.Value = KnifeName
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	equipCooldowns[player.UserId] = nil
end)

return InventoryHandler