-- TEST-ONLY native tutorial rehearsal. Injected into an unsaved Studio copy.
-- Locomotion/reload/heal signals are driven through the server Runtime here;
-- actual stab and throw use production weapon APIs against native geometry.
local Studio = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local args = Studio:GetTestArgs() or {}
local report = {Tests = {}, Errors = {}, Clients = {}, PlaceId = game.PlaceId, UniverseId = game.GameId,
	Backend = "BetaAuditBackend and ProfileStore.Mock; no persistent player records", Preview = true,
	MapFixture = args.MapFixture or RS:GetAttribute("TutorialTestMapFixture"),
	MapAlias = args.MapAlias == true or RS:GetAttribute("TutorialTestMapAlias") == true,
	Travel = "UnverifiedInStudio: published reserved-server round trip required",
	SyntheticActions = {"Move", "Sprint", "Slide", "Reload", "Heal", "Revolver"},
	NativeWeaponAPIs = {"StabKnife.Stab", "ThrowKnife.Throw"}}
local ended = false
local function endTest()
	if ended then return end
	ended = true
	report.StartupState = RS:GetAttribute("ServerStartupState")
	report.StartupPending = RS:GetAttribute("ServerStartupPending")
	report.StartupFailures = RS:GetAttribute("ServerStartupFailures")
	report.ConnectedPlayers = #Players:GetPlayers()
	Studio:EndTest(report)
end
task.delay(150, function() report.Fatal = "Native tutorial test exceeded its bounded watchdog"; endTest() end)
game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError and #report.Errors < 60 then table.insert(report.Errors, message) end
end)
local visual = RS:WaitForChild("TutorialVisualAudit", 10)
assert(visual and visual:IsA("RemoteEvent"), "Native visual report remote is missing")
visual.OnServerEvent:Connect(function(player, data)
	if type(data) == "table" and type(data.Checks) == "table" then report.Clients[player.Name] = data end
end)
local function waitFor(predicate, seconds, description)
	local deadline = os.clock() + seconds
	repeat
		if predicate() then return end
		task.wait(0.05)
	until ended or os.clock() >= deadline
	error("Timed out: " .. description)
end
local function test(name, fn)
	local ok, err = pcall(fn)
	table.insert(report.Tests, {Name = name, Passed = ok, Error = not ok and tostring(err) or nil})
	print("TUTORIAL_NATIVE " .. name .. ": " .. tostring(ok) .. (ok and "" or " " .. tostring(err)))
	return ok
end

local ok, fatal = pcall(function()
	assert(game:GetService("RunService"):IsStudio(), "Test is Studio-only")
	assert(args.NativeOverlay == true, "This script requires the isolated overlay builder")
	local config = require(RS.Modules.TutorialConfig)
	assert(config.Studio.EnableSoloPreview == true, "Preview must be explicit")
	assert(require(RS.Modules.DataConfig).UseMockProfiles == true, "Real player profiles are forbidden")
	waitFor(function() return #Players:GetPlayers() == 1 end, 60, "one native client")
	local player = Players:GetPlayers()[1]
	waitFor(function() return RS:GetAttribute("ServerReady") == true end, 60, "required startup")
	waitFor(function() return player:GetAttribute("DataReady") == true and player:GetAttribute("TutorialActive") == true end, 60, "mock profile and tutorial admission")
	local Runtime = require(SSS.Tutorial.TutorialRuntime)
	local State = require(SSS.Tutorial.TutorialState)
	local Steps = require(RS.Modules.TutorialSteps)
	local Controller = require(SSS.ServicesHandler.TutorialService)
	local Profiles = require(SSS.DataStore.ProfileManager)
	local Movement = require(SSS.CombatHandler.MovementAuthority)
	local Stab = require(SSS.CombatHandler.StabKnife)
	local Throw = require(SSS.CombatHandler.ThrowKnife)
	local Food = require(SSS.CombatHandler.FoodService)
	local session = Runtime.GetSession(player)
	assert(session and session.Arena, "Native tutorial session is missing")
	waitFor(function() return not session.Preparing and #Runtime.GetTargets(player) >= 1 end, 10, "first lesson ready with practice target")
	local stats = player:WaitForChild("leaderstats")
	local baseline = {XP = stats.XP.Value, Cash = stats.Cash.Value, Kills = stats.Kills.Value, Deaths = stats.Deaths.Value,
		Inventory = #stats.Inventory:GetChildren(), Tutorial = Profiles.GetProfile(player).Data.Tutorial}
	local function current() return State.Step(session.Progress) end
	local function moved(index)
		waitFor(function() return (session.Progress.Completed or session.Progress.Index > index) and not session.Preparing end, 10, "prepared lesson advance " .. tostring(index))
	end
	local function equip(category, name)
		local character = assert(player.Character)
		local humanoid = character:WaitForChild("Humanoid")
		for _, tool in ipairs(character:GetChildren()) do if tool:IsA("Tool") then tool:Destroy() end end
		local template = assert(SS:FindFirstChild(category)):FindFirstChild(name)
		assert(template and template:IsA("Tool"), "Native weapon template missing: " .. name)
		local tool = template:Clone(); tool.CanBeDropped = false; tool.Parent = player:WaitForChild("Backpack")
		humanoid:EquipTool(tool)
		waitFor(function() return tool.Parent == character end, 5, "native equip " .. name)
		return tool
	end
	local fixtureIndex = 0
	local function positionForTarget(model, distance)
		fixtureIndex += 1
		local character = assert(player.Character)
		local root = character:WaitForChild("HumanoidRootPart")
		local npcRoot = model:WaitForChild("HumanoidRootPart")
		root.Anchored, npcRoot.Anchored = true, true
		local base = session.Arena.Spawns[1].Position + Vector3.new(80 + fixtureIndex * 40, 60, 0)
		-- The elevated, anchored fixture isolates the native cover/ray/geometry
		-- test from map props. This does not validate authored spawn balance.
		model:PivotTo(CFrame.new(base + Vector3.new(0, 0, -distance)))
		character:PivotTo(CFrame.lookAt(base, npcRoot.Position))
		root.CFrame = CFrame.lookAt(base, npcRoot.Position)
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		player:SetAttribute("ServerTeleportPosition", root.Position)
		player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
		assert(Movement.Reset(player), "Native movement authority reset failed")
		task.wait(0.15) -- Settle native Motor6D/assembly transforms before geometry queries.
		assert(Movement.Reset(player), "Native settled movement reset failed")
		return character, root, model:FindFirstChildOfClass("Humanoid")
	end

	test("isolated native startup and registered practice targets", function()
		assert(session.Replay == true, "Studio rehearsal must be rewardless")
		assert(session.Arena.Map:GetAttribute("TutorialMap") == true)
		assert(Runtime.IsActive(player))
		local targets = Runtime.GetTargets(player); assert(#targets >= 1, "First lesson needs a practice target")
		for _, model in ipairs(targets) do
			assert(Runtime.GetTarget(player, model.HumanoidRootPart) == model)
			assert(model.HumanoidRootPart:GetNetworkOwner() == nil, "NPC assembly must be server-owned")
		end
		assert(require(SSS.Game.MainGame).GameActive == false, "Native PvP round loop must remain inactive")
	end)
	test("client actions cannot skip a gameplay objective", function()
		local index = session.Progress.Index
		Controller.Handle(player, "Continue")
		Controller.Handle(player, "Complete")
		Controller.Handle(player, {Action = "Continue"})
		assert(session.Progress.Index == index and session.Progress.Progress == 0, "Request bypassed gameplay evidence")
	end)

	local equipped = equip("Knives", stats.EquippedKnife.Value)
	waitFor(function() return current().Kind == "KnifeStab" and not session.Preparing end, 10, "first stab lesson")
	test("production stab validates native NPC and credits one knockout", function()
		local index = session.Progress.Index
		local model = assert(Runtime.GetTargets(player)[1])
		local _, root, humanoid = positionForTarget(model, 6)
		assert(equipped.Parent == player.Character)
		Stab.Stab(player)
		assert(humanoid.Health <= 0, "Native stab did not hit registered NPC")
		report.FirstKnockoutAtSeconds = os.clock() - session.Progress.StartedAt
		assert(session.Progress.Progress == current().Goal or session.Progress.Index > index, "Fatal stab did not credit objective")
		moved(index); assert(session.Arena:Place(player.Character)); root.Anchored = false
	end)
	waitFor(function() return current().Kind == "Move" end, 10, "move lesson")
	test("movement exploit and server teleport give no tutorial distance credit", function()
		local root = player.Character:WaitForChild("HumanoidRootPart")
		root.Anchored = false; assert(Movement.Reset(player))
		local frame, before = root.CFrame, session.Progress.Progress
		root.CFrame += Vector3.new(1000, 0, 0)
		assert(not Movement.Admit(player), "Excessive displacement was admitted")
		assert((root.Position - frame.Position).Magnitude < 1, "Rejected displacement was not restored")
		task.wait(0.2); assert(session.Progress.Progress == before, "Rejected movement counted toward lesson")
		root.CFrame += Vector3.new(0, 0, 20)
		player:SetAttribute("ServerTeleportPosition", root.Position)
		player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
		assert(Movement.Admit(player), "Server-authorized placement was rejected")
		task.wait(0.2); assert(session.Progress.Progress == before, "Server teleport counted as player movement")
	end)
	test("native reset preserves session and lesson without competitive death credit", function()
		local index, id, old = session.Progress.Index, session.Id, player.Character
		old:FindFirstChildOfClass("Humanoid").Health = 0
		waitFor(function() return player.Character ~= old and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 end, 15, "tutorial respawn")
		waitFor(function() return player:GetAttribute("MovementAdmitted") == true end, 5, "respawn movement authority")
		assert(Runtime.GetSession(player) == session and session.Id == id and session.Progress.Index == index)
		assert(stats.Deaths.Value == baseline.Deaths, "Tutorial reset changed competitive deaths")
	end)

	local guard = 0
	while not session.Progress.Completed do
		guard += 1; assert(guard <= #Steps + 2, "Tutorial loop failed to progress")
		local step, index = current(), session.Progress.Index
		if step.Kind == "EquipKnife" then equip("Knives", stats.EquippedKnife.Value)
		elseif step.Kind == "EquipRevolver" then equip("Revolvers", stats.EquippedGun.Value)
		elseif step.Kind == "KnifeThrow" then
			equip("Knives", stats.EquippedKnife.Value)
			test("production throw validates native head geometry and projectile path", function()
				local targets = Runtime.GetTargets(player); assert(#targets >= step.Goal)
				for _, model in ipairs(targets) do
					local character, _, humanoid = positionForTarget(model, 10)
					local origin = character.Head.Position
					local direction = (model.Head.Position - origin).Unit
					local probeParams = RaycastParams.new(); probeParams.FilterType = Enum.RaycastFilterType.Exclude
					probeParams.FilterDescendantsInstances = {character}
					local probe = workspace:Raycast(origin, direction * 20, probeParams)
					assert(probe and Runtime.GetTarget(player, probe.Instance) == model, "Fixture ray did not reach the selected live NPC")
					local accepted = Throw.Throw(player, "native_" .. game:GetService("HttpService"):GenerateGUID(false), origin, direction, 1)
					assert(accepted == true and humanoid.Health <= 0, "Native throw accepted=" .. tostring(accepted) .. " health=" .. tostring(humanoid.Health) .. " firstHit=" .. (probe and probe.Instance:GetFullName() or "none"))
					-- Corpses intentionally persist for presentation. Keep them
					-- outside subsequent fixture rays without altering runtime credit.
					for _, part in ipairs(model:GetDescendants()) do if part:IsA("BasePart") then part.CanQuery = false end end
					task.wait(0.85)
				end
				assert(session.Arena:Place(player.Character)); player.Character.HumanoidRootPart.Anchored = false
			end)
		elseif step.Kind == "Revolver" or step.Kind == "Eliminate" then
			test("registered NPC damage progresses " .. step.Kind .. " without PvP rewards", function()
				local targets = Runtime.GetTargets(player); assert(#targets >= step.Goal)
				for _, model in ipairs(targets) do
					assert(Runtime.Damage(player, model, model:FindFirstChildOfClass("Humanoid").Health, step.Kind) > 0)
				end
				assert(stats.Kills.Value == baseline.Kills and stats.XP.Value == baseline.XP and stats.Cash.Value == baseline.Cash)
			end)
		elseif step.Kind == "Heal" then
			test("native healing lesson damages safely and grants temporary food", function()
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				assert(humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth)
				local food = Food.GetTool(player); assert(food and food:GetAttribute("FoodItem") == "Burger")
				Runtime.Record(player, "Heal", food) -- TEST-ONLY event; native Eat input is covered by fixtures.
			end)
		elseif step.Kind == "Read" then
			Controller.Handle(player, "Continue")
		else
			for action = 1, step.Goal do Runtime.Record(player, step.Kind, {NativeTestAction = action}) end
		end
		moved(index)
	end
	test("preview completion releases enemies and never grants real entitlement", function()
		waitFor(function() return session.Saved == true end, 10, "preview completion")
		assert(not Runtime.IsActive(player) and #Runtime.GetTargets(player) == 0)
		assert(stats.XP.Value == baseline.XP and stats.Cash.Value == baseline.Cash and #stats.Inventory:GetChildren() == baseline.Inventory)
		local state = Profiles.GetProfile(player).Data.Tutorial
		assert(state == baseline.Tutorial and (not state or not state.Completed), "Preview wrote reward entitlement")
		Controller.Handle(player, "Continue"); Controller.Handle(player, "Continue")
		assert(stats.XP.Value == baseline.XP and stats.Cash.Value == baseline.Cash)
	end)
	test("native UI desktop portrait and short-landscape bounds", function()
		waitFor(function() return report.Clients[player.Name] ~= nil end, 35, "native client UI report")
		local client = report.Clients[player.Name]
		assert(#client.Checks >= 10, "Missing native client layout checks")
		for _, check in ipairs(client.Checks) do assert(check.Passed, check.Name .. ": " .. tostring(check.Error)) end
		assert(#client.Errors == 0, "Native client reported runtime errors")
	end)
	report.BackendWrites = require(SSS.BetaAuditBackend).Writes
	report.NativeCompletionDurationSeconds = os.clock() - session.Progress.StartedAt
	report.CompletedLessons = session.Progress.Index
	report.MovementRejectedCount = player:GetAttribute("MovementRejectedCount")
	report.ServerMemoryMB = game:GetService("Stats"):GetTotalMemoryUsageMb()
end)
if not ok then report.Fatal = tostring(fatal) end
report.AllPassed = report.Fatal == nil
for _, result in ipairs(report.Tests) do if not result.Passed then report.AllPassed = false end end
if #report.Errors > 0 then report.AllPassed = false end
endTest()
