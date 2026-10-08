local Studio = game:GetService("StudioTestService")
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local args = Studio:GetTestArgs() or {Players = 2}
local report = {Tests = {}, Errors = {}, Players = args.Players, Backend = "isolated in-memory adapter and ProfileStore.Mock", PlaceId = game.PlaceId, MaxPlayers = Players.MaxPlayers}
if args.RealBackend then report.Backend="real DataStores in unique disposable namespaces"; report.Namespace=args.Namespace end
local metrics=Instance.new("RemoteEvent"); metrics.Name,metrics.Parent="BetaAuditMetrics",RS
report.Clients={}
metrics.OnServerEvent:Connect(function(player,data) if type(data)=="table" then report.Clients[player.Name]=data end end)
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
	if args.RealBackend then
		test("real backend profile and receipt acknowledgements", function()
			local profile = Profiles.GetProfile(first)
			local marker = Http:GenerateGUID(false)
			profile.Data.BetaAuditProbe = marker
			assert(Profiles.ConfirmSave(first,profile,function(saved) return saved.BetaAuditProbe == marker end,30))
			local saved = Profiles.GetAsync(first.UserId)
			assert(saved and saved.Data.BetaAuditProbe == marker, "profile read did not contain acknowledged data")
			local config = require(RS.Modules.DataConfig)
			local store = game:GetService("DataStoreService"):GetDataStore(config.ReceiptStoreName)
			local archive = require(SSS.ServicesHandler.ReceiptArchive)
			local receipt = {PurchaseId = "native-" .. marker, PlayerId = first.UserId, ProductId = 100}
			assert(archive.Commit(store,receipt)); local read, granted = archive.Check(store,receipt.PurchaseId)
			assert(read and granted and archive.Commit(store,receipt), "receipt replay failed")
			profile.Data.BetaAuditProbe = nil
		end)
	end
	local Modes = require(RS.Modules.GameModes)
	Modes.FFA.RoundDuration = math.max(30,(args.Respawns or 3)*8+10)
	local ffaFinished = false
	test("FFA death respawn and lobby forfeit", function()
		task.spawn(function() Main.StartGame("Grids","FFA"); ffaFinished = true end)
		waitFor(function() return Main.GameActive and Main.CurrentMode.Id == "FFA" and first:GetAttribute("InRound") == true end, 30, "FFA start")
		for _ = 1, args.Respawns or 3 do
			local old = first.Character; old.Humanoid.Health = 0
			waitFor(function() return first.Character ~= old and first.Character and first.Character:FindFirstChild("Humanoid") and first.Character.Humanoid.Health > 0 end, 12, "FFA respawn")
			assert(first:GetAttribute("InRound") == true)
		end
		Main.LeaveRound(first)
		assert(first:GetAttribute("InRound") == false)
		waitFor(function() return ffaFinished end, Modes.FFA.RoundDuration+30, "FFA cleanup")
	end)
	-- A failed FFA assertion must not accidentally test the still-running FFA
	-- as BR. Wait for StartGame's final cleanup, including yielding rewards.
	waitFor(function() return ffaFinished end, Modes.FFA.RoundDuration+30, "FFA task completion")
	test("BR elimination and cleanup", function()
		local finished = false
		task.spawn(function() Main.StartGame("Grids","BattleRoyale"); finished = true end)
		waitFor(function() return Main.GameActive and Main.CurrentMode.Id == "BattleRoyale" and first:GetAttribute("InRound") == true end, 30, "BR start")
		for _, p in ipairs(Players:GetPlayers()) do if p ~= first and p.Character then p.Character.Humanoid.Health = 0 end end
		waitFor(function() return finished end, 20, "BR winner cleanup")
		waitFor(function() return next(Main.PlayersInGame) == nil end,10,"BR participant cleanup")
	end)
	if args.SoakSeconds and args.SoakSeconds>0 then
		report.Soak={Seconds=args.SoakSeconds,Samples={},Respawns=0}
		Modes.FFA.RoundDuration=args.SoakSeconds+60
		task.spawn(Main.StartGame,"Grids","FFA")
		waitFor(function() return Main.GameActive end,30,"soak round")
		local deadline=os.clock()+args.SoakSeconds
		while os.clock()<deadline do
			table.insert(report.Soak.Samples,{At=args.SoakSeconds-(deadline-os.clock()),MemoryMB=game:GetService("Stats"):GetTotalMemoryUsageMb(),Instances=#game:GetDescendants(),LuaKB=gcinfo()})
			metrics:FireAllClients()
			if first.Character then first.Character.Humanoid.Health=0; report.Soak.Respawns+=1 end
			task.wait(30)
		end
		Main.CleanupRound(true)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local data = Profiles.GetProfileData(p)
		if data then
			Profiles.SyncProfile(p)
			report["ProfileBytes_" .. p.Name] = #Http:JSONEncode(data)
		end
	end
	report.ServerMemoryMB = game:GetService("Stats"):GetTotalMemoryUsageMb()
	if not args.RealBackend then report.BackendWrites = require(SSS.BetaAuditBackend).Writes end
	report.InstanceCount = #game:GetDescendants()
	report.MovementRejections = first:GetAttribute("MovementRejectedCount")
end)
metrics:FireAllClients(); task.wait(2)
if not ok then report.Fatal = tostring(err) end
report.ConnectedPlayers = #Players:GetPlayers()
report.StartupState = RS:GetAttribute("ServerStartupState")
report.StartupPending = RS:GetAttribute("ServerStartupPending")
report.StartupFailed = RS:GetAttribute("ServerStartupFailures")
Studio:EndTest(report)
