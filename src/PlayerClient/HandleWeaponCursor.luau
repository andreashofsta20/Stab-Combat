local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.CursorConfig)
local MouseVisibility = require(ReplicatedStorage.Modules.MouseCursorVisibility)
local Knives = require(ReplicatedStorage.Modules.KnivesInfo)
local Revolvers = require(ReplicatedStorage.Modules.RevolversInfo)
local AimCamera = require(script.Parent.Modules.RevolverAimCamera)
local KnifeCombat = require(script.Parent.Modules.CombatController)
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "WeaponCursor", false, true, 19
gui.Enabled, gui.Parent = false, player:WaitForChild("PlayerGui")
local image = Instance.new("ImageLabel")
image.Name, image.BackgroundTransparency, image.AnchorPoint = "Cursor", 1, Vector2.new(0.5, 0.5)
image.ZIndex = 1
image.Size, image.Parent = UDim2.fromOffset(Config.HiddenMouseSize, Config.HiddenMouseSize), gui
local dot = Instance.new("Frame")
dot.Name, dot.AnchorPoint, dot.Size = "WhiteDot", Vector2.new(0.5, 0.5), UDim2.fromOffset(Config.WhiteDotSize, Config.WhiteDotSize)
dot.BackgroundColor3, dot.BorderSizePixel, dot.Parent = Color3.new(1, 1, 1), 0, gui
dot.ZIndex = 2
local outline = Instance.new("UIStroke")
outline.Color, outline.Thickness, outline.Enabled, outline.Parent = Color3.new(0, 0, 0), 2, false, dot
local character, humanoid, heldTool, weaponType
local connections = {}
local bound
local binding = "WeaponCursor"
local nextMenuCheck, blockingMenu = 0, false

local function release()
	MouseVisibility.Release(binding)
	gui.Enabled = false
	image.Visible, dot.Visible = false, false
end

local function menuOpen()
	if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return true end
	local time = workspace:GetServerTimeNow()
	if time >= nextMenuCheck then
		nextMenuCheck, blockingMenu = time + 0.1, false
		local main = player.PlayerGui:FindFirstChild("Main")
		local frames = main and main:FindFirstChild("Frames")
		if frames then
			for _, frame in ipairs(frames:GetChildren()) do
				if frame:IsA("GuiObject") and frame.Visible then blockingMenu = true; break end
			end
		end
		local emote = main and main:FindFirstChild("EmoteFrame")
		local background = emote and emote:FindFirstChild("background")
		blockingMenu = blockingMenu or (background ~= nil and background.Visible)
	end
	return blockingMenu
end

local function update()
	local stats = player:FindFirstChild("leaderstats")
	local settings = stats and stats:FindFirstChild("Settings")
	local contrast = settings and settings:FindFirstChild("HighContrastCrosshair")
	outline.Enabled = contrast and contrast.Value == true or false
	local input = UserInputService:GetLastInputType()
	local touch = input == Enum.UserInputType.Touch
	local gamepad = input.Name:match("^Gamepad") ~= nil
	if not Config.Enabled or not heldTool or heldTool.Parent ~= character or player.Character ~= character
		or not humanoid or humanoid.Health <= 0 or (touch and not Config.ShowOnTouch and weaponType ~= "Knife")
		or (Config.HideInMenus and menuOpen()) then release(); return end
	local aiming = weaponType == "Revolver" and AimCamera.IsAiming()
	local preset = weaponType == "Knife" and Config.Knife or (aiming and Config.Revolver.Aiming or Config.Revolver.Equipped)
	local cursor = preset.Image
	if cursor == "" and not Config.WhiteDotEnabled then release(); return end
	-- Never set or restore Mouse.Icon: Roblox's native shift-lock controller
	-- owns it, including icon changes made while this GUI cursor hides it.
	-- Render one GUI image below the revolver HUD's dot. Share pointer ownership
	-- with ADS so neither system restores the original pointer over the overlay.
	MouseVisibility.Acquire(binding)
	image.Visible = cursor ~= "" and (not touch or Config.ShowOnTouch)
	dot.Visible = weaponType == "Knife" and Config.WhiteDotEnabled
	gui.Enabled = image.Visible or dot.Visible
	if gui.Enabled then
		image.Image = cursor
		local camera = workspace.CurrentCamera
		local centered = aiming or gamepad or touch or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		local position = weaponType == "Knife" and KnifeCombat.GetAimScreenPosition()
			or (centered and camera and camera.ViewportSize / 2 or UserInputService:GetMouseLocation())
		image.Position = UDim2.fromOffset(position.X, position.Y)
		dot.Position = image.Position
	end
end

local function toolsChanged()
	heldTool, weaponType = nil, nil
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("FoodItem") == nil then
			if Revolvers[child.Name] then heldTool, weaponType = child, "Revolver"; break end
			if Knives[child.Name] then heldTool, weaponType = child, "Knife"; break end
		end
	end
	if heldTool then
		if not bound then
			bound = true
			RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 4, update)
		end
		update()
	else
		release()
		if bound then RunService:UnbindFromRenderStep(binding); bound = false end
	end
end

local function clearCharacter()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	heldTool, weaponType, character, humanoid = nil, nil, nil, nil
	release()
	if bound then RunService:UnbindFromRenderStep(binding); bound = false end
end

local function onCharacter(newCharacter)
	clearCharacter()
	character = newCharacter
	humanoid = character:FindFirstChildOfClass("Humanoid")
	table.insert(connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then humanoid = child end
		if child:IsA("Tool") then toolsChanged() end
	end))
	table.insert(connections, character.ChildRemoved:Connect(function(child) if child:IsA("Tool") then toolsChanged() end end))
	toolsChanged()
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(clearCharacter)
if player.Character then onCharacter(player.Character) end
return {}
