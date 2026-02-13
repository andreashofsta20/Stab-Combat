local Players = game:GetService("Players")
local plr = Players.LocalPlayer

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local UITemplatesFolder = ReplicatedStorage:WaitForChild("UITemplates")
local LeaderboardTemplate = UITemplatesFolder:WaitForChild("LeaderboardTemplates")
local LeaderboardsRemotesFolder = RemotesFolder:WaitForChild("Leaderboards")
local RequestLeaderboardsRemote = LeaderboardsRemotesFolder:WaitForChild("RequestLeaderboards")
local GetThumbnailModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))
local AbbreviateModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Abbreviate"))

RequestLeaderboardsRemote:FireServer()

local function applyRankLayout(entry, rank)
	if rank == 1 then
		entry.Size = UDim2.new(0, 595, 0, 200)
		entry.Info.Rank.BackgroundColor3 = Color3.fromRGB(255, 167, 50)
		return
	end

	if rank == 2 then
		entry.Size = UDim2.new(0.5, -30, 0, 185)
		entry.Position = UDim2.new(0, 0, 0, 220)
		entry.Info.Rank.BackgroundColor3 = Color3.fromRGB(147, 147, 147)
		return
	end

	if rank == 3 then
		entry.Size = UDim2.new(0.5, -30, 0, 185)
		entry.Position = UDim2.new(1, -40, 0, 220)
		entry.Info.Rank.BackgroundColor3 = Color3.fromRGB(157, 91, 0)
		return
	end

	entry.Size = UDim2.new(0, 185, 0, 185)
	entry.Info.Rank.BackgroundColor3 = Color3.fromRGB(0, 0, 0)

	local index = rank - 4
	local col = index % 3
	local row = math.floor(index / 3)
	local yOffset = 425 + (row * 195)

	if col == 0 then
		entry.Position = UDim2.new(0, 0, 0, yOffset)
		entry.AnchorPoint = Vector2.new(0, 0)
	elseif col == 1 then
		entry.Position = UDim2.new(0.5, -20, 0, yOffset)
		entry.AnchorPoint = Vector2.new(0.5, 0)
	else
		entry.Position = UDim2.new(1, -40, 0, yOffset)
		entry.AnchorPoint = Vector2.new(1, 0)
	end
end

local function setCommonEntry(entry, data, rank)
	entry.Profile.Image = GetThumbnailModule.GetThumbnail(data.UserId)
	entry.Info.Rank.Rank.Text = "#" .. rank
	entry.Info.Username.Username.Text = data.Name
end

local function renderLeaderboard(config, entries)
	local UI = Workspace:WaitForChild("IntermissionMap")
		:WaitForChild("Leaderboards")
		:WaitForChild(config.boardName)
		:WaitForChild("Bottom")
		:WaitForChild("Leaderboard")
	local LeaderboardScroll = UI:WaitForChild("ScrollingFrame")

	local templates = {
		First = LeaderboardTemplate:WaitForChild(config.templates.First),
		Second = LeaderboardTemplate:WaitForChild(config.templates.Second),
		Third = LeaderboardTemplate:WaitForChild(config.templates.Third),
		Other = LeaderboardTemplate:WaitForChild(config.templates.Other),
	}

	LeaderboardScroll:ClearAllChildren()

	for rank, data in ipairs(entries) do
		local value = data[config.valueKey] or data.Value or 0
		local text = AbbreviateModule.Ab(value) .. config.suffix

		local template = templates.Other
		if rank == 1 then
			template = templates.First
		elseif rank == 2 then
			template = templates.Second
		elseif rank == 3 then
			template = templates.Third
		end

		local entry = template:Clone()
		applyRankLayout(entry, rank)
		setCommonEntry(entry, data, rank)
		config.setText(entry, text)
		entry.Parent = LeaderboardScroll
	end
end

local LEADERBOARD_CONFIGS = {
	{
		key = "Levels",
		boardName = "Levels",
		valueKey = "Level",
		suffix = " Levels",
		templates = {
			First = "LevelsTemplate1",
			Second = "LevelsTemplate2",
			Third = "LevelsTemplate3",
			Other = "LevelsTemplateOthers",
		},
		setText = function(entry, text)
			entry.Levels.Levels.Text = text
		end,
	},
	{
		key = "Kills",
		boardName = "Kills",
		valueKey = "Kills",
		suffix = " Kills",
		templates = {
			First = "KillsTemplate1",
			Second = "KillsTemplate2",
			Third = "KillsTemplate3",
			Other = "KillsTemplateOthers",
		},
		setText = function(entry, text)
			entry.Kills.Kills.Text = text
		end,
	},
	{
		key = "Gold",
		boardName = "Gold",
		valueKey = "Cash",
		suffix = " GOLD",
		templates = {
			First = "GoldTemplate1",
			Second = "GoldTemplate2",
			Third = "GoldTemplate3",
			Other = "GoldTemplateOthers",
		},
		setText = function(entry, text)
			entry.Gold.Gold.Text = text
		end,
	},
}

RequestLeaderboardsRemote.OnClientEvent:Connect(function(leaderboardData)
	for _, config in ipairs(LEADERBOARD_CONFIGS) do
		local entries = leaderboardData[config.key]
		if entries then
			renderLeaderboard(config, entries)
		end
	end
end)


return {}