-- Drives the production observer listener using actual accepted server payload shapes.
local Vector, vectorMeta = {}, {}
function Vector.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vectorMeta) end
function vectorMeta.__index(v, key)
	if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
	if key == "Unit" then local magnitude = v.Magnitude; return Vector.new(v.X/magnitude, v.Y/magnitude, v.Z/magnitude) end
end
function vectorMeta.__sub(a, b) return Vector.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
function vectorMeta.__add(a, b) return Vector.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
function vectorMeta.__mul(v, scalar) return Vector.new(v.X*scalar, v.Y*scalar, v.Z*scalar) end
local function near(actual, expected) assert(math.abs(actual-expected) < 1e-7, tostring(actual) .. " ~= " .. tostring(expected)) end
local function signal()
	local value = {connections = {}}
	function value:Connect(fn)
		local connection = {active = true, fn = fn}
		function connection:Disconnect() self.active = false end
		table.insert(self.connections, connection); return connection
	end
	function value:Fire(data) for _, connection in ipairs(self.connections) do if connection.active then connection.fn(data) end end end
	function value:Count() local count = 0; for _, connection in ipairs(self.connections) do if connection.active then count += 1 end end; return count end
	return value
end
local function container(children)
	return {FindFirstChild = function(_, name) return children[name] end, WaitForChild = function(_, name) return assert(children[name], name) end}
end

return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, failure = pcall(fn)
		if not ok then error(name .. ": " .. tostring(failure), 0) end
		passed += 1; print("PASS " .. name)
	end
	local function fixture(skipInit)
		local f = {instances = {}, played = {}, tasks = {}, preloads = {}, clock = 0, shot = signal(), threw = signal(),
			config = load("Config"), revolver = load("RevolverConfig"), knife = load("KnifeConfig"), player = {UserId = 101}}
		f.workspace = {CurrentCamera = {CFrame = {Position = Vector.new(0, 5, 0)}}}
		f.fallback = {SoundId = "rbxassetid://knife-fallback", SoundGroup = {Name = "Weapons"}, IsA = function(_, name) return name == "Sound" end}
		f.sounds = {ThrowKnife = f.fallback}; f.assets = {Sounds = container(f.sounds)}
		f.storageChildren = {Assets = container(f.assets), Remotes = container({Revolver = container({Shot = {OnClientEvent = f.shot}}), Knife = container({ThrewClient = {OnClientEvent = f.threw}})})}
		local replicated = container(f.storageChildren)
		replicated.Modules = {CombatAudioConfig = "Config", RevolverConfig = "RevolverConfig", KnifeEffectsConfig = "KnifeConfig"}
		local content = {}
		function content:PreloadAsync(ids) if f.failPreload then error("asset unavailable") end; table.insert(f.preloads, ids) end
		local services = {Players = {LocalPlayer = f.player}, ReplicatedStorage = replicated, ContentProvider = content}
		f.env = {game = {GetService = function(_, name) return assert(services[name], name) end}, workspace = f.workspace,
			Vector3 = Vector, CFrame = {new = function(position) return {Position = position} end},
			Enum = {RollOffMode = {LinearSquare = "LinearSquare"}},
			require = function(name) return assert(({Config = f.config, RevolverConfig = f.revolver, KnifeConfig = f.knife})[name], name) end,
			typeof = function(value) return getmetatable(value) == vectorMeta and "Vector3" or typeof(value) end,
			os = {clock = function() return f.clock end}, task = {spawn = function(fn) table.insert(f.tasks, fn) end}, Instance = {}}
		function f.env.Instance.new(class)
			local value = {ClassName = class, SoundId = "", IsPlaying = false, stops = 0}
			function value:Stop() self.IsPlaying = false; self.stops += 1 end
			function value:Play()
				self.IsPlaying = true
				table.insert(f.played, {sound = self, id = self.SoundId, volume = self.Volume, pitch = self.PlaybackSpeed,
					position = self.Parent.Parent.CFrame.Position, min = self.RollOffMinDistance, max = self.RollOffMaxDistance,
					mode = self.RollOffMode, group = self.SoundGroup})
			end
			function value:Destroy()
				self.destroyed, self.Parent = true, nil
				for _, child in ipairs(f.instances) do if child.Parent == self then child:Destroy() end end
			end
			table.insert(f.instances, value); return value
		end
		f.audio = load("Audio", f.env); if not skipInit then f.audio.Init() end
		function f.fire(sequence, origin, session, shooter, weapon)
			f.clock += 0.01
			f.shot:Fire({ShooterId = shooter or 202, Session = session or "server-session", Sequence = sequence or 1,
				Weapon = weapon or "Normal Revolver", Origin = origin or Vector.new(5, 5, 0)})
		end
		function f.throw(id, origin, charge, shooter, name)
			f.clock += 0.01
			f.threw:Fire({visualOnly = true, shooterUserId = shooter or 202, shotId = id or "202_1", knifeName = name or "Normal Knife",
				origin = origin or Vector.new(5, 5, 0), charge = charge or 0})
		end
		function f.runTasks() local pending = f.tasks; f.tasks = {}; for _, fn in ipairs(pending) do fn() end end
		return f
	end
	local function serverFixture()
		local f = fixture()
		local rules = load("KnifeRules")
		local projectile = load("Projectile", {script = {Parent = {KnifeConfig = "Rules"}},
			require = function(name) assert(name == "Rules"); return rules end, typeof = f.env.typeof})
		f.shooter = {UserId = 202, GetAttribute = function(_, name) return name == "DataReady" and true or nil end}
		f.head = {Position = Vector.new(24, 5, 0)}
		f.tool = {Name = "Normal Knife"}
		f.humanoid = {Health = 100}
		f.shooter.Character = {
			FindFirstChild = function(_, name) return name == "Head" and f.head or nil end,
			FindFirstChildOfClass = function(_, class) return class == "Tool" and f.tool or class == "Humanoid" and f.humanoid or nil end,
		}
		f.main = {GameActive = true, PlayersInGame = {[202] = true}}
		local result = {}
		function result:FireClient(_, data) f.result = data end
		function result:FireAllClients(data) f.broadcast = data; f.threw:Fire(data) end
		local remotes = container({Knife = container({ThrewClient = result, DamageDealtClient = {}})})
		local replicated = container({Remotes = remotes})
		replicated.Modules = {ProjectileMath = "Projectile", RevolverRaycast = "Raycast", RagdollQuery = "Query"}
		local services = {ReplicatedStorage = replicated, Players = {PlayerRemoving = signal()},
			ServerStorage = container({Knives = container({[f.tool.Name] = true})})}
		local deps = {Game = f.main, Hitboxes = {GetPlayerFromHitbox = function() end}, Projectile = projectile, Raycast = {},
			Query = {Exclude = function(list) return list end}}
		local env = {game = {GetService = function(_, name) return assert(services[name], name) end},
			script = {Parent = {PlayerHitbox = "Hitboxes", Parent = {Game = {MainGame = "Game"}}}},
			require = function(name) return assert(deps[name], name) end, typeof = f.env.typeof,
			os = {clock = function() return f.clock end}, RaycastParams = {new = function() return {} end},
			Enum = {RaycastFilterType = {Exclude = "Exclude"}}, workspace = {Raycast = function() return f.hit end}}
		f.server = load("ServerThrow", env)
		function f.accept(id, origin, direction)
			f.clock += projectile.COOLDOWN
			return f.server.Throw(f.shooter, id or "202_1", origin or f.head.Position, direction or Vector.new(0, 0, -1), 1)
		end
		return f
	end
	test("startup prepares one bounded inert pool and exactly two listeners", function()
		local f = fixture(); f.audio.Init(); assert(f.shot:Count() == 1 and f.threw:Count() == 1)
		local parts, attachments, sounds = 0, 0, 0
		for _, item in ipairs(f.instances) do
			if item.ClassName == "Part" then
				parts += 1; assert(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery and not item.CastShadow)
			elseif item.ClassName == "Attachment" then attachments += 1
			elseif item.ClassName == "Sound" then sounds += 1; assert(not item.Looped and not item.PlayOnRemove) end
		end
		assert(parts == f.config.Observer.MaxVoices and attachments == parts and sounds == parts)
	end)
	test("owner broadcasts never duplicate predicted revolver or knife sounds", function()
		local f = fixture(); f.fire(1, nil, nil, 101); f.throw("101_1", nil, 1, 101); assert(#f.played == 0)
	end)
	test("remote gun audio uses the accepted origin and point-source spatial falloff", function()
		local f = fixture(); local position = Vector.new(17, 5, -6); f.fire(1, position)
		local shot = assert(f.played[1]); assert(shot.position == position and shot.id == f.revolver.Default.Effects.FireSoundId)
		assert(shot.sound.Parent.ClassName == "Attachment" and shot.sound.Parent.Parent.ClassName == "Part")
		assert(shot.mode == "LinearSquare" and shot.min == 14 and shot.max == 260)
		near(shot.volume, f.revolver.Default.Effects.SoundVolume * 1.1)
	end)
	test("a missing streamed shooter character does not suppress accepted audio", function()
		local f = fixture(); f.player.Character = nil; f.fire(); f.throw(); assert(#f.played == 2)
	end)
	test("knife throws use the existing sound asset and charge pitch", function()
		local f = fixture(); f.throw("202_1", nil, 1); local throw = assert(f.played[1])
		assert(throw.id == f.fallback.SoundId and throw.group == f.fallback.SoundGroup and throw.max == 160 and throw.min == 16)
		near(throw.pitch, f.knife.Default.ThrowPitchMax); near(throw.volume, f.knife.Default.SoundVolume * 1.1)
	end)
	test("skin sound overrides are honored without changing gameplay tuning", function()
		local f = fixture(); f.revolver.Overrides.Custom = {Effects = {FireSoundId = "rbxassetid://custom-shot", SoundVolume = 0.2, SoundPlaybackSpeed = 1.4}}
		f.knife.Overrides.Custom = {ThrowSoundId = "rbxassetid://custom-throw", SoundVolume = 0.3}
		f.fire(1, nil, nil, nil, "Custom"); f.throw("202_1", nil, 0, nil, "Custom")
		assert(f.played[1].id == "rbxassetid://custom-shot" and f.played[2].id == "rbxassetid://custom-throw")
		near(f.played[1].pitch, 1.4); near(f.played[1].volume, 0.22); near(f.played[2].volume, 0.33)
		assert(f.played[1].group == nil and f.played[2].group == nil)
	end)
	test("same server shot and throw broadcasts only play once", function()
		local f = fixture(); f.fire(); f.fire(); f.throw(); f.throw(); assert(#f.played == 2)
	end)
	test("gun sequence shooter and session all participate in deduplication", function()
		local f = fixture(); f.fire(1); f.fire(2); f.fire(1, nil, "next-life"); f.fire(1, nil, nil, 303)
		assert(#f.played == 4)
	end)
	test("knife acknowledgements and rejections cannot play observer throws", function()
		local f = fixture(); f.threw:Fire({shotId = "202_1", accepted = true}); f.threw:Fire({shotId = "202_2", accepted = false})
		assert(#f.played == 0)
	end)
	test("the sound pool stays bounded through sustained busy overlapping fire", function()
		local f = fixture(); local count = #f.instances; local first
		for index = 1, f.config.Observer.MaxVoices+1 do f.fire(index); if index == 1 then first = f.played[1].sound end end
		assert(#f.instances == count and f.played[#f.played].sound == first and first.stops == 2)
	end)
	test("a completed voice is reused before interrupting an active voice", function()
		local f = fixture(); f.fire(1); f.fire(2); local second = f.played[2].sound
		second.IsPlaying = false; f.fire(3); assert(f.played[3].sound == second and f.played[1].sound.stops == 1)
	end)
	test("deduplication memory is a bounded ring rather than an ever-growing history", function()
		local f = fixture(); f.fire(1)
		for sequence = 2, f.config.Observer.RememberedEvents+1 do f.fire(sequence) end
		local played = #f.played; f.fire(1); assert(#f.played == played+1)
	end)
	test("audible gun range exceeds the former hundred-stud cutoff", function()
		local f = fixture(); f.fire(1, Vector.new(150, 5, 0)); assert(#f.played == 1)
		f.fire(2, Vector.new(260, 5, 0)); assert(#f.played == 2)
		f.fire(3, Vector.new(260.01, 5, 0)); assert(#f.played == 2)
	end)
	test("knife audio stays local to its shorter configured audible range", function()
		local f = fixture(); f.throw("202_1", Vector.new(150, 5, 0)); assert(#f.played == 1)
		f.throw("202_2", Vector.new(160.01, 5, 0)); assert(#f.played == 1)
	end)
	test("a production server accepted miss broadcasts exactly one audible observer throw", function()
		local f = serverFixture(); assert(f.accept())
		assert(f.result.accepted and not f.result.hit and f.broadcast.visualOnly)
		assert(#f.played == 1 and f.played[1].position == f.head.Position and f.played[1].id == f.fallback.SoundId)
		assert(f.broadcast.shooterUserId == 202 and f.broadcast.knifeName == f.tool.Name)
		near(f.played[1].pitch, f.knife.Default.ThrowPitchMax)
	end)
	test("a production wall impact still emits the throw at release rather than at impact", function()
		local f = serverFixture()
		local wall = Vector.new(24, 5, -60)
		f.hit = {Position = wall, Normal = Vector.new(0, 0, 1), Instance = {Name = "Wall"}}
		assert(f.accept())
		assert(f.result.hit and f.broadcast.destination == wall)
		assert(#f.played == 1 and f.played[1].position == f.head.Position)
	end)
	test("rejected production server requests never broadcast observer audio", function()
		local f = serverFixture(); f.main.GameActive = false
		assert(not f.accept("lobby")); assert(#f.played == 0 and f.broadcast == nil)
		f.main.GameActive = true; assert(f.accept("valid")); assert(#f.played == 1)
		assert(not f.server.Throw(f.shooter, "cooldown", f.head.Position, Vector.new(0, 0, -1), 1))
		assert(not f.accept("valid")); assert(#f.played == 1)
		assert(not f.accept("invalid", nil, Vector.new(0/0, 0, 0))); assert(#f.played == 1)
	end)
	test("production observer broadcast excludes the local thrower without suppressing others", function()
		local f = serverFixture(); f.player.UserId = f.shooter.UserId
		assert(f.accept()); assert(#f.played == 0)
		f.player.UserId = 101; assert(f.accept("202_2")); assert(#f.played == 1)
	end)
	test("spatial range follows the current spectator camera rather than local body position", function()
		local f = fixture(); f.workspace.CurrentCamera = {CFrame = {Position = Vector.new(500, 5, 0)}}
		f.fire(1, Vector.new(510, 5, 0)); assert(#f.played == 1)
	end)
	test("missing camera or fallback asset safely skips unavailable sounds", function()
		local f = fixture(); f.workspace.CurrentCamera = nil; f.fire(); assert(#f.played == 0)
		f.workspace.CurrentCamera = {CFrame = {Position = Vector.new(0, 5, 0)}}; f.sounds.ThrowKnife = nil
		f.throw(); assert(#f.played == 0)
	end)
	test("a late replicated fallback sound works on the next throw", function()
		local f = fixture(); f.sounds.ThrowKnife = nil; f.throw("202_1"); assert(#f.played == 0)
		f.sounds.ThrowKnife = f.fallback; f.throw("202_2"); assert(#f.played == 1)
	end)
	test("malformed or nonfinite remote payloads cannot create sounds", function()
		local f = fixture()
		for _, data in ipairs({{}, {ShooterId = 202, Session = "session", Sequence = 1, Weapon = "Gun", Origin = Vector.new(0/0, 0, 0)},
			{ShooterId = 202, Session = "session", Sequence = 1e300, Weapon = "Gun", Origin = Vector.new()},
			{ShooterId = 1e300, Session = "session", Sequence = 1, Weapon = "Gun", Origin = Vector.new()}}) do f.shot:Fire(data) end
		f.threw:Fire({visualOnly = true, shooterUserId = 202, shotId = "1", knifeName = "Knife", origin = Vector.new(), charge = math.huge})
		f.threw:Fire({visualOnly = true, shooterUserId = 202, shotId = "2", knifeName = "Knife", origin = Vector.new(1000001, 0, 0), charge = 0})
		assert(#f.played == 0)
	end)
	test("charge pitch is safely clamped to configured endpoints", function()
		local f = fixture(); f.throw("202_1", nil, -99); f.throw("202_2", nil, 99)
		near(f.played[1].pitch, f.knife.Default.ThrowPitchMin); near(f.played[2].pitch, f.knife.Default.ThrowPitchMax)
	end)
	test("negative Studio user IDs still receive observer audio", function()
		local f = fixture(); f.player.UserId = -1; f.fire(1, nil, nil, -2); f.throw("-2_1", nil, 0, -2); assert(#f.played == 2)
	end)
	test("preloading is asynchronous deduplicated and never blocks first audio", function()
		local f = fixture(); assert(#f.preloads == 0 and #f.tasks == 1)
		f.fire(1); f.throw(); assert(#f.played == 2 and #f.tasks == 1)
		f.runTasks(); assert(#f.preloads == 1 and #f.preloads[1] == 2)
	end)
	test("an unavailable preload asset does not break event handling", function()
		local f = fixture(); f.failPreload = true; f.runTasks(); f.fire(); f.throw(); assert(#f.played == 2)
	end)
	test("destroy disconnects events destroys all voices and allows a clean reinitialization", function()
		local f = fixture(); f.fire(); local instances = #f.instances; f.audio.Destroy()
		assert(f.shot:Count() == 0 and f.threw:Count() == 0)
		for _, item in ipairs(f.instances) do assert(item.destroyed) end
		f.fire(2); assert(#f.played == 1); f.audio.Init(); f.fire(1)
		assert(#f.played == 2 and #f.instances == instances*2 and f.shot:Count() == 1)
	end)
	test("destroying during remote dependency loading cannot create orphaned voices or subscriptions", function()
		local f = fixture(true)
		local replicated = f.env.game:GetService("ReplicatedStorage")
		function replicated:WaitForChild(name)
			f.audio.Destroy()
			return assert(f.storageChildren[name], name)
		end
		f.audio.Init()
		assert(#f.instances == 0 and f.shot:Count() == 0 and f.threw:Count() == 0)
	end)
	test("standalone initializer starts audio once and owns its teardown", function()
		local calls, destroy = {}, nil
		load("Initialize", {script = {Parent = {Modules = {RemoteWeaponAudio = "Audio"}}, Destroying = {Connect = function(_, fn) destroy = fn end}},
			require = function(name) assert(name == "Audio"); return {Init = function() assert(destroy, "cleanup must be registered before yielding startup"); table.insert(calls, "init") end, Destroy = function() table.insert(calls, "destroy") end} end})
		assert(calls[1] == "init"); destroy(); assert(calls[2] == "destroy")
	end)
	print(string.format("%d remote weapon audio tests passed", passed))
end
