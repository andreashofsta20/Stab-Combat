local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Config = require(ReplicatedStorage.Modules.RagdollConfig)
local Rig = require(script.Parent.RagdollRig)
local Service = {}
local initialized, folder = false, nil
local states = setmetatable({}, { __mode = "k" })
local players, corpses = {}, {}

local function disconnect(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function setupWorld()
	if folder and folder.Parent == workspace then return end
	for _, name in ipairs({ Config.CollisionGroup, Config.CharacterCollisionGroup }) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then PhysicsService:RegisterCollisionGroup(name) end
	end
	-- Default character parts retain Default's relationships with existing map groups.
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if group.name ~= Config.CollisionGroup and group.name ~= Config.CharacterCollisionGroup then
			PhysicsService:CollisionGroupSetCollidable(Config.CharacterCollisionGroup, group.name,
				PhysicsService:CollisionGroupsAreCollidable("Default", group.name))
		end
	end
	PhysicsService:CollisionGroupSetCollidable(Config.CharacterCollisionGroup, Config.CharacterCollisionGroup,
		PhysicsService:CollisionGroupsAreCollidable("Default", "Default"))
	PhysicsService:CollisionGroupSetCollidable(Config.CollisionGroup, Config.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(Config.CollisionGroup, Config.CharacterCollisionGroup, false)
	folder = workspace:FindFirstChild(Config.FolderName)
	assert(not folder or folder:IsA("Folder"), Config.FolderName .. " must be a Folder")
	if not folder then folder = Instance.new("Folder"); folder.Name, folder.Parent = Config.FolderName, workspace end
end

function Service.Prepare(character)
	if not Config.Enabled or not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.BreakJointsOnDeath = false end
end

function Service.SetImpact(character, kind, direction)
	if not Config.Enabled or not character or states[character] and states[character].done then return end
	if typeof(direction) ~= "Vector3" or direction.Magnitude ~= direction.Magnitude
		or direction.Magnitude == math.huge or direction.Magnitude < 0.001 then return end
	local state = states[character] or {}; states[character] = state
	state.impact = { Kind = kind, Direction = direction.Unit }
end

function Service.ClearImpact(character)
	local state = states[character]
	if state then state.impact = nil end
end

function Service.OnDeath(character)
	if not Config.Enabled or not character or not character.Parent then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health > 0 then return nil end
	local state = states[character] or {}; states[character] = state
	if state.done then return nil end
	state.done = true -- Died and the synchronous damage path may both arrive
	local corpse
	local archivable = character.Archivable
	local ok, failure = pcall(function()
		setupWorld()
		character.Archivable = true
		corpse = character:Clone()
		character.Archivable = archivable
		if not corpse then error("Character could not be cloned") end
		local torso, motion = Rig.Build(corpse, character, Config)
		if not torso then error("Character has no supported body joints") end
		corpse.Name = character.Name .. "_Ragdoll"
		corpse:SetAttribute("DeathRagdoll", true)
		corpse.Parent = folder
		Rig.Start(corpse, torso, Config, state.impact, motion)
	end)
	character.Archivable = archivable
	state.impact = nil
	if not ok then
		if corpse then corpse:Destroy() end
		warn("[Ragdoll] " .. tostring(failure))
		return nil -- death/credit/respawn still proceed if a malformed avatar fails
	end
	character:SetAttribute("Ragdolled", true)
	Rig.HideOriginal(character)
	for index = #corpses, 1, -1 do if not corpses[index].Parent then table.remove(corpses, index) end end
	while #corpses >= Config.MaxCorpses do table.remove(corpses, 1):Destroy() end
	table.insert(corpses, corpse)
	task.delay(Config.LifetimeSeconds, function()
		local index = table.find(corpses, corpse)
		if index then table.remove(corpses, index) end
		corpse:Destroy() -- capture the corpse, never a player's new character
	end)
	return corpse
end

local function bindCharacter(player, character)
	local record = players[player]
	if not record or player.Character ~= character or record.character == character then return end
	disconnect(record.characterConnections)
	record.character = character
	local function prepareItem(item)
		if item:IsA("Humanoid") then
			Service.Prepare(character)
			table.insert(record.characterConnections, item.Died:Connect(function() Service.OnDeath(character) end))
		elseif item:IsA("BasePart") and item.CollisionGroup == "Default" then
			-- Existing custom character collision groups are preserved.
			item.CollisionGroup = Config.CharacterCollisionGroup
		end
	end
	table.insert(record.characterConnections, character.DescendantAdded:Connect(prepareItem))
	for _, item in ipairs(character:GetDescendants()) do prepareItem(item) end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then Service.OnDeath(character) end
end

local function observe(player)
	if players[player] then return end
	local record = { connections = {}, characterConnections = {} }; players[player] = record
	table.insert(record.connections, player.CharacterAdded:Connect(function(character) bindCharacter(player, character) end))
	table.insert(record.connections, player.CharacterRemoving:Connect(function(character)
		if record.character ~= character then return end
		-- Catch a death immediately followed by LoadCharacter before deferred Died.
		Service.OnDeath(character)
		disconnect(record.characterConnections)
		record.character = nil
	end))
	if player.Character then bindCharacter(player, player.Character) end
end

function Service.Init()
	if initialized or not Config.Enabled then return end
	setupWorld(); initialized = true
	Players.PlayerAdded:Connect(observe)
	Players.PlayerRemoving:Connect(function(player)
		local record = players[player]
		if record then disconnect(record.connections); disconnect(record.characterConnections); players[player] = nil end
	end)
	for _, player in ipairs(Players:GetPlayers()) do observe(player) end
end

return Service
