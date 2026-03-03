local KnifeModule = {}

-- // SERVICES
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

-- // MODULES
local MainGameModule = require(script.Parent.Parent.Game.MainGame)
local NotificationHandler = require(script.Parent.Parent.Game.SendNotification)
local ThrewKnifeClient = ReplicatedStorage.Remotes.Knife:WaitForChild("ThrewClient")

-- // ANIMATIONS
local KnivesFolder = ServerStorage:WaitForChild("Knives")
local CombatAnimations = ReplicatedStorage:WaitForChild("CombatAnimations")
local ThrowAnimation = CombatAnimations:WaitForChild("Throw")

-- // CONFIG
local KNIFE_SPEED = 10000  -- Studs per second for visual movement
local MAX_DISTANCE = 350
local LIFETIME = 5
local DAMAGE = 100
local COOLDOWN = 0.5
local VISUAL_OFFSET = 0.8
local MIN_SPEED_MULT = 0.7
local MAX_SPEED_MULT = 1.7

local Cooldown = {}

local function playThrowAnim(humanoid)
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(ThrowAnimation)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	--track:Play()
	Debris:AddItem(track, 2)
end

local function addTrail(part)
	local frontAttachment = Instance.new("Attachment", part)
	local backAttachment = Instance.new("Attachment", part)

	frontAttachment.Position = Vector3.new(0, 0, 0.5)
	backAttachment.Position = Vector3.new(0, 0, -0.5)

	local mainTrail = Instance.new("Trail")
	mainTrail.Attachment0 = frontAttachment
	mainTrail.Attachment1 = backAttachment
	mainTrail.Lifetime = 0.3
	mainTrail.MinLength = 0
	mainTrail.FaceCamera = true
	mainTrail.LightEmission = 1
	mainTrail.LightInfluence = 0

	local colorSequence = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(0, 162, 255)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 64, 64)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
	}
	mainTrail.Color = colorSequence

	local transparencySequence = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	}
	mainTrail.Transparency = transparencySequence

	local widthSequence = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0.1)
	}
	mainTrail.WidthScale = widthSequence

	mainTrail.Parent = part

	-- Secondary trail
	local secondaryTrail = Instance.new("Trail")
	secondaryTrail.Attachment0 = frontAttachment
	secondaryTrail.Attachment1 = backAttachment
	secondaryTrail.Lifetime = 0.15
	secondaryTrail.MinLength = 0
	secondaryTrail.FaceCamera = true
	secondaryTrail.LightEmission = 0.8
	secondaryTrail.LightInfluence = 0.2

	local innerColorSequence = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 128, 0))
	}
	secondaryTrail.Color = innerColorSequence

	local innerTransparencySequence = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.7),
		NumberSequenceKeypoint.new(1, 1)
	}
	secondaryTrail.Transparency = innerTransparencySequence

	local innerWidthSequence = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.05)
	}
	secondaryTrail.WidthScale = innerWidthSequence

	secondaryTrail.Parent = part

	-- Particle effects
	local particles = Instance.new("Attachment", part)
	particles.Position = Vector3.new(0, 0, -0.3)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Parent = particles
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Lifetime = NumberRange.new(0.1, 0.3)
	sparks.Rate = 100
	sparks.SpreadAngle = Vector2.new(45, 45)
	sparks.Speed = NumberRange.new(2, 8)
	sparks.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
	}
	sparks.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	}
	sparks.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.05),
		NumberSequenceKeypoint.new(1, 0.01)
	}
	sparks.LightEmission = 1
	sparks.LightInfluence = 0

	task.spawn(function()
		task.wait(0.5)
		sparks.Enabled = false
		Debris:AddItem(sparks, 2)
	end)

	return frontAttachment, backAttachment
end

local function stickKnife(knife, hitPart, pos, normal)
	knife.Anchored = true
	knife.CFrame = CFrame.new(pos, pos + normal) * CFrame.Angles(math.rad(90), 0, 0)

	if hitPart and hitPart:IsA("BasePart") then
		local model = hitPart:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return
		else
			knife.Anchored = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = knife
			weld.Part1 = hitPart
			weld.Parent = knife
		end
	end
end

local function getPlayerFromHit(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if not model then return nil, nil end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local plr = Players:GetPlayerFromCharacter(model)
	return plr, humanoid
end

function KnifeModule.ThrowKnife(player: Player, camOrigin: Vector3, targetPosition: Vector3, chargeRatio: number)
	if not player or player.ClassName ~= "Player" then return end
	if typeof(camOrigin) ~= "Vector3" or typeof(targetPosition) ~= "Vector3" then return end
	if typeof(chargeRatio) ~= "number" then
		chargeRatio = 0
	end

	if not MainGameModule.GameActive then return end
	if not MainGameModule.PlayersInGame[player.UserId] then return end

	-- Check cooldown
	if Cooldown[player.UserId] and os.clock() - Cooldown[player.UserId] < COOLDOWN then
		return
	end
	Cooldown[player.UserId] = os.clock()

	-- Get character info first
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")

	local equippedTool = character:FindFirstChildWhichIsA("Tool")
	if not equippedTool then return end

	ThrewKnifeClient:FireClient(player)

	local direction = (targetPosition - camOrigin).Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local hitResult = workspace:Raycast(camOrigin, direction * MAX_DISTANCE, rayParams)
	local finalHitPos = hitResult and hitResult.Position or (camOrigin + direction * MAX_DISTANCE)
	local actualDistance = (finalHitPos - camOrigin).Magnitude
	local speedMult = MIN_SPEED_MULT + ((MAX_SPEED_MULT - MIN_SPEED_MULT) * math.clamp(chargeRatio, 0, 1))

	local hitVictim = nil
	local hitHumanoid = nil

	if hitResult then
		hitVictim, hitHumanoid = getPlayerFromHit(hitResult.Instance)
		local victimId = hitVictim and hitVictim.UserId or nil

		if hitHumanoid and hitHumanoid ~= humanoid and hitHumanoid.Health > 0 then
			local canDamage = true
			if hitVictim then
				canDamage = MainGameModule.PlayersInGame[victimId] == true
			end

			if canDamage then
				-- FIX: Register pending kill BEFORE dealing damage
				if hitVictim and victimId then
					MainGameModule.RegisterPendingKill(player, victimId)
				end

				hitHumanoid:TakeDamage(DAMAGE)
			end
		end
	end

	-- Now create visual knife for the animation

	-- Play throw animation
	playThrowAnim(humanoid)

	-- Hide the tool after a brief delay (during the throw animation)
	local toolHandle = equippedTool:FindFirstChild("Handle")
	if toolHandle then
		task.delay(0.15, function()
			if toolHandle then
				toolHandle.Transparency = 1
			end
		end)
		task.delay(0.65, function()
			if toolHandle then
				toolHandle.Transparency = 0
			end
		end)
	end

	-- Get hand position for visual starting point
	local hand = character and character:FindFirstChild("RightHand")
	local baseOrigin = hand and hand.Position or (hrp and hrp.Position) or camOrigin
	local visualOrigin = baseOrigin + (direction * VISUAL_OFFSET)

	-- Create knife visual
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local equippedKnifeValue = leaderstats:FindFirstChild("EquippedKnife")
	if not equippedKnifeValue then return end
	local EquippedKnife = equippedKnifeValue.Value
	local Template = KnivesFolder:FindFirstChild(EquippedKnife)
	if not Template or not Template:FindFirstChild("Handle") then return end

	local handle = Template.Handle:Clone()
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = CFrame.lookAt(visualOrigin, visualOrigin + direction)
	handle.Parent = workspace
	handle:SetNetworkOwner(nil)

	local att0, att1 = addTrail(handle)

	-- Calculate travel time for visual
	local travelTime = actualDistance / (KNIFE_SPEED * speedMult)
	local startTime = os.clock()

	-- Visual movement animation
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		local progress = elapsed / travelTime

		if progress >= 1 then
			-- Animation complete - stick the knife
			handle.CFrame = CFrame.lookAt(finalHitPos, finalHitPos + direction)
			if hitResult then
				stickKnife(handle, hitResult.Instance, finalHitPos, hitResult.Normal)
			else
				Debris:AddItem(handle, 3)
			end
			conn:Disconnect()
			return
		end

		-- Interpolate position
		local currentPos = visualOrigin:Lerp(finalHitPos, progress)
		handle.CFrame = CFrame.lookAt(currentPos, currentPos + direction)
	end)

	-- Cleanup after lifetime
	Debris:AddItem(handle, LIFETIME)
end

return KnifeModule
