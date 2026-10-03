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

local boardStates = {}
local latestRevision = 0
local thumbnailCache, thumbnailPending, thumbnailQueue = {}, {}, {}
local activeThumbnails = 0
local function pumpThumbnails()
	while activeThumbnails < 4 and #thumbnailQueue > 0 do
		local id = table.remove(thumbnailQueue, 1)
		activeThumbnails += 1
		task.spawn(function()
			local ok, url = pcall(GetThumbnailModule.GetThumbnail, id)
			if ok and type(url) == "string" then thumbnailCache[id] = url end
			for _, entry in ipairs(thumbnailPending[id]) do
				if entry.Parent and thumbnailCache[id] then entry.Profile.Image = thumbnailCache[id] end
			end
			thumbnailPending[id] = nil
			activeThumbnails -= 1
			pumpThumbnails()
		end)
	end
end
local function assignThumbnail(entry, id)
	if thumbnailCache[id] then entry.Profile.Image = thumbnailCache[id]; return end
	entry.Profile.Image = ""
	if not thumbnailPending[id] then thumbnailPending[id] = {}; table.insert(thumbnailQueue, id) end
	table.insert(thumbnailPending[id], entry)
	pumpThumbnails()
end

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

local function renderLeaderboard(config, entries, revision)
	local state = boardStates[config.key]
	if not state then
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
		if revision ~= latestRevision then return end -- loading a streamed board can yield

		for _, item in ipairs(LeaderboardScroll:GetChildren()) do if item:IsA("GuiObject") then item:Destroy() end end
		state = {scroll = LeaderboardScroll, templates = templates, rows = {}}
		boardStates[config.key] = state
	end
	local seen = {}
	for rank, data in ipairs(entries) do
		local userId = tonumber(data.UserId)
		if not userId or userId <= 0 or userId % 1 ~= 0 then continue end
		local value = data[config.valueKey] or data.Value or 0
		local id = tostring(data.UserId)
		local kind = rank == 1 and "First" or rank == 2 and "Second" or rank == 3 and "Third" or "Other"
		local row = state.rows[id]
		if row and row.kind ~= kind then row.entry:Destroy(); row = nil end
		if not row then
			row = {entry = state.templates[kind]:Clone(), kind = kind}
			row.entry.Parent = state.scroll
			state.rows[id] = row
			assignThumbnail(row.entry, userId)
		end
		if row.rank ~= rank then
			applyRankLayout(row.entry, rank); row.entry.Info.Rank.Rank.Text = "#" .. rank; row.rank = rank
		end
		if row.name ~= data.Name then row.entry.Info.Username.Username.Text = data.Name; row.name = data.Name end
		if row.value ~= value then config.setText(row.entry, AbbreviateModule.Ab(value) .. config.suffix); row.value = value end
		seen[id] = true
	end
	for id, row in pairs(state.rows) do if not seen[id] then row.entry:Destroy(); state.rows[id] = nil end end
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
	if type(leaderboardData) ~= "table" then return end
	latestRevision += 1
	local revision = latestRevision
	for _, config in ipairs(LEADERBOARD_CONFIGS) do
		local entries = leaderboardData[config.key]
		if type(entries) == "table" then
			renderLeaderboard(config, entries, revision)
		end
	end
end)
-- Subscribe before requesting; an immediate empty/new-scope response must also
-- remove Studio/preexisting rows rather than being missed during initialization.
RequestLeaderboardsRemote:FireServer()


return {}
