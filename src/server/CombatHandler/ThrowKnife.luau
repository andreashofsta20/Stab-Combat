local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local MainGame = require(script.Parent.Parent.Game.MainGame)
local PlayerHitbox = require(script.Parent.PlayerHitbox)
local Projectile = require(ReplicatedStorage.Modules.ProjectileMath)

local KnifeRemotes = ReplicatedStorage.Remotes.Knife
local ResultRemote = KnifeRemotes.ThrewClient
local DamageRemote = KnifeRemotes.DamageDealtClient
local Knives = ReplicatedStorage:WaitForChild("Knives")

local VISUAL_OFFSET = 0.8

local activeShots: {[number]: {[string]: boolean}} = {}
local lastShot: {[number]: number} = {}

local function reject(player: Player, shotId: string)
	ResultRemote:FireClient(player, {shotId = shotId, accepted = false})
end

local function finiteId(id: any): boolean
	return typeof(id) == "string" and #id >= 1 and #id <= 64 and id:match("^[%w_%-]+$") ~= nil
end

local function addTrail(part: BasePart)
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
	mainTrail.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(0, 162, 255)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 64, 64)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
	}
	mainTrail.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	}
	mainTrail.WidthScale = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	}
	mainTrail.Parent = part

	local secondaryTrail = Instance.new("Trail")
	secondaryTrail.Attachment0 = frontAttachment
	secondaryTrail.Attachment1 = backAttachment
	secondaryTrail.Lifetime = 0.15
	secondaryTrail.MinLength = 0
	secondaryTrail.FaceCamera = true
	secondaryTrail.LightEmission = 0.8
	secondaryTrail.LightInfluence = 0.2
	secondaryTrail.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 128, 0)),
	}
	secondaryTrail.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	}
	secondaryTrail.WidthScale = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.05),
	}
	secondaryTrail.Parent = part

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
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0)),
	}
	sparks.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	}
	sparks.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.05),
		NumberSequenceKeypoint.new(1, 0.01),
	}
	sparks.LightEmission = 1
	sparks.LightInfluence = 0

	task.delay(0.5, function()
		sparks.Enabled = false
		Debris:AddItem(sparks, 2)
	end)
end

local function stickKnife(knife: BasePart, hitPart: BasePart?, position: Vector3, normal: Vector3)
	knife.Anchored = true
	knife.CFrame = CFrame.new(position, position + normal) * CFrame.Angles(math.rad(90), 0, 0)
	local model = hitPart and hitPart:FindFirstAncestorOfClass("Model")
	if hitPart and hitPart:IsA("BasePart") and not (model and model:FindFirstChildOfClass("Humanoid")) then
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = knife, hitPart, knife
	end
end

local function spawnVisual(player: Player, origin: Vector3, direction: Vector3, charge: number, shotId: string, hit)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("EquippedKnife")
	local template = value and Knives:FindFirstChild(value.Value)
	local source = template and template:FindFirstChild("Handle")
	if not source or not source:IsA("BasePart") then return end
	local knife = source:Clone()
	knife.CanCollide, knife.CanQuery, knife.Massless = false, false, true
	knife:SetAttribute("ShotId", shotId)
	knife:SetAttribute("ShooterUserId", player.UserId)
	knife.Parent = workspace
	knife:SetNetworkOwner(nil)
	CollectionService:AddTag(knife, "ServerKnife_" .. player.UserId)
	CollectionService:AddTag(knife, "ServerKnifeVisual")
	addTrail(knife)

	local visualOrigin = origin + direction * VISUAL_OFFSET
	local destination = Projectile.GetPosition(origin, direction, Projectile.MAX_FLIGHT_TIME, charge)
	local hitResult = nil
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		local distance = (destination - visualOrigin).Magnitude
		local alpha = distance > 0 and math.clamp(Projectile.GetSpeed(charge) * elapsed / distance, 0, 1) or 1
		local position = visualOrigin:Lerp(destination, alpha)
		knife.CFrame = CFrame.lookAt(position, position + direction)
		if alpha >= 1 then
			connection:Disconnect()
			if hitResult then
				stickKnife(knife, hitResult.part, hitResult.position, hitResult.normal)
			else
				Debris:AddItem(knife, 2)
			end
		end
	end)
	Debris:AddItem(knife, Projectile.MAX_FLIGHT_TIME + 3)

	return function(finalHit)
		hitResult = finalHit
		if finalHit then
			destination = finalHit.position
		end
	end
end

function Projectile.Throw(player: Player, shotId: string, origin: Vector3, direction: Vector3, charge: number)
	if not finiteId(shotId) or not Projectile.IsFiniteVector(origin) or not Projectile.IsFiniteVector(direction)
		or not Projectile.IsFiniteNumber(charge) then
		if finiteId(shotId) then reject(player, shotId) end
		return
	end
	if activeShots[player.UserId] and activeShots[player.UserId][shotId] then
		reject(player, shotId)
		return
	end
	activeShots[player.UserId] = activeShots[player.UserId] or {}
	activeShots[player.UserId][shotId] = true
	local now = os.clock()
	if lastShot[player.UserId] and now - lastShot[player.UserId] < Projectile.COOLDOWN then
		reject(player, shotId)
		return
	end
	lastShot[player.UserId] = now
	charge = Projectile.ClampCharge(charge)
	direction = Projectile.NormalizeDirection(direction)
	if not direction then reject(player, shotId) return end
	if not MainGame.GameActive or not MainGame.PlayersInGame[player.UserId] then
		reject(player, shotId)
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local physicalOrigin = (head and head.Position) or (root and root.Position)
	if not humanoid or not physicalOrigin or not tool or humanoid.Health <= 0 then
		reject(player, shotId)
		return
	end
	if (origin - physicalOrigin).Magnitude > Projectile.MAX_ORIGIN_DISTANCE then
		reject(player, shotId)
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local finishVisual = spawnVisual(player, origin, direction, charge, shotId, nil)
	local leaderstats = player:FindFirstChild("leaderstats")
	local equippedKnife = leaderstats and leaderstats:FindFirstChild("EquippedKnife")
	local position, elapsed = origin, 0
	local hit
	while elapsed < Projectile.MAX_FLIGHT_TIME do
		local step = math.min(Projectile.FIXED_STEP, Projectile.MAX_FLIGHT_TIME - elapsed)
		local nextPosition = Projectile.GetPosition(origin, direction, elapsed + step, charge)
		local result = workspace:Raycast(position, nextPosition - position, params)
		if result then
			local victim, victimHumanoid = PlayerHitbox.GetPlayerFromHitbox(result.Instance)
			if victimHumanoid and victimHumanoid ~= humanoid and victimHumanoid.Health > 0
				and (not victim or MainGame.PlayersInGame[victim.UserId]) then
				if victim and victimHumanoid.Health <= Projectile.DAMAGE then MainGame.RegisterPendingKill(player, victim.UserId) end
				victimHumanoid:TakeDamage(Projectile.DAMAGE)
				DamageRemote:FireClient(player, victimHumanoid.Parent, Projectile.DAMAGE)
			end
			hit = {part = result.Instance, position = result.Position, normal = result.Normal}
			break
		end
		position, elapsed = nextPosition, elapsed + step
		if (position - origin).Magnitude >= Projectile.MAX_DISTANCE then break end
	end

	local result = {shotId = shotId, accepted = true, hit = hit and true or false,
		position = hit and hit.position or position, normal = hit and hit.normal or nil}
	ResultRemote:FireClient(player, result)
	ResultRemote:FireAllClients({
		visualOnly = true,
		shotId = shotId,
		shooterUserId = player.UserId,
		knifeName = equippedKnife and equippedKnife.Value,
		origin = origin,
		direction = direction,
		charge = charge,
		destination = result.position,
		normal = result.normal,
	})
	if finishVisual then
		finishVisual(hit)
	end
end

Players.PlayerRemoving:Connect(function(player)
	activeShots[player.UserId], lastShot[player.UserId] = nil, nil
end)

return Projectile
