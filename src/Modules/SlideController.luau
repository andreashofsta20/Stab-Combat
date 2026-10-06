local RS = game:GetService("ReplicatedStorage")
local Motion = require(RS.Modules.SlideMotion)
local UP = Vector3.new(0, 1, 0)
local Slide = {}
Slide.__index = Slide
local blockedStates = {
	Dead = true, Jumping = true, Climbing = true, Seated = true,
	Swimming = true, Physics = true, Ragdoll = true,
	PlatformStanding = true, FallingDown = true,
}

function Slide.new(character, humanoid, root, config)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local overlaps = OverlapParams.new()
	overlaps.FilterType = Enum.RaycastFilterType.Exclude
	overlaps.FilterDescendantsInstances = {character}
	overlaps.RespectCanCollide = true
	overlaps.MaxParts = 1
	local attachment = Instance.new("Attachment")
	attachment.Name = "SlideMotionAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "SlideMotionVelocity"
	velocity.Enabled = false
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.ForceLimitsEnabled = true
	velocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	velocity.PrimaryTangentAxis = Vector3.new(0, 0, -1)
	velocity.SecondaryTangentAxis = Vector3.new(-1, 0, 0)
	velocity.Parent = root
	-- R6 HipHeight excludes leg length; R15 HipHeight already includes it.
	local leg = character:FindFirstChild("Left Leg")
	local floorDistance = root.Size.Y * 0.5 + humanoid.HipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 and leg then floorDistance += leg.Size.Y end
	local head = character:FindFirstChild("Head")
	local bodyHeight = floorDistance + root.Size.Y * 0.5 + (head and head.Size.Y or 2)
	return setmetatable({
		Character = character, Humanoid = humanoid, Root = root, Config = config,
		Attachment = attachment, Velocity = velocity, Params = params, Overlaps = overlaps,
		FloorDistance = floorDistance, BodySize = Vector3.new(root.Size.X * 0.95, bodyHeight, root.Size.Z * 0.95),
		Active = false, Speed = 0, Elapsed = 0, GroundNormal = UP, SurfaceNormal = UP,
	}, Slide)
end

function Slide:_ground()
	local root, config = self.Root, self.Config
	self.Params.CollisionGroup = root.CollisionGroup
	self.Overlaps.CollisionGroup = root.CollisionGroup
	local hit = workspace:Raycast(root.Position, -UP * (self.FloorDistance + config.SlideGroundTolerance), self.Params)
	local slope = math.min(config.SlideMaxSlopeDegrees, self.Humanoid.MaxSlopeAngle)
	if hit and Motion.Walkable(hit.Normal, slope) then return hit end
	return nil
end

function Slide:Start()
	if self.Active or self.Humanoid.Health <= 0 or blockedStates[self.Humanoid:GetState().Name]
		or self.Humanoid.FloorMaterial == Enum.Material.Air or self.Root.Anchored then return false end
	local ground = self:_ground()
	if not ground then return false end
	local root, config = self.Root, self.Config
	self.Direction = Motion.Horizontal(self.Humanoid.MoveDirection, Motion.Horizontal(root.CFrame.LookVector, Vector3.new(0, 0, -1)))
	local velocity = root.AssemblyLinearVelocity
	self.InitialSpeed = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude, config.WalkSpeed, config.SlideSpeed)
	self.Active, self.Elapsed, self.AirElapsed, self.ProbeElapsed = true, 0, 0, config.SlideProbeInterval
	self.LastStep, self.StepGraceUntil = -math.huge, 0
	self.Ground, self.GroundNormal, self.SurfaceNormal = ground, ground.Normal, ground.Normal
	self.Speed = self.InitialSpeed
	self.Velocity.Enabled = true
	self:_velocity(self.Speed, ground.Normal)
	return true
end

function Slide:_velocity(speed, normal)
	local forward = Motion.Tangent(self.Direction, normal)
	local sideways = normal:Cross(forward).Unit
	local platformVelocity = Vector3.zero
	local ground = self.Ground
	if ground and ground.Instance:IsA("BasePart") then platformVelocity = ground.Instance:GetVelocityAtPosition(self.Root.Position) end
	local velocity = self.Velocity
	velocity.PrimaryTangentAxis = forward
	velocity.SecondaryTangentAxis = sideways
	velocity.PlaneVelocity = Vector2.new(speed + platformVelocity:Dot(forward), platformVelocity:Dot(sideways))
	velocity.MaxForce = self.Root.AssemblyMass * self.Config.SlideAcceleration
end

function Slide:_step(ground, probeDt)
	local config, root = self.Config, self.Root
	if not ground or self.Elapsed - self.LastStep < config.SlideStepCooldown
		or self.Humanoid.FloorMaterial == Enum.Material.Air then return end
	local foot = Vector3.new(root.Position.X, ground.Position.Y, root.Position.Z)
	local probeHeight = config.SlideStepHeight
	local lowSize = Vector3.new(self.BodySize.X, probeHeight - 0.08, self.BodySize.Z)
	local lowCenter = foot + UP * (0.08 + lowSize.Y * 0.5)
	local direction = self.Direction * config.SlideStepProbeDistance
	local lowHit = workspace:Blockcast(CFrame.new(lowCenter), lowSize, direction, self.Params)
	local slope = math.min(config.SlideMaxSlopeDegrees, self.Humanoid.MaxSlopeAngle)
	if not lowHit or Motion.Walkable(lowHit.Normal, slope) then return end
	local model = lowHit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return end
	local topOrigin = lowHit.Position + self.Direction * 0.35
	topOrigin = Vector3.new(topOrigin.X, foot.Y + probeHeight + config.SlideStepMargin, topOrigin.Z)
	local top = workspace:Raycast(topOrigin, -UP * (probeHeight + config.SlideStepMargin), self.Params)
	if not top or not Motion.Walkable(top.Normal, slope) then return end
	local height = top.Position.Y - foot.Y
	local stepSpeed = Motion.StepSpeed(height, workspace.Gravity, config.SlideStepMargin, probeHeight)
	if not stepSpeed then return end
	-- Start close enough to arrive while rising. Tiny obstacles need a later,
	-- smaller lift than the maximum-height step, so they do not cause hopping.
	local reach = self.Speed * (stepSpeed / workspace.Gravity * 0.7 + math.min(probeDt, 1 / 15))
	if lowHit.Distance > math.max(reach, 0.3) then return end
	local clearanceCenter = foot + UP * (height + config.SlideStepMargin + self.BodySize.Y * 0.5)
	local clearanceFrame = CFrame.new(clearanceCenter)
	-- Blockcasts omit initial overlaps; the box query covers that starting case.
	if #workspace:GetPartBoundsInBox(clearanceFrame, self.BodySize, self.Overlaps) > 0 then return end
	-- The upward sweep also catches terrain ceilings, which box-overlap queries
	-- do not return, and checks the path to the elevated clearance position.
	local bodyFrame = CFrame.new(foot + UP * (0.08 + self.BodySize.Y * 0.5))
	if workspace:Blockcast(bodyFrame, self.BodySize, UP * (height + config.SlideStepMargin), self.Params) then return end
	if workspace:Blockcast(clearanceFrame, self.BodySize, self.Direction * (lowHit.Distance + 0.5), self.Params) then return end
	local lift = math.max(stepSpeed - root.AssemblyLinearVelocity.Y, 0)
	if lift <= 0 then return end
	root:ApplyImpulse(UP * root.AssemblyMass * math.min(lift, stepSpeed))
	self.LastStep = self.Elapsed
	self.StepGraceUntil = self.Elapsed + config.SlideStepGrace
	return true
end

function Slide:Step(dt, exitSpeed)
	if not self.Active then return false end
	if self.Root.Parent ~= self.Character or self.Root.Anchored or self.Humanoid.Health <= 0
		or blockedStates[self.Humanoid:GetState().Name] or self.Humanoid.Jump then
		self:Stop(); return false
	end
	dt = math.max(dt, 0)
	self.Elapsed += dt
	local config = self.Config
	if self.Elapsed >= config.SlideDuration then self:Stop(); return false end
	self.Direction = Motion.Steer(self.Direction, self.Humanoid.MoveDirection, math.rad(config.SlideSteerDegreesPerSecond) * dt)
	self.ProbeElapsed += dt
	local lifted = false
	if self.ProbeElapsed >= config.SlideProbeInterval then
		local probeDt = self.ProbeElapsed
		self.ProbeElapsed %= config.SlideProbeInterval
		self.Ground = self:_ground()
		if self.Ground then self.GroundNormal = self.Ground.Normal end
		lifted = self:_step(self.Ground, probeDt) == true
	end
	local grounded = not lifted and self.Ground ~= nil and self.Humanoid.FloorMaterial ~= Enum.Material.Air
	self.AirElapsed = grounded and 0 or self.AirElapsed + dt
	if self.AirElapsed > config.SlideGroundGrace and self.Elapsed > self.StepGraceUntil then self:Stop(); return false end
	self.Speed = Motion.Speed(self.InitialSpeed, config.SlideSpeed, exitSpeed or config.SlideEndSpeed,
		self.Elapsed, config.SlideDuration, config.SlideBoostSeconds)
	-- Release vertical motion immediately on leaving the floor, including a
	-- physical step lift. Jumps and gravity keep their normal behavior.
	if grounded then
		self.SurfaceNormal = Motion.SmoothNormal(self.SurfaceNormal, self.GroundNormal, config.SlideSurfaceResponse, dt)
	else self.SurfaceNormal = UP end
	self:_velocity(self.Speed, self.SurfaceNormal)
	return true
end

function Slide:Stop()
	self.Active = false
	self.Velocity.Enabled = false
	self.Ground = nil
end

function Slide:Destroy()
	self:Stop()
	self.Velocity:Destroy()
	self.Attachment:Destroy()
end

return Slide
