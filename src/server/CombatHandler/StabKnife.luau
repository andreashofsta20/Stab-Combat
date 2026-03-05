local KnifeModule = {}
-- // SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- // MODULES
local MainGameModule = require(script.Parent.Parent.Game.MainGame)
local PlayerHitbox = require(script.Parent.PlayerHitbox)
-- // ANIMS
local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations") 
local StabAnimation = CombatAnimations:WaitForChild("Stab")
-- // CONFIG
local STAB_RANGE = 12 -- How far in front of the player the stab reaches
local STAB_WIDTH = 8  -- Width of the stab hitbox
local STAB_HEIGHT = 8 -- Height of the stab hitbox
local DAMAGE = 100
local COOLDOWN = 0.6
local Cooldown = {}

local function playStabAnim(humanoid)
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(StabAnimation)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	--track:Play()
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

	-- Use GetPartBoundsInBox centered in front of the player
	local origin = hrp.Position + hrp.CFrame.LookVector * (STAB_RANGE / 2)
	local hitboxCFrame = CFrame.lookAt(origin, origin + hrp.CFrame.LookVector)
	local hitboxSize = Vector3.new(STAB_WIDTH, STAB_HEIGHT, STAB_RANGE)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local touchingParts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)

	local damagedPlayers = {}

	for _, part in ipairs(touchingParts) do
		-- Use PlayerHitbox to resolve player from any part (hitbox or body)
		local victimPlayer, victimHum = PlayerHitbox.GetPlayerFromHitbox(part)
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

		-- Register pending kill BEFORE dealing damage
		if victimPlayer and victimId then
			MainGameModule.RegisterPendingKill(player, victimId)
		end

		victimHum:TakeDamage(DAMAGE)
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	Cooldown[player.UserId] = nil
end)

return KnifeModule
