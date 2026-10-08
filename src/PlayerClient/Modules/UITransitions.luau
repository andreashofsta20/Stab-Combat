-- Reusable menu/page/property transitions. Authored layout is preserved; no
-- full-tree scaling, UI creation or recursive scans in opening handlers.
local TweenService = game:GetService("TweenService")
local Config = require(game:GetService("ReplicatedStorage").Modules.UIAnimationConfig)
local Transitions = {}
local controllers = setmetatable({}, {__mode = "k"})
local propertyTweens = setmetatable({}, {__mode = "k"})
local TAB = TweenInfo.new(Config.TabSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(Config.HoverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SELECTED = Color3.fromRGB(table.unpack(Config.SelectedColor))
local DEFAULT = Color3.fromRGB(table.unpack(Config.DefaultColor))

local function settings(frame, options)
	local name = type(options) == "string" and options or frame:GetAttribute("UIAnimationProfile") or "Modal"
	local result = table.clone(Config.Profiles[name] or Config.Profiles.Modal)
	if type(options) == "table" then for key, value in pairs(options) do result[key] = value end end
	return result
end
function Transitions.Enabled(target)
	local player = game:GetService("Players").LocalPlayer
	local stats = player and player:FindFirstChild("leaderstats")
	local settingsFolder = stats and stats:FindFirstChild("Settings")
	local reduced = settingsFolder and settingsFolder:FindFirstChild("ReducedEffects")
	return Config.Enabled and not Config.ReducedMotion and not (reduced and reduced.Value) and target:GetAttribute("UIAnimationDisabled") ~= true
end

function Transitions.Attach(frame, options)
	if controllers[frame] then return controllers[frame] end
	assert(frame:IsA("GuiObject"), "UITransitions.Attach expects a GuiObject")
	local style = settings(frame, options)
	local openInfo = TweenInfo.new(style.OpenSeconds, style.OpenStyle or Enum.EasingStyle.Quint, style.OpenDirection or Enum.EasingDirection.Out)
	local closeInfo = TweenInfo.new(style.CloseSeconds, style.CloseStyle or Enum.EasingStyle.Quad, style.CloseDirection or Enum.EasingDirection.In)
	local position = frame.Position
	local groupTransparency = frame:IsA("CanvasGroup") and frame.GroupTransparency or nil
	local tween, completed, token = nil, nil, 0
	local controller, connections, destroyed = {Closing = false}, {}, false
	local function cancel()
		token += 1
		controller.Closing = false
		if completed then completed:Disconnect(); completed = nil end
		if tween then tween:Cancel(); tween:Destroy(); tween = nil end
	end
	local function reset()
		if frame.Position ~= position then frame.Position = position end
		if groupTransparency and frame.GroupTransparency ~= groupTransparency then frame.GroupTransparency = groupTransparency end
	end
	function controller.Open()
		if destroyed then return end
		if not frame.Visible then frame.Visible = true; return end
		if tween and not controller.Closing then return end
		local wasClosing = controller.Closing
		cancel()
		if not Transitions.Enabled(frame) then reset(); return end
		if not wasClosing then
			frame.Position = position + UDim2.fromOffset(0, style.OpenOffsetPixels)
			if groupTransparency then frame.GroupTransparency = 1 end
		end
		local generation = token
		local goals = {Position = position}
		if groupTransparency then goals.GroupTransparency = groupTransparency end
		tween = TweenService:Create(frame, openInfo, goals)
		completed = tween.Completed:Connect(function(state)
			if token ~= generation or state ~= Enum.PlaybackState.Completed then return end
			cancel(); reset()
		end)
		tween:Play()
	end
	function controller.Close(afterClose)
		if destroyed or controller.Closing then return end
		cancel()
		if not frame.Visible then reset(); if afterClose then afterClose() end; return end
		if not Transitions.Enabled(frame) then frame.Visible = false; reset(); if afterClose then afterClose() end; return end
		controller.Closing = true
		local generation = token
		local goals = {Position = position + UDim2.fromOffset(0, style.CloseOffsetPixels)}
		if groupTransparency then goals.GroupTransparency = 1 end
		tween = TweenService:Create(frame, closeInfo, goals)
		completed = tween.Completed:Connect(function(state)
			if token ~= generation or state ~= Enum.PlaybackState.Completed then return end
			frame.Visible = false
			if afterClose then afterClose() end
		end)
		tween:Play()
	end
	function controller.Cancel() if not destroyed then cancel(); reset() end end
	function controller.Destroy()
		if destroyed then return end
		cancel(); reset(); destroyed = true
		for _, connection in ipairs(connections) do connection:Disconnect() end
		controllers[frame] = nil
	end
	table.insert(connections, frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then controller.Open() else cancel(); reset() end
	end))
	table.insert(connections, frame.Destroying:Connect(controller.Destroy))
	controllers[frame] = controller
	return controller
end

local function stopRecord(state, record)
	for property in pairs(record.Goals) do if state.Active[property] == record then state.Active[property] = nil end end
	if record.Connection then record.Connection:Disconnect() end
	record.Tween:Cancel(); record.Tween:Destroy()
end
function Transitions.Stop(target, properties)
	local state = propertyTweens[target]
	if not state then return end
	if properties then
		for property in pairs(properties) do local record = state.Active[property]; if record then stopRecord(state, record) end end
	else
		while next(state.Active) do local _, record = next(state.Active); stopRecord(state, record) end
	end
end
-- Combine goals for a target into one tween. Cancel conflicting properties
-- before applying new ones, and release completed/cancelled/destroyed tweens.
function Transitions.Tween(target, goals, info)
	local state = propertyTweens[target]
	if not state then
		state = {Active = {}}
		propertyTweens[target] = state
		state.Connection = target.Destroying:Connect(function()
			Transitions.Stop(target)
			state.Connection:Disconnect(); propertyTweens[target] = nil
		end)
	end
	local changed = {}
	for property, value in pairs(goals) do
		local previous = state.Active[property]
		if previous and previous.Goals[property] ~= value then stopRecord(state, previous); previous = nil end
		if not previous and target[property] ~= value then changed[property] = value end
	end
	if not next(changed) then return end
	if not Transitions.Enabled(target) then for property, value in pairs(changed) do target[property] = value end; return end
	local tween = TweenService:Create(target, info or TAB, changed)
	local record = {Tween = tween, Goals = changed}
	for property in pairs(changed) do state.Active[property] = record end
	record.Connection = tween.Completed:Connect(function()
		for property in pairs(changed) do if state.Active[property] == record then state.Active[property] = nil end end
		record.Connection:Disconnect(); tween:Destroy()
	end)
	tween:Play()
end

function Transitions.TweenProperty(target, property, value, info)
	Transitions.Tween(target, {[property] = value}, info)
end

function Transitions.Collection(container, options)
	return require(script.Parent.UIReveal).New(container, Transitions, options)
end

-- Bind menu roots and their authored pages/popups once, including later-added
-- frames. Specialized spinner/spectate controllers retain their own effects.
function Transitions.BindMenus(folder)
	local bindings, connections, alive = {}, {}, true
	local function watchChildren(parent, profile)
		local function bind(child) if child:IsA("GuiObject") then Transitions.Attach(child, profile) end end
		for _, child in ipairs(parent:GetChildren()) do bind(child) end
		table.insert(connections, parent.ChildAdded:Connect(bind))
	end
	local function bind(frame)
		if not frame:IsA("GuiObject") or bindings[frame] or Config.ManagedExternally[frame.Name] then return end
		bindings[frame] = true
		Transitions.Attach(frame, "Modal")
		local function childAdded(child)
			if child.Name == "Holders" then watchChildren(child, "Page")
			elseif child.Name == "Menu" and child:IsA("GuiObject") then Transitions.Attach(child, "Page")
			elseif child:IsA("GuiObject") and string.lower(child.Name):find("popup", 1, true) then Transitions.Attach(child, "Popup") end
		end
		for _, child in ipairs(frame:GetChildren()) do childAdded(child) end
		table.insert(connections, frame.ChildAdded:Connect(childAdded))
	end
	for _, frame in ipairs(folder:GetChildren()) do bind(frame) end
	table.insert(connections, folder.ChildAdded:Connect(bind))
	local function destroy()
		if not alive then return end; alive = false
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections); table.clear(bindings)
	end
	table.insert(connections, folder.Destroying:Connect(destroy))
	return {Destroy = destroy}
end

function Transitions.Select(buttons, name)
	for _, button in ipairs(buttons) do
		button.AutoButtonColor = false
		Transitions.TweenProperty(button, "BackgroundColor3", button.Name == name and SELECTED or DEFAULT, TAB)
	end
end

function Transitions.Hover(button, authoredSize, hovered)
	local target = authoredSize
	if hovered then
		local multiplier = Config.HoverSizeMultiplier
		target = UDim2.new(authoredSize.X.Scale * multiplier, authoredSize.X.Offset * multiplier,
			authoredSize.Y.Scale * multiplier, authoredSize.Y.Offset * multiplier)
	end
	Transitions.TweenProperty(button, "Size", target, HOVER)
end

return Transitions
