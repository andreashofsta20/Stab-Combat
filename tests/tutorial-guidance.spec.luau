-- Exercises the production guidance module: streamed/dead target cleanup,
-- graduated hints, one success cue, hotbar ownership and timer invalidation.
return function(load)
	local function signal()
		local listeners = {}
		return {
			Connect = function(_, callback)
				local connection = {Connected = true}
				function connection:Disconnect() self.Connected = false end
				table.insert(listeners, {Callback = callback, Connection = connection})
				return connection
			end,
			Fire = function(_, ...)
				for _, listener in ipairs(listeners) do if listener.Connection.Connected then listener.Callback(...) end end
			end,
			Count = function()
				local count = 0
				for _, listener in ipairs(listeners) do if listener.Connection.Connected then count += 1 end end
				return count
			end,
		}
	end
	local function fixture()
		local f = {Time = 0, Timers = {}, Hints = {}, Successes = 0, Instances = {}}
		local methods, meta = {}, {}
		meta.__index = function(object, key)
			if methods[key] then return methods[key] end
			return object.Properties[key]
		end
		meta.__newindex = function(object, key, value) object.Properties[key] = value end
		local function instance(class)
			local object = setmetatable({Properties = {ClassName = class, AncestryChanged = signal(), Died = signal()}}, meta)
			table.insert(f.Instances, object)
			return object
		end
		function methods:IsA(class)
			return self.ClassName == class or class == "GuiObject" and self.ClassName == "Frame" or class == "BasePart" and self.ClassName == "Part"
		end
		function methods:GetChildren()
			local list = {}
			for _, object in ipairs(f.Instances) do if object.Parent == self then table.insert(list, object) end end
			return list
		end
		function methods:FindFirstChild(name)
			for _, object in ipairs(self:GetChildren()) do if object.Name == name then return object end end
			return nil
		end
		function methods:FindFirstChildOfClass(class)
			for _, object in ipairs(self:GetChildren()) do if object:IsA(class) then return object end end
			return nil
		end
		function methods:IsDescendantOf(ancestor)
			local parent = self.Parent
			while parent do if parent == ancestor then return true end; parent = parent.Parent end
			return false
		end
		function methods:Destroy()
			for _, child in ipairs(self:GetChildren()) do child:Destroy() end
			self.Parent, self.Destroyed = nil, true
		end
		local function child(parent, class, name)
			local object = instance(class); object.Name, object.Parent = name, parent
			return object
		end
		f.Workspace = instance("Workspace")
		f.Workspace.GetServerTimeNow = function() return f.Time end
		f.PlayerGui = instance("PlayerGui")
		f.Slot = child(child(child(f.PlayerGui, "ScreenGui", "Main"), "Frame", "Bottom"), "Frame", "1")
		f.ExistingStroke = child(f.Slot, "UIStroke", "AuthoredStroke")
		f.RS = instance("ReplicatedStorage")
		f.RS.Modules = {TutorialUIConfig = "config"}
		f.Sound = child(child(child(f.RS, "Folder", "Assets"), "Folder", "Sounds"), "Sound", "NormalTick")
		f.Sound.Play = function() f.SoundPlays = (f.SoundPlays or 0) + 1 end
		local config = {
			Colors = {Background = "Background", Accent = "Accent"},
			Guidance = {HintAfterSeconds = {15, 30}, TargetRefreshSeconds = 0.5, MaxTargets = 8,
				MarkerMaxDistance = 140, SuccessSound = "NormalTick", SlotsByKind = {KnifeStab = "1"},
				Hints = {KnifeStab = {"Move closer.", "Stay within arm's reach."}},
			},
		}
		local environment = {
			game = {GetService = function(_, service)
				return service == "Players" and {LocalPlayer = {}} or service == "ReplicatedStorage" and f.RS or nil
			end},
			workspace = f.Workspace, Instance = {new = instance}, require = function() return config end,
			typeof = function(value) return getmetatable(value) == meta and "Instance" or type(value) end,
			UDim2 = {fromScale = function(...) return {...} end, fromOffset = function(...) return {...} end},
			UDim = {new = function(...) return {...} end}, Vector3 = {new = function(...) return {...} end},
			Enum = {Font = {GothamBold = "Bold"}, HighlightDepthMode = {Occluded = "Occluded"}, ApplyStrokeMode = {Border = "Border"}},
			task = {delay = function(seconds, callback) table.insert(f.Timers, {At = f.Time + seconds, Callback = callback}) end},
		}
		f.Guidance = load("TutorialGuidance", environment).new(f.PlayerGui, function(text, level)
			table.insert(f.Hints, {Text = text, Level = level})
		end, function() f.Successes += 1 end)
		function f:NPC()
			local model = child(self.Workspace, "Model", "Bandit")
			local humanoid = child(model, "Humanoid", "Humanoid"); humanoid.Health = 100
			child(model, "Part", "HumanoidRootPart")
			return model, humanoid
		end
		function f:Snapshot(targets, progress, index)
			return {Mode = "Active", StepIndex = index or 1, StepStartedAt = self.Time, Progress = progress or 0,
				Step = {Id = "stab", Kind = "KnifeStab", Goal = 1}, Targets = targets}
		end
		function f:Advance(seconds)
			self.Time += seconds
			local due = self.Timers; self.Timers = {}
			for _, timer in ipairs(due) do
				if timer.At <= self.Time then timer.Callback() else table.insert(self.Timers, timer) end
			end
		end
		return f
	end
	local f = fixture()
	local npc, humanoid = f:NPC()
	f.Guidance.Update(f:Snapshot({npc}, 0))
	assert(f.Workspace:FindFirstChild("TutorialGuidance"):FindFirstChild("PracticeTarget"))
	assert(f.PlayerGui:FindFirstChild("TrainingTarget").Enabled)
	assert(f.Slot:FindFirstChild("TutorialFocus"))
	f:Advance(15); assert(f.Hints[#f.Hints].Text == "Move closer.")
	f:Advance(15); assert(f.Hints[#f.Hints].Text == "Stay within arm's reach.")
	f.Guidance.Update(f:Snapshot({npc}, 1)); f.Guidance.Update(f:Snapshot({npc}, 1))
	assert(f.Successes == 1 and f.SoundPlays == 1, "Repeated snapshots replayed success")
	humanoid.Health = 0; humanoid.Died:Fire()
	assert(not f.PlayerGui:FindFirstChild("TrainingTarget").Enabled)
	f.Guidance.Update({Mode = "Hidden"})
	assert(humanoid.Died:Count() == 0 and npc.AncestryChanged:Count() == 0)
	assert(f.Slot:FindFirstChild("TutorialFocus") == nil and not f.ExistingStroke.Destroyed)
	local hintCount = #f.Hints
	f:Advance(30); assert(#f.Hints == hintCount, "An old lesson timer displayed a stale hint")
	f.Guidance.Update(f:Snapshot({npc}, 0, 2))
	f.Guidance.Destroy(); f.Guidance.Destroy()
	f:Advance(60)
	assert(f.PlayerGui:FindFirstChild("TrainingTarget") == nil and f.Workspace:FindFirstChild("TutorialGuidance") == nil)
	assert(f.Slot:FindFirstChild("TutorialFocus") == nil and not f.ExistingStroke.Destroyed)
	assert(humanoid.Died:Count() == 0 and npc.AncestryChanged:Count() == 0)
	print("PASS tutorial guidance targets hints success and lifecycle")
end
