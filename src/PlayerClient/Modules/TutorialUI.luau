-- Native, asset-independent tutorial presentation. The server is the only
-- source of progress; this view never infers a hit, lesson or reward locally.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage.Modules.TutorialUIConfig)
local Cursor = require(ReplicatedStorage.Modules.MouseCursorVisibility)
local Transitions = require(script.Parent.UITransitions)
local Colors, Copy, Layout = Config.Colors, Config.Text, Config.Layout
local TutorialUI = {}

local function create(className, parent, properties)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do object[property] = value end
	object.Parent = parent
	return object
end

local function corner(parent, radius)
	create("UICorner", parent, {CornerRadius = UDim.new(0, radius or Layout.CornerRadius)})
end

local function stroke(parent, color, transparency)
	return create("UIStroke", parent, {
		Color = color or Colors.Border, Thickness = 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(parent, value)
	create("UIPadding", parent, {
		PaddingLeft = UDim.new(0, value), PaddingRight = UDim.new(0, value),
		PaddingTop = UDim.new(0, value), PaddingBottom = UDim.new(0, value),
	})
end

local function label(parent, name, text, size, color, bold, order)
	return create("TextLabel", parent, {
		Name = name, Text = text or "", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = size or 16, TextColor3 = color or Colors.Text,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, RichText = false,
		LayoutOrder = order or 0,
	})
end

local function vertical(parent, gap)
	return create("UIListLayout", parent, {
		FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 12),
	})
end

local function button(parent, name, text, primary)
	local object = create("TextButton", parent, {
		Name = name, Text = text, Size = UDim2.new(1, 0, 0, Layout.ButtonHeight),
		BackgroundColor3 = primary and Colors.Accent or Colors.Raised,
		TextColor3 = primary and Colors.AccentText or Colors.Text,
		Font = Enum.Font.GothamBold, TextSize = 15, AutoButtonColor = false,
		BorderSizePixel = 0, Selectable = true, Active = true,
	})
	corner(object, 10)
	stroke(object, primary and Colors.Accent or Colors.Border, primary and 0.7 or 0.25)
	return object
end

local function safeText(value, fallback)
	return type(value) == "string" and value:sub(1, 3000) or fallback or ""
end

local function number(value, fallback)
	return type(value) == "number" and value == value and math.abs(value) < 1e12 and value or fallback or 0
end

local function integer(value)
	local valueNumber = math.max(0, math.floor(number(value)))
	local text = tostring(valueNumber)
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function TutorialUI.new(playerGui, onAction, getHint)
	local self = {}
	local player = Players.LocalPlayer
	local connections, mainConnections, transitions = {}, {}, {}
	local destroyed, busy, lobbyAllowed, exitConfirmation = false, false, false, false
	local current, modalAction, secondaryAction = {Mode = "Hidden"}, nil, nil
	local guidanceText, pulseGeneration = "", 0
	local main, gate, previousSelection, ownsSelection
	local function connect(signal, callback, list)
		table.insert(list or connections, signal:Connect(callback))
	end
	local function disconnect(list)
		for _, connection in ipairs(list) do connection:Disconnect() end
		table.clear(list)
	end

	local screen = create("ScreenGui", playerGui, {
		Name = "TrainingGui", ResetOnSpawn = false, DisplayOrder = Config.DisplayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ClipToDeviceSafeArea = true,
	})
	local root = create("Frame", screen, {Name = "SafeArea", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1})
	local backdrop = create("TextButton", root, {
		Name = "ModalBackdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.32, Text = "", AutoButtonColor = false,
		BorderSizePixel = 0, Active = true, Selectable = false, Modal = true, Visible = false,
	})
	local modal = create("Frame", root, {
		Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.ModalWidth, Layout.ModalHeight),
		BackgroundColor3 = Colors.Background, BorderSizePixel = 0, Visible = false,
		SelectionGroup = true, SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop, SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	corner(modal); stroke(modal)
	create("Frame", modal, {Name = "AccentLine", Size = UDim2.new(1, -40, 0, 3), Position = UDim2.fromOffset(20, 0), BackgroundColor3 = Colors.Accent, BorderSizePixel = 0})
	local modalHeader = create("Frame", modal, {Name = "Header", Size = UDim2.new(1, -40, 0, 33), Position = UDim2.fromOffset(20, 21), BackgroundTransparency = 1})
	label(modalHeader, "Eyebrow", Copy.Eyebrow, 11, Colors.Accent, true)
	local modalScroll = create("ScrollingFrame", modal, {
		Name = "Content", Position = UDim2.fromOffset(20, 60), Size = UDim2.new(1, -40, 1, -193),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Border, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, Selectable = true,
	})
	padding(modalScroll, 2); vertical(modalScroll, 16)
	local title = label(modalScroll, "Title", Copy.OfferTitle, 30, Colors.Text, true, 1)
	local body = label(modalScroll, "Body", Copy.OfferBody, 16, Colors.Muted, false, 2)
	local location = create("Frame", modalScroll, {Name = "Location", Size = UDim2.new(1, -4, 0, 35), BackgroundColor3 = Colors.Surface, BorderSizePixel = 0, LayoutOrder = 3})
	corner(location, 8); padding(location, 10)
	label(location, "Text", Copy.Location, 10, Colors.Accent, true)
	local lessons = create("Frame", modalScroll, {Name = "Lessons", Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4})
	vertical(lessons, 15)
	for index, lesson in ipairs(Config.Lessons) do
		local row = create("Frame", lessons, {Name = "Lesson" .. index, Size = UDim2.new(1, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = index})
		local badge = create("TextLabel", row, {Name = "Number", Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Colors.Raised, BorderSizePixel = 0, Text = string.format("%02d", index), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Colors.Accent})
		corner(badge, 8)
		local content = create("Frame", row, {Name = "Text", Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -44, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1})
		vertical(content, 5)
		label(content, "Title", lesson.Title, 12, Colors.Text, true, 1)
		label(content, "Body", lesson.Body, 13, Colors.Muted, false, 2)
	end
	local rewardsSection = create("Frame", modalScroll, {Name = "Rewards", Size = UDim2.new(1, -4, 0, 116), BackgroundTransparency = 1, LayoutOrder = 5})
	local rewardsHeading = label(rewardsSection, "Heading", Copy.RewardsTitle, 10, Colors.Muted, true)
	local rewardCards = {}
	for index, definition in ipairs({{"XP", Colors.Accent}, {"GOLD", Colors.Gold}, {"KNIFE", Colors.Success}}) do
		local card = create("Frame", rewardsSection, {
			Name = definition[1], Size = UDim2.new(1 / 3, -8, 0, 76),
			Position = UDim2.new((index - 1) / 3, index == 1 and 0 or 4, 0, 27),
			BackgroundColor3 = Colors.Surface, BorderSizePixel = 0,
		})
		corner(card, 10); stroke(card, definition[2], 0.7); padding(card, 10)
		vertical(card, 7)
		label(card, "Category", definition[1], 10, definition[2], true, 1)
		rewardCards[index] = label(card, "Value", "—", index == 3 and 13 or 19, Colors.Text, true, 2)
	end
	local rewardNote = label(modalScroll, "RewardNote", Copy.RewardPending, 12, Colors.Muted, false, 6)
	local message = label(modalScroll, "Message", "", 13, Colors.Error, false, 7)
	message.Visible = false
	local footer = create("Frame", modal, {Name = "Footer", Position = UDim2.new(0, 20, 1, -121), Size = UDim2.new(1, -40, 0, 101), BackgroundTransparency = 1})
	vertical(footer, 8)
	local primary = button(footer, "Primary", Copy.Start, true); primary.LayoutOrder = 1
	local secondary = button(footer, "Secondary", Copy.Dismiss, false); secondary.LayoutOrder = 2
	primary.NextSelectionDown, secondary.NextSelectionUp = secondary, primary
	primary.NextSelectionUp, modalScroll.NextSelectionDown = modalScroll, primary

	local active = create("Frame", root, {
		Name = "LessonCard", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -Layout.Margin, 0, Layout.Margin),
		Size = UDim2.fromOffset(Layout.ActiveWidth, Layout.ActiveHeight), BackgroundColor3 = Colors.Background,
		BorderSizePixel = 0, Visible = false,
	})
	corner(active, 12)
	local activeBorder = stroke(active)
	local stepLabel = create("TextLabel", active, {Name = "Step", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32, 0, 16), Text = "", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Colors.Accent, TextXAlignment = Enum.TextXAlignment.Left})
	local activeTitle = create("TextLabel", active, {Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -32, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextWrapped = true, TextColor3 = Colors.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top})
	local successBanner = create("TextLabel", active, {Name = "LessonSuccess", Position = UDim2.fromOffset(16, 35), Size = UDim2.new(1, -32, 0, 45), BackgroundColor3 = Colors.Success, BorderSizePixel = 0, Text = "✓  Nice work!", Font = Enum.Font.GothamBold, TextSize = 19, TextColor3 = Colors.AccentText, Visible = false, ZIndex = 3})
	corner(successBanner, 9)
	local activeScroll = create("ScrollingFrame", active, {Name = "Lesson", Position = UDim2.fromOffset(16, 88), Size = UDim2.new(1, -32, 1, -146), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Colors.Border, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y})
	padding(activeScroll, 2); vertical(activeScroll, 11)
	local activeBody = label(activeScroll, "Body", "", 14, Colors.Muted, false, 5)
	local hint = label(activeScroll, "Hint", "", 13, Colors.Accent, false, 3)
	local guidanceHint = label(activeScroll, "ExtraHint", "", 13, Colors.Gold, false, 4)
	local objective = label(activeScroll, "Objective", "", 13, Colors.Text, true, 1)
	local track = create("Frame", activeScroll, {Name = "ProgressTrack", Size = UDim2.new(1, -4, 0, 5), BackgroundColor3 = Colors.Raised, BorderSizePixel = 0, LayoutOrder = 2})
	corner(track, 3)
	local progress = create("Frame", track, {Name = "Progress", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Colors.Success, BorderSizePixel = 0})
	corner(progress, 3)
	local activeStatus = label(activeScroll, "Status", Copy.PracticeHint, 11, Colors.Muted, false, 6)
	local activeFooter = create("Frame", active, {Name = "Actions", Position = UDim2.new(0, 16, 1, -64), Size = UDim2.new(1, -32, 0, 48), BackgroundTransparency = 1})
	local continueButton = button(activeFooter, "Continue", Copy.Continue, true)
	continueButton.Size = UDim2.new(0.52, -4, 1, 0); continueButton.TextSize = 13
	local exitButton = button(activeFooter, "Exit", Copy.Exit, false)
	exitButton.Size = UDim2.new(0.48, -4, 1, 0); exitButton.Position = UDim2.new(0.52, 4, 0, 0); exitButton.TextSize = 12
	continueButton.NextSelectionRight, exitButton.NextSelectionLeft = exitButton, continueButton
	-- The lesson card changes its anchor/position at responsive breakpoints.
	-- Attach only the centered modal; an authored-position transition would
	-- restore a desktop card position after a mobile resize.
	table.insert(transitions, Transitions.Attach(modal, "Popup"))
	for _, object in ipairs({primary, secondary, continueButton, exitButton}) do
		local base = object.BackgroundColor3
		local outline = object:FindFirstChildOfClass("UIStroke")
		local function emphasize(value)
			Transitions.TweenProperty(object, "BackgroundColor3", value and base:Lerp(Colors.Text, 0.09) or base)
			if outline then outline.Color = value and Colors.Accent or (object == primary or object == continueButton) and Colors.Accent or Colors.Border end
		end
		connect(object.MouseEnter, function() if object.Active then emphasize(true) end end)
		connect(object.MouseLeave, function() emphasize(false) end)
		connect(object.SelectionGained, function() emphasize(true) end)
		connect(object.SelectionLost, function() emphasize(false) end)
	end

	local function releaseSelection()
		if ownsSelection and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
			GuiService.SelectedObject = previousSelection and previousSelection.Parent and previousSelection or nil
		end
		previousSelection, ownsSelection = nil, nil
	end
	local function focusButton(target)
		if UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad then return end
		if not ownsSelection then previousSelection = GuiService.SelectedObject; ownsSelection = true end
		GuiService.SelectedObject = target
	end

	local function updateCursor()
		local shown = modal.Visible
		local readable = current.Step and current.Step.Kind == "Read" and current.CanContinue == true
		if shown or (active.Visible and readable) then Cursor.Show("TutorialUI") else Cursor.Hide("TutorialUI") end
		if gate then gate.Visible = shown end
		if not shown and not (active.Visible and readable) then releaseSelection() end
	end
	local function bindMain()
		disconnect(mainConnections)
		local replacement = playerGui:FindFirstChild("Main")
		if main ~= replacement then
			if gate then gate:Destroy(); gate = nil end
			main = replacement
		end
		if not main then return end
		local old = main:FindFirstChild("TutorialFrame")
		if old and old:IsA("GuiObject") then old.Visible = false end
		local frames = main:FindFirstChild("Frames")
		if frames and not gate then
			gate = create("Frame", frames, {Name = "TutorialModalGate", Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = modal.Visible, Active = false, Selectable = false})
			gate:SetAttribute("UIAnimationDisabled", true)
		end
		connect(main.ChildAdded, bindMain, mainConnections)
		connect(main.ChildRemoved, function(child)
			if child == gate or child == frames then gate = nil end
			bindMain()
		end, mainConnections)
		updateCursor()
	end

	local function resize()
		local available = root.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then return end
		local margin = math.min(Layout.Margin, 12)
		local small = available.X < Layout.MobileBreakpoint
		local width = math.max(220, math.min(Layout.ModalWidth, available.X - margin * 2))
		local height = math.max(205, math.min(Layout.ModalHeight, available.Y - margin * 2))
		modal.Size = UDim2.fromOffset(width, height)
		title.TextSize = small and 24 or 30
		rewardCards[1].TextSize, rewardCards[2].TextSize = small and 16 or 19, small and 16 or 19
		local shortLandscape = available.Y < 450 and available.X > available.Y
		local activeWidth = math.min(small and 430 or Layout.ActiveWidth, available.X - margin * 2)
		if shortLandscape then activeWidth = math.min(activeWidth, available.X * 0.42) end
		local activeHeight = math.min(Layout.ActiveHeight, shortLandscape and available.Y - margin * 2 or math.max(185, available.Y * 0.48))
		active.Size = UDim2.fromOffset(activeWidth, activeHeight)
		active.AnchorPoint = small and not shortLandscape and Vector2.new(0.5, 0) or Vector2.new(1, 0)
		active.Position = small and not shortLandscape and UDim2.new(0.5, 0, 0, margin) or UDim2.new(1, -Layout.Margin, 0, Layout.Margin)
		activeTitle.TextSize = small and 18 or 20
		local contentTop = 38 + math.max(22, activeTitle.AbsoluteSize.Y) + 8
		activeScroll.Position = UDim2.fromOffset(16, contentTop)
		activeScroll.Size = UDim2.new(1, -32, 1, -(contentTop + 74))
	end

	local function setButtonEnabled(object, enabled)
		object.Active, object.Selectable, object.Interactable = enabled, enabled, enabled
		object.TextTransparency = enabled and 0 or 0.48
	end
	local function rewardValues(rewards)
		rewards = type(rewards) == "table" and rewards or {}
		rewardCards[1].Text = "+" .. integer(rewards.XP) .. " XP"
		rewardCards[2].Text = "+" .. integer(rewards.Gold) .. " Gold"
		rewardCards[3].Text = safeText(rewards.KnifeDisplayName or rewards.Knife, "Free knife")
	end

	local render
	local function send(action)
		if destroyed or busy or not action then return end
		onAction(action)
	end
	connect(primary.Activated, function()
		if exitConfirmation and modalAction == "Keep" then exitConfirmation = false; render(); return end
		send(modalAction)
	end)
	connect(secondary.Activated, function()
		if secondaryAction == "Keep" then exitConfirmation = false; render(); return end
		send(secondaryAction)
	end)
	connect(continueButton.Activated, function() if current.CanContinue == true then send("Continue") end end)
	connect(exitButton.Activated, function() if not busy then exitConfirmation = true; render() end end)
	connect(UserInputService.InputBegan, function(input, processed)
		if processed or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return end
		if active.Visible and current.Step and current.Step.Kind == "Read" and current.CanContinue == true and input.UserInputType == Enum.UserInputType.Keyboard
			and (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) then send("Continue") end
	end)

	function render()
		if destroyed then return end
		local mode = current.Mode
		local inTraining = current.CanReturn == true or (current.CanReturn == nil
			and (ReplicatedStorage:GetAttribute("TutorialPlace") == true or player:GetAttribute("TutorialActive") == true))
		local isActive = mode == "Active" and not exitConfirmation
		local isModal = exitConfirmation or mode == "Offer" or mode == "Loading" or mode == "Complete" or mode == "Error"
		local previouslyShown, previousActive = modal.Visible, active.Visible
		backdrop.Visible, modal.Visible, active.Visible = isModal, isModal, isActive
		modalAction, secondaryAction = nil, nil
		location.Visible, lessons.Visible, rewardsSection.Visible = false, false, false
		rewardNote.Visible = false
		message.Visible = false
		primary.Visible, secondary.Visible = true, true
		rewardValues(current.Rewards)
		if exitConfirmation then
			title.Text, body.Text = Copy.ExitTitle, Copy.ExitBody
			primary.Text, modalAction = Copy.KeepTraining, "Keep"
			secondary.Text, secondaryAction = Copy.Exit, "Return"
		elseif mode == "Offer" then
			title.Text = current.Replay and Copy.ReplayTitle or Copy.OfferTitle
			body.Text = current.Replay and Copy.ReplayBody or Copy.OfferBody
			location.Visible, lessons.Visible = true, true
			rewardsSection.Visible, rewardNote.Visible = not current.Replay, true
			rewardNote.Text = current.Replay and Copy.ReplayRewards or Copy.RewardPending
			primary.Text, modalAction = current.Replay and Copy.Replay or Copy.Start, current.Replay and "Replay" or "Start"
			secondary.Text, secondaryAction = Copy.Dismiss, "Dismiss"
		elseif mode == "Loading" then
			title.Text, body.Text = Copy.LoadingTitle, safeText(current.Message, Copy.LoadingBody)
			primary.Text, secondary.Visible = Copy.Waiting, false
		elseif mode == "Complete" then
			title.Text = Copy.CompleteTitle
			body.Text = current.Replay and Copy.ReplayCompleteBody or current.RewardGranted == true and Copy.CompleteBody or Copy.EarnedBody
			rewardsSection.Visible = not current.Replay
			rewardNote.Visible = inTraining and type(current.ReturnIn) == "number" and current.ReturnIn > 0
			rewardNote.Text = Copy.ReturningSoon
			primary.Text, modalAction, secondary.Visible = inTraining and Copy.Return or Copy.Play, inTraining and "Return" or "Dismiss", false
		elseif mode == "Error" then
			title.Text, body.Text = Copy.ErrorTitle, safeText(current.Message, Copy.ErrorBody)
			primary.Text, modalAction = Copy.Retry, current.RetryAction or (inTraining and "Return" or "Start")
			secondary.Text, secondaryAction = Copy.Dismiss, "Dismiss"
			secondary.Visible = not inTraining
		end
		if isActive then
			local step = type(current.Step) == "table" and current.Step or {}
			local stepIndex, count = math.max(1, math.floor(number(current.StepIndex, 1))), math.max(1, math.floor(number(current.StepCount, 1)))
			stepLabel.Text = string.format("%s  /  LESSON %02d OF %02d", safeText(step.Phase, "TRAINING"):upper(), stepIndex, count)
			activeTitle.Text = safeText(step.Title, "Training")
			activeBody.Text = safeText(step.Body, "Follow the next objective.")
			hint.Text = getHint and getHint(step) or safeText(step.Hint)
			hint.Visible = hint.Text ~= ""
			guidanceHint.Text, guidanceHint.Visible = guidanceText, guidanceText ~= ""
			local goal, done = math.max(0, number(step.Goal)), math.max(0, number(current.Progress))
			local objectiveText = safeText(step.Objective)
			objective.Text = goal > 0 and string.format("%s  %s / %s", objectiveText, integer(math.min(done, goal)), integer(goal)) or objectiveText
			objective.Visible = objective.Text ~= ""
			track.Visible = goal > 0
			Transitions.TweenProperty(progress, "Size", UDim2.fromScale(goal > 0 and math.clamp(done / goal, 0, 1) or 0, 1))
			local continueHint = UserInputService.PreferredInput == Enum.PreferredInput.Touch and Copy.TouchContinueHint
				or UserInputService.PreferredInput == Enum.PreferredInput.Gamepad and Copy.GamepadContinueHint or Copy.ContinueHint
			local completedAction = step.Kind ~= "Read" and goal > 0 and done >= goal
			activeStatus.Text = completedAction and Copy.StepComplete
				or (step.Kind == "Read" and current.CanContinue == true) and continueHint or safeText(current.Message, Copy.PracticeHint)
			continueButton.Text = busy and Copy.Waiting or Copy.Continue
			continueButton.Visible = step.Kind == "Read"
			continueButton.Modal = step.Kind == "Read" and current.CanContinue == true
			exitButton.Size = step.Kind == "Read" and UDim2.new(0.48, -4, 1, 0) or UDim2.new(0.48, 0, 1, 0)
			exitButton.Position = UDim2.new(0.52, 4, 0, 0)
			setButtonEnabled(continueButton, current.CanContinue == true and not busy)
			setButtonEnabled(exitButton, not busy)
			if not previousActive then activeScroll.CanvasPosition = Vector2.zero end
		end
		setButtonEnabled(primary, modalAction ~= nil and not busy)
		setButtonEnabled(secondary, secondaryAction ~= nil and not busy)
		if busy and primary.Visible and mode ~= "Loading" then primary.Text = Copy.Waiting end
		updateCursor()
		if isModal and not previouslyShown then modalScroll.CanvasPosition = Vector2.zero; focusButton(primary)
		elseif isActive and current.Step and current.Step.Kind == "Read" and current.CanContinue == true and (not previousActive or not GuiService.SelectedObject) then focusButton(continueButton) end
	end

	function self.Update(snapshot)
		if destroyed or type(snapshot) ~= "table" then return end
		local previousStep = current.StepIndex
		local previouslyReady = current.CanContinue == true
		current, busy = snapshot, false
		exitConfirmation = exitConfirmation and snapshot.Mode == "Active"
		if snapshot.StepIndex ~= previousStep or snapshot.Mode ~= "Active" then
			activeScroll.CanvasPosition = Vector2.zero
			guidanceText = ""
			pulseGeneration += 1
			successBanner.Visible = false
			activeBorder.Color, activeBorder.Thickness = Colors.Border, 1
		end
		render()
		if snapshot.Mode == "Active" and snapshot.Step and snapshot.Step.Kind == "Read" and snapshot.CanContinue == true
			and (not previouslyReady or snapshot.StepIndex ~= previousStep) then focusButton(continueButton) end
	end
	function self.SetGuidance(text)
		if destroyed then return end
		guidanceText = safeText(text)
		render()
	end
	function self.PulseCompletion()
		if destroyed or current.Mode ~= "Active" then return end
		pulseGeneration += 1
		local token = pulseGeneration
		successBanner.Visible = true
		activeBorder.Color, activeBorder.Thickness = Colors.Success, 2
		activeStatus.Text = Copy.StepComplete
		task.delay(Config.Guidance.SuccessPulseSeconds, function()
			if destroyed or pulseGeneration ~= token then return end
			successBanner.Visible = false
			activeBorder.Color, activeBorder.Thickness = Colors.Border, 1
		end)
	end
	function self.RefreshHints() if not destroyed then render() end end
	function self.SetBusy(value) busy = value == true; render() end
	function self.HideTravelLoading()
		if destroyed then return end
		current = {Mode = "Hidden"}
		exitConfirmation = false
		render()
	end
	function self.SetLobbyVisible(value) lobbyAllowed = value == true; render() end
	function self.SetMessage(text)
		if destroyed then return end
		busy = false; render()
		if modal.Visible then message.Text, message.Visible = safeText(text), true
		elseif active.Visible then activeStatus.Text = safeText(text) end
	end
	function self.ShowRecovery(text, action)
		if destroyed then return end
		busy, exitConfirmation = false, false
		current = {Mode = "Error", Message = safeText(text), RetryAction = action or "Status"}
		render()
	end
	function self.Destroy()
		if destroyed then return end
		destroyed = true
		disconnect(connections); disconnect(mainConnections)
		Cursor.Hide("TutorialUI"); releaseSelection()
		if gate then gate:Destroy(); gate = nil end
		for _, transition in ipairs(transitions) do transition.Destroy() end
		screen:Destroy()
	end
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), resize)
	connect(activeTitle:GetPropertyChangedSignal("AbsoluteSize"), resize)
	local function reducedMotion()
		modal:SetAttribute("UIAnimationDisabled", GuiService.ReducedMotionEnabled)
		progress:SetAttribute("UIAnimationDisabled", GuiService.ReducedMotionEnabled)
	end
	connect(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), reducedMotion)
	connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), function() render(); if modal.Visible then focusButton(primary) end end)
	connect(playerGui.ChildAdded, function(child) if child.Name == "Main" then bindMain() end end)
	connect(playerGui.ChildRemoved, function(child) if child == main then bindMain() end end)
	connect(screen.Destroying, self.Destroy)
	reducedMotion(); bindMain(); resize(); render()
	return self
end

return TutorialUI
