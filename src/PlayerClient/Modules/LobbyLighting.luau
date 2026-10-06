local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LobbyLighting = {}

local function colorFloor(base, r, g, b)
	return Color3.new(math.max(base.R, r / 255), math.max(base.G, g / 255), math.max(base.B, b / 255))
end

-- Local readability fill preserves the saved time-of-day preference and authored
-- combat lighting. No extra lights, shadow maps, frame loop or map scan is needed.
function LobbyLighting.New(player, daySetting)
	local gameActive = ReplicatedStorage:WaitForChild("GameActive")
	local baseline = {
		Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
	local connections, cameraConnections = {}, {}
	local tween, completedConnection, profile, destroyed

	local function cancelTween()
		if completedConnection then completedConnection:Disconnect(); completedConnection = nil end
		if tween then tween:Cancel(); tween:Destroy(); tween = nil end
	end
	local function isLobbyView()
		if player:GetAttribute("InRound") == true then return false end
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Scripted death views and watching another player's avatar use round light.
		if camera and (camera.CameraType ~= Enum.CameraType.Custom
			or (camera.CameraSubject and camera.CameraSubject ~= humanoid)) then return false end
		return not gameActive.Value or (humanoid ~= nil and humanoid.Health > 0)
	end
	local function update()
		if destroyed then return end
		local day, lobby = daySetting.Value == true, isLobbyView()
		local nextProfile = (day and "Day" or "Night") .. (lobby and "Lobby" or "Round")
		if nextProfile == profile then return end
		profile = nextProfile
		cancelTween()
		local goals = {
			ClockTime = day and 14.5 or 20,
			Ambient = baseline.Ambient, OutdoorAmbient = baseline.OutdoorAmbient,
			ExposureCompensation = baseline.ExposureCompensation,
		}
		if lobby then
			goals.Ambient = day and colorFloor(baseline.Ambient, 88, 90, 98) or colorFloor(baseline.Ambient, 76, 86, 108)
			goals.OutdoorAmbient = day and colorFloor(baseline.OutdoorAmbient, 112, 114, 122) or colorFloor(baseline.OutdoorAmbient, 98, 110, 134)
			goals.ExposureCompensation = math.max(baseline.ExposureCompensation, day and 0 or 0.18)
		end
		tween = TweenService:Create(Lighting, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), goals)
		completedConnection = tween.Completed:Connect(function()
			if completedConnection then completedConnection:Disconnect(); completedConnection = nil end
			if tween then tween:Destroy(); tween = nil end
		end)
		tween:Play()
	end
	local function bindCamera()
		for _, connection in ipairs(cameraConnections) do connection:Disconnect() end
		table.clear(cameraConnections)
		local camera = workspace.CurrentCamera
		if camera then
			table.insert(cameraConnections, camera:GetPropertyChangedSignal("CameraSubject"):Connect(update))
			table.insert(cameraConnections, camera:GetPropertyChangedSignal("CameraType"):Connect(update))
		end
		update()
	end
	table.insert(connections, daySetting:GetPropertyChangedSignal("Value"):Connect(update))
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(update))
	table.insert(connections, player.CharacterAdded:Connect(update))
	table.insert(connections, player.CharacterRemoving:Connect(update))
	table.insert(connections, gameActive:GetPropertyChangedSignal("Value"):Connect(update))
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	bindCamera()
	local controller = {}
	function controller.Destroy()
		if destroyed then return end
		destroyed = true
		cancelTween()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		for _, connection in ipairs(cameraConnections) do connection:Disconnect() end
		table.clear(connections); table.clear(cameraConnections)
		for property, value in pairs(baseline) do Lighting[property] = value end
	end
	return controller
end

return LobbyLighting
