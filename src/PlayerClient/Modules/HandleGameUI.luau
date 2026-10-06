local HandleGameUI = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local inGameGui = playerGui:WaitForChild("Main"):WaitForChild("Ingame")
local battleRoyaleUI = inGameGui:WaitForChild("BR"):WaitForChild("Top")
local ffaUI = inGameGui:WaitForChild("FFA"):WaitForChild("Top")
local battleRoyaleList = battleRoyaleUI:WaitForChild("PlayerList")
local ffaList = ffaUI:WaitForChild("PlayerList")

local templates = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InGameUITemplates")
local ffaTemplate = templates:WaitForChild("FFA"):WaitForChild("PlayerTemplate")
local battleRoyaleTemplate = templates:WaitForChild("BR"):WaitForChild("PlayerTemplate")

local gameActive = ReplicatedStorage:WaitForChild("GameActive")
local spectateFrame = playerGui:WaitForChild("Main"):WaitForChild("SpectateFrame")


local TopOtherButtons = playerGui:WaitForChild("Main"):WaitForChild("Top"):WaitForChild("Buttons")

local GOLD = Color3.fromRGB(253, 194, 46)
local rows = {FFA = {}, BR = {}}
local playerConnections, connections = {}, {}
local destroyed = false

local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

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

local function clearRows(mode)
	for player, row in pairs(rows[mode]) do row:Destroy(); rows[mode][player] = nil end
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
	local stroke = row:FindFirstChildWhichIsA("UIStroke", true)
	if stroke then
		stroke.Color = dead and Color3.fromRGB(255, 70, 70) or (isLocalPlayer and GOLD or Color3.fromRGB(255, 255, 255))
		stroke.Transparency = dead and 0.5 or 0
	end

	setOptionalVisible(row, "DeadImg", dead)
	row.PlayerKills.TextTransparency = dead and 0.53 or 0
	row.PlayerName.TextTransparency = dead and 0.45 or 0
end

local function refresh(mode)
	local list = mode == "BR" and battleRoyaleList or ffaList
	local template = mode == "BR" and battleRoyaleTemplate or ffaTemplate
	local retained = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if playerConnections[player] and isRoundParticipant(player) then
			retained[player] = true
			local row = rows[mode][player]
			if not row then
				row = template:Clone()
				rows[mode][player] = row
				row.Parent = list
			end
			styleRow(row, player, mode)
		end
	end
	-- LayoutOrder handles kill ordering; updates retain the same UI instances.
	for player, row in pairs(rows[mode]) do
		if not retained[player] then row:Destroy(); rows[mode][player] = nil end
	end
end

local function hide()
	battleRoyaleUI.Visible = false
	ffaUI.Visible = false
	clearRows("BR")
	clearRows("FFA")
end

local function update()
	if destroyed then return end
	local mode = getMode()
	local isInRound = localPlayer:GetAttribute("InRound") == true
	TopOtherButtons.Visible = not (gameActive.Value and (isInRound or spectateFrame.Visible))
	local shouldShow = gameActive.Value
		and mode ~= nil
		and (isInRound or spectateFrame.Visible)

	if not shouldShow then
		hide()
		return
	end

	battleRoyaleUI.Visible = mode == "BR"
	ffaUI.Visible = mode == "FFA"
	clearRows(mode == "BR" and "FFA" or "BR")
	refresh(mode)
end

local function observePlayer(player)
	if playerConnections[player] then return end
	playerConnections[player] = {
		player:GetAttributeChangedSignal("CurrentRoundKills"):Connect(update),
		player:GetAttributeChangedSignal("CurrentRoundParticipant"):Connect(update),
		player:GetAttributeChangedSignal("InRound"):Connect(update),
	}
end

table.insert(connections, gameActive.Changed:Connect(update))
table.insert(connections, ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundCountdown").OnClientEvent:Connect(function(phase)
	if phase == "roundover" then
		TopOtherButtons.Visible = true
		hide()
	end
end))
table.insert(connections, spectateFrame:GetPropertyChangedSignal("Visible"):Connect(update))
table.insert(connections, localPlayer:GetAttributeChangedSignal("CurrentRoundMode"):Connect(update))

table.insert(connections, Players.PlayerAdded:Connect(function(player)
	observePlayer(player)
	update()
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	if playerConnections[player] then disconnect(playerConnections[player]); playerConnections[player] = nil end
	update()
end))
for _, player in ipairs(Players:GetPlayers()) do
	observePlayer(player)
end

function HandleGameUI.Destroy()
	if destroyed then return end
	destroyed = true
	disconnect(connections)
	for player, listeners in pairs(playerConnections) do disconnect(listeners); playerConnections[player] = nil end
	hide()
end

table.insert(connections, inGameGui.Destroying:Connect(HandleGameUI.Destroy))
clearList(battleRoyaleList)
clearList(ffaList)
hide()
update()

return HandleGameUI
