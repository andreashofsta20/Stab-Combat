local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Validation = require(RS.Modules.KeybindValidation)
local Config = require(RS.Modules.KnifeConfig)
local Hint = {}
local gui, label, marker, binds, lastWidth
local hitMarkerUntil = 0

function Hint.Format(stabKey, throwKey, mobile, charge)
	if charge ~= nil then
		local ratio = math.clamp(charge, 0, 1)
		if ratio < Config.Throw.HoldThreshold / Config.Throw.MaxChargeTime then return "TAP TO STAB  |  HOLD TO CHARGE" end
		return string.format("THROW CHARGE %d%%  |  RELEASE TO THROW", math.floor(ratio * 100 + 0.5))
	end
	if mobile then return "TAP TO STAB  |  HOLD THROW, THEN RELEASE" end
	return string.format("[%s] TAP STAB  |  [%s] HOLD TO THROW", Validation.ToDisplay(stabKey), Validation.ToDisplay(throwKey))
end

function Hint.Init()
	if gui then return end
	local player = Players.LocalPlayer
	binds = player:WaitForChild("leaderstats"):WaitForChild("KeyBinds")
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "KnifeHUD", false, true, 20
	gui.Enabled, gui.Parent = false, player:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	-- Matches RevolverController's ammo position.
	label.AnchorPoint, label.Position = Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.88)
	label.Size, label.BackgroundTransparency = UDim2.fromOffset(420, 34), 1
	label.TextColor3, label.TextStrokeTransparency = Color3.new(1, 1, 1), 0.4
	label.Font, label.TextSize, label.TextScaled, label.Parent = Enum.Font.GothamBold, 18, true, gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize, limit.MaxTextSize, limit.Parent = 10, 18, label
	-- Matches the revolver's confirmed-hit marker, above the weapon cursor.
	marker = Instance.new("TextLabel")
	marker.Name, marker.Visible = "HitMarker", false
	marker.AnchorPoint, marker.Size, marker.BackgroundTransparency = Vector2.new(0.5, 0.5), UDim2.fromOffset(32, 32), 1
	marker.Text, marker.TextColor3, marker.TextSize, marker.Parent = "X", Color3.fromRGB(255, 210, 80), 32, gui
end

function Hint.ShowHitMarker()
	if gui and Config.Presentation.HitMarkerEnabled then
		hitMarkerUntil = os.clock() + Config.Presentation.HitMarkerSeconds
	end
end

function Hint.Update(visible, mobile, charge, aimPosition)
	if not gui then return end
	if visible ~= true then hitMarkerUntil = 0 end
	marker.Visible = visible == true and Config.Presentation.HitMarkerEnabled
		and aimPosition ~= nil and os.clock() < hitMarkerUntil
	if marker.Visible then marker.Position = UDim2.fromOffset(aimPosition.X, aimPosition.Y) end
	label.Visible = visible == true and Config.Presentation.HintEnabled
	gui.Enabled = label.Visible or marker.Visible
	if not gui.Enabled then return end
	local camera = workspace.CurrentCamera
	if camera then
		local width = math.max(1, math.min(420, camera.ViewportSize.X - 32))
		if width ~= lastWidth then label.Size, lastWidth = UDim2.fromOffset(width, 34), width end
	end
	local stab, throw = binds:FindFirstChild("Stab"), binds:FindFirstChild("ThrowKnife")
	local text = Hint.Format(stab and stab.Value or "MouseButton1", throw and throw.Value or "E", mobile, charge)
	if label.Text ~= text then label.Text = text end
end

return Hint
