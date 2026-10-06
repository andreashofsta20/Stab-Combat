-- Executes the production render controller in a deterministic camera scheduler.
local Vector, vectorMeta = {}, {}
function Vector.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vectorMeta) end
function vectorMeta.__index(v, key) if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end end
function vectorMeta.__add(a, b) return Vector.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__sub(a, b) return Vector.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
local Frame, frameMeta = {}, {}
function Frame.new(x, y, z, rotation) return setmetatable({Position = Vector.new(x, y, z), rotation = rotation or "native"}, frameMeta) end
function frameMeta.__add(frame, offset)
	return Frame.new(frame.Position.X+offset.X, frame.Position.Y+offset.Y, frame.Position.Z+offset.Z, frame.rotation)
end
function frameMeta.__eq(a, b)
	return a.Position.X == b.Position.X and a.Position.Y == b.Position.Y and a.Position.Z == b.Position.Z and a.rotation == b.rotation
end
local function near(actual, expected, tolerance) assert(math.abs(actual-expected) <= (tolerance or 1e-7), tostring(actual) .. " ~= " .. tostring(expected)) end
local function character()
	local model = {attributes = {}}
	model.humanoid = {Parent = model, Health = 100, CameraOffset = "untouched", AutoRotate = true}
	model.root = {CFrame = "untouched", AssemblyLinearVelocity = "untouched"}
	function model:FindFirstChildOfClass(name) return name == "Humanoid" and self.humanoid or nil end
	function model:GetAttribute(name) return self.attributes[name] end
	function model:SetAttribute(name, value) self.attributes[name] = value end
	return model
end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, failure = pcall(fn)
		if not ok then error(name .. ": " .. tostring(failure), 0) end
		passed += 1; print("PASS " .. name)
	end
	local function fixture()
		local f = {bindings = {}, binds = 0, warnings = {}, config = load("Config"), character = character()}
		f.player = {Character = f.character}
		f.camera = {CFrame = Frame.new(0,5,0), Focus = Frame.new(0,5,-0.5), CameraType = "Custom", CameraSubject = f.character.humanoid}
		f.workspace, f.vr = {CurrentCamera = f.camera}, {VREnabled = false}
		local run = {}
		function run:BindToRenderStep(name, priority, fn) assert(not f.bindings[name]); f.binds += 1; f.bindings[name] = {priority = priority, fn = fn} end
		function run:UnbindFromRenderStep(name) f.bindings[name] = nil end
		local services = {Players = {LocalPlayer = f.player}, ReplicatedStorage = {Modules = {FirstPersonCameraConfig = "Config"}}, RunService = run, VRService = f.vr}
		f.env = {game = {GetService = function(_, name) return assert(services[name], name) end}, workspace = f.workspace, Vector3 = Vector,
			Enum = {CameraType = {Custom = "Custom"}, RenderPriority = {Camera = {Value = 200}}},
			require = function(name) assert(name == "Config"); return f.config end,
			warn = function(message) table.insert(f.warnings, message) end}
		f.controller = load("Camera", f.env); f.controller.Init()
		function f.before() f.bindings.FirstPersonPostureRestore.fn() end
		function f.after(dt) f.bindings.FirstPersonPostureCamera.fn(dt or 1/60); assert(#f.warnings == 0, f.warnings[1]) end
		function f.step(dt) f.before(); f.after(dt) end
		function f.posture(name) f.player.Character:SetAttribute(f.config.PostureAttribute, name) end
		function f.setZoom(distance) f.before(); f.camera.Focus = Frame.new(f.camera.CFrame.Position.X, f.camera.CFrame.Position.Y, f.camera.CFrame.Position.Z-distance) end
		return f
	end
	test("render order brackets native camera and precedes both weapon models", function()
		local f = fixture(); f.controller.Init(); assert(f.binds == 2)
		assert(f.bindings.FirstPersonPostureRestore.priority == 199 and f.bindings.FirstPersonPostureCamera.priority == 202)
		f.posture("Crouch"); f.step(); f.controller.Destroy(); assert(next(f.bindings) == nil); near(f.camera.CFrame.Position.Y, 5)
		f.controller.Init(); assert(f.binds == 4)
	end)
	test("crouch lowers eyes smoothly then smoothly returns to standing", function()
		local f = fixture(); f.posture("Crouch"); f.step(1/60)
		assert(f.camera.CFrame.Position.Y < 5 and f.camera.CFrame.Position.Y > 5-f.config.CrouchDrop)
		for _ = 1, 120 do f.step(1/60) end
		near(f.camera.CFrame.Position.Y, 5-f.config.CrouchDrop, 1e-6)
		local lower = f.camera.CFrame.Position.Y; f.posture("Stand"); f.step(1/60)
		assert(f.camera.CFrame.Position.Y > lower and f.camera.CFrame.Position.Y < 5)
		for _ = 1, 120 do f.step(1/60) end; near(f.camera.CFrame.Position.Y, 5)
	end)
	test("slide is visibly lower than crouch without an instantaneous snap", function()
		local f = fixture(); f.posture("Crouch"); f.step(1)
		local crouch = f.camera.CFrame.Position.Y; f.posture("Slide"); f.step(1/60)
		assert(f.camera.CFrame.Position.Y < crouch and f.camera.CFrame.Position.Y > 5-f.config.SlideDrop)
		f.step(1); near(f.camera.CFrame.Position.Y, 5-f.config.SlideDrop, 1e-6)
	end)
	test("posture smoothing gives the same height at thirty and one hundred twenty FPS", function()
		local slow, fast = fixture(), fixture(); slow.posture("Slide"); fast.posture("Slide")
		for _ = 1, 30 do slow.step(1/30) end; for _ = 1, 120 do fast.step(1/120) end
		near(slow.camera.CFrame.Position.Y, fast.camera.CFrame.Position.Y)
	end)
	test("lowering only activates at full zoom with the same narrow weapon hysteresis", function()
		local f = fixture(); f.posture("Crouch"); f.setZoom(0.56); f.step(1); near(f.camera.CFrame.Position.Y, 5)
		f.setZoom(0.54); f.step(1); assert(f.camera.CFrame.Position.Y < 5)
		f.setZoom(0.59); f.step(1); assert(f.camera.CFrame.Position.Y < 5)
		f.setZoom(0.6); f.step(1); near(f.camera.CFrame.Position.Y, 5)
	end)
	test("camera and Focus shift equally so the weapon zoom distance stays exact", function()
		local f = fixture(); f.posture("Slide"); f.step(1)
		near((f.camera.CFrame.Position-f.camera.Focus.Position).Magnitude, 0.5)
		near(f.camera.CFrame.Position.Y, f.camera.Focus.Position.Y)
	end)
	test("height remains world vertical and preserves native look rotation at any pitch", function()
		local f = fixture(); f.camera.CFrame = Frame.new(2,5,9,"look-straight-down")
		f.camera.Focus = Frame.new(2,4.5,9,"look-straight-down"); f.posture("Slide"); f.step(1)
		near(f.camera.CFrame.Position.X, 2); near(f.camera.CFrame.Position.Z, 9)
		assert(f.camera.CFrame.rotation == "look-straight-down" and f.camera.Focus.rotation == "look-straight-down")
	end)
	test("restoring before native update prevents cumulative camera drift", function()
		local f = fixture(); f.posture("Slide")
		for _ = 1, 600 do f.step(1/60) end
		near(f.camera.CFrame.Position.Y, 5-f.config.SlideDrop)
		f.before(); near(f.camera.CFrame.Position.Y, 5); near(f.camera.Focus.Position.Y, 5)
	end)
	test("new native translation is preserved while posture only changes height", function()
		local f = fixture(); f.posture("Slide"); f.step(1); f.before()
		f.camera.CFrame, f.camera.Focus = Frame.new(30,10,15,"turn"), Frame.new(30,10,14.5,"turn")
		f.after(1); near(f.camera.CFrame.Position.X,30); near(f.camera.CFrame.Position.Y,9); near(f.camera.CFrame.Position.Z,15)
		assert(f.camera.CFrame.rotation == "turn")
	end)
	test("VR scripted spectator dead and ragdolled cameras release lowering immediately", function()
		for _, deactivate in ipairs({function(f) f.vr.VREnabled = true end,
			function(f) f.camera.CameraSubject = {} end,
			function(f) f.character.humanoid.Health = 0 end,
			function(f) f.character:SetAttribute("Ragdolled",true) end}) do
			local f = fixture(); f.posture("Slide"); f.step(1); deactivate(f); f.step(1); near(f.camera.CFrame.Position.Y,5)
		end
	end)
	test("Scriptable takeover preserves even the last owned posture frame and Focus", function()
		local f = fixture(); f.posture("Slide"); f.step(1)
		local frame, focus = f.camera.CFrame, f.camera.Focus
		f.camera.CameraType = "Scriptable"; f.step(1); f.controller.Destroy()
		assert(f.camera.CFrame == frame and f.camera.Focus == focus and f.camera.CameraType == "Scriptable")
	end)
	test("camera replacement restores the previous view and starts a fresh blend", function()
		local f = fixture(); f.posture("Slide"); f.step(1)
		local nextCamera = {CFrame = Frame.new(0,8,0), Focus = Frame.new(0,8,-0.5), CameraType = "Custom", CameraSubject = f.character.humanoid}
		f.workspace.CurrentCamera = nextCamera; f.step(1/60)
		near(f.camera.CFrame.Position.Y,5); assert(nextCamera.CFrame.Position.Y < 8 and nextCamera.CFrame.Position.Y > 7)
	end)
	test("respawn drops old posture and waits for delayed Humanoid replication", function()
		local f = fixture(); f.posture("Slide"); f.step(1); local replacement = character()
		local nextHumanoid = replacement.humanoid; replacement.humanoid = nil
		f.player.Character = replacement; f.camera.CameraSubject = nextHumanoid; f.step(1); near(f.camera.CFrame.Position.Y,5)
		replacement.humanoid = nextHumanoid; f.posture("Crouch"); f.step(1); near(f.camera.CFrame.Position.Y,5-f.config.CrouchDrop,1e-6)
	end)
	test("a replacement Humanoid in the same character is discovered", function()
		local f = fixture(); f.posture("Crouch"); f.step(1)
		f.character.humanoid.Parent = nil; f.character.humanoid = {Parent = f.character,Health = 100}
		f.camera.CameraSubject = f.character.humanoid; f.step(1); near(f.camera.CFrame.Position.Y,5-f.config.CrouchDrop,1e-6)
	end)
	test("cleanup preserves camera fields another camera script has replaced", function()
		local f = fixture(); f.posture("Slide"); f.step(1)
		f.camera.CFrame, f.camera.Focus = Frame.new(100,50,70,"spectator"), Frame.new(100,50,60,"spectator")
		f.controller.Destroy(); near(f.camera.CFrame.Position.Y,50); assert(f.camera.CFrame.rotation == "spectator")
	end)
	test("camera presentation never writes root physics or the ADS-owned offset", function()
		local f = fixture(); f.posture("Slide"); for _ = 1,120 do f.step(1/60) end
		assert(f.character.root.CFrame == "untouched" and f.character.root.AssemblyLinearVelocity == "untouched")
		assert(f.character.humanoid.CameraOffset == "untouched" and f.character.humanoid.AutoRotate == true)
	end)
	test("negative render delta does not move the camera or corrupt the blend", function()
		local f = fixture(); f.posture("Slide"); f.step(-1); near(f.camera.CFrame.Position.Y,5)
		f.step(1); near(f.camera.CFrame.Position.Y,4,1e-6)
	end)
	test("standalone client initializes the camera and disconnects on script destruction", function()
		local calls, callback = {}, nil
		load("Initialize",{script = {Parent = {Modules = {FirstPersonPostureCamera = "Camera"}},Destroying = {Connect = function(_, fn) callback = fn end}},
			require = function(name) assert(name == "Camera"); return {Init = function() table.insert(calls,"init") end,Destroy = function() table.insert(calls,"destroy") end} end})
		assert(calls[1] == "init"); callback(); assert(calls[2] == "destroy")
	end)
	print(string.format("%d first-person camera tests passed",passed))
end
