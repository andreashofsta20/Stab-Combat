local Player = game.Players.LocalPlayer
local Character = Player.Character

local EmotesFolder: Folder = Player:WaitForChild("leaderstats"):WaitForChild("Emotes")
local ReplicatedEmotes = game:GetService("ReplicatedStorage"):WaitForChild("Emotes")

if not Character then
	while not Character do
		Character = Player.CharacterAdded:Wait()
	end
end

local humanoid:Humanoid = Character:WaitForChild("Humanoid")

local StarterGui = Player.PlayerGui
local MainUI = StarterGui:WaitForChild("Main")
local frame = MainUI:WaitForChild("EmoteFrame"):WaitForChild("background")
local container = frame:WaitForChild("container")

local hotkey = Enum.KeyCode.G
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local EmotesModule = require(game.ReplicatedStorage.Modules:WaitForChild("Emotes"))
local RarityColorModule = require(game.ReplicatedStorage.Modules:WaitForChild("RarityColor"))

local open = false
local LastAnimationTrack: AnimationTrack?
local LastAnimation: Animation?
local isMobile = false
local decided = false

local OtherFrames = MainUI:WaitForChild("Frames")

local leaderstats = Player:WaitForChild("leaderstats")
local KeyBindFolder = leaderstats:WaitForChild("KeyBinds")
local CurrentKeyBind = nil

local function anyOtherFrameVisible(container)
	for _, v in ipairs(container:GetChildren()) do
		if v:IsA("GuiObject") and v.Visible then
			return true
		end
	end
	return false
end


UIS.InputBegan:Connect(function(input)
	if decided then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		isMobile = true
		decided = true
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		isMobile = false
		decided = true
	end
end)

while not decided do task.wait() end

local emoteFrame = MainUI:WaitForChild("Mobile")
local emoteButton = emoteFrame:WaitForChild("StuffContainer"):WaitForChild("Emote"):WaitForChild("TextButton")

Player.CharacterAdded:Connect(function(char)
	Character = char
	humanoid = Character:WaitForChild("Humanoid")
end)

local function PlayAnimation(animObj: Animation)
	if LastAnimationTrack then
		LastAnimationTrack:Stop()
	end

	local animator = humanoid:WaitForChild("Animator")
	local track = animator:LoadAnimation(animObj)
	track.Priority = Enum.AnimationPriority.Action3
	track:AdjustSpeed(16)
	track:Play()
	LastAnimationTrack = track
	LastAnimation = animObj

	task.delay(0.8, function()
		if humanoid.MoveDirection.Magnitude > 0 then
			track:Stop()
		else
			local conn
			conn = humanoid.Running:Connect(function(speed)
				if speed > 0 then
					track:Stop()
					if conn then conn:Disconnect() end
				end
			end)
		end
	end)
end

local function animateVisibility()
	if open then
		frame.Visible = true
		Lighting.Blur.Enabled = true
	else
		frame.Visible = false
		local MakeEnabled = false 
		for i, v in pairs(OtherFrames:GetChildren()) do
			if v:IsA("Frame") and v.Visible == true then
				MakeEnabled = true
				break 
			end
		end

		Lighting.Blur.Enabled = MakeEnabled
	end
end

local function parseInput(inputString)
	if not inputString or inputString == "" then
		return nil
	end

	if inputString:find("Enum.KeyCode.") then
		local keyName = inputString:match("Enum%.KeyCode%.(.+)")
		if keyName and Enum.KeyCode[keyName] then
			return Enum.KeyCode[keyName]
		end
	elseif inputString == "MouseButton1" then
		return "MouseButton1"
	end
	return nil
end


local function initializeKeyBind()
	local emoteKeyBind = KeyBindFolder:WaitForChild("Emote")

	-- Wait for the value to be properly set
	if emoteKeyBind.Value == "" or emoteKeyBind.Value == nil then
		-- If it's empty on first join, wait a moment for it to be set by the server
		task.wait(0.1)
	end

	local parsedKey = parseInput(emoteKeyBind.Value)
	CurrentKeyBind = parsedKey or Enum.KeyCode.G

	print("Initialized keybind to:", CurrentKeyBind) -- Debug print
end

initializeKeyBind()


UIS.InputBegan:Connect(function(key, gp)
	if gp then return end
	if UIS:GetFocusedTextBox() ~= nil then return end

	if typeof(CurrentKeyBind) == "EnumItem" and key.UserInputType == Enum.UserInputType.Keyboard then
		if key.KeyCode == CurrentKeyBind then
			open = true
			animateVisibility()
		end
	end
end)

UIS.InputEnded:Connect(function(key, gp)
	if gp then return end
	if UIS:GetFocusedTextBox() ~= nil then return end
	if key.KeyCode == CurrentKeyBind then
		open = false
		animateVisibility()
		if LastAnimation then
			PlayAnimation(LastAnimation)
		end
	end
end)


local emoteState = {}

local function disconnectAll(conns)
	for _, c in ipairs(conns) do
		if c and c.Disconnect then
			c:Disconnect()
		end
	end
end

local function teardownEmote(name)
	local state = emoteState[name]
	if not state then return end

	if state.dummyAnim then
		pcall(function() state.dummyAnim:Stop() end)
	end
	disconnectAll(state.conns or {})
	if state.viewport and state.viewport:IsA("ViewportFrame") then
		state.viewport.Visible = false
	end
	if state.frame and state.frame:IsA("GuiObject") then
		state.frame.Visible = true
		if RarityColorModule.Common and RarityColorModule.Common.Image then
			state.frame.Image = RarityColorModule.Common.Image
		end
	end

	emoteState[name] = nil
end

local function getAnimationForEmote(emoteValueObj: StringValue)
	local animObj = ReplicatedEmotes:FindFirstChild(emoteValueObj.Name)
	if animObj and animObj:IsA("Animation") then
		return animObj
	end

	local a = Instance.new("Animation")
	a.AnimationId = emoteValueObj.Value
	a.Name = emoteValueObj.Name
	return a
end

local function setupEmote(emoteValueObj: StringValue)
	local emoteName = emoteValueObj.Name

	if emoteState[emoteName] then
		teardownEmote(emoteName)
	end

	local conns = {}


	local frameBtn: ImageButton = container:FindFirstChild(emoteName)


	if not frameBtn then
		warn("No frame found for emote", emoteName)
		return
	end

	if frameBtn:GetAttribute("DefaultImage") == nil then
		frameBtn:SetAttribute("DefaultImage", frameBtn.Image)
	end

	frameBtn.Visible = true

	local rar = EmotesModule[emoteName] and EmotesModule[emoteName].Rarity
	if rar and RarityColorModule[rar] then
		frameBtn.Image = RarityColorModule[rar].Image
	end

	local AnimationNeeded = getAnimationForEmote(emoteValueObj)

	local ViewPortFrame = frameBtn:WaitForChild("EmoteViewport")
	if ViewPortFrame then
		ViewPortFrame.Visible = true
	end
	local dummy = ViewPortFrame:WaitForChild("World"):WaitForChild("Rig")

	local dummyAnim = dummy.Humanoid:LoadAnimation(AnimationNeeded)
	dummyAnim.Looped = true
	dummyAnim:Play()
	dummyAnim:AdjustSpeed(0)

	table.insert(conns, frameBtn.MouseEnter:Connect(function()
		LastAnimation = AnimationNeeded
		dummyAnim:AdjustSpeed(1)
		frameBtn.Size = UDim2.new(0.286, 0, 0.286, 0)
	end))

	table.insert(conns, frameBtn.MouseLeave:Connect(function()
		LastAnimation = nil
		dummyAnim:AdjustSpeed(0)
		frameBtn.Size = UDim2.new(0.262, 0, 0.262, 0)
	end))

	table.insert(conns, frameBtn.MouseButton1Up:Connect(function()
		PlayAnimation(AnimationNeeded)
		open = false
		animateVisibility()
	end))

	table.insert(conns, emoteValueObj:GetPropertyChangedSignal("Value"):Connect(function()
		setupEmote(emoteValueObj)
	end))

	emoteState[emoteName] = {
		conns = conns,
		dummyAnim = dummyAnim,
		frame = frameBtn,
		viewport = ViewPortFrame
	}
end

local function fullRefresh()
	for name, _ in pairs(emoteState) do
		if not EmotesFolder:FindFirstChild(name) then
			teardownEmote(name)
		end
	end

	for _, v in ipairs(EmotesFolder:GetChildren()) do
		if v:IsA("StringValue") then
			setupEmote(v)
		end
	end
end

fullRefresh()

EmotesFolder.ChildAdded:Connect(function(child)
	if child:IsA("StringValue") then
		setupEmote(child)
	end
end)

EmotesFolder.ChildRemoved:Connect(function(child)
	teardownEmote(child.Name)
end)

if isMobile then
	emoteFrame.Visible = true
	emoteButton.Visible = true

	emoteButton.MouseButton1Up:Connect(function()
		open = not open
		animateVisibility()
	end)
end



KeyBindFolder:WaitForChild("Emote").Changed:Connect(function()
	local newValue = KeyBindFolder.Emote.Value
	local newInput = parseInput(newValue)
	if newInput then
		CurrentKeyBind = newInput
		print("Updated keybind to:", CurrentKeyBind) -- Debug print
	else
		print("Failed to parse keybind:", newValue) -- Debug print
	end
end)

return {}
