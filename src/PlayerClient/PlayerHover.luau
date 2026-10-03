local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.PlayerHoverConfig)
local RagdollQuery = require(RS.Modules.RagdollQuery)
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("Main")
local oldFrame = gui:FindFirstChild("PlayerHover")
if oldFrame then oldFrame.Visible = false end
local gameActive = RS:WaitForChild("GameActive")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local filterCharacter, filterRagdolls, target, selectedHighlight
local records, characterOwners = {}, {}
local lastClickPlayer, lastClickTime, lastClickPosition
local nextProfile, scanElapsed = 0, 0

-- Cache menu children; do not allocate GetChildren arrays during hover scans.
local frames, menuFrames = gui:FindFirstChild("Frames"), {}
local emote = gui:FindFirstChild("EmoteFrame")
local emoteBackground = emote and emote:FindFirstChild("background")
if frames then
	for _, frame in ipairs(frames:GetChildren()) do if frame:IsA("GuiObject") then menuFrames[frame] = true end end
	frames.ChildAdded:Connect(function(frame) if frame:IsA("GuiObject") then menuFrames[frame] = true end end)
	frames.ChildRemoved:Connect(function(frame) menuFrames[frame] = nil end)
end
local function blocked()
	if not Config.Enabled or gameActive.Value or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return true end
	local character = player.Character
	if character and character:FindFirstChildOfClass("Tool") then return true end
	for frame in pairs(menuFrames) do if frame.Visible then return true end end
	return emoteBackground ~= nil and emoteBackground.Visible
end
local function clear()
	if selectedHighlight then selectedHighlight.Enabled = false end
	target, selectedHighlight, lastClickPlayer = nil, nil, nil
end
local function disconnect(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end
local function clearCharacter(other, record)
	if target == other then clear() end
	if record.character then characterOwners[record.character] = nil end
	disconnect(record.characterConnections)
	if record.highlight then record.highlight:Destroy() end
	record.character, record.humanoid, record.highlight = nil, nil, nil
end
local function prepareCharacter(other, record, character)
	clearCharacter(other, record)
	if not character or other.Parent ~= Players then return end
	record.character, characterOwners[character] = character, other
	-- Prepare once on spawn. Hover only switches Enabled; it never creates,
	-- reparents, destroys or retargets a Highlight or avatar geometry.
	local highlight = Instance.new("Highlight")
	highlight.Name = "PlayerHoverHighlight_" .. other.UserId
	highlight.FillTransparency, highlight.OutlineTransparency = 1, 0
	highlight.OutlineColor, highlight.DepthMode = Color3.new(1, 1, 1), Enum.HighlightDepthMode.Occluded
	highlight.Enabled, highlight.Adornee, highlight.Parent = false, character, workspace
	record.highlight = highlight
	local function attachHumanoid(humanoid)
		if not humanoid or record.humanoid == humanoid then return end
		record.humanoid = humanoid
		table.insert(record.characterConnections, humanoid.Died:Connect(function() if target == other then clear() end end))
	end
	attachHumanoid(character:FindFirstChildOfClass("Humanoid"))
	table.insert(record.characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then attachHumanoid(child) end
	end))
	table.insert(record.characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent and target == other then clear() end
	end))
end
local function trackPlayer(other)
	if other == player or records[other] then return end
	local record = {connections = {}, characterConnections = {}}
	records[other] = record
	table.insert(record.connections, other.CharacterAdded:Connect(function(character) prepareCharacter(other, record, character) end))
	table.insert(record.connections, other.CharacterRemoving:Connect(function(character)
		if record.character == character then clearCharacter(other, record) end
	end))
	if other.Character then prepareCharacter(other, record, other.Character) end
end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(other)
	local record = records[other]
	if not record then return end
	clearCharacter(other, record)
	disconnect(record.connections)
	records[other] = nil
end)
for _, other in ipairs(Players:GetPlayers()) do trackPlayer(other) end

local function playerAt(position)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ragdolls = RagdollQuery.GetFolder()
	if filterCharacter ~= player.Character or filterRagdolls ~= ragdolls then
		filterCharacter, filterRagdolls = player.Character, ragdolls
		params.FilterDescendantsInstances = RagdollQuery.Exclude(filterCharacter and {filterCharacter} or {})
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * Config.MaxDistance, params)
	local ancestor = hit and hit.Instance
	while ancestor and ancestor ~= workspace do
		local other = characterOwners[ancestor]
		local record = other and records[other]
		if record and other.Character == ancestor and record.humanoid and record.humanoid.Health > 0 then return other end
		ancestor = ancestor.Parent
	end
end
local function select(other)
	if other == target then return end
	clear()
	local record = other and records[other]
	if not record or not record.highlight then return end
	target, selectedHighlight = other, record.highlight
	selectedHighlight.Enabled = true
end
local function click(position)
	if blocked() then clear(); return end
	local other, now = playerAt(position), os.clock()
	if not other then clear(); return end
	select(other)
	if lastClickPlayer == other and now - lastClickTime <= Config.DoubleClickSeconds
		and (position - lastClickPosition).Magnitude <= Config.DoubleClickPixels then
		lastClickPlayer = nil
		if now >= nextProfile then
			nextProfile = now + Config.ProfileCooldown
			-- Hover and first click do no network/profile/portrait work.
			local remotes = RS:FindFirstChild("Remotes")
			local handler = remotes and remotes:FindFirstChild("ProfileHandler")
			local request = handler and handler:FindFirstChild("RequestViewProfile")
			if request then request:FireServer(other.UserId) end
		end
	else
		lastClickPlayer, lastClickTime, lastClickPosition = other, now, position
	end
end
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then click(UIS:GetMouseLocation()) end
end)
UIS.TouchTapInWorld:Connect(function(position, processed) if not processed then click(position) end end)
RunService.Heartbeat:Connect(function(dt)
	scanElapsed += dt
	if scanElapsed < Config.ScanInterval then return end
	scanElapsed = 0
	if blocked() then if target then clear() end; return end
	if target and (target.Parent ~= Players or selectedHighlight.Adornee ~= target.Character) then clear() end
	if UIS:GetLastInputType() ~= Enum.UserInputType.Touch then select(playerAt(UIS:GetMouseLocation())) end
end)
gameActive.Changed:Connect(clear)
player.CharacterRemoving:Connect(clear)
UIS.WindowFocusReleased:Connect(clear)
return {}
