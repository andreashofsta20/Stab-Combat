local function signal(registry)
	local listeners, event = {}, {}
	function event:Connect(fn)
		local connection = {Connected = true, fn = fn}; function connection:Disconnect() self.Connected = false end
		table.insert(listeners, connection); table.insert(registry, connection); return connection
	end
	function event:Fire(...) for _, connection in ipairs(table.clone(listeners)) do if connection.Connected then connection.fn(...) end end end
	return event
end
local methods, objectMeta = {}, {}
objectMeta.__index = function(self, name)
	if methods[name] then return methods[name] end
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function methods:IsA(name) return name == self.ClassName or name == "Instance" end
function methods:FindFirstChild(name) for _, child in ipairs(self.children) do if child.Name == name then return child end end end
function methods:FindFirstChildOfClass(name) for _, child in ipairs(self.children) do if child:IsA(name) then return child end end end
function methods:GetChildren() self.Scans = (self.Scans or 0) + 1; return table.clone(self.children) end
function methods:Destroy() self.Destroyed = true; self.Parent = nil end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end

return function(load)
	local passed = 0
	local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); passed += 1; print("PASS " .. name) end
	local function fixture(options)
		options = options or {}
		local f = {connections = {}, calls = {}, created = {}, ready = {}, frames = {}, timers = {}, held = {}, time = 0, active = 0, peak = 0, modules = {}}
		function f.node(class, name, parent)
			local item = setmetatable({ClassName = class, Name = name, Parent = parent, children = {}}, objectMeta)
			for _, key in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Changed", "CharacterAdded", "CharacterRemoving", "Destroying"}) do item[key] = signal(f.connections) end
			if parent then
				table.insert(parent.children, item); parent.ChildAdded:Fire(item)
				local ancestor = parent; while ancestor do ancestor.DescendantAdded:Fire(item); ancestor = ancestor.Parent end
			end
			return item
		end
		f.player, f.rs = f.node("Player", "Player"), f.node("Folder", "ReplicatedStorage")
		f.stats = f.node("Folder", "leaderstats", f.player)
		f.knife = f.node("StringValue", "EquippedKnife", f.stats); f.knife.Value = options.noLoadout and "" or "Knife A"
		f.gun = f.node("StringValue", "EquippedGun", f.stats); f.gun.Value = options.noLoadout and "" or "Gun A"
		f.backpack = f.node("Backpack", "Backpack", f.player)
		f.character = f.node("Model", "Character"); f.player.Character = f.character
		local modules = f.node("Folder", "Modules", f.rs)
		f.config = load("Config"); if options.cache then f.config.MaxRememberedAssets = options.cache end
		local effects = function(name) return {Effects = {EquipSoundId = "rbxassetid://100", FireSoundId = "rbxassetid://101", ReloadSoundId = "rbxassetid://102", EmptySoundId = options.emptySound or "", FireAnimationId = "rbxassetid://103", ReloadAnimationId = "rbxassetid://104", BulletHoleTextureId = options.holeTexture, BulletHoleEnabled = options.holeEnabled}} end
		if options.uniqueSounds then effects = function(name) return {Effects = {EquipSoundId = "rbxassetid://" .. name:match("%d+")}} end end
		for name, module in pairs({WeaponAssetWarmupConfig = f.config, RevolverConfig = {Get = effects}, KnifeEffectsConfig = {Get = function() return {ThrowSoundId = "", ImpactSoundId = "", TrailTexture = ""} end}, CombatAudioConfig = {Hit = {SoundId = "rbxassetid://105"}}}) do f.modules[f.node("ModuleScript", name, modules)] = module end
		f.knives = f.node("Folder", "Knives", f.rs)
		if not options.noGunTemplate then f.guns = f.node("Folder", "Revolvers", f.rs) end
		f.selected = f.node("Tool", "Knife A", f.knives)
		f.mesh = f.node("MeshPart", "Blade", f.selected); f.mesh.FakeAssetId = "rbxassetid://200"
		f.ignored = f.node("Tool", "Other Knife", f.knives); f.node("MeshPart", "Unselected", f.ignored).FakeAssetId = "rbxassetid://999"
		if f.guns then local gun = f.node("Tool", "Gun A", f.guns); f.node("MeshPart", "Handle", gun).FakeAssetId = "rbxassetid://201" end
		f.combat = f.node("Folder", "CombatAnimations", f.rs)
		local n = 300; for _, name in ipairs({"Charge", "ChargeHold", "Throw", "Stab"}) do local clip = f.node("Animation", name, f.combat); clip.AnimationId = "rbxassetid://" .. n; n += 1 end
		f.node("Animation", "Unused Emote", f.combat).AnimationId = "rbxassetid://998"
		local sounds = f.node("Folder", "Sounds", f.node("Folder", "Assets", f.rs))
		n = 400; for _, name in ipairs({"EquipKnife", "Stab", "ThrowKnife", "EliminatedPlayer"}) do local audio = f.node("Sound", name, sounds); audio.SoundId = "rbxassetid://" .. n; n += 1 end
		f.node("Sound", "Unused UI Sound", sounds).SoundId = "rbxassetid://997"
		function f.resume(thread)
			local ok, reason = coroutine.resume(thread); assert(ok, reason)
			if coroutine.status(thread) ~= "dead" then table.insert(reason == "preload" and f.held or f.frames, thread) end
		end
		function f.step(dt)
			f.time += dt or 0.1
			for _, thread in ipairs(f.frames) do table.insert(f.ready, thread) end; f.frames = {}
			for i = #f.timers, 1, -1 do if f.timers[i].at <= f.time then table.insert(f.ready, f.timers[i].thread); table.remove(f.timers, i) end end
			while #f.ready > 0 do f.resume(table.remove(f.ready, 1)) end
		end
		function f.run(count) for _ = 1, count or 40 do f.step(0.1) end end
		function f.complete() local thread = table.remove(f.held, 1); assert(thread); f.resume(thread) end
		f.provider = {}
		function f.provider:PreloadAsync(assets, callback)
			f.active += 1; f.peak = math.max(f.peak, f.active); table.insert(f.calls, table.clone(assets))
			if f.hold then coroutine.yield("preload") end
			for _, asset in ipairs(assets) do callback(type(asset) == "string" and asset or asset.SoundId or asset.AnimationId or asset.FakeAssetId or "", f.fail and "Failure" or "Success") end
			f.active -= 1
		end
		f.env = {game = {GetService = function(_, name) return ({Players = {LocalPlayer = f.player}, ReplicatedStorage = f.rs, ContentProvider = f.provider})[name] end},
			Enum = {AssetFetchStatus = {Success = "Success"}}, require = function(module) return assert(f.modules[module], module and module.Name) end,
			Instance = {new = function(class) local item = f.node(class, class); table.insert(f.created, item); return item end},
			task = {defer = function(fn) table.insert(f.ready, coroutine.create(fn)) end, delay = function(delay, fn) table.insert(f.timers, {at = f.time + delay, thread = coroutine.create(fn)}) end, wait = function() coroutine.yield("frame") end}}
		f.warmup = load("Warmup", f.env)
		function f.select(field, name) field.Value = name; field.Changed:Fire(name) end
		function f.requested(value)
			for _, batch in ipairs(f.calls) do for _, asset in ipairs(batch) do if asset == value or type(asset) ~= "string" and (asset.SoundId == value or asset.AnimationId == value or asset.FakeAssetId == value) then return true end end end
			return false
		end
		return f
	end
	test("configured bullet hole images warm in the background before the first accepted miss", function()
		local f = fixture({holeTexture = "rbxassetid://8765"}); f.warmup.Init()
		equal(#f.calls, 0); f.run(); assert(f.requested("rbxassetid://8765"))
		local disabled = fixture({holeTexture = "rbxassetid://8765", holeEnabled = false}); disabled.warmup.Init(); disabled.run()
		assert(not disabled.requested("rbxassetid://8765"))
	end)
	test("configured empty click audio warms as a Sound while a blank slot queues nothing", function()
		local f = fixture({emptySound = "rbxassetid://9876"}); f.warmup.Init()
		equal(#f.calls, 0); f.run(); assert(f.requested("rbxassetid://9876"))
		local matching = 0
		for _, batch in ipairs(f.calls) do
			for _, asset in ipairs(batch) do
				if type(asset) ~= "string" and asset.SoundId == "rbxassetid://9876" then
					equal(asset.ClassName, "Sound"); matching += 1
				end
			end
		end
		equal(matching, 1)
		local count = #f.calls; f.select(f.gun, "Gun A"); f.run(); equal(#f.calls, count)
		local blank = fixture(); blank.warmup.Init(); blank.run(); assert(not blank.requested(""))
	end)
	test("startup returns immediately and warms only selected geometry and combat resources", function()
		local f = fixture(); f.warmup.Init(); equal(#f.calls, 0); f.run()
		assert(f.requested("rbxassetid://100") and f.requested("rbxassetid://103") and f.requested("rbxassetid://300"))
		assert(f.requested("rbxassetid://200") and f.requested("rbxassetid://201"))
		assert(not f.requested("rbxassetid://999") and not f.requested("rbxassetid://998") and not f.requested("rbxassetid://997"))
		equal(f.rs.Scans, nil); equal(f.knives.Scans, nil); equal(f.ignored.Scans, nil)
		for _, batch in ipairs(f.calls) do assert(#batch <= 8); for _, asset in ipairs(batch) do if type(asset) ~= "string" and asset.AnimationId then equal(asset.ClassName, "Animation") end end end
		for _, item in ipairs(f.created) do assert(item.Destroyed) end
	end)
	test("idempotent initialization and unchanged selections do not repeat warmed requests", function()
		local f = fixture(); f.warmup.Init(); f.warmup.Init(); f.run(); local count = #f.calls
		f.select(f.knife, "Knife A"); f.select(f.gun, "Gun A"); f.run(); equal(#f.calls, count)
		f.warmup.Destroy(); for _, connection in ipairs(f.connections) do assert(not connection.Connected) end
	end)
	test("requests stay serialized while selection changes supersede queued skins", function()
		local f = fixture(); f.hold = true; f.warmup.Init(); f.run(6); equal(#f.calls, 1)
		for _, name in ipairs({"Knife B", "Knife C"}) do local tool = f.node("Tool", name, f.knives); f.node("MeshPart", "Blade", tool).FakeAssetId = name; f.select(f.knife, name); f.run(2) end
		equal(#f.calls, 1); f.hold = false; f.complete(); f.run(); equal(f.peak, 1)
		assert(f.requested("Knife C") and not f.requested("Knife B"))
	end)
	test("destroy cancels scans and callbacks while cleaning temporary typed resources", function()
		local f = fixture(); f.hold = true; f.warmup.Init(); f.run(6); equal(#f.calls, 1)
		f.warmup.Destroy(); f.hold = false; f.complete(); f.run(); equal(#f.calls, 1)
		for _, connection in ipairs(f.connections) do assert(not connection.Connected) end
		for _, item in ipairs(f.created) do assert(item.Destroyed) end
	end)
	test("reinitialization queues behind the previous native preload instead of overlapping it", function()
		local f = fixture(); f.hold = true; f.warmup.Init(); f.run(6); f.warmup.Destroy(); f.warmup.Init(); f.run(6); equal(#f.calls, 1)
		f.hold = false; f.complete(); f.run(); assert(#f.calls > 1); equal(f.peak, 1)
	end)
	test("late selected replicas warm when no client revolver template is available", function()
		local f = fixture({noGunTemplate = true}); f.warmup.Init(); f.run(); assert(not f.requested("rbxassetid://202"))
		local tool = f.node("Tool", "Gun A", f.character); f.node("MeshPart", "Handle", tool).FakeAssetId = "rbxassetid://202"; f.run()
		assert(f.requested("rbxassetid://202")); equal(f.character.Scans, nil)
	end)
	test("empty loadouts do no preload work and denied assets do not loop on refresh", function()
		local empty = fixture({noLoadout = true}); empty.warmup.Init(); empty.run(); equal(#empty.calls, 0)
		local f = fixture(); f.fail = true; f.warmup.Init(); f.run(); local count = #f.calls
		f.select(f.gun, "Gun A"); f.select(f.knife, "Knife A"); f.run(); equal(#f.calls, count)
	end)
	test("bounded cache evicts old requests and bounded weapon walks yield", function()
		local f = fixture({cache = 4, uniqueSounds = true, noLoadout = true}); f.knife.Value = ""; f.gun.Value = "Gun 1"; f.warmup.Init(); f.run()
		for i = 2, 10 do f.select(f.gun, "Gun " .. i); f.run(3) end
		local count = #f.calls; f.select(f.gun, "Gun 1"); f.run(); assert(#f.calls > count)
		local large = fixture(); for i = 1, 1000 do large.node("MeshPart", "Piece" .. i, large.selected).FakeAssetId = "part" .. i end
		large.warmup.Init(); large.run(); local meshCount = 0
		for _, batch in ipairs(large.calls) do for _, asset in ipairs(batch) do if type(asset) ~= "string" and asset.ClassName == "MeshPart" and asset.Parent == large.selected then meshCount += 1 end end end
		assert(meshCount <= large.config.MaxScanItemsPerWeapon and #large.calls < 40); equal(large.ignored.Scans, nil)
	end)
	test("standalone initializer starts once and destruction disconnects background listeners", function()
		local f = fixture(); local owner = f.node("Folder", "CLIENT"); local modules = f.node("Folder", "Modules", owner)
		f.modules[f.node("ModuleScript", "WeaponAssetWarmup", modules)] = f.warmup
		f.env.script = f.node("LocalScript", "Initialize", owner); load("Initialize", f.env); f.run(); assert(#f.calls > 0)
		f.env.script.Destroying:Fire(); local count = #f.calls; f.select(f.gun, "Gun A"); f.run(); equal(#f.calls, count)
	end)
	print(tostring(passed) .. " weapon asset warmup tests passed")
end
