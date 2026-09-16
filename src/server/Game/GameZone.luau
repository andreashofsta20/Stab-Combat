local ZoneHandler = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local NotifyClient = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Zone"):WaitForChild("RecieveClient")

-- DON'T require MainGame here - it causes circular dependency!


function ZoneHandler.NotifyPlayer(player : Player, visible : boolean)
    NotifyClient:FireClient(player, visible)
end

function ZoneHandler.SpawnZone()
	local ZoneMesh = ServerStorage:FindFirstChild("Zone"):Clone()
	ZoneMesh.Parent = workspace
end

function ZoneHandler.StartZone()
	-- Lazy require - only load when function is called
	local MainGame = require(game.ServerScriptService.Game:WaitForChild("MainGame"))

	-- PlayersInGame is a table, not a function - we'll use it directly below

	if not MainGame.GameActive then 
		return 
	end

	local Zone = workspace:FindFirstChild("Zone")
	if not Zone then 
		return 
	end

	local isBattleRoyale = MainGame.CurrentMode.Id == "BattleRoyale"
	local margin = 1.5
	local shrinkStep = Vector3.new(3, 0, 3)
	local shrinkInterval = 0.5
	-- Battle Royale reaches a tiny final core instead of stopping at a safe
	-- 100x100 area where players could avoid each other indefinitely.
	local minSize = isBattleRoyale and Vector3.new(4, 1000, 4) or Vector3.new(100, 1000, 100)
	local finalZoneDamage = 25
	local finalZoneDamageRamp = 1.2
	local finalZoneDamageCap = 1000
	ZoneHandler._zoneActive = true

	local function isInsideZone(player)
		local char = player.Character
		if not char then return false end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end

		local relativePos = Zone.CFrame:PointToObjectSpace(hrp.Position)
		local distanceFromCenter = Vector2.new(relativePos.X, relativePos.Z).Magnitude
		local radius = (math.min(Zone.Size.X, Zone.Size.Z) / 2) - margin

		return distanceFromCenter <= radius
	end

	task.spawn(function()
		while ZoneHandler._zoneActive and (Zone.Size.X > minSize.X or Zone.Size.Z > minSize.Z) do
			local targetX = math.max(Zone.Size.X - shrinkStep.X, minSize.X)
			local targetZ = math.max(Zone.Size.Z - shrinkStep.Z, minSize.Z)
			local targetSize = Vector3.new(targetX, Zone.Size.Y, targetZ)

			local tweenInfo = TweenInfo.new(shrinkInterval, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(Zone, tweenInfo, {Size = targetSize})
			tween:Play()
			tween.Completed:Wait()
		end
	end)

	task.spawn(function()
		local finalPhase = false
		while ZoneHandler._zoneActive do
			for _, player in ipairs(Players:GetPlayers()) do
				if not MainGame.PlayersInGame[player.UserId] then continue end

				local insideZone = isInsideZone(player)
				if insideZone and not finalPhase then
					if player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Main") and player.PlayerGui.Main:FindFirstChild("OutsideZone") then
						NotifyClient:FireClient(player, false)
					end
				else
					if player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Main") and player.PlayerGui.Main:FindFirstChild("OutsideZone") then
						NotifyClient:FireClient(player, true)
					end

					if player.Character and player.Character:FindFirstChild("Humanoid") then
						local damage = finalPhase and finalZoneDamage or 10
						player.Character.Humanoid:TakeDamage(damage)
					end
				end
			end

			if isBattleRoyale and not finalPhase
				and Zone.Size.X <= minSize.X and Zone.Size.Z <= minSize.Z then
				-- Once the zone is fully collapsed, damage everyone in the
				-- final core and ramp it until the round has one survivor.
				finalPhase = true
			elseif finalPhase then
				finalZoneDamage = math.min(finalZoneDamage * finalZoneDamageRamp, finalZoneDamageCap)
			end
			task.wait(0.5)
		end
	end)
end

function ZoneHandler.StopZone()
	ZoneHandler._zoneActive = false
	local Zone = workspace:FindFirstChild("Zone")
	if Zone then
		Zone:Destroy()
	end
    NotifyClient:FireAllClients(false)
end

return ZoneHandler