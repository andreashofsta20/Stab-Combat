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
	Frame.identity = Frame.new()
	local Config = load("Config")
	local Math = load("Math", { CFrame = Frame, Vector3 = Vector })
	local settings = Config.Default.Pose
	local RayMath = load("RayMath", { typeof = function(value) return type(value) == "table" and value.kind or type(value) end })
	local Raycast = load("Raycast", { script = { Parent = { RevolverMath = "RayMath" } }, require = function() return RayMath end, Vector3 = Vector })
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
	test("a low ledge between camera and barrel cannot redirect a forward shot downward/backward", function()
		local target = { frame = Frame.new(0, 1, -40) }
		local worldCast = worldBoxes({ { position = V(0, 1, 3), size = { 6, 0.6, 2 } } })
		local result = Raycast.Resolve(V(0, 1, 8), V(0, 0, -1), V(1, 2, 0), Config.Default, { target }, worldCast)
		assert(result and result.victim == target, "Shot was redirected to foreground ledge; z=" .. tostring(result and result.position.Z))
		assert(result.position.Z < 0)
	end)
	test("open-ground aiming never converges toward a floor hit behind the firing plane", function()
		local function ground(origin, vector)
			if vector.Y >= 0 or origin.Y < 0 then return nil end
			local fraction = -origin.Y / vector.Y
			if fraction < 0 or fraction > 1 then return nil end
			return { Distance = vector.Magnitude * fraction, Normal = V(0, 1, 0) }
		end
		local muzzle, direction = V(1, 5, 0), V(0, -0.5, -1).Unit
		local result = Raycast.Resolve(V(0, 2, 8), direction, muzzle, Config.Default, {}, ground)
		assert(result and result.position.Z < 0, "Floor should be hit in front of the barrel")
		near(result.position.Y, 0)
		assert((result.position - muzzle):Dot(direction) > 0)
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
	test("near clipping stays on the cursor ray across steep angles and never extends range", function()
		for _, direction in ipairs({ V(0, 0, -1), V(0.4, 0.5, -1).Unit, V(-0.4, -0.6, -1).Unit, V(0, 1, 0), V(0, -1, 0) }) do
			local camera, muzzle = V(0, 4, 8), V(1, 2, 0)
			local origin = Raycast.GetAimOrigin(camera, direction, muzzle)
			near((origin - camera):Cross(direction).Magnitude, 0)
			assert((origin - camera):Dot(direction) >= 0)
			assert((origin - muzzle):Dot(direction) >= -1e-5)
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
		local obj = { ClassName = class, Name = name, children = {}, Transform = Frame.identity, Size = V(1, 2, 1), ChildAdded = signal(), ChildRemoved = signal(), Activated = signal() }
		function obj:IsA(kind) return kind == class or (kind == "BasePart" and class == "Part") end
		function obj:GetChildren() self.childReads = (self.childReads or 0) + 1; return self.children end
		function obj:GetDescendants()
			self.descendantReads = (self.descendantReads or 0) + 1
			local result = {}; for _, child in ipairs(self.children) do table.insert(result, child); for _, d in ipairs(child:GetDescendants()) do table.insert(result, d) end end
			return result
		end
		function obj:FindFirstChild(childName) for _, child in ipairs(self.children) do if child.Name == childName then return child end end end
		function obj:FindFirstChildOfClass(kind) for _, child in ipairs(self.children) do if child:IsA(kind) then return child end end end
		function obj:Destroy() self.Parent = nil; self.destroyed = true; for _, child in ipairs(self.children) do child:Destroy() end end
		function obj:Emit(count) self.emitted = (self.emitted or 0) + count end
		function obj:Play() self.played = true end
		function obj:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
		return obj
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
			ReplicatedStorage = { Modules = { RevolverConfig = "Config", RevolversInfo = "Catalog", RevolverPoseMath = "Math", RevolverRaycast = "Raycast" } },
			Debris = { AddItem = function() end }, TweenService = { Create = function() return { Play = function() end } end } }
		local function constructor(...) return { ... } end
		local env = {
			game = { GetService = function(_, name) return assert(services[name], name) end }, workspace = { GetServerTimeNow = function() return now end },
			os = { clock = function() return now end }, CFrame = Frame, Vector3 = Vector,
			Vector2 = { new = constructor }, Color3 = { new = constructor, fromRGB = constructor },
			ColorSequence = { new = constructor }, ColorSequenceKeypoint = { new = constructor },
			NumberRange = { new = constructor }, NumberSequence = { new = constructor }, NumberSequenceKeypoint = { new = constructor }, TweenInfo = { new = constructor },
			typeof = function(value) return type(value) == "table" and value.kind or typeof(value) end,
			Enum = { Material = { Neon = "Neon" }, NormalId = { Front = "Front" }, TextureMode = { Stretch = "Stretch" }, AnimationPriority = { Action4 = "Action4" },
				UserInputState = { End = "End", Cancel = "Cancel" },
				MouseBehavior = { Default = "Default", LockCenter = "LockCenter", LockCurrentPosition = "LockCurrentPosition" }, CameraType = { Custom = "Custom", Scriptable = "Scriptable" },
				RenderPriority = { Camera = { Value = 200 } }, RaycastFilterType = { Exclude = "Exclude" }, Font = { GothamBold = "GothamBold" } },
			RaycastParams = { new = function() return {} end }, UDim2 = { new = constructor, fromScale = constructor, fromOffset = constructor },
			Instance = { new = function(class) local obj = object(class, class); table.insert(created, obj); return obj end },
			require = function(name) return assert(({ Config = Config, Math = Math, Raycast = Raycast, Catalog = { ["Amber Revolver"] = {} } })[name]) end,
		}
		local camera = { FieldOfView = 70, CFrame = Frame.new(0, 0, 10), Focus = Frame.identity, CameraSubject = humanoid, CameraType = "Custom", ViewportSize = { X = 1000, Y = 600 } }
		env.workspace.CurrentCamera = camera
		local f = { env = env, joint = joint, support = support, torso = torso, root = root, humanoid = humanoid, input = input,
			tool = tool, player = player, character = character, events = events, created = created, remote = remote, bindings = bindings, camera = camera, services = services }
		function f.advance(dt)
			now += dt; events.RenderStepped:Fire(dt)
			local sorted = {}; for _, b in pairs(bindings) do table.insert(sorted, b) end
			table.sort(sorted, function(a, b) return a.priority < b.priority end)
			for _, b in ipairs(sorted) do b.fn(dt) end
		end
		function f.step() events.PreAnimation:Fire(); events.PreSimulation:Fire(1 / 60) end
		return f
	end
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
	test("arm cursor sampling also skips foreground behind the barrel in free aim and ADS", function()
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
			near(sampled.X, 0); near(sampled.Y, 2); near(sampled.Z, 0)
			assert(#f.remote.sent == 1 and math.abs(f.remote.sent[1][3]) < math.rad(1), "Arm followed foreground ground")
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
	test("impact particles require a confirmed normal and disabled tracers allocate nothing", function()
		local f = fixture(false); local effects = load("Effects", f.env)
		local count = #f.created
		effects.Impact(Vector.zero, nil, Config.Default.Effects); assert(#f.created == count)
		effects.Impact(Vector.zero, V(0, 1, 0), Config.Default.Effects); assert(#f.created > count)
		local disabled = table.clone(Config.Default.Effects); disabled.TracerEnabled = false
		count = #f.created; assert(not effects.Tracer(Vector.zero, V(0, 0, -40), disabled)); assert(#f.created == count)
		assert(not effects.Tracer(Vector.zero, Vector.zero, Config.Default.Effects))
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
		function f.player:FindFirstChildOfClass(name) return name == "PlayerGui" and playerGui end
		function f.player:WaitForChild(name) return name == "PlayerGui" and playerGui end
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
		for _, name in ipairs({ "Unknown", "R", "ButtonX", "ButtonR2", "ButtonL2" }) do f.env.Enum.KeyCode[name] = { Name = name } end
		local aim = load("Camera", f.env)
		local pose = { Init = function() end, SetLocalAim = function(tool) f.poseCleared = tool == nil end,
			Kick = function() end, ResetLocal = function() end, SetSession = function() end,
			SampleCursor = function(...) f.lastSample = { ... }; f.poseCleared = false end }
		local effects = { Fire = function() f.fireEffects = (f.fireEffects or 0) + 1; return nil end,
			Reload = function() f.reloadEffects = (f.reloadEffects or 0) + 1 end, StopReload = function() end, Clear = function() end }
		f.env.script = { Parent = { RevolverEffects = "Effects", RevolverAimPose = "Pose", RevolverAimCamera = "Camera" } }
		local dependencies = { Config = f.config, Math = Math, Catalog = { ["Amber Revolver"] = {} }, Camera = aim, Pose = pose, Effects = effects,
			Raycast = { GetMuzzle = function(_, h) return h.Position end, Resolve = function() return { position = V(0, 2, -20) } end } }
		f.env.require = function(name) return assert(dependencies[name], name) end
		f.controller, f.aim, f.action, f.active = load("Controller", f.env), aim, action, active
		f.controller.Init()
		f.hud, f.ammoLabel = f.created[1], f.created[2]
		for _, obj in ipairs(f.created) do
			if obj.Text == "SHOOT" then f.shootButton = obj
			elseif obj.Text == "RELOAD" then f.reloadButton = obj
			elseif obj.Text == "AIM" then f.aimButton = obj end
		end
		function f.snapshot(ammo, reload, ack)
			snapshot.OnClientEvent:Fire({ Character = f.character, Session = "session", Revision = (f.revision or 0) + 1,
				AckSequence = ack or 0, Ammo = ammo, ReloadEnd = reload or 0, NextShot = 0 })
			f.revision = (f.revision or 0) + 1
		end
		function f.inputObject(kind, key) return { UserInputType = f.env.Enum.UserInputType[kind], KeyCode = f.env.Enum.KeyCode[key or "Unknown"] } end
		return f
	end
	test("RMB hold starts ADS and release restores it even for processed input", function()
		local f = controllerFixture(); f.snapshot(3)
		local right = f.inputObject("MouseButton2")
		f.input.InputBegan:Fire(right, false); assert(f.aim.IsAiming())
		f.input.InputEnded:Fire(right, true); assert(not f.aim.IsAiming())
		f.input.InputBegan:Fire(right, true); assert(not f.aim.IsAiming())
		f.input.InputBegan:Fire(right, false); f.input.WindowFocusReleased:Fire(); assert(not f.aim.IsAiming())
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
		function damage:FireClient() f.damageCalls = (f.damageCalls or 0) + 1 end
		knife.children, remotes.children = { damage }, { revolver, knife }
		f.action, f.snapshotRemote, f.shot, f.poseRemote = object("RemoteEvent", "Action"), object("RemoteEvent", "State"), object("RemoteEvent", "Shot"), object("UnreliableRemoteEvent", "Aim")
		for _, remote in ipairs({ f.action, f.snapshotRemote, f.shot, f.poseRemote }) do remote.OnServerEvent = signal() end
		function f.snapshotRemote:FireClient(_, data) f.snapshotData = data end
		function f.shot:FireAllClients() f.shotCalls = (f.shotCalls or 0) + 1 end
		f.posePackets = {}
		function f.poseRemote:FireAllClients(...) table.insert(f.posePackets, { ... }) end
		revolver.children = { f.action, f.snapshotRemote, f.shot, f.poseRemote }
		local rs = object("Folder", "ReplicatedStorage")
		rs.children, rs.Remotes = { remotes }, remotes
		rs.Modules = { RevolverConfig = "Config", RevolverMath = "RayMath", RevolverRaycast = "Raycast", RevolversInfo = "Catalog", RevolverPoseMath = "Math" }
		f.services.ReplicatedStorage = rs
		local state = load("State")
		local dependencies = { Config = f.config, RayMath = RayMath, Math = Math, Catalog = { [f.tool.Name] = {} }, State = state,
			Game = f.mainGame, History = { Sample = function() end, Remove = function() end },
			Raycast = { GetMuzzle = function(_, head) return head.Position end,
				Resolve = function() f.rayCalls = (f.rayCalls or 0) + 1; return { position = V(0, 2, -20) } end } }
		f.env.require = function(name) return assert(dependencies[name], name) end
		f.env.script = { Parent = { RevolverState = "State", RevolverHitHistory = "History", Parent = { Game = { MainGame = "Game" } } } }
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
	print(string.format("%d revolver presentation tests passed", passed))
end
