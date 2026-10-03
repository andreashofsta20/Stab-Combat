local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local MainGame = require(script.Parent.Parent.Game.MainGame)
local Hitboxes = require(script.Parent.PlayerHitbox)
local Math = require(RS.Modules.ProjectileMath)
local RagdollQuery = require(RS.Modules.RagdollQuery)
local remotes = RS:WaitForChild("Remotes"):WaitForChild("Knife")
local resultRemote, damageRemote = remotes:WaitForChild("ThrewClient"), remotes:WaitForChild("DamageDealtClient")
local knives = ServerStorage:WaitForChild("Knives")
local recent, order, lastShot = {}, {}, {}
local ThrowKnife = {}

local function validId(id)
	return type(id) == "string" and #id > 0 and #id <= 64 and id:match("^[%w_%-]+$") ~= nil
end
local function reject(player, id)
	if validId(id) then resultRemote:FireClient(player, {shotId = id, accepted = false}) end
	return false
end
function ThrowKnife.Throw(player, id, origin, direction, charge)
	if not validId(id) or not Math.IsFiniteVector(origin) or not Math.IsFiniteVector(direction)
		or not Math.IsFiniteNumber(charge) then return reject(player, id) end
	local now = os.clock()
	if recent[player] and recent[player][id] then return reject(player, id) end
	if now - (lastShot[player] or -math.huge) < Math.COOLDOWN then return reject(player, id) end
	if not MainGame.GameActive or not MainGame.PlayersInGame[player.UserId] or player:GetAttribute("DataReady") ~= true then return reject(player, id) end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not humanoid or humanoid.Health <= 0 or not head or not tool or not knives:FindFirstChild(tool.Name) then return reject(player, id) end
	local unit = Math.NormalizeDirection(direction)
	if not unit or (origin - head.Position).Magnitude > Math.MAX_ORIGIN_DISTANCE then return reject(player, id) end
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, RagdollQuery.Exclude({character})
	local originOffset = origin - head.Position
	if originOffset.Magnitude > 0.001 and workspace:Raycast(head.Position, originOffset, params) then return reject(player, id) end
	charge, direction = Math.ClampCharge(charge), unit
	lastShot[player] = now
	recent[player], order[player] = recent[player] or {}, order[player] or {}
	recent[player][id] = true
	table.insert(order[player], id)
	if #order[player] > 128 then recent[player][table.remove(order[player], 1)] = nil end
	-- The old fixed-step loop never yielded and the path has no gravity. A
	-- single swept ray covers exactly the same line at the same hit timing.
	local destination = Math.GetPosition(origin, direction, Math.MAX_FLIGHT_TIME, charge)
	local hit = workspace:Raycast(origin, destination - origin, params)
	if hit then
		destination = hit.Position
		local victim, victimHumanoid = Hitboxes.GetPlayerFromHitbox(hit.Instance)
		if victim and victim ~= player and MainGame.PlayersInGame[victim.UserId]
			and victimHumanoid and victimHumanoid.Health > 0 and not victimHumanoid.Parent:FindFirstChildOfClass("ForceField") then
            local dealt = MainGame.DamagePlayer(player, victim, victimHumanoid, Math.DAMAGE,
				{ Kind = "KnifeThrow", Direction = direction })
			if dealt > 0 then damageRemote:FireClient(player, victimHumanoid.Parent, dealt, "KnifeThrow", tool.Name) end
		end
	end
	local result = {shotId = id, accepted = true, hit = hit ~= nil, position = destination, normal = hit and hit.Normal}
	resultRemote:FireClient(player, result)
	-- Clients render anchored cosmetics. Server geometry/damage stays authoritative.
	resultRemote:FireAllClients({
		visualOnly = true, shotId = id, shooterUserId = player.UserId,
		knifeName = tool.Name, origin = origin, direction = direction, charge = charge,
		destination = destination, normal = result.normal,
	})
	return true
end
Players.PlayerRemoving:Connect(function(player) recent[player], order[player], lastShot[player] = nil, nil, nil end)
return ThrowKnife
