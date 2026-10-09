-- Runs actual production sources with lightweight Roblox stand-ins.
-- This verifies math and lifecycle, not the GPU appearance or live replication.
return function(load)
	local passed = 0
	local function near(a, b) assert(math.abs(a - b) < 1e-5, tostring(a) .. " ~= " .. tostring(b)) end
	local function test(name, fn)
		local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err))
		passed += 1; print("PASS " .. name)
	end
	local Vector = {}
	local vm = {}
	function Vector.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z, kind = "Vector3" }, vm) end
	function Vector:Cross(other) return Vector.new(self.Y * other.Z - self.Z * other.Y, self.Z * other.X - self.X * other.Z, self.X * other.Y - self.Y * other.X) end
	function Vector:Dot(other) return self.X * other.X + self.Y * other.Y + self.Z * other.Z end
	vm.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
		if key == "Unit" then return v / v.Magnitude end
		return Vector[key]
	end
	vm.__add = function(a, b) return Vector.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	vm.__sub = function(a, b) return Vector.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	vm.__mul = function(a, b) if type(a) == "number" then a, b = b, a end; return Vector.new(a.X * b, a.Y * b, a.Z * b) end
	vm.__div = function(a, b) return Vector.new(a.X / b, a.Y / b, a.Z / b) end
	vm.__unm = function(a) return a * -1 end
	Vector.zero, Vector.one = Vector.new(0, 0, 0), Vector.new(1, 1, 1)
	local V = Vector.new
	local queryStub = {Exclude = function(ignore) return ignore end}
	local identity = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	local Frame, fm = {}, {}
	local function frame(position, matrix) return setmetatable({ Position = position, matrix = matrix }, fm) end
	function Frame.new(x, y, z)
		return frame(type(x) == "table" and x or V(x or 0, y or 0, z or 0), table.clone(identity))
	end
	function Frame:VectorToWorldSpace(v)
		local r = self.matrix
		return V(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
	end
	function Frame:PointToWorldSpace(v) return self.Position + self:VectorToWorldSpace(v) end
	function Frame:Inverse()
		local r = self.matrix
		local inverse = frame(Vector.zero, { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] })
		inverse.Position = inverse:VectorToWorldSpace(-self.Position)
		return inverse
	end
	function Frame:VectorToObjectSpace(v) return self:Inverse():VectorToWorldSpace(v) end
	function Frame:PointToObjectSpace(v) return self:Inverse():PointToWorldSpace(v) end
	function Frame:ToObjectSpace(other) return self:Inverse() * other end
	function Frame:Lerp(other, alpha)
		local r = {}; for i = 1, 9 do r[i] = self.matrix[i] + (other.matrix[i] - self.matrix[i]) * alpha end
		return frame(self.Position + (other.Position - self.Position) * alpha, r)
	end
	fm.__index = function(cf, key)
		if key == "Rotation" then return frame(Vector.zero, cf.matrix) end
		if key == "LookVector" then return cf:VectorToWorldSpace(V(0, 0, -1)) end
		return Frame[key]
	end
	fm.__mul = function(a, b)
		local r = {}
		for row = 0, 2 do for column = 0, 2 do
			local sum = 0; for k = 0, 2 do sum += a.matrix[row * 3 + k + 1] * b.matrix[k * 3 + column + 1] end
			r[row * 3 + column + 1] = sum
		end end
		return frame(a:PointToWorldSpace(b.Position), r)
	end
	function Frame.Angles(x, y, z)
		local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
		return frame(Vector.zero, { 1, 0, 0, 0, cx, -sx, 0, sx, cx })
			* frame(Vector.zero, { cy, 0, sy, 0, 1, 0, -sy, 0, cy })
			* frame(Vector.zero, { cz, -sz, 0, sz, cz, 0, 0, 0, 1 })
	end
	function Frame.lookAt(position, target, up)
		local look = (target - position).Unit
		local right = look:Cross(up or V(0, 1, 0)).Unit
		local vertical = right:Cross(look)
		return frame(position, { right.X, vertical.X, -look.X, right.Y, vertical.Y, -look.Y, right.Z, vertical.Z, -look.Z })
	end
	function Frame.fromAxisAngle(axis, angle)
		local x, y, z = axis.X, axis.Y, axis.Z
		local c, s, k = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
		return frame(Vector.zero, {c + x*x*k, x*y*k-z*s, x*z*k+y*s,
			y*x*k+z*s, c+y*y*k, y*z*k-x*s, z*x*k-y*s, z*y*k+x*s, c+z*z*k})
	end
	function Frame:ToAxisAngle()
		local r = self.matrix
		local angle = math.acos(math.clamp((r[1] + r[5] + r[9] - 1) / 2, -1, 1))
		if angle < 1e-7 then return V(1, 0, 0), 0 end
		local axis = V(r[8] - r[6], r[3] - r[7], r[4] - r[2])
		if axis.Magnitude < 1e-7 then return V(1, 0, 0), angle end
		return axis.Unit, angle
	end
	Frame.identity = Frame.new()
	local Config = load("Config")
	local InspectConfig = load("InspectConfig")
	local InspectMotion = load("InspectMotion", {CFrame = Frame, script = {Parent = {WeaponInspectConfig = "InspectConfig"}},
		require = function(name) assert(name == "InspectConfig"); return InspectConfig end})
	local Math = load("Math", { CFrame = Frame, Vector3 = Vector })
	local settings = Config.Default.Pose
	local ToolPhysics = load("ToolPhysics")
	local Motion = load("ViewmodelMath", {CFrame = Frame, Vector3 = Vector})
	local firstPerson = Config.Default.FirstPerson
	test("walk and sprint avatar animations stay nearly fixed at 30 60 and 144 FPS", function()
		for _, tuning in ipairs({firstPerson, load("KnifeConfig").FirstPerson}) do
			for _, hz in ipairs({30, 60, 144}) do
				local state, posture, rendered = Motion.New(), nil, nil
				for tick = 1, hz * 4 do
					local phase = tick / hz * 12
					local body = Frame.new(math.sin(phase) * 0.4, math.cos(phase) * 0.4, 0.2)
						* Frame.Angles(math.sin(phase) * 0.5, 0, 0.3)
					local arm = Frame.Angles(math.sin(phase) * 1.2, 0.2, 0)
					rendered, posture = Motion.Step(state, Frame.identity, 1/hz, false, false, 32, tuning, body, arm)
					if tick > hz then
						assert(posture.Position.Magnitude <= tuning.MaxMovementAnimationOffset + 0.0001)
						local _, angle = posture:ToAxisAngle()
						assert(angle <= math.rad(tuning.MaxMovementAnimationDegrees) + 0.0001)
						assert((rendered.Position - V(table.unpack(tuning.ArmPosition))).Magnitude < 0.025)
					end
				end
				assert(state.bob <= 1 and state.movement > 0.99)
				for _ = 1, hz*2 do Motion.Step(state, Frame.identity, 1/hz, false, false, 0, tuning) end
				assert(state.movement < 1e-5 and state.bob < 1e-5)
			end
		end
	end)
	test("both first-person weapons keep walking bob and airborne animation within tighter sightline budgets", function()
		local knife = load("KnifeConfig").FirstPerson
		for _, tuning in ipairs({firstPerson, knife}) do
			for _, hz in ipairs({30, 60, 144}) do
				local state = Motion.New()
				for _ = 1, hz * 2 do Motion.Step(state, Frame.identity, 1/hz, false, false, 32, tuning) end
				for _ = 1, hz do
					local frame = Motion.Step(state, Frame.identity, 1/hz, false, false, 32, tuning)
					assert(math.abs(frame.Position.Y - tuning.ArmPosition[2]) < 0.01)
					assert(math.abs(frame.Position.X - tuning.ArmPosition[1]) < 0.02)
				end
				local airborne
				for _ = 1, hz * 2 do
					_, airborne = Motion.Step(state, Frame.identity, 1/hz, false, false, 32, tuning,
						Frame.new(0, 2, 0) * Frame.Angles(1.2, 0.5, 0), Frame.Angles(1.8, 0, 0), nil, {airborne = true})
				end
				assert(airborne.Position.Y <= 0.02)
				local _, angle = airborne:ToAxisAngle(); assert(angle <= math.rad(2) + 1e-6)
			end
		end
	end)
	test("jump pose stays below its upward cap with reduced rotation and bob", function()
		for _, hz in ipairs({30, 60, 144}) do
			local state, posture = Motion.New(), nil
			for _ = 1, hz * 2 do
				_, posture = Motion.Step(state, Frame.identity, 1/hz, false, false, 32, firstPerson,
					Frame.new(0, 2, 0) * Frame.Angles(0.8, 0, 0), Frame.Angles(1.8, 0, 0), nil, {airborne = true})
			end
			assert(posture.Position.Y <= firstPerson.MaxUpwardAnimationOffset + 1e-6)
			local _, angle = posture:ToAxisAngle(); assert(angle <= math.rad(firstPerson.AirMaxAnimationDegrees) + 1e-6)
		end
	end)
	test("inspection damps sprint posture smoothly without changing action authority", function()
		local function settle(inspectBlend)
			local state, posture = Motion.New(), nil
			for _ = 1, 120 do
				_, posture = Motion.Step(state, Frame.identity, 1/60, false, false, 32, firstPerson,
					Frame.new(0.2, -0.2, 0.1) * Frame.Angles(0.4, 0, 0), Frame.Angles(0.8, 0, 0), nil,
					{inspectBlend = inspectBlend})
			end
			return posture
		end
		local sprint, inspect = settle(0), settle(1)
		assert(inspect.Position.Magnitude < sprint.Position.Magnitude * 0.2)
		local _, sprintAngle = sprint:ToAxisAngle(); local _, inspectAngle = inspect:ToAxisAngle()
		assert(inspectAngle < sprintAngle * 0.2)
	end)
	test("first-person is restricted to fully zoomed in with a small numerical tolerance", function()
		assert(Motion.FirstPerson(false, 0.5, firstPerson))
		assert(not Motion.FirstPerson(false, 0.56, firstPerson))
		assert(Motion.FirstPerson(true, 0.56, firstPerson))
		for _, distance in ipairs({0.6, 0.7, 0.8, 1, 1.4, 5}) do
			assert(not Motion.FirstPerson(true, distance, firstPerson) and not Motion.FirstPerson(false, distance, firstPerson))
		end
	end)
	test("crouch and slide animation are smoothed, bounded and return to neutral", function()
		local state = Motion.New()
		local body = Frame.new(0, -2, 0) * Frame.Angles(math.pi/2, 0, 0)
		local arm = Frame.Angles(0, 0, 0.4)
		local _, first = Motion.Step(state, Frame.identity, 1/60, false, false, 0, firstPerson, body, arm)
		assert(first.Position.Y < 0 and first.Position.Y > -firstPerson.MaxAnimationOffset)
		local posture
		for _ = 1, 180 do _, posture = Motion.Step(state, Frame.identity, 1/60, false, false, 0, firstPerson, body, arm) end
		near(posture.Position.Y, -firstPerson.MaxAnimationOffset)
		local _, angle = posture:ToAxisAngle(); assert(angle <= math.rad(firstPerson.MaxAnimationDegrees) + 1e-5)
		for _ = 1, 180 do _, posture = Motion.Step(state, Frame.identity, 1/60, false, false, 0, firstPerson) end
		assert(posture.Position.Magnitude < 1e-5)
		local _, neutralAngle = posture:ToAxisAngle(); assert(neutralAngle < 1e-5)
	end)
	test("actual movement remains visible while aiming with reduced animation influence", function()
		local function settle(aiming)
			local state = Motion.New(); local posture
			for _ = 1, 180 do
				_, posture = Motion.Step(state, Frame.identity, 1/60, aiming, false, 0, firstPerson,
					Frame.new(0, -0.4, 0) * Frame.Angles(0.3, 0, 0), Frame.identity)
			end
			return posture
		end
		local hip, aim = settle(false), settle(true)
		assert(hip.Position.Y < aim.Position.Y and aim.Position.Y < 0)
		near(aim.Position.Y / hip.Position.Y, firstPerson.AnimationAimScale)
	end)
	test("animation follow timing agrees at 30 and 144 FPS without accumulating posture", function()
		local function settle(hz)
			local state = Motion.New(); local posture
			for _ = 1, hz do
				_, posture = Motion.Step(state, Frame.identity, 1/hz, false, false, 0, firstPerson,
					Frame.new(0.1, -0.3, 0.1) * Frame.Angles(0.2, 0.1, 0), Frame.Angles(0, 0, 0.15))
			end
			return posture
		end
		local a, b = settle(30), settle(144)
		near((a.Position - b.Position).Magnitude, 0)
		for i = 1, 9 do near(a.matrix[i], b.matrix[i]) end
	end)
	test("first-person aiming settles lower and left without camera movement", function()
		local hip, aim = Motion.New(), Motion.New()
		local h, a
		for _ = 1, 180 do
			h = Motion.Step(hip, Frame.identity, 1/60, false, false, 0, firstPerson)
			a = Motion.Step(aim, Frame.identity, 1/60, true, false, 0, firstPerson)
		end
		near(a.Position.X - h.Position.X, firstPerson.AimOffset[1])
		near(a.Position.Y - h.Position.Y, firstPerson.AimOffset[2])
		assert(a.Position.X < h.Position.X and a.Position.Y < h.Position.Y)
	end)
	test("first-person transitions and recoil recovery agree at 30 and 144 FPS", function()
		local function simulate(hz)
			local state = Motion.New(); Motion.Kick(state)
			for _ = 1, hz do Motion.Step(state, Frame.identity, 1/hz, true, true, 0, firstPerson) end
			return state
		end
		local a, b = simulate(30), simulate(144)
		for _, key in ipairs({"aim", "reload", "raise", "recoil"}) do near(a[key], b[key]) end
	end)
	test("camera snaps and stalled frames keep sway bounded and recoil capped", function()
		local state = Motion.New()
		Motion.Step(state, Frame.identity, 1/60, false, false, 0, firstPerson)
		for i = 1, 50 do
			Motion.Step(state, Frame.Angles(i * 2, i * 3, 0), 1/144, false, false, 0, firstPerson)
			assert(math.abs(state.swayX) <= 1 and math.abs(state.swayY) <= 1)
			Motion.Kick(state)
		end
		near(state.recoil, 2)
		Motion.Step(state, Frame.identity, 1, false, false, 0, firstPerson)
		assert(state.recoil < 1e-5 and math.abs(state.swayX) < 1e-5)
	end)
	test("first-person per-skin offsets merge independently from shared defaults", function()
		Config.Overrides.TestView = {FirstPerson = {AimOffset = {-0.4, -0.2, 0.1}}}
		local a, b = Config.Get("TestView"), Config.Get("TestView")
		assert(a.FirstPerson.SwaySpeed == firstPerson.SwaySpeed)
		a.FirstPerson.AimOffset[1] = -1
		near(b.FirstPerson.AimOffset[1], -0.4); near(firstPerson.AimOffset[1], -0.3)
		Config.Overrides.TestView = nil
	end)
	test("headshot damage and optional empty-click settings inherit per skin and reject invalid values", function()
		local config = load("Config")
		assert(config.Get("Normal Revolver").Damage == 34 and config.Get("Normal Revolver").HeadshotDamage == 70)
		assert(config.Get("Normal Revolver").Effects.EmptySoundId == "")
		config.Overrides.TestClick = {HeadshotDamage = 80, Effects = {
			EmptySoundId = "rbxassetid://123456", EmptySoundVolume = 0.4, EmptySoundCooldownMs = 400}}
		local custom = config.Get("TestClick")
		assert(custom.Damage == 34 and custom.HeadshotDamage == 80 and custom.Effects.EmptySoundVolume == 0.4)
		assert(config.Get("Normal Revolver").HeadshotDamage == 70 and config.Get("Normal Revolver").Effects.EmptySoundId == "")
		for _, override in ipairs({
			{HeadshotDamage = 0}, {HeadshotDamage = math.huge}, {HeadshotDamage = 0/0},
			{Effects = {EmptySoundId = 123}}, {Effects = {EmptySoundVolume = -1}},
			{Effects = {EmptySoundVolume = 0/0}}, {Effects = {EmptySoundCooldownMs = 0}},
			{Effects = {EmptySoundCooldownMs = math.huge}},
		}) do
			config.Overrides.TestInvalidClick = override
			assert(not pcall(config.Get, "TestInvalidClick"))
		end
	end)
	local RayMath = load("RayMath", { typeof = function(value) return type(value) == "table" and value.kind or type(value) end })
	local Raycast = load("Raycast", { script = { Parent = { RevolverMath = "RayMath" } }, require = function() return RayMath end, Vector3 = Vector, CFrame = Frame })
	local function worldBoxes(boxes)
		return function(origin, vector)
			local length = vector.Magnitude
			if length < 1e-8 then return nil end
			local direction, nearest = vector.Unit, nil
			for _, box in ipairs(boxes) do
				local position = origin - box.position
				local distance = RayMath.RayAabbDistance(position.X, position.Y, position.Z, direction.X, direction.Y, direction.Z,
					box.size[1] / 2, box.size[2] / 2, box.size[3] / 2, length)
				if distance and (not nearest or distance < nearest.Distance) then
					nearest = { Distance = distance, Normal = V(0, 1, 0) }
				end
			end
			return nearest
		end
	end
	test("a visible cursor ledge between camera and avatar can be shot behind the character", function()
		local target = { frame = Frame.new(0, 1, -40) }
		local worldCast = worldBoxes({ { position = V(0, 1, 3), size = { 6, 0.6, 2 } } })
		local result = Raycast.Resolve(V(0, 1, 8), V(0, 0, -1), V(0, 1, 0), Config.Default, { target }, worldCast)
		assert(result and not result.victim and result.normal, "The cursor's foreground ledge must remain selectable")
		near(result.position.Z, 2)
	end)
	test("cursor ground behind the character remains a valid third-person target", function()
		local function ground(origin, vector)
			if vector.Y >= 0 or origin.Y < 0 then return nil end
			local fraction = -origin.Y / vector.Y
			if fraction < 0 or fraction > 1 then return nil end
			return { Distance = vector.Magnitude * fraction, Normal = V(0, 1, 0) }
		end
		local muzzle, direction = V(1, 5, 0), V(0, -0.5, -1).Unit
		local result = Raycast.Resolve(V(0, 2, 8), direction, muzzle, Config.Default, {}, ground)
		assert(result and result.position.Z > 0, "The visible floor under the cursor must not be skipped behind the character")
		near(result.position.Y, 0)
		near(result.position.Z, 4)
		assert((result.position - muzzle):Dot(direction) < 0)
	end)
	test("first-person and shoulder aiming retain cursor alignment and barrel range", function()
		local target = { frame = Frame.new(0, 3, -40) }
		for _, pair in ipairs({ { V(0, 3, 0), V(1, 2.5, -1) }, { V(0, 3, 10), V(1, 2.5, -1) } }) do
			local result = Raycast.Resolve(pair[1], V(0, 0, -1), pair[2], Config.Default, { target }, function() return nil end)
			assert(result and result.victim == target)
			near(result.position.X, 0); near(result.position.Y, 3)
			assert(result.distance <= Config.Default.Range)
		end
	end)
	test("real camera and barrel obstructions still stop shots", function()
		local target = { frame = Frame.new(0, 1, -40) }
		for _, obstacle in ipairs({ { position = V(0, 2, -4), size = { 6, 6, 1 } },
			{ position = V(1, 2, -3), size = { 0.5, 0.5, 0.5 } } }) do
			local result = Raycast.Resolve(V(0, 1, 8), V(0, 0, -1), V(1, 2, 0), Config.Default, { target }, worldBoxes({ obstacle }))
			assert(result and not result.victim and result.normal, "Cover must still stop damage")
			assert(result.position.Z > -5 and result.position.Z < 0)
		end
	end)
	test("cursor picking starts at the camera across steep angles and physical shots never extend range", function()
		for _, direction in ipairs({ V(0, 0, -1), V(0.4, 0.5, -1).Unit, V(-0.4, -0.6, -1).Unit, V(0, 1, 0), V(0, -1, 0) }) do
			local camera, muzzle = V(0, 4, 8), V(1, 2, 0)
			local origin = Raycast.GetAimOrigin(camera, direction, muzzle)
			near((origin - camera).Magnitude, 0)
			local result = Raycast.Resolve(camera, direction, muzzle, Config.Default, {}, function() return nil end)
			assert(result and result.distance <= Config.Default.Range)
			assert((result.position - muzzle):Dot(direction) > 0)
		end
	end)
	test("cursor pitch rises/falls and yaw uses the character's forward axis", function()
		local pitch, yaw = Math.Angles(0, 1, -1, settings); near(pitch, math.pi / 4); near(yaw, 0)
		pitch, yaw = Math.Angles(0, -1, -1, settings); near(pitch, -math.pi / 4)
		pitch, yaw = Math.Angles(1, 0, -1, settings); near(yaw, -math.pi / 4)
		pitch, yaw = Math.Angles(0, 0, 0, settings); near(pitch, 0); near(yaw, 0)
		pitch = Math.Angles(0, 100, 0, settings); near(pitch, math.rad(75))
		pitch = Math.Angles(0, -100, 0, settings); near(pitch, math.rad(-65))
	end)
	test("smoothing is independent of frame rate", function()
		local function converge(hz)
			local value = 0
			for _ = 1, hz do value += (1 - value) * Math.Alpha(settings.FollowSpeed, 1 / hz) end
			return value
		end
		near(converge(30), converge(144)); near(Math.Alpha(20, -1), 0)
	end)
	test("pose packets reject replay, out-of-order, NaN, infinity and excessive angles", function()
		local state = {}
		assert(Math.AcceptPacket(state, 2, 0.1, 0.2, settings))
		for _, packet in ipairs({ { 1, 0, 0 }, { 2, 0, 0 }, { 3.5, 0, 0 }, { 4, math.huge, 0 },
			{ 4, 0 / 0, 0 }, { 4, 0, 10 }, { 4, -2, 0 }, { 2147483648, 0, 0 } }) do
			assert(not Math.AcceptPacket(state, packet[1], packet[2], packet[3], settings))
		end
		assert(Math.AcceptPacket(state, 10, 0, 0, settings))
	end)
	test("R6 shoulder solution preserves its anchor", function()
		for _, c0 in ipairs({ Frame.new(1, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0), Frame.new(1, 0.8, 0) }) do
			local c1 = Frame.new(-0.5, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0)
			for _, pitch in ipairs({ -0.6, 0, 0.6 }) do
				local goal = Math.ShoulderTransform(c0, c1, pitch, 0.2, { 0, 0, 0 })
				local arm = c0 * goal * c1:Inverse()
				local anchor = arm:PointToWorldSpace(c1.Position)
				near((anchor - c0.Position).Magnitude, 0)
				local palm = arm:VectorToWorldSpace(V(0, -1, 0))
				near(palm.Y, math.sin(pitch)); near(palm.Z, -math.cos(pitch) * math.cos(0.2))
			end
		end
	end)
	test("per-gun Pose overrides retain default smoothing and effects", function()
		Config.Overrides.Test = { Pose = { MaxPitchDegrees = 60 }, Aim = { FieldOfView = 55 }, Effects = { SmokeEnabled = false } }
		local tuning = Config.Get("Test")
		assert(tuning.Pose.MaxPitchDegrees == 60 and tuning.Pose.FollowSpeed == settings.FollowSpeed)
		assert(tuning.Effects.SmokeEnabled == false and tuning.Effects.MuzzleFlashEnabled)
		assert(tuning.Aim.FieldOfView == 55 and tuning.Aim.BodyFollowSpeed == 24 and Config.Default.Aim.FieldOfView == 60)
		assert(Config.Default.Pose.MaxPitchDegrees == 75 and Config.Default.Effects.SmokeEnabled)
		Config.Overrides.Test = nil
	end)

	local function signal()
		local handlers = {}
		return { Connect = function(_, fn)
			local connection = { Connected = true }
			handlers[connection] = fn
			function connection:Disconnect() self.Connected = false; handlers[self] = nil end
			return connection
		end, Fire = function(_, ...) for _, fn in pairs(handlers) do fn(...) end end,
			Count = function() local n = 0; for _ in pairs(handlers) do n += 1 end; return n end }
	end
	local function object(class, name)
		local obj = { kind = "Instance", ClassName = class, Name = name, children = {}, Transform = Frame.identity, Size = V(1, 2, 1), ChildAdded = signal(), ChildRemoved = signal(), Activated = signal(), DescendantAdded = signal(), DescendantRemoving = signal() }
		function obj:IsA(kind) return kind == class or (kind == "BasePart" and class == "Part") end
		function obj:GetChildren() self.childReads = (self.childReads or 0) + 1; return self.children end
		function obj:GetDescendants()
			self.descendantReads = (self.descendantReads or 0) + 1
			local result = {}; for _, child in ipairs(self.children) do table.insert(result, child); for _, d in ipairs(child:GetDescendants()) do table.insert(result, d) end end
			return result
		end
		function obj:FindFirstChild(childName) for _, child in ipairs(self.children) do if child.Name == childName then return child end end end
		function obj:FindFirstChildOfClass(kind) for _, child in ipairs(self.children) do if child:IsA(kind) then return child end end end
		function obj:GetAttribute(name) return self.attributes and self.attributes[name] end
		function obj:SetAttribute(name, value) self.attributes = self.attributes or {}; self.attributes[name] = value end
		function obj:GetPropertyChangedSignal(name)
			self.propertySignals = self.propertySignals or {}; self.propertySignals[name] = self.propertySignals[name] or signal()
			return self.propertySignals[name]
		end
		obj.FindFirstChildWhichIsA = obj.FindFirstChildOfClass
		function obj:Destroy() self.Parent = nil; self.destroyed = true; for _, child in ipairs(self.children) do child:Destroy() end end
		function obj:Emit(count) self.emitted = (self.emitted or 0) + count end
		function obj:Clear() self.cleared = (self.cleared or 0) + 1 end
		function obj:Stop() self.stopped = (self.stopped or 0) + 1 end
		function obj:Play() self.played = true end
		function obj:Clone()
			assert(class == "Sound", "Add fixture support for cloning " .. class)
			local copy = object(class, self.Name)
			copy.SoundId = self.SoundId
			if self.created then table.insert(self.created, copy) end
			return copy
		end
		function obj:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
		return setmetatable(obj, {__index = function(self, key)
			if key == "CFrame" and class == "Part" then return Frame.new(self.Position or Vector.zero) end
			if key == "WorldCFrame" and class == "Attachment" then
				local basis = self.Parent and self.Parent.CFrame or Frame.identity
				local localFrame = self.CFrame or Frame.new(self.Position or Vector.zero)
				local full = basis * localFrame
				if rawget(self, "WorldPosition") then return Frame.new(self.WorldPosition) * full.Rotation end
				return full
			end
			if key == "WorldPosition" and class == "Attachment" and self.Parent and self.Parent:IsA("BasePart") then
				return (self.Parent.CFrame or Frame.identity):PointToWorldSpace(self.CFrame and self.CFrame.Position or self.Position or Vector.zero)
			end
		end})
	end
	local function fixture()
		local character, torso, arm = object("Model", "Character"), object("Part", "Torso"), object("Part", "Right Arm")
		torso.CFrame, arm.CFrame = Frame.new(), Frame.new(1.5, 0, 0)
		local humanoid = object("Humanoid", "Humanoid"); humanoid.Health, humanoid.Parent, humanoid.AutoRotate, humanoid.CameraOffset = 100, character, true, Vector.zero
		local tool = object("Tool", "Amber Revolver"); tool.Parent = character
		local joint = object("Motor6D", "Right Shoulder")
		local c0, c1 = Frame.new(1, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0), Frame.new(-0.5, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0)
		joint.Parent, joint.Part0, joint.Part1, joint.C0, joint.C1 = torso, torso, arm, c0, c1
		local left = object("Part", "Left Arm"); left.Parent, arm.Parent = character, character
		local support = object("Motor6D", "Left Shoulder")
		support.Parent, support.Part0, support.Part1 = torso, torso, left
		support.C0, support.C1 = Frame.new(-1, 0.5, 0) * Frame.Angles(0, -math.pi / 2, 0), Frame.new(0.5, 0.5, 0) * Frame.Angles(0, -math.pi / 2, 0)
		local root = object("Part", "HumanoidRootPart"); root.CFrame, root.Position, root.Parent = Frame.identity, Vector.zero, character
		local head = object("Part", "Head"); head.Position, head.Parent = V(0, 2, 0), character
		torso.children = { joint, support }; character.children = { torso, arm, left, root, head, humanoid, tool }
		character.Parent = {}
		local player = { Character = character, UserId = 1, CharacterAdded = signal(), CharacterRemoving = signal(), CameraMaxZoomDistance = 40 }
		function player:FindFirstChild() return nil end
		local now, created = 100, {}
		local events = { PreAnimation = signal(), PreSimulation = signal(), RenderStepped = signal() }
		local bindings = {}
		function events:BindToRenderStep(name, priority, callback) bindings[name] = { priority = priority, fn = callback } end
		function events:UnbindFromRenderStep(name) bindings[name] = nil end
		local players = { LocalPlayer = player, PlayerRemoving = signal(), GetPlayers = function() return { player } end, GetPlayerByUserId = function() return nil end }
		local remote = { OnClientEvent = signal(), sent = {} }
		function remote:FireServer(...) table.insert(self.sent, { ... }) end
		local input = { MouseBehavior = "Default", MouseIconEnabled = true, MouseEnabled = true, TouchEnabled = false,
			mousePressed = true, IsMouseButtonPressed = function(self) return self.mousePressed end,
			InputBegan = signal(), InputEnded = signal(), WindowFocusReleased = signal(), TextBoxFocused = signal(), LastInputTypeChanged = signal(),
			GetFocusedTextBox = function() return nil end, GetMouseLocation = function() return { X = 123, Y = 234 } end }
		local services = { Players = players, UserInputService = input, GuiService = { MenuOpened = signal() }, RunService = events,
			ContentProvider = {PreloadAsync = function() end},
			ReplicatedStorage = { Modules = { WeaponInspectConfig = "InspectConfig", WeaponInspectMotion = "InspectMotion", RagdollQuery = "RagdollQuery", RevolverConfig = "Config", RevolverToolPhysics = "ToolPhysics", CursorConfig = "CursorConfig", RevolversInfo = "Catalog", RevolverPoseMath = "Math", RevolverRaycast = "Raycast", MouseCursorVisibility = "MouseVisibility" } },
			Debris = { AddItem = function() end }, TweenService = { Create = function() return { Play = function() end } end } }
		local function constructor(...) return { ... } end
		local env = {
			task = {spawn = function(fn, ...) fn(...) end},
			game = { GetService = function(_, name) return assert(services[name], name) end }, workspace = { GetServerTimeNow = function() return now end },
			os = { clock = function() return now end }, CFrame = Frame, Vector3 = Vector,
			Vector2 = { new = constructor }, Color3 = { new = constructor, fromRGB = constructor },
			ColorSequence = { new = constructor }, ColorSequenceKeypoint = { new = constructor },
			NumberRange = { new = constructor }, NumberSequence = { new = constructor }, NumberSequenceKeypoint = { new = constructor }, TweenInfo = { new = constructor },
			typeof = function(value) return type(value) == "table" and value.kind or typeof(value) end,
			Enum = { SurfaceGuiSizingMode = {FixedSize = "FixedSize"}, Material = { Air = "Air", Neon = "Neon" }, NormalId = { Front = "Front" }, TextureMode = { Stretch = "Stretch" }, AnimationPriority = { Action4 = "Action4" },
				UserInputState = { End = "End", Cancel = "Cancel" },
				MouseBehavior = { Default = "Default", LockCenter = "LockCenter", LockCurrentPosition = "LockCurrentPosition" }, CameraType = { Custom = "Custom", Scriptable = "Scriptable" },
				RenderPriority = { Camera = { Value = 200 } }, RaycastFilterType = { Exclude = "Exclude" }, Font = { GothamBold = "GothamBold" } },
			RaycastParams = { new = function() return {} end }, UDim2 = { new = constructor, fromScale = constructor, fromOffset = constructor }, UDim = {new = constructor},
			Instance = { new = function(class) local obj = object(class, class); obj.created = created; table.insert(created, obj); return obj end },
			require = function(name) return assert(({ RagdollQuery = queryStub, Config = Config, ToolPhysics = ToolPhysics, Math = Math, Raycast = Raycast, Catalog = { ["Amber Revolver"] = {} } })[name]) end,
		}
		local camera = { FieldOfView = 70, CFrame = Frame.new(0, 0, 10), Focus = Frame.identity, CameraSubject = humanoid, CameraType = "Custom", ViewportSize = { X = 1000, Y = 600 } }
		local visibility = load("MouseVisibility", env)
		local requireModule = env.require
		env.require = function(name) if name == "MouseVisibility" then return visibility end; return requireModule(name) end
		env.workspace.CurrentCamera = camera
		local f = { env = env, joint = joint, support = support, torso = torso, root = root, humanoid = humanoid, input = input,
			tool = tool, player = player, character = character, events = events, created = created, remote = remote, bindings = bindings, camera = camera, services = services, visibility = visibility }
		function f.advance(dt)
			now += dt; events.RenderStepped:Fire(dt)
			local sorted = {}; for _, b in pairs(bindings) do table.insert(sorted, b) end
			table.sort(sorted, function(a, b) return a.priority < b.priority end)
			for _, b in ipairs(sorted) do b.fn(dt) end
		end
		function f.step() events.PreAnimation:Fire(); events.PreSimulation:Fire(1 / 60) end
		return f
	end
	local function collisionFixture()
		local f = fixture()
		f.groups, f.masks, f.groupWrites, f.warnings = {Default = true, PlayerCharacters = true, DeathRagdolls = true}, {}, {}, {}
		local function pair(a, b) return a < b and a .. ":" .. b or b .. ":" .. a end
		f.physics = {}
		function f.physics:IsCollisionGroupRegistered(name) return f.groups[name] == true end
		function f.physics:RegisterCollisionGroup(name)
			if f.registrationFailure then error("simulated group registration failure") end
			f.groups[name] = true
		end
		function f.physics:GetRegisteredCollisionGroups()
			local groups = {}; for name in pairs(f.groups) do table.insert(groups, {name = name}) end; return groups
		end
		function f.physics:CollisionGroupsAreCollidable(a, b) return f.masks[pair(a, b)] ~= false end
		function f.physics:CollisionGroupSetCollidable(a, b, value)
			assert(f.groups[a] and f.groups[b]); f.masks[pair(a, b)] = value
			table.insert(f.groupWrites, {a, b, value})
		end
		f.services.PhysicsService = f.physics
		local attributes = {}
		f.services.ReplicatedStorage.GetAttribute = function(_, name) return attributes[name] end
		f.services.ReplicatedStorage.SetAttribute = function(_, name, value) attributes[name] = value end
		f.events.Heartbeat = signal()
		f.env.warn = function(message) table.insert(f.warnings, message) end
		f.setup = load("ViewmodelPhysicsServer", f.env)
		return f
	end
	test("viewmodel collision group excludes all registered groups without changing character or world collisions", function()
		local f = collisionFixture(); f.setup.Init(); local group = Config.FirstPersonPhysics.CollisionGroup
		assert(f.services.ReplicatedStorage:GetAttribute(Config.FirstPersonPhysics.ReadyAttribute))
		for name in pairs(f.groups) do assert(not f.physics:CollisionGroupsAreCollidable(group, name)) end
		assert(f.physics:CollisionGroupsAreCollidable("Default", "PlayerCharacters"))
		assert(f.physics:CollisionGroupsAreCollidable("PlayerCharacters", "DeathRagdolls"))
		for _, write in ipairs(f.groupWrites) do assert(write[1] == group and write[3] == false) end
		f.setup.Init(); assert(f.events.Heartbeat:Count() == 1)
	end)
	test("viewmodel collision mask covers late groups and repairs resets without per-frame group writes", function()
		local f = collisionFixture(); f.setup.Init(); local group = Config.FirstPersonPhysics.CollisionGroup
		local writes = #f.groupWrites
		for _ = 1, 20 do f.events.Heartbeat:Fire(0.01) end
		assert(#f.groupWrites == writes)
		f.groups.MapSpecific = true
		f.events.Heartbeat:Fire(1); assert(not f.physics:CollisionGroupsAreCollidable(group, "MapSpecific"))
		assert(f.physics:CollisionGroupsAreCollidable("Default", "MapSpecific"))
		f.physics:CollisionGroupSetCollidable(group, "Default", true)
		f.events.Heartbeat:Fire(1); assert(not f.physics:CollisionGroupsAreCollidable(group, "Default"))
	end)
	test("failed collision setup keeps presentation unready and recovers without repeated warnings", function()
		local f = collisionFixture(); f.registrationFailure = true; f.setup.Init()
		assert(f.services.ReplicatedStorage:GetAttribute(Config.FirstPersonPhysics.ReadyAttribute) == false)
		f.events.Heartbeat:Fire(1); f.events.Heartbeat:Fire(1); assert(#f.warnings == 1)
		f.registrationFailure = false; f.events.Heartbeat:Fire(1)
		assert(f.services.ReplicatedStorage:GetAttribute(Config.FirstPersonPhysics.ReadyAttribute) == true)
	end)
	test("ADS and weapon crosshair share native cursor ownership without early restoration", function()
		for _, weaponFirst in ipairs({true, false}) do
			local f = fixture(); local aim = load("Camera", f.env)
			if weaponFirst then f.visibility.Acquire("WeaponCursor") end
			assert(aim.Start(f.tool, Config.Get(f.tool.Name).Aim, function() return true end))
			if not weaponFirst then f.visibility.Acquire("WeaponCursor") end
			f.advance(1 / 60); assert(f.input.MouseIconEnabled == false)
			if weaponFirst then
				aim.Stop(true); assert(f.input.MouseIconEnabled == false)
				f.visibility.Release("WeaponCursor")
			else
				f.visibility.Release("WeaponCursor"); assert(f.input.MouseIconEnabled == false)
				aim.Stop(true)
			end
			assert(f.input.MouseIconEnabled == true)
		end
	end)
	test("idle/walk arm is overridden after Animator and restored before the next update", function()
		local f = fixture(false); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("session")
		local walk = Frame.Angles(0, 0, -0.4); f.joint.Transform = walk
		pose.SetLocalAim(f.tool, V(0, 20, -40), false)
		f.step(); assert(f.joint.Transform ~= walk)
		f.events.PreAnimation:Fire(); assert(f.joint.Transform == walk)
		for _ = 1, 120 do f.step() end
		f.events.PreAnimation:Fire(); assert(f.joint.Transform == walk) -- no cumulative pose drift
		pose.SetLocalAim(nil); for _ = 1, 120 do f.step() end
		assert(f.joint.Transform == walk)
	end)
	test("first-person samples Animator motion instead of feeding the aimed shoulder back into itself", function()
		local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote)
		local rootJoint = object("Motor6D", "RootJoint")
		rootJoint.Parent, rootJoint.Part0, rootJoint.Part1 = f.root, f.root, f.torso
		rootJoint.C0, rootJoint.C1 = Frame.Angles(-math.pi/2, 0, math.pi), Frame.identity
		rootJoint.Transform = Frame.new(0, 0, -0.5) * Frame.Angles(0.3, 0, 0)
		f.root.children = {rootJoint}
		local walk = Frame.Angles(0, 0, -0.4); f.joint.Transform = walk
		pose.SetLocalAim(f.tool, V(0, 20, -40), false, true); f.step()
		assert(f.joint.Transform ~= walk)
		local applied = f.joint.Transform
		local body, arm = pose.GetLocalAnimation()
		local basis = rootJoint.C0.Rotation
		local expectedBody = basis * rootJoint.Transform * basis:Inverse()
		local expectedArm = f.joint.C0.Rotation * walk * f.joint.C0.Rotation:Inverse()
		near((body.Position - expectedBody.Position).Magnitude, 0)
		for i = 1, 9 do near(body.matrix[i], expectedBody.matrix[i]); near(arm.matrix[i], expectedArm.matrix[i]) end
		for _ = 1, 240 do pose.GetLocalAnimation() end
		assert(f.joint.Transform == applied and not f.character.descendantReads and not f.root.descendantReads)
		pose.SetLocalAim(nil); local inactiveBody, inactiveArm = pose.GetLocalAnimation()
		assert(not inactiveBody and not inactiveArm)
	end)
	test("two-hand hold blends in, follows pitch and restores both original joints", function()
		local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote)
		local walk = Frame.Angles(0.2, 0, 0); f.support.Transform = walk
		local c0, c1 = f.support.C0, f.support.C1
		pose.SetLocalAim(f.tool, V(0, 10, -40), false, false)
		for _ = 1, 60 do f.step() end
		assert(f.support.Transform == walk)
		pose.SetLocalAim(f.tool, V(0, 10, -40), false, true)
		for _ = 1, 60 do f.step() end
		assert(f.support.Transform ~= walk and f.support.C0 == c0 and f.support.C1 == c1)
		f.events.PreAnimation:Fire(); assert(f.support.Transform == walk)
		pose.ResetLocal(); assert(f.joint.Transform == Frame.identity and f.support.Transform == walk)
	end)
	test("rear aim is continuous over a full rotation with no left/right snap", function()
		local _, previous = Math.Angles(0, 0, -1, settings)
		for degrees = 1, 360 do
			local a = math.rad(degrees)
			local _, yaw = Math.Angles(math.sin(a), 0, -math.cos(a), settings)
			assert(math.abs(yaw - previous) <= math.rad(1.01)); previous = yaw
		end
		local _, left = Math.Angles(-1e-5, 0, 1, settings)
		local _, right = Math.Angles(1e-5, 0, 1, settings)
		assert(math.abs(left - right) < 0.001)
		near(Math.WrapAngle(math.rad(-179) - math.rad(179)), math.rad(2))
	end)
	test("pose networking is throttled and follows the current session", function()
		local f = fixture(false); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("one")
		for _ = 1, 100 do pose.SetLocalAim(f.tool, V(0, 20, -40), false) end
		assert(#f.remote.sent == 1 and f.remote.sent[1][1] == "one")
		f.advance(0.1); pose.SetLocalAim(f.tool, V(0, 20, -40), false); assert(#f.remote.sent == 1)
		f.advance(0.16); pose.SetLocalAim(f.tool, V(0, 20, -40), false); assert(#f.remote.sent == 2)
		pose.SetSession("two"); pose.SetLocalAim(f.tool, V(0, 20, -40), false)
		assert(f.remote.sent[3][1] == "two" and f.remote.sent[3][2] == 1)
		pose.SetLocalAim(f.tool, V(0, 20, -40), false, true)
		assert(f.remote.sent[4][5] == true)
	end)
	test("malformed ADS flags cannot advance a pose sequence", function()
		local state = {}
		assert(not Math.AcceptPacket(state, 1, 0, 0, settings, "true"))
		assert(not state.poseSequence)
		assert(Math.AcceptPacket(state, 1, 0, 0, settings, true))
	end)
	test("R6 pose caches joints and cursor params instead of scanning every frame", function()
		local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote)
		local allocations, rays = 0, 0
		f.env.RaycastParams.new = function() allocations += 1; return {} end
		f.env.workspace.Raycast = function() rays += 1; return nil end
		local ray = { Origin = Vector.zero, Direction = V(0, 0, -1) }
		pose.SampleCursor(f.tool, ray, false, true)
		for _ = 1, 144 do f.advance(1 / 144); pose.SampleCursor(f.tool, ray, false, true); f.step() end
		assert(allocations == 1 and rays <= 31)
		assert(not f.character.descendantReads and not f.character.childReads)
	end)
	test("arm cursor sampling retains rear targets between camera and avatar in free aim and ADS", function()
		for _, aiming in ipairs({ false, true }) do
			local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("session")
			f.torso.CFrame = Frame.new(0, 3, 0)
			local muzzle = object("Attachment", Config.Default.MuzzleAttachmentName)
			muzzle.WorldPosition, muzzle.Parent = V(1, 3, 0), f.tool
			table.insert(f.tool.children, muzzle)
			local ray = { Origin = V(0, 2, 8), Direction = V(0, 0, -1) }
			local foreground = worldBoxes({ { position = V(0, 2, 3), size = { 6, 0.6, 2 } } })
			local sampled
			f.env.workspace.Raycast = function(_, origin, vector)
				sampled = origin
				local hit = foreground(origin, vector)
				if hit then hit.Position = origin + vector.Unit * hit.Distance end
				return hit
			end
			pose.SampleCursor(f.tool, ray, false, aiming)
			near(sampled.X, 0); near(sampled.Y, 2); near(sampled.Z, 8)
			assert(#f.remote.sent == 1)
			local shoulder = f.torso.CFrame:PointToWorldSpace(f.joint.C0.Position)
			local direction = f.torso.CFrame:VectorToObjectSpace(V(0, 2, 4) - shoulder)
			local pitch, yaw = Math.Angles(direction.X, direction.Y, direction.Z, Config.Default.Pose)
			near(f.remote.sent[1][3], pitch); near(f.remote.sent[1][4], yaw)
		end
	end)
	test("aim camera centers input, smoothly zooms, and restores on release", function()
		local f = fixture(); local aim = load("Camera", f.env)
		assert(aim.Start(f.tool, Config.Default.Aim, function() return true end))
		assert(aim.IsAiming() and f.input.MouseBehavior == "LockCenter" and not f.humanoid.AutoRotate)
		for _ = 1, 60 do f.advance(1 / 60) end
		near(f.camera.FieldOfView, 60); near(f.humanoid.CameraOffset.X, 1.5)
		aim.Stop()
		assert(not aim.IsAiming() and f.input.MouseBehavior == "Default" and f.humanoid.AutoRotate and f.input.MouseIconEnabled)
		for _ = 1, 60 do f.advance(1 / 60) end
		near(f.camera.FieldOfView, 70); near(f.humanoid.CameraOffset.Magnitude, 0)
		assert(not next(f.bindings) and f.events.PreSimulation.Count() == 0)
	end)
	test("first person keeps its shoulder offset zero and hands mouse control back to the native camera", function()
		local f = fixture(); f.camera.CFrame = Frame.new(0, 0, 0.5)
		f.input.MouseBehavior, f.humanoid.AutoRotate = "LockCenter", false
		local aim = load("Camera", f.env); aim.Start(f.tool, Config.Default.Aim, function() return true end)
		for _ = 1, 60 do f.advance(1 / 60) end
		near(f.humanoid.CameraOffset.Magnitude, 0)
		aim.Stop(true); assert(f.input.MouseBehavior == "Default" and not f.humanoid.AutoRotate)
	end)
	test("a temporary LockCenter at aim start cannot become a permanent restored lock", function()
		local f = fixture(); f.input.MouseBehavior = "LockCenter"
		local aim = load("Camera", f.env); aim.Start(f.tool, Config.Default.Aim, function() return true end)
		aim.Stop(true); assert(f.input.MouseBehavior == "Default")
	end)
	test("camera update errors release controls and disconnect the aim loop", function()
		local f = fixture(); local fail = false; local aim = load("Camera", f.env)
		assert(aim.Start(f.tool, Config.Default.Aim, function() if fail then error("Simulated callback error") end; return true end))
		fail = true; f.advance(0.02)
		assert(not aim.IsAiming() and f.input.MouseBehavior == "Default" and f.input.MouseIconEnabled and f.humanoid.AutoRotate)
		assert(not next(f.bindings) and f.events.PreSimulation.Count() == 0)
	end)
	test("mobile shift-lock changes during ADS are preserved on release", function()
		local f = fixture(); local aim = load("Camera", f.env)
		aim.Start(f.tool, Config.Default.Aim, function() return true end)
		aim.SetExternalShiftLock(true); aim.Stop(true)
		assert(not f.humanoid.AutoRotate and f.input.MouseBehavior == "LockCenter")
		aim.Start(f.tool, Config.Default.Aim, function() return true end)
		f.humanoid.AutoRotate = true -- mobile toggle disables its loop first
		aim.SetExternalShiftLock(false); assert(not f.humanoid.AutoRotate)
		aim.Stop(true); assert(f.humanoid.AutoRotate and f.input.MouseBehavior == "Default")
	end)
	test("observing clients apply two-hand aim and ignore reordered or expired packets", function()
		local f, other = fixture(), fixture(); other.player.UserId = 2
		f.services.Players.GetPlayerByUserId = function(_, id) return id == 2 and other.player end
		local pose = load("Pose", f.env); pose.Init(f.remote)
		f.remote.OnClientEvent:Fire(2, other.character, "one", 2, 0.1, 0, true, false, 100)
		for _ = 1, 60 do f.step() end
		assert(other.support.Transform ~= Frame.identity)
		f.remote.OnClientEvent:Fire(2, other.character, "one", 1, 0.1, 0, false, false, 100)
		for _ = 1, 60 do f.step() end
		assert(other.support.Transform ~= Frame.identity)
		f.advance(1); for _ = 1, 120 do f.step() end
		assert(other.support.Transform == Frame.identity)
		f.remote.OnClientEvent:Fire(2, other.character, "one", 3, 0.1, 0, true, false, 100)
		for _ = 1, 60 do f.step() end; assert(other.support.Transform == Frame.identity)
	end)
	test("rapid re-aims do not accumulate FOV/offset or leak update connections", function()
		local f = fixture(); local aim = load("Camera", f.env)
		for _ = 1, 50 do
			assert(aim.Start(f.tool, Config.Default.Aim, function() return true end)); f.advance(0.02)
			aim.Stop(); f.advance(0.02)
		end
		aim.Stop(true); near(f.camera.FieldOfView, 70); near(f.humanoid.CameraOffset.Magnitude, 0)
		assert(not next(f.bindings) and f.events.PreSimulation.Count() == 0)
	end)
	test("round/menu restrictions, unequip, death and camera replacement release aim", function()
		for _, reason in ipairs({ "disallowed", "tool", "death", "camera" }) do
			local f = fixture(); local allowed = true; local aim = load("Camera", f.env)
			assert(aim.Start(f.tool, Config.Default.Aim, function() return allowed end)); f.advance(0.05)
			if reason == "disallowed" then allowed = false
			elseif reason == "tool" then f.tool.Parent = nil
			elseif reason == "death" then f.humanoid.Health = 0
			else f.env.workspace.CurrentCamera = {} end
			f.advance(0.05); assert(not aim.IsAiming() and f.humanoid.AutoRotate and f.input.MouseBehavior == "Default")
			aim.Stop(true); assert(not next(f.bindings))
		end
	end)
	test("camera takeover retains externally changed FOV/offset", function()
		local f = fixture(); local aim = load("Camera", f.env)
		aim.Start(f.tool, Config.Default.Aim, function() return true end); f.advance(0.05)
		f.camera.FieldOfView, f.humanoid.CameraOffset = 80, V(2, 0, 0)
		f.advance(0.05); near(f.camera.FieldOfView, 80); near(f.humanoid.CameraOffset.X, 2)
		assert(not aim.IsAiming() and not next(f.bindings))
	end)
	test("engine FOV rounding does not cancel aim or prevent restoration", function()
		local f = fixture(); local values = f.camera
		f.camera = setmetatable({}, { __index = values, __newindex = function(_, key, value)
			values[key] = key == "FieldOfView" and math.floor(value * 10000) / 10000 or value
		end })
		f.env.workspace.CurrentCamera = f.camera
		local aim = load("Camera", f.env); aim.Start(f.tool, Config.Default.Aim, function() return true end)
		for _ = 1, 30 do f.advance(1 / 60) end
		assert(aim.IsAiming()); aim.Stop(true); near(f.camera.FieldOfView, 70)
	end)
	test("body turning follows the shortest path across the yaw seam", function()
		local f = fixture(); local aim = load("Camera", f.env)
		f.root.CFrame = Frame.Angles(0, math.rad(179), 0)
		f.camera.CFrame = Frame.new(0, 0, 10) * Frame.Angles(0, math.rad(-179), 0)
		aim.Start(f.tool, Config.Default.Aim, function() return true end)
		f.events.PreSimulation:Fire(1 / 60)
		local look = f.root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		assert(Math.WrapAngle(yaw - math.rad(179)) > 0 and Math.WrapAngle(yaw - math.rad(179)) < math.rad(2))
		aim.Stop(true)
	end)
	test("an authored reload releases the aim layer and death restores animation", function()
		local f = fixture(false); local pose = load("Pose", f.env); pose.Init(f.remote)
		Config.Overrides["Amber Revolver"] = { Effects = { ReloadAnimationId = "rbxassetid://test" } }
		pose.SetLocalAim(f.tool, V(0, 10, -40), false); for _ = 1, 60 do f.step() end
		pose.SetLocalAim(f.tool, V(0, 10, -40), true); for _ = 1, 120 do f.step() end
		assert(f.joint.Transform == Frame.identity)
		pose.SetLocalAim(f.tool, V(0, 10, -40), false); f.step()
		f.character:FindFirstChildOfClass("Humanoid").Health = 0
		for _ = 1, 120 do f.step() end; assert(f.joint.Transform == Frame.identity)
		Config.Overrides["Amber Revolver"] = nil
	end)
	test("missing aim updates expire instead of leaving an arm frozen", function()
		local f = fixture(false); local pose = load("Pose", f.env); pose.Init(f.remote)
		pose.SetLocalAim(f.tool, V(0, 10, -40), false)
		for _ = 1, 60 do f.step() end
		assert(f.joint.Transform ~= Frame.identity)
		f.advance(1)
		for _ = 1, 120 do f.step() end
		assert(f.joint.Transform == Frame.identity)
	end)
	test("shot visuals create layered trails, flash and smoke with nonqueryable parts", function()
		local f = fixture(false); local effects = load("Effects", f.env)
		assert(f.events.RenderStepped.Count() == 0)
		local shot = effects.Fire(nil, Vector.zero, V(0, 0, -40), Config.Get("Amber Revolver"), false)
		assert(shot and shot.Parent)
		local trails, beams, particles, continuous = 0, 0, 0, 0
		for _, obj in ipairs(f.created) do
			if obj.ClassName == "Part" then assert(obj.CanQuery == false and obj.CanCollide == false and obj.CanTouch == false) end
			if obj.ClassName == "Trail" then trails += 1 end
			if obj.ClassName == "Beam" then beams += 1 end
			if obj.ClassName == "ParticleEmitter" then particles += obj.emitted or 0; continuous += obj.Rate end
		end
		assert(trails == 2 and beams == 2 and particles == 13 and continuous == 0)
		f.advance(0.03); assert(shot.Parent)
		effects.CorrectTracer(shot, V(0, 0, -20)); f.advance(0.2); assert(shot.destroyed)
		assert(f.events.RenderStepped.Count() == 0)
	end)
	test("shot beams stay straight and trail history is bounded to the same tail", function()
		local f = fixture(); local effects = load("Effects", f.env)
		local settings = Config.Default.Effects
		effects.Tracer(Vector.zero, V(0, 0, -100), settings)
		for _, item in ipairs(f.created) do
			if item:IsA("Beam") then
				assert(item.CurveSize0 == 0 and item.CurveSize1 == 0 and item.Segments == 1)
			elseif item:IsA("Trail") then assert(item.MaxLength == settings.TracerTailLength) end
		end
		effects.Clear()
	end)
	test("off-axis corrections clear the old path and synchronously place one streak at its original age", function()
		for _, hz in ipairs({30, 60, 144}) do
			local f = fixture(); local effects = load("Effects", f.env); local settings = Config.Default.Effects
			local shot = effects.Tracer(Vector.zero, V(0, 0, -100), settings)
			local tip, beam, ribbons = nil, nil, {}
			for _, item in ipairs(f.created) do
				if item.Name == "BulletGlint" then tip = item end
				if item:IsA("Beam") then beam = item end
				if item:IsA("Trail") then table.insert(ribbons, item) end
			end
			f.advance(1 / hz); local created = #f.created
			local before = {ribbons[1].cleared, ribbons[2].cleared}
			local destination = V(8, 4, -20)
			effects.CorrectTracer(shot, destination)
			local fraction = math.min(1, (1 / hz) / (settings.VisualTravelMs / 1000))
			near((tip.CFrame.Position - destination * fraction).Magnitude, 0)
			near((beam.Attachment1.Position - destination * fraction).Magnitude, 0)
			for index, ribbon in ipairs(ribbons) do assert(ribbon.cleared == before[index] + 2 and ribbon.Enabled) end
			assert(#f.created == created and f.events.RenderStepped:Count() == 1)
			f.advance(settings.VisualTravelMs / 1000 - 1 / hz + 0.001)
			near((tip.CFrame.Position - destination).Magnitude, 0)
			assert(tip.Transparency == 1 and not ribbons[1].Enabled and not ribbons[2].Enabled)
			effects.Clear()
		end
	end)
	test("late shorter and longer corrections cannot replay a finished glint or retain a second trail", function()
		for _, destination in ipairs({V(4, 2, -10), V(-20, 10, -300)}) do
			local f = fixture(); local effects = load("Effects", f.env); local settings = Config.Default.Effects
			local shot = effects.Tracer(Vector.zero, V(0, 0, -100), settings)
			local tip, ribbons = nil, {}
			for _, item in ipairs(f.created) do
				if item.Name == "BulletGlint" then tip = item end
				if item:IsA("Trail") then table.insert(ribbons, item) end
			end
			f.advance(settings.VisualTravelMs / 1000 + 0.02)
			assert(tip.Transparency == 1 and not ribbons[1].Enabled and not ribbons[2].Enabled)
			local created, cleared = #f.created, ribbons[1].cleared
			effects.CorrectTracer(shot, destination)
			near((tip.CFrame.Position - destination).Magnitude, 0)
			assert(tip.Transparency == 1 and not ribbons[1].Enabled and not ribbons[2].Enabled)
			assert(ribbons[1].cleared == cleared + 2 and #f.created == created)
			f.advance(settings.TracerLifetimeMs / 1000 - 0.02 + 0.001)
			assert(shot.destroyed and f.events.RenderStepped:Count() == 0)
		end
	end)
	test("empty trigger sound is opt-in pooled owner feedback with independent skin settings", function()
		local f = fixture(); local effects = load("Effects", f.env); local tuning = Config.Get("Amber Revolver")
		local created = #f.created
		effects.Empty(f.tool, tuning); assert(#f.created == created)
		tuning.Effects.EmptySoundId, tuning.Effects.EmptySoundVolume = "rbxassetid://123456", 0.65
		effects.Empty(f.tool, tuning)
		local sound = f.created[#f.created]
		assert(sound.Name == "RevolverEmptySound" and sound.Parent:IsA("Folder") and sound.played)
		assert(sound.SoundId == tuning.Effects.EmptySoundId and sound.Volume == 0.65)
		local count = #f.created
		tuning.Effects.EmptySoundId, tuning.Effects.EmptySoundVolume = "rbxassetid://654321", 0.4
		for _ = 1, 20 do effects.Empty(f.tool, tuning) end
		assert(#f.created == count and sound.SoundId == "rbxassetid://654321" and sound.Volume == 0.4)
		assert(sound.TimePosition == 0 and sound.PlaybackSpeed == tuning.Effects.SoundPlaybackSpeed)
		effects.Clear(); assert(sound.destroyed)
	end)
	test("impact particles require a confirmed normal and disabled tracers allocate nothing", function()
		local f = fixture(false); local effects = load("Effects", f.env)
		local count = #f.created
		effects.Impact(Vector.zero, nil, Config.Default.Effects); assert(#f.created == count)
		effects.Impact(Vector.zero, V(0, 1, 0), Config.Default.Effects); assert(#f.created > count)
		local disabled = table.clone(Config.Default.Effects); disabled.TracerEnabled = false
		count = #f.created; assert(not effects.Tracer(Vector.zero, V(0, 0, -40), disabled)); assert(#f.created == count)
		assert(not effects.Tracer(Vector.zero, Vector.zero, Config.Default.Effects))
	end)
	test("built-in muzzle bursts suppress a second authored flash on copied and world guns", function()
		for _, localShot in ipairs({true, false}) do
			local f = fixture(); local effects = load("Effects", f.env)
			local visual = object("Model", "Weapon")
			local liveMuzzle, copyMuzzle = object("Attachment", "Muzzle"), object("Attachment", "Muzzle")
			liveMuzzle.WorldPosition, copyMuzzle.WorldPosition = V(0, 2, -1), V(0.4, 1.5, -2)
			local liveEmitter, copyEmitter = object("ParticleEmitter", "LiveBurst"), object("ParticleEmitter", "CopyBurst")
			liveMuzzle.children, copyMuzzle.children = {liveEmitter}, {copyEmitter}
			f.tool.children, visual.children = {liveMuzzle}, {copyMuzzle}
			local shot = effects.Fire(f.tool, Vector.zero, V(0, 2, -20), Config.Get(f.tool.Name), localShot, visual)
			assert(shot)
			assert(not copyEmitter.emitted and not liveEmitter.emitted)
			local bursts = 0
			for _, item in ipairs(f.created) do if item.Name == "RevolverMuzzleBurst" then bursts += 1 end end
			assert(bursts == 1)
			local sounds = 0
			for _, item in ipairs(f.created) do if item.ClassName == "Sound" and item.played then sounds += 1 end end
			assert(sounds == 1)
			effects.Clear()
		end
	end)
	test("first-person bursts and tracers use the camera muzzle even when the animated head is far away", function()
		local f = fixture(); local effects = load("Effects", f.env)
		local visual, muzzle = object("Model", "Weapon"), object("Attachment", "Muzzle")
		muzzle.WorldPosition = V(20, 1, -2); visual.children = {muzzle}
		local shot = effects.Fire(f.tool, Vector.zero, V(20, 1, -40), Config.Get(f.tool.Name), true, visual)
		assert(shot)
		local burst, path
		for _, item in ipairs(f.created) do
			if item.Name == "RevolverMuzzleBurst" then burst = item end
			if item.Name == "Path" then path = item end
		end
		assert(burst and path)
		local expected = Raycast.GetVisualMuzzleFrame(visual, Config.Get(f.tool.Name)).Position
		near((burst.CFrame.Position - expected).Magnitude, 0)
		near((path.CFrame.Position - expected).Magnitude, 0)
		effects.Clear()
	end)
	test("fallback barrel origin rises and advances in the rotated Handle's local space", function()
		local f = fixture(); local tuning = Config.Get(f.tool.Name)
		local handle = object("Part", "Handle"); handle.Parent = f.tool; f.tool.children = {handle}
		handle.CFrame = Frame.new(0.4, 1.1, -0.6) * Frame.Angles(0.7, -0.8, 0.2)
		local previous = handle.CFrame:PointToWorldSpace(V(0, 0, -0.5))
		local expected = previous + handle.CFrame:VectorToWorldSpace(V(0, 0.18, -0.2))
		local cosmetic = Raycast.GetMuzzlePosition(f.tool, tuning)
		local physical = Raycast.GetMuzzle(f.tool, f.character:FindFirstChild("Head"), tuning, Config.Security.MaxMuzzleDistance)
		near((cosmetic - expected).Magnitude, 0); near((physical - cosmetic).Magnitude, 0)
		assert((cosmetic - previous).Magnitude < 0.3, "The fallback adjustment must remain small")
	end)
	test("authored muzzle attachments and parts retain their exact origin ahead of the fallback", function()
		for _, class in ipairs({"Attachment", "Part"}) do
			local f = fixture(); local tuning = Config.Get(f.tool.Name)
			tuning.MuzzleOffset = {0, 4, -4}
			local handle, muzzle = object("Part", "Handle"), object(class, tuning.MuzzleAttachmentName)
			handle.CFrame, handle.Parent = Frame.new(0.5, 1.2, -0.4), f.tool
			muzzle.Parent = handle
			if class == "Attachment" then muzzle.CFrame = Frame.new(0.1, 0.3, -1.2)
			else muzzle.Position = V(0.6, 1.5, -1.6) end
			f.tool.children = {handle, muzzle}
			local expected = class == "Attachment" and muzzle.WorldPosition or muzzle.Position
			local origin, authored = Raycast.GetMuzzlePosition(f.tool, tuning)
			assert(authored == muzzle); near((origin - expected).Magnitude, 0)
			near((Raycast.GetMuzzle(f.tool, f.character:FindFirstChild("Head"), tuning, 7) - expected).Magnitude, 0)
		end
	end)
	test("per-skin muzzle names and fallback offsets remain authoritative", function()
		local f = fixture(); local previous = Config.Overrides[f.tool.Name]
		Config.Overrides[f.tool.Name] = {MuzzleAttachmentName = "BarrelTip", MuzzleOffset = {0.1, 0.35, -0.9}}
		local tuning = Config.Get(f.tool.Name); Config.Overrides[f.tool.Name] = previous
		local handle = object("Part", "Handle"); handle.CFrame = Frame.new(0, 1, 0); handle.Parent = f.tool
		f.tool.children = {handle}
		near((Raycast.GetMuzzlePosition(f.tool, tuning) - V(0.1, 1.35, -0.9)).Magnitude, 0)
		local muzzle = object("Attachment", "BarrelTip"); muzzle.CFrame, muzzle.Parent = Frame.new(0, 0.2, -1.1), handle
		table.insert(f.tool.children, muzzle)
		near((Raycast.GetMuzzlePosition(f.tool, tuning) - muzzle.WorldPosition).Magnitude, 0)
	end)
	test("invalid or distant muzzle geometry keeps the protected server and observer origin", function()
		for _, position in ipairs({V(0, 2, -100), V(0/0, 2, -1), V(math.huge, 2, -1)}) do
			local f = fixture(); local tuning = Config.Get(f.tool.Name)
			local head = f.character:FindFirstChild("Head")
			local muzzle = object("Attachment", "Muzzle"); muzzle.WorldPosition = position; f.tool.children = {muzzle}
			local physical = Raycast.GetMuzzle(f.tool, head, tuning, Config.Security.MaxMuzzleDistance)
			near((physical - head.Position).Magnitude, 0)
			local effects = load("Effects", f.env)
			effects.Fire(f.tool, physical, V(0, 2, -20), tuning, false)
			for _, item in ipairs(f.created) do
				if item.Name == "RevolverMuzzleBurst" or item.Name == "Path" then
					near((item.CFrame.Position - physical).Magnitude, 0)
				end
			end
			effects.Clear()
		end
	end)
	test("observer muzzle flash and streak use the exact accepted origin despite replicated barrel offsets", function()
		local f = fixture(); local tuning = Config.Get(f.tool.Name)
		local handle = object("Part", "Handle"); handle.CFrame, handle.Parent = Frame.new(0.7, 1.2, -0.4), f.tool
		f.tool.children = {handle}
		local physical = Raycast.GetMuzzle(f.tool, f.character:FindFirstChild("Head"), tuning, 7)
		local expected = V(0, 2, 0)
		assert((Raycast.GetVisualMuzzleFrame(f.tool, tuning).Position - physical).Magnitude > 0.1)
		local effects = load("Effects", f.env); effects.Fire(f.tool, expected, V(0, 2, -20), tuning, false)
		local found = 0
		for _, item in ipairs(f.created) do
			if item.Name == "RevolverMuzzleBurst" or item.Name == "Path" then
				found += 1; near((item.CFrame.Position - expected).Magnitude, 0)
			end
		end
		assert(found == 2); effects.Clear()
	end)
	test("visual muzzle overrides apply to authored sockets without changing the authoritative origin", function()
		local f = fixture(); local tuning = Config.Get(f.tool.Name)
		local handle, muzzle = object("Part", "Handle"), object("Attachment", "Muzzle")
		handle.CFrame, handle.Parent = Frame.new(0.5, 1, 0) * Frame.Angles(0.1, -0.3, 0.2), f.tool
		muzzle.Parent, muzzle.CFrame = handle, Frame.new(0, 0.2, -0.5) * Frame.Angles(0.4, 0.5, 0.6)
		f.tool.children = {handle, muzzle}
		local physical = Raycast.GetMuzzle(f.tool, f.character:FindFirstChild("Head"), tuning, 7)
		tuning.Effects.MuzzleVisualRight, tuning.Effects.MuzzleVisualUp, tuning.Effects.MuzzleVisualForward = 0.1, 0.4, 0.7
		local visual = Raycast.GetVisualMuzzleFrame(f.tool, tuning)
		near((visual.Position - muzzle.WorldCFrame:PointToWorldSpace(V(0.1, 0.4, -0.7))).Magnitude, 0)
		near((Raycast.GetMuzzle(f.tool, f.character:FindFirstChild("Head"), tuning, 7) - physical).Magnitude, 0)
	end)
	test("two-ray resolution identifies world miss surfaces while victim hits have no mark surface", function()
		local wall = object("Part", "Wall"); local tuning = Config.Get("Amber Revolver")
		local function cast(_, vector) return {Distance = math.min(8, vector.Magnitude), Normal = V(0, 0, 1), Instance = wall} end
		local miss = Raycast.Resolve(Vector.zero, V(0, 0, -1), Vector.zero, tuning, {}, cast)
		assert(miss.surface == wall and miss.normal and not miss.victim)
		local target = {frame = Frame.new(0, 0, -5)}
		local hit = Raycast.Resolve(Vector.zero, V(0, 0, -1), Vector.zero, tuning, {target}, cast)
		assert(hit.victim == target and not hit.surface and not hit.normal)
	end)

	local function holeFixture(texture)
		local f = fixture(); f.holeSettings = Config.Get(f.tool.Name).Effects
		f.holeSettings.ImpactEnabled = false
		if texture then f.holeSettings.BulletHoleTextureId = texture end
		f.wall = object("Part", "Wall"); f.wall.Parent, f.wall.CFrame = f.env.workspace, Frame.identity
		f.effects = load("Effects", f.env)
		function f.mark(position, normal, surface)
			return f.effects.BulletHole(position or V(0, 2, -10), normal or V(0, 0, 1), surface or f.wall, f.holeSettings)
		end
		function f.countHoles()
			local count = 0; for _, item in ipairs(f.created) do if item.Name == "RevolverBulletHole" then count += 1 end end; return count
		end
		function f.holeGui(part)
			for _, item in ipairs(f.created) do if item.Name == "BulletHoleSurface" and item.Parent == part then return item end end
		end
		return f
	end
	test("bullet marks align with wall floor and ceiling normals and retain a surface separation", function()
		for _, normal in ipairs({V(0, 0, 1), V(0, 1, 0), V(0, -1, 0), V(0.6, 0.8, 0)}) do
			local f = holeFixture(); local position = V(2, 3, -10); local part = f.mark(position, normal)
			assert(part and part.CanQuery == false and part.CanCollide == false and not part.CastShadow)
			near((part.CFrame.Position - position):Dot(normal), f.holeSettings.BulletHoleSurfaceOffset)
			near(part.CFrame.LookVector:Dot(normal), 1)
			local gui = f.holeGui(part); assert(gui and not gui.AlwaysOnTop and gui.Enabled)
			f.effects.Clear(); assert(part.destroyed and f.events.RenderStepped:Count() == 0)
		end
	end)
	test("bullet marks reject air avatars invalid normals and distant surfaces before allocating", function()
		local f = holeFixture(); local count = #f.created
		for _, normal in ipairs({V(0, 0, 0), V(0/0, 0, 1), V(math.huge, 0, 1), V(0, 9, 0)}) do assert(not f.mark(nil, normal)) end
		assert(not f.mark(V(0/0, 0, 0)))
		assert(not f.mark(V(2000, 0, 0)))
		f.effects.Impact(V(0, 2, -10), V(0, 0, 1), f.holeSettings, nil, false)
		f.effects.Impact(V(0, 2, -10), V(0, 0, 1), f.holeSettings, f.wall, true)
		assert(not f.mark(nil, nil, f.character:FindFirstChild("Head")))
		assert(#f.created == count and f.events.RenderStepped:Count() == 0)
	end)
	test("bullet mark texture overrides replace the immediately available drawn puncture", function()
		for _, texture in ipairs({"", "rbxassetid://test-image"}) do
			local f = holeFixture(texture); local part = f.mark(); local gui = f.holeGui(part)
			local image, fallback
			for _, item in ipairs(f.created) do
				if item.Parent == gui and item.Name == "Texture" then image = item end
				if item.Parent == gui and item.Name == "DrawnPuncture" then fallback = item end
			end
			assert(image.Image == texture and image.Visible == (texture ~= "") and fallback.Visible == (texture == ""))
			f.effects.Clear()
		end
	end)
	test("bullet mark pool grows one miss at a time then reuses its bounded slots and expires its update", function()
		local f = holeFixture(); local first = f.mark(); assert(f.countHoles() == 1)
		for _ = 2, Config.Presentation.MaxBulletHoles do f.mark() end
		local allocated = #f.created
		for _ = 1, 200 do f.mark() end
		assert(#f.created == allocated and f.countHoles() == Config.Presentation.MaxBulletHoles)
		assert(f.events.RenderStepped:Count() == 1)
		f.advance(7.5)
		for _, item in ipairs(f.created) do if item.Name == "Texture" then near(item.ImageTransparency, 0.5) end end
		f.advance(0.6); assert(f.events.RenderStepped:Count() == 0)
		for _, item in ipairs(f.created) do if item.Name == "BulletHoleSurface" then assert(not item.Enabled) end end
		f.mark(); assert(#f.created == allocated and f.events.RenderStepped:Count() == 1)
		f.effects.Clear(); assert(first.destroyed and f.events.RenderStepped:Count() == 0)
	end)
	test("bullet marks follow moving parts hide near the camera and clear removed surfaces", function()
		local f = holeFixture(); local position = V(0, 2, -10); local part = f.mark(position); local gui = f.holeGui(part)
		local original = part.CFrame
		f.wall.CFrame = Frame.new(2, 3, 4) * Frame.Angles(0.2, 0.3, 0.4); f.advance(0.02)
		near((part.CFrame.Position - f.wall.CFrame:PointToWorldSpace(original.Position)).Magnitude, 0)
		f.camera.CFrame = Frame.new(part.CFrame.Position); f.advance(0.02); assert(not gui.Enabled)
		f.camera.CFrame = Frame.new(0, 0, 10); f.advance(0.02); assert(gui.Enabled)
		f.wall.Parent = nil; f.advance(0.02); assert(not gui.Enabled and f.events.RenderStepped:Count() == 0)
		f.effects.Clear()
	end)
	test("stationary bullet marks avoid redundant appearance and transform writes until fading", function()
		local f = holeFixture(); local part = f.mark(); local gui = f.holeGui(part)
		local writes = 0
		local function watch(item, key)
			local mt, stored = table.clone(getmetatable(item) or {}), item[key]
			local oldIndex, oldNewIndex = mt.__index, mt.__newindex
			rawset(item, key, nil)
			mt.__index = function(self, property)
				if property == key then return stored end
				if type(oldIndex) == "function" then return oldIndex(self, property) end
				return oldIndex and oldIndex[property]
			end
			mt.__newindex = function(self, property, value)
				if property == key then writes += 1; stored = value
				elseif oldNewIndex then oldNewIndex(self, property, value)
				else rawset(self, property, value) end
			end
			setmetatable(item, mt)
		end
		watch(part, "CFrame"); watch(gui, "Enabled")
		for _, item in ipairs(f.created) do
			if item.Name == "Texture" then watch(item, "ImageTransparency") end
			if item.Name == "Puncture" or item.Name:match("^Crack") then watch(item, "BackgroundTransparency") end
		end
		for _ = 1, 144 do f.advance(1/144) end
		assert(writes == 0)
		f.advance(6.5); assert(writes > 0)
		f.effects.Clear()
	end)
	test("cancelled predictions and character cleanup remove tracer state", function()
		local f = fixture(false); local effects = load("Effects", f.env)
		local shot = effects.Tracer(Vector.zero, V(0, 0, -40), Config.Default.Effects)
		shot:Destroy(); f.advance(0.01); effects.CorrectTracer(shot, V(0, 0, -20))
		local nextShot = effects.Tracer(Vector.zero, V(0, 0, -40), Config.Default.Effects)
		effects.Clear(); assert(nextShot.destroyed); f.advance(0.01)
		assert(f.events.RenderStepped.Count() == 0)
	end)
	test("tracer render budget is bounded and distant effects are culled", function()
		local f = fixture(); local effects = load("Effects", f.env)
		local first = effects.Tracer(Vector.zero, V(0, 0, -40), Config.Default.Effects)
		f.advance(0.0001)
		for _ = 1, Config.Presentation.MaxActiveTracers do effects.Tracer(Vector.zero, V(0, 0, -40), Config.Default.Effects); f.advance(0.0001) end
		assert(first.destroyed and f.events.RenderStepped.Count() == 1)
		effects.Clear(); assert(f.events.RenderStepped.Count() == 0)
		local count = #f.created
		effects.Fire(nil, V(2000, 0, 0), V(2000, 0, -40), Config.Get("Amber Revolver"), false)
		effects.Impact(V(2000, 0, 0), V(0, 1, 0), Config.Default.Effects)
		assert(#f.created == count)
	end)
	test("distant glints grow within their width cap without adding particles", function()
		local f = fixture(); local effects = load("Effects", f.env)
		effects.Tracer(Vector.zero, V(0, 0, -350), Config.Default.Effects); f.advance(0.05)
		local tip
		for _, obj in ipairs(f.created) do if obj.Name == "BulletGlint" then tip = obj end end
		assert(tip.Size.X > Config.Default.Effects.TracerThickness and tip.Size.X <= Config.Default.Effects.TracerMaxThickness)
		effects.Clear()
	end)

	local function controllerFixture()
		local f = fixture()
		f.config = load("Config")
		local playerGui = object("PlayerGui", "PlayerGui")
		local leaderstats, binds = object("Folder", "leaderstats"), object("Folder", "KeyBinds")
		f.reloadBind = object("StringValue", "Reload"); f.reloadBind.Value, f.reloadBind.Changed = "R", signal()
		binds.children, leaderstats.children = {f.reloadBind}, {binds}
		function f.player:FindFirstChildOfClass(name) return name == "PlayerGui" and playerGui end
		function f.player:WaitForChild(name) return name == "PlayerGui" and playerGui or name == "leaderstats" and leaderstats end
		f.player.attributes = { DataReady = true, InRound = true }
		function f.player:GetAttribute(name) return self.attributes[name] end
		function f.player:GetAttributeChangedSignal() return signal() end
		local active = object("BoolValue", "GameActive"); active.Value, active.Changed = true, signal()
		local remotes, folder = object("Folder", "Remotes"), object("Folder", "Revolver")
		local action, snapshot, shot = object("RemoteEvent", "Action"), object("RemoteEvent", "State"), object("RemoteEvent", "Shot")
		action.sent = {}; function action:FireServer(...) table.insert(self.sent, { ... }) end
		snapshot.OnClientEvent, shot.OnClientEvent = signal(), signal()
		local poseRemote = object("UnreliableRemoteEvent", "Aim")
		folder.children = { action, snapshot, shot, poseRemote }; remotes.children = { folder }
		f.services.ReplicatedStorage.children = { remotes, active }
		f.services.ReplicatedStorage.WaitForChild = function(self, name) for _, child in ipairs(self.children) do if child.Name == name then return child end end; error(name) end
		f.camera.ViewportSize = V(1000, 600, 0)
		f.camera.ViewportPointToRay = function(_, x, y)
			f.lastRay = { X = x, Y = y }; return { Origin = V(0, 2, 10), Direction = V(0, 0, -1) }
		end
		f.env.workspace.Raycast = function() return nil end
		f.env.Enum.UserInputType = {}
		for _, name in ipairs({ "MouseButton1", "MouseButton2", "Touch", "Keyboard", "Gamepad1" }) do f.env.Enum.UserInputType[name] = { Name = name } end
		f.env.Enum.KeyCode = {}
		for _, name in ipairs({"W","A","S","D","Space","Tab","Slash","Escape","Backspace","Return","KeypadEnter","I","O","F","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","LeftMeta","RightMeta","Unknown","ButtonR2","ButtonL2","ButtonX","E","G","LeftShift","LeftControl","C","One","Two","Three","Q","R","T","X","Y","H","J","K","L","U","B"}) do f.env.Enum.KeyCode[name] = {Name = name} end
		function f.env.Enum.KeyCode:GetEnumItems()
			local values = {}; for _, item in pairs(self) do if type(item) == "table" then table.insert(values, item) end end; return values
		end
		local validation = load("KeybindValidation", f.env)
		f.services.ReplicatedStorage.Modules.KeybindValidation = "KeybindValidation"
		local aim = load("Camera", f.env)
		local pose = { Init = function() end, SetLocalAim = function(tool) f.poseCleared = tool == nil end,
			Kick = function() end, ResetLocal = function() end, SetSession = function() end,
			SampleCursor = function(...) f.lastSample = { ... }; f.poseCleared = false end,
			GetLocalAnimation = function() return f.bodyAnimation, f.armAnimation end }
		local effects = { Equip = function() f.equipEffects = (f.equipEffects or 0) + 1 end,
			SetFirstPerson = function(tool) f.preparedShotTool = tool end,
			GetShotOrigin = function(_, origin) return f.cosmeticOrigin or origin end,
			Fire = function(...) f.fireEffects = (f.fireEffects or 0) + 1; f.fireEffectArgs = {...}; return f.tracer end,
			ConfirmedTracer = function(...) f.confirmedTracers = (f.confirmedTracers or 0) + 1; f.confirmedArgs = {...}; return f.tracer end,
			Empty = function(...) f.emptyEffects = (f.emptyEffects or 0) + 1; f.emptyEffectArgs = {...} end,
			CorrectTracer = function(...) f.corrections = (f.corrections or 0) + 1; f.correctionArgs = {...} end,
			Impact = function(...) f.impacts = (f.impacts or 0) + 1; f.impactArgs = {...} end,
			Reload = function() f.reloadEffects = (f.reloadEffects or 0) + 1 end, StopReload = function() end, Clear = function() end }
		local viewmodel = {Clear = function() f.viewClears = (f.viewClears or 0) + 1 end,
			InterruptInspect = function() f.inspectInterrupts = (f.inspectInterrupts or 0) + 1 end,
			Update = function(...) f.viewUpdate = {...} end, Kick = function(tool) f.viewKick = tool end,
			GetVisualTool = function() return f.visualTool end, IsFirstPerson = function() return f.firstPerson == true end}
		f.env.script = { Parent = { HitFeedback = "Feedback", RevolverEffects = "Effects", RevolverAimPose = "Pose", RevolverAimCamera = "Camera", RevolverViewmodel = "Viewmodel" } }
		local dependencies = { Config = f.config, KeybindValidation = validation, Math = Math, Catalog = { ["Amber Revolver"] = {} }, Camera = aim, Pose = pose, Effects = effects,
			RagdollQuery = queryStub, Viewmodel = viewmodel, ToolPhysics = ToolPhysics,
			Feedback = {SetAimPosition = function(position) f.feedbackPosition = position end},
			CursorConfig = {WhiteDotSize = 5, WhiteDotEnabled = true},
			Raycast = { GetCharacterGeometry = function(character)
					if f.actualRaycast then return Raycast.GetCharacterGeometry(character) end
					return {}
				end,
				GetVisualShotOrigin = Raycast.GetVisualShotOrigin,
				GetMuzzle = function(_, h)
					f.muzzleReads = (f.muzzleReads or 0) + 1
					return f.physicalOrigin or h.Position
				end,
				Resolve = function(...)
					if f.actualRaycast then return Raycast.Resolve(...) end
					return { position = V(0, 2, -20) }
				end } }
		f.env.require = function(name) return assert(dependencies[name], name) end
		f.controller, f.aim, f.action, f.active, f.shot, f.state = load("Controller", f.env), aim, action, active, shot, snapshot
		f.controller.Init()
		f.hud, f.ammoLabel = f.created[1], f.created[2]
		for _, obj in ipairs(f.created) do
			if obj.Text == "SHOOT" then f.shootButton = obj
			elseif obj.Text == "RELOAD" then f.reloadButton = obj
			elseif obj.Text == "AIM" then f.aimButton = obj end
		end
		function f.snapshot(ammo, reload, ack, reason)
			snapshot.OnClientEvent:Fire({ Character = f.character, Session = "session", Revision = (f.revision or 0) + 1,
				AckSequence = ack or 0, Ammo = ammo, ReloadEnd = reload or 0, NextShot = 0, Reason = reason })
			f.revision = (f.revision or 0) + 1
		end
		function f.inputObject(kind, key) return { UserInputType = f.env.Enum.UserInputType[kind], KeyCode = f.env.Enum.KeyCode[key or "Unknown"] } end
		return f
	end
	test("accepted owner shots reconcile once without duplicate fire flash or sound", function()
		local f = controllerFixture(); f.snapshot(3); f.tracer = {Parent = true}
		assert(f.controller.Fire()); local request = f.action.sent[#f.action.sent]
		local accepted = {ShooterId = f.player.UserId, Session = "session", Sequence = request[3],
			Weapon = f.tool.Name, Origin = Vector.zero, Position = V(5, 2, -30), Normal = V(0, 0, 1), Hit = false}
		for _ = 1, 4 do f.shot.OnClientEvent:Fire(accepted) end
		assert(f.fireEffects == 1 and not f.corrections and f.confirmedTracers == 1 and f.impacts == 1)
		assert(f.fireEffectArgs[9] == true and f.confirmedArgs[2] == accepted.Position)
	end)
	test("a delayed blocked shot starts only one confirmed streak and cannot use a muzzle beyond the wall", function()
		local f = controllerFixture(); f.snapshot(3)
		f.cosmeticOrigin = V(0, 2, -4)
		assert(f.controller.Fire() and not f.confirmedTracers and not f.impacts)
		assert(f.fireEffectArgs[9] == true)
		f.advance(0.7)
		assert(not f.confirmedTracers and not f.impacts)
		f.snapshot(2, nil, 1, "Fired")
		local accepted = {ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -2), Normal = V(0, 0, 1), Hit = false}
		for _ = 1, 3 do f.shot.OnClientEvent:Fire(accepted) end
		assert(f.confirmedTracers == 1 and f.fireEffects == 1 and f.impacts == 1 and not f.corrections)
		near((f.confirmedArgs[1] - accepted.Origin).Magnitude, 0)
		near((f.confirmedArgs[2] - accepted.Position).Magnitude, 0)
	end)
	test("confirmed cover replaces an unsafe cosmetic path with the accepted physical origin", function()
		local f = controllerFixture(); f.snapshot(3); f.cosmeticOrigin = V(2, 2, -1)
		assert(f.controller.Fire())
		local physical = V(0, 2, 0)
		f.env.workspace.Raycast = function(_, origin, vector)
			local length = vector.Magnitude
			if length < 0.001 then return nil end
			local distance = RayMath.RayBoxDistance(origin, vector.Unit, Frame.new(1.6, 2, -5), {0.5, 4, 0.5}, length)
			return distance and {Distance = distance, Normal = V(0, 0, 1)} or nil
		end
		f.shot.OnClientEvent:Fire({ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = physical, Position = V(0, 2, -20), Normal = nil, Hit = false})
		assert(f.confirmedTracers == 1)
		near((f.confirmedArgs[1] - physical).Magnitude, 0)
	end)
	test("cover moving into a confirmed path suppresses stale owner and observer flight without a second endpoint", function()
		local f = controllerFixture(); f.snapshot(3); assert(f.controller.Fire())
		f.env.workspace.Raycast = function(_, _, vector)
			return vector.Magnitude > 10 and {Distance = 10, Normal = V(0, 0, 1)} or nil
		end
		local data = {ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -20), Normal = V(0, 0, 1)}
		f.shot.OnClientEvent:Fire(data)
		assert(not f.confirmedTracers and f.fireEffects == 1 and f.impacts == 1)
		near((f.impactArgs[1] - data.Position).Magnitude, 0)
		data.ShooterId, data.Session = 2, "observer-session"
		f.shot.OnClientEvent:Fire(data)
		assert(f.fireEffects == 2 and f.fireEffectArgs[9] == true and f.impacts == 2)
		near((f.fireEffectArgs[2] - data.Origin).Magnitude, 0)
		near((f.fireEffectArgs[3] - data.Position).Magnitude, 0)
	end)
	test("rejected state removes only its shot while earlier accepted replies still create one streak", function()
		local f = controllerFixture(); f.snapshot(3); assert(f.controller.Fire())
		f.snapshot(2, nil, 1, "Fired")
		f.advance(0.4); assert(f.controller.Fire())
		f.snapshot(2, nil, 2, "InvalidAim")
		local accepted = {ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -6), Normal = V(0, 0, 1)}
		f.shot.OnClientEvent:Fire(accepted)
		assert(f.confirmedTracers == 1 and f.fireEffects == 2)
		accepted.Sequence = 2; f.shot.OnClientEvent:Fire(accepted)
		assert(f.confirmedTracers == 1)
	end)
	test("a world target between camera and avatar is fired at and resolved against head-side cover", function()
		local f = controllerFixture(); f.snapshot(3); f.actualRaycast = true
		f.env.workspace.Raycast = function(_, origin, vector)
			local length = vector.Magnitude; if length < 0.001 then return nil end
			local distance = RayMath.RayBoxDistance(origin, vector.Unit, Frame.new(0, 2, 4), {4, 4, 1}, length)
			return distance and {Distance = distance, Normal = V(0, 0, -1)} or nil
		end
		local requests = #f.action.sent
		assert(f.controller.Fire() and #f.action.sent == requests + 1 and f.fireEffects == 1 and not f.confirmedTracers)
		near(f.fireEffectArgs[3].Z, 3.5)
		assert(f.action.sent[#f.action.sent][3] == 1)
	end)
	test("third-person client can shoot a rear player inside the camera-to-avatar span", function()
		for _, aiming in ipairs({false, true}) do
			local f = controllerFixture(); f.snapshot(3); f.actualRaycast = true
			local other, character = object("Player", "Other"), object("Model", "RearPlayer")
			other.Character = character; function other:GetAttribute(name) return name == "InRound" end
			local root, head, humanoid = object("Part", "HumanoidRootPart"), object("Part", "Head"), object("Humanoid", "Humanoid")
			root.Parent, root.Position, root.CFrame, root.Size = character, V(0, 0, 4), Frame.new(0, 0, 4), V(2, 2, 1)
			head.Parent, head.Position, head.CFrame, head.Size = character, V(0, 2, 4), Frame.new(0, 2, 4), V(2, 1, 1)
			humanoid.Parent, humanoid.Health = character, 100
			character.children = {root, head, humanoid}
			f.services.Players.GetPlayers = function() return {f.player, other} end
			if aiming then assert(f.controller.SetAiming(true)) end
			assert(f.controller.Fire() and f.fireEffects == 1 and not f.muzzleReads)
			near((f.fireEffectArgs[2] - V(0, 2, 0)).Magnitude, 0)
			near(f.fireEffectArgs[3].Z, 3.5)
			assert(f.action.sent[#f.action.sent][1] == "Fire" and not f.confirmedTracers)
		end
	end)
	test("an advanced decorative barrel cannot flip the shot backwards or skip a nearby cursor blocker", function()
		local f = controllerFixture(); f.snapshot(3); f.actualRaycast = true
		f.physicalOrigin, f.cosmeticOrigin = V(1, 2, -2), V(1, 2, -2)
		f.env.workspace.Raycast = function(_, origin, vector)
			local length = vector.Magnitude; if length < 0.001 then return nil end
			local distance = RayMath.RayBoxDistance(origin, vector.Unit, Frame.new(0, 2, -1), {0.2, 0.2, 0.2}, length)
			return distance and {Distance = distance, Normal = V(0, 0, 1)} or nil
		end
		assert(f.controller.Fire() and not f.muzzleReads)
		near((f.fireEffectArgs[2] - V(0, 2, 0)).Magnitude, 0)
		near((f.fireEffectArgs[10] - V(0, 2, 0)).Magnitude, 0)
		near(f.fireEffectArgs[3].Z, -0.9)
		assert(f.action.sent[#f.action.sent][3] == 1 and f.fireEffectArgs[9] == true)
	end)
	test("lowered and rotated gun movement cannot block a clear cursor over a ledge in hip fire or first person", function()
		for _, firstPerson in ipairs({false, true}) do
			local f = controllerFixture(); f.snapshot(3); f.actualRaycast, f.firstPerson = true, firstPerson
			local head = V(0, 2, 0)
			f.camera.ViewportPointToRay = function() return {Origin = firstPerson and head or V(0, 2, 8), Direction = V(0, 0, -1)} end
			local ledge = worldBoxes({{position = V(0, 0.75, -2), size = {4, 1.5, 0.5}}})
			f.env.workspace.Raycast = function(_, origin, vector) return ledge(origin, vector) end
			local acceptedPoint
			for _, muzzle in ipairs({V(0, 0.7, -1), V(0.4, 0.3, -1.2), V(-0.4, 1, -0.8)}) do
				f.physicalOrigin, f.cosmeticOrigin = muzzle, muzzle
				assert(ledge(muzzle, V(0, 2, -350) - muzzle), "The moving barrel path must actually cross the low ledge")
				assert(f.controller.Fire() and not f.muzzleReads)
				near((f.fireEffectArgs[2] - head).Magnitude, 0)
				near((f.fireEffectArgs[10] - head).Magnitude, 0)
				local endpoint = f.fireEffectArgs[3]
				near(endpoint.Y, 2); near(endpoint.Z, -350)
				if acceptedPoint then near((endpoint - acceptedPoint).Magnitude, 0) else acceptedPoint = endpoint end
				f.advance(0.4)
			end
		end
	end)
	test("a barely embedded decorative muzzle cannot make engine-style inside-origin casts skip cover", function()
		local f = controllerFixture(); f.snapshot(3); f.actualRaycast = true
		f.physicalOrigin, f.cosmeticOrigin = V(0, 2, -1.005), V(0, 2, -1.005)
		local box, size = Frame.new(0, 2, -1.1), {4, 4, 0.2}
		f.env.workspace.Raycast = function(_, origin, vector)
			local localOrigin, length = box:PointToObjectSpace(origin), vector.Magnitude
			if math.abs(localOrigin.X) < 2 and math.abs(localOrigin.Y) < 2 and math.abs(localOrigin.Z) < 0.1 then return nil end
			if length < 0.001 then return nil end
			local distance = RayMath.RayBoxDistance(origin, vector.Unit, box, size, length)
			return distance and {Distance = distance, Normal = V(0, 0, 1)} or nil
		end
		assert(f.controller.Fire())
		near((f.fireEffectArgs[2] - V(0, 2, 0)).Magnitude, 0)
		near((f.fireEffectArgs[10] - V(0, 2, 0)).Magnitude, 0)
		near(f.fireEffectArgs[3].Z, -1)
		assert(f.fireEffectArgs[9] == true and not f.confirmedTracers)
	end)
	test("expired and previous-session owner replies cannot resurrect a traveling streak", function()
		local f = controllerFixture(); f.snapshot(3); assert(f.controller.Fire())
		f.advance(2.01)
		local data = {ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -20), Normal = V(0, 0, 1)}
		f.shot.OnClientEvent:Fire(data); assert(not f.confirmedTracers and f.impacts == 1)
		data.Session, data.Sequence = "old-session", 2
		f.shot.OnClientEvent:Fire(data); assert(not f.confirmedTracers and f.impacts == 1)
	end)
	test("empty trigger clicks are throttled and never create shots or consume ammo", function()
		local f = controllerFixture(); f.snapshot(0)
		local count = #f.action.sent
		for _ = 1, 10 do assert(not f.controller.Fire()) end
		assert(f.emptyEffects == 1 and not f.fireEffects and #f.action.sent == count)
		assert(f.emptyEffectArgs[1] == f.tool and f.emptyEffectArgs[2].Effects.EmptySoundId == "")
		f.advance(f.config.Default.Effects.EmptySoundCooldownMs / 1000 + 0.001)
		assert(not f.controller.Fire() and f.emptyEffects == 2 and #f.action.sent == count)
		f.snapshot(3); assert(f.controller.Fire() and f.fireEffects == 1)
		local request = f.action.sent[#f.action.sent]; assert(request[3] == 1)
	end)
	test("empty clicks respect reload menu lobby and shot cooldown gates", function()
		for _, block in ipairs({
			function(f) f.snapshot(0, f.env.workspace:GetServerTimeNow() + 2) end,
			function(f) f.snapshot(0); f.controller.Reload() end,
			function(f) f.snapshot(0); f.player.attributes.InRound = false end,
			function(f) f.snapshot(0); f.services.GuiService.MenuIsOpen = true end,
			function(f) f.snapshot(1); assert(f.controller.Fire()) end,
		}) do
			local f = controllerFixture(); block(f)
			assert(not f.controller.Fire() and not f.emptyEffects)
		end
	end)
	test("shoot aim and reload interrupt inspect before accepting gameplay input", function()
		local f = controllerFixture(); f.snapshot(3); f.advance(1/60)
		local count = f.inspectInterrupts or 0
		assert(f.controller.Fire()); assert(f.inspectInterrupts == count + 1 and f.action.sent[#f.action.sent][1] == "Fire")
		assert(f.controller.SetAiming(true)); assert(f.inspectInterrupts == count + 2)
		assert(f.controller.Reload()); assert(f.inspectInterrupts == count + 3 and f.action.sent[#f.action.sent][1] == "Reload")
		assert(not f.controller.Fire()); assert(f.inspectInterrupts == count + 4, "an attempted shot must also cancel inspect")
	end)
	test("reload input and HUD use the saved key and switch immediately when rebound", function()
		local f = controllerFixture(); f.snapshot(2); f.advance(1/60)
		assert(f.ammoLabel.Text:find("[R]", 1, true))
		f.reloadBind.Value = "T"; f.reloadBind.Changed:Fire("T"); f.advance(1/60)
		assert(f.ammoLabel.Text:find("[T]", 1, true))
		f.input.InputBegan:Fire(f.inputObject("Keyboard", "R"), false); assert(not f.reloadEffects)
		f.input.InputBegan:Fire(f.inputObject("Keyboard", "T"), true); assert(not f.reloadEffects)
		f.input.InputBegan:Fire(f.inputObject("Keyboard", "T"), false); assert(f.reloadEffects == 1)
		local request = f.action.sent[#f.action.sent]; assert(request[1] == "Reload")
	end)
	test("default R and gamepad reload remain available without bypassing combat gates", function()
		local f = controllerFixture(); f.snapshot(2)
		f.input.InputBegan:Fire(f.inputObject("Keyboard", "R"), false); assert(f.reloadEffects == 1)
		local pad = controllerFixture(); pad.snapshot(2)
		pad.reloadBind.Value = "T"; pad.reloadBind.Changed:Fire("T")
		pad.input.InputBegan:Fire(pad.inputObject("Gamepad1", "ButtonX"), false); assert(pad.reloadEffects == 1)
		local lobby = controllerFixture(); lobby.snapshot(2); lobby.player.attributes.InRound = false
		lobby.input.InputBegan:Fire(lobby.inputObject("Keyboard", "R"), false); assert(not lobby.reloadEffects)
	end)
	test("RMB hold starts ADS and release restores it even for processed input", function()
		local f = controllerFixture(); f.snapshot(3)
		local right = f.inputObject("MouseButton2")
		f.input.InputBegan:Fire(right, false); assert(f.aim.IsAiming())
		f.input.InputEnded:Fire(right, true); assert(not f.aim.IsAiming())
		f.input.InputBegan:Fire(right, true); assert(not f.aim.IsAiming())
		f.input.InputBegan:Fire(right, false); f.input.WindowFocusReleased:Fire(); assert(not f.aim.IsAiming())
	end)
	test("controller updates viewmodel after camera with aim reload and visibility state", function()
		local f = controllerFixture(); f.snapshot(2)
		f.bodyAnimation, f.armAnimation = Frame.new(0, -0.3, 0), Frame.Angles(0.1, 0, 0)
		f.advance(1/60)
		assert(f.bindings.RevolverHUD.priority == 203 and f.viewUpdate[1] == f.tool and f.viewUpdate[3])
		near(f.viewUpdate[6], 1/60)
		assert(f.viewUpdate[7] == f.bodyAnimation and f.viewUpdate[8] == f.armAnimation)
		assert(f.controller.SetAiming(true)); f.advance(1/60); assert(f.viewUpdate[4])
		assert(f.controller.Reload()); f.advance(1/60); assert(f.viewUpdate[5])
		f.services.GuiService.MenuIsOpen = true; f.advance(1/60); assert(not f.viewUpdate[3])
		local clears = f.viewClears
		f.tool.Parent = nil; f.character.ChildRemoved:Fire(f.tool); assert(f.viewClears > clears)
	end)
	test("client equip hardens the hidden real revolver immediately without altering avatar motion", function()
		local f = controllerFixture(); f.player.attributes.InRound = false
		local handle = object("Part", "Handle"); handle.Parent, handle.CFrame, handle.AssemblyLinearVelocity = f.tool, Frame.identity, V(1, 0, 0)
		handle.CanCollide, handle.CanTouch, handle.Massless, handle.Anchored, handle.CanQuery = true, true, false, false, true
		table.insert(f.tool.children, handle); f.tool.DescendantAdded:Fire(handle)
		assert(not handle.CanCollide and not handle.CanTouch and handle.Massless and not handle.Anchored and handle.CanQuery)
		assert(handle.CFrame == Frame.identity and handle.AssemblyLinearVelocity.X == 1)
		assert(f.root.CFrame == Frame.identity and f.humanoid.AutoRotate)
	end)
	test("viewmodel firing adds cosmetic recoil without sending a cosmetic muzzle to the server", function()
		local f = controllerFixture(); f.snapshot(3); f.advance(1/60)
		f.visualTool = {Name = "CosmeticOnly"}
		assert(f.controller.Fire())
		assert(f.viewKick == f.tool and f.fireEffects == 1 and f.fireEffectArgs[6] == f.visualTool)
		local packet = f.action.sent[#f.action.sent]
		assert(packet[1] == "Fire" and #packet == 6)
		near(packet[4].Z, 10); near(packet[5].Z, -1)
		local fires = 0; for _, data in ipairs(f.action.sent) do if data[1] == "Fire" then fires += 1 end end
		assert(fires == 1)
	end)
	test("first-person shots request camera muzzle feedback and still show confirmed impacts once", function()
		local f = controllerFixture(); f.snapshot(3); f.firstPerson = true
		assert(f.controller.Fire() and f.fireEffectArgs[7] == true)
		f.firstPerson = false -- zoom out before the server replies
		f.shot.OnClientEvent:Fire({ShooterId = f.player.UserId, Session = "session", Sequence = 1,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -20), Normal = V(0, 0, 1)})
		assert(f.impacts == 1)
		f.advance(0.4); assert(f.controller.Fire() and f.fireEffectArgs[7] == false)
		f.shot.OnClientEvent:Fire({ShooterId = f.player.UserId, Session = "session", Sequence = 2,
			Weapon = f.tool.Name, Origin = V(0, 2, 0), Position = V(0, 2, -20), Normal = V(0, 0, 1)})
		assert(f.impacts == 2)
		f.firstPerson = true
		f.shot.OnClientEvent:Fire({ShooterId = 2, Session = "other-session", Sequence = 1, Weapon = f.tool.Name, Origin = V(0, 2, 0),
			Position = V(0, 2, -20), Normal = V(0, 0, 1)})
		assert(f.impacts == 3 and f.fireEffectArgs[5] == false)
	end)
	test("accepted shot marks use the server surface and position once for owners and observers", function()
		local f = controllerFixture(); f.snapshot(3)
		assert(f.controller.Fire() and not f.impacts)
		local wall = object("Part", "ConfirmedWall")
		local data = {ShooterId = f.player.UserId, Session = "session", Sequence = 1, Weapon = f.tool.Name,
			Origin = V(0, 2, 0), Position = V(1, 3, -9), Normal = V(0, 0, 1), Surface = wall, Hit = false}
		f.shot.OnClientEvent:Fire(data)
		assert(f.impacts == 1 and f.fireEffects == 1 and f.impactArgs[4] == wall and f.impactArgs[5] == false)
		near((f.impactArgs[1] - data.Position).Magnitude, 0)
		f.shot.OnClientEvent:Fire(data); assert(f.impacts == 1 and f.fireEffects == 1)
		data.Session = "stale-session"; f.shot.OnClientEvent:Fire(data); assert(f.impacts == 1)
		data.ShooterId, data.Session = 2, "observer-session"
		data.Origin = V(0, 2, 0); f.shot.OnClientEvent:Fire(data)
		assert(f.impacts == 2 and f.fireEffects == 2 and f.fireEffectArgs[8] == true)
		f.shot.OnClientEvent:Fire(data); assert(f.impacts == 2 and f.fireEffects == 2)
		f.services.Players.PlayerRemoving:Fire({UserId = 2})
		data.Session = "new-observer-session"; f.shot.OnClientEvent:Fire(data); assert(f.impacts == 3)
	end)
	test("missing RMB release events are recovered from the real held-button state", function()
		local f = controllerFixture(); f.snapshot(3)
		f.input.InputBegan:Fire(f.inputObject("MouseButton2"), false); assert(f.aim.IsAiming())
		f.input.mousePressed = false -- no InputEnded arrives
		f.advance(0.02)
		assert(not f.aim.IsAiming() and f.input.MouseBehavior == "Default" and f.input.MouseIconEnabled)
	end)
	test("ADS shoots through screen centre while hip fire retains cursor aim", function()
		local f = controllerFixture(); f.snapshot(3)
		assert(f.controller.SetAiming(true))
		assert(f.controller.Fire(V(12, 34, 0))); assert(f.lastRay.X == 500 and f.lastRay.Y == 300)
		f.controller.SetAiming(false); f.advance(0.4)
		assert(f.controller.Fire(V(12, 34, 0))); assert(f.lastRay.X == 12 and f.lastRay.Y == 34)
		f.controller.SetAiming(false)
	end)
	test("disabled lobby aim retains round restrictions and menus/unequip still cancel ADS", function()
		local f = controllerFixture(); f.snapshot(2)
		f.config.Presentation.LobbyAimingEnabled = false
		f.player.attributes.InRound = false; assert(not f.controller.SetAiming(true))
		f.player.attributes.InRound = true; f.services.GuiService.MenuIsOpen = true; assert(not f.controller.SetAiming(true))
		f.services.GuiService.MenuIsOpen = false; assert(f.controller.SetAiming(true))
		f.tool.Parent = nil; f.character.ChildRemoved:Fire(f.tool); assert(not f.aim.IsAiming())
		f.tool.Parent = f.character; assert(f.controller.SetAiming(true))
		f.services.GuiService.MenuOpened:Fire(); assert(not f.aim.IsAiming())
		assert(f.controller.SetAiming(true)); f.active.Value = false; f.active.Changed:Fire(); assert(not f.aim.IsAiming())
	end)
	test("lobby arm tracking and ADS work without firing, reloading or combat controls", function()
		local f = controllerFixture(); f.snapshot(2)
		f.player.attributes.InRound, f.active.Value = false, false
		f.input.TouchEnabled = true
		f.advance(0.1)
		assert(f.lastSample and f.lastSample[1] == f.tool and not f.lastSample[3] and not f.lastSample[4])
		assert(f.hud.Enabled and not f.ammoLabel.Visible and not f.shootButton.Visible and not f.reloadButton.Visible and f.aimButton.Visible)
		f.input.InputBegan:Fire(f.inputObject("MouseButton2"), false); f.advance(0.1)
		assert(f.aim.IsAiming() and f.lastSample[4] and f.input.MouseBehavior == "LockCenter")
		assert(not f.controller.Fire() and not f.controller.Reload())
		assert(not f.fireEffects and not f.reloadEffects)
		for _, packet in ipairs(f.action.sent) do assert(packet[1] == "Sync", "Lobby sent a combat action") end
		f.input.mousePressed = false; f.advance(0.1)
		assert(not f.aim.IsAiming() and f.input.MouseBehavior == "Default")
	end)
	test("disabling lobby aim clears its camera/pose but keeps round presentation", function()
		local f = controllerFixture(); f.snapshot(3)
		f.player.attributes.InRound, f.active.Value = false, false
		assert(f.controller.SetAiming(true)); f.advance(0.1)
		f.config.Presentation.LobbyAimingEnabled = false; f.advance(0.1)
		assert(not f.aim.IsAiming() and not f.hud.Enabled and f.poseCleared and f.input.MouseBehavior == "Default")
		assert(not f.controller.SetAiming(true))
		f.player.attributes.InRound, f.active.Value = true, true; f.advance(0.1)
		assert(f.hud.Enabled and f.ammoLabel.Visible and f.controller.SetAiming(true))
	end)
	test("lobby presentation still requires loaded data, life, a held gun and no menu", function()
		local f = controllerFixture(); f.snapshot(3)
		f.player.attributes.InRound, f.active.Value = false, false
		f.player.attributes.DataReady = false; assert(not f.controller.SetAiming(true))
		f.player.attributes.DataReady = true; assert(f.controller.SetAiming(true))
		f.humanoid.Health = 0; f.advance(0.1); assert(not f.aim.IsAiming() and f.poseCleared)
		f.humanoid.Health = 100; assert(f.controller.SetAiming(true))
		f.services.GuiService.MenuIsOpen = true; f.advance(0.1); assert(not f.aim.IsAiming() and f.poseCleared)
		f.services.GuiService.MenuIsOpen = false; assert(f.controller.SetAiming(true))
		f.tool.Parent = nil; table.remove(f.character.children, table.find(f.character.children, f.tool))
		f.character.ChildRemoved:Fire(f.tool); f.advance(0.1)
		assert(not f.aim.IsAiming() and f.poseCleared)
		f.tool.Parent = f.character; table.insert(f.character.children, f.tool); f.player.attributes.InRound = true
		assert(not f.controller.SetAiming(true), "An inactive round must not use lobby permission")
	end)
	test("held RMB survives reload prediction, server acknowledgement and completion", function()
		local f = controllerFixture(); f.snapshot(2)
		f.input.InputBegan:Fire(f.inputObject("MouseButton2"), false); f.advance(0.1)
		assert(f.controller.Reload() and f.aim.IsAiming()); assert(not f.controller.Fire())
		f.advance(0.1); assert(f.aim.IsAiming() and f.input.MouseBehavior == "LockCenter")
		f.snapshot(2, 102, 1); f.advance(0.1)
		assert(f.aim.IsAiming() and not f.controller.Fire())
		f.snapshot(3, 0, 1); f.advance(0.1)
		assert(f.aim.IsAiming() and f.controller.Fire()); assert(f.lastRay.X == 500 and f.lastRay.Y == 300)
	end)
	test("RMB release during reload releases aim without enabling fire", function()
		local f = controllerFixture(); f.snapshot(2)
		local right = f.inputObject("MouseButton2")
		f.input.InputBegan:Fire(right, false); assert(f.controller.Reload())
		f.input.InputEnded:Fire(right, true); f.advance(0.1)
		assert(not f.aim.IsAiming() and f.input.MouseBehavior == "Default" and not f.controller.Fire())
		f.snapshot(3, 0, 1); assert(not f.aim.IsAiming())
	end)
	test("ADS can start during reload and a missed RMB release still cancels it", function()
		local f = controllerFixture(); f.snapshot(2)
		assert(f.controller.Reload()); f.snapshot(2, 102, 1)
		f.input.InputBegan:Fire(f.inputObject("MouseButton2"), false); f.advance(0.1)
		assert(f.aim.IsAiming() and not f.controller.Fire())
		f.input.mousePressed = false; f.advance(0.1)
		assert(not f.aim.IsAiming() and f.input.MouseBehavior == "Default")
	end)
	test("gamepad L2 holds ADS and ending the input releases it", function()
		local f = controllerFixture(); f.snapshot(3)
		local left = f.inputObject("Gamepad1", "ButtonL2")
		f.input.InputBegan:Fire(left, false); assert(f.aim.IsAiming())
		f.input.InputEnded:Fire(left, false); assert(not f.aim.IsAiming())
	end)
	local function serverFixture()
		local f = fixture()
		f.config = load("Config")
		f.events.Heartbeat = signal(); f.services.Players.PlayerAdded = signal()
		local guid = 0
		f.services.HttpService = { GenerateGUID = function() guid += 1; return "session-" .. guid end }
		local storage, weapons = object("Folder", "ServerStorage"), object("Folder", "Revolvers")
		weapons.children = { object("Tool", f.tool.Name) }; storage.children = { weapons }
		f.services.ServerStorage = storage
		local stats, selected, inventory = object("Folder", "leaderstats"), object("StringValue", "EquippedGun"), object("Folder", "RevolverInventory")
		local owned, quantity = object("Folder", f.tool.Name), object("IntValue", "Quantity")
		selected.Value, quantity.Value = f.tool.Name, 1
		owned.children, inventory.children, stats.children = { quantity }, { owned }, { selected, inventory }
		f.player.attributes = { DataReady = true, InRound = false }
		function f.player:GetAttribute(name) return self.attributes[name] end
		function f.player:FindFirstChild(name) return name == "leaderstats" and stats or nil end
		function f.player:GetNetworkPing() return 0 end
		f.quantity = quantity
		f.mainGame = { GameActive = false, PlayersInGame = {}, RoundStats = nil }
		local remotes, revolver, knife = object("Folder", "Remotes"), object("Folder", "Revolver"), object("Folder", "Knife")
		local damage = object("RemoteEvent", "DamageDealtClient")
		function damage:FireClient(...) f.damageCalls = (f.damageCalls or 0) + 1; f.damageArgs = {...} end
		knife.children, remotes.children = { damage }, { revolver, knife }
		f.action, f.snapshotRemote, f.shot, f.poseRemote = object("RemoteEvent", "Action"), object("RemoteEvent", "State"), object("RemoteEvent", "Shot"), object("UnreliableRemoteEvent", "Aim")
		for _, remote in ipairs({ f.action, f.snapshotRemote, f.shot, f.poseRemote }) do remote.OnServerEvent = signal() end
		function f.snapshotRemote:FireClient(_, data) f.snapshotData = data end
		function f.shot:FireAllClients(data) f.shotCalls = (f.shotCalls or 0) + 1; f.shotData = data end
		f.posePackets = {}
		function f.poseRemote:FireAllClients(...) table.insert(f.posePackets, { ... }) end
		revolver.children = { f.action, f.snapshotRemote, f.shot, f.poseRemote }
		local rs = object("Folder", "ReplicatedStorage")
		rs.children, rs.Remotes = { remotes }, remotes
		rs.Modules = { RagdollQuery = "RagdollQuery", RevolverConfig = "Config", RevolverToolPhysics = "ToolPhysics", RevolverMath = "RayMath", RevolverRaycast = "Raycast", RevolversInfo = "Catalog", RevolverPoseMath = "Math" }
		f.services.ReplicatedStorage = rs
		local state = load("State")
		f.tutorialRuntime = load("TutorialRuntime")
		local dependencies = { Config = f.config, RayMath = RayMath, Math = Math, Catalog = { [f.tool.Name] = {} }, State = state,
			RagdollQuery = queryStub, ToolPhysics = ToolPhysics,
			TutorialRuntime = f.tutorialRuntime,
			Game = f.mainGame, History = { Sample = function() end, Remove = function() end },
			Raycast = { GetMuzzle = function(_, head) return head.Position end, GetCharacterGeometry = Raycast.GetCharacterGeometry,
				Resolve = function(...)
					f.rayCalls = (f.rayCalls or 0) + 1
					if f.realTutorialRay then return Raycast.Resolve(...) end
					return f.resolved or { position = V(0, 2, -20) }
				end } }
		f.env.require = function(name) return assert(dependencies[name], name) end
		f.env.script = { Parent = { RevolverState = "State", RevolverHitHistory = "History", Parent = {
			Game = { MainGame = "Game" }, Tutorial = {TutorialRuntime = "TutorialRuntime"} } } }
		f.env.workspace.Raycast = function() return nil end
		load("Server", f.env)
		function f.sync()
			f.action.OnServerEvent:Fire(f.player, "Sync", f.snapshotData and f.snapshotData.Session, 0)
			f.session = f.snapshotData.Session
		end
		function f.pose(sequence, pitch, session)
			f.poseRemote.OnServerEvent:Fire(f.player, session or f.session, sequence, pitch or 0, 0, true)
		end
		function f.combat(action, sequence)
			f.action.OnServerEvent:Fire(f.player, action, f.session, sequence, V(0, 2, 10), V(0, 0, -1), f.env.workspace:GetServerTimeNow())
		end
		f.sync()
		return f
	end
	test("server replicates lobby arm/ADS angles without changing combat state", function()
		local f = serverFixture(); f.pose(1, 0.2)
		assert(#f.posePackets == 1)
		local packet = f.posePackets[1]
		assert(packet[1] == f.player.UserId and packet[2] == f.character and packet[3] == f.session)
		assert(packet[5] == 0.2 and packet[7] == true and packet[8] == false)
		assert(f.snapshotData.Ammo == 3 and f.snapshotData.ReloadEnd == 0 and not f.shotCalls and not f.rayCalls and not f.damageCalls)
	end)
	test("server lobby pose enforces its own toggle, ownership, sessions and packet validation", function()
		local f = serverFixture()
		f.quantity.Value = 0; f.pose(1); assert(#f.posePackets == 0)
		f.quantity.Value = 1; f.pose(1, 0, "forged-session"); assert(#f.posePackets == 0)
		f.pose(1, 0 / 0); assert(#f.posePackets == 0)
		f.pose(1); assert(#f.posePackets == 1)
		f.advance(0.3); f.pose(1); assert(#f.posePackets == 1)
		f.config.Presentation.LobbyAimingEnabled = false; f.pose(2); assert(#f.posePackets == 1)
		f.config.Presentation.LobbyAimingEnabled = true; f.player.attributes.DataReady = false; f.pose(2); assert(#f.posePackets == 1)
		f.advance(0.3); f.player.attributes.DataReady = true; f.humanoid.Health = 0; f.pose(2); assert(#f.posePackets == 1)
		f.humanoid.Health = 100; f.tool.Parent = nil; f.character.children = {}; f.pose(2); assert(#f.posePackets == 1)
	end)
	test("forged lobby fire/reload remain denied and round transitions preserve combat authority", function()
		local f = serverFixture()
		f.combat("Fire", 1); f.combat("Reload", 2)
		assert(f.snapshotData.Ammo == 3 and f.snapshotData.ReloadEnd == 0 and not f.rayCalls and not f.shotCalls and not f.damageCalls)
		f.player.attributes.InRound = true; f.combat("Fire", 3)
		assert(not f.rayCalls and f.snapshotData.Ammo == 3, "Client round attribute must not grant server membership")
		f.mainGame.GameActive, f.mainGame.PlayersInGame[f.player.UserId], f.mainGame.RoundStats = true, true, {}
		f.sync(); f.combat("Fire", 1)
		assert(f.rayCalls == 1 and f.shotCalls == 1 and f.snapshotData.Ammo == 2)
		f.combat("Reload", 2); assert(f.snapshotData.ReloadEnd > 0)
		f.mainGame.PlayersInGame[f.player.UserId], f.player.attributes.InRound = nil, false
		f.pose(1); assert(#f.posePackets == 1 and f.posePackets[1][8] == false, "Lobby must not display a pending round reload")
		f.events.Heartbeat:Fire(0.1); assert(f.snapshotData.ReloadEnd == 0 and f.snapshotData.Ammo == 2)
		f.advance(0.3); f.combat("Fire", 3); f.combat("Reload", 4)
		assert(f.rayCalls == 1 and f.shotCalls == 1 and f.snapshotData.Ammo == 2 and f.snapshotData.ReloadEnd == 0)
	end)
	test("lobby pose works during another match but rejects stale rounds and characters", function()
		local f = serverFixture()
		local oldSession = f.session
		f.mainGame.GameActive, f.mainGame.RoundStats = true, {}
		f.pose(1); assert(#f.posePackets == 0)
		f.sync(); f.pose(1); assert(#f.posePackets == 1)
		f.pose(2, 0, oldSession); assert(#f.posePackets == 1)
		f.player.CharacterRemoving:Fire(f.character); f.pose(2); assert(#f.posePackets == 1)
		f.advance(0.3); f.sync(); f.pose(1); assert(#f.posePackets == 2)
		f.mainGame.PlayersInGame[f.player.UserId] = true
		f.pose(2); assert(#f.posePackets == 2, "A participant with missing round state must not use lobby permission")
	end)
	test("revolver server sends hit audio metadata only for actual positive damage", function()
		local f = serverFixture(); f.player.attributes.InRound = true
		f.mainGame.GameActive, f.mainGame.RoundStats, f.mainGame.PlayersInGame[1], f.mainGame.PlayersInGame[2] = true, {}, true, true
		local char, hum = object("Model", "Victim"), object("Humanoid", "Humanoid")
		hum.Parent, hum.Health, char.children = char, 100, {hum}
		local victim = {UserId = 2, Character = char, FindFirstChild = function() return nil end, GetAttribute = function(_,name) return name=="DataReady" or name=="InRound" end}
		f.resolved = {position = V(0, 2, -20), victim = {player = victim, character = char, humanoid = hum}}
		local dealt = 30; f.mainGame.DamagePlayer = function() return dealt end
		f.sync(); f.combat("Fire", 1)
		assert(f.damageCalls == 1 and f.damageArgs[1] == f.player and f.damageArgs[2] == char and f.damageArgs[3] == 30)
		assert(f.damageArgs[4] == "Revolver" and f.damageArgs[5] == f.tool.Name)
		dealt = 0; f.advance(1); f.combat("Fire", 2); assert(f.damageCalls == 1 and f.shotCalls == 2)
	end)
	test("tutorial-looking attributes cannot grant revolver permission without a registered session", function()
		local f = serverFixture(); f.player.attributes.TutorialActive, f.player.attributes.InRound = true, true
		f.combat("Fire", 1); f.combat("Reload", 2)
		assert(f.snapshotData.Ammo == 3 and f.snapshotData.ReloadEnd == 0 and not f.rayCalls and not f.damageCalls)
	end)
	test("tutorial revolver resolves owned NPC geometry credits kills and reloads without match stats", function()
		local f = serverFixture(); f.player.attributes.TutorialActive, f.player.attributes.InRound = true, true
		local actions = {}; local tutorialSession = {Active = true, Progress = {Completed = false},
			OnAction = function(kind, evidence) table.insert(actions, {Kind = kind, Evidence = evidence}) end}
		f.tutorialRuntime.Register(f.player, tutorialSession)
		local function target()
			local model, root, head, hum = object("Model", "Bandit"), object("Part", "HumanoidRootPart"), object("Part", "Head"), object("Humanoid", "Humanoid")
			root.Position, root.CFrame, root.Size = V(0, 0, -20), Frame.new(0, 0, -20), V(2, 2, 1)
			head.Position, head.CFrame, head.Size = V(0, 2, -20), Frame.new(0, 2, -20), V(2, 1, 1)
			hum.Health = 70; function hum:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
			model.Parent, model.children = {}, {root, head, hum}; root.Parent, head.Parent, hum.Parent = model, model, model
			f.tutorialRuntime.RegisterTarget(f.player, model); return model, hum
		end
		local model, hum = target(); f.realTutorialRay = true
		f.mainGame.DamagePlayer = function() error("NPC practice must not award match stats") end
		f.combat("Fire", 1)
		assert(hum.Health == 0 and f.snapshotData.Ammo == 2 and f.damageCalls == 1 and f.shotData.Hit)
		assert(#actions == 2 and actions[1].Kind == "Revolver" and actions[2].Kind == "Eliminate" and actions[1].Evidence == model)
		assert(f.mainGame.GameActive == false and next(f.mainGame.PlayersInGame) == nil)
		f.combat("Reload", 2); assert(f.snapshotData.ReloadEnd > 0)
		f.advance(2); f.events.Heartbeat:Fire(0.1)
		assert(f.snapshotData.Ammo == 3 and #actions == 3 and actions[3].Kind == "Reload")
		local covered, coveredHum = target(); local wall = object("Part", "Cover")
		f.env.workspace.Raycast = function(_, origin, direction) return {Distance = 5, Position = origin + direction.Unit * 5, Normal = V(0, 0, 1), Instance = wall} end
		f.combat("Fire", 3)
		assert(coveredHum.Health == 70 and f.damageCalls == 1 and #actions == 3 and not f.shotData.Hit)
		tutorialSession.Progress.Completed = true; f.advance(1); f.combat("Fire", 4)
		assert(f.snapshotData.Ammo == 2 and f.damageCalls == 1)
	end)
	test("server broadcasts confirmed miss surface metadata only after accepting a shot", function()
		local f = serverFixture(); f.player.attributes.InRound = true
		f.mainGame.GameActive, f.mainGame.RoundStats, f.mainGame.PlayersInGame[1] = true, {}, true
		local wall = object("Part", "Wall")
		f.resolved = {position = V(2, 3, -10), normal = V(0, 0, 1), surface = wall}
		f.sync(); f.combat("Fire", 1)
		assert(f.shotData.Surface == wall and f.shotData.Hit == false and f.shotCalls == 1)
		near((f.shotData.Position - f.resolved.position).Magnitude, 0)
		f.combat("Fire", 1); assert(f.shotCalls == 1)
		f.combat("Fire", 2); assert(f.shotCalls == 1, "Cooldown rejection cannot leave a bullet mark")
	end)
	local function knifeFixture()
		local f = fixture()
		local config = load("KnifeConfig")
		local projectile = load("Projectile", {script = {Parent = {KnifeConfig = "KnifeConfig"}}, require = function() return config end, typeof = f.env.typeof})
		f.projectile, f.config = projectile, config
		f.tool.Name = "KnifeA"
		f.player.ClassName = "Player"
		f.player.attributes = {DataReady = true, InRound = true}
		function f.player:GetAttribute(name) return self.attributes[name] end
		f.mainGame = {GameActive = true, PlayersInGame = {[1] = true, [2] = true}}
		function f.mainGame.RegisterPendingKill(_, victim) f.killVictim = victim end
        function f.mainGame.DamagePlayer(killer, victim, humanoid, damage)
            if victim.Character ~= humanoid.Parent then return 0 end
            if humanoid.Health <= damage then f.mainGame.RegisterPendingKill(killer, victim.UserId) end
            local before = humanoid.Health
            humanoid:TakeDamage(damage)
            return before - humanoid.Health
        end
		local victimChar, victimHum, victimPart = object("Model", "Victim"), object("Humanoid", "Humanoid"), object("Part", "Hitbox")
		local victimRoot = object("Part", "HumanoidRootPart")
		victimRoot.Position = V(0, 0, -5)
		victimHum.Health, victimHum.Parent, victimPart.Parent = 100, victimChar, victimChar
		function victimHum:TakeDamage(amount) self.Health -= amount end
		victimChar.children = {victimHum, victimPart, victimRoot}
		f.victim, f.victimHum, f.victimChar, f.victimPart = {UserId = 2, Character = victimChar}, victimHum, victimChar, victimPart
		local results, damage = object("RemoteEvent", "ThrewClient"), object("RemoteEvent", "DamageDealtClient")
		function results:FireClient(_, data) f.result = data end
		function results:FireAllClients(data) f.visual = data end
		function damage:FireClient(...) f.damageCalls = (f.damageCalls or 0) + 1; f.damageArgs = {...} end
		local remotes, knife = object("Folder", "Remotes"), object("Folder", "Knife")
		knife.children, knife.DamageDealtClient = {results, damage}, damage
		remotes.children = {knife}
		local rs, ss, knives = object("Folder", "ReplicatedStorage"), object("Folder", "ServerStorage"), object("Folder", "Knives")
		rs.children, rs.Modules, rs.Remotes = {remotes}, {RagdollQuery = "RagdollQuery", ProjectileMath = "Projectile",
			RevolverRaycast = "Raycast", KnifeConfig = "KnifeConfig"}, remotes
		ss.children, knives.children = {knives}, {object("Tool", "KnifeA")}
		f.services.ReplicatedStorage, f.services.ServerStorage = rs, ss
		local deps = {RagdollQuery = queryStub, Projectile = projectile, Raycast = Raycast, KnifeConfig = config, Game = f.mainGame, Hitboxes = {GetPlayerFromHitbox = function(part)
			if part == victimPart then return f.victim, victimHum end
		end}}
		f.env.require = function(name) return assert(deps[name], name) end
		f.env.script = {Parent = {PlayerHitbox = "Hitboxes", Parent = {Game = {MainGame = "Game"}}}}
		f.rays = 0
		f.env.workspace.Raycast = function(_, origin, vector, params)
			f.rays += 1; f.castOrigin, f.castVector = origin, vector
			if f.hit and f.hit.Instance and f.hit.Instance.Parent == f.victimChar
				and table.find(params.FilterDescendantsInstances, f.victimChar) then return nil end
			return f.hit
		end
		f.throw = load("KnifeThrow", f.env)
		f.head = f.character:FindFirstChild("Head")
		function f.fire(id, charge, origin, direction) return f.throw.Throw(f.player, id or "shot", origin or f.head.Position, direction or V(0, 0, -1), charge or 1) end
		return f
	end
    test("faster knife retains charge curve and capped range with one straight swept ray", function()
        local f = knifeFixture(); assert(f.fire("low", 0)); near(f.castVector.Magnitude, 350); assert(f.rays == 1)
        near(f.projectile.GetSpeed(0), 500); near(f.projectile.GetSpeed(0.5), 625); near(f.projectile.GetSpeed(1), 750)
        near(f.projectile.GetPosition(Vector.zero, V(0,0,-1), 0.1, 0).Magnitude, 50)
		f.advance(f.projectile.COOLDOWN + 0.001); assert(f.fire("full", 1)); near(f.castVector.Magnitude, 350); assert(f.rays == 2)
		assert(f.result.accepted and f.visual.visualOnly and f.visual.knifeName == "KnifeA")
	end)
	test("knife server rejects duplicate shots, cooldown, malformed vectors and spoofed origin", function()
		local f = knifeFixture(); assert(f.fire("one")); assert(not f.fire("two")); f.advance(1)
		assert(not f.fire("one")); assert(not f.fire("far", 1, V(50, 2, 0)))
		assert(not f.fire("zero", 1, nil, Vector.zero)); assert(not f.fire("nan", 0/0)); assert(not f.fire("inf", math.huge))
		assert(not f.fire("overflow", 1, nil, V(1e300, 1e300, 1e300)))
		assert(f.rays == 1)
	end)
	test("knife damage remains 50 and death credit is registered only for an active unprotected victim", function()
		local f = knifeFixture(); f.hit = {Instance = f.victimPart, Position = V(0, 2, -5), Normal = V(0, 0, 1)}
		assert(f.fire("first")); near(f.victimHum.Health, 50); assert(f.killVictim == nil)
		assert(f.damageArgs[4] == "KnifeThrow" and f.damageArgs[5] == "KnifeA")
		f.advance(f.projectile.COOLDOWN + 0.001); assert(f.fire("second")); near(f.victimHum.Health, 0); assert(f.killVictim == 2 and f.damageCalls == 2)
	end)
	test("knife blocks lobby fire, unequipped weapons, forcefields and nonparticipant damage", function()
		local f = knifeFixture(); f.mainGame.GameActive = false; assert(not f.fire("lobby")); assert(f.rays == 0)
		f.mainGame.GameActive = true; f.tool.Parent = nil
		-- Remove from the stand-in's child array to represent unequip.
		table.remove(f.character.children, table.find(f.character.children, f.tool)); assert(not f.fire("unequipped"))
		local protected = knifeFixture(); protected.hit = {Instance = protected.victimPart, Position = V(0, 2, -5), Normal = V(0, 0, 1)}
		table.insert(protected.victimChar.children, object("ForceField", "ForceField")); assert(protected.fire("protected")); near(protected.victimHum.Health, 100)
		protected.victimChar.children[#protected.victimChar.children] = nil; protected.mainGame.PlayersInGame[2] = nil
		protected.advance(protected.projectile.COOLDOWN + 0.001); assert(protected.fire("spectator")); near(protected.victimHum.Health, 100); assert(not protected.damageCalls)
	end)
	test("knife origin cannot be moved through cover even within the allowed origin radius", function()
		local f = knifeFixture(); f.hit = {Instance = object("Part", "Wall"), Position = V(1, 2, 0), Normal = V(-1, 0, 0)}
		assert(not f.fire("wall", 1, V(2, 2, 0))); assert(f.rays == 1 and not f.damageCalls)
	end)
	test("stab preserves damage/range, deduplicates overlapping parts and respects cover", function()
		local f = knifeFixture()
		f.env.OverlapParams = {new = function() return {} end}
		f.env.workspace.GetPartBoundsInBox = function() return {f.victimPart, f.victimPart} end
		local stab = load("KnifeStab", f.env)
		stab.Stab(f.player); near(f.victimHum.Health, 0); assert(f.damageCalls == 1 and f.killVictim == 2)
		local covered = knifeFixture(); covered.env.OverlapParams = {new = function() return {} end}
		covered.env.workspace.GetPartBoundsInBox = function() return {covered.victimPart} end
		covered.hit = {Instance = object("Part", "Wall")}
		load("KnifeStab", covered.env).Stab(covered.player); near(covered.victimHum.Health, 100)
	end)
	test("knife defaults are white and only Frostbite receives multicolor effects", function()
		local config = load("KnifeEffectsConfig")
		local white, rainbow = config.Get("Shadow Dagger"), config.Get("Frostbite")
		assert(#white.TrailColors == 1 and white.SparkRate == 0)
		assert(white.TrailColors[1][1] == 255 and white.TrailColors[1][2] == 255 and white.TrailColors[1][3] == 255)
		assert(#rainbow.TrailColors == 4 and rainbow.SparkRate == 30)
		rainbow.TrailColors[1][1] = 0; white.TrailColors[1][1] = 0
		assert(config.Get("Frostbite").TrailColors[1][1] == 255 and config.Get("Unknown").TrailColors[1][1] == 255)
	end)
	test("knife rail spans across flight direction and stops emission at impact", function()
		local f = fixture(); local config = load("KnifeEffectsConfig")
		local effects = load("KnifeEffects", f.env)
		local stop = effects.Attach(f.root, config.Get("Shadow Dagger"))
		local rail
		for _, item in ipairs(f.created) do if item.Name == "KnifeRail" then rail = item end end
		assert(rail and rail.FaceCamera); near(rail.MaxLength, 18)
		near((rail.Attachment1.Position - rail.Attachment0.Position).Magnitude, 0.32)
		near(rail.Attachment0.Position.Z, 0); near(rail.Attachment1.Position.Z, 0)
		stop(); assert(rail.Enabled == false)
	end)
	test("knife custom sound, pitch and vertical impact burst follow skin configuration", function()
		local f = fixture(); local config = load("KnifeEffectsConfig")
		local effects = load("KnifeEffects", f.env); local tuning = config.Get("Frostbite")
		tuning.ThrowSoundId = "rbxassetid://123"; tuning.ThrowPitchMax = 1.25
		effects.ThrowSound(Vector.zero, 1, tuning)
		local audio
		for _, item in ipairs(f.created) do if item.ClassName == "Sound" then audio = item end end
		assert(audio and audio.SoundId == tuning.ThrowSoundId and audio.played); near(audio.PlaybackSpeed, 1.25)
		effects.Impact(Vector.zero, V(0, 1, 0), tuning)
		local emitted = 0
		for _, item in ipairs(f.created) do if item.ClassName == "ParticleEmitter" then emitted += item.emitted or 0 end end
		near(emitted, tuning.ImpactSparkCount)
	end)
	test("each revolver has an independent override and custom shot colors/sounds reach effects", function()
		local f = fixture(); local settings = load("Config")
		local count = 0; for _ in pairs(settings.Overrides) do count += 1 end; assert(count == 54)
		settings.Overrides["Azure Revolver"] = {Effects = {TracerColor = {50, 150, 255}, MuzzleColors = {{50, 150, 255}},
			MuzzleLightColor = {50,150,255}, ImpactColors = {{50,150,255}}, FireSoundId = "rbxassetid://blue", TracerThickness = 0.3}}
		local tuning = settings.Get("Azure Revolver"); tuning.Effects.TracerColor[1] = 55
		assert(settings.Get("Azure Revolver").Effects.TracerColor[1] == 50 and settings.Default.Effects.TracerColor[1] == 255)
		local oldRequire = f.env.require; f.env.require = function(name) if name == "Config" then return settings end; return oldRequire(name) end
		local effects = load("Effects", f.env); effects.Fire(nil, Vector.zero, V(0, 0, -20), tuning, false)
		effects.Impact(Vector.zero, V(0,1,0), tuning.Effects)
		local audio, flash, impact
		for _, item in ipairs(f.created) do
			if item.ClassName == "Sound" then audio = item end
			if item.ClassName == "ParticleEmitter" and item.emitted == 2 then flash = item end
			if item.ClassName == "ParticleEmitter" and item.emitted == tuning.Effects.ImpactSparkCount then impact = item end
		end
		assert(audio.SoundId == "rbxassetid://blue" and flash.Color[1][1] == 50 and impact.Color[1][3] == 255)
	end)
	test("knife server cannot damage an old character returned by a stale hitbox", function()
		local f = knifeFixture(); f.victim.Character = object("Model", "Replacement")
		f.hit = {Instance = f.victimPart, Position = V(0,2,-5), Normal = V(0,0,1)}
		assert(f.fire("stale")); near(f.victimHum.Health, 100); assert(not f.damageCalls)
	end)
	test("first-person fire before the camera model is ready keeps sound and streak without using hidden skin emitters", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local muzzle, custom = object("Attachment", "Muzzle"), object("ParticleEmitter", "SkinFlash")
		muzzle.WorldPosition, muzzle.children = V(0, 1, -1), {custom}
		table.insert(f.tool.children, muzzle)
		local effects = load("Effects", f.env)
		local shot = effects.Fire(f.tool, Vector.zero, V(0, 0, -20), tuning, true, nil, true); assert(shot)
		assert(not custom.emitted)
		local sounds = 0
		for _, item in ipairs(f.created) do
			assert(item.ClassName ~= "ParticleEmitter" and item.ClassName ~= "PointLight")
			if item.ClassName == "Sound" and item.played then sounds += 1 end
		end
		assert(sounds == 1); effects.Clear(); assert(shot.destroyed)
	end)
	test("first-person feedback reuses emitters audio and streaks with one shared update and no new Instances or scans", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual = object("Model", "CameraWeapon"); visual.Parent = object("Model", "RevolverFirstPerson")
		local handle = object("Part", "Handle"); handle.Parent, handle.CFrame = visual, Frame.identity
		visual.children = {handle}
		local effects = load("Effects", f.env)
		effects.SetFirstPerson(visual, tuning)
		local created = #f.created
		local flash, sparks, voices, streaks = nil, nil, 0, 0
		for _, item in ipairs(f.created) do
			if item.Name == "FirstPersonShotFlash" then flash = item end
			if item.Name == "FirstPersonShotSparks" then sparks = item end
			if item.Name == "FirstPersonShotSound" then voices += 1 end
			if item.Name == "RevolverShotStreak" then streaks += 1 end
		end
		assert(flash and sparks and voices == tuning.FirstPerson.ShotSoundVoices)
		assert(streaks == tuning.FirstPerson.ShotTracerSlots)
		assert(flash.Parent.Parent == handle and flash.Rate == 0 and not flash.Enabled and flash.LockedToPart == false)
		assert(flash.Lifetime[1] <= 0.08 and sparks.Lifetime[1] <= 0.1)
		for _ = 1, 100 do
			effects.SetFirstPerson(visual, tuning)
			assert(effects.Fire(f.tool, Vector.zero, V(0, 0, -20), tuning, true, visual, true).Parent)
		end
		assert(#f.created == created and not visual.descendantReads and f.events.RenderStepped:Count() == 1)
		assert(flash.emitted == 200 and sparks.emitted == 100 * tuning.FirstPerson.ShotSparkCount)
		for _, item in ipairs(f.created) do assert(not item:IsA("PointLight")) end
		effects.SetFirstPerson(nil, tuning); assert(flash.cleared == 1 and sparks.cleared == 1)
		f.advance(0.3); assert(f.events.RenderStepped:Count() == 0)
		for _, item in ipairs(f.created) do
			if item:IsA("Beam") or item:IsA("Trail") then assert(not item.Enabled) end
			if item.Name == "RevolverShotStreak" then assert(not item.destroyed) end
		end
		effects.SetFirstPerson(nil, tuning); assert(flash.cleared == 1)
		effects.SetFirstPerson(visual, tuning); assert(#f.created == created)
		effects.Clear(); assert(flash.Parent.destroyed and sparks.Parent.destroyed)
	end)
	test("deferred first-person feedback emits once at the safe origin and confirmation only starts the pooled streak", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		local flash, socket, path
		for _, item in ipairs(f.created) do
			if item.Name == "FirstPersonShotFlash" then flash, socket = item, item.Parent end
		end
		local safe, destination, priorFrame = V(0, 2, 0), V(0, 2, -1), socket.CFrame
		local emittedAt
		function flash:Emit(count) self.emitted = (self.emitted or 0) + count; emittedAt = socket.WorldPosition end
		local allocated = #f.created
		assert(not effects.Fire(f.tool, safe, destination, tuning, true, visual, true, false, true, safe))
		assert(f.events.RenderStepped:Count() == 0 and flash.emitted == 2)
		near((socket.CFrame.Position - priorFrame.Position).Magnitude, 0)
		near(socket.CFrame.LookVector:Dot(priorFrame.LookVector), 1)
		near((emittedAt - safe).Magnitude, 0)
		f.advance(0.6)
		local lease = effects.ConfirmedTracer(safe, destination, tuning, visual, true)
		assert(lease and lease.Parent and flash.emitted == 2 and #f.created == allocated)
		for _, item in ipairs(f.created) do if item:IsA("Beam") and item.Enabled then path = item.Parent end end
		assert(path); near((path.CFrame.Position - safe).Magnitude, 0)
		f.advance(0.3); effects.Clear(); assert(not lease.Parent and f.events.RenderStepped:Count() == 0)
	end)
	test("a zero-distance pointblank hit still emits first-person flash at the safe origin without a streak", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		local safe, emittedAt = V(0, 2, 0), nil
		for _, item in ipairs(f.created) do
			if item.Name == "FirstPersonShotFlash" then
				function item:Emit(count) self.emitted = count; emittedAt = self.Parent.WorldPosition end
			end
		end
		assert(not effects.Fire(f.tool, safe, safe, tuning, true, visual, true, false, true, safe))
		near((emittedAt - safe).Magnitude, 0)
		assert(not effects.ConfirmedTracer(safe, safe, tuning, visual, true) and f.events.RenderStepped:Count() == 0)
		effects.Clear()
	end)
	test("first-person streak starts at the visible muzzle and follows confirmed correction", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, handle, muzzle = object("Model", "CameraWeapon"), object("Part", "Handle"), object("Attachment", "Muzzle")
		visual.Parent, visual.children, handle.Parent = {}, {handle, muzzle}, visual
		muzzle.Parent, muzzle.CFrame = handle, Frame.new(0.8,-0.6,-1.5)
		local hidden = object("ParticleEmitter", "HiddenSkinFlash"); f.tool.children = {hidden}
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual,tuning)
		local lease = effects.Fire(f.tool,V(300,200,0),V(0,0,-30),tuning,true,visual,true)
		local path, tip
		local expected = muzzle.WorldPosition + f.camera.CFrame:VectorToWorldSpace(V(tuning.Effects.MuzzleVisualRight,
			tuning.Effects.MuzzleVisualUp, -tuning.Effects.MuzzleVisualForward))
		for _, item in ipairs(f.created) do
			if item.Name == "Path" and (item.CFrame.Position - expected).Magnitude < 1e-5 then path = item end
			if item.Name == "BulletGlint" and item.Transparency == 0.15 then tip = item end
		end
		assert(path and tip and lease.Parent and not hidden.emitted)
		near((path.CFrame.Position-expected).Magnitude,0)
		effects.CorrectTracer(lease,V(2,1,-25)); f.advance(tuning.Effects.VisualTravelMs/1000)
		near((tip.CFrame.Position-V(2,1,-25)).Magnitude,0)
		effects.Clear(); assert(not lease.Parent and f.events.RenderStepped:Count() == 0)
	end)
	test("reused streak leases ignore delayed corrections and cleanup for an older shot", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver"); tuning.FirstPerson.ShotTracerSlots = 1
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual,tuning)
		local old = effects.Fire(f.tool,Vector.zero,V(0,0,-20),tuning,true,visual,true)
		local clearCounts = {}
		for _, item in ipairs(f.created) do if item:IsA("Trail") then clearCounts[item] = item.cleared end end
		f.advance(0.01)
		local current = effects.Fire(f.tool,Vector.zero,V(3,1,-40),tuning,true,visual,true)
		assert(old ~= current and not old.Parent and current.Parent)
		old:Destroy(); effects.CorrectTracer(old,V(0,0,-1)); assert(current.Parent)
		f.advance(tuning.Effects.VisualTravelMs/1000 + 0.001)
		for _, item in ipairs(f.created) do
			if item.Name == "BulletGlint" then near((item.CFrame.Position-V(3,1,-40)).Magnitude,0) end
			if item:IsA("Trail") then assert(item.cleared == clearCounts[item] + 3 and not item.Enabled) end
		end
		current:Destroy(); assert(not current.Parent and f.events.RenderStepped:Count() == 0)
		effects.Clear()
	end)
	test("disabled tracers keep first-person flash and sound without preparing a streak pool", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver"); tuning.Effects.TracerEnabled = false
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual,tuning)
		assert(not effects.Fire(f.tool,Vector.zero,V(0,0,-20),tuning,true,visual,true))
		local flashed = false
		for _, item in ipairs(f.created) do
			assert(not item:IsA("Beam") and not item:IsA("Trail"))
			if item.Name == "FirstPersonShotFlash" then flashed = item.emitted == 2 end
		end
		assert(flashed and f.events.RenderStepped:Count() == 0); effects.Clear()
	end)
	test("first-person and observer streaks share the same active budget and single update", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local previousBudget = Config.Presentation.MaxActiveTracers; Config.Presentation.MaxActiveTracers = 2
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual,tuning)
		local owner = effects.Fire(f.tool,Vector.zero,V(0,0,-20),tuning,true,visual,true)
		f.advance(0.001); local observer = effects.Tracer(Vector.zero,V(0,0,-25),tuning.Effects)
		f.advance(0.001); local latest = effects.Tracer(Vector.zero,V(0,0,-30),tuning.Effects)
		assert(not owner.Parent and observer.Parent and latest.Parent)
		f.advance(0.001); local nextOwner = effects.Fire(f.tool,Vector.zero,V(0,0,-40),tuning,true,visual,true)
		assert(observer.destroyed and latest.Parent and nextOwner.Parent and f.events.RenderStepped:Count() == 1)
		effects.Clear(); assert(latest.destroyed and not nextOwner.Parent and f.events.RenderStepped:Count() == 0)
		Config.Presentation.MaxActiveTracers = previousBudget
	end)
	test("removing an already suspended camera gun destroys its cached streak pool", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual,tuning)
		local shot = effects.Fire(f.tool,Vector.zero,V(0,0,-20),tuning,true,visual,true)
		effects.SetFirstPerson(nil,tuning); assert(shot.Parent)
		visual.Parent = nil; effects.SetFirstPerson(nil,tuning)
		assert(not shot.Parent and f.events.RenderStepped:Count() == 0)
		for _, item in ipairs(f.created) do if item.Name == "RevolverShotStreak" then assert(item.destroyed) end end
		effects.Clear()
	end)
	test("pooled first-person flash follows the authored muzzle and cleanup preserves that attachment", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver")
		local visual, barrel, muzzle = object("Model", "CameraWeapon"), object("Part", "Muzzle"), object("Attachment", "Muzzle")
		local handle = object("Part", "Handle"); handle.Parent, handle.CFrame = visual, Frame.identity
		muzzle.Parent, muzzle.CFrame = barrel, Frame.new(0, 0, -1)
		visual.children, visual.Parent = {muzzle, handle}, object("Model", "RevolverFirstPerson")
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		local flash
		for _, item in ipairs(f.created) do if item.Name == "FirstPersonShotFlash" then flash = item end end
		assert(flash.Parent ~= muzzle and flash.Parent.Parent == muzzle.Parent)
		local oldSocket = flash.Parent
		muzzle.CFrame = Frame.new(0.3, 0.1, -2); effects.SetFirstPerson(visual, tuning)
		local expected = muzzle.WorldPosition + f.camera.CFrame:VectorToWorldSpace(V(0,
			tuning.Effects.MuzzleVisualUp, -tuning.Effects.MuzzleVisualForward))
		near((flash.Parent.WorldPosition - expected).Magnitude, 0)
		effects.Clear(); assert(not muzzle.destroyed and oldSocket.destroyed)
	end)
	test("first-person fallback flash and streak leave the raised forward barrel tip", function()
		local f = fixture(); local tuning = Config.Get(f.tool.Name)
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		handle.CFrame = Frame.new(0.7, -0.5, -0.6) * Frame.Angles(0.1, 0.2, 0.05)
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		local expected = Raycast.GetMuzzlePosition(visual, tuning) + f.camera.CFrame:VectorToWorldSpace(V(0,
			tuning.Effects.MuzzleVisualUp, -tuning.Effects.MuzzleVisualForward))
		local flash, path
		effects.Fire(f.tool, Vector.zero, V(0, 0, -20), tuning, true, visual, true)
		for _, item in ipairs(f.created) do
			if item.Name == "FirstPersonShotFlash" then flash = item end
			if item.Name == "Path" and item.CFrame.Position.Z < -1 then path = item end
		end
		assert(flash and path and flash.Parent.Parent == handle)
		near((flash.Parent.WorldPosition - expected).Magnitude, 0)
		near((path.CFrame.Position - expected).Magnitude, 0)
		local socket = flash.Parent; effects.Clear(); assert(socket.destroyed and not handle.destroyed)
	end)
	test("first-person visual Up and Forward use camera axes across rotated skin attachments", function()
		local f = fixture(); local tuning = Config.Get(f.tool.Name)
		local visual, handle, muzzle = object("Model", "CameraWeapon"), object("Part", "Handle"), object("Attachment", "Muzzle")
		visual.Parent, visual.children, handle.Parent = {}, {handle, muzzle}, visual
		handle.CFrame = Frame.new(0.6, -0.5, -1) * Frame.Angles(0.2, 0.6, 0.3)
		muzzle.Parent, muzzle.CFrame = handle, Frame.new(0.1, 0.2, -0.4) * Frame.Angles(1.1, 0.2, 1.3)
		f.camera.CFrame = Frame.new(0, 0, 0) * Frame.Angles(0.5, -0.7, 0.1)
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		local socket
		for _, item in ipairs(f.created) do if item.Name == "FirstPersonShotMuzzle" then socket = item end end
		local offset = V(tuning.Effects.MuzzleVisualRight, tuning.Effects.MuzzleVisualUp, -tuning.Effects.MuzzleVisualForward)
		near((f.camera.CFrame:VectorToObjectSpace(socket.WorldPosition - muzzle.WorldPosition) - offset).Magnitude, 0)
		f.camera.CFrame = Frame.new(0, 0, 0) * Frame.Angles(-1.2, 1.1, -0.2); effects.SetFirstPerson(visual, tuning)
		near((f.camera.CFrame:VectorToObjectSpace(socket.WorldPosition - muzzle.WorldPosition) - offset).Magnitude, 0)
		effects.Clear(); assert(not muzzle.destroyed)
	end)
	test("camera muzzle enable setting hides its particles while retaining the pooled firing sound", function()
		local f = fixture(); local tuning = Config.Get("Amber Revolver"); tuning.FirstPerson.ShotEnabled = false
		local visual, handle = object("Model", "CameraWeapon"), object("Part", "Handle")
		visual.Parent, visual.children, handle.Parent = {}, {handle}, visual
		local effects = load("Effects", f.env); effects.SetFirstPerson(visual, tuning)
		effects.Fire(f.tool, Vector.zero, V(0, 0, -20), tuning, true, visual, true)
		local played = false
		for _, item in ipairs(f.created) do
			if item:IsA("ParticleEmitter") then assert(not item.emitted) end
			if item:IsA("Sound") and item.played then played = true end
		end
		assert(played); effects.Clear()
	end)
	-- Geometry stand-ins keep real parenting and recursive cloning semantics.
	local geometryMethods = {}
	local geometryObject
	local geometryParentObserver
	geometryObject = function(class, name, parent)
		local props = {ClassName = class, Name = name or class, Archivable = true, CFrame = Frame.identity,
			Size = V(1, 2, 1), Transparency = 0, LocalTransparencyModifier = 0, Offset = Vector.zero,
			Enabled = true, Rate = 20, Brightness = 2, Scale = Vector.one, MeshType = "FileMesh",
			Changed = signal(), ChildAdded = signal(), ChildRemoved = signal(), DescendantAdded = signal(), DescendantRemoving = signal()}
		local item = setmetatable({props = props, children = {}}, {
			__index = function(self, key)
				if key == "LocalTransparencyModifier" and self.props.noLocalModifier then error("unsupported legacy modifier") end
				return geometryMethods[key] or self.props[key]
			end,
			__newindex = function(self, key, value)
				if key == "LocalTransparencyModifier" and self.props.noLocalModifier then error("unsupported legacy modifier") end
				if key == "Parent" then
					local old = self.props.Parent
					if old == value then return end
					if geometryParentObserver then geometryParentObserver(self, value) end
					if old then local i = table.find(old.children, self); if i then table.remove(old.children, i) end; old.ChildRemoved:Fire(self) end
					self.props.Parent = value
					if value then table.insert(value.children, self); value.ChildAdded:Fire(self) end
				else
					local previous = self.props[key]; self.props[key] = value
					if previous ~= value then self.props.Changed:Fire(key) end
				end
			end,
		})
		item.Parent = parent
		return item
	end
	function geometryMethods:IsA(class)
		return class == self.ClassName or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
			or (class == "BaseScript" and (self.ClassName == "Script" or self.ClassName == "LocalScript"))
			or (class == "LuaSourceContainer" and (self.ClassName == "Script" or self.ClassName == "LocalScript" or self.ClassName == "ModuleScript"))
			or (class == "Constraint" and self.ClassName == "BallSocketConstraint")
			or (class == "Light" and self.ClassName == "PointLight")
			or (class == "JointInstance" and (self.ClassName == "Weld" or self.ClassName == "Motor6D"))
			or (class == "DataModelMesh" and (self.ClassName == "SpecialMesh" or self.ClassName == "BlockMesh"))
			or (class == "FaceInstance" and (self.ClassName == "Decal" or self.ClassName == "Texture"))
	end
	function geometryMethods:GetChildren() return table.clone(self.children) end
	function geometryMethods:GetDescendants()
		self.descendantReads = (self.descendantReads or 0) + 1
		local all = {}; for _, c in ipairs(self.children) do table.insert(all, c); for _, d in ipairs(c:GetDescendants()) do table.insert(all, d) end end; return all
	end
	function geometryMethods:FindFirstChild(name, recursive)
		for _, c in ipairs(self.children) do if c.Name == name then return c end end
		if recursive then for _, c in ipairs(self.children) do local found = c:FindFirstChild(name, true); if found then return found end end end
	end
	function geometryMethods:FindFirstChildOfClass(class) for _, c in ipairs(self.children) do if c:IsA(class) then return c end end end
	function geometryMethods:Clone()
		if not self.Archivable then return nil end
		if self.cloneFailure then error("simulated clone failure") end
		self.cloneCount = (self.cloneCount or 0) + 1
		local clone = geometryObject(self.ClassName, self.Name)
		for k, v in pairs(self.props) do
			if k ~= "Parent" and k ~= "Changed" and k ~= "ChildAdded" and k ~= "ChildRemoved" and k ~= "DescendantAdded" and k ~= "DescendantRemoving"
				and not (k == "LocalTransparencyModifier" and self.props.noLocalModifier) then clone[k] = v end
		end
		for _, c in ipairs(self.children) do local copy = c:Clone(); if copy then copy.Parent = clone end end
		return clone
	end
	function geometryMethods:Destroy() for _, c in ipairs(self:GetChildren()) do c:Destroy() end; self.Parent = nil; self.destroyed = true end
	function geometryMethods:GetAttribute(name) return self.attributes and self.attributes[name] end
	function geometryMethods:Clear() self.clearCount = (self.clearCount or 0) + 1 end
	function geometryMethods:CanCollideWith(other)
		if not self.CanCollide or not other.CanCollide then return false end
		return self.collisionRegistry:CollisionGroupsAreCollidable(self.CollisionGroup or "Default", other.CollisionGroup or "Default")
	end
	local function viewmodelFixture()
		local f = fixture(); f.env.Instance.new = geometryObject
		f.buildJobs, f.buildYields = {}, 0
		f.env.task = {defer = function(fn) table.insert(f.buildJobs, fn) end,
			wait = function() f.buildYields += 1 end}
		function f.flushBuilds()
			local jobs = f.buildJobs; f.buildJobs = {}
			for _, job in ipairs(jobs) do job() end
			return #jobs > 0
		end
		f.services.PhysicsService = {IsCollisionGroupRegistered = function() return true end}
		local attributes = {[Config.FirstPersonPhysics.ReadyAttribute] = true}
		f.services.ReplicatedStorage.GetAttribute = function(_, name) return attributes[name] end
		f.services.ReplicatedStorage.SetAttribute = function(_, name, value) attributes[name] = value end
		f.character = geometryObject("Model", "Character")
		f.right = geometryObject("Part", "Right Arm", f.character)
		f.left = geometryObject("Part", "Left Arm", f.character)
		f.root = geometryObject("Part", "HumanoidRootPart", f.character); f.root.AssemblyLinearVelocity = Vector.zero
		geometryObject("Part", "Torso", f.character)
		geometryObject("Part", "Head", f.character)
		f.humanoid = geometryObject("Humanoid", "Humanoid", f.character)
		f.humanoid.Health, f.humanoid.WalkSpeed, f.humanoid.FloorMaterial = 100, 16, "Concrete"
		f.player.Character = f.character
		f.tool = geometryObject("Tool", "Amber Revolver", f.character); f.tool.Grip = Frame.identity
		f.handle = geometryObject("Part", "Handle", f.tool); f.handle.CFrame = Frame.new(3, 5, 7)
		f.barrel = geometryObject("MeshPart", "Barrel", f.tool)
		f.barrel.CFrame, f.barrel.TextureID = f.handle.CFrame * Frame.new(0, 0, -1), "skin-texture"
		f.grip = geometryObject("Weld", "RightGrip", f.right)
		f.grip.Part0, f.grip.Part1, f.grip.C0, f.grip.C1 = f.right, f.handle, Frame.new(0, -1, 0), Frame.Angles(-math.pi/2, 0, 0)
		f.camera = geometryObject("Camera", "Camera")
		f.camera.CFrame, f.camera.Focus = Frame.identity, Frame.new(0, 0, -0.5)
		f.camera.CameraType, f.camera.CameraSubject = "Custom", f.humanoid
		f.env.workspace.CurrentCamera = f.camera
		f.services.VRService = {VREnabled = false}
		f.env.Enum.HumanoidDisplayDistanceType = {None = "None"}
		f.env.Enum.HumanoidRigType = {R6 = "R6"}
		f.env.Enum.MeshType = {FileMesh = "FileMesh", Brick = "Brick"}
		f.tuning = Config.Get(f.tool.Name)
		local visibility = load("WeaponVisibility", f.env)
		f.env.script = {Parent = {WeaponViewmodelVisibility = "WeaponVisibility"}}
		local requireModule = f.env.require
		f.env.require = function(name) if name == "WeaponVisibility" then return visibility end; return requireModule(name) end
		f.geometry = load("WeaponGeometry", f.env)
		f.skinEffects = load("WeaponEffects", f.env)
		f.services.ReplicatedStorage.Modules.RevolverViewmodelMath = "ViewmodelMath"
		f.env.script = {Parent = {WeaponViewmodelGeometry = "WeaponGeometry", WeaponViewmodelEffects = "WeaponEffects",
			WeaponViewmodel = "WeaponViewmodel", RevolverEffects = "RevolverEffects"}}
		local dependencies = {Config = Config, InspectConfig = InspectConfig, InspectMotion = InspectMotion,
			ViewmodelMath = Motion, WeaponGeometry = f.geometry, WeaponEffects = f.skinEffects, WeaponVisibility = visibility,
			RevolverEffects = {SetFirstPerson = function(weapon) f.preparedWeapon = weapon end}}
		f.env.require = function(name) return assert(dependencies[name], name) end
		f.warnings = {}; f.env.warn = function(message) table.insert(f.warnings, message) end
		f.factory = load("WeaponViewmodel", f.env); dependencies.WeaponViewmodel = f.factory
		assert(load("ViewmodelGeometry", f.env) == f.geometry and load("ViewmodelEffects", f.env) == f.skinEffects)
		f.view = load("Viewmodel", f.env)
		function f.update(allowed, aiming, reloading, dt)
			f.view.Update(f.tool, f.tuning, allowed ~= false, aiming == true, reloading == true, dt or 1/60,
				f.bodyAnimation, f.armAnimation, f.action, f.weaponVisible)
			-- Deferred construction runs outside the render callback. Publish only on
			-- the following render; preserve this fixture's settled-frame assertions.
			if f.flushBuilds() then
				f.view.Update(f.tool, f.tuning, allowed ~= false, aiming == true, reloading == true, dt or 1/60,
					f.bodyAnimation, f.armAnimation, f.action, f.weaponVisible)
			end
		end
		function f.model() return f.camera:FindFirstChild("RevolverFirstPerson") end
		return f
	end
	test("render schedules construction without cloning and Clear cancels queued work", function()
		local f = viewmodelFixture()
		f.view.Update(f.tool, f.tuning, true, false, false, 1/60)
		assert(#f.buildJobs == 1 and not f.handle.cloneCount and not f.model())
		for _ = 1, 10 do f.view.Update(f.tool, f.tuning, true, false, false, 1/60) end
		assert(#f.buildJobs == 1 and not f.handle.cloneCount)
		f.view.Clear(); f.flushBuilds()
		assert(not f.model() and not f.handle.cloneCount and f.tool.DescendantAdded:Count() == 0)
		f.update(); assert(f.model() and f.preparedWeapon == f.view.GetVisualTool(f.tool)); f.view.Clear()
	end)
	test("large cosmetic builds yield and late geometry during a yield cannot publish a stale copy", function()
		local f = viewmodelFixture(); f.tuning.FirstPerson.BuildObjectsPerFrame = 2
		local late
		f.env.task.wait = function()
			f.buildYields += 1
			if not late then
				late = geometryObject("Part", "LateBlade", f.tool)
				f.tool.DescendantAdded:Fire(late)
			end
		end
		f.update(); assert(not f.model() and f.buildYields > 0 and #f.warnings == 0)
		f.update(); assert(f.model():FindFirstChild("LateBlade", true))
		assert(f.tool.DescendantAdded:Count() == 1); f.view.Clear()
		assert(f.tool.DescendantAdded:Count() == 0 and f.handle.Changed:Count() == 0)
	end)
	test("cancelling during a construction yield destroys the partial model and temporary listeners", function()
		local f = viewmodelFixture(); f.tuning.FirstPerson.BuildObjectsPerFrame = 1
		local createdModels = {}
		f.env.Instance.new = function(class)
			local item = geometryObject(class)
			if class == "Model" then table.insert(createdModels, item) end
			return item
		end
		f.env.task.wait = function() f.view.Clear() end
		f.view.Update(f.tool, f.tuning, true, false, false, 1/60); f.flushBuilds()
		assert(not f.model() and #f.buildJobs == 0 and #f.warnings == 0)
		for _, model in ipairs(createdModels) do assert(model.destroyed) end
		assert(f.tool.DescendantAdded:Count() == 0 and f.handle.Changed:Count() == 0
			and f.character.DescendantAdded:Count() == 0 and f.handle.LocalTransparencyModifier == 0)
		f.env.task.wait = function() end; f.update(); assert(f.model()); f.view.Clear()
	end)
	test("sprinting can start and finish a stable inspection without changing movement", function()
		local f = viewmodelFixture(); f.humanoid.WalkSpeed = 32; f.root.AssemblyLinearVelocity = V(32, 0, 0)
		f.bodyAnimation = Frame.Angles(0.4, 0, 0); f.armAnimation = Frame.Angles(0.9, 0, 0)
		f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
		for _ = 1, 60 do f.update() end
		assert(f.view.IsInspecting(f.tool) and f.humanoid.WalkSpeed == 32)
		for _ = 1, math.ceil(InspectConfig.Revolver.Duration * 60) do f.update() end
		assert(not f.view.IsInspecting(f.tool) and #f.warnings == 0); f.view.Clear()
	end)
	test("animated skin appearance during build settles to the latest snapshot without starvation", function()
		local f = viewmodelFixture(); f.tuning.FirstPerson.BuildObjectsPerFrame = 1
		f.env.task.wait = function()
			f.buildYields += 1
			f.handle.Color = f.buildYields
			f.handle.Size = V(1 + f.buildYields * 0.01, 2, 1)
		end
		f.update()
		local handle = assert(f.view.GetVisualTool(f.tool)):FindFirstChild("Handle")
		assert(handle.Color == f.handle.Color and handle.Size.X == f.handle.Size.X and #f.warnings == 0)
		assert(f.handle.cloneCount == 1 and f.handle.Changed:Count() == 1)
		f.view.Clear(); assert(f.handle.Changed:Count() == 0)
	end)
	test("inspect waits for a fully published hold and never restarts an active animation", function()
		local f = viewmodelFixture()
		assert(not f.view.StartInspect(f.tool))
		f.update(); assert(not f.view.StartInspect(f.tool))
		f.update(true, false, false, 0.25)
		assert(f.view.StartInspect(f.tool) and f.view.IsInspecting(f.tool))
		assert(not f.view.StartInspect(f.tool) and not f.view.StartInspect({}))
		f.view.Clear(); assert(not f.view.IsInspecting(f.tool))
	end)
	test("inspect moves the camera copy while preserving skin grip and all gameplay transforms", function()
		local f = viewmodelFixture(); f.update(true, false, false, 0.25)
		local model = assert(f.model())
		local camera, focus, root, shoulder, handle = f.camera.CFrame, f.camera.Focus, f.root.CFrame, f.joint.C0, f.handle.CFrame
		local idle = model:FindFirstChild("Right Arm").CFrame
		local skinOffset = f.handle.CFrame:Inverse() * f.barrel.CFrame
		local reads, avatarReads, modelParts = f.tool.descendantReads, f.character.descendantReads, #model:GetDescendants()
		assert(f.view.StartInspect(f.tool))
		for _ = 1, 48 do f.update() end
		local copy = model:FindFirstChild("Handle", true)
		local barrel = model:FindFirstChild("Barrel", true)
		local inspected = model:FindFirstChild("Right Arm").CFrame
		assert((inspected.Position - idle.Position).Magnitude < 0.1, "inspect must retain a small, in-place hold")
		local rotationChange = 0; for i = 1, 9 do rotationChange += math.abs(inspected.matrix[i] - idle.matrix[i]) end
		assert(rotationChange > 0.1, "inspect must visibly tilt the held weapon")
		local expectedBarrel = copy.CFrame * skinOffset
		near((expectedBarrel.Position - barrel.CFrame.Position).Magnitude, 0)
		for i = 1, 9 do near(expectedBarrel.matrix[i], barrel.CFrame.matrix[i]) end
		assert(f.camera.CFrame == camera and f.camera.Focus == focus and f.root.CFrame == root
			and f.joint.C0 == shoulder and f.handle.CFrame == handle)
		assert(f.model() == model and #model:GetDescendants() == modelParts
			and f.tool.descendantReads == reads and f.character.descendantReads == avatarReads)
		for _ = 1, math.ceil(InspectConfig.Revolver.Duration * 60) do f.update() end
		assert(not f.view.IsInspecting(f.tool) and f.model() == model and #f.warnings == 0)
		f.view.Clear()
	end)
	for _, case in ipairs({
		{"aim", function(f) f.update(true, true) end},
		{"reload", function(f) f.update(true, false, true) end},
		{"knife early charge", function(f) f.action = {holdingCharge = true, charging = false}; f.update() end},
		{"knife full charge", function(f) f.action = {charging = true, charge = 1}; f.update() end},
		{"knife throw", function(f) f.action = {throwElapsed = 0.1}; f.update() end},
		{"knife stab", function(f) f.action = {stabElapsed = 0.1}; f.update() end},
		{"hidden returning blade", function(f) f.weaponVisible = false; f.update() end},
	}) do
		test(case[1] .. " takes the viewmodel immediately and blocks inspect", function()
			local f = viewmodelFixture(); f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
			f.update(true, false, false, 0.3); case[2](f)
			assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool) and #f.warnings == 0)
			f.view.Clear()
		end)
	end
	for _, case in ipairs({
		{"slide", function(f) f.character.attributes = {[InspectConfig.PostureAttribute] = "Slide"} end},
		{"jump", function(f) f.humanoid.FloorMaterial = "Air" end},
		{"seat", function(f) f.humanoid.Sit = true end},
	}) do
		test(case[1] .. " blends inspect out quickly and prevents another start", function()
			local f = viewmodelFixture(); f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
			f.update(true, false, false, 0.5); case[2](f); f.update()
			assert(f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
			f.update(true, false, false, InspectConfig.ReturnSeconds)
			assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
			f.view.Clear()
		end)
	end
	test("walking and crouching retain inspect while taking damage cancels it", function()
		local f = viewmodelFixture(); f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
		f.root.AssemblyLinearVelocity = V(10, 0, 0); f.humanoid.WalkSpeed = 8
		f.character.attributes = {[InspectConfig.PostureAttribute] = "Crouch"}; f.bodyAnimation = Frame.new(0, -0.5, 0)
		f.update(true, false, false, 0.5); assert(f.view.IsInspecting(f.tool))
		f.humanoid.Health = 75; f.update()
		assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
		f.update(true, false, false, InspectConfig.AfterActionSeconds); assert(f.view.StartInspect(f.tool))
		f.view.Clear()
	end)
	test("combat interruption is immediate and late recoil for an old Tool cannot interrupt the next hold", function()
		local f = viewmodelFixture(); f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
		f.view.Kick({}); assert(f.view.IsInspecting(f.tool))
		f.view.Kick(f.tool); assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
		f.update(true, false, false, InspectConfig.AfterActionSeconds); assert(f.view.StartInspect(f.tool))
		f.view.InterruptInspect(); assert(not f.view.IsInspecting(f.tool))
		f.view.Clear()
	end)
	for _, case in ipairs({
		{"zoom out", function(f) f.camera.Focus = Frame.new(0, 0, -2); f.update() end},
		{"menu", function(f) f.update(false) end},
		{"VR", function(f) f.services.VRService.VREnabled = true; f.update() end},
		{"camera takeover", function(f) f.camera.CameraType = "Scriptable"; f.update() end},
		{"spectating", function(f) f.camera.CameraSubject = {}; f.update() end},
		{"death", function(f) f.humanoid.Health = 0; f.update() end},
		{"ragdoll", function(f) f.character.attributes = {Ragdolled = true}; f.update() end},
		{"unequip", function(f) f.tool.Parent = nil; f.update() end},
	}) do
		test(case[1] .. " clears inspect without retaining the hidden hold", function()
			local f = viewmodelFixture(); f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
			f.update(true, false, false, 0.5); case[2](f)
			assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool)
				and not f.model() and f.handle.LocalTransparencyModifier == 0 and #f.warnings == 0)
			f.view.Clear()
		end)
	end
	test("actual knife motion shares inspect and instantly yields to held charge", function()
		local f = viewmodelFixture(); local knifeConfig = load("KnifeConfig")
		local knifeMotion = load("KnifeMotion", {CFrame = Frame, Vector3 = Vector,
			script = {Parent = {RevolverViewmodelMath = "Shared"}}, require = function(name) assert(name == "Shared"); return Motion end})
		f.tuning = {FirstPerson = knifeConfig.FirstPerson, Pose = {R6RotationOffset = knifeConfig.FirstPerson.R6RotationOffset}}
		f.view = f.factory.New({Name = "RevolverFirstPerson", Motion = knifeMotion, InspectKind = "Knife"})
		f.update(true, false, false, 0.25); assert(f.view.StartInspect(f.tool))
		for _ = 1, 60 do f.update() end
		assert(f.view.IsInspecting(f.tool) and f.model() and #f.warnings == 0)
		f.action = {holdingCharge = true, charging = true, charge = 1}; f.update()
		assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
		for _ = 1, 90 do f.update() end
		local arm = f.model():FindFirstChild("Right Arm")
		assert(arm.CFrame.Position.Y > 0, "full charge must retain its raised knife pose")
		assert(f.view.IsActive(f.tool) and #f.warnings == 0); f.view.Clear()
	end)
	test("knife presenter holds a visible forward stab and blocks inspection for its configurable duration", function()
		local f = viewmodelFixture(); local knifeConfig = load("KnifeConfig")
		local knifeMotion = load("KnifeMotion", {CFrame = Frame, Vector3 = Vector,
			script = {Parent = {RevolverViewmodelMath = "Shared"}}, require = function() return Motion end})
		local settings = table.clone(knifeConfig.FirstPerson); settings.StabSeconds = 0.6
		f.tuning = {FirstPerson = settings, Pose = {R6RotationOffset = settings.R6RotationOffset}}
		f.view = f.factory.New({Name = "RevolverFirstPerson", Motion = knifeMotion, InspectKind = "Knife"})
		for _ = 1,120 do f.update() end
		local model = assert(f.model()); local arm = model:FindFirstChild("Right Arm")
		local originalArm, originalHandle = arm.CFrame, f.handle.CFrame
		assert(f.view.StartInspect(f.tool))
		f.action = {stabElapsed = settings.StabSeconds * 0.5}; f.update()
		assert(not f.view.IsInspecting(f.tool) and not f.view.StartInspect(f.tool))
		assert(arm.CFrame.Position.Z - originalArm.Position.Z < -1.3)
		local held = arm.CFrame
		f.bodyAnimation = Frame.Angles(0.7,-0.4,0); f.armAnimation = Frame.Angles(-1.2,0.5,0.3)
		f.root.AssemblyLinearVelocity = V(32,0,0); f.action.stabElapsed = settings.StabSeconds * 0.55; f.update()
		near((arm.CFrame.Position-held.Position).Magnitude,0)
		for index=1,9 do near(arm.CFrame.matrix[index],held.matrix[index]) end
		local copyHandle = model:FindFirstChild("Handle",true)
		local copyBlade = model:FindFirstChild("Barrel",true)
		near(((copyHandle.CFrame:Inverse()*copyBlade.CFrame).Position
			-(f.handle.CFrame:Inverse()*f.barrel.CFrame).Position).Magnitude,0)
		assert(f.handle.CFrame == originalHandle and f.humanoid.WalkSpeed == 16)
		f.action.stabElapsed = 0.5; f.update(); assert(not f.view.StartInspect(f.tool))
		f.action.stabElapsed = settings.StabSeconds; f.update(); assert(f.view.StartInspect(f.tool))
		assert(#f.warnings == 0); f.view.Clear()
	end)
	test("canceling an extended knife through menu or unequip cannot carry its attack into the next hold", function()
		for _, exit in ipairs({"menu","unequip"}) do
			local f = viewmodelFixture(); local knifeConfig = load("KnifeConfig")
			local knifeMotion = load("KnifeMotion", {CFrame = Frame, Vector3 = Vector,
				script = {Parent = {RevolverViewmodelMath = "Shared"}}, require = function() return Motion end})
			f.tuning = {FirstPerson = knifeConfig.FirstPerson, Pose = {R6RotationOffset = knifeConfig.FirstPerson.R6RotationOffset}}
			f.view = f.factory.New({Name = "RevolverFirstPerson", Motion = knifeMotion, InspectKind = "Knife"})
			f.update(); f.action = {stabElapsed = knifeConfig.FirstPerson.StabSeconds*0.5}; f.update()
			local extended = assert(f.model()); assert(extended:FindFirstChild("Right Arm").CFrame.Position.Z < -2)
			if exit == "menu" then f.update(false) else f.tool.Parent = nil; f.update() end
			assert(not f.model() and f.handle.LocalTransparencyModifier == 0)
			if exit == "unequip" then assert(extended.destroyed); f.tool.Parent = f.character end
			f.action = {}; f.update()
			near(assert(f.model()):FindFirstChild("Right Arm").CFrame.Position.Z,knifeConfig.FirstPerson.ArmPosition[3])
			assert(#f.warnings == 0); f.view.Clear()
			assert(f.handle.Changed:Count() == 0 and f.tool.DescendantAdded:Count() == 0)
		end
	end)
	test("independent shared presenters release their own model listeners and character visibility", function()
		local old = viewmodelFixture(); old.update(); local oldModel = assert(old.model())
		local nextAvatar = viewmodelFixture()
		old.player.Character, old.env.workspace.CurrentCamera = nextAvatar.character, nextAvatar.camera
		local knife = old.factory.New({Name = "KnifeFirstPerson", Motion = Motion})
		knife.Update(nextAvatar.tool, nextAvatar.tuning, true, false, false, 1/60)
		old.flushBuilds(); knife.Update(nextAvatar.tool, nextAvatar.tuning, true, false, false, 1/60)
		local nextModel = assert(nextAvatar.camera:FindFirstChild("KnifeFirstPerson"))
		old.view.Clear()
		assert(oldModel.destroyed and not nextModel.destroyed and knife.IsActive(nextAvatar.tool))
		assert(old.handle.LocalTransparencyModifier == 0 and nextAvatar.handle.LocalTransparencyModifier == 1)
		knife.Clear()
		assert(nextModel.destroyed and nextAvatar.handle.LocalTransparencyModifier == 0
			and old.handle.Changed:Count() == 0 and nextAvatar.handle.Changed:Count() == 0)
	end)
	test("a temporary hidden weapon baseline can transfer back to visible without revealing its active copy", function()
		local f = viewmodelFixture(); f.handle.LocalTransparencyModifier = 1; f.update()
		assert(f.view.GetOriginalTransparency(f.handle) == 1)
		f.view.SetOriginalTransparency(f.handle, 0)
		assert(f.view.GetOriginalTransparency(f.handle) == 0 and f.handle.LocalTransparencyModifier == 1)
		f.camera.Focus = Frame.new(0, 0, -1); f.update()
		assert(f.handle.LocalTransparencyModifier == 0 and not f.model())
		f.view.SetOriginalTransparency(f.handle, 0.5) -- inactive setter owns no mask
		assert(f.handle.LocalTransparencyModifier == 0)
		f.view.Clear()
	end)
	test("first-person camera probe works before building and respects real camera ownership", function()
		local f = viewmodelFixture(); f.services.ReplicatedStorage:SetAttribute(Config.FirstPersonPhysics.ReadyAttribute, false)
		assert(f.view.IsFirstPerson(f.tool, f.tuning) and not f.view.IsActive(f.tool) and not f.model())
		f.update(); assert(not f.model())
		f.camera.Focus = Frame.new(0, 0, -1); assert(not f.view.IsFirstPerson(f.tool, f.tuning))
		f.camera.Focus = Frame.new(0, 0, -0.5); f.camera.CameraSubject = geometryObject("Humanoid")
		assert(not f.view.IsFirstPerson(f.tool, f.tuning))
		f.camera.CameraSubject = f.humanoid; f.services.VRService.VREnabled = true
		assert(not f.view.IsFirstPerson(f.tool, f.tuning))
		f.services.VRService.VREnabled = false; f.humanoid.Health = 0
		assert(not f.view.IsFirstPerson(f.tool, f.tuning))
		f.view.Clear()
	end)
	test("viewmodel snapshots avatar arms, shirt, body mesh and gun skin with safe geometry", function()
		local f = viewmodelFixture()
		geometryObject("Shirt", "Shirt", f.character).ShirtTemplate = "shirt-texture"
		geometryObject("CharacterMesh", "ArmMesh", f.character)
		geometryObject("SpecialMesh", "CustomArm", f.right)
		geometryObject("LocalScript", "EquipScript", f.tool)
		geometryObject("ModuleScript", "State", f.handle)
		geometryObject("BallSocketConstraint", "Physics", f.barrel)
		geometryObject("Sound", "GunSound", f.handle)
		geometryObject("PointLight", "Light", f.handle)
		geometryObject("ParticleEmitter", "Smoke", f.handle).Enabled = true
		f.update(); local model = assert(f.model())
		assert(model:FindFirstChild("Shirt").ShirtTemplate == "shirt-texture" and model:FindFirstChild("ArmMesh"))
		assert(model:FindFirstChild("Right Arm"):FindFirstChild("CustomArm"))
		assert(model:FindFirstChild("Barrel", true).TextureID == "skin-texture")
		for _, part in ipairs(model:GetDescendants()) do
			assert(not part:IsA("LuaSourceContainer") and not part:IsA("JointInstance") and not part:IsA("Constraint") and not part:IsA("Sound"))
			if part:IsA("BasePart") then assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery and not part.CastShadow) end
		end
		assert(not model:FindFirstChild("Smoke", true) and not model:FindFirstChild("Light", true))
		assert(f.handle:FindFirstChild("Smoke").LocalTransparencyModifier == 1 and f.handle:FindFirstChild("Light").Brightness == 0)
		assert(model:FindFirstChild("Humanoid").EvaluateStateMachine == false)
		assert(f.right.LocalTransparencyModifier == 1 and f.handle.LocalTransparencyModifier == 1 and #f.warnings == 0)
		f.view.Clear()
	end)
	test("the hidden real gun masks textures and decals independently while its camera skin stays visible", function()
		local f = viewmodelFixture()
		local texture, decal = geometryObject("Texture", "SkinFace", f.barrel), geometryObject("Decal", "SkinLogo", f.handle)
		texture.Transparency, texture.LocalTransparencyModifier, decal.LocalTransparencyModifier = 0.25, 0.3, 0.1
		f.update(); local model, reads = assert(f.model()), f.tool.descendantReads
		local copy = model:FindFirstChild("SkinFace", true)
		assert(texture.LocalTransparencyModifier == 1 and decal.LocalTransparencyModifier == 1)
		assert(copy.LocalTransparencyModifier == 0 and copy.Transparency == 0.25)
		texture.LocalTransparencyModifier = 0.4; texture.Transparency = 0.5
		assert(texture.LocalTransparencyModifier == 1 and copy.Transparency == 0.5)
		for _ = 1, 300 do f.update() end
		assert(f.model() == model and f.tool.descendantReads == reads)
		f.camera.Focus = Frame.new(0, 0, -1); f.update()
		assert(texture.LocalTransparencyModifier == 0.4 and decal.LocalTransparencyModifier == 0.1)
		f.view.Clear(); assert(texture.Changed:Count() == 0 and decal.Changed:Count() == 0)
	end)
	test("fallback texture hiding never mirrors its hidden transparency onto the camera skin", function()
		local f = viewmodelFixture(); local texture = geometryObject("Texture", "LegacyTexture", f.handle)
		texture.noLocalModifier, texture.Transparency = true, 0.2
		f.update(); local copy = f.model():FindFirstChild("LegacyTexture", true)
		assert(texture.Transparency == 1 and copy.Transparency == 0.2)
		texture.Transparency = 0.6
		assert(texture.Transparency == 1 and copy.Transparency == 0.6)
		f.update(false); assert(texture.Transparency == 0.6 and copy.Transparency == 0.6)
		f.update(); assert(texture.Transparency == 1 and copy.Transparency == 0.6)
		f.view.Clear(); assert(texture.Transparency == 0.6 and texture.Changed:Count() == 0)
	end)
	test("texture masks restore on every weapon lifecycle exit and late faces are also hidden", function()
		for _, exit in ipairs({"menu", "unequip", "death", "respawn"}) do
			local f = viewmodelFixture(); f.update()
			local texture = geometryObject("Texture", "LateFace", f.handle); texture.LocalTransparencyModifier = 0.2
			f.tool.DescendantAdded:Fire(texture); f.update()
			assert(texture.LocalTransparencyModifier == 1 and f.model():FindFirstChild("LateFace", true).LocalTransparencyModifier == 0)
			if exit == "unequip" then f.tool.Parent = nil
			elseif exit == "death" then f.humanoid.Health = 0
			elseif exit == "respawn" then f.player.Character = geometryObject("Model", "Replacement") end
			f.update(exit ~= "menu")
			assert(texture.LocalTransparencyModifier == 0.2 and not f.model())
			f.view.Clear(); assert(texture.Changed:Count() == 0)
		end
	end)
	test("knife throw hiding includes the camera weapon's face textures and restores its skin after return", function()
		local f = viewmodelFixture(); local texture = geometryObject("Texture", "BladeSkin", f.barrel)
		texture.Transparency = 0.2
		f.update(); local copy = f.model():FindFirstChild("BladeSkin", true)
		f.weaponVisible = false; f.update()
		assert(copy.LocalTransparencyModifier == 1 and f.model():FindFirstChild("Right Arm").LocalTransparencyModifier == 0)
		texture.Transparency = 0.5; assert(copy.Transparency == 0.5 and copy.LocalTransparencyModifier == 1)
		f.weaponVisible = true; f.update()
		assert(copy.LocalTransparencyModifier == 0 and copy.Transparency == 0.5)
		f.view.Clear(); assert(texture.LocalTransparencyModifier == 0 and texture.Changed:Count() == 0)
	end)
	test("deferred fallback texture masks preserve authored opacity and release all listeners", function()
		local f = viewmodelFixture(); local texture = geometryObject("Texture", "DeferredFace", f.barrel)
		texture.noLocalModifier, texture.Transparency = true, 0.2
		local changed, dispatch, queue = texture.Changed, texture.Changed.Fire, {}
		function changed:Fire(property) table.insert(queue, property) end
		local function flush() while #queue > 0 do dispatch(changed, table.remove(queue, 1)) end end
		f.update(); flush(); assert(f.model():FindFirstChild("DeferredFace", true).Transparency == 0.2)
		texture.Transparency = 0.7; f.update(); flush()
		assert(texture.Transparency == 1 and f.model():FindFirstChild("DeferredFace", true).Transparency == 0.7)
		f.view.Clear(); flush(); assert(texture.Transparency == 0.7 and changed:Count() == 0)
	end)
	test("first-person arms use configured thickness without changing length, avatar or gun grip", function()
		local f = viewmodelFixture(); local mesh = geometryObject("SpecialMesh", "ArmMesh", f.right)
		mesh.Scale, mesh.Offset = V(1.2, 1.1, 0.9), V(0.1, 0.2, 0.3)
		local block = geometryObject("BlockMesh", "Block", f.left); block.Scale = V(1.1, 0.9, 1.2)
		f.right.Size = V(1.2, 2.4, 1.1)
		local size, scale, offset, grip = f.right.Size, mesh.Scale, mesh.Offset, f.grip.C0
		f.update(); local arm = f.model():FindFirstChild("Right Arm")
		local thickness = f.tuning.FirstPerson.ArmThicknessScale
		near(arm.Size.X, size.X * thickness); near(arm.Size.Y, size.Y); near(arm.Size.Z, size.Z * thickness)
		local copy = arm:FindFirstChild("ArmMesh")
		near(copy.Scale.X, scale.X * thickness); near(copy.Scale.Y, scale.Y); near(copy.Scale.Z, scale.Z * thickness)
		near(copy.Offset.X, offset.X * thickness); near(copy.Offset.Y, offset.Y); near(copy.Offset.Z, offset.Z * thickness)
		assert(f.model():FindFirstChild("Left Arm"):FindFirstChild("Block").Scale == block.Scale)
		assert(f.right.Size == size and mesh.Scale == scale and mesh.Offset == offset and f.grip.C0 == grip)
		local gun = f.view.GetVisualTool(f.tool):FindFirstChild("Handle")
		near((gun.CFrame.Position - (arm.CFrame * f.grip.C0 * f.grip.C1:Inverse()).Position).Magnitude, 0)
		f.view.Clear()
	end)
	local function addSkinEffects(f)
		local first = geometryObject("Attachment", "EffectStart", f.handle)
		local last = geometryObject("Attachment", "EffectEnd", f.barrel)
		local particles = geometryObject("ParticleEmitter", "SkinParticles", first)
		particles.Rate, particles.LocalTransparencyModifier = 25, 0.25
		local beam = geometryObject("Beam", "SkinBeam", f.handle); beam.Attachment0, beam.Attachment1 = first, last
		local trail = geometryObject("Trail", "SkinTrail", f.barrel); trail.Attachment0, trail.Attachment1 = first, last
		local light = geometryObject("PointLight", "SkinLight", f.handle); light.Shadows = true
		return {first = first, last = last, particles = particles, beam = beam, trail = trail, light = light}
	end
	test("camera weapon contains no skin VFX and original effects are locally masked", function()
		local f = viewmodelFixture(); local skin = addSkinEffects(f); f.update()
		local weapon = f.view.GetVisualTool(f.tool)
		for _, name in ipairs({"SkinParticles", "SkinBeam", "SkinTrail", "SkinLight"}) do assert(not weapon:FindFirstChild(name, true)) end
		assert(weapon:FindFirstChild("EffectStart", true) ~= skin.first and weapon:FindFirstChild("EffectEnd", true) ~= skin.last)
		assert(skin.particles.LocalTransparencyModifier == 1 and skin.particles.Rate == 0)
		assert(skin.beam.LocalTransparencyModifier == 1 and skin.trail.LocalTransparencyModifier == 1)
		assert(skin.light.Brightness == 0 and skin.light.Shadows)
		assert(skin.particles.clearCount == 1 and skin.trail.clearCount == 1)
		local external = geometryObject("Attachment", "OtherCharacterAttachment")
		skin.beam.Attachment1 = external; assert(skin.beam.Attachment1 == external)
		f.view.Clear()
	end)
	test("skin effects stay suppressed while latest authored values are restored without scans or rebuilds", function()
		local f = viewmodelFixture(); local skin = addSkinEffects(f); f.update()
		local model, reads = f.model(), f.tool.descendantReads
		local weapon = f.view.GetVisualTool(f.tool)
		local endpoint = weapon:FindFirstChild("EffectEnd", true)
		skin.particles.Rate = 40; skin.particles.Texture = "new-texture"; skin.particles.Enabled = false
		assert(skin.particles.Rate == 0 and skin.particles.LocalTransparencyModifier == 1)
		skin.light.Brightness = 3; skin.light.Enabled = false
		assert(skin.light.Brightness == 0)
		skin.last.Position = V(0, 0.2, -1); assert(endpoint.Position == skin.last.Position)
		for _ = 1, 240 do f.update() end
		assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
		assert(not weapon:FindFirstChild("SkinParticles", true) and not weapon:FindFirstChild("SkinLight", true))
		f.view.Clear()
		assert(skin.particles.Rate == 40 and skin.particles.Enabled == false and skin.light.Brightness == 3 and skin.light.Enabled == false)
		assert(skin.particles.Texture == "new-texture")
	end)
	test("zooming out restores original VFX and reentry reuses geometry while clearing original particles and trails", function()
		local f = viewmodelFixture(); local skin = addSkinEffects(f); f.update()
		local model = f.model()
		f.camera.Focus = Frame.new(0, 0, -1); f.update()
		assert(not f.model() and skin.particles.Rate == 25 and skin.particles.LocalTransparencyModifier == 0.25)
		assert(skin.beam.LocalTransparencyModifier == 0 and skin.trail.LocalTransparencyModifier == 0 and skin.light.Brightness == 2)
		assert(skin.particles.clearCount == 1 and skin.trail.clearCount == 1)
		f.camera.Focus = Frame.new(0, 0, -0.5); f.update()
		assert(f.model() == model and f.handle.cloneCount == 1 and skin.particles.Rate == 0)
		assert(skin.particles.clearCount == 2 and skin.trail.clearCount == 2)
		f.view.Clear()
		for _, source in pairs(skin) do assert(source.Changed:Count() == 0) end
		assert(skin.particles.Rate == 25 and skin.light.Brightness == 2)
	end)
	test("deferred suppression notifications preserve latest desired VFX values without adding copied effects", function()
		local f = viewmodelFixture(); local skin = addSkinEffects(f)
		local queue = {}
		for _, source in ipairs({skin.particles, skin.light}) do
			local changed, dispatch = source.Changed, source.Changed.Fire
			function changed:Fire(property) table.insert(queue, {signal = changed, dispatch = dispatch, property = property}) end
		end
		local function flush()
			while #queue > 0 do local event = table.remove(queue, 1); event.dispatch(event.signal, event.property) end
		end
		f.update(); flush()
		assert(f.model() and not f.model():FindFirstChild("SkinParticles", true) and not f.model():FindFirstChild("SkinLight", true))
		assert(skin.particles.Rate == 0 and skin.light.Brightness == 0)
		skin.particles.Rate = 60; skin.light.Brightness = 4; f.update(); flush()
		assert(skin.particles.Rate == 0 and skin.light.Brightness == 0)
		f.view.Clear(); flush()
		assert(skin.particles.Rate == 60 and skin.light.Brightness == 4)
	end)
	test("late VFX rebuild safely without copying effects or rejecting effects-heavy skins", function()
		local f = viewmodelFixture(); f.update(); local old = f.model()
		local particles = geometryObject("ParticleEmitter", "LateSkinParticles", f.handle)
		f.tool.DescendantAdded:Fire(particles); f.update()
		assert(old.destroyed and f.model() and not f.model():FindFirstChild("LateSkinParticles", true) and particles.LocalTransparencyModifier == 1)
		f.view.Clear(); assert(particles.Rate == 20 and particles.LocalTransparencyModifier == 0 and particles.Changed:Count() == 0)
		local oversized = viewmodelFixture(); local skin = addSkinEffects(oversized); oversized.tuning.FirstPerson.MaxSkinEffects = 0
		oversized.update(); assert(oversized.model() and #oversized.warnings == 0 and oversized.handle.cloneCount == 1)
		assert(skin.particles.Rate == 0 and skin.particles.LocalTransparencyModifier == 1 and skin.light.Brightness == 0)
		oversized.view.Clear()
	end)
	test("VFX suppression is released on menus unequip death and respawn without listener leaks", function()
		for _, action in ipairs({"menu", "unequip", "death", "respawn"}) do
			local f = viewmodelFixture(); local skin = addSkinEffects(f); f.update()
			if action == "unequip" then f.tool.Parent = nil
			elseif action == "death" then f.humanoid.Health = 0
			elseif action == "respawn" then f.player.Character = geometryObject("Model", "Respawn") end
			f.update(action ~= "menu")
			assert(not f.model() and skin.particles.Rate == 25 and skin.particles.LocalTransparencyModifier == 0.25)
			assert(skin.light.Brightness == 2 and skin.beam.LocalTransparencyModifier == 0)
			f.view.Clear()
			for _, source in pairs(skin) do assert(source.Changed:Count() == 0) end
		end
	end)
	test("all legacy Smoke Sparkles and Fire remain absent from the clone and restore supported source properties", function()
		local f = viewmodelFixture()
		local smoke = geometryObject("Smoke", "LegacySmoke", f.handle); smoke.noLocalModifier, smoke.Opacity = true, 0.7
		local sparkles = geometryObject("Sparkles", "LegacySparkles", f.handle); sparkles.noLocalModifier = true
		local fire = geometryObject("Fire", "LegacyFire", f.handle); fire.noLocalModifier = true
		f.update(); assert(f.model() and #f.warnings == 0)
		assert(not f.model():FindFirstChild("LegacySmoke", true) and not f.model():FindFirstChild("LegacySparkles", true) and not f.model():FindFirstChild("LegacyFire", true))
		assert(smoke.Opacity == 0 and not sparkles.Enabled and not fire.Enabled)
		f.view.Clear()
		assert(smoke.Opacity == 0.7 and sparkles.Enabled and fire.Enabled and smoke.Changed:Count() == 0 and sparkles.Changed:Count() == 0 and fire.Changed:Count() == 0)
	end)
	test("viewmodel preserves grip and multipart transforms without moving the live weapon", function()
		local f = viewmodelFixture(); local live = f.handle.CFrame
		f.update(); local model = assert(f.model()); local right = model:FindFirstChild("Right Arm")
		local handle, barrel = model:FindFirstChild("Handle", true), model:FindFirstChild("Barrel", true)
		local expected = right.CFrame * f.grip.C0 * f.grip.C1:Inverse()
		near((handle.CFrame.Position - expected.Position).Magnitude, 0)
		near((handle.CFrame:Inverse() * barrel.CFrame).Position.Z, -1)
		assert(f.handle.CFrame == live and f.view.GetVisualTool(f.tool) == model:FindFirstChild("Weapon"))
		f.view.Clear()
	end)
	test("weapon meshes and textures retain their authored parent offsets and scale", function()
		local f = viewmodelFixture()
		local mesh = geometryObject("SpecialMesh", "GunMesh", f.handle)
		mesh.Offset, mesh.Scale, mesh.TextureId = V(0.35, -0.2, 0.15), V(1.3, 0.9, 1.1), "mesh-skin"
		local texture = geometryObject("Texture", "Pattern", f.barrel)
		texture.Texture, texture.OffsetStudsU, texture.OffsetStudsV = "surface-skin", 0.35, -0.4
		local decal = geometryObject("Decal", "Logo", f.handle); decal.Texture = "logo-skin"
		local surface = geometryObject("SurfaceAppearance", "Finish", f.barrel); surface.ColorMap = "finish-skin"
		local offset = Frame.new(0.4, 0.1, -0.9) * Frame.Angles(0.1, 0.3, -0.2)
		f.barrel.CFrame = f.handle.CFrame * offset
		f.update(); local weapon = f.view.GetVisualTool(f.tool)
		local handle, barrel = weapon:FindFirstChild("Handle"), weapon:FindFirstChild("Barrel", true)
		local actual = handle.CFrame:Inverse() * barrel.CFrame
		near((actual.Position - offset.Position).Magnitude, 0)
		for i = 1, 9 do near(actual.matrix[i], offset.matrix[i]) end
		local copy = handle:FindFirstChild("GunMesh")
		assert(copy.Offset == mesh.Offset and copy.Scale == mesh.Scale and copy.TextureId == "mesh-skin")
		assert(barrel:FindFirstChild("Pattern").Parent == barrel and barrel:FindFirstChild("Pattern").Texture == "surface-skin")
		assert(handle:FindFirstChild("Logo").Parent == handle and barrel:FindFirstChild("Finish").Parent == barrel)
		assert(barrel:FindFirstChild("Pattern").OffsetStudsU == 0.35 and barrel:FindFirstChild("Pattern").OffsetStudsV == -0.4)
		f.view.Clear()
	end)
	test("late skin transform and appearance updates stay aligned without rebuilding or scanning descendants", function()
		local f = viewmodelFixture()
		local mesh = geometryObject("SpecialMesh", "GunMesh", f.handle)
		local texture = geometryObject("Texture", "Pattern", f.barrel)
		local decal = geometryObject("Decal", "Logo", f.handle)
		local surface = geometryObject("SurfaceAppearance", "Finish", f.barrel)
		f.update(); local model, reads = f.model(), f.tool.descendantReads
		local weapon = f.view.GetVisualTool(f.tool)
		local handle, barrel = weapon:FindFirstChild("Handle"), weapon:FindFirstChild("Barrel", true)
		mesh.Scale, mesh.Offset, mesh.TextureId = V(1.4, 0.8, 1.2), V(0.2, 0.4, -0.3), "settled-mesh"
		texture.Texture, texture.OffsetStudsU, decal.Texture, surface.ColorMap = "settled-skin", 0.6, "settled-logo", "settled-finish"
		f.barrel.TextureID, f.barrel.Transparency, f.barrel.Size = "new-barrel-skin", 0.3, V(0.4, 0.6, 1.7)
		local offset = Frame.new(-0.3, 0.4, -1.2) * Frame.Angles(-0.2, 0.5, 0.3)
		f.handle.CFrame = Frame.new(12, 9, -4) * Frame.Angles(0.2, -0.3, 0)
		f.barrel.CFrame = f.handle.CFrame * offset
		f.update()
		local actual = handle.CFrame:Inverse() * barrel.CFrame
		near((actual.Position - offset.Position).Magnitude, 0)
		for i = 1, 9 do near(actual.matrix[i], offset.matrix[i]) end
		assert(handle:FindFirstChild("GunMesh").Offset == mesh.Offset and handle:FindFirstChild("GunMesh").Scale == mesh.Scale)
		assert(handle:FindFirstChild("GunMesh").TextureId == "settled-mesh" and handle:FindFirstChild("Logo").Texture == "settled-logo")
		assert(barrel:FindFirstChild("Pattern").Texture == "settled-skin" and barrel:FindFirstChild("Pattern").OffsetStudsU == 0.6)
		assert(barrel:FindFirstChild("Finish").ColorMap == "settled-finish" and barrel.TextureID == "new-barrel-skin")
		assert(barrel.Transparency == 0.3 and barrel.Size == f.barrel.Size)
		for _ = 1, 240 do f.update() end
		assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
		f.view.Clear()
	end)
	test("dynamic avatar appearance keeps slender arms and releases every source listener", function()
		local f = viewmodelFixture(); local mesh = geometryObject("SpecialMesh", "ArmMesh", f.right)
		local shirt = geometryObject("Shirt", "Shirt", f.character)
		f.update(); local model = f.model(); local arm = model:FindFirstChild("Right Arm")
		local scale = f.tuning.FirstPerson.ArmThicknessScale
		f.right.Size, mesh.Scale, mesh.Offset = V(1.4, 2.3, 1.2), V(1.3, 1.1, 0.8), V(0.2, 0.3, 0.1)
		shirt.ShirtTemplate = "updated-shirt"
		near(arm.Size.X, 1.4 * scale); near(arm.Size.Y, 2.3); near(arm.Size.Z, 1.2 * scale)
		local copy = arm:FindFirstChild("ArmMesh")
		near(copy.Scale.X, 1.3 * scale); near(copy.Scale.Y, 1.1); near(copy.Scale.Z, 0.8 * scale)
		near(copy.Offset.X, 0.2 * scale); near(copy.Offset.Y, 0.3); near(copy.Offset.Z, 0.1 * scale)
		assert(model:FindFirstChild("Shirt").ShirtTemplate == "updated-shirt")
		assert(f.right.Changed:Count() == 1 and mesh.Changed:Count() == 1 and shirt.Changed:Count() == 1)
		f.view.Clear()
		assert(f.right.Changed:Count() == 0 and mesh.Changed:Count() == 0 and shirt.Changed:Count() == 0)
		assert(f.handle.Changed:Count() == 0 and f.barrel.Changed:Count() == 0 and model.destroyed)
	end)
	test("appearance synchronization ignores source physics and visibility ownership", function()
		local f = viewmodelFixture(); f.update(); local weapon = f.view.GetVisualTool(f.tool)
		local clone = weapon:FindFirstChild("Handle"); local frame = clone.CFrame
		f.handle.Anchored, f.handle.CanCollide, f.handle.CanTouch, f.handle.CanQuery, f.handle.Massless = false, true, true, true, false
		f.handle.CollisionGroup, f.handle.CastShadow, f.handle.LocalTransparencyModifier = "Default", true, 0.2
		f.handle.CFrame = Frame.new(100, 40, 60)
		assert(clone.Anchored and not clone.CanCollide and not clone.CanTouch and not clone.CanQuery and clone.Massless)
		assert(clone.CollisionGroup == Config.FirstPersonPhysics.CollisionGroup and not clone.CastShadow)
		assert(clone.LocalTransparencyModifier == 0 and clone.CFrame == frame)
		f.view.Clear()
	end)
	test("one-hand presentation and throw hiding keep the visible hand and cached geometry", function()
		local f = viewmodelFixture(); f.tuning.FirstPerson.SupportArmEnabled = false
		f.update(); local model = f.model(); local arm, left = model:FindFirstChild("Right Arm"), model:FindFirstChild("Left Arm")
		assert(arm.LocalTransparencyModifier == 0 and left.LocalTransparencyModifier == 1)
		f.weaponVisible = false; f.update()
		for _, part in ipairs(f.view.GetVisualTool(f.tool):GetDescendants()) do
			if part:IsA("BasePart") then assert(part.LocalTransparencyModifier == 1) end
		end
		assert(arm.LocalTransparencyModifier == 0 and f.model() == model)
		f.weaponVisible = true; f.update()
		for _, part in ipairs(f.view.GetVisualTool(f.tool):GetDescendants()) do
			if part:IsA("BasePart") then assert(part.LocalTransparencyModifier == 0) end
		end
		assert(f.handle.cloneCount == 1 and #f.warnings == 0)
		f.view.Clear()
	end)
	test("late texture and decal descendants rebuild once and preserve the correct surface parent", function()
		for _, class in ipairs({"Texture", "Decal"}) do
			local f = viewmodelFixture(); f.update(); local old = f.model()
			local surface = geometryObject(class, "LateSurface", f.barrel); surface.Texture = "late-skin"
			f.tool.DescendantAdded:Fire(surface); f.update()
			local barrel = f.view.GetVisualTool(f.tool):FindFirstChild("Barrel", true)
			assert(old.destroyed and barrel:FindFirstChild("LateSurface").Parent == barrel and barrel:FindFirstChild("LateSurface").Texture == "late-skin")
			for _ = 1, 20 do f.update() end
			assert(f.handle.cloneCount == 2 and #f.warnings == 0)
			f.view.Clear(); assert(surface.Changed:Count() == 0)
		end
	end)
	test("viewmodel collision mask prevents body contacts even if CanCollide is re-enabled after rendering", function()
		local setup = collisionFixture(); setup.setup.Init()
		local f = viewmodelFixture(); f.services.PhysicsService = setup.physics
		f.update(); local model = assert(f.model()); f.root.CanCollide, f.right.CanCollide, f.handle.CanCollide = true, true, true
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide, part.collisionRegistry = true, setup.physics
				assert(part.CollisionGroup == Config.FirstPersonPhysics.CollisionGroup)
				assert(not part:CanCollideWith(f.root) and not part:CanCollideWith(f.right) and not part:CanCollideWith(f.handle))
			end
		end
		f.view.Clear()
	end)
	test("viewmodel guard repairs altered physics flags using only cached parts", function()
		local f = viewmodelFixture(); f.update(); local model = assert(f.model())
		local parts = model:GetDescendants(); local reads = f.tool.descendantReads
		for _, part in ipairs(parts) do if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.Massless, part.CollisionGroup = false, true, true, true, false, "Default"
		end end
		model:FindFirstChild("Humanoid").EvaluateStateMachine = true
		f.update()
		for _, part in ipairs(parts) do if part:IsA("BasePart") then
			assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery and part.Massless)
			assert(part.CollisionGroup == Config.FirstPersonPhysics.CollisionGroup)
		end end
		assert(f.tool.descendantReads == reads and not model:FindFirstChild("Humanoid").EvaluateStateMachine)
		f.view.Clear()
	end)
	test("first-person waits for both server collision readiness and client group replication", function()
		local f = viewmodelFixture()
		f.services.ReplicatedStorage:SetAttribute(Config.FirstPersonPhysics.ReadyAttribute, false)
		for _ = 1, 20 do f.update() end
		assert(not f.model() and not f.handle.cloneCount and #f.warnings == 0)
		f.services.ReplicatedStorage:SetAttribute(Config.FirstPersonPhysics.ReadyAttribute, true)
		f.services.PhysicsService.IsCollisionGroupRegistered = function() return false end
		f.update(); assert(not f.model() and not f.handle.cloneCount)
		f.services.PhysicsService.IsCollisionGroupRegistered = function() return true end
		f.update(); local model = assert(f.model())
		f.services.ReplicatedStorage:SetAttribute(Config.FirstPersonPhysics.ReadyAttribute, false)
		f.update(); assert(not f.model() and not model.destroyed and f.right.LocalTransparencyModifier == 0)
		f.services.ReplicatedStorage:SetAttribute(Config.FirstPersonPhysics.ReadyAttribute, true)
		f.update(); assert(f.model() == model)
		f.view.Clear()
	end)
	test("first-person never clones live Humanoid body references or physics components", function()
		local f = viewmodelFixture()
		local torso = f.character:FindFirstChild("Torso")
		f.humanoid.Torso, f.humanoid.RootPart, f.humanoid.WalkToPart = torso, f.root, f.root
		f.humanoid.EvaluateStateMachine, f.humanoid.AutoRotate = true, true
		f.root.CFrame, f.root.AssemblyLinearVelocity, f.root.AssemblyAngularVelocity = Frame.new(10, 2, 20), V(1, 0, 2), V(0, 0.5, 0)
		local physical = {f.tool, f.humanoid, f.root, torso, f.grip}
		local rootJoint = geometryObject("Motor6D", "RootJoint", f.root)
		rootJoint.Part0, rootJoint.Part1 = f.root, torso; table.insert(physical, rootJoint)
		for _, class in ipairs({"BodyVelocity", "BodyPosition", "BodyGyro", "WeldConstraint", "NoCollisionConstraint", "LinearVelocity", "IKControl", "ObjectValue"}) do
			local item = geometryObject(class, class, f.handle)
			item.Part0, item.Part1, item.Value = f.root, f.right, f.root
			table.insert(physical, item)
		end
		local rootFrame, velocity, angular = f.root.CFrame, f.root.AssemblyLinearVelocity, f.root.AssemblyAngularVelocity
		f.update(); local model = assert(f.model())
		local hum = model:FindFirstChild("Humanoid")
		assert(hum ~= f.humanoid and not hum.Torso and not hum.RootPart and not hum.WalkToPart)
		for _, item in ipairs(physical) do assert(not item.cloneCount, item.Name .. " was cloned") end
		for _, item in ipairs(model:GetDescendants()) do
			assert(item.Part0 ~= f.root and item.Part1 ~= f.right and item.Value ~= f.root)
		end
		for i = 1, 120 do
			f.camera.CFrame = Frame.new(i, 2, i/2) * Frame.Angles(0.3, i/30, 0)
			f.camera.Focus = f.camera.CFrame * Frame.new(0, 0, -0.5)
			f.update(true, i > 60, false)
		end
		assert(f.root.CFrame == rootFrame and f.root.AssemblyLinearVelocity == velocity and f.root.AssemblyAngularVelocity == angular)
		assert(f.humanoid.EvaluateStateMachine and f.humanoid.AutoRotate and f.humanoid.RootPart == f.root)
		f.view.Clear(); assert(f.grip.Parent == f.right and f.grip.Part1 == f.handle)
	end)
	test("viewmodel parts and fresh Humanoid are inert before any camera parenting", function()
		local f = viewmodelFixture(); local renderHumanoids = 0
		geometryParentObserver = function(item, parent)
			if not parent then return end
			if item:IsA("Humanoid") and parent.Name == "RevolverFirstPerson" then
				assert(item.EvaluateStateMachine == false and item.RequiresNeck == false and item.AutoRotate == false)
				assert(item.WalkSpeed == 0 and item.JumpPower == 0 and item.JumpHeight == 0)
				assert(item.Torso ~= f.character:FindFirstChild("Torso") and item.RootPart ~= f.root)
				renderHumanoids += 1
			elseif parent == f.camera then
				for _, part in ipairs(item:GetDescendants()) do
					if part:IsA("BasePart") then
						assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery and part.Massless)
						near(part.AssemblyLinearVelocity.Magnitude, 0); near(part.AssemblyAngularVelocity.Magnitude, 0)
					end
				end
			end
		end
		local ok, errorMessage = pcall(f.update)
		geometryParentObserver = nil
		assert(ok, errorMessage); assert(f.model() and renderHumanoids == 1 and #f.warnings == 0)
		f.view.Clear()
	end)
	test("failed visual-only cloning restores both included and excluded Archivable flags", function()
		local f = viewmodelFixture(); f.tool.Archivable, f.barrel.Archivable = false, false
		f.handle.Archivable = false
		local script = geometryObject("LocalScript", "LiveEquipScript", f.handle); script.Archivable = true
		local mesh = geometryObject("SpecialMesh", "Skin", f.handle); mesh.Archivable = false
		f.handle.cloneFailure = true
		f.update()
		assert(not f.model() and #f.warnings == 1 and not f.tool.Archivable and not f.barrel.Archivable and script.Archivable)
		assert(not f.handle.Archivable and not mesh.Archivable)
		assert(f.handle.LocalTransparencyModifier == 0 and f.right.LocalTransparencyModifier == 0)
	end)
	test("viewmodel reuses one snapshot without descendant scans across 240 frames", function()
		local f = viewmodelFixture(); f.update(); local model, reads = f.model(), f.tool.descendantReads
		for _ = 1, 240 do f.update() end
		assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
		assert(f.tool.DescendantAdded:Count() == 1 and f.character.DescendantAdded:Count() == 1 and #f.warnings == 0)
		f.view.Clear()
		assert(model.destroyed and f.tool.DescendantAdded:Count() == 0 and f.character.DescendantRemoving:Count() == 0)
	end)
	test("zooming out restores original visibility and reentering reuses the cached model", function()
		local f = viewmodelFixture(); f.handle.LocalTransparencyModifier = 0.25
		f.update(); local model = f.model()
		f.camera.Focus = Frame.new(0, 0, -0.56); f.update(); assert(f.model() == model)
		f.camera.Focus = Frame.new(0, 0, -0.7); f.update()
		assert(not f.model() and not model.destroyed and not f.view.GetVisualTool(f.tool))
		near(f.handle.LocalTransparencyModifier, 0.25); near(f.right.LocalTransparencyModifier, 0)
		f.camera.Focus = Frame.new(0, 0, -1); f.update(); assert(not f.model())
		f.camera.Focus = Frame.new(0, 0, -0.5); f.update(); assert(f.model() == model and f.handle.cloneCount == 1)
		f.view.Clear()
	end)
	test("menus, VR and camera takeover suspend the viewmodel without cloning again", function()
		local f = viewmodelFixture(); f.update(); local model = f.model()
		f.update(false); assert(not f.model() and f.handle.LocalTransparencyModifier == 0)
		f.update(); assert(f.model() == model)
		f.services.VRService.VREnabled = true; f.update(); assert(not f.model())
		f.services.VRService.VREnabled = false; f.camera.CameraType = "Scriptable"; f.update(); assert(not f.model())
		f.camera.CameraType = "Custom"; f.camera.CameraSubject = {}; f.update(); assert(not f.model())
		f.camera.CameraSubject = f.humanoid; f.update(); assert(f.model() == model and f.handle.cloneCount == 1)
		f.view.Clear()
	end)
	test("death, ragdoll, unequip and respawn destroy models and release visibility", function()
		for _, action in ipairs({"death", "ragdoll", "unequip", "respawn"}) do
			local f = viewmodelFixture(); f.update(); local model = f.model()
			if action == "death" then f.humanoid.Health = 0
			elseif action == "ragdoll" then f.character.attributes = {Ragdolled = true}
			elseif action == "unequip" then f.tool.Parent = nil
			else f.player.Character = geometryObject("Model", "Respawn") end
			f.update(); assert(model.destroyed and not f.view.GetVisualTool(f.tool))
			assert(f.right.LocalTransparencyModifier == 0 and f.tool.DescendantAdded:Count() == 0)
		end
	end)
	test("replacing a destroyed camera rebuilds the local hold without losing visibility ownership", function()
		local f = viewmodelFixture(); f.update(); local original = f.model()
		local nextCamera = geometryObject("Camera", "ReplacementCamera")
		nextCamera.CFrame, nextCamera.Focus = Frame.new(0, 2, 0), Frame.new(0, 2, -0.5)
		nextCamera.CameraType, nextCamera.CameraSubject = "Custom", f.humanoid
		f.camera:Destroy(); f.camera = nextCamera; f.env.workspace.CurrentCamera = nextCamera
		f.update()
		assert(original.destroyed and f.model() and f.handle.cloneCount == 2 and #f.warnings == 0)
		assert(f.handle.LocalTransparencyModifier == 1)
		f.view.Clear(); assert(f.handle.LocalTransparencyModifier == 0)
	end)
	local function gripFixture(kind)
		local f = viewmodelFixture()
		if kind == "knife" then
			local config = load("KnifeConfig")
			local motion = load("KnifeMotion", {CFrame = Frame, Vector3 = Vector,
				script = {Parent = {RevolverViewmodelMath = "Shared"}}, require = function() return Motion end})
			f.tuning = {FirstPerson = config.FirstPerson, Pose = {R6RotationOffset = config.FirstPerson.R6RotationOffset}}
			f.view = f.factory.New({Name = "RevolverFirstPerson", Motion = motion, InspectKind = "Knife"})
		end
		return f
	end
	local function assertGrip(f, transform)
		local arm, gun = f.model():FindFirstChild("Right Arm"), f.view.GetVisualTool(f.tool):FindFirstChild("Handle")
		local expected = arm.CFrame * f.grip.C0 * (transform or Frame.identity) * f.grip.C1:Inverse()
		near((gun.CFrame.Position - expected.Position).Magnitude, 0)
		for i = 1, 9 do near(gun.CFrame.matrix[i], expected.matrix[i]) end
	end
	for _, kind in ipairs({"revolver", "knife"}) do
		test(kind .. " waits for a real RightGrip instead of publishing a guessed upward hold", function()
			local f = gripFixture(kind); f.grip.Parent = nil
			for _ = 1, 20 do f.update() end
			assert(not f.model() and not f.handle.cloneCount and f.handle.LocalTransparencyModifier == 0)
			f.grip.Parent = f.right; f.character.DescendantAdded:Fire(f.grip)
			for _ = 1, 12 do f.update() end
			assert(f.model() and f.handle.cloneCount == 1 and #f.warnings == 0)
			assertGrip(f); f.view.Clear()
		end)
		test(kind .. " recovers when existing grip part references replicate after its parent", function()
			local f = gripFixture(kind); f.grip.Part0, f.grip.Part1 = nil, nil
			for _ = 1, 12 do f.update() end
			assert(not f.model() and not f.handle.cloneCount)
			f.grip.Part0 = f.right
			for _ = 1, 12 do f.update() end
			assert(not f.model() and f.handle.LocalTransparencyModifier == 0)
			f.grip.Part1 = f.handle -- no DescendantAdded event for property replication
			for _ = 1, 12 do f.update() end
			assertGrip(f); assert(f.handle.cloneCount == 1 and #f.warnings == 0); f.view.Clear()
		end)
		test(kind .. " follows settled grip position and rotation without rebuilding or world pose feedback", function()
			local f = gripFixture(kind); f.update()
			local model, reads, live = f.model(), f.tool.descendantReads, f.handle.CFrame
			f.tool.Grip = Frame.new(0.2, 0.1, -0.3) * Frame.Angles(0.3, -0.4, 0.5)
			f.grip.C0 = Frame.new(0.1, -0.85, 0.2) * Frame.Angles(-0.2, 0.3, -0.1)
			f.grip.C1 = f.tool.Grip
			for _, pitch in ipairs({-1.5, 0, 1.5}) do
				f.camera.CFrame = Frame.new(10, 20, -5) * Frame.Angles(pitch, 0.7, 0)
				f.camera.Focus = f.camera.CFrame * Frame.new(0, 0, -0.5)
				f.update(); assertGrip(f)
			end
			assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
			assert(f.handle.CFrame == live and #f.warnings == 0); f.view.Clear()
		end)
		test(kind .. " suspends an invalid grip and resumes the same complete camera model", function()
			local f = gripFixture(kind); f.update(true, false, false, 0.25)
			local model, reads = f.model(), f.tool.descendantReads
			assert(f.view.StartInspect(f.tool))
			f.grip.Part1 = geometryObject("Part", "OtherHandle", f.character)
			f.update()
			assert(not f.model() and not f.view.IsActive(f.tool) and not f.view.IsInspecting(f.tool))
			assert(f.handle.LocalTransparencyModifier == 0 and f.right.LocalTransparencyModifier == 0)
			f.grip.Part1 = f.handle; f.update()
			assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
			assertGrip(f); assert(#f.warnings == 0); f.view.Clear()
		end)
		test(kind .. " follows a replacement animated grip without cloning or retaining the old joint", function()
			local f = gripFixture(kind); f.update()
			local model, reads, old = f.model(), f.tool.descendantReads, f.grip
			old.Parent = nil; f.character.DescendantRemoving:Fire(old); f.update()
			assert(not f.model() and f.handle.LocalTransparencyModifier == 0)
			f.grip = geometryObject("Motor6D", "RightGrip", f.right)
			f.grip.Part0, f.grip.Part1 = f.right, f.handle
			f.grip.C0, f.grip.C1 = Frame.new(0, -1, 0), Frame.Angles(-math.pi/2, 0, 0)
			f.grip.Transform = Frame.new(0.1, 0.2, 0) * Frame.Angles(0.25, -0.15, 0.1)
			f.character.DescendantAdded:Fire(f.grip); f.update(); assertGrip(f, f.grip.Transform)
			f.grip.Transform = Frame.Angles(-0.4, 0.2, -0.1); f.update(); assertGrip(f, f.grip.Transform)
			assert(f.model() == model and f.handle.cloneCount == 1 and f.tool.descendantReads == reads)
			assert(not old.cloneCount and not f.grip.cloneCount and #f.warnings == 0); f.view.Clear()
		end)
	end
	test("new skin pieces rebuild once and nonarchivable source flags are restored", function()
		local f = viewmodelFixture(); f.tool.Archivable, f.barrel.Archivable = false, false
		f.update(); local model = f.model(); assert(model and not f.tool.Archivable and not f.barrel.Archivable)
		local piece = geometryObject("MeshPart", "NewSkinPiece", f.tool)
		f.tool.DescendantAdded:Fire(piece); f.update()
		assert(model.destroyed and f.model():FindFirstChild("NewSkinPiece", true))
		for _ = 1, 20 do f.update() end
		assert(f.handle.cloneCount == 2 and not f.tool.Archivable and not f.barrel.Archivable)
		f.view.Clear()
	end)
	test("oversized weapons report once and leave the live gun visible during bounded retries", function()
		local f = viewmodelFixture(); f.tuning.FirstPerson.MaxWeaponParts = 1
		for _ = 1, 100 do f.update() end
		assert(not f.model() and f.handle.LocalTransparencyModifier == 0 and #f.warnings == 1 and not f.tool.cloneCount)
		f.view.Clear()
	end)
	test("late arms and a late Handle recover automatically without unequipping", function()
		for _, name in ipairs({"left", "handle"}) do
			local f = viewmodelFixture(); local missing, parent = f[name], f[name].Parent
			missing.Parent = nil
			for _ = 1, 20 do f.update() end
			assert(not f.model() and f.right.LocalTransparencyModifier == 0 and #f.warnings == 0)
			missing.Parent = parent
			for _ = 1, 12 do f.update() end
			assert(f.model() and f.view.GetVisualTool(f.tool) and #f.warnings == 0)
			assert(f.handle.LocalTransparencyModifier == 1 and f.right.LocalTransparencyModifier == 1)
			f.view.Clear()
		end
	end)
	test("transient cloning failure recovers on the same equip and never exposes a partial model", function()
		local f = viewmodelFixture(); f.handle.cloneFailure = true
		for _ = 1, 20 do f.update() end
		assert(not f.model() and f.handle.LocalTransparencyModifier == 0 and f.right.LocalTransparencyModifier == 0)
		assert(#f.warnings == 1)
		f.handle.cloneFailure = false
		for _ = 1, 60 do f.update() end
		assert(f.model() and f.handle.cloneCount == 1 and #f.warnings == 1)
		f.view.Clear()
	end)
	test("persistent build errors back off and warning output stays bounded", function()
		local f = viewmodelFixture(); f.handle.cloneFailure = true
		local create, attempts = f.geometry.Create, 0
		f.geometry.Create = function(...) attempts += 1; return create(...) end
		for _ = 1, 600 do f.update() end
		assert(attempts > 5 and attempts < 20 and #f.warnings == 1)
		assert(not f.model() and f.right.LocalTransparencyModifier == 0)
		f.view.Clear()
	end)
	test("placement errors also back off, clean up snapshots and recover after the fault clears", function()
		local f = viewmodelFixture(); local place = f.geometry.Place
		f.geometry.Place = function() error("temporary placement failure") end
		for _ = 1, 600 do f.update() end
		assert(f.handle.cloneCount > 5 and f.handle.cloneCount < 20 and #f.warnings == 1)
		assert(not f.model() and f.right.LocalTransparencyModifier == 0 and f.handle.LocalTransparencyModifier == 0)
		assert(f.tool.DescendantAdded:Count() == 0 and f.character.DescendantAdded:Count() == 0)
		f.geometry.Place = place
		for _ = 1, 90 do f.update() end
		assert(f.model() and f.handle.LocalTransparencyModifier == 1 and #f.warnings == 1)
		f.view.Clear()
	end)
	test("unequipping cancels a failed build cooldown so the next equip is immediate", function()
		local f = viewmodelFixture(); f.handle.cloneFailure = true
		for _ = 1, 100 do f.update() end
		assert(not f.model())
		f.tool.Parent = nil; f.update()
		f.handle.cloneFailure = false; f.tool.Parent = f.character; f.update()
		assert(f.model() and f.handle.cloneCount == 1 and #f.warnings == 1)
		f.view.Clear()
	end)
	test("repeated equip and unequip always publishes a complete hold and restores originals", function()
		local f = viewmodelFixture()
		for _ = 1, 30 do
			f.tool.Parent = f.character; f.update(); assert(f.model() and f.view.GetVisualTool(f.tool))
			local model = f.model()
			f.tool.Parent = nil; f.update()
			assert(model.destroyed and not f.model() and f.right.LocalTransparencyModifier == 0 and f.handle.LocalTransparencyModifier == 0)
		end
		assert(#f.warnings == 0 and f.handle.cloneCount == 30)
		f.view.Clear()
	end)
	test("crouch and slide pose moves both arms while keeping the weapon on its grip", function()
		local f = viewmodelFixture()
		for _ = 1, 120 do f.update() end
		local model = f.model(); local right, left = model:FindFirstChild("Right Arm"), model:FindFirstChild("Left Arm")
		local standing, shoulder = right.CFrame.Position, left.CFrame.Position
		f.bodyAnimation = Frame.new(0, -0.5, 0) * Frame.Angles(0.3, 0, 0)
		f.armAnimation = Frame.Angles(0, 0, -0.2)
		for _ = 1, 120 do f.update() end
		assert(right.CFrame.Position.Y < standing.Y and (left.CFrame.Position - shoulder).Magnitude > 0.1)
		local gun = f.view.GetVisualTool(f.tool):FindFirstChild("Handle")
		local expected = right.CFrame * f.grip.C0 * f.grip.C1:Inverse()
		near((gun.CFrame.Position - expected.Position).Magnitude, 0)
		for i = 1, 9 do near(gun.CFrame.matrix[i], expected.matrix[i]) end
		assert(f.model() == model and f.handle.cloneCount == 1 and f.handle.CFrame.Position.Z == 7)
		f.bodyAnimation, f.armAnimation = nil, nil
		for _ = 1, 120 do f.update() end
		near((right.CFrame.Position - standing).Magnitude, 0)
		f.view.Clear()
	end)
	test("aim, reload and recoil remain cosmetic and lower the visible hold smoothly", function()
		local f = viewmodelFixture()
		for _ = 1, 120 do f.update() end
		local arm = f.model():FindFirstChild("Right Arm"); local hip = arm.CFrame.Position
		f.update(true, true); local first = arm.CFrame.Position
		assert(first.X < hip.X and first.X > hip.X + f.tuning.FirstPerson.AimOffset[1])
		for _ = 1, 120 do f.update(true, true) end
		local aimed = arm.CFrame.Position
		near(aimed.X - hip.X, f.tuning.FirstPerson.AimOffset[1]); near(aimed.Y - hip.Y, f.tuning.FirstPerson.AimOffset[2])
		f.view.Kick(f.tool); f.update(true, true); assert(arm.CFrame.Position.Z > aimed.Z)
		for _ = 1, 120 do f.update(true, true, true) end
		assert(arm.CFrame.Position.Y < aimed.Y and f.handle.CFrame.Position.Z == 7 and #f.warnings == 0)
		f.view.Clear()
	end)
	test("unsupported avatars and disabled first-person settings allocate no weapon copy", function()
		local f = viewmodelFixture(); f.left.Parent = nil
		f.update(); f.update(); assert(not f.model() and not f.tool.cloneCount and #f.warnings == 0)
		f.view.Clear(); f.left.Parent = f.character; f.tuning.FirstPerson.Enabled = false
		f.update(); assert(not f.model() and not f.tool.cloneCount)
	end)
	local function visualFixture()
		local f = fixture(); f.env.Instance.new = geometryObject
		f.effects = load("KnifeEffectsConfig").Get("Ordinary Knife")
		f.visuals = load("KnifeVisual", f.env)
		f.template = geometryObject("Tool", "Ordinary Knife")
		f.handle = geometryObject("Part", "Handle", f.template); f.handle.Transparency = 1
		f.handle.CFrame = Frame.new(5, 7, 3) * Frame.Angles(0, 0.4, 0)
		f.blade = geometryObject("MeshPart", "Blade", geometryObject("Model", "BladeAssembly", f.template))
		f.blade.CFrame = f.handle.CFrame * Frame.new(0, 1, 0); f.blade.Size = V(0.3, 4, 0.3)
		f.blade.TextureID, f.blade.LocalTransparencyModifier = "blade-texture", 1
		return f
	end
	test("multipart knife preserves sibling/nested blades, texture and relative geometry", function()
		local f = visualFixture(); local visual = assert(f.visuals.Create(f.template, f.effects))
		assert(#visual.parts == 2 and visual.model:FindFirstChild("Blade", true))
		local blade = visual.model:FindFirstChild("Blade", true)
		assert(blade.TextureID == "blade-texture" and blade.Transparency == 0 and blade.LocalTransparencyModifier == 0)
		f.visuals.Fly(visual, V(0, 2, -10), V(0, 0, -1))
		local offset = visual.root.CFrame:Inverse() * blade.CFrame
		near(offset.Position.X, 0); near(offset.Position.Y, 1); near(offset.Position.Z, 0)
		near((blade.CFrame:VectorToWorldSpace(V(0, 1, 0)) - V(0, 0, -1)).Magnitude, 0)
		assert(blade.Anchored and not blade.CanCollide and not blade.CanTouch and not blade.CanQuery)
		assert(f.blade.LocalTransparencyModifier == 1 and f.handle.Transparency == 1)
	end)
	test("half the visible multipart knife embeds into walls floors ceilings and slopes", function()
		local f = visualFixture(); local visual = f.visuals.Create(f.template, f.effects)
		local blade = visual.model:FindFirstChild("Blade", true)
		for _, case in ipairs({{V(0, 2, -20), V(0, 0, 1)}, {V(5, 0, 7), V(0, 1, 0)},
			{V(0, 10, 0), V(0, -1, 0)}, {V(2, 2, 2), V(1, 1, 0).Unit}}) do
			local hit, normal = case[1], case[2]
			f.visuals.Stick(visual, hit, V(0, 0, -1), normal)
			local tip = blade.CFrame:PointToWorldSpace(V(0, 2, 0))
			local tail = blade.CFrame:PointToWorldSpace(V(0, -2, 0))
			near((tip - hit):Dot(normal), -2)
			near((tail - hit):Dot(normal), 2)
			near((blade.CFrame.Position - hit):Dot(normal), 0)
			near((blade.CFrame:VectorToWorldSpace(V(0, 1, 0)) + normal).Magnitude, 0)
		end
	end)
	test("nonarchivable knife parts clone without modifying source scripts or visibility", function()
		local f = visualFixture(); f.template.Archivable, f.blade.Archivable = false, false
		local script = geometryObject("LocalScript", "EquippedScript", f.template)
		geometryObject("WeldConstraint", "BladeWeld", f.blade)
		geometryObject("ParticleEmitter", "BakedRainbow", f.blade)
		geometryObject("Sound", "BakedSound", f.handle)
		local visual = assert(f.visuals.Create(f.template, f.effects))
		assert(visual.model:FindFirstChild("Blade", true) and not visual.model:FindFirstChild("EquippedScript", true))
		assert(not visual.model:FindFirstChild("BladeWeld", true) and not visual.model:FindFirstChild("BakedRainbow", true))
		assert(not visual.model:FindFirstChild("BakedSound", true))
		assert(f.template.Archivable == false and f.blade.Archivable == false and script.Parent == f.template)
	end)
	test("invisible mesh templates and handleless knives still produce a visible projectile", function()
		local f = visualFixture(); f.blade.Transparency = 1; f.handle:Destroy()
		local visual = assert(f.visuals.Create(f.template, f.effects)); assert(#visual.parts == 1)
		assert(visual.root.Transparency == 0 and f.blade.Transparency == 1)
		local empty = geometryObject("Tool", "Empty"); assert(f.visuals.Create(empty, f.effects) == nil)
	end)
	test("per-skin blade axis and tip distance orient sideways meshes and keep rails aligned", function()
		local f = visualFixture(); f.blade.Size, f.blade.CFrame = V(6, 0.3, 0.3), f.handle.CFrame
		f.effects.TipDistance = 3.5
		local visual = f.visuals.Create(f.template, f.effects); near(visual.tipDistance, 3.5)
		f.visuals.Fly(visual, V(0, 0, -5), V(0, 0, -1))
		local blade = visual.model:FindFirstChild("Blade", true)
		near((blade.CFrame:VectorToWorldSpace(V(1, 0, 0)) - V(0, 0, -1)).Magnitude, 0)
		near((visual.trailAnchor.CFrame.LookVector - V(0, 0, -1)).Magnitude, 0)
		f.effects.BladeAxis = "-X"
		local reversed = f.visuals.Create(f.template, f.effects)
		f.visuals.Fly(reversed, Vector.zero, V(0, -1, 0))
		near((reversed.root.CFrame:VectorToWorldSpace(V(-1, 0, 0)) - V(0, -1, 0)).Magnitude, 0)
	end)
	test("charge speed cannot exceed the maximum after a long hold or server charge clamp", function()
		local f = knifeFixture(); near(f.projectile.GetSpeed(2), 750); near(f.projectile.GetSpeed(-1), 500)
		assert(f.fire("overcharged", 20)); near(f.visual.charge, 1)
	end)
	test("revolver equip sound plays once per equip instead of every HUD update", function()
		local f = controllerFixture(); f.snapshot(3); f.advance(0.02)
		local count = f.equipEffects; assert(count == 1)
		for _ = 1, 30 do f.advance(0.02) end; assert(f.equipEffects == count)
		f.tool.Parent = nil; table.remove(f.character.children, table.find(f.character.children, f.tool)); f.character.ChildRemoved:Fire(f.tool)
		f.advance(0.02); f.tool.Parent = f.character; table.insert(f.character.children, f.tool); f.character.ChildAdded:Fire(f.tool)
		f.advance(0.02); assert(f.equipEffects == count + 1)
	end)
	test("all revolvers inherit the requested shoot reload and equip audio IDs", function()
		local f = fixture(); local effects = load("Effects", f.env)
		local cfg = load("Config"); local tuning = cfg.Get("Azure Revolver")
		assert(tuning.Effects.FireSoundId == "rbxassetid://134770754233897")
		assert(tuning.Effects.ReloadSoundId == "rbxassetid://108663305361300")
		assert(tuning.Effects.EquipSoundId == "rbxassetid://98462055955985")
		local handle = object("Part", "Handle"); handle.Position, handle.CFrame = Vector.zero, Frame.identity; handle.Parent = f.tool; table.insert(f.tool.children, handle)
		effects.Fire(f.tool, Vector.zero, V(0, 0, -20), tuning, false)
		effects.Reload(f.tool, tuning); effects.Equip(f.tool, tuning)
		local ids = {}; for _, item in ipairs(f.created) do if item.ClassName == "Sound" and item.played then ids[item.SoundId] = item.Volume end end
		near(ids[tuning.Effects.FireSoundId], tuning.Effects.SoundVolume)
		near(ids[tuning.Effects.ReloadSoundId], tuning.Effects.SoundVolume)
		near(ids[tuning.Effects.EquipSoundId], tuning.Effects.EquipSoundVolume)
	end)
	local function knifeClientFixture()
		local f = fixture(); f.config = load("KnifeConfig"); f.effectsConfig = load("KnifeEffectsConfig")
		table.remove(f.character.children, table.find(f.character.children, f.tool)); f.tool.Parent = nil
		f.tool = geometryObject("Tool", "Ordinary Knife", f.character)
		local handle = geometryObject("Part", "Handle", f.tool); handle.Transparency = 1
		local blade = geometryObject("MeshPart", "Blade", f.tool); blade.Size = V(0.3, 4, 0.3)
		f.handle, f.blade = handle, blade
		f.rootJoint = object("Motor6D", "RootJoint")
		f.rootJoint.C0, f.rootJoint.C1 = Frame.identity, Frame.identity
		f.rootJoint.Part0, f.rootJoint.Part1, f.rootJoint.Parent = f.root, f.torso, f.root
		table.insert(f.root.children, f.rootJoint)
		f.workspace = f.env.workspace; f.workspace.children, f.workspace.ChildAdded, f.workspace.ChildRemoved = {}, signal(), signal()
		f.env.Instance.new = geometryObject
		f.player.attributes = {InRound = true, DataReady = true}
		function f.player:GetAttribute(name) return self.attributes[name] end
		function f.player:FindFirstChild(name) return self[name] end
		local function add(parent, class, name)
			local item = object(class, name); item.Parent = parent; table.insert(parent.children, item); parent[name] = item; return item
		end
		local gui = object("PlayerGui", "PlayerGui"); f.player.PlayerGui = gui
		local main = add(gui, "ScreenGui", "Main")
		local ability = add(add(add(main, "Frame", "BottomLeft"), "Frame", "StuffContainer"), "Frame", "Ability")
		add(add(ability, "Frame", "OnClick"), "Frame", "OnClickFrame"); f.frames = add(main, "Folder", "Frames")
		local rs = object("Folder", "ReplicatedStorage"); f.services.ReplicatedStorage = rs
		local modules = add(rs, "Folder", "Modules")
		for _, name in ipairs({"RagdollQuery", "KnifeConfig", "KnifeEffectsConfig", "ProjectileMath", "RevolverRaycast", "SprintState"}) do add(modules, "ModuleScript", name) end
		local knives = add(rs, "Folder", "Knives"); f.tool:Clone().Parent = knives; f.knives = knives
		local animations = add(rs, "Folder", "CombatAnimations")
		for _, name in ipairs({"Charge", "ChargeHold", "Throw", "Stab"}) do add(animations, "Animation", name) end
		f.active = add(rs, "BoolValue", "GameActive"); f.active.Value, f.active.Changed = true, signal()
		local remotes = add(add(rs, "Folder", "Remotes"), "Folder", "Knife")
		f.throwRemote = add(remotes, "RemoteEvent", "ThrowKnife"); f.throwRemote.sent = {}
		function f.throwRemote:FireServer(...) table.insert(self.sent, {...}) end
		add(remotes, "RemoteEvent", "StabKnife").FireServer = function() f.stabs = (f.stabs or 0) + 1 end
		f.result = add(remotes, "RemoteEvent", "ThrewClient"); f.result.OnClientEvent = signal()
		f.damage = add(remotes, "RemoteEvent", "DamageDealtClient"); f.damage.OnClientEvent = signal()
		f.humanoid.Died = signal(); f.events.Heartbeat = signal()
		f.camera.ViewportPointToRay = function() return {Origin = V(0, 2, 10), Direction = V(0, 0, -1)} end
		f.workspace.Raycast = function() return f.castResult end
		f.services.TweenService.Create = function()
			local tween = {Completed = signal()}; function tween:Play() end; function tween:Cancel() self.Completed:Fire("Cancelled") end; return tween
		end
		f.env.Enum.EasingStyle, f.env.Enum.PlaybackState = {Linear = "Linear"}, {Completed = "Completed"}
		f.delayed = {}
		f.env.task = {spawn = function() end, delay = function(seconds, fn) table.insert(f.delayed, {at = f.env.os.clock() + seconds, fn = fn}) end}
		local visual = load("KnifeVisual", f.env)
		local hidden, parts = {}, {}
		local function restorePresentation()
			for part, original in pairs(hidden) do
				if part.Parent and part.LocalTransparencyModifier == 1 then part.LocalTransparencyModifier = original end
			end
			table.clear(hidden)
		end
		local knifeViewmodel = {
			InterruptInspect = function() f.inspectInterrupts = (f.inspectInterrupts or 0) + 1 end,
			Init = function() f.viewmodelInits = (f.viewmodelInits or 0) + 1 end,
			Clear = function() f.viewmodelClears = (f.viewmodelClears or 0) + 1; restorePresentation() end,
			IsFirstPerson = function() return f.firstPerson == true end,
			GetOriginalTransparency = function(part) return hidden[part] or part.LocalTransparencyModifier end,
			SetOriginalTransparency = function(part, original)
				f.snapshotUpdates = (f.snapshotUpdates or 0) + 1
				if hidden[part] ~= nil then hidden[part] = original end
			end,
			Update = function(tool, allowed, dt, body, arm, action)
				f.knifePresentation = {tool = tool, allowed = allowed, dt = dt, body = body, arm = arm, action = action}
				if f.firstPerson and not f.presentationPending and allowed and tool then
					if not parts[tool] then
						parts[tool] = {}; for _, part in ipairs(tool:GetDescendants()) do if part:IsA("BasePart") then table.insert(parts[tool], part) end end
					end
					for _, part in ipairs(parts[tool]) do
						if hidden[part] == nil then hidden[part] = part.LocalTransparencyModifier end
						part.LocalTransparencyModifier = 1
					end
				else restorePresentation() end
			end,
		}
		local dependencies = {
			RagdollQuery = queryStub,
			KnifeConfig = f.config, KnifeEffectsConfig = f.effectsConfig, KnifeVisual = visual,
			KnifeViewmodel = knifeViewmodel,
			KnifeEffects = {Attach = function() f.attached = (f.attached or 0) + 1; return function() f.stopped = (f.stopped or 0) + 1 end end,
				ThrowSound = function(origin) f.sounds = (f.sounds or 0) + 1; f.soundOrigin = origin end,
				Impact = function() f.impacts = (f.impacts or 0) + 1 end},
			KnifeHint = {Init = function() end, Update = function(visible, mobile, charge, position) f.hint = {visible, mobile, charge, position} end,
				ShowHitMarker = function() f.hitMarkers = (f.hitMarkers or 0) + 1 end},
			SprintState = {}, SoundHandler = {Sounds = {ThrowKnife = {}}, PlaySound = function() end},
			RevolverRaycast = {GetAimOrigin = function(origin) return origin end},
		}
		f.env.script = {Parent = {KnifeEffects = "KnifeEffects", KnifeVisual = "KnifeVisual", KnifeHint = "KnifeHint", KnifeViewmodel = "KnifeViewmodel", WaitForChild = function(_, name) return name end}}
		dependencies.ProjectileMath = load("Projectile", {require = function() return f.config end, script = {Parent = {KnifeConfig = "KnifeConfig"}}, typeof = f.env.typeof})
		f.env.require = function(name) return assert(dependencies[type(name) == "table" and name.Name or name], tostring(name)) end
		f.controller = load("KnifeController", f.env); f.controller.Init()
		local advance = f.advance
		function f.advance(seconds)
			advance(seconds); f.events.Heartbeat:Fire(seconds)
			for _, job in ipairs(table.clone(f.delayed)) do
				if job.at <= f.env.os.clock() then local index = table.find(f.delayed, job); if index then table.remove(f.delayed, index); job.fn() end end
			end
		end
		function f.projectiles() local all = {}; for _, item in ipairs(f.workspace.children) do if string.find(item.Name, "KnifeProjectile_", 1, true) then table.insert(all, item) end end; return all end
		return f
	end
	test("knife charge and stab interrupt inspect without delaying the combat request", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge())
		assert(f.inspectInterrupts == 1); f.controller.CancelCharge(); f.advance(0.02)
		assert(f.controller.Stab()); assert(f.inspectInterrupts == 2 and f.stabs == 1)
	end)
	test("emote menu opening cancels knife presentation and its active charge", function()
		local f = knifeClientFixture(); f.firstPerson = true; assert(f.controller.BeginCharge())
		local main = f.player.PlayerGui:FindFirstChild("Main")
		local emote, background = object("Frame", "EmoteFrame"), object("Frame", "background")
		background.Visible, background.Parent = true, emote; emote.children = {background}
		emote.Parent = main; table.insert(main.children, emote)
		f.advance(0.25); f.advance(0.01) -- the heartbeat cancellation precedes the next render sample
		assert(not f.knifePresentation.allowed and not f.knifePresentation.action.holdingCharge)
		assert(not f.controller.BeginCharge() and #f.throwRemote.sent == 0)
	end)
	test("knife presentation follows the same actual charge threshold and cancellation as combat", function()
		local f = knifeClientFixture(); assert(f.viewmodelInits == 1)
		assert(f.controller.BeginCharge()); f.advance(0.1)
		assert(f.knifePresentation.tool == f.tool and not f.knifePresentation.action.charging)
		f.advance(0.15); assert(f.knifePresentation.action.charging); near(f.knifePresentation.action.charge, 0.25)
		f.controller.CancelCharge(); f.advance(0.01)
		assert(not f.knifePresentation.action.charging and f.knifePresentation.action.charge == 0 and #f.throwRemote.sent == 0)
	end)
	test("knife camera hand receives actual crouch and shoulder animation through cached joints", function()
		local f = knifeClientFixture(); local reads = f.character.childReads or 0
		f.rootJoint.Transform = Frame.new(0, -0.5, 0) * Frame.Angles(0.3, 0, 0)
		f.joint.Transform = Frame.Angles(0, 0, -0.2)
		for _ = 1, 90 do f.advance(1/60) end
		near(f.knifePresentation.body.Position.Y, -0.5)
		local expected = f.joint.C0.Rotation * f.joint.Transform * f.joint.C0.Rotation:Inverse()
		for i = 1, 9 do near(f.knifePresentation.arm.matrix[i], expected.matrix[i]) end
		assert(f.character.childReads == reads, "equipped knife selection must remain cached between lifecycle events")
	end)
	test("knife tap stab and held throw drive distinct cosmetic releases on the equipped knife", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge()); f.advance(0.1)
		assert(f.controller.ReleaseCharge()); f.advance(0.01)
		assert(f.stabs == 1 and f.knifePresentation.action.stabElapsed and not f.knifePresentation.action.throwElapsed)
		f.advance(1); assert(f.controller.BeginCharge()); f.advance(0.4)
		assert(f.controller.ReleaseCharge()); f.advance(0.01)
		assert(#f.throwRemote.sent == 1 and f.knifePresentation.action.throwElapsed)
		near(f.knifePresentation.action.throwElapsed, 0.01)
		assert(f.throwRemote.sent[1][2] == f.character:FindFirstChild("Head").Position)
	end)
	test("equipping a different knife does not inherit the old throw hide or charge state", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge())
		f.tool.Parent = nil
		local nextTool = geometryObject("Tool", "Another Knife", f.character)
		geometryObject("Part", "Handle", nextTool); local template = nextTool:Clone(); template.Parent = f.knives
		f.advance(0.01)
		assert(f.knifePresentation.tool == nextTool and not f.knifePresentation.action.throwElapsed)
		assert(not f.knifePresentation.action.charging and not f.controller.IsCharging())
	end)
	test("first-person knife shots preserve visible flight and sound while suppressing delayed VFX", function()
		local f = knifeClientFixture(); f.firstPerson = true; f.advance(0.01); f.castResult = {Position = V(0, 2, -5)}
		assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge())
		local projectile = f.projectiles()[1]; assert(projectile and not f.attached and f.sounds == 1)
		assert(f.soundOrigin == f.character:FindFirstChild("Head").Position)
		f.advance(0.02); f.firstPerson = false; f.advance(0.1)
		f.result.OnClientEvent:Fire({shotId = f.throwRemote.sent[1][1], accepted = true, position = V(0,2,-5), normal = V(0,0,1)})
		assert(not f.impacts and projectile.Parent == f.workspace)
	end)
	test("a first-person throw restores the real blade after zooming out during its hide window", function()
		local f = knifeClientFixture(); f.firstPerson = true; f.advance(0.01)
		assert(f.handle.LocalTransparencyModifier == 1 and f.blade.LocalTransparencyModifier == 1)
		assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge()); f.advance(0.16)
		f.firstPerson = false; f.advance(0.01)
		near(f.handle.LocalTransparencyModifier,1); near(f.blade.LocalTransparencyModifier,1)
		f.advance(0.5); f.advance(0.01)
		near(f.handle.LocalTransparencyModifier,0); near(f.blade.LocalTransparencyModifier,0)
	end)
	test("zooming in during a third-person knife throw cannot preserve the temporary hidden snapshot", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge()); f.advance(0.3)
		assert(f.controller.ReleaseCharge()); f.advance(0.16)
		near(f.handle.LocalTransparencyModifier,1); near(f.blade.LocalTransparencyModifier,1)
		f.firstPerson = true; f.advance(0.01)
		f.advance(0.49); f.advance(0.01)
		assert(f.snapshotUpdates == 2)
		near(f.handle.LocalTransparencyModifier,1); near(f.blade.LocalTransparencyModifier,1)
		f.firstPerson = false; f.advance(0.01)
		near(f.handle.LocalTransparencyModifier,0); near(f.blade.LocalTransparencyModifier,0)
	end)
	test("a delayed first-person knife build after a throw returns with the correct original visibility", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge()); f.advance(0.3)
		assert(f.controller.ReleaseCharge()); f.advance(0.16)
		f.firstPerson, f.presentationPending = true, true; f.advance(0.5)
		near(f.handle.LocalTransparencyModifier,0); near(f.blade.LocalTransparencyModifier,0)
		f.presentationPending = false; f.advance(0.01)
		near(f.handle.LocalTransparencyModifier,1); near(f.blade.LocalTransparencyModifier,1)
		f.firstPerson = false; f.advance(0.01)
		near(f.handle.LocalTransparencyModifier,0); near(f.blade.LocalTransparencyModifier,0)
	end)
	test("knife death menu and respawn cannot leave a stale visible camera weapon", function()
		local f = knifeClientFixture(); f.advance(0.01); assert(f.knifePresentation.allowed)
		f.services.GuiService.MenuIsOpen = true; f.advance(0.01); assert(not f.knifePresentation.allowed)
		f.services.GuiService.MenuIsOpen = false; f.humanoid.Health = 0; f.humanoid.Died:Fire(); f.advance(0.01)
		assert(not f.knifePresentation.allowed and f.viewmodelClears >= 1)
		f.player.CharacterRemoving:Fire(f.character); f.advance(0.01); assert(f.knifePresentation.tool == nil)
	end)
	test("knife controller leaves hit presentation to shared feedback and installs no obsolete marker listener", function()
		local f = knifeClientFixture(); f.castResult = {Position = V(0, 2, -5)}
		assert(f.damage.OnClientEvent:Count() == 0)
		assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge())
		assert(not f.hitMarkers)
		f.result.OnClientEvent:Fire({shotId = f.throwRemote.sent[1][1], accepted = true, position = V(0, 2, -5), normal = V(0,0,1)})
		assert(not f.hitMarkers)
		for _, amount in ipairs({0, -1, math.huge, -math.huge, 0/0, "50"}) do f.damage.OnClientEvent:Fire(nil, amount, "KnifeThrow") end
		for _, kind in ipairs({"Revolver", "KnifeStab", "Unknown"}) do f.damage.OnClientEvent:Fire(nil, 50, kind) end
		assert(not f.hitMarkers)
		f.damage.OnClientEvent:Fire(nil, 50, "KnifeThrow"); assert(not f.hitMarkers)
	end)
	test("knife controller adds no legacy marker subscription across combat gates", function()
		for _, block in ipairs({"round", "unready", "dead", "unequip", "menu", "inactive"}) do
			local f = knifeClientFixture()
			if block == "round" then f.player.attributes.InRound = false
			elseif block == "unready" then f.player.attributes.DataReady = false
			elseif block == "dead" then f.humanoid.Health = 0
			elseif block == "unequip" then f.tool.Parent = nil
			elseif block == "menu" then f.services.GuiService.MenuIsOpen = true
			else f.active.Value = false end
			f.damage.OnClientEvent:Fire(nil, 50, "KnifeThrow")
			assert(f.damage.OnClientEvent:Count() == 0 and not f.hitMarkers, block)
		end
	end)
	test("observer knives fly then remain embedded for four seconds with a stopped trail", function()
		local f = knifeClientFixture()
		f.result.OnClientEvent:Fire({visualOnly = true, shooterUserId = 2, shotId = "observer", knifeName = "Ordinary Knife",
			origin = V(0, 2, 0), direction = V(0, 0, -1), charge = 1, destination = V(0, 2, -10), normal = V(0, 0, 1)})
		local projectile = f.projectiles()[1]; assert(projectile and projectile:FindFirstChild("Blade", true))
		f.advance(0.02); assert(f.impacts == 1 and f.stopped == 1)
		f.advance(3.99); assert(projectile.Parent == f.workspace)
		f.advance(0.02); assert(projectile.Parent == nil)
	end)
	test("late close-range acknowledgement embeds the owner's blade and renews its visible lifetime", function()
		local f = knifeClientFixture(); f.castResult = {Position = V(0, 2, -5)}
		assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge())
		local projectile = f.projectiles()[1]; local sent = f.throwRemote.sent[1]
		f.advance(0.02); assert(not f.impacts)
		f.advance(0.2); f.result.OnClientEvent:Fire({shotId = sent[1], accepted = true, position = V(0, 2, -5), normal = V(0, 0, 1)})
		assert(f.impacts == 1); local blade = projectile:FindFirstChild("Blade", true)
		near((blade.CFrame:PointToWorldSpace(V(0, 2, 0)) - V(0, 2, -5)):Dot(V(0, 0, 1)), -2)
		f.advance(3.99); assert(projectile.Parent == f.workspace)
		f.advance(0.02); assert(projectile.Parent == nil)
	end)
	test("confirmed knife misses vanish promptly and rejected predictions allocate no lingering blade", function()
		local f = knifeClientFixture()
		f.result.OnClientEvent:Fire({visualOnly = true, shooterUserId = 2, shotId = "miss", knifeName = "Ordinary Knife",
			origin = V(0, 2, 0), direction = V(0, 0, -1), charge = 1, destination = V(0, 2, -10)})
		f.advance(0.02); assert(#f.projectiles() == 1); f.advance(0.16); assert(#f.projectiles() == 0 and not f.impacts)
		assert(f.controller.BeginCharge()); f.advance(0.3); assert(f.controller.ReleaseCharge())
		f.result.OnClientEvent:Fire({shotId = f.throwRemote.sent[1][1], accepted = false}); assert(#f.projectiles() == 0)
	end)
	test("knife controller caps long-held charge and restores every held blade part on unequip", function()
		local f = knifeClientFixture(); assert(f.controller.BeginCharge()); f.advance(3)
		near(f.hint[3], 1); assert(f.controller.ReleaseCharge()); near(f.throwRemote.sent[1][4], 1)
		f.advance(0.16)
		for _, part in ipairs(f.tool:GetDescendants()) do if part:IsA("BasePart") then near(part.LocalTransparencyModifier, 1) end end
		f.tool.Parent = nil
		for _, part in ipairs(f.tool:GetDescendants()) do if part:IsA("BasePart") then near(part.LocalTransparencyModifier, 0) end end
		f.advance(0.01); assert(not f.hint[1])
	end)
	test("observer shot IDs cannot overwrite another shooter and duplicate packets leave no orphan", function()
		local f = knifeClientFixture()
		local packet = {visualOnly = true, shooterUserId = 2, shotId = "shared", knifeName = "Ordinary Knife",
			origin = V(0, 2, 0), direction = V(0, 0, -1), charge = 1, destination = V(0, 2, -10), normal = V(0, 0, 1)}
		f.result.OnClientEvent:Fire(packet); local first = f.projectiles()[1]
		packet.shooterUserId = 3; f.result.OnClientEvent:Fire(packet); assert(#f.projectiles() == 2)
		packet.shooterUserId = 2; f.result.OnClientEvent:Fire(packet); assert(#f.projectiles() == 2 and not first.Parent)
		f.advance(0.02); f.advance(4.01); assert(#f.projectiles() == 0)
	end)
	test("gun HUD starts hidden and disappears immediately on unequip or character removal", function()
		local f = controllerFixture(); assert(f.hud.Enabled == false)
		f.advance(0.02); assert(f.hud.Enabled)
		table.remove(f.character.children, table.find(f.character.children, f.tool)); f.tool.Parent = nil
		f.character.ChildRemoved:Fire(f.tool); assert(f.hud.Enabled == false)
		f.tool.Parent = f.character; table.insert(f.character.children, f.tool); f.character.ChildAdded:Fire(f.tool)
		f.advance(0.02); assert(f.hud.Enabled)
		f.player.CharacterRemoving:Fire(f.character); assert(f.hud.Enabled == false)
		f.advance(0.02); assert(f.hud.Enabled == false, "old character must not reacquire its gun HUD")
	end)
	test("support arm rotates continuously through the former vertical up-vector switch", function()
		local c0, c1, previous = Frame.new(-1,0.5,0), Frame.new(0.5,0.5,0), nil
		for _, y in ipairs({0.975,0.979,0.981,0.985,0.99,0.999,1}) do
			local direction = V(math.sqrt(1-y*y), -y, 0)
			local transform = Math.SupportTransform(c0, c1, c0.Position + direction * 3, 2)
			local arm = c0 * transform * c1:Inverse()
			local palm = V(0,-1,0) - c1.Position
			near((arm:VectorToWorldSpace(palm).Unit - direction).Magnitude, 0)
			if previous then for i = 1, 9 do assert(math.abs(arm.matrix[i] - previous.matrix[i]) < 0.12) end end
			previous = arm
		end
	end)
	test("near-vertical aim preserves body yaw instead of following unstable horizontal noise", function()
		local f = fixture(); local aim = load("Camera", f.env); assert(aim.Start(f.tool, Config.Default.Aim, function() return true end))
		local before = f.root.CFrame
		for _, direction in ipairs({V(0.001,-1,0.001).Unit, V(-0.001,-1,-0.001).Unit}) do
			f.camera.CFrame = Frame.lookAt(V(0,5,10), V(0,5,10)+direction, V(1,0,0))
			f.events.PreSimulation:Fire(0.02); assert(f.root.CFrame == before)
		end
		assert(aim.IsAiming()); aim.Stop(true)
	end)
	test("steep cursor aim fades unstable shoulder yaw while ordinary aiming retains its range", function()
		for _, y in ipairs({-1, 1}) do
			for _, x in ipairs({-0.001, 0.001, -0.07, 0.07}) do
				local _, yaw = Math.Angles(x, y, 0.001, settings)
				near(yaw, 0)
			end
		end
		local _, ordinary = Math.Angles(1, 0.5, -1, settings); near(ordinary, -math.pi / 4)
		local previous
		for index = 0, 300 do
			local _, yaw = Math.Angles(index / 1000, -1, 0.001, settings)
			if previous then assert(math.abs(yaw - previous) < math.rad(1)) end
			previous = yaw
		end
	end)
	test("vertical yaw fade tuning rejects invalid skin overrides before pose math", function()
		for _, limits in ipairs({{0.2, 0.2}, {0.3, 0.1}, {-0.1, 0.25}, {0.1, 1.1}, {0/0, 0.25}, {0.1, "bad"}}) do
			Config.Overrides.InvalidVerticalFade = {Pose = {VerticalYawFadeStart = limits[1], VerticalYawFadeEnd = limits[2]}}
			assert(not pcall(Config.Get, "InvalidVerticalFade"))
		end
		Config.Overrides.InvalidVerticalFade = nil
		assert(Config.Get("Normal Revolver").Pose.VerticalYawFadeStart == settings.VerticalYawFadeStart)
	end)
	test("camera support arm stays continuous through vertical alignment and steep camera turns", function()
		local f = viewmodelFixture(); f.update()
		f.grip.C0, f.grip.C1 = Frame.identity, Frame.identity
		local visual = {
			right = {Size = V(1, 2, 1)}, left = {Size = V(1, 2, 1)},
			sourceRight = f.right, sourceHandle = f.handle, pieces = {}, shell = {}, leftShoulder = V(0, 0, 0),
			weaponVisibility = {SetActive = function() end, Guard = function() end}, supportHandOffset = V(0, 0, 0),
		}
		for _, pitch in ipairs({-1.56, 0, 1.56}) do
			for _, yaw in ipairs({-1.5, 0, 1.5}) do
				local camera = Frame.new(10, 25, -8) * Frame.Angles(pitch, yaw, 0)
				local previous
				for _, y in ipairs({0.975, 0.979, 0.981, 0.985, 0.99, 0.999, 1}) do
					local direction = V(math.sqrt(1 - y*y), -y, 0)
					f.geometry.Place(visual, camera, Frame.new(direction * 3), firstPerson, {0, 0, 0})
					local localArm = camera:Inverse() * visual.left.CFrame
					near((localArm:VectorToWorldSpace(V(0, -1, 0)) - direction).Magnitude, 0)
					near((visual.left.CFrame:PointToWorldSpace(V(0, -1, 0)) - visual.right.CFrame.Position).Magnitude, 0)
					if previous then for index = 1, 9 do assert(math.abs(localArm.matrix[index] - previous.matrix[index]) < 0.12) end end
					previous = localArm
				end
			end
		end
		f.view.Clear()
	end)
	test("camera collision distances around one stud do not toggle the shoulder offset", function()
		local f = fixture(); local aim = load("Camera", f.env); assert(aim.Start(f.tool, Config.Default.Aim, function() return true end))
		for _ = 1, 80 do f.advance(0.02) end
		local before = f.humanoid.CameraOffset.X
		for _, distance in ipairs({0.95,1.05,0.9,1.1,0.99}) do
			f.camera.Focus = Frame.new(); f.camera.CFrame = Frame.new(0,0,distance); f.advance(0.02)
			assert(f.humanoid.CameraOffset.X >= before - 0.001)
		end
		aim.Stop(true)
	end)
	test("degenerate hits almost touching the shoulder use a stable fallback", function()
		local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("test")
		local distance = 0.1
		f.env.workspace.Raycast = function() return {Position = V(1, 0.5, -distance)} end
		local ray = {Origin = V(0,2,10), Direction = V(0,-1,-0.1).Unit}
		pose.SampleCursor(f.tool, ray, false, false); local first = f.remote.sent[#f.remote.sent]
		distance = 0.2; f.advance(0.1); pose.SampleCursor(f.tool, ray, false, true)
		local second = f.remote.sent[#f.remote.sent]; near(first[3], second[3]); near(first[4], second[4])
	end)
	test("full overhead cursor rays retain elevated targets and actual firing-path cover still blocks them", function()
		local camera, reference, targetPosition = V(0,28,8), V(0,4,0), V(0,6,-2)
		local direction = (targetPosition-camera).Unit
		local tuning = table.clone(Config.Default); tuning.HitboxSize = {0.2,0.2,0.2}
		local target = {frame = Frame.new(targetPosition)}
		local muzzle = V(1,3,-0.5)
		local result = Raycast.Resolve(camera, direction, muzzle, tuning, {target}, function() return nil end, reference)
		assert(result and result.victim == target)
		local wall = worldBoxes({{position = V(0,4.5,-1.25), size = {6,0.2,1}}})
		result = Raycast.Resolve(camera, direction, muzzle, tuning, {target}, wall, reference)
		assert(result and not result.victim and result.normal)
	end)
	test("an overhead camera keeps the arm on a nearby forward target instead of extending below the floor", function()
		for _, aiming in ipairs({false, true}) do
			local f = fixture(); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("test")
			f.torso.CFrame = Frame.new(0, 3, 0); f.character:FindFirstChild("Head").Position = V(0, 4, 0)
			local target, camera = V(1, 3.5, -6), V(0, 25, 10)
			local ray = {Origin = camera, Direction = (target-camera).Unit}
			-- Reproduce the old extension numerically: its target is below ground.
			local oldOrigin = camera + ray.Direction * math.max(0,(V(1,3,0)-camera):Dot(ray.Direction))
			assert((oldOrigin + ray.Direction * 12).Y < 0)
			f.env.workspace.Raycast = function() return {Position = target} end
			pose.SampleCursor(f.tool, ray, false, aiming)
			local packet = f.remote.sent[#f.remote.sent]
			near(packet[3], 0); near(packet[4], 0)
		end
	end)
	print(string.format("%d revolver/knife tests passed", passed))
end
