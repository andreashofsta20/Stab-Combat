-- A hidden equipped Tool still participates in physics. Keep every catalog
-- revolver part decorative on server and client; server rays stay authoritative.
local Physics = {}

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function makeDecorative(part)
	if part.CanCollide then part.CanCollide = false end
	if part.CanTouch then part.CanTouch = false end
	if not part.Massless then part.Massless = true end
	-- Never anchor a held Tool or change its query/raycast behavior here.
end

function Physics.New(catalog)
	local players = {}
	local manager = {}

	local function clearTool(state, tool)
		local record = state.tools[tool]
		if not record then return end
		state.tools[tool] = nil
		disconnectAll(record.connections)
		for _, connections in pairs(record.parts) do disconnectAll(connections) end
		table.clear(record.parts)
	end

	local function bindTool(state, tool)
		if state.tools[tool] or not tool:IsA("Tool") or not catalog[tool.Name] then return end
		local record = {connections = {}, parts = {}}
		state.tools[tool] = record
		local function addPart(part)
			if not part:IsA("BasePart") or record.parts[part] then return end
			local connections = {}
			record.parts[part] = connections
			local function enforce()
				if state.tools[tool] == record and record.parts[part] then makeDecorative(part) end
			end
			for _, property in ipairs({"CanCollide", "CanTouch", "Massless"}) do
				table.insert(connections, part:GetPropertyChangedSignal(property):Connect(enforce))
			end
			enforce()
		end
		table.insert(record.connections, tool.DescendantAdded:Connect(addPart))
		table.insert(record.connections, tool.DescendantRemoving:Connect(function(part)
			local connections = record.parts[part]
			if connections then record.parts[part] = nil; disconnectAll(connections) end
		end))
		for _, part in ipairs(tool:GetDescendants()) do addPart(part) end
	end

	local function clearCharacter(state)
		disconnectAll(state.characterConnections)
		for tool in pairs(state.tools) do clearTool(state, tool) end
		state.character = nil
	end

	local function bindCharacter(state, character)
		if state.character == character then return end
		clearCharacter(state)
		state.character = character
		table.insert(state.characterConnections, character.ChildAdded:Connect(function(child) bindTool(state, child) end))
		table.insert(state.characterConnections, character.ChildRemoved:Connect(function(child) clearTool(state, child) end))
		for _, child in ipairs(character:GetChildren()) do bindTool(state, child) end
	end

	function manager.BindPlayer(player)
		if players[player] then return end
		local state = {connections = {}, characterConnections = {}, tools = {}}
		players[player] = state
		table.insert(state.connections, player.CharacterAdded:Connect(function(character) bindCharacter(state, character) end))
		table.insert(state.connections, player.CharacterRemoving:Connect(function(character)
			if state.character == character then clearCharacter(state) end
		end))
		if player.Character then bindCharacter(state, player.Character) end
	end

	function manager.RemovePlayer(player)
		local state = players[player]
		if not state then return end
		players[player] = nil
		clearCharacter(state)
		disconnectAll(state.connections)
	end

	return manager
end

return Physics
