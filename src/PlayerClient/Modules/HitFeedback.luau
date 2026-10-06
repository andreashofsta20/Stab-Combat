local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Config = require(RS.Modules.CombatFeedbackConfig)
local Audio = require(RS.Modules.CombatAudioConfig).Hit
local Feedback = {}
local initialized = false
local generation = 0
local gui, killHost, hostScale, marker, markerScale, cameraConnection
local aimPosition, markerRecord
local connections, activeSounds, cards, activeCards, damagePool = {}, {}, {}, {}, {}
local damageCursor, soundCursor = 0, 0

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function create(class, name, parent, properties)
	local object = Instance.new(class)
	object.Name = name
	for property, value in pairs(properties or {}) do object[property] = value end
	object.Parent = parent
	return object
end

local function rounded(object, radius)
	create("UICorner", "Corner", object, {CornerRadius = UDim.new(0, radius)})
end

local function cancel(record)
	if record.timer then task.cancel(record.timer); record.timer = nil end
	for _, animation in ipairs(record.tweens) do animation:Cancel(); animation:Destroy() end
	table.clear(record.tweens)
	record.version += 1
end

local function tween(record, object, seconds, goal, style)
	local animation = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	table.insert(record.tweens, animation)
	animation:Play()
end

local function later(record, seconds, fn)
	local version = record.version
	record.timer = task.delay(seconds, function()
		if not initialized or record.version ~= version then return end
		record.timer = nil
		fn()
	end)
end

local function addFade(record, object, property, visibleValue)
	table.insert(record.fade, {object = object, property = property, visibleValue = visibleValue or 0})
end

local function fade(record, hidden, seconds)
	for _, item in ipairs(record.fade) do
		local value = hidden and 1 or item.visibleValue
		if seconds then tween(record, item.object, seconds, {[item.property] = value})
		else item.object[item.property] = value end
	end
end

local function label(name, parent, position, size, textSize, color)
	return create("TextLabel", name, parent, {
		Position = position, Size = size, BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = textSize, Text = "",
		TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

local function makeCard(index)
	local record = {version = 0, tweens = {}, fade = {}}
	record.frame = create("Frame", "KillCard" .. index, killHost, {
		AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(Config.Kill.Width, Config.Kill.Height),
		BackgroundColor3 = Config.Kill.Background, BackgroundTransparency = Config.Kill.BackgroundTransparency,
		BorderSizePixel = 0, Visible = false,
	})
	rounded(record.frame, 12)
	record.scale = create("UIScale", "EntryScale", record.frame, {Scale = 1})
	local border = create("UIStroke", "Border", record.frame, {Color = Color3.fromRGB(81, 89, 106), Thickness = 1, Transparency = 0.45})
	local accent = create("Frame", "Accent", record.frame, {
		Position = UDim2.fromOffset(0, 15), Size = UDim2.fromOffset(3, 50), BorderSizePixel = 0,
		BackgroundColor3 = Config.Kill.Accent,
	})
	rounded(accent, 2)
	local portrait = create("Frame", "Portrait", record.frame, {
		Position = UDim2.fromOffset(13, 13), Size = UDim2.fromOffset(54, 54), BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(36, 41, 53),
	})
	rounded(portrait, 9)
	record.avatar = create("ImageLabel", "Avatar", portrait, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = ""})
	rounded(record.avatar, 9)
	local title = label("Killed", record.frame, UDim2.fromOffset(80, 9), UDim2.new(1, -92, 0, 17), 12, Config.Kill.Accent)
	title.Text = "KILLED"
	record.username = label("Username", record.frame, UDim2.fromOffset(80, 26), UDim2.new(1, -92, 0, 26), 20, Color3.fromRGB(249, 250, 255))
	record.xp = label("XP", record.frame, UDim2.fromOffset(80, 53), UDim2.new(1, -92, 0, 18), 13, Color3.fromRGB(183, 196, 214))
	addFade(record, record.frame, "BackgroundTransparency", Config.Kill.BackgroundTransparency)
	addFade(record, border, "Transparency", 0.45)
	addFade(record, accent, "BackgroundTransparency")
	addFade(record, portrait, "BackgroundTransparency")
	addFade(record, record.avatar, "ImageTransparency")
	for _, text in ipairs({title, record.username, record.xp}) do addFade(record, text, "TextTransparency") end
	return record
end

local function layoutCards(animate, incoming)
	for index, record in ipairs(activeCards) do
		local position = UDim2.new(0.5, 0, 1, -(index - 1) * (Config.Kill.Height + Config.Kill.Gap))
		if animate and record ~= incoming then tween(record, record.frame, Config.Kill.EnterTime, {Position = position})
		else record.frame.Position = position end
	end
end

local function hideCard(record)
	if not record.id then return end
	cancel(record)
	record.id = nil
	table.remove(activeCards, table.find(activeCards, record))
	fade(record, true, Config.Kill.ExitTime)
	tween(record, record.scale, Config.Kill.ExitTime, {Scale = 0.97})
	later(record, Config.Kill.ExitTime, function() record.frame.Visible = false end)
	layoutCards(true)
end

local function showKill(payload)
	if not Config.Kill.Enabled or type(payload) ~= "table" or type(payload.KillId) ~= "string"
		or type(payload.VictimUsername) ~= "string" or not finite(payload.VictimUserId)
		or math.abs(payload.VictimUserId) > 1e15 or payload.VictimUserId % 1 ~= 0 then return end
	for _, card in ipairs(activeCards) do if card.id == payload.KillId then return end end
	local record
	for _, card in ipairs(cards) do if not card.id and not card.frame.Visible then record = card; break end end
	-- Recycle the oldest card, including a card finishing its exit animation.
	record = record or activeCards[#activeCards] or cards[1]
	local oldIndex = table.find(activeCards, record)
	if oldIndex then table.remove(activeCards, oldIndex) end
	cancel(record)
	record.id, record.frame.Visible = payload.KillId, true
	record.username.Text = payload.VictimUsername
	-- Roblox resolves the thumbnail URI asynchronously; gameplay never waits on an avatar API call.
	record.avatar.Image = payload.VictimUserId > 0
		and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", payload.VictimUserId) or ""
	record.xp.Text = "XP earned ..."
	table.insert(activeCards, 1, record)
	layoutCards(true, record)
	record.scale.Scale = 0.94
	fade(record, true)
	fade(record, false, Config.Kill.EnterTime)
	tween(record, record.scale, Config.Kill.EnterTime, {Scale = 1}, Enum.EasingStyle.Back)
	later(record, Config.Kill.Lifetime, function() hideCard(record) end)
end

local function showReward(payload)
	if type(payload) ~= "table" or type(payload.KillId) ~= "string" or not finite(payload.XpEarned) or payload.XpEarned < 0 then return end
	for _, record in ipairs(activeCards) do
		if record.id == payload.KillId then
			record.xp.Text = string.format("+%d XP earned", math.floor(payload.XpEarned))
			return
		end
	end
end

local function makeMarker()
	markerRecord = {version = 0, tweens = {}, fade = {}}
	marker = create("Frame", "HitConfirmation", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(Config.Hit.Size, Config.Hit.Size),
		BackgroundTransparency = 1, Visible = false,
	})
	markerScale = create("UIScale", "PulseScale", marker, {Scale = 1})
	-- Open corners keep the target visible and read more crisply than a font glyph.
	for _, corner in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		local x, y = corner[1], corner[2]
		for _, size in ipairs({Vector2.new(7, 2), Vector2.new(2, 7)}) do
			local bar = create("Frame", "Corner", marker, {
				AnchorPoint = Vector2.new(x, y), Position = UDim2.fromScale(x, y),
				Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = Config.Hit.Color, BorderSizePixel = 0,
			})
			addFade(markerRecord, bar, "BackgroundTransparency")
		end
	end
end

local function makeDamage(index)
	local record = {version = 0, tweens = {}}
	record.gui = create("BillboardGui", "DamageFeedback" .. index, gui.Parent, {
		-- These are siblings of CombatFeedback, so each needs its own respawn protection.
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(160, 80), AlwaysOnTop = true, Enabled = false,
		MaxDistance = Config.Damage.MaxDistance, LightInfluence = 0,
	})
	record.text = create("TextLabel", "Amount", record.gui, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack,
		TextSize = Config.Damage.TextSize, TextColor3 = Config.Damage.Color,
		TextStrokeColor3 = Color3.fromRGB(12, 16, 24), TextStrokeTransparency = 0.15,
	})
	record.scale = create("UIScale", "PopScale", record.text, {Scale = 1})
	return record
end

function Feedback.SetAimPosition(position)
	aimPosition = position
	if marker and marker.Visible and position then marker.Position = UDim2.fromOffset(position.X, position.Y) end
end

local function showHit(victim, amount, headshot)
	local humanoid = victim and victim:FindFirstChildOfClass("Humanoid")
	local markerColor = humanoid and humanoid.Health <= 0 and Config.Hit.KillColor or Config.Hit.Color
	if Config.Hit.Enabled then
		cancel(markerRecord)
		local camera = workspace.CurrentCamera
		local position = aimPosition or (camera and camera.ViewportSize / 2) or Vector2.new(0, 0)
		marker.Position, marker.Visible, markerScale.Scale = UDim2.fromOffset(position.X, position.Y), true, 1.3
		for _, item in ipairs(markerRecord.fade) do item.object.BackgroundColor3 = markerColor end
		fade(markerRecord, false)
		tween(markerRecord, markerScale, 0.1, {Scale = 1})
		fade(markerRecord, true, Config.Hit.Lifetime)
		later(markerRecord, Config.Hit.Lifetime, function() marker.Visible = false end)
	end
	local head = victim and (victim:FindFirstChild("Head") or victim:FindFirstChild("HumanoidRootPart"))
	if not Config.Damage.Enabled or #damagePool == 0 or not head or not head:IsA("BasePart") then return end
	damageCursor = damageCursor % #damagePool + 1
	local record = damagePool[damageCursor]
	cancel(record)
	record.gui.Adornee, record.gui.Enabled = head, true
	local offset = Vector3.new(((damageCursor - 1) % 3 - 1) * 0.55, 2.6, 0)
	record.gui.StudsOffsetWorldSpace = offset
	record.text.Text = string.format("-%d", math.max(1, math.floor(amount + 0.5)))
	-- Reset every pooled style so a body hit cannot inherit a previous headshot's color or motion.
	record.text.TextColor3 = headshot and Config.Damage.HeadshotColor or Config.Damage.Color
	record.text.TextSize = headshot and Config.Damage.HeadshotTextSize or Config.Damage.TextSize
	record.text.TextTransparency, record.text.TextStrokeTransparency = 0, 0.15
	record.text.Rotation = headshot and (damageCursor % 2 == 0 and 1 or -1) * Config.Damage.HeadshotTilt or 0
	record.scale.Scale = headshot and Config.Damage.HeadshotPopScale or Config.Damage.PopScale
	tween(record, record.scale, Config.Damage.PopTime, {Scale = 1}, Enum.EasingStyle.Back)
	if headshot then tween(record, record.text, Config.Damage.PopTime, {Rotation = 0}) end
	local rise = headshot and Config.Damage.HeadshotRise or Config.Damage.Rise
	tween(record, record.gui, Config.Damage.Lifetime, {StudsOffsetWorldSpace = offset + Vector3.new(0, rise, 0)})
	local fadeTime = math.min(Config.Damage.FadeTime, Config.Damage.Lifetime)
	later(record, Config.Damage.Lifetime - fadeTime, function()
		tween(record, record.text, fadeTime, {TextTransparency = 1, TextStrokeTransparency = 1})
		later(record, fadeTime, function() record.gui.Enabled, record.gui.Adornee = false, nil end)
	end)
end

local function playHitSound(weaponKind)
	if not Audio.WeaponKinds[weaponKind] or #activeSounds == 0 then return end
	local selected = soundCursor % #activeSounds + 1
	for offset = 0, #activeSounds - 1 do
		local index = (selected + offset - 1) % #activeSounds + 1
		if not activeSounds[index].IsPlaying then selected = index; break end
	end
	soundCursor = selected
	local sound = activeSounds[selected]
	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local function bindCamera()
	if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
	local camera = workspace.CurrentCamera
	local function resize()
		hostScale.Scale = camera and math.clamp((camera.ViewportSize.X - 24) / Config.Kill.Width, 0.55, 1) or 1
		if camera then
			local width = camera.ViewportSize.X
			local halfWidth = Config.Kill.Width * hostScale.Scale / 2
			local x = math.clamp(width * Config.Kill.Position.X, halfWidth + 12, math.max(halfWidth + 12, width - halfWidth - 12))
			killHost.Position = UDim2.new(0, x, Config.Kill.Position.Y, 0)
		end
	end
	resize()
	if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
end

function Feedback.Destroy()
	if not initialized then return end
	initialized = false
	generation += 1
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
	for _, record in ipairs(cards) do cancel(record) end
	for _, record in ipairs(damagePool) do cancel(record); record.gui:Destroy() end
	if markerRecord then cancel(markerRecord) end
	for _, sound in ipairs(activeSounds) do sound:Destroy() end
	table.clear(activeSounds); table.clear(cards); table.clear(activeCards); table.clear(damagePool)
	if gui then gui:Destroy(); gui = nil end
	marker, aimPosition, markerRecord, damageCursor, soundCursor = nil, nil, nil, 0, 0
end

function Feedback.Init()
	if initialized then return end
	initialized = true
	generation += 1
	local initGeneration = generation
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local knife = RS:WaitForChild("Remotes"):WaitForChild("Knife")
	local damageRemote = knife:WaitForChild("DamageDealtClient")
	local killRemote = knife:WaitForChild("PlayerGotKilledRemote")
	if not initialized or initGeneration ~= generation then return end
	gui = create("ScreenGui", "CombatFeedback", playerGui, {
		ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 24, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	killHost = create("Frame", "KillNotifications", gui, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(Config.Kill.Position.X, Config.Kill.Position.Y),
		Size = UDim2.fromOffset(Config.Kill.Width, 0), BackgroundTransparency = 1,
	})
	hostScale = create("UIScale", "ResponsiveScale", killHost, {Scale = 1})
	for index = 1, Config.Kill.MaxActive do table.insert(cards, makeCard(index)) end
	makeMarker()
	for index = 1, Config.Damage.MaxActive do table.insert(damagePool, makeDamage(index)) end
	if Audio.SoundId ~= "" then
		for index = 1, Audio.MaxActiveSounds do
			table.insert(activeSounds, create("Sound", "CombatHit" .. index, SoundService, {
				SoundId = Audio.SoundId, Volume = Audio.Volume, PlaybackSpeed = Audio.PlaybackSpeed, Looped = false,
			}))
		end
	end
	table.insert(connections, damageRemote.OnClientEvent:Connect(function(victim, amount, weaponKind, _toolName, headshot)
		if not finite(amount) or amount <= 0 or typeof(victim) ~= "Instance" or not victim:IsA("Model") then return end
		-- Headshot classification comes from the server; older events default to a body hit.
		showHit(victim, amount, headshot == true)
		playHitSound(weaponKind)
	end))
	table.insert(connections, killRemote.OnClientEvent:Connect(function(action, payload)
		if action == "Kill" then showKill(payload)
		elseif action == "KillReward" then showReward(payload) end
	end))
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	table.insert(connections, gui.Destroying:Connect(Feedback.Destroy))
	bindCamera()
end

return Feedback
