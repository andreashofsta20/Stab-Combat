-- Actual inspect sources. Frames below measure timing and cancellation, not native quaternion rendering.
local function signal()
	local listeners, event = {}, {}
	function event:Connect(fn)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false end
		table.insert(listeners, {fn = fn, connection = connection})
		return connection
	end
	function event:Fire(...)
		for _, listener in ipairs(table.clone(listeners)) do if listener.connection.Connected then listener.fn(...) end end
	end
	function event:Count()
		local count = 0; for _, listener in ipairs(listeners) do if listener.connection.Connected then count += 1 end end
		return count
	end
	return event
end
local methods, meta = {}, {}
function meta.__index(self, key)
	if methods[key] then return methods[key] end
	if self.props[key] ~= nil then return self.props[key] end
	if self.signals[key] then return self.signals[key] end
	for _, child in ipairs(self.children) do if child.Name == key then return child end end
end
function meta.__newindex(self, key, value)
	local old = self.props[key]
	if old == value then return end
	if key == "Parent" then
		if old then local index = table.find(old.children, self); if index then table.remove(old.children, index) end end
		self.props.Parent = value
		if old then old.ChildRemoved:Fire(self) end
		if value then table.insert(value.children, self); value.ChildAdded:Fire(self) end
	else self.props[key] = value end
	if self.signals["Property_" .. key] then self.signals["Property_" .. key]:Fire() end
end
local function object(class, name, parent)
	local result = setmetatable({props = {ClassName = class, Name = name or class}, children = {}, attributes = {}, signals = {}}, meta)
	for _, name in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying", "CharacterAdded", "CharacterRemoving", "InputBegan", "WindowFocusReleased", "TextBoxFocused", "MenuOpened"}) do result.signals[name] = signal() end
	result.Parent = parent
	return result
end
function methods:IsA(class)
	return self.ClassName == class or class == "Instance" or class == "GuiObject" and (self.ClassName == "Frame" or self.ClassName == "ImageLabel" or self.ClassName == "TextButton")
end
function methods:GetChildren() self.ChildScans = (self.ChildScans or 0) + 1; return table.clone(self.children) end
function methods:GetDescendants()
	local result = {}; for _, child in ipairs(self.children) do table.insert(result, child); for _, descendant in ipairs(child:GetDescendants()) do table.insert(result, descendant) end end
	return result
end
function methods:FindFirstChild(name)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:SetAttribute(name, value) self.attributes[name] = value end
function methods:GetPropertyChangedSignal(name)
	self.signals["Property_" .. name] = self.signals["Property_" .. name] or signal()
	return self.signals["Property_" .. name]
end
local function near(actual, expected) assert(math.abs(actual - expected) < 1e-7, tostring(actual) .. " ~= " .. tostring(expected)) end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); passed += 1; print("PASS " .. name)
	end
	local Frame, frameMeta, frameCreations = {}, {}, 0
	frameMeta.__index = Frame
	local function frame(x, y, z, rx, ry, rz)
		frameCreations += 1
		return setmetatable({Position = {X = x or 0, Y = y or 0, Z = z or 0}, angles = {rx or 0, ry or 0, rz or 0}}, frameMeta)
	end
	function Frame.new(x, y, z) return frame(x, y, z) end
	function Frame.Angles(x, y, z) return frame(0, 0, 0, x, y, z) end
	function Frame:Lerp(other, alpha)
		local p, q, r, s = self.Position, other.Position, self.angles, other.angles
		return frame(p.X+(q.X-p.X)*alpha, p.Y+(q.Y-p.Y)*alpha, p.Z+(q.Z-p.Z)*alpha,
			r[1]+(s[1]-r[1])*alpha, r[2]+(s[2]-r[2])*alpha, r[3]+(s[3]-r[3])*alpha)
	end
	frameMeta.__mul = function(a, b)
		-- Production presets multiply only a translation by a pure rotation.
		local p, q, r, s = a.Position, b.Position, a.angles, b.angles
		return frame(p.X+q.X, p.Y+q.Y, p.Z+q.Z, r[1]+s[1], r[2]+s[2], r[3]+s[3])
	end
	Frame.identity = Frame.new()
	local positionMeta = {}
	local function position(x, y, z) return setmetatable({X = x, Y = y, Z = z}, positionMeta) end
	positionMeta.__sub = function(a, b) return position(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
	positionMeta.__index = function(value, key)
		if key == "Magnitude" then return math.sqrt(value.X*value.X + value.Y*value.Y + value.Z*value.Z) end
	end
	local config = load("Config")
	local motion = load("Motion", {CFrame = Frame, script = {Parent = {WeaponInspectConfig = "Config"}}, require = function(name) equal(name, "Config"); return config end})
	local function samePose(a, b)
		for _, axis in ipairs({"X", "Y", "Z"}) do near(a.Position[axis], b.Position[axis]) end
		for i = 1, 3 do near(a.angles[i], b.angles[i]) end
	end
	test("fixed F config has bounded durations and ordered zero-to-zero keyframes", function()
		equal(config.Key, "F"); equal(config.CooldownSeconds, 0.5); assert(config.ReturnSeconds > 0 and config.ReturnSeconds <= 0.2)
		for _, kind in ipairs({"Revolver", "Knife"}) do
			local preset = config[kind]; assert(preset.Duration > 1 and preset.Duration <= 6)
			equal(preset.Frames[1].Time, 0); equal(preset.Frames[#preset.Frames].Time, 1)
			for i = 2, #preset.Frames do assert(preset.Frames[i].Time > preset.Frames[i-1].Time) end
			for _, key in ipairs({preset.Frames[1], preset.Frames[#preset.Frames]}) do
				for i = 1, 3 do equal(key.Position[i], 0); equal(key.Rotation[i], 0) end
			end
		end
	end)
	test("both presets finish on elapsed time and restart with clean state", function()
		for _, kind in ipairs({"Revolver", "Knife"}) do
			local state = motion.New(); equal(motion.Start(state, kind), true); equal(motion.IsActive(state), true)
			local pose = motion.Step(state, config[kind].Duration * 0.36); assert(pose.Position.Y > 0 and pose.Position.X < 0)
			equal(motion.Step(state, config[kind].Duration), Frame.identity); equal(motion.IsActive(state), false)
			equal(state.preset, nil); equal(motion.Start(state, kind), true); samePose(motion.Step(state, 0), Frame.identity)
		end
	end)
	test("time-based poses match at 30 and 144 FPS with no accumulating lag", function()
		for _, kind in ipairs({"Revolver", "Knife"}) do
			local a, b = motion.New(), motion.New(); motion.Start(a, kind); motion.Start(b, kind)
			for _ = 1, 15 do motion.Step(a, 1/30) end
			for _ = 1, 72 do motion.Step(b, 1/144) end
			samePose(a.pose, b.pose)
		end
	end)
	test("negative delta does not reverse the inspect pose or segment", function()
		local state = motion.New(); motion.Start(state, "Knife"); motion.Step(state, 1)
		local elapsed, segment, pose = state.elapsed, state.segment, state.pose
		samePose(motion.Step(state, -1), pose); equal(state.elapsed, elapsed); equal(state.segment, segment)
	end)
	test("early cancel returns smoothly and repeated cancel does not restart its timer", function()
		for _, kind in ipairs({"Revolver", "Knife"}) do
			local state = motion.New(); motion.Start(state, kind); motion.Step(state, config[kind].Duration * 0.36)
			local from = state.pose; motion.Cancel(state, false); equal(state.playing, false); equal(state.returning, true)
			local halfway = motion.Step(state, config.ReturnSeconds / 2)
			near(halfway.Position.Y, from.Position.Y / 2); motion.Cancel(state, false)
			motion.Step(state, config.ReturnSeconds / 2); equal(motion.IsActive(state), false); equal(state.pose, Frame.identity)
		end
	end)
	test("immediate cancellation clears held pose and unknown kinds cannot start", function()
		local state = motion.New(); equal(motion.Start(state, "Food"), false); equal(motion.IsActive(state), false)
		motion.Start(state, "Revolver"); motion.Step(state, 0.5); equal(motion.Start(state, "Knife"), false)
		motion.Cancel(state, true); equal(state.pose, Frame.identity); equal(state.returnFrom, nil); equal(state.preset, nil)
		equal(motion.Start(state, "Knife"), true)
	end)
	test("idle motion returns shared identity without building frames", function()
		local state = motion.New(); local before = frameCreations
		for _ = 1, 500 do equal(motion.Step(state, 1/60), Frame.identity) end
		equal(frameCreations, before)
	end)
	local function fixture()
		local f = {time = 100, modules = {}}
		f.player = object("Player", "Player"); f.player:SetAttribute("DataReady", true)
		f.character = object("Model", "Character"); f.player.Character = f.character
		f.humanoid = object("Humanoid", "Humanoid", f.character)
		f.humanoid.Health, f.humanoid.WalkSpeed, f.humanoid.FloorMaterial, f.humanoid.Sit = 100, 16, "Concrete", false
		f.camera = {CameraType = "Custom", CameraSubject = f.humanoid,
			CFrame = {Position = position(0, 2, 0)}, Focus = {Position = position(0, 2, -0.5)}}
		f.ui = {InputBegan = signal(), WindowFocusReleased = signal(), TextBoxFocused = signal(), GetFocusedTextBox = function() return f.textBox end}
		f.gui = {MenuIsOpen = false, MenuOpened = signal()}; f.vr = {VREnabled = false}
		f.rs = object("Folder", "ReplicatedStorage"); local moduleFolder = object("Folder", "Modules", f.rs)
		f.guiFolder = object("PlayerGui", "PlayerGui", f.player); f.main = object("ScreenGui", "Main", f.guiFolder)
		f.frames = object("Folder", "Frames", f.main); f.settings = object("Frame", "Settings", f.frames); f.settings.Visible = false
		f.emote = object("Frame", "background", object("Frame", "EmoteFrame", f.main)); f.emote.Visible = false
		local controllerFolder = object("Folder", "Modules")
		f.env = {workspace = {CurrentCamera = f.camera}, game = {GetService = function(_, name)
			return assert(({Players = {LocalPlayer = f.player}, ReplicatedStorage = f.rs, UserInputService = f.ui, GuiService = f.gui, VRService = f.vr})[name], name)
		end}, require = function(module) return assert(f.modules[module], tostring(module and module.Name)) end,
			os = {clock = function() return f.time end}, Enum = {UserInputType = {Keyboard = "Keyboard"}, KeyCode = {F = "F", E = "E"}, CameraType = {Custom = "Custom"}, Material = {Air = "Air"}}}
		f.modules[object("ModuleScript", "WeaponInspectConfig", moduleFolder)] = config
		f.modules[object("ModuleScript", "RevolversInfo", moduleFolder)] = {GunA = {}}
		f.modules[object("ModuleScript", "KnivesInfo", moduleFolder)] = {KnifeA = {}}
		local function view()
			local presenter = {active = true, starts = 0, cancels = 0, state = motion.New()}
			function presenter.IsActive(tool) return presenter.active and presenter.tool == tool end
			function presenter.IsInspecting(tool) return presenter.IsActive(tool) and motion.IsActive(presenter.state) end
			function presenter.CancelInspect(immediate) presenter.cancels += 1; presenter.lastCancel = immediate; motion.Cancel(presenter.state, immediate) end
			function presenter.StartInspect(tool)
				if presenter.busy or not presenter.IsActive(tool) then return false end
				if motion.Start(presenter.state, presenter.kind) then presenter.starts += 1; return true end
				return false
			end
			return presenter
		end
		f.gunView, f.knifeView = view(), view(); f.gunView.kind, f.knifeView.kind = "Revolver", "Knife"
		f.modules[object("ModuleScript", "RevolverViewmodel", controllerFolder)] = f.gunView
		f.modules[object("ModuleScript", "KnifeViewmodel", controllerFolder)] = f.knifeView
		f.env.script = object("ModuleScript", "WeaponInspectController", controllerFolder)
		f.controller = load("Controller", f.env)
		function f:equip(kind)
			for _, item in ipairs(self.character.children) do if item:IsA("Tool") then item.Parent = nil end end
			local presenter = kind == "Knife" and self.knifeView or self.gunView
			local tool = object("Tool", kind == "Knife" and "KnifeA" or "GunA", self.character)
			presenter.tool, presenter.state = tool, motion.New()
			return tool, presenter
		end
		function f:press(processed, key, inputType)
			self.ui.InputBegan:Fire({UserInputType = inputType or "Keyboard", KeyCode = key or "F"}, processed == true)
		end
		f:equip("Revolver"); f.controller.Init()
		return f
	end
	test("fixed F starts only its equipped active first-person presenter", function()
		local f = fixture(); f:press(false, "E"); f:press(false, "F", "MouseButton1"); equal(f.gunView.starts, 0)
		f:press(); equal(f.gunView.starts, 1); equal(f.knifeView.starts, 0)
		f.time += 1; f.gunView.CancelInspect(true); f:equip("Knife"); f:press(); equal(f.knifeView.starts, 1)
	end)
	test("processed input focused text Roblox menu and custom modal UI block start", function()
		for _, gate in ipairs({"processed", "chat", "menu", "settings", "emote"}) do
			local f = fixture()
			if gate == "chat" then f.textBox = {} elseif gate == "menu" then f.gui.MenuIsOpen = true
			elseif gate == "settings" then f.settings.Visible = true elseif gate == "emote" then f.emote.Visible = true end
			f:press(gate == "processed"); equal(f.gunView.starts, 0)
		end
	end)
	test("unready dead ragdolled VR and foreign cameras block start", function()
		for _, gate in ipairs({"data", "dead", "ragdoll", "vr", "cameraType", "cameraSubject", "cameraMissing", "characterMissing"}) do
			local f = fixture()
			if gate == "data" then f.player:SetAttribute("DataReady", false) elseif gate == "dead" then f.humanoid.Health = 0
			elseif gate == "ragdoll" then f.character:SetAttribute("Ragdolled", true) elseif gate == "vr" then f.vr.VREnabled = true
			elseif gate == "cameraType" then f.camera.CameraType = "Scriptable" elseif gate == "cameraSubject" then f.camera.CameraSubject = {}
			elseif gate == "cameraMissing" then f.env.workspace.CurrentCamera = nil else f.player.Character = nil end
			f:press(); equal(f.gunView.starts, 0)
		end
	end)
	test("live camera zoom blocks a stale first-person presenter after zooming out", function()
		local f = fixture(); f.camera.Focus.Position = position(0, 2, -config.MaxCameraDistance - 0.001)
		f:press(); equal(f.gunView.starts, 0)
		f.camera.Focus.Position = position(0, 2, -0.5); f:press(); equal(f.gunView.starts, 1)
	end)
	test("slide jump and seating block inspect without changing their state", function()
		for _, gate in ipairs({"slide", "jump", "seat"}) do
			local f = fixture()
			if gate == "slide" then f.character:SetAttribute(config.PostureAttribute, "Slide")
			elseif gate == "jump" then f.humanoid.FloorMaterial = "Air" else f.humanoid.Sit = true end
			f:press(); equal(f.gunView.starts, 0)
			if gate == "seat" then equal(f.humanoid.Sit, true) end
		end
	end)
	test("sprint inspection starts without changing the humanoid speed", function()
		local f = fixture(); f.humanoid.WalkSpeed = 32
		f:press(); equal(f.gunView.starts, 1); equal(f.humanoid.WalkSpeed, 32)
	end)
	test("inactive incomplete unequipped backpack and unknown tools cannot inspect", function()
		for _, gate in ipairs({"inactive", "busy", "unequipped", "backpack", "unknown"}) do
			local f = fixture()
			if gate == "inactive" then f.gunView.active = false elseif gate == "busy" then f.gunView.busy = true
			elseif gate == "unknown" then f.gunView.tool.Name = "Food"
			else f.gunView.tool.Parent = gate == "backpack" and object("Backpack", "Backpack", f.player) or nil end
			f:press(); equal(f.gunView.starts, 0)
		end
	end)
	test("F cancels early even within cooldown and cannot restart the return pose", function()
		local f = fixture(); f:press(); motion.Step(f.gunView.state, 0.5)
		f.time += 0.01; f:press(); equal(f.gunView.lastCancel, false); equal(f.gunView.state.returning, true)
		f:press(); equal(f.gunView.starts, 1); motion.Step(f.gunView.state, config.ReturnSeconds)
		f:press(); equal(f.gunView.starts, 1)
		f.time += 0.5; f:press(); equal(f.gunView.starts, 2)
	end)
	test("cooldown is shared across weapon changes and only successful starts consume it", function()
		local f = fixture(); f.gunView.busy = true; f:press(); equal(f.gunView.starts, 0)
		f.gunView.busy = false; f:press(); equal(f.gunView.starts, 1); f.gunView.CancelInspect(true)
		f:equip("Knife"); f.time += 0.49; f:press(); equal(f.knifeView.starts, 0)
		f.time += 0.02; f:press(); equal(f.knifeView.starts, 1)
	end)
	test("focus loss chat focus menu opening and character removal cancel both presenters", function()
		for _, gate in ipairs({"focus", "chat", "menu", "character"}) do
			local f = fixture(); f:press(); motion.Start(f.knifeView.state, "Knife")
			if gate == "focus" then f.ui.WindowFocusReleased:Fire() elseif gate == "chat" then f.ui.TextBoxFocused:Fire({})
			elseif gate == "menu" then f.gui.MenuOpened:Fire() else f.player.CharacterRemoving:Fire(f.character) end
			equal(motion.IsActive(f.gunView.state), false); equal(motion.IsActive(f.knifeView.state), false)
			equal(f.gunView.lastCancel, true); equal(f.knifeView.lastCancel, true)
		end
	end)
	test("Init is idempotent and Destroy removes every input and lifecycle listener", function()
		local f = fixture(); f.controller.Init(); equal(f.ui.InputBegan:Count(), 1); equal(f.ui.WindowFocusReleased:Count(), 1)
		f:press(); equal(f.gunView.starts, 1); f.controller.Destroy(); f.controller.Destroy()
		for _, event in ipairs({f.ui.InputBegan, f.ui.WindowFocusReleased, f.ui.TextBoxFocused, f.gui.MenuOpened, f.player.CharacterRemoving}) do equal(event:Count(), 0) end
		f:press(); equal(f.gunView.starts, 1); equal(f.controller.Inspect(), false)
		f.controller.Init(); f:press(); equal(f.gunView.starts, 2); equal(f.ui.InputBegan:Count(), 1)
	end)
	test("initializer starts once and destroys its controller on script teardown", function()
		local initCount, destroyCount = 0, 0; local initializer = {Parent = {Modules = {WeaponInspectController = "Controller"}}, Destroying = signal()}
		load("Initialize", {script = initializer, require = function(name)
			equal(name, "Controller"); return {Init = function() initCount += 1 end, Destroy = function() destroyCount += 1 end}
		end})
		equal(initCount, 1); equal(destroyCount, 0); initializer.Destroying:Fire(); equal(destroyCount, 1)
	end)
	test("controller has no render listener or scans when unrelated input arrives", function()
		local f = fixture(); local before = f.character.ChildScans or 0
		for _ = 1, 100 do f:press(false, "E"); f:press(true) end
		equal(f.character.ChildScans or 0, before); equal(f.gunView.starts, 0)
	end)
	print(string.format("Weapon inspect tests passed: %d", passed))
end
