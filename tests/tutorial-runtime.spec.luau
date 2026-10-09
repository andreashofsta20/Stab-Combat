return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, reason = pcall(fn)
		assert(ok, name .. ": " .. tostring(reason))
		passed += 1
	end
	local function humanoid(health)
		local h = {Health = health or 100, hits = 0}
		function h:TakeDamage(amount) self.hits += 1; self.Health = math.max(0, self.Health - amount) end
		return h
	end
	local function model(health)
		local m = {Parent = {}, humanoid = humanoid(health)}
		function m:FindFirstChildOfClass(kind)
			if kind == "Humanoid" then return self.humanoid end
			if kind == "ForceField" then return self.forceField end
		end
		return m
	end
	local function fixture()
		local f = {runtime = load("Runtime"), player = {Character = model()}, other = {Character = model()}, actions = {}}
		f.session = {Active = true, Progress = {Completed = false}, OnAction = function(kind, evidence)
			 table.insert(f.actions, {Kind = kind, Evidence = evidence})
		end}
		f.runtime.Register(f.player, f.session)
		f.target = model()
		f.runtime.RegisterTarget(f.player, f.target)
		return f
	end
	test("nested hit parts resolve only server-registered living targets", function()
		local f = fixture(); local attachment = {Parent = {Parent = f.target}}
		local target, h = f.runtime.GetTarget(f.player, attachment)
		assert(target == f.target and h == f.target.humanoid)
		assert(f.runtime.GetTarget(f.player, model()) == nil)
	end)
	test("replicated tutorial-looking tags do not authorize unregistered enemies", function()
		local f = fixture(); local forged = model(); forged.TutorialTarget, forged.OwnerId = true, 1
		assert(f.runtime.Damage(f.player, forged, 100, "KnifeStab") == 0 and forged.humanoid.Health == 100)
		assert(#f.actions == 0)
	end)
	test("another player's targets are neither hit nor credited", function()
		local f = fixture(); f.runtime.Register(f.other, {Active = true, Progress = {Completed = false}})
		assert(f.runtime.GetTarget(f.other, {Parent = f.target}) == nil)
		assert(f.runtime.Damage(f.other, f.target, 100, "KnifeStab") == 0 and f.target.humanoid.Health == 100)
		assert(#f.runtime.GetTargets(f.other) == 0 and #f.actions == 0)
	end)
	test("registered target belongs to its exact tutorial session", function()
		local f = fixture(); f.runtime.Register(f.player, {Active = true, Progress = {Completed = false}})
		assert(f.runtime.GetTarget(f.player, f.target) == nil and #f.runtime.GetTargets(f.player) == 0)
		assert(f.runtime.Damage(f.player, f.target, 100, "KnifeThrow") == 0 and f.target.humanoid.Health == 100)
	end)
	test("inactive and completed sessions cannot damage or record progress", function()
		for _, scenario in ipairs({"inactive", "completed"}) do
			local f = fixture()
			if scenario == "inactive" then f.session.Active = false else f.session.Progress.Completed = true end
			f.runtime.Record(f.player, "Slide", "slide")
			assert(f.runtime.Damage(f.player, f.target, 100, "KnifeStab") == 0)
			assert(f.runtime.GetTarget(f.player, f.target) == nil and #f.runtime.GetTargets(f.player) == 0 and #f.actions == 0)
		end
	end)
	test("preparing sessions may register NPCs but cannot damage them or record progress", function()
		local f = fixture(); f.session.Preparing = true; local extra = model()
		assert(f.runtime.IsActive(f.player)); f.runtime.RegisterTarget(f.player, extra)
		f.runtime.Record(f.player, "Slide", "early-slide")
		assert(f.runtime.Damage(f.player, extra, 100, "KnifeStab") == 0 and extra.humanoid.Health == 100 and #f.actions == 0)
		f.session.Preparing = false
		assert(f.runtime.Damage(f.player, extra, 100, "KnifeStab") == 100 and #f.actions == 2)
	end)
	test("dead missing attacker and forcefields stop damage", function()
		for _, scenario in ipairs({"dead", "missing", "forcefield", "missing-target-humanoid"}) do
			local f = fixture()
			if scenario == "dead" then f.player.Character.humanoid.Health = 0
			elseif scenario == "missing" then f.player.Character = nil
			elseif scenario == "forcefield" then f.target.forceField = {}
			else f.target.humanoid = nil end
			assert(f.runtime.Damage(f.player, f.target, 100, "Revolver") == 0 and #f.actions == 0)
		end
	end)
	test("invalid numbers cannot reach Humanoid.TakeDamage", function()
		local f = fixture()
		for _, amount in ipairs({0, -1, 0/0, math.huge, -math.huge, "100", false}) do
			assert(f.runtime.Damage(f.player, f.target, amount, "Revolver") == 0)
		end
		assert(f.target.humanoid.Health == 100 and f.target.humanoid.hits == 0)
	end)
	test("nonlethal hits deal bounded damage without prematurely completing a lesson", function()
		local f = fixture(); assert(f.runtime.Damage(f.player, f.target, 20, "KnifeStab") == 20)
		assert(f.target.humanoid.Health == 80 and #f.actions == 0)
	end)
	test("one lethal hit records the weapon and elimination once", function()
		local f = fixture(); assert(f.runtime.Damage(f.player, f.target, 1000, "KnifeThrow") == 100)
		assert(#f.actions == 2 and f.actions[1].Kind == "KnifeThrow" and f.actions[2].Kind == "Eliminate")
		assert(f.actions[1].Evidence == f.target and f.actions[2].Evidence == f.target)
		assert(f.runtime.Damage(f.player, f.target, 100, "KnifeThrow") == 0 and #f.actions == 2)
		-- A revived target cannot create another kill receipt for the same model.
		f.target.humanoid.Health = 100; assert(f.runtime.Damage(f.player, f.target, 100, "KnifeThrow") == 100)
		assert(#f.actions == 2)
	end)
	test("target listing excludes dead detached and foreign models", function()
		local f = fixture(); local dead, detached, other = model(0), model(), model()
		detached.Parent = nil; f.runtime.RegisterTarget(f.player, dead); f.runtime.RegisterTarget(f.player, detached)
		f.runtime.Register(f.other, {Active = true, Progress = {Completed = false}}); f.runtime.RegisterTarget(f.other, other)
		local targets = f.runtime.GetTargets(f.player)
		assert(#targets == 1 and targets[1] == f.target and f.runtime.GetTarget(f.player, dead) == nil)
	end)
	test("removing a target prevents damage and progress immediately", function()
		local f = fixture(); f.runtime.RemoveTarget(f.target)
		assert(f.runtime.Damage(f.player, f.target, 100, "KnifeStab") == 0)
		assert(f.runtime.GetTarget(f.player, f.target) == nil and #f.runtime.GetTargets(f.player) == 0)
	end)
	test("cleanup releases only the leaving player's session and targets", function()
		local f = fixture(); local otherTarget = model()
		f.runtime.Register(f.other, {Active = true, Progress = {Completed = false}}); f.runtime.RegisterTarget(f.other, otherTarget)
		f.runtime.Remove(f.player)
		assert(f.runtime.GetSession(f.player) == nil and not f.runtime.IsActive(f.player))
		assert(f.runtime.Damage(f.player, f.target, 100, "KnifeStab") == 0)
		assert(f.runtime.GetTarget(f.other, otherTarget) == otherTarget)
	end)
	test("death callback owns a registered tutorial respawn and cleanup stops it", function()
		local f = fixture(); local seen
		f.session.OnDeath = function(character) seen = character end
		assert(f.runtime.OnDeath(f.player, f.player.Character) and seen == f.player.Character)
		assert(not f.runtime.OnDeath(f.other, f.other.Character))
		f.runtime.Remove(f.player); assert(not f.runtime.OnDeath(f.player, f.player.Character))
	end)
	test("target registration requires a server-owned session", function()
		local f = fixture(); assert(not pcall(f.runtime.RegisterTarget, f.other, model()))
	end)
	print("Tutorial runtime: " .. passed .. " ownership/damage tests passed")
end
