-- Local presentation for server-registered practice targets. Visual hints do
-- not alter hits, teleport destinations, tutorial progress or rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.TutorialUIConfig)
local GuidanceConfig = Config.Guidance
local Guidance = {}

function Guidance.new(playerGui, onHint, onComplete)
	local self = {}
	local player = Players.LocalPlayer
	local snapshot, stepKey, completedKey
	local generation, destroyed = 0, false
	local highlights, targets, targetConnections = {}, {}, {}
	local hotbarStroke, hotbarSlot
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "TutorialGuidance", workspace
	local marker = Instance.new("BillboardGui")
	marker.Name, marker.Size = "TrainingTarget", UDim2.fromOffset(160, 48)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	marker.AlwaysOnTop, marker.MaxDistance = false, GuidanceConfig.MarkerMaxDistance
	marker.Enabled, marker.Parent = false, playerGui
	local markerLabel = Instance.new("TextLabel")
	markerLabel.Size, markerLabel.BackgroundColor3 = UDim2.fromScale(1, 1), Config.Colors.Background
	markerLabel.BackgroundTransparency, markerLabel.BorderSizePixel = 0.08, 0
	markerLabel.Text, markerLabel.TextColor3 = "↓  PRACTICE TARGET", Config.Colors.Accent
	markerLabel.Font, markerLabel.TextSize = Enum.Font.GothamBold, 11
	markerLabel.Parent = marker
	local rounded = Instance.new("UICorner")
	rounded.CornerRadius, rounded.Parent = UDim.new(0, 8), markerLabel
	local outline = Instance.new("UIStroke")
	outline.Color, outline.Transparency, outline.Parent = Config.Colors.Accent, 0.3, markerLabel

	local function clearTargets()
		for _, connection in ipairs(targetConnections) do connection:Disconnect() end
		table.clear(targetConnections)
		for _, highlight in pairs(highlights) do highlight:Destroy() end
		table.clear(highlights); table.clear(targets)
		marker.Enabled, marker.Adornee = false, nil
	end
	local function alive(model)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		return model:IsDescendantOf(workspace) and humanoid and humanoid.Health > 0
	end
	local function focusNearest()
		if destroyed then return end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local nearest, shortest = nil, math.huge
		for _, model in ipairs(targets) do
			local targetRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			local live = alive(model)
			local highlight = highlights[model]
			if highlight then highlight.Enabled = live == true end
			if live and targetRoot and targetRoot:IsA("BasePart") then
				local distance = root and (targetRoot.Position - root.Position).Magnitude or 0
				if distance < shortest then nearest, shortest = targetRoot, distance end
			end
		end
		marker.Adornee, marker.Enabled = nearest, nearest ~= nil
	end
	local function setTargets(list)
		local nextTargets = {}
		if type(list) == "table" then
			for _, model in ipairs(list) do
				if #nextTargets >= GuidanceConfig.MaxTargets then break end
				if typeof(model) == "Instance" and model:IsA("Model") and not table.find(nextTargets, model) then
					table.insert(nextTargets, model)
				end
			end
		end
		local same = #nextTargets == #targets
		if same then for index, model in ipairs(nextTargets) do if targets[index] ~= model then same = false; break end end end
		if same then focusNearest(); return end
		clearTargets()
		targets = nextTargets
		for _, model in ipairs(targets) do
			local highlight = Instance.new("Highlight")
			highlight.Name, highlight.Adornee = "PracticeTarget", model
			highlight.FillColor, highlight.OutlineColor = Config.Colors.Accent, Config.Colors.Accent
			highlight.FillTransparency, highlight.OutlineTransparency = 0.9, 0.2
			highlight.DepthMode, highlight.Parent = Enum.HighlightDepthMode.Occluded, folder
			highlights[model] = highlight
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then table.insert(targetConnections, humanoid.Died:Connect(focusNearest)) end
			table.insert(targetConnections, model.AncestryChanged:Connect(focusNearest))
		end
		focusNearest()
	end
	local function updateHotbar()
		local kind = snapshot and snapshot.Step and snapshot.Step.Kind
		local slotName = kind and GuidanceConfig.SlotsByKind[kind]
		local main = playerGui:FindFirstChild("Main")
		local bottom = main and main:FindFirstChild("Bottom")
		local slot = slotName and bottom and bottom:FindFirstChild(slotName)
		if slot == hotbarSlot and hotbarStroke and hotbarStroke.Parent then return end
		if hotbarStroke then hotbarStroke:Destroy(); hotbarStroke = nil end
		hotbarSlot = slot
		if slot and slot:IsA("GuiObject") then
			hotbarStroke = Instance.new("UIStroke")
			hotbarStroke.Name, hotbarStroke.Color = "TutorialFocus", Config.Colors.Accent
			hotbarStroke.Thickness, hotbarStroke.Transparency = 3, 0.1
			hotbarStroke.ApplyStrokeMode, hotbarStroke.Parent = Enum.ApplyStrokeMode.Border, slot
		end
	end
	local function graduatedHint(level)
		if not snapshot or not snapshot.Step then return end
		local step = snapshot.Step
		local hints = type(step.Hints) == "table" and step.Hints or GuidanceConfig.Hints[step.Kind]
		local text = hints and hints[level]
		if text and onHint then onHint(text, level) end
	end
	local function success()
		if completedKey == stepKey then return end
		completedKey = stepKey
		if onComplete then onComplete() end
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local sounds = assets and assets:FindFirstChild("Sounds")
		local sound = sounds and sounds:FindFirstChild(GuidanceConfig.SuccessSound)
		if sound and sound:IsA("Sound") then sound:Play() end
	end
	local function scheduleStep()
		generation += 1
		local token = generation
		local startedAt = type(snapshot.StepStartedAt) == "number" and snapshot.StepStartedAt or workspace:GetServerTimeNow()
		local elapsed = math.max(0, workspace:GetServerTimeNow() - startedAt)
		for level, seconds in ipairs(GuidanceConfig.HintAfterSeconds) do
			if elapsed >= seconds then graduatedHint(level)
			else task.delay(seconds - elapsed, function()
				if destroyed or generation ~= token or completedKey == stepKey then return end
				graduatedHint(level)
			end) end
		end
		-- One bounded timer chain per active lesson, with no remote calls or
		-- frame-by-frame world scans. Step changes invalidate the old chain.
		local function refresh()
			if destroyed or generation ~= token then return end
			focusNearest(); updateHotbar()
			task.delay(GuidanceConfig.TargetRefreshSeconds, refresh)
		end
		refresh()
	end
	function self.Update(nextSnapshot)
		if destroyed then return end
		snapshot = nextSnapshot
		if type(snapshot) ~= "table" or snapshot.Mode ~= "Active" or type(snapshot.Step) ~= "table" then
			generation += 1; stepKey = nil; clearTargets()
			if hotbarStroke then hotbarStroke:Destroy(); hotbarStroke = nil end
			hotbarSlot = nil
			if onHint then onHint("", 0) end
			return
		end
		local nextKey = tostring(snapshot.StepIndex) .. ":" .. tostring(snapshot.Step.Id)
		local changed = stepKey ~= nextKey
		stepKey = nextKey
		setTargets(snapshot.Targets); updateHotbar()
		if changed then
			completedKey = nil
			if onHint then onHint("", 0) end
			scheduleStep()
		end
		local goal, progress = snapshot.Step.Goal, snapshot.Progress
		if snapshot.Step.Kind ~= "Read" and type(goal) == "number" and goal > 0 and type(progress) == "number" and progress >= goal then success() end
		if type(snapshot.HintLevel) == "number" and snapshot.HintLevel > 0 then graduatedHint(math.clamp(math.floor(snapshot.HintLevel), 1, 2)) end
	end
	function self.Destroy()
		if destroyed then return end
		destroyed = true; generation += 1
		clearTargets()
		if hotbarStroke then hotbarStroke:Destroy() end
		marker:Destroy(); folder:Destroy()
	end
	return self
end

return Guidance
