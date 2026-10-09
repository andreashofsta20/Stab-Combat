local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Pathfinding = game:GetService("PathfindingService")
local RS = game:GetService("ReplicatedStorage")
local Runtime = require(script.Parent.TutorialRuntime)
local Config = require(RS.Modules.TutorialNPCConfig)
local SpawnMap = require(script.Parent.Parent.Game.SpawnMap)
local Arena = {}
Arena.__index = Arena

local function spawnParts(folder)
	local result={}
	if folder then
		for _,part in ipairs(folder:GetDescendants()) do
			if part:IsA("BasePart") then table.insert(result,part) end
		end
	end
	table.sort(result,function(a,b) return a.Name<b.Name end)
	return result
end

local function fallbackRig()
	local model=Instance.new("Model")
	local color=Color3.fromRGB(table.unpack(Config.Color))
	local function part(name,size,position)
		local p=Instance.new("Part")
		p.Name,p.Size,p.CFrame=name,size,CFrame.new(position)
		p.Color,p.Material,p.CanCollide=color,Enum.Material.SmoothPlastic,name=="Torso"
		p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
		p.Parent=model
		return p
	end
	local root=part("HumanoidRootPart",Vector3.new(2,2,1),Vector3.zero); root.Transparency=1
	local torso=part("Torso",Vector3.new(2,2,1),Vector3.zero)
	local head=part("Head",Vector3.new(2,1,1),Vector3.new(0,1.5,0)); head.Color=Color3.fromRGB(234,192,143)
	local leftArm=part("Left Arm",Vector3.new(1,2,1),Vector3.new(-1.5,0,0))
	local rightArm=part("Right Arm",Vector3.new(1,2,1),Vector3.new(1.5,0,0))
	local leftLeg=part("Left Leg",Vector3.new(1,2,1),Vector3.new(-0.5,-2,0))
	local rightLeg=part("Right Leg",Vector3.new(1,2,1),Vector3.new(0.5,-2,0))
	leftLeg.Color,rightLeg.Color=Color3.fromRGB(48,51,65),Color3.fromRGB(48,51,65)
	local function joint(name,a,b,c0,c1)
		local motor=Instance.new("Motor6D")
		motor.Name,motor.Part0,motor.Part1,motor.C0,motor.C1=name,a,b,c0,c1
		motor.Parent=a
	end
	joint("RootJoint",root,torso,CFrame.identity,CFrame.identity)
	joint("Neck",torso,head,CFrame.new(0,1,0),CFrame.new(0,-0.5,0))
	joint("Left Shoulder",torso,leftArm,CFrame.new(-1,0.5,0),CFrame.new(0.5,0.5,0))
	joint("Right Shoulder",torso,rightArm,CFrame.new(1,0.5,0),CFrame.new(-0.5,0.5,0))
	joint("Left Hip",torso,leftLeg,CFrame.new(-0.5,-1,0),CFrame.new(0,1,0))
	joint("Right Hip",torso,rightLeg,CFrame.new(0.5,-1,0),CFrame.new(0,1,0))
	local humanoid=Instance.new("Humanoid"); humanoid.Parent=model
	local animator=Instance.new("Animator"); animator.Parent=humanoid
	model.PrimaryPart=root
	return model
end

function Arena.New(player, session, config)
	local template=ServerStorage:FindFirstChild(config.MapName)
	assert(template and (template:IsA("Model") or template:IsA("Folder")),"Tutorial: add ServerStorage."..config.MapName.." map template")
	local map,folder
	local prepared,result=pcall(function()
		SpawnMap.RemoveAllMaps()
		map=template:Clone()
		assert(map,"Tutorial map must be Archivable")
		local spawns=spawnParts(map:FindFirstChild("TutorialPlayerSpawns",true) or map:FindFirstChild("Spawns",true))
		if #spawns==0 then map:Destroy(); error("Tutorial Studs map needs Spawns or TutorialPlayerSpawns BaseParts") end
		for _,child in ipairs(map:GetDescendants()) do
			if child:IsA("BaseScript") then child:Destroy() end
			if child:IsA("SpawnLocation") then child.Enabled=false end
		end
		map.Name="TutorialStuds"; map:SetAttribute("TutorialMap",true); map.Parent=workspace
		if map:IsA("Model") then map.ModelStreamingMode=Enum.ModelStreamingMode.Persistent end
		task.wait(0.2)
		folder=Instance.new("Folder"); folder.Name="TutorialBandits"; folder.Parent=workspace
		local self=setmetatable({Player=player,Session=session,Map=map,Folder=folder,Spawns=spawns,
			NPCSpawns=spawnParts(map:FindFirstChild("TutorialNPCSpawns",true)),NPCs={},Generation=0,Alive=true,
			Desired=0,Aggressive=false,LastPlacement=0},Arena)
		return self
	end)
	if not prepared then
		if folder then pcall(function() folder:Destroy() end) end
		if map then pcall(function() map:Destroy() end) end
		error(result,0)
	end
	return result
end

function Arena:_Fail(reason)
	if self.Failed or self.Destroyed then return end
	self.Failed=true
	self:Destroy()
	if self.OnFailure then self.OnFailure(reason) else warn("[Tutorial] Arena stopped: "..tostring(reason)) end
end

function Arena:_Check()
	assert(self.Alive and not self.Destroyed and self.Map.Parent and self.Folder.Parent,"Tutorial arena or Studs map is unavailable")
end

function Arena:Place(character)
	self:_Check()
	local root=character:WaitForChild("HumanoidRootPart",10)
	local hum=character:FindFirstChildOfClass("Humanoid")
	if not self.Alive or self.Player.Character~=character or not root or not hum or hum.Health<=0 then return false end
	local spawn=self.Spawns[1]
	if not spawn then return false end
	local spawnPosition = spawn.Position
	if workspace.StreamingEnabled then pcall(function() self.Player:RequestStreamAroundAsync(spawnPosition, 32) end) end
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include; params.FilterDescendantsInstances={self.Map}
	local ground=workspace:Raycast(spawnPosition + Vector3.new(0, 64, 0), Vector3.new(0, -128, 0), params)
	local destination=CFrame.new((ground and ground.Position or spawnPosition) + Vector3.new(0, Config.SpawnHeight, 0))
	if spawn:IsA("BasePart") and spawn.CFrame.LookVector.Magnitude > 0 then
		destination = CFrame.lookAt((ground and ground.Position or spawnPosition) + Vector3.new(0, Config.SpawnHeight, 0), (ground and ground.Position or spawnPosition) + spawn.CFrame.LookVector * 6)
	end
	for _=1, 25 do
		local check=workspace:Raycast(spawnPosition + Vector3.new(0, 64, 0), Vector3.new(0, -128, 0), params)
		if check then break end
		task.wait(0.05)
	end
	if not self.Alive or self.Player.Character~=character or hum.Health<=0 then return false end
	hum.Sit=false; hum.PlatformStand=false; hum.AutoRotate=true
	if hum:GetState() == Enum.HumanoidStateType.GettingUp then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
	character:PivotTo(destination); root.CFrame=destination
	root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
	self.Player:SetAttribute("ServerTeleportPosition",root.Position)
	self.Player:SetAttribute("ServerTeleportVersion",(self.Player:GetAttribute("ServerTeleportVersion") or 0)+1)
	self.LastPlacement=os.clock()
	for _,child in ipairs(character:GetChildren()) do if child:IsA("ForceField") then child:Destroy() end end
	if self.OnPlaced then self.OnPlaced(character) end
	return true
end

function Arena:ClearNPCs()
	self.Generation+=1
	for model,record in pairs(self.NPCs) do
		Runtime.RemoveTarget(model)
		if record.Died then pcall(function() record.Died:Disconnect() end) end
		pcall(function() model:Destroy() end)
	end
	table.clear(self.NPCs)
end

function Arena:SpawnNPC(index)
	if not self.Alive or not Runtime.IsActive(self.Player) then return end
	self:_Check()
	local model
	local spawned,spawnError=pcall(function()
		local template=ServerStorage:FindFirstChild(Config.TemplateName)
		model=template and template:IsA("Model") and template:Clone() or fallbackRig()
		local hum=model:FindFirstChildOfClass("Humanoid")
		local root=model:FindFirstChild("HumanoidRootPart")
		if not hum or not root or not root:IsA("BasePart") then model:Destroy(); error("TutorialNPC rig needs Humanoid and HumanoidRootPart") end
		for _,child in ipairs(model:GetDescendants()) do
			if child:IsA("BaseScript") then child:Destroy() end
			if child:IsA("BasePart") then child.Anchored=false end
		end
		model.Name=Config.Name; model.PrimaryPart=root
		model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
		hum.MaxHealth,hum.Health,hum.WalkSpeed=Config.Health,Config.Health,Config.WalkSpeed
		hum.DisplayName=Config.Name; hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOn
		hum.Sit=false; hum.PlatformStand=false; hum.AutoRotate=true
		local playerRoot=self.Player.Character and self.Player.Character:FindFirstChild("HumanoidRootPart")
		local anchorPosition=(playerRoot and playerRoot.Position) or (self.Spawns[1].Position)
		local total = math.max(1, self.Desired > 0 and self.Desired or 1)
		local direction = ((index - 1) / total) * math.pi * 2
		local orbit = 8 + math.min(index, 4) * 2
		local localOffset = Vector3.new(math.cos(direction) * orbit, 0, math.sin(direction) * orbit)
		local marker = self.NPCSpawns[((index-1)%math.max(1,#self.NPCSpawns))+1]
		local frame = marker and marker.CFrame*CFrame.new(0,Config.SpawnHeight,0)
			or CFrame.new(anchorPosition + localOffset + Vector3.new(0,Config.SpawnHeight,0))
		-- Keep all tutorial targets immediately around the player, in a readable ring,
		-- so the first objective is obvious instead of feeling hidden across the map.
		local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include; params.FilterDescendantsInstances={self.Map}
		local ground=workspace:Raycast(frame.Position+Vector3.new(0,40,0),Vector3.new(0,-120,0),params)
		if not ground then model:Destroy(); error("Tutorial NPC spawn has no Grids map floor; add TutorialNPCSpawns markers") end
		frame=CFrame.new(ground.Position+Vector3.new(0,3,0))*CFrame.Angles(0, math.atan2(localOffset.Z, localOffset.X), 0)
		hum.Sit=false; hum.PlatformStand=false; hum.AutoRotate=true
		model:PivotTo(frame); model.Parent=self.Folder
		for _,part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then pcall(function() part:SetNetworkOwner(nil) end) end
		end
		Runtime.RegisterTarget(self.Player,model)
		if self.OnTargetsChanged then self.OnTargetsChanged() end
		local record={Humanoid=hum,Root=root,Spawn=frame,LastAttack=-math.huge,PathAt=-math.huge,Index=index,Generation=self.Generation}
		self.NPCs[model]=record
		record.Died=hum.Died:Connect(function()
			Runtime.RemoveTarget(model)
			if self.OnTargetsChanged then self.OnTargetsChanged() end
			task.delay(Config.RespawnSeconds,function()
				if self.NPCs[model]~=record then return end
				self.NPCs[model]=nil; record.Died:Disconnect(); model:Destroy()
				if self.Alive and record.Generation==self.Generation and self.Desired>0 then
					local respawned,respawnError=pcall(function() self:SpawnNPC(index) end)
					if not respawned then self:_Fail(respawnError) end
				end
			end)
		end)
		local animator=hum:FindFirstChildOfClass("Animator") or Instance.new("Animator",hum)
		local animation=Instance.new("Animation"); animation.AnimationId="rbxassetid://180426354"
		pcall(function() local track=animator:LoadAnimation(animation); track.Looped=true; record.WalkTrack=track end)
		animation:Destroy()
	end)
	if not spawned then
		if model then
			Runtime.RemoveTarget(model)
			local record=self.NPCs[model]; self.NPCs[model]=nil
			if record and record.Died then pcall(function() record.Died:Disconnect() end) end
			pcall(function() model:Destroy() end)
		end
		error(spawnError,0)
	end
end

function Arena:SetLesson(step)
	self:_Check()
	self:ClearNPCs()
	self.Desired=math.clamp(step.NPCs or 0,0,Config.MaxAlive)
	self.Aggressive=step.Aggressive==true
	for index=1,self.Desired do self:SpawnNPC(index) end
	if step.Kind=="Heal" then self:PrepareHealing() end
end

function Arena:PrepareHealing()
	local char=self.Player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health>0 then hum.Health=math.max(Config.SafeHealthFloor,hum.MaxHealth-Config.PracticeDamage) end
	local food=require(script.Parent.Parent.CombatHandler.FoodService)
	food.Clear(self.Player)
	if char then food.Grant(self.Player,char) end
end

function Arena:Tick(now)
	if not self.Alive or not Runtime.IsActive(self.Player) then return end
	self:_Check()
	-- Destroyed streamed/server objects must not leave an objective without targets.
	for model,record in pairs(self.NPCs) do
		if not model.Parent or not record.Root.Parent or not record.Humanoid.Parent then
			self.NPCs[model]=nil; Runtime.RemoveTarget(model)
			if record.Died then record.Died:Disconnect() end
			model:Destroy()
			if self.Desired>0 and record.Generation==self.Generation then self:SpawnNPC(record.Index) end
		end
	end
	if not self.Aggressive then return end
	local char=self.Player.Character
	local root=char and char:FindFirstChild("HumanoidRootPart")
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health<=0 then return end
	for model,record in pairs(self.NPCs) do
		local npcHum,npcRoot=record.Humanoid,record.Root
		if npcHum.Health<=0 or not model.Parent then continue end
		local offset=root.Position-npcRoot.Position
		if (npcRoot.Position-record.Spawn.Position).Magnitude>Config.LeashDistance or npcRoot.Position.Y<workspace.FallenPartsDestroyHeight+10 then
			model:PivotTo(record.Spawn); record.Waypoints=nil
		elseif offset.Magnitude<=Config.AttackRange then
			if now-record.LastAttack>=Config.AttackCooldownSeconds and now-self.LastPlacement>=Config.SpawnProtectionSeconds then
				local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={self.Folder,char}
				if not workspace:Raycast(npcRoot.Position,offset,params) then
					record.LastAttack=now
					-- Gentle enemies teach fighting without trapping beginners in a death loop.
					hum:TakeDamage(math.max(0,math.min(Config.AttackDamage,hum.Health-Config.SafeHealthFloor)))
				end
			end
		else
			if now-record.PathAt>=2 and not record.Computing then
				record.PathAt,record.Computing=now,true
				local target=root.Position
				task.spawn(function()
					local path
					local ok,waypoints=pcall(function()
						path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true})
						path:ComputeAsync(npcRoot.Position,target)
						return path.Status==Enum.PathStatus.Success and path:GetWaypoints() or nil
					end)
					if self.Alive and self.NPCs[model]==record and record.Generation==self.Generation then
						record.Computing=false
						record.Waypoints=ok and waypoints or nil
						record.Waypoint=2
					end
					if path then pcall(function() path:Destroy() end) end
				end)
			end
			local point=record.Waypoints and record.Waypoints[record.Waypoint]
			if point and (point.Position-npcRoot.Position).Magnitude<4 then record.Waypoint+=1; point=record.Waypoints[record.Waypoint] end
			if point and point.Action==Enum.PathWaypointAction.Jump then npcHum.Jump=true end
			npcHum:MoveTo(point and point.Position or root.Position)
		end
		if record.WalkTrack then
			local moving=npcRoot.AssemblyLinearVelocity.Magnitude>1
			if moving and not record.WalkTrack.IsPlaying then record.WalkTrack:Play(0.15)
			elseif not moving and record.WalkTrack.IsPlaying then record.WalkTrack:Stop(0.15) end
		end
	end
end

function Arena:Destroy()
	if self.Destroyed then return end
	self.Destroyed=true
	self.Alive=false; self.Desired=0
	self:ClearNPCs()
	if self.Map then pcall(function() self.Map:Destroy() end) end
	if self.Folder then pcall(function() self.Folder:Destroy() end) end
end
return Arena
