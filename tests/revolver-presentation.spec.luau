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
	vm.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
		if key == "Unit" then return v / v.Magnitude end
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
	function Frame:Lerp(other, alpha)
		local r = {}; for i = 1, 9 do r[i] = self.matrix[i] + (other.matrix[i] - self.matrix[i]) * alpha end
		return frame(self.Position + (other.Position - self.Position) * alpha, r)
	end
	fm.__index = function(cf, key)
		if key == "Rotation" then return frame(Vector.zero, cf.matrix) end
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
	function Frame.lookAt(position) return Frame.new(position) end -- rendering stand-in only
	Frame.identity = Frame.new()
	local Config = load("Config")
	local Math = load("Math", { CFrame = Frame })
	local settings = Config.Default.Pose
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
	test("shoulder solution preserves its anchor for R6 and R15", function()
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
		Config.Overrides.Test = { Pose = { MaxPitchDegrees = 60 }, Effects = { SmokeEnabled = false } }
		local tuning = Config.Get("Test")
		assert(tuning.Pose.MaxPitchDegrees == 60 and tuning.Pose.FollowSpeed == settings.FollowSpeed)
		assert(tuning.Effects.SmokeEnabled == false and tuning.Effects.MuzzleFlashEnabled)
		assert(Config.Default.Pose.MaxPitchDegrees == 75 and Config.Default.Effects.SmokeEnabled)
		Config.Overrides.Test = nil
	end)

	local function signal()
		local handlers = {}
		return { Connect = function(_, fn) table.insert(handlers, fn); return { Disconnect = function() end } end,
			Fire = function(_, ...) for _, fn in ipairs(handlers) do fn(...) end end }
	end
	local function object(class, name)
		local obj = { ClassName = class, Name = name, children = {}, Transform = Frame.identity }
		function obj:IsA(kind) return kind == class or (kind == "BasePart" and class == "Part") end
		function obj:GetChildren() return self.children end
		function obj:GetDescendants()
			local result = {}; for _, child in ipairs(self.children) do table.insert(result, child); for _, d in ipairs(child:GetDescendants()) do table.insert(result, d) end end
			return result
		end
		function obj:FindFirstChild(childName) for _, child in ipairs(self.children) do if child.Name == childName then return child end end end
		function obj:FindFirstChildOfClass(kind) for _, child in ipairs(self.children) do if child:IsA(kind) then return child end end end
		function obj:Destroy() self.Parent = nil; self.destroyed = true; for _, child in ipairs(self.children) do child:Destroy() end end
		function obj:Emit(count) self.emitted = (self.emitted or 0) + count end
		function obj:Play() self.played = true end
		return obj
	end
	local function fixture(upgraded)
		local character, torso, arm = object("Model", "Character"), object("Part", "Torso"), object("Part", "Right Arm")
		torso.CFrame, arm.CFrame = Frame.new(), Frame.new(1.5, 0, 0)
		local humanoid = object("Humanoid", "Humanoid"); humanoid.Health = 100
		local tool = object("Tool", "Amber Revolver"); tool.Parent = character
		local joint = object(upgraded and "AnimationConstraint" or "Motor6D", "Right Shoulder")
		local c0, c1 = Frame.new(1, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0), Frame.new(-0.5, 0.5, 0) * Frame.Angles(0, math.pi / 2, 0)
		joint.Parent, joint.Part0, joint.Part1, joint.C0, joint.C1 = torso, torso, arm, c0, c1
		if upgraded then
			joint.Attachment0 = { Parent = torso, CFrame = c0 }; joint.Attachment1 = { Parent = arm, CFrame = c1 }
		end
		torso.children = { joint }; character.children = { torso, arm, humanoid, tool }
		character.Parent = {}
		local player = { Character = character, UserId = 1 }
		local now, created = 100, {}
		local events = { PreAnimation = signal(), PreSimulation = signal(), RenderStepped = signal() }
		local players = { LocalPlayer = player, PlayerRemoving = signal(), GetPlayers = function() return { player } end, GetPlayerByUserId = function() return nil end }
		local remote = { OnClientEvent = signal(), sent = {} }
		function remote:FireServer(...) table.insert(self.sent, { ... }) end
		local services = { Players = players, RunService = events, ReplicatedStorage = { Modules = { RevolverConfig = "Config", RevolversInfo = "Catalog", RevolverPoseMath = "Math" } },
			Debris = { AddItem = function() end }, TweenService = { Create = function() return { Play = function() end } end } }
		local function constructor(...) return { ... } end
		local env = {
			game = { GetService = function(_, name) return assert(services[name], name) end }, workspace = { GetServerTimeNow = function() return now end },
			os = { clock = function() return now end }, CFrame = Frame, Vector3 = Vector,
			Vector2 = { new = constructor }, Color3 = { new = constructor, fromRGB = constructor },
			ColorSequence = { new = constructor }, ColorSequenceKeypoint = { new = constructor },
			NumberRange = { new = constructor }, NumberSequence = { new = constructor }, NumberSequenceKeypoint = { new = constructor }, TweenInfo = { new = constructor },
			typeof = function(value) return type(value) == "table" and value.kind or typeof(value) end,
			Enum = { Material = { Neon = "Neon" }, NormalId = { Front = "Front" }, TextureMode = { Stretch = "Stretch" }, AnimationPriority = { Action4 = "Action4" } },
			Instance = { new = function(class) local obj = object(class, class); table.insert(created, obj); return obj end },
			require = function(name) return assert(({ Config = Config, Math = Math, Catalog = { ["Amber Revolver"] = {} } })[name]) end,
		}
		local f = { env = env, joint = joint, torso = torso, tool = tool, player = player, character = character, events = events, created = created, remote = remote }
		function f.advance(dt) now += dt; events.RenderStepped:Fire() end
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
	test("AnimationConstraint rigs use attachment frames without editing them", function()
		local f = fixture(true); local pose = load("Pose", f.env); pose.Init(f.remote)
		local original = f.joint.Attachment0.CFrame
		pose.SetLocalAim(f.tool, V(0, 20, -40), false); f.step()
		assert(f.joint.Transform ~= Frame.identity and f.joint.Attachment0.CFrame == original)
		pose.ResetLocal(); assert(f.joint.Transform == Frame.identity)
	end)
	test("R15 elbow and wrist animations cannot pull the held gun down", function()
		local f = fixture(false)
		f.torso.Name = "UpperTorso"; f.joint.Part1.Name = "RightUpperArm"
		local lower, hand = object("Part", "RightLowerArm"), object("Part", "RightHand")
		local elbow, wrist = object("Motor6D", "RightElbow"), object("Motor6D", "RightWrist")
		elbow.Part0, elbow.Part1, elbow.C0, elbow.C1, elbow.Parent = f.joint.Part1, lower, Frame.identity, Frame.identity, f.joint.Part1
		wrist.Part0, wrist.Part1, wrist.C0, wrist.C1, wrist.Parent = lower, hand, Frame.identity, Frame.identity, lower
		elbow.Transform, wrist.Transform = Frame.Angles(0.6, 0, 0), Frame.Angles(0, 0, 0.4)
		f.joint.Part1.children, lower.children = { elbow }, { wrist }
		table.insert(f.character.children, lower); table.insert(f.character.children, hand)
		local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetLocalAim(f.tool, V(0, 10, -40), false)
		for _ = 1, 120 do f.step() end
		for index = 1, 9 do near(elbow.Transform.matrix[index], identity[index]); near(wrist.Transform.matrix[index], identity[index]) end
	end)
	test("pose networking is throttled and follows the current session", function()
		local f = fixture(false); local pose = load("Pose", f.env); pose.Init(f.remote); pose.SetSession("one")
		for _ = 1, 100 do pose.SetLocalAim(f.tool, V(0, 20, -40), false) end
		assert(#f.remote.sent == 1 and f.remote.sent[1][1] == "one")
		f.advance(0.1); pose.SetLocalAim(f.tool, V(0, 20, -40), false); assert(#f.remote.sent == 2)
		pose.SetSession("two"); pose.SetLocalAim(f.tool, V(0, 20, -40), false)
		assert(f.remote.sent[3][1] == "two" and f.remote.sent[3][2] == 1)
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
	end)
	print(string.format("%d revolver presentation tests passed", passed))
end
