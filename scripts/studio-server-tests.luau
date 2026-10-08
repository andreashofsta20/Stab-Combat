local Studio = game:GetService("StudioTestService")
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local args = Studio:GetTestArgs() or {Players = 2}
local report = {Tests = {}, Errors = {}, Players = args.Players, Backend = "isolated in-memory adapter and ProfileStore.Mock", PlaceId = game.PlaceId}
game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError and #report.Errors < 100 then table.insert(report.Errors, message) end
end)
local function waitFor(predicate, seconds, description)
	local deadline = os.clock() + seconds
	repeat if predicate() then return end; task.wait(0.1) until os.clock() >= deadline
	error("Timed out: " .. description)
end
local function test(name, fn)
	local ok, err = pcall(fn); table.insert(report.Tests, {Name = name, Passed = ok, Error = not ok and tostring(err) or nil})
	print("BETA_NATIVE " .. name .. ": " .. tostring(ok) .. (ok and "" or " " .. tostring(err)))
	return ok
end
local ok, err = pcall(function()
	waitFor(function() return #Players:GetPlayers() >= args.Players end, 90, "multiplayer connections")
	test("required startup and independent profiles", function()
		waitFor(function() return RS:GetAttribute("ServerReady") == true end, 60, "startup: " .. tostring(RS:GetAttribute("ServerStartupPending")))
		for _, p in ipairs(Players:GetPlayers()) do
			waitFor(function() return p:GetAttribute("DataReady") == true end, 60, "profile " .. p.Name)
			assert(p.leaderstats.Inventory:FindFirstChild("Bowie")); assert(p.leaderstats.RevolverInventory:FindFirstChild("Normal Revolver"))
		end
	end)
	if RS:GetAttribute("ServerReady") ~= true then error("Startup failed: " .. tostring(RS:GetAttribute("ServerStartupFailed"))) end
	local first, second = Players:GetPlayers()[1], Players:GetPlayers()[2]
	local Profiles = require(SSS.DataStore.ProfileManager)
	local Movement = require(SSS.CombatHandler.MovementAuthority)
	test("authorized teleports and excessive displacement", function()
		local root = first.Character:WaitForChild("HumanoidRootPart")
		Movement.Reset(first)
		local accepted = root.CFrame
		root.CFrame += Vector3.new(1000,0,0)
		assert(not Movement.Admit(first), "teleport was admitted")
		assert((root.Position - accepted.Position).Magnitude < 1, "rejection did not restore root")
		root.CFrame += Vector3.new(20,0,0)
		first:SetAttribute("ServerTeleportPosition", root.Position)
		first:SetAttribute("ServerTeleportVersion", (first:GetAttribute("ServerTeleportVersion") or 0)+1)
		assert(Movement.Admit(first), "authorized teleport rejected")
	end)
	if second then
		test("native durable trade acknowledgements", function()
			local Inventory = require(SSS.DataStore.InventoryHandler)
			local catalog = require(RS.Modules.KnivesInfo)
			local item; for name, info in pairs(catalog) do if name ~= "Bowie" and info.Tradeable ~= false then item = name; break end end
			assert(item and Inventory.AddKnife(first, item), "test grant failed")
			local Session = require(SSS.Trading.TradeSession)
			local session = Session.new(first,second)
			assert(session:AddItem(first,"Inventory",item,1))
			assert(require(SSS.Trading.TradePersistence).Execute(session), "trade failed")
			assert(not first:GetAttribute("InventoryLocked") and not second:GetAttribute("InventoryLocked"))
			assert(second.leaderstats.Inventory:FindFirstChild(item), "incoming stock absent")
			assert(next(Profiles.GetProfile(first).Data.TradeJournal) == nil)
		end)
	end
	local Main = require(SSS.Game.MainGame)
	test("practice excludes all persistent rewards and cleans up",function()
		local Range=require(SSS.Game.PracticeRange)
		Profiles.SyncProfile(first)
		local before=Http:JSONEncode(Profiles.GetProfileData(first))
		assert(Range.Enter(first)); assert(first:GetAttribute("PracticeActive")==true)
		task.wait(.3)
		local target=workspace.PracticeRanges[tostring(first.UserId)].Target1
		local head=first.Character.Head
		Range.Action(first,"Fire",head.Position,(target.Position-head.Position).Unit)
		assert(target:GetAttribute("PracticeHealth")<100,"target was not hit")
		Range.Exit(first,true)
		assert(first:GetAttribute("PracticeActive")==false and workspace.PracticeRanges:FindFirstChild(tostring(first.UserId))==nil)
		Profiles.SyncProfile(first)
		assert(before==Http:JSONEncode(Profiles.GetProfileData(first)),"practice changed persistent profile")
	end)
	local Modes = require(RS.Modules.GameModes)
	Modes.FFA.RoundDuration = 30
	test("FFA death respawn and lobby forfeit", function()
		task.spawn(Main.StartGame,"Grids","FFA")
		waitFor(function() return Main.GameActive and first:GetAttribute("InRound") == true end, 30, "FFA start")
		for _ = 1, args.Respawns or 3 do
			local old = first.Character; old.Humanoid.Health = 0
			waitFor(function() return first.Character ~= old and first.Character and first.Character:FindFirstChild("Humanoid") and first.Character.Humanoid.Health > 0 end, 12, "FFA respawn")
			assert(first:GetAttribute("InRound") == true)
		end
		Main.LeaveRound(first)
		assert(first:GetAttribute("InRound") == false)
		waitFor(function() return not Main.GameActive end, 45, "FFA cleanup")
	end)
	test("BR elimination and cleanup", function()
		task.spawn(Main.StartGame,"Grids","BattleRoyale")
		waitFor(function() return Main.GameActive and first:GetAttribute("InRound") == true end, 30, "BR start")
		for _, p in ipairs(Players:GetPlayers()) do if p ~= first and p.Character then p.Character.Humanoid.Health = 0 end end
		waitFor(function() return not Main.GameActive end, 20, "BR winner cleanup")
		waitFor(function() return next(Main.PlayersInGame) == nil end,10,"BR participant cleanup")
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		local data = Profiles.GetProfileData(p)
		if data then
			Profiles.SyncProfile(p)
			report["ProfileBytes_" .. p.Name] = #Http:JSONEncode(data)
		end
	end
	report.ServerMemoryMB = game:GetService("Stats"):GetTotalMemoryUsageMb()
	report.BackendWrites = require(SSS.BetaAuditBackend).Writes
	report.InstanceCount = #game:GetDescendants()
	report.MovementRejections = first:GetAttribute("MovementRejectedCount")
end)
if not ok then report.Fatal = tostring(err) end
report.StartupState = RS:GetAttribute("ServerStartupState")
report.StartupPending = RS:GetAttribute("ServerStartupPending")
report.StartupFailed = RS:GetAttribute("ServerStartupFailures")
Studio:EndTest(report)
