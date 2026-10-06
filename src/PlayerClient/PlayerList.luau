local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local profileRemote = RS:WaitForChild("Remotes"):WaitForChild("ProfileHandler"):WaitForChild("RequestViewProfile")
local modules = RS:WaitForChild("Modules")
local Thumbnail = require(modules:WaitForChild("GetThumbnail"))
local Level = require(modules:WaitForChild("CalculateLevel"))
local container = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("PlayerList"):WaitForChild("Container")
local rows = container:WaitForChild("Players")
local template = RS:WaitForChild("UITemplates"):WaitForChild("PlayerListTemplates"):WaitForChild("Player")
local records, connections = {}, {}
local alive, toggleAt = true, 0

local function disconnect(items)
	for _, connection in ipairs(items) do connection:Disconnect() end
	table.clear(items)
end
local function removePlayer(other)
	local record = records[other]
	if not record then return end
	records[other] = nil
	disconnect(record.connections)
	disconnect(record.statsConnections)
	if record.xpConnection then record.xpConnection:Disconnect() end
	if record.hoverTween then record.hoverTween:Cancel() end
	record.row:Destroy()
end
local function addPlayer(other)
	if not alive or records[other] or other.Parent ~= Players then return end
	local record = {connections = {}, statsConnections = {}, row = template:Clone()}
	records[other] = record
	local row = record.row
	row.Name, row.PlayerName.Text, row.PlayerImage.Image = other.Name, other.Name, ""
	row.Level.Text, row.LayoutOrder, row.Parent = "0", 0, rows
	local function attachXP(xp)
		if not xp:IsA("ValueBase") or record.xp == xp then return end
		if record.xpConnection then record.xpConnection:Disconnect() end
		record.xp = xp
		local function updateLevel()
			local level = Level.GetLevel(xp.Value)
			row.Level.Text, row.LayoutOrder = tostring(level), -level
		end
		record.xpConnection = xp:GetPropertyChangedSignal("Value"):Connect(updateLevel)
		updateLevel()
	end
	local function attachStats(stats)
		if record.stats == stats then return end
		disconnect(record.statsConnections)
		if record.xpConnection then record.xpConnection:Disconnect(); record.xpConnection = nil end
		record.stats, record.xp = stats, nil
		table.insert(record.statsConnections, stats.ChildAdded:Connect(function(child) if child.Name == "XP" then attachXP(child) end end))
		local xp = stats:FindFirstChild("XP")
		if xp then attachXP(xp) end
	end
	table.insert(record.connections, other.ChildAdded:Connect(function(child) if child.Name == "leaderstats" then attachStats(child) end end))
	local stats = other:FindFirstChild("leaderstats")
	if stats then attachStats(stats) end
	table.insert(record.connections, row.MouseButton1Up:Connect(function() profileRemote:FireServer(other.UserId) end))
	local background = row:FindFirstChild("Gradient")
	if background then
		local function hover(transparency)
			if record.hoverTween then record.hoverTween:Cancel() end
			record.hoverTween = TweenService:Create(background, TweenInfo.new(0.5), {BackgroundTransparency = transparency})
			record.hoverTween:Play()
		end
		table.insert(record.connections, row.MouseEnter:Connect(function() hover(0.5) end))
		table.insert(record.connections, row.MouseLeave:Connect(function() hover(1) end))
	end
	-- Async portraits cannot block row creation or recreate a departing player.
	task.spawn(function()
		local image = Thumbnail.GetThumbnail(other.UserId)
		if alive and records[other] == record then row.PlayerImage.Image = image or "" end
	end)
end

for _, child in ipairs(rows:GetChildren()) do if child:IsA("ImageButton") then child:Destroy() end end
table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
for _, other in ipairs(Players:GetPlayers()) do addPlayer(other) end
table.insert(connections, UIS.InputBegan:Connect(function(input, processed)
	if processed or UIS:GetFocusedTextBox() or input.UserInputType ~= Enum.UserInputType.Keyboard
		or input.KeyCode ~= Enum.KeyCode.Tab or os.clock() < toggleAt then return end
	toggleAt = os.clock() + 0.1
	container.Visible = not container.Visible
end))
table.insert(connections, container.Destroying:Connect(function()
	alive = false
	disconnect(connections)
	for other in pairs(records) do removePlayer(other) end
end))
return {}
