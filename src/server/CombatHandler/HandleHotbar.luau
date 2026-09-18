-- // SERVICES // --
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")


-- // REMOTES // --
local Remotes = RS:WaitForChild("Remotes")
local HotBarRemotes = Remotes:WaitForChild("HotBar")
local EquipRemote = HotBarRemotes:WaitForChild("Equip")
local EquippedClient = HotBarRemotes:WaitForChild("EquippedClient")



-- // Other // --
local KnivesFolder = ServerStorage:WaitForChild("Knives")


local function NotifyClient(player : Player, action : string, equippedornot : boolean)
	if not player then return end
	
	
	EquippedClient:FireClient(player, action, equippedornot)
end


local function UnequipOtherTools(player : Player)
	local character = player.Character
	if not character then return end
	for i , v in pairs(character:GetChildren()) do
		if v:IsA("Tool") then
			v:Destroy()
			NotifyClient(player, "Knife", false)
		end
	end
end

local function EquipKnife(player : Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local EquippedKnife = leaderstats:FindFirstChild("EquippedKnife")
	
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
	local EquippedGun = leaderstats:FindFirstChild("EquippedKnife")

	if leaderstats and EquippedGun then
		local Gun = KnivesFolder:FindFirstChild(EquippedGun.Value)
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
local EQUIP_COOLDOWN = 0.3

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
	if typeof(category) ~= "string" then return end
	local now = os.clock()
	if equipCooldowns[player.UserId] and (now - equipCooldowns[player.UserId]) < EQUIP_COOLDOWN then return end
	equipCooldowns[player.UserId] = now
	
	

	
	
	if category == "Knife" then
		if CheckIfEquipped(player) then
			UnequipOtherTools(player)
			return
		end
		
		EquipKnife(player)
		return
	end
	
	
	if category == "Revolver" then
		if CheckIfEquipped(player) then
			UnequipOtherTools(player)
			return
		end
		
		EquipGun(player)
	end
	
	
end)


game:GetService("Players").PlayerRemoving:Connect(function(player)
	equipCooldowns[player.UserId] = nil
end)

return {}