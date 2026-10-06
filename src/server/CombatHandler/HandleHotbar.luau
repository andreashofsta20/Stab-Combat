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
local pendingEquips = {}
local EQUIP_RETRY_SECONDS = 0.1
local MAX_EQUIP_ATTEMPTS = 5

local function CancelPendingEquip(player)
	local pending = pendingEquips[player]
	pendingEquips[player] = nil
	if pending and pending.tool then pending.tool:Destroy() end
end


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

local function EquipCatalogTool(player: Player, template: Tool, action: string, stillOwned)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	local handle = template:FindFirstChild("Handle")
	if not humanoid or humanoid.Health <= 0 or not backpack or not template:IsA("Tool")
		or (template.RequiresHandle and (not handle or not handle:IsA("BasePart"))) then return end
	local tool = template:Clone()
	if not tool then return end
	tool.Enabled, tool.CanBeDropped = true, false
	-- Prepare the real held geometry before parenting it into a character.
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanTouch, part.Massless = false, false, false, true
		end
	end
	UnequipOtherTools(player)
	tool.Parent = backpack
	local pending = {tool = tool, character = character, humanoid = humanoid, backpack = backpack, attempts = 0}
	pendingEquips[player] = pending
	local function attempt()
		-- A delayed native equip cannot replace a later slot selection or respawn.
		if pendingEquips[player] ~= pending then return end
		if player.Character ~= character or humanoid.Parent ~= character or humanoid.Health <= 0 or not stillOwned()
			or player:GetAttribute("DataReady") ~= true or backpack.Parent ~= player or tool.Parent ~= backpack then
			CancelPendingEquip(player)
			return
		end
		if character:FindFirstChildOfClass("Tool") then CancelPendingEquip(player); return end
		pending.attempts += 1
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if not template.RequiresHandle or (hand and hand:IsA("BasePart")) then humanoid:EquipTool(tool) end
		if tool.Parent == character then
			pendingEquips[player] = nil
			NotifyClient(player, action, true)
		elseif pending.attempts < MAX_EQUIP_ATTEMPTS then
			task.delay(EQUIP_RETRY_SECONDS, attempt)
		else
			CancelPendingEquip(player)
		end
	end
	attempt()
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
			EquipCatalogTool(player, Knife, "Knife", function()
				return leaderstats.Parent == player and EquippedKnife.Parent == leaderstats and inventory.Parent == leaderstats
					and owned.Parent == inventory and EquippedKnife.Value == Knife.Name and quantity.Parent == owned
					and quantity.Value > 0 and Knife.Parent == KnivesFolder
			end)
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
			EquipCatalogTool(player, Gun, "Gun", function()
				return leaderstats.Parent == player and EquippedGun.Parent == leaderstats and revolverInventory.Parent == leaderstats
					and owned.Parent == revolverInventory and EquippedGun.Value == Gun.Name and quantity.Parent == owned
					and quantity.Value > 0 and Gun.Parent == RevolversFolder
			end)
			return
		end
	end
end






local equipCooldowns: {[number]: number} = {}
local EQUIP_COOLDOWN = 0.1

EquipRemote.OnServerEvent:Connect(function(player, category)
	if category ~= "Knife" and category ~= "Revolver" and category ~= "Food" then return end
	if player:GetAttribute("DataReady") ~= true then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local now = os.clock()
	if equipCooldowns[player.UserId] and (now - equipCooldowns[player.UserId]) < EQUIP_COOLDOWN then return end
	equipCooldowns[player.UserId] = now
	CancelPendingEquip(player)
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
	CancelPendingEquip(player)
	equipCooldowns[player.UserId] = nil
end)

return {}
