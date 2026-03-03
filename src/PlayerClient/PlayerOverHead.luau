-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // TEMPLATE // --
local OverHeadTemplate = ReplicatedStorage:WaitForChild("Overhead")
local WinStreakImages = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WinStreakImages"))






local function CreateOverhead(player: Player, character: Model)
	local head = character:WaitForChild("Head", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (head and humanoid) then return end
	
	if head:FindFirstChild("OverheadUI_" .. player.Name) then
		head:FindFirstChild("OverheadUI_" .. player.Name):Destroy()
	end

	local overhead = OverHeadTemplate:Clone()
	overhead.Name = "OverheadUI_" .. tostring(player.Name)

	local container = overhead:WaitForChild("Container")
	local nameLabel = container:WaitForChild("PlayerName")
	local membershipBadge = container:WaitForChild("PlayerMembership")
	local leaderstats = player:WaitForChild("leaderstats")
	local settingsFolder = leaderstats:WaitForChild("Settings")
	local lobbyModeSetting = settingsFolder:WaitForChild("LobbyMode")
	local winStreakValue = leaderstats:WaitForChild("WinStreak")

	local function updateMembershipBadge()
		membershipBadge.Visible = player:GetAttribute("HasVIP") == true
	end
	updateMembershipBadge()
	player:GetAttributeChangedSignal("HasVIP"):Connect(updateMembershipBadge)

	local isSpecial = player.UserId == 9304217232
	local function updateDisplayName()
		local baseName = isSpecial and ("[FRIEND] " .. player.Name) or player.Name
		if lobbyModeSetting.Value == true then
			nameLabel.Text = baseName .. " [AFK]"
		else
			nameLabel.Text = baseName
		end
	end
	updateDisplayName()
	lobbyModeSetting:GetPropertyChangedSignal("Value"):Connect(updateDisplayName)

	if isSpecial then
		nameLabel.TextColor3 = Color3.fromHex("#F5A9D0")
	end
	
	
	container:WaitForChild("Health").Visible = true
	local healthBar = container:WaitForChild("Health"):WaitForChild("Container"):WaitForChild("HealthBar")

	local StreakFrame = overhead.Container:WaitForChild("Streak")
	local StreakFireImage = overhead.Container:WaitForChild("Streak"):WaitForChild("FireEmoji")
	local StreakAmountLabel = overhead.Container:WaitForChild("Streak"):WaitForChild("StreakValue")

	
	local function updateWinStreak()

		if winStreakValue.Value == 0 then
			StreakFrame.Visible = false
			return
		end
		StreakFrame.Visible = true

		local ImageId

		if winStreakValue.Value >= 10 then
			ImageId = WinStreakImages[10]
		elseif winStreakValue.Value >= 5 then
			ImageId = WinStreakImages[5]
		else
			ImageId = WinStreakImages[0]
		end
		
		StreakFireImage.Image = ImageId
		StreakAmountLabel.Text = tostring(winStreakValue.Value)
	end
	updateWinStreak()
	winStreakValue.Changed:Connect(updateWinStreak)


	overhead.Parent = head

	local currentTween
	humanoid.HealthChanged:Connect(function(currentHealth)
		local maxHealth = humanoid.MaxHealth
		local percent = math.clamp(currentHealth / maxHealth, 0, 1)

		if currentTween then
			currentTween:Cancel()
		end
		currentTween = TweenService:Create(

			healthBar,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(percent, 0, 1, 0)

			}
		)

		currentTween:Play()
	end)

	local scale = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	healthBar.Size = UDim2.new(scale, 0, 1, 0)
end

local function SetupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.wait()
		CreateOverhead(player, character)
	end)

	if player.Character then
		CreateOverhead(player, player.Character)
	end
end


for _, player in pairs(Players:GetPlayers()) do
	SetupPlayer(player)
end

Players.PlayerAdded:Connect(SetupPlayer)



return {}