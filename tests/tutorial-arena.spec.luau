-- Run real arena construction against injected engine failures. These tests
-- verify that partial maps/rigs are destroyed and never retain combat authority.
return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, reason = pcall(fn); assert(ok, name .. ": " .. tostring(reason)); passed += 1
	end
	local function fixture(mode)
		local f = {created = {}, registry = {}, workspace = {}}
		local methods = {}
		local function object(class, name)
			local o = {_properties = {ClassName = class, Name = name, children = {}}}
			setmetatable(o, {
				__index = function(self, key) return methods[key] or self._properties[key] end,
				__newindex = function(self, key, value)
					if key == "ModelStreamingMode" and mode == "map-publication" and self.Name == "TutorialStuds" then error("publication failed") end
					self._properties[key] = value
				end,
			})
			table.insert(f.created, o); return o
		end
		function methods:IsA(class) return self.ClassName == class or class == "BasePart" and self.ClassName == "Part" end
		function methods:SetAttribute(name, value) self._properties["Attribute_"..name] = value end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self.children) do if child.Name == name then return child end end
		end
		function methods:FindFirstChildOfClass(class)
			for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
		end
		function methods:GetDescendants()
			if self.Name == "Spawns" and mode == "spawn-inspection" then error("spawn data failed") end
			if self.Name == "TutorialNPCSpawns" and mode == "npc-markers" then error("marker inspection failed") end
			return self.children
		end
		function methods:Destroy() self.Destroyed = true; self.Parent = nil; self.DestroyCalls = (self.DestroyCalls or 0) + 1 end
		local vecMeta = {}
		vecMeta.__add = function(a, b) return setmetatable({X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}, vecMeta) end
		local function vec(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vecMeta) end
		local frameMeta = {}
		frameMeta.__mul = function(a, b) return setmetatable({Position = a.Position + b.Position, Rotation = a.Rotation}, frameMeta) end
		local function frame(x, y, z)
			local result = setmetatable({Position = type(x) == "table" and x or vec(x, y, z)}, frameMeta)
			result.Rotation = setmetatable({Position = vec()}, frameMeta); return result
		end
		local template = object("Model", "Studs")
		function template:Clone()
			local map, spawns, npc = object("Model", "StudsClone"), object("Folder", "Spawns"), object("Folder", "TutorialNPCSpawns")
			local spawn = object("Part", "Spawn"); spawn.CFrame = frame()
			spawns.children = mode == "no-spawns" and {} or {spawn}; map.children = {spawns, npc}; f.map = map
			return map
		end
		local rigTemplate = object("Model", "TutorialNPC")
		function rigTemplate:Clone()
			local rig = object("Model", "RigClone"); f.rig = rig
			if mode ~= "bad-rig" then
				local root, hum = object("Part", "HumanoidRootPart"), object("Humanoid", "Humanoid")
				root.CFrame, root.Position = frame(), vec(); rig.children = {root, hum}
			end
			return rig
		end
		local storage = {FindFirstChild = function(_, name) return name == "Studs" and template or name == "TutorialNPC" and rigTemplate end}
		local runtime = {IsActive = function() return true end,
			RegisterTarget = function(_, model) f.registry[model] = true end, RemoveTarget = function(model) f.registry[model] = nil end}
		local npcConfig = {TemplateName = "TutorialNPC", Name = "Bandit", Color = {1, 2, 3}, Health = 100, WalkSpeed = 10, SpawnHeight = 4}
		local rs = {Modules = {TutorialNPCConfig = "NPCConfig"}}
		f.workspace.Raycast = function() return nil end
		local env = {game = {GetService = function(_, name)
			return name == "ServerStorage" and storage or name == "ReplicatedStorage" and rs or {}
		end}, script = {Parent = {TutorialRuntime = "Runtime"}}, require = function(name) return name == "Runtime" and runtime or npcConfig end,
			workspace = f.workspace, Vector3 = {new = vec}, CFrame = {new = frame},
			Instance = {new = function(class)
				if mode == "folder-creation" then error("folder creation failed") end
				local o = object(class, class); f.folder = o; return o
			end}, Enum = {ModelStreamingMode = {Persistent = "Persistent"}, HumanoidHealthDisplayType = {AlwaysOn = "AlwaysOn"}, RaycastFilterType = {Include = "Include"}},
			RaycastParams = {new = function() return {} end}, warn = function() end,
		}
		f.arenaModule = load("TutorialArena", env)
		function f:build() return self.arenaModule.New({}, {}, {MapName = "Studs"}) end
		return f
	end
	test("arena constructor cleans clones on absent or malformed spawn markers", function()
		for _, mode in ipairs({"no-spawns", "spawn-inspection"}) do
			local f = fixture(mode); assert(not pcall(function() f:build() end)); assert(f.map.Destroyed and f.map.Parent == nil)
		end
	end)
	test("arena constructor destroys map and folder on faults after workspace publication", function()
		for _, mode in ipairs({"map-publication", "folder-creation", "npc-markers"}) do
			local f = fixture(mode); assert(not pcall(function() f:build() end)); assert(f.map.Destroyed and f.map.Parent == nil)
			if f.folder then assert(f.folder.Destroyed and f.folder.Parent == nil) end
		end
	end)
	test("invalid NPC rigs and missing floor destroy partial clones without granting authority", function()
		for _, mode in ipairs({"bad-rig", "no-floor"}) do
			local f = fixture(mode); local arena = f:build()
			assert(not pcall(function() arena:SpawnNPC(1) end))
			assert(f.rig.Destroyed and f.rig.Parent == nil and next(f.registry) == nil and next(arena.NPCs) == nil)
		end
	end)
	test("deleted arena map rejects new NPC work and destruction is idempotent", function()
		local f = fixture(); local arena = f:build(); f.map.Parent = nil
		assert(not pcall(function() arena:SpawnNPC(1) end)); assert(f.rig == nil)
		arena:Destroy(); arena:Destroy()
		assert(f.map.DestroyCalls == 1 and f.folder.DestroyCalls == 1 and arena.Destroyed)
	end)
	test("async arena faults notify once after cleaning physical objects", function()
		local f = fixture(); local arena = f:build(); local errors = 0
		arena.OnFailure = function(reason) errors += 1; assert(reason == "respawn failed" and f.map.Destroyed and f.folder.Destroyed) end
		arena:_Fail("respawn failed"); arena:_Fail("duplicate")
		assert(errors == 1 and arena.Failed and arena.Destroyed)
	end)
	print("Tutorial arena: " .. passed .. " partial-construction/fault tests passed")
end
