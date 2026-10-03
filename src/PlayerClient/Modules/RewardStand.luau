local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local RewardStand = {}

local function disconnect(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function findTouch(selection)
	if not selection then return nil end
	local direct = selection:FindFirstChild("Touch")
	if direct and direct:IsA("BasePart") then return direct end
	for _, item in ipairs(selection:GetDescendants()) do
		if item.Name == "Touch" and item:IsA("BasePart") then return item end
	end
	if selection:IsA("BasePart") then return selection end
	return nil
end

-- A limb leaving the pad must not close a panel while another limb is on it.
-- Watch only the lobby path and selected stand, never all Workspace descendants.
local function bind(root, path, frame, onOpen, onClose, onTick)
	local selection, touch, touchConnection, overlapCharacter
	local decals, connections, pathConnections, standConnections = {}, {}, {}, {}
	local disposed = false
	local monitoring, dismissed, elapsed, seconds = false, false, 0, 0
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.MaxParts = 1
	local function decorate()
		for _, decal in ipairs(decals) do
			decal.Color3 = frame.Visible and Color3.fromRGB(0, 152, 255) or Color3.fromRGB(205, 205, 205)
		end
	end
	local function touching()
		local character = player.Character
		if not character or not touch or not touch:IsDescendantOf(workspace) then return false end
		if overlapCharacter ~= character then
			overlapCharacter = character
			params.FilterDescendantsInstances = {character}
		end
		return #workspace:GetPartsInPart(touch, params) > 0
	end
	local function hide()
		if frame.Visible then frame.Visible = false end
	end
	local function enter()
		monitoring = true
		if not dismissed and not frame.Visible then frame.Visible = true end
	end
	local function setTouch(nextTouch)
		if nextTouch == touch then return end
		if touchConnection then touchConnection:Disconnect(); touchConnection = nil end
		if touch then hide() end
		touch = nextTouch
		monitoring, dismissed, elapsed, seconds = frame.Visible, false, 0, 0
		if not touch then return end
		local boundTouch = touch
		touchConnection = touch.Touched:Connect(function(hit)
			if disposed or touch ~= boundTouch or not touch:IsDescendantOf(workspace) then return end
			if not player.Character or not hit:IsDescendantOf(player.Character) then return end
			enter()
		end)
		-- The part may arrive after the player is already standing on the pad.
		if touching() then enter() end
	end
	local function refreshTouch()
		if disposed then return end
		setTouch(selection and selection:IsDescendantOf(workspace) and findTouch(selection) or nil)
	end
	local function setSelection(nextSelection)
		if nextSelection == selection then return end
		disconnect(standConnections)
		setTouch(nil)
		selection = nextSelection
		table.clear(decals)
		if not selection then return end
		local boundSelection = selection
		for _, item in ipairs(selection:GetDescendants()) do
			if item:IsA("Decal") then table.insert(decals, item) end
		end
		table.insert(standConnections, selection.DescendantAdded:Connect(function(item)
			if selection ~= boundSelection then return end
			if item:IsA("Decal") then table.insert(decals, item); decorate() end
			if item.Name == "Touch" and item:IsA("BasePart") then refreshTouch() end
		end))
		table.insert(standConnections, selection.DescendantRemoving:Connect(function(item)
			if selection ~= boundSelection then return end
			local index = table.find(decals, item)
			if index then table.remove(decals, index) end
			if touch and (item == touch or touch:IsDescendantOf(item)) then
				setTouch(nil)
				-- DescendantRemoving fires before Parent changes; resolve afterward.
				task.defer(refreshTouch)
			end
		end))
		table.insert(standConnections, selection.AncestryChanged:Connect(refreshTouch))
		decorate()
		refreshTouch()
	end
	local refreshPath
	refreshPath = function()
		if disposed then return end
		disconnect(pathConnections)
		local node = root
		for _, name in ipairs(path) do
			if not node then break end
			table.insert(pathConnections, node.ChildAdded:Connect(function(item)
				if item.Name == name then refreshPath() end
			end))
			table.insert(pathConnections, node.ChildRemoved:Connect(function(item)
				if item.Name == name then refreshPath() end
			end))
			node = node:FindFirstChild(name)
		end
		setSelection(node)
	end
	table.insert(connections, frame:GetPropertyChangedSignal("Visible"):Connect(function()
		decorate()
		if frame.Visible then
			monitoring = true; seconds = 0; onOpen()
		else
			if monitoring and touch then dismissed = true end
			if not touch then monitoring = false end
			if onClose then onClose() end
		end
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if not monitoring then return end
		elapsed, seconds = elapsed + dt, seconds + dt
		if elapsed >= 0.15 then
			elapsed = 0
			if touch and not touching() then monitoring, dismissed = false, false; hide(); return end
		end
		if frame.Visible and seconds >= 1 then seconds = 0; if onTick then onTick() end end
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		monitoring, dismissed, overlapCharacter = false, false, nil
		hide()
	end))
	table.insert(connections, frame.Destroying:Connect(function()
		disposed = true
		if touchConnection then touchConnection:Disconnect(); touchConnection = nil end
		disconnect(pathConnections)
		disconnect(standConnections)
		disconnect(connections)
		if onClose then onClose() end
	end))
	if frame.Visible then monitoring = true; onOpen() end
	refreshPath()
	return hide
end

function RewardStand.Bind(selection, frame, onOpen, onClose, onTick)
	return bind(selection, {}, frame, onOpen, onClose, onTick)
end

-- No yielding: GUI close/refresh setup continues even before the lobby streams in.
function RewardStand.BindLobby(selectionName, frame, onOpen, onClose, onTick)
	return bind(workspace, {"IntermissionMap", selectionName}, frame, onOpen, onClose, onTick)
end
return RewardStand
