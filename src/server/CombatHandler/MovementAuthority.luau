local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.MovementConfig)
local Admission = require(RS.Modules.MovementAdmission)
local Authority = {}
local states, slides = {}, {}
local elapsed = 0
local function parts(player)
	local character = player.Character
	return character, character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end
function Authority.Reset(player)
	local character, root = parts(player)
	local state = {Character = character, Frame = root and root.CFrame, TeleportVersion = player:GetAttribute("ServerTeleportVersion")}
	local finite = root and Admission.Step(state, root.Position, os.clock(), Config.RunSpeed, 0, false)
	states[player] = finite and state or nil
	player:SetAttribute("MovementAdmitted", finite == true)
	return finite == true
end
function Authority.Admit(player)
	local character, root, humanoid = parts(player)
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local state = states[player]
	if not state or state.Character ~= character or root.Anchored then return Authority.Reset(player) end
	local version = player:GetAttribute("ServerTeleportVersion")
	local destination = player:GetAttribute("ServerTeleportPosition")
	if version ~= state.TeleportVersion and destination and (root.Position - destination).Magnitude < 2 then return Authority.Reset(player) end
	local now = os.clock()
	local speed = slides[player] and now < slides[player].untilTime and Config.SlideSpeed or Config.RunSpeed
	local pingOK, ping = pcall(function() return player:GetNetworkPing() end)
	local blocked = false
	if (root.Position - state.Position).Magnitude > 0.2 then
		local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local exclude = {}
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(exclude, p.Character) end end
		params.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(state.Position, root.Position - state.Position, params)
		blocked = hit ~= nil and math.abs(hit.Normal.Y) < 0.65
	end
	local accepted, reason = Admission.Step(state, root.Position, now, speed * 1.1, pingOK and ping or 0, blocked)
	if accepted then
		state.Frame = root.CFrame
	else
		root.CFrame = state.Frame
		root.AssemblyLinearVelocity = Vector3.zero
		state.Position, state.Debt = root.Position, 0
		player:SetAttribute("MovementRejection", reason)
		player:SetAttribute("MovementRejectedCount", (player:GetAttribute("MovementRejectedCount") or 0) + 1)
	end
	player:SetAttribute("MovementAdmitted", accepted)
	return accepted
end
-- A client may request a slide, never its speed/duration/cooldown/position.
local folder = RS:WaitForChild("Remotes")
local remote = folder:FindFirstChild("MovementIntent") or Instance.new("RemoteEvent")
remote.Name, remote.Parent = "MovementIntent", folder
remote.OnServerEvent:Connect(function(player, action)
	if action ~= "Slide" or player:GetAttribute("DataReady") ~= true or player:GetAttribute("InventoryLocked") == true then return end
	local now, previous = os.clock(), slides[player]
	if previous and now < previous.nextTime then return end
	local character, root, humanoid = parts(player)
	if not root or not humanoid or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then return end
	if not Authority.Admit(player) then return end
	slides[player] = {untilTime = now + Config.SlideDuration + 0.2, nextTime = now + Config.SlideCooldown}
end)
game:GetService("RunService").Heartbeat:Connect(function(dt)
	elapsed += dt; if elapsed < 0.1 then return end; elapsed = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("DataReady") == true then Authority.Admit(player) end
	end
end)
Players.PlayerRemoving:Connect(function(player) states[player], slides[player] = nil, nil end)
return Authority
