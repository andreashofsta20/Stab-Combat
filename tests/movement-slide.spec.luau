-- Executes production slide code with numeric vectors and deterministic spatial
-- queries. Native Roblox collision response still requires a Studio playtest.
local Vector, vectorMeta = {}, {}
function Vector.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vectorMeta) end
Vector.zero = Vector.new()
vectorMeta.__index = function(value, key)
	if key == "Magnitude" then return math.sqrt(value.X^2 + value.Y^2 + value.Z^2) end
	if key == "Unit" then local length = value.Magnitude; return length > 0 and Vector.new(value.X / length, value.Y / length, value.Z / length) or Vector.zero end
	return Vector[key]
end
vectorMeta.__add = function(a, b) return Vector.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vectorMeta.__sub = function(a, b) return Vector.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vectorMeta.__unm = function(a) return Vector.new(-a.X, -a.Y, -a.Z) end
vectorMeta.__mul = function(a, b)
	if type(a) == "number" then return Vector.new(b.X * a, b.Y * a, b.Z * a) end
	return Vector.new(a.X * b, a.Y * b, a.Z * b)
end
function Vector:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
function Vector:Cross(b) return Vector.new(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X) end
function Vector:Lerp(b, alpha) return self + (b - self) * alpha end
local UP, FORWARD = Vector.new(0, 1, 0), Vector.new(0, 0, -1)
local function near(actual, expected, epsilon) assert(math.abs(actual - expected) <= (epsilon or 1e-6), tostring(actual) .. " ~= " .. tostring(expected)) end
local function same(a, b) near(a.X, b.X); near(a.Y, b.Y); near(a.Z, b.Z) end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); passed += 1; print("PASS " .. name)
	end
	local config = load("Config")
	local motion = load("Motion", {Vector3 = Vector})
	test("surface tangents climb and descend ramps with orthogonal unit axes", function()
		local direction = Vector.new(1, 0, 0)
		for _, degrees in ipairs({-45, -20, 0, 20, 45}) do
			local angle = math.rad(degrees); local normal = Vector.new(-math.sin(angle), math.cos(angle), 0)
			local tangent = motion.Tangent(direction, normal)
			near(tangent.Magnitude, 1); near(tangent:Dot(normal), 0)
			near(tangent.Y, math.sin(angle)); near(tangent.X, math.cos(angle))
			near(normal:Cross(tangent).Magnitude, 1)
		end
		assert(motion.Walkable(UP, 50)); assert(not motion.Walkable(Vector.new(1, 0, 0), 50))
	end)
	test("slide curve gently boosts and decelerates continuously to exit speed", function()
		near(motion.Speed(32, 60, 32, 0, 0.8, 0.1), 32)
		near(motion.Speed(32, 60, 32, 0.1, 0.8, 0.1), 60)
		near(motion.Speed(32, 60, 32, 0.8, 0.8, 0.1), 32)
		near(motion.Speed(32, 60, 16, 1, 0.8, 0.1), 16)
		local previous = 60
		for i = 1, 70 do local speed = motion.Speed(32, 60, 32, 0.1 + i * 0.01, 0.8, 0.1); assert(speed <= previous and speed >= 32); previous = speed end
		near(motion.Speed(32, 60, 32, 0.1 - 1e-7, 0.8, 0.1), 60, 1e-8)
	end)
	test("steering has a frame-independent angular limit even for a 180-degree reversal", function()
		local function turn(fps)
			local direction = FORWARD
			for _ = 1, fps do direction = motion.Steer(direction, -FORWARD, math.rad(85) / fps) end
			return direction
		end
		same(turn(30), turn(144)); near(math.deg(math.acos(turn(30):Dot(FORWARD))), 85)
		local direction = motion.Steer(FORWARD, Vector.zero, math.rad(85)); same(direction, FORWARD)
		near(direction.Magnitude, 1)
	end)
	test("step impulse is bounded by height and gravity and rejects unsafe rises", function()
		for _, height in ipairs({0.1, 0.4, 0.85}) do
			local speed = motion.StepSpeed(height, 196.2, 0.1, 0.85)
			near(speed^2 / (2 * 196.2), height + 0.1)
		end
		assert(not motion.StepSpeed(0.9, 196.2, 0.1, 0.85)); assert(not motion.StepSpeed(-1, 196.2, 0.1, 0.85))
		assert(not motion.StepSpeed(0.01, 196.2, 0.1, 0.85)); assert(not motion.StepSpeed(0.5, 0, 0.1, 0.85))
	end)
	local function fixture(r15)
		local f = {created = {}, raycasts = 0, blockcasts = 0, overlaps = 0, groundNormal = UP, platformVelocity = Vector.zero}
		local character = {}
		local head = {Size = Vector.new(2, 1, 1)}
		function character:FindFirstChild(name) if name == "Head" then return head elseif name == "Left Leg" and not r15 then return {Size = Vector.new(1, 2, 1)} end end
		local humanoid = {Health = 100, HipHeight = r15 and 2 or 0, RigType = r15 and "R15" or "R6", MaxSlopeAngle = 80, FloorMaterial = "Ground", MoveDirection = FORWARD, Jump = false}
		function humanoid:GetState() return {Name = f.state or "Running"} end
		local root = {Position = Vector.new(0, 3, 0), Size = Vector.new(2, 2, 1), AssemblyMass = 10, CollisionGroup = "Players", AssemblyLinearVelocity = FORWARD * 32,
			CFrame = {LookVector = FORWARD}, Parent = character, CanCollide = true, Anchored = false}
		function root:ApplyImpulse(impulse) table.insert(f.impulses, impulse) end
		local floor = {}
		function floor:IsA(name) return name == "BasePart" end
		function floor:GetVelocityAtPosition() return f.platformVelocity end
		local obstacle = {}
		function obstacle:FindFirstAncestorOfClass() if f.characterObstacle then return {FindFirstChildOfClass = function() return {} end} end end
		local environment = {Vector3 = Vector, Vector2 = {new = function(x, y) return {X = x, Y = y} end}, CFrame = {new = function(position) return {Position = position} end},
			Enum = {RaycastFilterType = {Exclude = "Exclude"}, Material = {Air = "Air"}, ActuatorRelativeTo = {World = "World"},
				VelocityConstraintMode = {Plane = "Plane"}, ForceLimitMode = {Magnitude = "Magnitude"}, HumanoidRigType = {R6 = "R6", R15 = "R15"}},
			RaycastParams = {new = function() return {} end}, OverlapParams = {new = function() return {} end},
			game = {GetService = function() return {Modules = {SlideMotion = "Motion"}, FindFirstChild = function() return nil end} end}, require = function(name) assert(name == "Motion"); return motion end}
		environment.Instance = {new = function(class)
			local object = {ClassName = class}; function object:Destroy() self.Destroyed = true; self.Parent = nil end
			table.insert(f.created, object); return object
		end}
		f.impulses = {}
		f.workspace = {Gravity = 196.2}
		function f.workspace:Raycast(origin, _, params)
			f.raycasts += 1; f.lastParams = params
			if origin == root.Position then
				if f.noGround then return nil end
				return {Position = Vector.zero, Normal = f.groundNormal, Instance = floor}
			end
			if not f.stepHeight then return nil end
			return {Position = Vector.new(0, f.stepHeight, -2), Normal = f.topNormal or UP, Instance = obstacle}
		end
		function f.workspace:Blockcast(frame, size, direction, params)
			f.blockcasts += 1; f.lastParams = params
			if size.Y < 1 and f.stepObstacle then return {Position = Vector.new(0, 0.3, -2), Normal = Vector.new(0, 0, 1), Distance = f.distance or 1, Instance = obstacle} end
			if size.Y >= 1 then
				if direction.Y > 0 then if f.terrainCeiling then return {Instance = obstacle} end
				else f.clearanceFrame = frame; if f.wallAbove then return {Instance = obstacle} end end
			end
		end
		function f.workspace:GetPartBoundsInBox(frame, _, params)
			f.overlaps += 1; f.lastOverlaps = params; f.clearanceFrame = frame
			return f.ceilingOverlap and {obstacle} or {}
		end
		environment.workspace = f.workspace
		f.controller = load("Controller", environment).new(character, humanoid, root, config)
		f.root, f.character, f.humanoid = root, character, humanoid
		return f
	end
	test("finite planar force preserves collision and uses grounded slope direction", function()
		local f = fixture(); f.groundNormal = Vector.new(0, math.cos(math.rad(30)), math.sin(math.rad(30)))
		assert(f.controller:Start()); assert(f.controller:Step(1 / 60, 32))
		local velocity = f.controller.Velocity
		assert(velocity.Enabled and velocity.ForceLimitsEnabled); near(velocity.MaxForce, 10 * config.SlideAcceleration)
		assert(velocity.PrimaryTangentAxis.Y > 0); near(velocity.PrimaryTangentAxis:Dot(velocity.SecondaryTangentAxis), 0)
		assert(f.root.CanCollide); near(f.root.Position.Y, 3); same(f.root.AssemblyLinearVelocity, FORWARD * 32)
		assert(f.lastParams.RespectCanCollide and f.lastParams.IgnoreWater); assert(f.lastParams.FilterDescendantsInstances[1] == f.character)
		assert(f.lastParams.CollisionGroup == "Players")
	end)
	test("R6 and R15 probe distances follow their different HipHeight conventions", function()
		near(fixture().controller.FloorDistance, 3); near(fixture(true).controller.FloorDistance, 3)
	end)
	test("moving floor velocity is added along the plane without vertical anchoring", function()
		local f = fixture(); f.platformVelocity = Vector.new(4, 2, -3); assert(f.controller:Start())
		near(f.controller.Velocity.PlaneVelocity.X, 35); near(f.controller.Velocity.PlaneVelocity.Y, -4)
		near(f.controller.Velocity.PrimaryTangentAxis.Y, 0); near(f.controller.Velocity.SecondaryTangentAxis.Y, 0)
	end)
	test("air, missing floor, steep slopes, jumping and dead states cannot start a slide", function()
		for _, prepare in ipairs({
			function(f) f.humanoid.FloorMaterial = "Air" end,
			function(f) f.noGround = true end,
			function(f) f.groundNormal = Vector.new(0, 0.4, 0.9165) end,
			function(f) f.humanoid.MaxSlopeAngle = 20; f.groundNormal = Vector.new(0, 0.8, 0.6) end,
			function(f) f.state = "Jumping" end,
			function(f) f.humanoid.Health = 0 end,
		}) do local f = fixture(); prepare(f); assert(not f.controller:Start()); assert(not f.controller.Velocity.Enabled) end
	end)
	test("short floor gaps blend through while sustained air releases the force", function()
		local f = fixture(); assert(f.controller:Start()); f.humanoid.FloorMaterial = "Air"; f.noGround = true
		assert(f.controller:Step(0.1, 32)); near(f.controller.Velocity.PrimaryTangentAxis.Y, 0)
		f.humanoid.FloorMaterial = "Ground"; f.noGround = false; assert(f.controller:Step(0.04, 32)); near(f.controller.AirElapsed, 0)
		f.humanoid.FloorMaterial = "Air"; f.noGround = true; assert(not f.controller:Step(0.13, 32)); assert(not f.controller.Velocity.Enabled)
	end)
	test("jump intent, climbing, death, anchoring and root replacement cancel before physics", function()
		for _, prepare in ipairs({function(f) f.humanoid.Jump = true end, function(f) f.state = "Jumping" end,
			function(f) f.state = "Climbing" end, function(f) f.humanoid.Health = 0 end,
			function(f) f.root.Anchored = true end, function(f) f.root.Parent = {} end}) do
			local f = fixture(); assert(f.controller:Start()); prepare(f); assert(not f.controller:Step(1 / 60, 32)); assert(not f.controller.Velocity.Enabled)
		end
	end)
	test("clear small obstacles use bounded upward impulse and allow a short physical lift", function()
		local f = fixture(); f.stepObstacle, f.stepHeight = true, 0.5; assert(f.controller:Start()); assert(f.controller:Step(1 / 60, 32))
		assert(#f.impulses == 1); local impulse = f.impulses[1]; near(impulse.X, 0); near(impulse.Z, 0)
		near(impulse.Y / f.root.AssemblyMass, math.sqrt(2 * 196.2 * 0.6))
		assert(f.lastOverlaps.RespectCanCollide); assert(f.lastOverlaps.CollisionGroup == "Players")
		near(f.clearanceFrame.Position.Y - f.controller.BodySize.Y / 2, 0.6)
		f.humanoid.FloorMaterial = "Air"; f.noGround = true; assert(f.controller:Step(0.14, 32))
		near(f.controller.Velocity.PrimaryTangentAxis.Y, 0); assert(not f.controller:Step(0.1, 32)); assert(#f.impulses == 1)
	end)
	test("tall or steep obstacles, players, ceilings and upper walls never receive step lift", function()
		for _, prepare in ipairs({function(f) f.stepHeight = 0.9 end,
			function(f) f.topNormal = Vector.new(0, 0.3, 0.95) end,
			function(f) f.characterObstacle = true end, function(f) f.ceilingOverlap = true end,
			function(f) f.wallAbove = true end, function(f) f.terrainCeiling = true end, function(f) f.stepHeight = nil end}) do
			local f = fixture(); f.stepObstacle, f.stepHeight = true, 0.5; prepare(f)
			assert(f.controller:Start()); f.controller:Step(1 / 60, 32); assert(#f.impulses == 0)
		end
	end)
	test("tiny distant obstacles wait until their smaller impulse can reach the top", function()
		local f = fixture(); f.stepObstacle, f.stepHeight, f.distance = true, 0.1, 5; assert(f.controller:Start())
		f.controller:Step(1 / 30, 32); assert(#f.impulses == 0)
		f.distance = 0.5; f.controller:Step(1 / 30, 32); assert(#f.impulses == 1)
	end)
	test("slide retains its reusable constraint and probes at a bounded rate", function()
		local f = fixture(); assert(f.controller:Start())
		for _ = 1, 96 do assert(f.controller:Step(1 / 240, 32)) end
		assert(f.raycasts <= 15 and f.blockcasts <= 14); assert(#f.created == 2)
		f.controller:Stop(); local queries = f.raycasts; assert(not f.controller:Step(1 / 60, 32)); assert(f.raycasts == queries)
		for _ = 1, 20 do assert(f.controller:Start()); f.controller:Stop() end
		assert(#f.created == 2); f.controller:Destroy(); assert(f.created[1].Destroyed and f.created[2].Destroyed)
	end)
	test("frame-rate changes cannot overshoot duration or the speed bounds", function()
		local function advance(fps)
			local f = fixture(); assert(f.controller:Start()); for _ = 1, fps / 2 do assert(f.controller:Step(1 / fps, 32)) end
			return f.controller
		end
		near(advance(30).Speed, advance(144).Speed)
		local f = fixture(); assert(f.controller:Start()); assert(not f.controller:Step(1, 32)); assert(not f.controller.Velocity.Enabled)
	end)
	print(tostring(passed) .. " movement slide tests passed")
end
