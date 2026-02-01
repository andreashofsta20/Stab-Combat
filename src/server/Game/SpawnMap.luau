local SpawnMap = {}
local Maps = require(script.Parent:WaitForChild("Maps"))






function SpawnMap.Spawn(MapName : string)
	if not MapName then
		print("1")
		return
	end

	local mapInfo = Maps[MapName]
	if not mapInfo then
		print("2")
		warn("MODULE SPAWNMAP. Error is: invalid map name : ", MapName)
		return
	end

	local serverStorageFolder = mapInfo.MapFolder
	local folderName = serverStorageFolder.Name


	if workspace:FindFirstChild(folderName) then
		print("3")
		return
	end


	local original = game:GetService("ServerStorage"):FindFirstChild(folderName)
	if original then
		local clone = original:Clone()
		clone.Parent = workspace
		
		task.wait(4)

		for _, player in ipairs(game.Players:GetPlayers()) do
			local character = player.Character
			local LobbyMode = player:WaitForChild("leaderstats"):WaitForChild("Settings"):WaitForChild("LobbyMode").Value
			if character then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				local spawn = clone:FindFirstChild("Map") and clone.Map:FindFirstChild("Spawn")

				if hrp and spawn and not LobbyMode then
					local spawnCFrame = spawn.CFrame * CFrame.new(0, 10, 0)
					hrp.CFrame = spawnCFrame
					
				else
					warn("LobbyMode enabled", player.Name)
				end
			end
		end
	else
		print("4")
		warn("MODULE SPAWNMAP. Couldn't find map for : ", folderName)
	end
	
	
end

function SpawnMap.RemoveAllMaps()
	for _, v in pairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name ~= "IntermissionMap" then
			v:Destroy()
		end
	end
end

function SpawnMap.RemoveOtherMapsThen(MapName : string)
	
	local mapInfo = Maps[MapName]
	if not mapInfo then
		warn("SpawnMap: Error: invalid map name : ", MapName)
		return
	end

	local serverStorageFolder = mapInfo.MapFolder
	local folderName = serverStorageFolder.Name
	
	
	for i , v in pairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name ~= folderName and v.Name ~= "IntermissionMap" then
			v:Destroy()
		end
	end
end

return SpawnMap
