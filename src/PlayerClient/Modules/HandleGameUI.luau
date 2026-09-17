local HandleGameUI = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local inGameGui = playerGui:WaitForChild("Main"):WaitForChild("InGame")
local battleRoyaleUI = inGameGui:WaitForChild("BR")
local ffaUI = inGameGui:WaitForChild("FFA")
local battleRoyaleList = battleRoyaleUI:WaitForChild("Top"):WaitForChild("PlayerList")
local ffaList = ffaUI:WaitForChild("Top"):WaitForChild("PlayerList")

local templates = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InGameUITemplates")
local ffaTemplate = templates:WaitForChild("FFA"):WaitForChild("PlayerTemplate")
local battleRoyaleTemplate = templates:WaitForChild("BR"):WaitForChild("PlayerTemplate")

local gameActive = ReplicatedStorage:WaitForChild("GameActive")
local spectateFrame = playerGui:WaitForChild("Main"):WaitForChild("SpectateFrame")

local GOLD = Color3.fromRGB(253, 194, 46)

local function getMode()
	local mode = localPlayer:GetAttribute("CurrentRoundMode")
	if mode == "FFA" or mode == "Free For All" then
		return "FFA"
	elseif mode == "BR" or mode == "BattleRoyale" or mode == "Battle Royale" then
		return "BR"
	end
	return nil
end

local function isRoundParticipant(player)
	return player:GetAttribute("CurrentRoundParticipant") == true
end

local function isDead(player)
	return isRoundParticipant(player) and player:GetAttribute("InRound") ~= true
end

local function clearList(list)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function setOptionalVisible(parent, name, visible)
	local object = parent:FindFirstChild(name, true)
	if object and object:IsA("GuiObject") then
		object.Visible = visible
	end
end

local function styleRow(row, player, mode)
	local kills = player:GetAttribute("CurrentRoundKills") or 0
	local dead = mode == "BR" and isDead(player)

	row.Name = player.Name
	row.LayoutOrder = dead and 100000 or -(kills * 1000) + player.UserId % 1000
	row.PlayerName.Text = player.Name
	row.PlayerKills.Text = tostring(kills)
	row.ProfileImg.Image = string.format(
		"rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420",
		player.UserId
	)

	local isLocalPlayer = player == localPlayer
	row.PlayerKills.TextColor3 = isLocalPlayer and GOLD or Color3.fromRGB(255, 255, 255)
	local stroke = row:FindFirstChild("UiStroke")
	if stroke then
		stroke.Color = isLocalPlayer and GOLD or Color3.fromRGB(255, 255, 255)
		stroke.Transparency = dead and 0.5 or 0
	end

	setOptionalVisible(row, "DeadImg", dead)
	row.PlayerKills.TextTransparency = dead and 0.53 or 0
	row.PlayerName.TextTransparency = dead and 0.45 or 0
end

local function refresh(mode)
	local list = mode == "BR" and battleRoyaleList or ffaList
	local template = mode == "BR" and battleRoyaleTemplate or ffaTemplate
	clearList(list)

	local participants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if isRoundParticipant(player) then
			table.insert(participants, player)
		end
	end

	table.sort(participants, function(a, b)
		local aKills = a:GetAttribute("CurrentRoundKills") or 0
		local bKills = b:GetAttribute("CurrentRoundKills") or 0
		if aKills == bKills then
			return a.Name < b.Name
		end
		return aKills > bKills
	end)

	for _, player in ipairs(participants) do
		local row = template:Clone()
		styleRow(row, player, mode)
		row.Parent = list
	end
end

local function hide()
	battleRoyaleUI.Visible = false
	ffaUI.Visible = false
	clearList(battleRoyaleList)
	clearList(ffaList)
end

local function update()
	local mode = getMode()
	local shouldShow = gameActive.Value
		and mode ~= nil
		and (localPlayer:GetAttribute("InRound") == true or spectateFrame.Visible)

	if not shouldShow then
		hide()
		return
	end

	battleRoyaleUI.Visible = mode == "BR"
	ffaUI.Visible = mode == "FFA"
	refresh(mode)
end

local function observePlayer(player)
	player:GetAttributeChangedSignal("CurrentRoundKills"):Connect(update)
	player:GetAttributeChangedSignal("CurrentRoundParticipant"):Connect(update)
	player:GetAttributeChangedSignal("InRound"):Connect(update)
end

gameActive.Changed:Connect(update)
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundCountdown").OnClientEvent:Connect(function(phase)
	if phase == "roundover" then
		hide()
	end
end)
spectateFrame:GetPropertyChangedSignal("Visible"):Connect(update)
localPlayer:GetAttributeChangedSignal("CurrentRoundMode"):Connect(update)
localPlayer:GetAttributeChangedSignal("InRound"):Connect(update)

Players.PlayerAdded:Connect(function(player)
	observePlayer(player)
	update()
end)

Players.PlayerRemoving:Connect(update)
for _, player in ipairs(Players:GetPlayers()) do
	observePlayer(player)
end

hide()
update()

return HandleGameUI
