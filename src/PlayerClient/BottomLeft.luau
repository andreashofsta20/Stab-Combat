-- // SERVICES // --
local Players = game:GetService("Players")

-- // PLAYER // --
local Player = Players.LocalPlayer

-- // PLAYERGUI // --
local PlayerGui = Player.PlayerGui


-- // UI // --
local GUI = PlayerGui:WaitForChild("Main")

local BottomLeftFrame = GUI:WaitForChild("BottomLeft")

local StuffContainerFrame = BottomLeftFrame:WaitForChild("StuffContainer")

local ProfileImageLabel = StuffContainerFrame:WaitForChild("Profile"):WaitForChild("ProfileImage")
local ProfileButton = StuffContainerFrame:WaitForChild("Profile")

local StuffContainerFrame = BottomLeftFrame:WaitForChild("StuffContainer")

local GoldAmountTextLabel = StuffContainerFrame:WaitForChild("Gold"):WaitForChild("Amount")



local LevelFrame = BottomLeftFrame:WaitForChild("Level")
local LevelContainer = LevelFrame:WaitForChild("Container")
local LevelBar = LevelContainer:WaitForChild("LevelBar")
local LevelText = LevelFrame:WaitForChild("LevelText")


-- // VALUES // --
local CashValue = Player:WaitForChild("leaderstats"):WaitForChild("Cash")
local XpValue = Player:WaitForChild("leaderstats"):WaitForChild("XP")


-- // MODULES // --
local Abbreviate = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Abbreviate"))
local GetLevelModule = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CalculateLevel"))
local viewremote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ProfileHandler"):WaitForChild("RequestViewProfile")



local function GetThumbnail(UserId : number)
	local i , v = pcall(function()
		return Players:GetUserThumbnailAsync(UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)

	if i then
		if v then
			return v
		end
	else
		print("couldnt find")
	end
end

local function RefreshLevel()
	local level, currentXP, toNext = GetLevelModule.GetLevel(XpValue.Value)
	local progressPercent = GetLevelModule.GetLevelProgress(XpValue.Value) 

	LevelText.Text = tostring(level)
	LevelBar.Size = UDim2.new(1, 0, progressPercent, 0)
end


XpValue:GetPropertyChangedSignal("Value"):Connect(function()
	RefreshLevel()
end)


CashValue:GetPropertyChangedSignal("Value"):Connect(function()
	local Money = Abbreviate.WithCommas(CashValue.Value)
	GoldAmountTextLabel.Text = tostring(Money) .. " GOLD"
end)

ProfileButton.MouseButton1Up:Connect(function()
	viewremote:FireServer(Player.UserId)
end)


ProfileImageLabel.Image = GetThumbnail(Player.UserId)


GoldAmountTextLabel.Text = tostring(Abbreviate.WithCommas(CashValue.Value)) .. " GOLD"


RefreshLevel()

return {}