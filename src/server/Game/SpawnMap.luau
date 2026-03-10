local SpawnMap = {}
local Maps = require(script.Parent:WaitForChild("Maps"))

local function collectSpawnParts(spawnFolder: Instance)
	local parts = {}
	for _, part in ipairs(spawnFolder:GetChildren()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function shuffleParts(parts)
	for i = #parts, 2, -1 do
		local j = math.random(i)
		parts[i], parts[j] = parts[j], parts[i]
	end
end

local function teleportPlayerToSpawn(player: Player, spawnPart: BasePart?)
	if not spawnPart then
	
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	hrp.CFrame = spawnPart.CFrame * CFrame.new(0, 10, 0)
	return true
end

function SpawnMap.Spawn(MapName: string)
	if not MapName then
		return
	end

	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("MODULE SPAWNMAP. Error is: invalid map name : ", MapName)
		return
	end

	local folderName = mapInfo.MapFolder.Name

	if workspace:FindFirstChild(folderName) then
		return
	end

	local original = game:GetService("ServerStorage"):FindFirstChild(folderName)
	if not original then
		warn("MODULE SPAWNMAP. Couldn't find map for : ", folderName)
		return
	end

	local clone = original:Clone()
	clone.Parent = workspace

	task.wait(4)

	local spawnFolder = clone:FindFirstChild("Spawns")
	if not spawnFolder then
		warn("MODULE SPAWNMAP. No Spawns folder for map : ", folderName)
		return
	end

	local spawnParts = collectSpawnParts(spawnFolder)
	if #spawnParts == 0 then
		warn("MODULE SPAWNMAP. No spawn parts found in Spawns folder for map : ", folderName)
		return
	end

	shuffleParts(spawnParts)

	local players = game.Players:GetPlayers()
	local spawnCount = #spawnParts
	local reuseSpawns = spawnCount < #players
	if reuseSpawns then
		warn("MODULE SPAWNMAP. More players than spawns; some spawns will be reused.")
	end

	local usedIndex = 0
	for _, player in ipairs(players) do
		local lobbyMode = player:WaitForChild("leaderstats"):WaitForChild("Settings"):WaitForChild("LobbyMode").Value
		if not lobbyMode then
			usedIndex += 1
			local spawnPart = reuseSpawns and spawnParts[((usedIndex - 1) % spawnCount) + 1] or spawnParts[usedIndex]
			local ok = teleportPlayerToSpawn(player, spawnPart)
			if not ok then
				warn("MODULE SPAWNMAP. Failed to teleport player", player.Name)
			end
		end
	end
end

function SpawnMap.RemoveAllMaps()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name ~= "IntermissionMap" then
			v:Destroy()
		end
	end
end

function SpawnMap.RemoveOtherMapsThen(MapName: string)
	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("SpawnMap: Error: invalid map name : ", MapName)
		return
	end

	local folderName = mapInfo.MapFolder.Name

	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name ~= folderName and v.Name ~= "IntermissionMap" then
			v:Destroy()
		end
	end
end

return SpawnMap
