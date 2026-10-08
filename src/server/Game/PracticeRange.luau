-- Separate session-only targets. Practice never joins MainGame or touches
-- profiles, rewards, quests, leaderboards, win streaks or round history.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local Math = require(RS.Modules.RevolverMath)
local Revolver = require(RS.Modules.RevolverConfig)
local Knife = require(RS.Modules.KnifeConfig)
local sessions, cooldowns = {}, {}
local Range = {}
local remote = RS.Remotes:FindFirstChild("Practice") or Instance.new("RemoteEvent")
remote.Name, remote.Parent = "Practice", RS.Remotes
local arenas = Instance.new("Folder"); arenas.Name, arenas.Parent = "PracticeRanges", workspace
local lanes = {}
local function teleport(player, frame)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	root.CFrame, root.AssemblyLinearVelocity = frame, Vector3.zero
	player:SetAttribute("ServerTeleportPosition", root.Position)
	player:SetAttribute("ServerTeleportVersion", (player:GetAttribute("ServerTeleportVersion") or 0) + 1)
end
local function clearTool(player)
	for _, container in ipairs({player.Character, player:FindFirstChildOfClass("Backpack")}) do
		for _, tool in ipairs(container:GetChildren()) do if tool:IsA("Tool") then tool:Destroy() end end
	end
end
local function update(player, session, message)
	remote:FireClient(player, {Hits = session.hits, Attempts = session.attempts, Ammo = session.ammo, Message = message})
end
local function equip(player, session, category)
	local templates = category == "Knife" and SS:FindFirstChild("Knives") or SS:FindFirstChild("Revolvers")
	local template = templates and templates:FindFirstChild(category == "Knife" and "Bowie" or "Normal Revolver")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not template or not humanoid then return end
	clearTool(player)
	local tool = template:Clone()
	for _, item in ipairs(tool:GetDescendants()) do
		if item:IsA("BaseScript") then item:Destroy()
		elseif item:IsA("BasePart") then item.Anchored, item.CanCollide, item.Massless = false, false, true end
	end
	tool.CanBeDropped, tool.Parent = false, player:FindFirstChildOfClass("Backpack")
	humanoid:EquipTool(tool); session.tool, session.category = tool, category
end
function Range.Exit(player, returnToLobby)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil
	lanes[session.lane] = nil
	player:SetAttribute("PracticeActive", false)
	session.characterConnection:Disconnect(); session.deathConnection:Disconnect()
	session.folder:Destroy()
	if player.Character then clearTool(player) end
	if returnToLobby then teleport(player, session.returnFrame) end
end
function Range.Enter(player)
	local Main = require(script.Parent.MainGame)
	if sessions[player] or player:GetAttribute("DataReady") ~= true or player:GetAttribute("InventoryLocked") == true
		or player:GetAttribute("InRound") == true or Main.IsLobbyModeLocked() then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return false end
	local lane
	for index = 1,64 do if not lanes[index] then lane = index; break end end
	if not lane then return false end
	lanes[lane] = true
	local center = Vector3.new(lane * 160, -500, 0)
	local folder = Instance.new("Folder"); folder.Name, folder.Parent = tostring(player.UserId), arenas
	local function part(name, position, size, color)
		local p = Instance.new("Part"); p.Name, p.Anchored, p.Size, p.Position, p.Color, p.Parent = name, true, size, position, color, folder
		return p
	end
	part("Floor", center, Vector3.new(110,2,120), Color3.fromRGB(35,40,50))
	part("Backstop", center + Vector3.new(0,15,-59), Vector3.new(110,30,2), Color3.fromRGB(45,50,65))
	local targets = {}
	for index, distance in ipairs({12,35,70}) do
		local target = part("Target" .. index, center + Vector3.new((index-2)*16,5,40-distance), Vector3.new(5,7,1), Color3.fromRGB(235,105,65))
		targets[target] = 100; target:SetAttribute("PracticeHealth",100)
	end
	local session = {folder=folder, lane=lane, returnFrame=root.CFrame, targets=targets, hits=0, attempts=0, ammo=Revolver.Capacity, nextShot=0, reloadUntil=0, center=center}
	sessions[player] = session
	session.characterConnection = player.CharacterRemoving:Connect(function() Range.Exit(player,false) end)
	session.deathConnection = hum.Died:Connect(function() Range.Exit(player,false) end)
	player:SetAttribute("PracticeActive",true)
	teleport(player, CFrame.new(center + Vector3.new(0,5,48)))
	equip(player,session,"Revolver"); update(player,session,"Aim at the orange targets. Practice gives no rewards.")
	return true
end
function Range.Action(player, action, origin, direction)
	if action == "Exit" then Range.Exit(player,true); return end
	local session = sessions[player]
	if not session or player:GetAttribute("DataReady") ~= true or player:GetAttribute("InventoryLocked") == true then return end
	local now = os.clock()
	local head = player.Character and player.Character:FindFirstChild("Head")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not head or not hum or hum.Health <= 0 then return end
	if action == "EquipKnife" or action == "EquipRevolver" then
		if now < session.nextShot then return end
		session.nextShot = now+0.2
		equip(player,session,action == "EquipKnife" and "Knife" or "Revolver"); return
	end
	local tuning = Revolver.Get("Normal Revolver")
	if session.reloadUntil > 0 and now >= session.reloadUntil then session.ammo, session.reloadUntil = Revolver.Capacity, 0 end
	if action == "Reload" then
		if session.reloadUntil == 0 and session.ammo < Revolver.Capacity then session.reloadUntil = now+tuning.ReloadDurationMs/1000; update(player,session,"Reloading") end
		return
	end
	if action ~= "Fire" and action ~= "Throw" and action ~= "Stab" or now < session.nextShot or session.reloadUntil > 0 then return end
	if not session.tool or session.tool.Parent ~= player.Character then update(player,session,"Select a practice weapon"); return end
	if action == "Fire" and session.category ~= "Revolver" or action ~= "Fire" and session.category ~= "Knife" then return end
	if not Math.IsFiniteVector(origin,1e6) or not Math.IsFiniteVector(direction,2) or direction.Magnitude < .99 or direction.Magnitude > 1.01
		or (origin-head.Position).Magnitude > Revolver.Security.MaxCameraDistance then return end
	if not require(script.Parent.Parent.CombatHandler.MovementAuthority).Admit(player) then return end
	if action == "Fire" and session.ammo <= 0 then update(player,session,"Press R to reload"); return end
	local distance = action == "Stab" and Knife.Stab.Range or 350
	local damage = action == "Fire" and tuning.Damage or action == "Stab" and Knife.Stab.Damage or 100
	session.nextShot = now + (action == "Fire" and tuning.FireIntervalMs/1000 or action == "Stab" and Knife.Stab.Cooldown or .5)
	if action == "Fire" then session.ammo -= 1 end
	session.attempts += 1
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(head.Position,direction.Unit*distance,params)
	local target = hit and hit.Instance
	if session.targets[target] then
		session.hits += 1
		session.targets[target] = math.max(0,session.targets[target]-damage)
		target:SetAttribute("PracticeHealth",session.targets[target])
		if session.targets[target] == 0 then
			target.Color = Color3.fromRGB(80,220,120)
			task.delay(1,function()
				if sessions[player] ~= session or not target.Parent then return end
				session.targets[target] = 100; target:SetAttribute("PracticeHealth",100); target.Color = Color3.fromRGB(235,105,65)
			end)
		end
	end
	update(player,session,target and session.targets[target] and "Hit" or "Miss")
end
remote.OnServerEvent:Connect(function(player,action,origin,direction)
	if type(action) ~= "string" then return end
	local now = os.clock()
	if now - (cooldowns[player] or -math.huge) < .1 then return end
	cooldowns[player] = now
	if action == "Enter" then Range.Enter(player) else Range.Action(player,action,origin,direction) end
end)
Players.PlayerRemoving:Connect(function(player) Range.Exit(player,false); cooldowns[player] = nil end)
return Range
