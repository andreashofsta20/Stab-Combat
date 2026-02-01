-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	if workspace:FindFirstChild("Map1") or workspace:FindFirstChild("Map2") or workspace:FindFirstChild("Map3") then
		PlayerHoverFrame.Visible = false
		highlight.Adornee = nil
		AbleToClick = false
		HoveredPlayer = nil
		UserID = nil
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
		AbleToClick = true

		local possiblePlayer = Players:FindFirstChild(modelToHighlight.Name)
		HoveredPlayer = possiblePlayer or nil
		UserID = HoveredPlayer and HoveredPlayer.UserId or nil
	else
		PlayerHoverFrame.Visible = false
		highlight.Adornee = nil
		AbleToClick = false
		HoveredPlayer = nil
		UserID = nil
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
		print("none hovered player")
		return
	end
	

	RequestViewProfile:FireServer(HoveredPlayer.UserId)
		
end)

return {}
