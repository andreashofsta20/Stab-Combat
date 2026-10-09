return function(load)
	local State, Steps = load("State"), load("Steps")
	local passed = 0
	local function test(name, fn)
		local ok, reason = pcall(fn)
		assert(ok, name .. ": " .. tostring(reason))
		passed += 1
	end
	local function state(steps) return State.New(steps, 100) end
	test("briefings require their reading time and cannot accept forged combat progress", function()
		local s = state({{Kind = "Read", Goal = 1, MinSeconds = 4}, {Kind = "KnifeStab", Goal = 1}})
		assert(not State.Record(s, "KnifeStab", 1, "enemy") and not State.Record(s, "Read", 1))
		assert(not State.Advance(s, 103.99) and s.Index == 1 and s.Progress == 0)
		assert(State.Advance(s, 104) and s.Index == 2 and s.StepStartedAt == 104)
	end)
	test("wrong weapons and unrelated actions never satisfy a lesson", function()
		local s = state({{Kind = "KnifeThrow", Goal = 2, MinSeconds = 0}})
		for _, kind in ipairs({"KnifeStab", "Revolver", "Eliminate", "Slide", "Heal", "Read"}) do
			assert(not State.Record(s, kind, 1, kind))
		end
		assert(s.Progress == 0 and not State.CanContinue(s, 110))
	end)
	test("an enemy is credited once per objective even if hit packets repeat", function()
		local s = state({{Kind = "Revolver", Goal = 2, MinSeconds = 1}})
		local enemy = {}
		assert(State.Record(s, "Revolver", 1, enemy)); assert(not State.Record(s, "Revolver", 1, enemy))
		assert(s.Progress == 1 and not State.CanContinue(s, 105))
		assert(State.Record(s, "Revolver", 1, {}) and State.CanContinue(s, 105))
	end)
	test("invalid and nonpositive progress cannot complete an objective", function()
		local s = state({{Kind = "Move", Goal = 24, MinSeconds = 0}})
		for _, amount in ipairs({0, -1, 0/0, math.huge, -math.huge, "24", false}) do assert(not State.Record(s, "Move", amount)) end
		assert(s.Progress == 0 and not State.CanContinue(s, 105))
	end)
	test("movement samples accumulate and cap at the objective goal", function()
		local s = state({{Kind = "Move", Goal = 24, MinSeconds = 1}})
		for _ = 1, 8 do assert(State.Record(s, "Move", 3)) end
		assert(s.Progress == 24 and State.CanContinue(s, 101))
		assert(State.Record(s, "Move", 1000) and s.Progress == 24)
	end)
	test("achieving a goal does not bypass the minimum lesson duration", function()
		local s = state({{Kind = "Slide", Goal = 1, MinSeconds = 1}, {Kind = "Read", Goal = 1, MinSeconds = 2}})
		assert(State.Record(s, "Slide", 1, "first-slide"))
		assert(not State.Advance(s, 100.5) and s.Index == 1)
		assert(State.Advance(s, 101) and s.Index == 2 and s.Progress == 0)
		assert(not State.Advance(s, 102.99) and State.Advance(s, 103) and s.Completed)
	end)
	test("advancing resets deduplication only for the next lesson", function()
		local s = state({{Kind = "Reload", Goal = 1, MinSeconds = 0}, {Kind = "Reload", Goal = 1, MinSeconds = 0}})
		assert(State.Record(s, "Reload", 1, "weapon")); assert(State.Advance(s, 100))
		assert(s.Progress == 0 and State.Record(s, "Reload", 1, "weapon"))
	end)
	test("completion freezes objectives and cannot be repeated", function()
		local s = state({{Kind = "Heal", Goal = 1, MinSeconds = 0}})
		assert(State.Record(s, "Heal", 1, "bite")); assert(State.Advance(s, 100))
		assert(s.Completed and not State.Advance(s, 101) and not State.Record(s, "Heal", 1, "next-bite"))
		assert(not State.CanContinue(s, 101))
	end)
	test("reading timestamps reject premature and invalid clocks", function()
		local s = state({{Kind = "Read", Goal = 1, MinSeconds = 1}})
		assert(not State.Advance(s, 99) and not State.Advance(s, 0/0))
		assert(State.Advance(s, 101))
	end)
	test("request limiter permits its burst then replenishes at the configured rate", function()
		local bucket = {}
		for _ = 1, 6 do assert(State.AllowRequest(bucket, 100, 6, 2)) end
		assert(not State.AllowRequest(bucket, 100, 6, 2))
		assert(not State.AllowRequest(bucket, 100.49, 6, 2))
		assert(State.AllowRequest(bucket, 100.5, 6, 2) and not State.AllowRequest(bucket, 100.5, 6, 2))
	end)
	test("idle request buckets cap replenishment at the allowed burst", function()
		local bucket = {}; assert(State.AllowRequest(bucket, 1, 3, 2))
		for _ = 1, 3 do assert(State.AllowRequest(bucket, 1000, 3, 2)) end
		assert(not State.AllowRequest(bucket, 1000, 3, 2))
	end)
	test("configured tutorial covers every core action and closes with lobby systems", function()
		local kinds, ids = {}, {}
		for _, step in ipairs(Steps) do
			assert(type(step.Id) == "string" and not ids[step.Id]); ids[step.Id] = true
			assert(type(step.Title) == "string" and #step.Title > 0 and type(step.Body) == "string" and #step.Body > 0)
			assert(type(step.Objective) == "string" and #step.Objective > 0 and step.Goal > 0 and step.MinSeconds >= 0)
			kinds[step.Kind] = true
			if step.NPCs then assert(step.NPCs >= 1 and step.NPCs <= 4) end
		end
		for _, kind in ipairs({"Move", "Sprint", "Slide", "EquipKnife", "KnifeStab", "KnifeThrow", "EquipRevolver", "Revolver", "Reload", "Heal", "Eliminate", "Read"}) do assert(kinds[kind]) end
		assert(ids.rounds and ids.collection and ids.settings and Steps[1].Kind == "EquipKnife" and Steps[1].NPCs == 1 and Steps[#Steps].Kind == "Read")
	end)
	print("Tutorial state: " .. passed .. " progress/rate-limit tests passed")
end
