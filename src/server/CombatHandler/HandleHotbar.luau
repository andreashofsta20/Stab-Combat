-- // SERVICES // --
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local FoodService = require(script.Parent.FoodService)


-- // REMOTES // --
local Remotes = RS:WaitForChild("Remotes")
local HotBarRemotes = Remotes:WaitForChild("HotBar")
local EquipRemote = HotBarRemotes:WaitForChild("Equip")
local EquippedClient = HotBarRemotes:WaitForChild("EquippedClient")



-- // Other // --
local KnivesFolder = ServerStorage:WaitForChild("Knives")
local RevolversFolder = ServerStorage:WaitForChild("Revolvers")


local function NotifyClient(player : Player, action : string, equippedornot : boolean)
	if not player then return end
	
	
	EquippedClient:FireClient(player, action, equippedornot)
end


local function UnequipOtherTools(player : Player)
	local character = player.Character
	if not character then return end
	for i , v in pairs(character:GetChildren()) do
		if v:IsA("Tool") then
			local action = v:GetAttribute("FoodItem") == "Burger" and "Food" or (RevolversFolder:FindFirstChild(v.Name) and "Gun" or "Knife")
			if not FoodService.Store(player, v) then v:Destroy() end
			NotifyClient(player, action, false)
		end
	end
end

local function IsEquippedFrom(folder: Folder, player: Player)
	local character = player.Character
	if not character then return false end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and folder:FindFirstChild(child.Name) then
			return true
		end
	end
	return false
end

local function EquipKnife(player : Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local EquippedKnife = leaderstats:FindFirstChild("EquippedKnife")
	local inventory = leaderstats:FindFirstChild("Inventory")
	local owned = EquippedKnife and inventory and inventory:FindFirstChild(EquippedKnife.Value)
	local quantity = owned and owned:FindFirstChild("Quantity")
	if not quantity or not quantity:IsA("IntValue") or quantity.Value <= 0 then return end
	
	if leaderstats and EquippedKnife then
		local Knife = KnivesFolder:FindFirstChild(EquippedKnife.Value)
		if Knife then
			local KnifeClone = Knife:Clone()
			UnequipOtherTools(player)
			KnifeClone.Parent = player.Character
			NotifyClient(player, "Knife", true)
			return
		end
	end
end


local function EquipGun(player : Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local EquippedGun = leaderstats:FindFirstChild("EquippedGun")
	local revolverInventory = leaderstats:FindFirstChild("RevolverInventory")
	local owned = EquippedGun and revolverInventory and revolverInventory:FindFirstChild(EquippedGun.Value)
	local quantity = owned and owned:FindFirstChild("Quantity")
	if not quantity or not quantity:IsA("IntValue") or quantity.Value <= 0 then return end

	if EquippedGun and revolverInventory and EquippedGun.Value ~= ""
		and revolverInventory:FindFirstChild(EquippedGun.Value) then
		local Gun = RevolversFolder:FindFirstChild(EquippedGun.Value)
		if Gun then
			local GunClone = Gun:Clone()
			UnequipOtherTools(player)
			GunClone.Parent = player.Character
			NotifyClient(player, "Gun", true)
			return
		end
	end
end






local equipCooldowns: {[number]: number} = {}
local EQUIP_COOLDOWN = 0.1

local function CheckIfEquipped(player : Player)
	local character = player.Character
	if not character then return false end
	for i , v in pairs(character:GetChildren()) do
		if v:IsA("Tool") then
			return true
		end
	end
	
	return false
end

EquipRemote.OnServerEvent:Connect(function(player, category)
	if category ~= "Knife" and category ~= "Revolver" and category ~= "Food" then return end
	if player:GetAttribute("DataReady") ~= true then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local now = os.clock()
	if equipCooldowns[player.UserId] and (now - equipCooldowns[player.UserId]) < EQUIP_COOLDOWN then return end
	equipCooldowns[player.UserId] = now
	if category == "Food" then
		local tool = FoodService.GetTool(player)
		if not tool then return end
		if tool.Parent == character then
			FoodService.Store(player, tool)
			NotifyClient(player, "Food", false)
		else
			UnequipOtherTools(player)
			humanoid:EquipTool(tool)
			NotifyClient(player, "Food", true)
		end
		return
	end
	
	

	
	
	if category == "Knife" then
		if IsEquippedFrom(KnivesFolder, player) then
			UnequipOtherTools(player)
			return
		end
		
		EquipKnife(player)
		return
	end
	
	
	if category == "Revolver" then
		if IsEquippedFrom(RevolversFolder, player) then
			UnequipOtherTools(player)
			return
		end

		EquipGun(player)
		return
	end
	
	
end)


game:GetService("Players").PlayerRemoving:Connect(function(player)
	equipCooldowns[player.UserId] = nil
end)

return {}
