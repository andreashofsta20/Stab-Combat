-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local mouse = Player:GetMouse()
local PlayerGui = Player.PlayerGui

-- // GUI // --
local MainGUI = PlayerGui:WaitForChild("Main")
local PlayerHoverFrame = MainGUI:WaitForChild("PlayerHover")
PlayerHoverFrame.AnchorPoint = Vector2.new(0, 0)


-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ProfileRemotes = RemotesFolder:WaitForChild("ProfileHandler")

local RequestViewProfile = ProfileRemotes:WaitForChild("RequestViewProfile")


local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = PlayerGui

local gameactive = false


local AbleToClick = false
local HoveredPlayer = nil
local UserID = nil

local adorneeConnections = {}

local function clearHighlight()
	PlayerHoverFrame.Visible = false
	highlight.Adornee = nil
	AbleToClick = false
	HoveredPlayer = nil
	UserID = nil
	for _, conn in ipairs(adorneeConnections) do
		conn:Disconnect()
	end
	adorneeConnections = {}
end

local function trackAdornee(model)
	for _, conn in ipairs(adorneeConnections) do
		conn:Disconnect()
	end
	adorneeConnections = {}

	local humanoid = model:FindFirstChild("Humanoid")
	if humanoid then
		table.insert(adorneeConnections, humanoid.Died:Connect(function()
			clearHighlight()
		end))
	end

	table.insert(adorneeConnections, model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			clearHighlight()
		end
	end))
end

local function GetThumbnail(UserId: number)
	local success, result = pcall(function()
		return Players:GetUserThumbnailAsync(UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	if success then
		return result
	else
	end
end

local function changeplayer(model)
	local PlayerUsername = PlayerHoverFrame:WaitForChild("Username")
	local PlayerProfileIMG = PlayerHoverFrame:WaitForChild("ProfileImage")

	local playerName = model.Name
	local userId
	local targetPlayer = Players:FindFirstChild(playerName)

	if targetPlayer then
		userId = targetPlayer.UserId
		PlayerUsername.Text = targetPlayer.Name
	else
		PlayerUsername.Text = playerName
	end

	if userId then
		local thumb = GetThumbnail(userId)
		if thumb then
			PlayerProfileIMG.Image = thumb
		end
	else
		PlayerProfileIMG.Image = ""
	end
end

mouse.Move:Connect(function()
	if workspace:FindFirstChild("Cargo Port") or workspace:FindFirstChild("Farm") or workspace:FindFirstChild("Grids") or workspace:FindFirstChild("Tropical Island") or workspace:FindFirstChild("Classic ROBLOX") then
		clearHighlight()
		return
	end
	local target = mouse.Target
	local modelToHighlight
	local isCharacter = false
	
	if ReplicatedStorage:WaitForChild("GameActive").Value == true then
		return
	end

	if target then
		local model = target:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChild("Humanoid") then
			isCharacter = true
			modelToHighlight = model
		end
	end
	if isCharacter and modelToHighlight then
		changeplayer(modelToHighlight)
		PlayerHoverFrame.Visible = true
		highlight.Adornee = modelToHighlight
		trackAdornee(modelToHighlight)
		AbleToClick = true

		local possiblePlayer = Players:FindFirstChild(modelToHighlight.Name)
		HoveredPlayer = possiblePlayer or nil
		UserID = HoveredPlayer and HoveredPlayer.UserId or nil
	else
		clearHighlight()
	end

	local mousePos = UserInputService:GetMouseLocation()
	local viewportSize = workspace.CurrentCamera.ViewportSize

	local xOffset = 30
	local yOffset = -20

	local xScale = (mousePos.X + xOffset) / viewportSize.X
	local yScale = (mousePos.Y + yOffset) / viewportSize.Y

	PlayerHoverFrame.Position = UDim2.new(xScale, 0, yScale, 0)
end)


mouse.Button1Up:Connect(function()
	if not AbleToClick then
		return
	end
	
	if not HoveredPlayer then
--		print("none hovered player")
		return
	end

	RequestViewProfile:FireServer(HoveredPlayer.UserId)
end)

Player.CharacterAdded:Connect(function()
	clearHighlight()
end)

RunService.Heartbeat:Connect(function()
	local adornee = highlight.Adornee
	if adornee and (not adornee.Parent or not adornee:FindFirstChild("Humanoid")) then
		clearHighlight()
	end
end)

return {}
