-- Cosmetic only: uses server-owned loadout values and equipped Tools.
-- No client remote or changes to the actual combat weapons are needed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local config = require(modules:WaitForChild("KnifeRevAccesoryCframe"))
local catalogs = {
	Knife = require(modules:WaitForChild("KnivesInfo")),
	Revolver = require(modules:WaitForChild("RevolversInfo")),
}
local states = {}
local warnedTemplates = {}

local function disconnectAll(connections)
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function findTemplate(settings, itemName)
	local itemSettings = settings.Items[itemName]
	local templateName = itemSettings and itemSettings.TemplateName or itemName
	for _, folderName in ipairs(settings.TemplateFolders) do
		for _, storage in ipairs({ ReplicatedStorage, ServerStorage }) do
			local folder = storage:FindFirstChild(folderName)
			local template = folder and folder:FindFirstChild(templateName)
			if template then
				return template
			end
		end
	end
	return nil
end

local function getRoot(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	local handle = instance:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end
	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function createDisplay(template, torso, offset, settings, itemName)
	if not (template:IsA("BasePart") or template:IsA("Model")
		or template:IsA("Tool") or template:IsA("Accessory")) then return nil end
	local clone = template:Clone()
	if not clone then return nil end

	-- Sanitize before parenting to the live character. Rebuild rigid joints
	-- locally so a template cannot retain a weld to its original assembly.
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer")
			or descendant:IsA("JointInstance") or descendant:IsA("Constraint")
			or descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction")
			or descendant:IsA("BindableEvent") or descendant:IsA("BindableFunction")
			or descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector")
			or descendant:IsA("Humanoid") or descendant:IsA("AnimationController")
			or descendant:IsA("BodyMover") then
			descendant:Destroy()
		end
	end

	local root = getRoot(clone)
	if not root then
		clone:Destroy()
		return nil
	end

	local display = Instance.new("Model")
	display.Name = settings.DisplayName
	display:SetAttribute("WeaponName", itemName)
	if clone:IsA("Tool") then
		-- A holstered copy must never behave like an equippable Tool.
		for _, child in ipairs(clone:GetChildren()) do
			child.Parent = display
		end
		clone:Destroy()
	else
		clone.Parent = display
	end
	display.PrimaryPart = root

	local transform = (torso.CFrame * offset) * root.CFrame:Inverse()
	local parts = {}
	for _, part in ipairs(display:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false -- do not block combat rays or overlap queries
			part.Massless = true
			part.Anchored = false
			part.CFrame = transform * part.CFrame
		end
	end
	-- Position every part before building joints, preserving multipart geometry.
	for _, part in ipairs(parts) do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = settings.MotorName
	motor.Part0 = torso
	motor.Part1 = root
	motor.C0 = offset
	motor.C1 = CFrame.identity
	motor.Parent = root
	return display
end

local function isHolding(character, category)
	local folderName = category == "Knife" and "Knives" or "Revolvers"
	local weaponFolder = ServerStorage:FindFirstChild(folderName)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and (catalogs[category][child.Name]
			or (weaponFolder and weaponFolder:FindFirstChild(child.Name))) then
			return true
		end
	end
	return false
end

local function clearDisplay(state, category)
	local display = state.displays[category]
	if display then display:Destroy() end
	state.displays[category] = nil
end

local function refresh(state)
	local character = state.character
	if not character or character ~= state.player.Character or not character.Parent then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if character:GetAttribute("Ragdolled") == true or humanoid and humanoid.Health <= 0 then
		for category in pairs(config) do clearDisplay(state, category) end
		return
	end
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	if state.torso ~= torso then
		for category in pairs(config) do clearDisplay(state, category) end
		state.torso = torso
	end
	local stats = state.player:FindFirstChild("leaderstats")
	for category, settings in pairs(config) do
		local value = stats and stats:FindFirstChild(settings.StatName)
		-- Rebind if leaderstats/the loadout value was created late or replaced.
		local observed = state.values[category]
		if observed ~= value then
			if state.valueConnections[category] then
				state.valueConnections[category]:Disconnect()
				state.valueConnections[category] = nil
			end
			state.values[category] = value
			if value and value:IsA("StringValue") then
				state.valueConnections[category] = value:GetPropertyChangedSignal("Value"):Connect(state.schedule)
			end
		end

		local itemName = value and value:IsA("StringValue") and value.Value or ""
		local info = catalogs[category][itemName]
		local ready = state.player:GetAttribute("DataReady") ~= false
		if not ready or not torso or not torso:IsA("BasePart") or not info
			or isHolding(character, category) then
			clearDisplay(state, category)
			continue
		end

		local current = state.displays[category]
		if current and current.Parent == state.folder
			and current:GetAttribute("WeaponName") == itemName then
			continue
		end
		clearDisplay(state, category)
		local itemSettings = settings.Items[itemName]
		local offset = itemSettings and itemSettings.Offset
			or info.CframeBackrelativeOffset or settings.DefaultOffset
		if torso.Name == "UpperTorso" and itemSettings and itemSettings.R15Offset then
			offset = itemSettings.R15Offset
		end

		local template = findTemplate(settings, itemName)
		local display = template and createDisplay(template, torso, offset, settings, itemName)
		if display then
			display.Parent = state.folder
			state.displays[category] = display
		else
			local warningKey = category .. ":" .. itemName
			if not warnedTemplates[warningKey] then
				warnedTemplates[warningKey] = true
				warn("[WeaponAttachments] Missing/non-cloneable template or BasePart for " .. warningKey)
			end
		end
	end
end

local function clearCharacter(state)
	disconnectAll(state.characterConnections)
	for category in pairs(config) do clearDisplay(state, category) end
	if state.folder then state.folder:Destroy() end
	state.folder = nil
	state.torso = nil
	state.character = nil
end

local function bindCharacter(state, character)
	clearCharacter(state)
	state.character = character
	state.folder = Instance.new("Folder")
	state.folder.Name = "WeaponAttachments"
	state.folder.Parent = character
	local function onChildChanged(child)
		if child:IsA("Tool") or child.Name == "Torso" or child.Name == "UpperTorso" then
			state.schedule()
		end
	end
	table.insert(state.characterConnections, character.ChildAdded:Connect(onChildChanged))
	table.insert(state.characterConnections, character.ChildRemoved:Connect(onChildChanged))
	table.insert(state.characterConnections, character:GetAttributeChangedSignal("Ragdolled"):Connect(state.schedule))
	state.schedule()
end

local function onPlayerAdded(player)
	if states[player] then return end
	local state = {
		player = player,
		alive = true,
		queued = false,
		displays = {},
		values = {},
		valueConnections = {},
		characterConnections = {},
		playerConnections = {},
	}
	states[player] = state
	state.schedule = function()
		if not state.alive or state.queued then return end
		state.queued = true
		task.defer(function()
			state.queued = false
			if state.alive then refresh(state) end
		end)
	end
	local function onStatChanged(descendant)
		if descendant.Name == "leaderstats" or descendant.Name == "EquippedKnife"
			or descendant.Name == "EquippedGun" then
			state.schedule()
		end
	end
	table.insert(state.playerConnections, player.DescendantAdded:Connect(onStatChanged))
	table.insert(state.playerConnections, player.DescendantRemoving:Connect(onStatChanged))
	table.insert(state.playerConnections, player:GetAttributeChangedSignal("DataReady"):Connect(state.schedule))
	table.insert(state.playerConnections, player.CharacterAdded:Connect(function(character)
		bindCharacter(state, character)
	end))
	table.insert(state.playerConnections, player.CharacterRemoving:Connect(function(character)
		if state.character == character then clearCharacter(state) end
	end))
	if player.Character then bindCharacter(state, player.Character) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if not state then return end
	state.alive = false
	clearCharacter(state)
	disconnectAll(state.valueConnections)
	disconnectAll(state.playerConnections)
	states[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
