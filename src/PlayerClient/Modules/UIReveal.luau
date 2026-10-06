-- Cache authored transparency once per card, then reveal only visible cards
-- within a fixed tween budget. Never move grid/list items or clone UI for fades.
local Config = require(game:GetService("ReplicatedStorage").Modules.UIAnimationConfig)
local Reveal = {}

local function properties(item)
	local names = {}
	if item:IsA("CanvasGroup") then return {"GroupTransparency"} end
	if item:IsA("GuiObject") then table.insert(names, "BackgroundTransparency") end
	if item:IsA("ImageLabel") or item:IsA("ImageButton") or item:IsA("ViewportFrame") then table.insert(names, "ImageTransparency") end
	if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
		table.insert(names, "TextTransparency"); table.insert(names, "TextStrokeTransparency")
	end
	if item:IsA("UIStroke") then table.insert(names, "Transparency") end
	return names
end
local function visibleIn(item, root)
	local ancestor = item
	while ancestor and ancestor ~= root do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
		ancestor = ancestor.Parent
	end
	return true
end
local function onScreen(card, container)
	local p, s, cp, cs = card.AbsolutePosition, card.AbsoluteSize, container.AbsolutePosition, container.AbsoluteSize
	if not p or not s or not cp or not cs or cs.X <= 0 or cs.Y <= 0 or s.X <= 0 or s.Y <= 0 then return true end
	return p.X + s.X > cp.X and p.X < cp.X + cs.X and p.Y + s.Y > cp.Y and p.Y < cp.Y + cs.Y
end

function Reveal.New(container, transitions, options)
	local style = table.clone(Config.Reveal)
	for key, value in pairs(options or {}) do style[key] = value end
	local cards, active, connections, destroyed = {}, {}, {}, false
	local controller = {}
	local function restore(record)
		transitions.Stop(record.Target, record.Goals)
		for property, value in pairs(record.Goals) do
			if record.Target[property] ~= value then record.Target[property] = value end
		end
	end
	function controller.Cancel()
		for _, record in ipairs(active) do restore(record) end
		table.clear(active)
	end
	local function remove(card)
		local entry = cards[card]
		if not entry then return end
		entry.Connection:Disconnect()
		for _, record in ipairs(entry.Targets) do restore(record) end
		cards[card] = nil
		for i = #active, 1, -1 do if active[i].Card == card then table.remove(active, i) end end
	end
	function controller.Register(card)
		if destroyed or cards[card] or not card:IsA("GuiObject") then return end
		local entry = {Targets = {}}
		local pending, count = {card}, 0
		while #pending > 0 and count < style.MaxNodesPerCard do
			local item = table.remove(pending); count += 1
			local goals = {}
			for _, property in ipairs(properties(item)) do
				local value = item[property]
				if type(value) == "number" and value < 1 then goals[property] = value end
			end
			if next(goals) then table.insert(entry.Targets, {Target = item, Goals = goals, Card = card}) end
			-- Viewport rig descendants and CanvasGroup descendants need no walk.
			if not item:IsA("ViewportFrame") and not item:IsA("WorldModel") and not item:IsA("CanvasGroup") then
				for _, child in ipairs(item:GetChildren()) do table.insert(pending, child) end
			end
		end
		entry.Connection = card.Destroying:Connect(function() remove(card) end)
		cards[card] = entry
	end
	function controller.Play()
		if destroyed then return end
		controller.Cancel()
		if not transitions.Enabled(container) then return end
		local visible = {}
		for card, entry in pairs(cards) do
			if card.Visible and onScreen(card, container) then table.insert(visible, {Card = card, Entry = entry}) end
		end
		table.sort(visible, function(a, b)
			if a.Card.LayoutOrder ~= b.Card.LayoutOrder then return a.Card.LayoutOrder < b.Card.LayoutOrder end
			return a.Card.Name < b.Card.Name
		end)
		for index = 1, math.min(#visible, style.MaxCards) do
			local card = visible[index]
			local delay = math.min((index - 1) * style.StaggerSeconds, style.MaxStaggerSeconds)
			local info = TweenInfo.new(style.Seconds, style.EasingStyle or Enum.EasingStyle.Quad,
				style.EasingDirection or Enum.EasingDirection.Out, 0, false, delay)
			for _, record in ipairs(card.Entry.Targets) do
				if #active >= style.MaxTargets then return end
				if visibleIn(record.Target, card.Card) and transitions.Enabled(record.Target) then
					for property, value in pairs(record.Goals) do record.Target[property] = math.max(value, style.StartTransparency) end
					table.insert(active, record)
					transitions.Tween(record.Target, record.Goals, info)
				end
			end
		end
	end
	function controller.Destroy()
		if destroyed then return end
		controller.Cancel(); destroyed = true
		for card in pairs(cards) do remove(card) end
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end
	for _, card in ipairs(container:GetChildren()) do controller.Register(card) end
	table.insert(connections, container.ChildAdded:Connect(controller.Register))
	table.insert(connections, container.ChildRemoved:Connect(remove))
	table.insert(connections, container.Destroying:Connect(controller.Destroy))
	return controller
end

return Reveal
