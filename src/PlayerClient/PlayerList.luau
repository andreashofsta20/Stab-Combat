-- // LOADING // --
repeat task.wait(1) until game.Loaded or game:IsLoaded()



-- // SERVICES // --
local RS  = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")


-- // REMOTES // --
local RemotesFolder = RS:WaitForChild("Remotes")
local ProfileHandlerFolder = RemotesFolder:WaitForChild("ProfileHandler")
local RequestViewProfileRemote = ProfileHandlerFolder:WaitForChild("RequestViewProfile")


-- // CLIENT // --
local Player = game.Players.LocalPlayer
local Players = game:GetService("Players")
local PlayerGui = Player.PlayerGui


-- // MODULES // --
local ModulesFolder = RS:WaitForChild("Modules")

local GetThumbnailModule = require(ModulesFolder:WaitForChild("GetThumbnail")) -- userid to return img
local GetLevel = require(ModulesFolder:WaitForChild("CalculateLevel"))


-- // UI // --
local MainUI = PlayerGui:WaitForChild("Main")
local TopUI = MainUI:WaitForChild("TopUI")
local PlayerListFrame = TopUI:WaitForChild("PlayerListFrame")
local PlayerList = PlayerListFrame:WaitForChild("PlayerList")
local PlayerListDeco = TopUI:WaitForChild("PlayerListInfo")


-- // TEMPLATES // --
local PlayerListTemplateFolder = RS:WaitForChild("UITemplates"):WaitForChild("PlayerListTemplates")
local PlayerListTemplate = PlayerListTemplateFolder:WaitForChild("PlayerListTemplate")


-- // Debounce // --
local db = false
local DBDELAY = 0.1








local function AddPlayerToList(player : Player)
	if not player then return end
	local leaderstats = player:WaitForChild("leaderstats")
	local XP = leaderstats:WaitForChild("XP")
	
	
	
	
	local level = GetLevel.GetLevel(XP.Value)
	
	
	if PlayerList:FindFirstChild(player.Name) then
		return
	end
	
	

	local Template = PlayerListTemplate:Clone()
	Template:WaitForChild("ProfileImgFrame"):WaitForChild("ProfileImg").Image = GetThumbnailModule.GetThumbnail(player.UserId)
	Template:WaitForChild("LevelText").Text = tostring(level)
	Template.Name = player.Name
	Template:WaitForChild("PlayerName").Text = player.Name
	Template:WaitForChild("LoadProfileButton").MouseButton1Up:Connect(function()
		RequestViewProfileRemote:FireServer(player.UserId)
	end)
	Template.Parent = PlayerList
	
	XP:GetPropertyChangedSignal("Value"):Connect(function()
		local newLevel = GetLevel.GetLevel(XP.Value)
		if PlayerListFrame:FindFirstChild(player.Name) then
			PlayerListFrame[player.Name].LevelText.Text = tostring(newLevel)
		end
	end)
	
	
end


local function RemovePlayerFromList(player : Player)
	if not player then return end
	
	
	local frame = PlayerList:FindFirstChild(player.Name)
	if frame then	
		frame:Destroy()
	end
	
end

local function ClearPlayerList()
	for i , v in pairs(PlayerList:GetChildren()) do
		if v:IsA("Frame") then
			v:Destroy()
		end
	end
end


local function RefreshPlayerList()
	ClearPlayerList()
	for i , player in pairs(Players:GetPlayers()) do
		if player:IsA("Player") then
			AddPlayerToList(player)
		end

	end
end



local function ShowPlayerList()
	if PlayerListFrame.Visible then
		return
	end
	
	PlayerListFrame.Visible = true
	
end

local function HidePlayerList()
	if not PlayerListFrame.Visible then
		return
	end

	PlayerListFrame.Visible = false
	
end


local function TooglePlayerList()
	if db then return end
	
	
	
	
	
	if PlayerListFrame.Visible then
		HidePlayerList()
		db = true
		task.spawn(function()
			task.wait(DBDELAY)
			db = false
		end)
	else
		ShowPlayerList()
		db = true
		task.spawn(function()
			task.wait(DBDELAY)
			db = false
		end)
	end
end


UserInputService.InputBegan:Connect(function(input, right)
	
	if right then return end
	
	
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Tab then
		TooglePlayerList()
	end
end)







Players.PlayerRemoving:Connect(function(player : Player)
	RemovePlayerFromList(player)
	
end)
Players.PlayerAdded:Connect(function(player : Player)
	AddPlayerToList(player)
end)




task.spawn(function()
	while task.wait(100) do
		RefreshPlayerList()
	end
	
	
end)


RefreshPlayerList()

return {}