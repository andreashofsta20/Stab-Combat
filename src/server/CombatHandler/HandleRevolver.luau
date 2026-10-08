local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig)
local Math = require(ReplicatedStorage.Modules.RevolverMath)
local Raycast = require(ReplicatedStorage.Modules.RevolverRaycast)
local Catalog = require(ReplicatedStorage.Modules.RevolversInfo)
local ToolPhysics = require(ReplicatedStorage.Modules.RevolverToolPhysics).New(Catalog)
local State = require(script.Parent.RevolverState)
local History = require(script.Parent.RevolverHitHistory)
local PoseMath = require(ReplicatedStorage.Modules.RevolverPoseMath)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)
local MainGame = require(script.Parent.Parent.Game.MainGame)
local DamageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("DamageDealtClient")

local function getOrCreate(parent, name, className)
	local instance = parent:FindFirstChild(name)
	if instance then
		assert(instance:IsA(className), name .. " must be a " .. className)
		return instance
	end
	instance = Instance.new(className)
	instance.Name, instance.Parent = name, parent
	return instance
end
local folder = getOrCreate(ReplicatedStorage.Remotes, "Revolver", "Folder")
local Action = getOrCreate(folder, "Action", "RemoteEvent")
local Snapshot = getOrCreate(folder, "State", "RemoteEvent")
local Shot = getOrCreate(folder, "Shot", "RemoteEvent")
local Aim = getOrCreate(folder, "Aim", "UnreliableRemoteEvent")
local sessions, buckets, connections = {}, {}, {}
local poseBuckets = {}
local tunings = {}

local function getTuning(name)
	local tuning = tunings[name]
	if not tuning then tuning = Config.Get(name); tunings[name] = tuning end
	return tuning
end

local function now() return workspace:GetServerTimeNow() end
local function heldRevolver(player)
	local character = player.Character
	local stats = player:FindFirstChild("leaderstats")
	local selected = stats and stats:FindFirstChild("EquippedGun")
	local inventory = stats and stats:FindFirstChild("RevolverInventory")
	local owned = selected and selected:IsA("StringValue") and inventory and inventory:FindFirstChild(selected.Value)
	local quantity = owned and owned:FindFirstChild("Quantity")
	local weapons = ServerStorage:FindFirstChild("Revolvers")
	if not character or not selected or not selected:IsA("StringValue")
		or not quantity or not quantity:IsA("IntValue") or quantity.Value <= 0
		or not weapons or not Catalog[selected.Value] or not weapons:FindFirstChild(selected.Value) then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == selected.Value then return child end
	end
	return nil
end

local function canPlay(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local stats = player:FindFirstChild("leaderstats")
	local settings = stats and stats:FindFirstChild("Settings")
	local lobby = settings and settings:FindFirstChild("LobbyMode")
	return MainGame.GameActive and MainGame.PlayersInGame[player.UserId] == true
		and MainGame.RoundStats ~= nil and not MainGame.RoundStats.rewardsApplied
		and player:GetAttribute("DataReady") == true and player:GetAttribute("InRound") == true
		and humanoid ~= nil and humanoid.Health > 0 and not (lobby and lobby.Value)
end

local function canPresent(player)
	if canPlay(player) then return true end
	if Config.Presentation.LobbyAimingEnabled ~= true or player:GetAttribute("InRound") == true
		or MainGame.PlayersInGame[player.UserId] == true or player:GetAttribute("DataReady") ~= true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function getSession(player)
	local session = sessions[player]
	if not session or session.character ~= player.Character or session.round ~= MainGame.RoundStats then
		session = State.New(Config.Capacity)
		session.id = HttpService:GenerateGUID(false)
		session.character, session.round = player.Character, MainGame.RoundStats
		sessions[player] = session
	end
	return session
end

local function sendState(player, session, reason, syncSequence)
	session.revision += 1
	Snapshot:FireClient(player, {
		Session = session.id, Character = session.character,
		Revision = session.revision, AckSequence = session.sequence,
		Ammo = session.ammo, Capacity = Config.Capacity,
		ReloadEnd = session.reloadEnd, NextShot = session.nextShot,
		Reason = reason,
		SyncSequence = syncSequence,
	})
end

local function worldCaster()
	local ignore = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = RagdollQuery.Exclude(ignore)
	params.IgnoreWater = true
	return function(origin, vector) return workspace:Raycast(origin, vector, params) end
end

local function candidates(shooter, time, tuning)
	local result = {}
	for _, victim in ipairs(Players:GetPlayers()) do
		if victim ~= shooter and canPlay(victim) then
			local character = victim.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and Math.IsFiniteVector(root.Position, Config.Security.MaxCoordinate)
				and humanoid and not character:FindFirstChildOfClass("ForceField") then
				local snapshot = History.GetSnapshot(victim, character, MainGame.RoundStats, time, root.CFrame, Config.LagCompensation)
				snapshot.player, snapshot.humanoid, snapshot.character = victim, humanoid, character
				snapshot.frame = snapshot.frame * CFrame.new(table.unpack(tuning.HitboxOffset))
				table.insert(result, snapshot)
			end
		end
	end
	return result
end

Action.OnServerEvent:Connect(function(player, action, sessionId, sequence, cameraOrigin, cameraDirection, timestamp)
	local time = now()
	local bucket = buckets[player]
	if not bucket then bucket = { tokens = Config.Security.RequestBurst, time = time }; buckets[player] = bucket end
	-- Limit before expensive validation/rays; floods produce no reply amplification.
	if not State.AllowRequest(bucket, time, Config.Security.RequestBurst, Config.Security.RequestsPerSecond) then return end
	if action ~= "Sync" and action ~= "Fire" and action ~= "Reload" then return end
	local session = getSession(player)
	if action == "Sync" then
		local syncSequence = sessionId == session.id and Math.IsFiniteNumber(sequence)
			and sequence >= 0 and sequence % 1 == 0 and sequence <= 2147483647 and sequence or 0
		sendState(player, session, "Sync", syncSequence)
		return
	end
	if type(sessionId) ~= "string" or #sessionId > 64 or sessionId ~= session.id then
		sendState(player, session, "Session")
		return
	end
	if not State.AcceptSequence(session, sequence) then return end
	local tool = heldRevolver(player)
	if player:GetAttribute("MovementAdmitted") ~= nil and not require(script.Parent.MovementAuthority).Admit(player) then return end
	if not canPlay(player) or not tool or player:GetAttribute("InventoryLocked") == true or player:GetAttribute("MovementAdmitted") == false then
		State.CancelReload(session)
		sendState(player, session, "Unavailable")
		return
	end
	local tuning = getTuning(tool.Name)
	if session.reloadEnd > 0 and session.reloadTool ~= tool then State.CancelReload(session) end
	State.Advance(session, time, Config.Capacity)
	if action == "Reload" then
		local accepted, reason = State.Reload(session, time, tuning.ReloadDurationMs / 1000, Config.Capacity)
		session.reloadTool = accepted and tool or session.reloadTool
		sendState(player, session, accepted and "Reload" or reason)
		return
	end
	if session.reloadEnd > 0 or time < session.nextShot or session.ammo <= 0 then
		local reason = session.reloadEnd > 0 and "Reloading" or (session.ammo <= 0 and "Empty" or "Cooldown")
		sendState(player, session, reason)
		return
	end
	local ping = player:GetNetworkPing()
	if not Math.IsFiniteVector(cameraOrigin, Config.Security.MaxCoordinate)
		or not Math.IsFiniteVector(cameraDirection, 2)
		or cameraDirection.Magnitude < 0.99 or cameraDirection.Magnitude > 1.01
		or not Math.TimestampAllowed(time, timestamp, ping, Config.Security) then
		sendState(player, session, "InvalidAim")
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart")
		or not Math.IsFiniteVector(head.Position, Config.Security.MaxCoordinate)
		or (cameraOrigin - head.Position).Magnitude > Config.Security.MaxCameraDistance then
		sendState(player, session, "Camera")
		return
	end
	local cast = worldCaster()
	-- The animated Tool can dip behind a ledge while the cursor stays clear.
	-- Resolve gameplay from the trusted eye/head position; barrel motion is visual.
	-- Cover is checked head-to-target, not head-to-camera: a valid rear target
	-- can itself be the part between the camera and character.
	local origin = head.Position
	local rewind = Math.RewindTime(time, timestamp, ping, Config.LagCompensation)
	local result = Raycast.Resolve(cameraOrigin, cameraDirection.Unit, origin, tuning, candidates(player, rewind, tuning), cast)
	if not result then sendState(player, session, "InvalidAim"); return end
	local accepted, reason = State.Fire(session, time, tuning.FireIntervalMs / 1000, Config.Capacity)
	if not accepted then sendState(player, session, reason); return end
	-- No yields between consumption, resolution, eligibility checks and damage.
	local victim = result.victim
	local hit = false
	if victim and canPlay(victim.player) and victim.player.Character == victim.character
		and victim.humanoid.Health > 0 and not victim.character:FindFirstChildOfClass("ForceField") then
		local headshot = result.headshot == true
        local dealt = MainGame.DamagePlayer(player, victim.player, victim.humanoid, headshot and tuning.HeadshotDamage or tuning.Damage,
			{ Kind = "Revolver", Direction = result.position - origin })
		if dealt > 0 then DamageRemote:FireClient(player, victim.character, dealt, "Revolver", tool.Name, headshot); hit = true end
	end
	sendState(player, session, "Fired")
	Shot:FireAllClients({
		ShooterId = player.UserId, Session = session.id, Sequence = sequence,
		Weapon = tool.Name, Origin = origin, Position = result.position, Normal = result.normal,
		Surface = result.surface, Hit = hit,
	})
end)

-- Cosmetic angles only: these packets never authorize damage or change ammo.
-- A separate bucket keeps pose updates from consuming the shooting budget.
Aim.OnServerEvent:Connect(function(player, sessionId, sequence, pitch, yaw, aiming)
	local time = now()
	local limits = Config.PoseReplication
	local bucket = poseBuckets[player]
	if not bucket then bucket = { tokens = limits.RequestBurst, time = time }; poseBuckets[player] = bucket end
	if not State.AllowRequest(bucket, time, limits.RequestBurst, limits.RequestsPerSecond) then return end
	if type(aiming) ~= "boolean" then return end
	local session = sessions[player]
	if not session or sessionId ~= session.id or session.character ~= player.Character
		or session.round ~= MainGame.RoundStats or not canPresent(player) then return end
	local tool = heldRevolver(player)
	if not tool then return end
	local tuning = getTuning(tool.Name)
	if not tuning.Pose.Enabled or not PoseMath.AcceptPacket(session, sequence, pitch, yaw, tuning.Pose, aiming) then return end
	Aim:FireAllClients(player.UserId, session.character, session.id, sequence, pitch, yaw,
		aiming and tuning.Aim.Enabled, canPlay(player) and session.reloadEnd > time, time)
end)

local function bindPlayer(player)
	if connections[player] then return end
	ToolPhysics.BindPlayer(player)
	connections[player] = player.CharacterRemoving:Connect(function()
		sessions[player] = nil
		History.Remove(player)
	end)
end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	ToolPhysics.RemovePlayer(player)
	if connections[player] then connections[player]:Disconnect() end
	connections[player], sessions[player], buckets[player] = nil, nil, nil
	poseBuckets[player] = nil
	History.Remove(player)
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end

local sampleElapsed = 0
RunService.Heartbeat:Connect(function(dt)
	local time = now()
	sampleElapsed += dt
	if sampleElapsed >= 1 / Config.LagCompensation.SampleHz then
		sampleElapsed = 0
		History.Sample(time, MainGame.RoundStats, MainGame.PlayersInGame, Config.LagCompensation)
	end
	for player, session in pairs(sessions) do
		if session.reloadEnd > 0 then
			if session.character ~= player.Character or session.round ~= MainGame.RoundStats
				or not canPlay(player) or heldRevolver(player) ~= session.reloadTool then
				State.CancelReload(session)
				sendState(player, session, "ReloadCancelled")
			elseif State.Advance(session, time, Config.Capacity) then
				session.reloadTool = nil
				sendState(player, session, "Reloaded")
			end
		end
	end
end)

return {}
