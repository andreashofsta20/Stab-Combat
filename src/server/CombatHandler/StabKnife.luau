local KnifeModule = {}
-- // SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- // MODULES
local MainGameModule = require(script.Parent.Parent.Game.MainGame)
-- // ANIMS
local StabAnimation = ReplicatedStorage:WaitForChild("Emotes"):WaitForChild("Stab")
-- // CONFIG
local STAB_RANGE = 7
local STAB_WIDTH = 4  -- Width of the stab hitbox
local STAB_HEIGHT = 6 -- Height of the stab hitbox
local DAMAGE = 34
local COOLDOWN = 0.6
local Cooldown = {}

local function playStabAnim(humanoid)
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(StabAnimation)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play()
end

local function getPlayerFromHit(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if not model then return nil, nil end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local plr = Players:GetPlayerFromCharacter(model)
	return plr, humanoid
end

-- Create multiple raycasts in a box pattern for better hit detection
local function performStabHitbox(origin, direction, character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	-- Create a grid of raycasts to form a hitbox
	local hitResults = {}

	-- Calculate the right and up vectors for the hitbox
	local lookVector = direction.Unit
	local rightVector = lookVector:Cross(Vector3.new(0, 1, 0)).Unit
	local upVector = rightVector:Cross(lookVector).Unit

	-- Define hitbox grid points (3x3 grid for good coverage)
	local gridPoints = {
		Vector3.new(0, 0, 0),        -- Center
		Vector3.new(-1, 0, 0),       -- Left
		Vector3.new(1, 0, 0),        -- Right
		Vector3.new(0, -1, 0),       -- Down
		Vector3.new(0, 1, 0),        -- Up
		Vector3.new(-1, -1, 0),      -- Bottom-left
		Vector3.new(1, -1, 0),       -- Bottom-right
		Vector3.new(-1, 1, 0),       -- Top-left
		Vector3.new(1, 1, 0),        -- Top-right
	}

	-- Perform raycast for each grid point
	for _, offset in ipairs(gridPoints) do
		local rayOrigin = origin +
			rightVector * (offset.X * STAB_WIDTH / 2) +
			upVector * (offset.Y * STAB_HEIGHT / 2)

		local result = workspace:Raycast(rayOrigin, direction, params)
		if result then
			table.insert(hitResults, result)
		end
	end

	return hitResults
end

-- Alternative method using Region3 for even better detection
local function performStabRegion(origin, direction, character)
	local hitbox = Instance.new("Part")
	hitbox.Name = "StabHitbox"
	hitbox.Size = Vector3.new(STAB_WIDTH, STAB_HEIGHT, STAB_RANGE)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = false
	hitbox.Anchored = true

	-- Position the hitbox in front of the player
	local centerPos = origin + direction.Unit * (STAB_RANGE / 2)
	hitbox.CFrame = CFrame.lookAt(centerPos, centerPos + direction.Unit)
	hitbox.Parent = workspace

	-- Find all parts touching the hitbox
	local touchingParts = workspace:GetPartBoundsInBox(hitbox.CFrame, hitbox.Size)

	-- Clean up hitbox
	hitbox:Destroy()

	return touchingParts
end

function KnifeModule.Stab(player: Player)
	if not player or player.ClassName ~= "Player" then return end

	local now = os.clock()
	if Cooldown[player.UserId] and now - Cooldown[player.UserId] < COOLDOWN then
		return
	end
	Cooldown[player.UserId] = now

	if not MainGameModule.GameActive then return end
	if not MainGameModule.PlayersInGame[player.UserId] then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	if not character:FindFirstChildWhichIsA("Tool") then return end

	playStabAnim(hum)

	local origin = hrp.Position
	local direction = hrp.CFrame.LookVector * STAB_RANGE

	local touchingParts = performStabRegion(origin, direction, character)

	local damagedPlayers = {}

	for _, part in ipairs(touchingParts) do
		local victimPlayer, victimHum = getPlayerFromHit(part)
		local victimId = victimPlayer and victimPlayer.UserId or nil

		if not victimHum or victimHum == hum or (victimId and damagedPlayers[victimId]) then
			continue
		end

		if victimPlayer and not MainGameModule.PlayersInGame[victimId] then
			continue
		end

		if victimHum.Health <= 0 then
			continue
		end

		if victimId then
			damagedPlayers[victimId] = true
		end

		-- FIX: Register pending kill BEFORE dealing damage
		if victimPlayer and victimId then
			MainGameModule.RegisterPendingKill(player, victimId)
		end

		victimHum:TakeDamage(DAMAGE)

		-- FIX: Only handle rewards here - OnDeath handles elimination tracking and kill credits
		task.defer(function()
			task.wait()
			if victimHum.Health <= 0 and victimPlayer and victimId then
				-- Award kill rewards immediately
				local playerCount = 0
				for _ in pairs(MainGameModule.PlayersInGame) do
					playerCount += 1
				end
				playerCount += 1

				local GameRewardModule = require(script.Parent.Parent.Game.GameReward)
				GameRewardModule.XpReward(player, "kill", playerCount)
				GameRewardModule.CashReward(player, "kill", playerCount)
				GameRewardModule.XpReward(victimPlayer, "lose", playerCount)
				GameRewardModule.CashReward(victimPlayer, "lose", playerCount)
			end
		end)
	end
end

return KnifeModule
