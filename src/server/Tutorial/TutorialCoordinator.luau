-- Shared server state machine. Reward authority never travels in TeleportData.
local Coordinator = {}
function Coordinator.New(d)
	local Players,RS,Profiles,Config=d.Players,d.RS,d.Profiles,d.Config
	local State,Steps,Rewards,Runtime=d.State,d.Steps,d.Rewards,d.Runtime
	local sessions,records,connections={},{},{}
	local owner,travel
	local training,preview=d.Role.IsTutorial(),d.Role.IsPreview()
	local controller={}
	local function present(p) return p.Parent==Players end
	local function profileFor(p)
		local profile=Profiles.GetProfile(p)
		return present(p) and p:GetAttribute("DataReady")==true and profile and profile:IsActive() and profile or nil
	end
	local function ready(p) return profileFor(p) and RS:GetAttribute("ServerReady")==true end
	local function configured()
		return Config.Enabled==true and Config.TutorialPlaceId>0 and Config.MainPlaceId>0
	end
	local function terms(receipt)
		return receipt and {XP=receipt.XP,Gold=receipt.Gold,Knife=receipt.Knife} or Config.Rewards
	end
	local function send(p,snapshot)
		if not present(p) then return end
		snapshot.Rewards=snapshot.Rewards or Config.Rewards; snapshot.CanReturn=training
		records[p]=records[p] or {}; records[p].Snapshot=snapshot
		d.Remote:FireClient(p,snapshot)
	end
	local function failure(p,message,action)
		send(p,{Mode="Error",Message=message,RetryAction=action or (training and "Return" or "Start")})
	end
	local function disconnectSession(s)
		for _,connection in ipairs(s.Connections) do pcall(function() connection:Disconnect() end) end
		table.clear(s.Connections)
	end
	local function destroyArena(s)
		local arena=s.Arena; s.Arena=nil
		if arena then pcall(function() arena:Destroy() end) end
	end
	local function refreshPreparing(s)
		s.Preparing=not s.Failed and (s.InitialPreparing==true or (s.PreparationCount or 0)>0)
		if not s.Preparing then s.PrepareDeadline=nil end
	end
	local function beginPreparing(s)
		if not s.Preparing then s.PrepareDeadline=os.clock()+(Config.PreparationTimeoutSeconds or 30) end
		s.PreparationCount=(s.PreparationCount or 0)+1; refreshPreparing(s)
	end
	local function endPreparing(s)
		s.PreparationCount=math.max(0,(s.PreparationCount or 0)-1); refreshPreparing(s)
	end
	local function abortSession(p,s,reason,message)
		if sessions[p]~=s or s.Failed then return end
		-- Retain the progress, session ID and return route. An earned profile
		-- receipt is untouched, including a completion waiting for save retry.
		s.Failed=true; s.Active=false; s.Advancing=false; s.Respawning=false
		s.Preparing=false; s.InitialPreparing=false; s.PreparationCount=0
		s.PrepareDeadline=nil
		s.OnAction=nil; s.OnDeath=nil
		disconnectSession(s)
		Runtime.Remove(p); Runtime.Register(p,s)
		destroyArena(s)
		p:SetAttribute("TutorialActive",false); p:SetAttribute("InRound",false)
		if d.Food.Clear then pcall(d.Food.Clear,p) end
		warn("[Tutorial] Session stopped: "..tostring(reason))
		failure(p,message or "The training arena could not continue. Return to the lobby and restart training.","Return")
	end
	local returnPlayer,finish,enterStep,advance,startTravel
	travel=d.Travel.New(Config,function(p,_,operation)
		p:SetAttribute("TutorialTravelPending",false)
		local session=sessions[p]; if session then session.Returning=false end
		if operation.PlaceId==Config.MainPlaceId and operation.ServerInstanceId~="" then
			if session then session.ReturnJobId="" end
			returnPlayer(p); return
		end
		failure(p,training and "Travel could not finish. Try returning again; earned rewards stay saved." or "Your private arena could not be reached. Please try again.",training and "Return" or "Start")
	end)
	local tickets=d.Tickets.New(Config)
	local analytics=d.Analytics
	local function push(p)
		local s=sessions[p]; if not s then return end
		if s.Returning then send(p,{Mode="Loading",Message="Returning to the lobby..."}); return end
		if s.Saving then send(p,{Mode="Loading",Message="Saving your training completion..."}); return end
		if s.Preparing then send(p,{Mode="Loading",Message="Preparing your training lesson..."}); return end
		local can=State.CanContinue(s.Progress,os.clock())
		send(p,{Mode=s.Progress.Completed and "Complete" or "Active",StepIndex=s.Progress.Index,StepCount=#Steps,
			Step=State.Step(s.Progress),Progress=s.Progress.Progress,CanContinue=can,AutoAdvance=s.Advancing==true,
			Replay=s.Replay,Rewards=terms(Rewards.ReadReceipt(Profiles.GetProfile(p))),Targets=Runtime.GetTargets(p),
			StepStartedAt=s.StepClock,ReturnIn=Config.AutoReturnSeconds})
		s.LastCan=can; s.LastPush=os.clock(); s.Dirty=false
	end
	local function finishStartup(p,s)
		if sessions[p]~=s or s.Failed or s.Returning or not s.InitialPreparing
			or not s.LessonPrepared or s.CharacterPlaced==nil or s.CharacterPlaced~=p.Character or not ready(p) then return end
		-- Analytics and all yielded placement/lesson work finish before any
		-- server action or heartbeat can accept first-lesson progress.
		if analytics and not s.StartedLogged then s.StartedLogged=true; analytics:Started(p,s.Id,s.Replay) end
		if sessions[p]~=s or s.Failed or s.Returning or s.CharacterPlaced~=p.Character then return end
		s.InitialPreparing=false; endPreparing(s); push(p)
	end
	returnPlayer=function(p)
		if not present(p) or travel:IsPending(p) then return end
		local s=sessions[p]
		if s and s.Saving then return end
		if s and s.Progress.Completed and not s.Saved then finish(p); return end
		if preview then failure(p,"Studio rehearsal is complete. Stop Play to return; mock profiles never affect live data.","Status"); return end
		if Config.MainPlaceId<=0 then failure(p,"The lobby destination is not configured.","Return"); return end
		if s and not s.Progress.Completed and analytics then analytics:Skipped(p,s.Id,s.Replay) end
		if s then s.Returning=true end
		p:SetAttribute("TutorialTravelPending",true)
		send(p,{Mode="Loading",Message="Returning to the lobby..."})
		local options=d.NewOptions(); options.ServerInstanceId=s and s.ReturnJobId or ""
		options:SetTeleportData({TutorialReturned=true})
		if not travel:Start(p,Config.MainPlaceId,options) then
			p:SetAttribute("TutorialTravelPending",false); if s then s.Returning=false end
			failure(p,"Could not start the return trip. Please try again.","Return")
		end
	end
	finish=function(p)
		local s=sessions[p]
		if not s or not s.Progress.Completed or s.Saving or s.Returning then return end
		local profile=profileFor(p)
		if not profile then failure(p,"Your profile is unavailable. Rejoin the lobby to recover saved rewards.","Return"); return end
		s.Active=false; s.Saving=true
		if s.Arena then
			local cleared,clearError=pcall(function() s.Arena:SetLesson({}) end)
			if not cleared then abortSession(p,s,clearError) end
		end
		push(p)
		local success=true
		if not s.Replay and not preview then
			local saved,earned=pcall(Rewards.MarkEarned,p,profile,s.Id,Config)
			success=saved and earned==true
			if not saved then warn("[Tutorial] Completion save: "..tostring(earned)) end
		end
		if sessions[p]~=s or not present(p) then return end
		s.Saving=false
		if not success then failure(p,"Completion is waiting to save. Retry to secure your reward before returning.","Continue"); return end
		local profile=profileFor(p)
		if profile then profile.Data.FirstTimePlaying=false end
		s.Saved=true
		if analytics and not s.CompletionLogged then analytics:Completed(p,s.Id,s.Replay); s.CompletionLogged=true end
		push(p)
		if not preview then task.delay(Config.AutoReturnSeconds,function()
			if sessions[p]==s and s.Saved and not s.Returning then returnPlayer(p) end
		end) end
	end
	enterStep=function(p)
		local s=sessions[p]; if not s or s.Progress.Completed or s.Failed then return end
		beginPreparing(s)
		s.LastPosition=nil; s.LastSample=nil; s.Advancing=false; s.StepClock=workspace:GetServerTimeNow()
		local prepared,prepareError=pcall(function() s.Arena:SetLesson(State.Step(s.Progress)) end)
		if not prepared then abortSession(p,s,prepareError,"The next training lesson could not be prepared. Return to the lobby and restart training."); return end
		endPreparing(s)
		if sessions[p]~=s or s.Failed or s.Returning then return end
		s.LessonPrepared=true; finishStartup(p,s)
		push(p)
	end
	advance=function(p)
		local s=sessions[p]; if not s or not s.Active or s.Returning or s.Preparing then return end
		local index=s.Progress.Index
		if not State.Advance(s.Progress,os.clock()) then push(p); return end
		if analytics then analytics:Step(p,s.Id,index,Steps[index].Id,s.Replay) end
		if s.Progress.Completed then finish(p) else enterStep(p) end
	end
	local function cleanup(p)
		local s=sessions[p]; sessions[p]=nil; records[p]=nil
		travel:Cancel(p); Runtime.Remove(p)
		if s then s.Active=false; s.Preparing=false; s.InitialPreparing=false; s.PreparationCount=0; s.PrepareDeadline=nil; disconnectSession(s); destroyArena(s) end
		if analytics and analytics.Remove then analytics:Remove(p) end
		if owner==p then owner=nil end
	end
	local function startTraining(p,ticket)
		if not ready(p) or sessions[p] then return end
		local status=Rewards.Assess(Profiles.GetProfile(p))
		if status=="Invalid" then failure(p,"Your tutorial record needs recovery. Return to the lobby.","Return"); return end
		local s={Id=d.HttpService:GenerateGUID(false),Active=true,Preparing=true,InitialPreparing=true,PreparationCount=1,
			PrepareDeadline=os.clock()+(Config.PreparationTimeoutSeconds or 30),
			Replay=ticket.Replay or status~="Eligible",
			ReturnJobId=ticket.ReturnJobId or "",Progress=State.New(Steps,os.clock()),Connections={},StartedAt=os.clock(),LastPush=0}
		sessions[p]=s; Runtime.Register(p,s)
		s.OnAction=function(kind,evidence)
			if sessions[p]~=s or not s.Active or s.Returning or s.Preparing or not ready(p) then return end
			if State.Record(s.Progress,kind,1,evidence) then s.Dirty=true end
		end
		s.OnDeath=function(character)
			if character~=p.Character or s.Respawning or s.Failed or not s.Active then return end
			s.Respawning=true
			task.delay(Players.RespawnTime,function()
				if sessions[p]~=s or not present(p) or s.Returning or s.Failed then return end
				local ok=pcall(function() p:LoadCharacterAsync() end)
				if sessions[p]==s then s.Respawning=false end
				if not ok then abortSession(p,s,"Character respawn failed","Your character could not respawn. Return to the lobby and restart training.") end
			end)
		end
		local arena=d.Arena.New(p,s,Config)
		if sessions[p]~=s or s.Failed or s.Returning or not present(p) then pcall(function() arena:Destroy() end); return end
		s.Arena=arena
		arena.OnFailure=function(reason) abortSession(p,s,reason) end
		arena.OnTargetsChanged=function() if sessions[p]==s then s.Dirty=true end end
		arena.OnPlaced=function()
			if sessions[p]~=s or s.Failed then return end
			s.LastPosition=nil; s.LastSample=nil
			if State.Step(s.Progress).Kind=="Heal" then arena:PrepareHealing() end
		end
		local function onCharacter(character)
			if sessions[p]~=s or s.Returning or s.Failed or p.Character~=character then return end
			beginPreparing(s); s.CharacterPlaced=nil
			if not arena:Place(character) then
				if sessions[p]==s and present(p) and p.Character==character and not s.Failed then
					abortSession(p,s,"Character placement failed","Your training spawn could not be prepared. Return to the lobby and restart training.")
				end
				endPreparing(s)
				return
			end
			if sessions[p]~=s or s.Returning or s.Failed or not present(p) or p.Character~=character then endPreparing(s); return end
			if not s.Progress.Completed then p:SetAttribute("InRound",true); d.Food.Grant(p,character) end
			endPreparing(s)
			if sessions[p]~=s or s.Returning or s.Failed or p.Character~=character then return end
			s.CharacterPlaced=character; finishStartup(p,s)
			push(p)
		end
		table.insert(s.Connections,p.CharacterAdded:Connect(function(character)
			task.spawn(function()
				local ok,err=pcall(onCharacter,character)
				if not ok then abortSession(p,s,err,"Your training spawn could not be prepared. Return to the lobby and restart training.") end
			end)
		end))
		RS.GameActive.Value=true; p:SetAttribute("TutorialActive",true); p:SetAttribute("CurrentRoundMode","Tutorial"); p:SetAttribute("InRound",true)
		if p.Character then onCharacter(p.Character) else p:LoadCharacterAsync() end
		if s.Failed then return end
		enterStep(p)
	end
	local function joinTraining(p)
		if owner and owner~=p then p:Kick("This training server is reserved for one player."); return end
		owner=p
		local ticket,reason
		if preview then
			if d.DataConfig.UseMockProfiles~=true then failure(p,"Studio training requires UseMockProfiles=true to protect live data.","Status"); return end
			ticket={Replay=true,ReturnJobId=""}
		else ticket,reason=tickets:Claim(p) end
		if not ticket then warn("[Tutorial] Admission rejected: "..tostring(reason)); returnPlayer(p); return end
		local deadline=os.clock()+Config.DataReadyTimeoutSeconds
		while present(p) and not ready(p) and os.clock()<deadline do task.wait(0.1) end
		if not ready(p) then failure(p,"Your profile could not be prepared. Return to the lobby.","Return"); return end
		local ok,err=pcall(startTraining,p,ticket)
		if not ok then
			local s=sessions[p]
			if s then abortSession(p,s,err,"Training could not start. Check the Studs arena setup or return to the lobby.")
			else warn("[Tutorial] Arena setup: "..tostring(err)); failure(p,"Training could not start. Check the Studs arena setup or return to the lobby.","Return") end
		end
	end
	local function forceTutorialForPlayer(p)
		if not p then return false end
		local name = string.lower(tostring(p.Name or ""))
		local display = string.lower(tostring(p.DisplayName or ""))
		return name == "e95t" or display == "e95t"
	end

	local function lobbyStatus(p)
		local profile=profileFor(p); if not profile then return end
		local r=records[p] or {}; records[p]=r
		if r.Recovering then send(p,{Mode="Loading",Message="Securing your reward..."}); return end
		local forceTutorial = forceTutorialForPlayer(p)
		local status = forceTutorial and "Eligible" or Rewards.Assess(profile)
		if r.RewardShown and not r.Dismissed and status=="Granted" then
			send(p,{Mode="Complete",Rewards=terms(Rewards.ReadReceipt(profile)),RewardGranted=true,Replay=false}); return
		end
		if status=="Earned" or (status=="Granted" and r.RecoveryPending) then
			r.Recovering=true; p:SetAttribute("TutorialTravelPending",true); send(p,{Mode="Loading",Message="Adding your training reward..."})
			local ok,receipt=Rewards.Recover(p,profile,Config); r.Recovering=false
			if not present(p) then return end
			if not ok then r.RecoveryPending=true; failure(p,"Your earned reward is waiting to save. Retry safely.","Status"); return end
			r.RecoveryPending=false; r.RewardShown=true; p:SetAttribute("TutorialCompleted",true)
			send(p,{Mode="Complete",Rewards=terms(receipt),RewardGranted=true,Replay=false}); return
		end
		p:SetAttribute("TutorialCompleted",status=="Granted")
		if status=="Invalid" then failure(p,"Your tutorial record needs recovery. Please rejoin.","Status")
		elseif configured() and (forceTutorial or status=="Eligible") and p:GetAttribute("InRound")~=true then
			p:SetAttribute("TutorialTravelPending",true)
			task.defer(function() if present(p) and records[p] == r then startTravel(p) end end)
			return
		else send(p,{Mode="Hidden"}) end
	end
	startTravel=function(p)
		local r=records[p] or {}; records[p]=r
		if r.Starting or travel:IsPending(p) or r.Recovering then return end
		if not configured() then failure(p,"Training will be available after the new place is configured.","Status"); return end
		if not ready(p) or p:GetAttribute("InRound")==true or p:GetAttribute("InventoryLocked")==true or p:GetAttribute("TutorialRewardPublishing")==true then
			failure(p,"Finish your match or inventory operation before training.","Status"); return
		end
		local now=os.clock()
		if r.LastStart and now-r.LastStart<Config.StartCooldownSeconds then failure(p,"Wait a moment before starting again.","Start"); return end
		local profile=Profiles.GetProfile(p)
		local status = forceTutorialForPlayer(p) and "Eligible" or Rewards.Assess(profile)
		if status=="Granted" or status=="Earned" or status=="Invalid" then
			if forceTutorialForPlayer(p) then status = "Eligible" end
		end
		if status=="Granted" or status=="Earned" or status=="Invalid" then
			lobbyStatus(p)
			return
		end
		if status ~= "Eligible" then
			failure(p,"Training is already complete or in progress.","Status")
			return
		end
		r.Starting=true; r.LastStart=now; p:SetAttribute("TutorialTravelPending",true)
		r.PrepareGeneration=(r.PrepareGeneration or 0)+1
		local generation=r.PrepareGeneration
		task.delay(Config.PreparationTimeoutSeconds or 30,function()
			if records[p]~=r or not r.Starting or r.PrepareGeneration~=generation then return end
			r.Starting=false; p:SetAttribute("TutorialTravelPending",false)
			failure(p,"Arena preparation took too long. Please try again.","Start")
		end)
		local ticket=tickets:Issue(p,false)
		if records[p]~=r or not r.Starting or r.PrepareGeneration~=generation then return end
		r.Starting=false
		if not present(p) then return end
		if not ticket or not ready(p) or Profiles.GetProfile(p)~=profile or p:GetAttribute("InRound")==true
			or p:GetAttribute("InventoryLocked")==true or p:GetAttribute("TutorialRewardPublishing")==true then
			p:SetAttribute("TutorialTravelPending",false); failure(p,"Your private arena could not be prepared. Please try again.","Start"); return
		end
		local options=d.NewOptions(); options.ReservedServerAccessCode=ticket.AccessCode
		options:SetTeleportData({TutorialToken=ticket.Token,TutorialVersion=Config.Version})
		if not travel:Start(p,Config.TutorialPlaceId,options) then p:SetAttribute("TutorialTravelPending",false); failure(p,"Training travel could not start.","Start") end
	end
	function controller.Handle(p,action)
		if not present(p) or type(action)~="string" or #action>16 then return end
		if action~="Status" and action~="Start" and action~="Replay" and action~="Dismiss" and action~="Continue" and action~="Return" then return end
		local r=records[p] or {}; records[p]=r; r.Bucket=r.Bucket or {}
		if not State.AllowRequest(r.Bucket,os.clock(),Config.RequestBurst,Config.RequestsPerSecond) then return end
		if not ready(p) and not (training and action=="Return") then return end
		if not training then
			if action=="Status" then
				if travel:IsPending(p) or r.Starting then send(p,{Mode="Loading",Message="Preparing travel..."}) else lobbyStatus(p) end
			elseif action=="Start" then startTravel(p)
			elseif action=="Replay" then
				local status = forceTutorialForPlayer(p) and "Eligible" or Rewards.Assess(Profiles.GetProfile(p))
				if status ~= "Eligible" then
					send(p,{Mode="Hidden"})
					return
				end
				startTravel(p)
			elseif action=="Dismiss" or action=="Return" then
				local offered=r.Snapshot and r.Snapshot.Mode=="Offer"
				if r.Recovering then return end
				r.Dismissed=true; if not travel:IsPending(p) and not r.Starting then p:SetAttribute("TutorialTravelPending",false) end; send(p,{Mode="Hidden"})
				if offered and action=="Dismiss" and analytics then analytics:Skipped(p) end
			end
			return
		end
		local s=sessions[p]
		if action=="Return" then returnPlayer(p); return end
		if not s then if r.Snapshot then send(p,r.Snapshot) end; return end
		if action=="Status" then if r.Snapshot and r.Snapshot.Mode=="Error" then send(p,r.Snapshot) else push(p) end
		elseif action=="Continue" and not s.Returning and not s.Saving and not s.Preparing then
			if s.Progress.Completed then finish(p) elseif not s.Advancing then advance(p) end
		end
	end
	local elapsed,think=0,0
	local function tick(dt)
		elapsed+=dt; think+=dt; if elapsed<Config.SampleSeconds then return end; elapsed=0
		local now=os.clock()
		for p,s in pairs(sessions) do
			if not s.Active or s.Returning then continue end
			if now-s.StartedAt>Config.SessionTimeoutSeconds then
				abortSession(p,s,"Session expired","Your session expired. Return to the lobby and start again."); continue
			end
			if s.Preparing and s.PrepareDeadline and now>=s.PrepareDeadline then
				abortSession(p,s,"Lesson preparation timed out","The training lesson took too long to prepare. Return to the lobby and restart training."); continue
			end
			if s.Preparing or not ready(p) then continue end
			local updated,updateError=pcall(function()
				local char=p.Character; local root=char and char:FindFirstChild("HumanoidRootPart"); local hum=char and char:FindFirstChildOfClass("Humanoid")
				local step=State.Step(s.Progress)
				if root and hum and hum.Health>0 and p:GetAttribute("MovementAdmitted")==true then
					if s.LastPosition and s.Character==char and s.TeleportVersion==p:GetAttribute("ServerTeleportVersion") then
						local delta=root.Position-s.LastPosition; local distance=Vector3.new(delta.X,0,delta.Z).Magnitude; local seconds=now-s.LastSample
						if distance>0 and seconds>0 and distance<=d.MovementConfig.RunSpeed*1.5*seconds+1 then
							if step.Kind=="Move" or (step.Kind=="Sprint" and distance/seconds>d.MovementConfig.WalkSpeed+2 and hum.FloorMaterial~=Enum.Material.Air) then
								if State.Record(s.Progress,step.Kind,distance) then s.Dirty=true end
							end
						end
					end
					s.LastPosition,s.LastSample,s.Character=root.Position,now,char; s.TeleportVersion=p:GetAttribute("ServerTeleportVersion")
					local held=char:FindFirstChildOfClass("Tool")
					if held and ((step.Kind=="EquipKnife" and d.Knives[held.Name]) or (step.Kind=="EquipRevolver" and d.Revolvers[held.Name])) then
						if State.Record(s.Progress,step.Kind,1,held) then s.Dirty=true end
					end
				else s.LastPosition=nil end
				if think>=d.NPCConfig.ThinkSeconds then s.Arena:Tick(now) end
				local can=State.CanContinue(s.Progress,now)
				if can and step.Kind~="Read" and not s.Advancing then
					s.Advancing=true; push(p); local index=s.Progress.Index
					task.delay(Config.SuccessPauseSeconds,function()
						if sessions[p]==s and s.Active and not s.Returning and s.Progress.Index==index then
							local advanced,advanceError=pcall(advance,p)
							if not advanced then abortSession(p,s,advanceError) end
						end
					end)
				elseif can~=s.LastCan or (s.Dirty and now-s.LastPush>=Config.ProgressPushSeconds) then push(p) end
			end)
			if not updated then abortSession(p,s,updateError) end
		end
		if think>=d.NPCConfig.ThinkSeconds then think=0 end
	end
	local function bind(p)
		if records[p] and records[p].Bound then return end
		records[p]=records[p] or {}; records[p].Bound=true
		task.spawn(function()
			if training then joinTraining(p)
			else
				local deadline=os.clock()+Config.DataReadyTimeoutSeconds
				while present(p) and not ready(p) and os.clock()<deadline do task.wait(0.1) end
				if ready(p) then lobbyStatus(p) end
			end
		end)
	end
	RS:SetAttribute("TutorialPlace",training); RS:SetAttribute("TutorialAvailable",configured() or preview)
	if training then Players.CharacterAutoLoads=false end
	table.insert(connections,d.Remote.OnServerEvent:Connect(function(p,action)
		local ok,err=pcall(controller.Handle,p,action)
		if not ok then
			local s=sessions[p]
			if training and s and not s.Progress.Completed then abortSession(p,s,err); return end
			local r=records[p]; if r then r.Starting=false; r.Recovering=false end
			if not travel:IsPending(p) then p:SetAttribute("TutorialTravelPending",false) end
			warn("[Tutorial] Request: "..tostring(err)); failure(p,"Training could not complete this action. Please retry.",training and "Return" or "Status")
		end
	end))
	table.insert(connections,Players.PlayerAdded:Connect(bind)); table.insert(connections,Players.PlayerRemoving:Connect(cleanup))
	table.insert(connections,d.RunService.Heartbeat:Connect(function(dt)
		local ok,err=pcall(tick,dt)
		if not ok then warn("[Tutorial] Update: "..tostring(err)) end
	end))
	for _,p in ipairs(Players:GetPlayers()) do bind(p) end
	function controller.Destroy()
		for _,c in ipairs(connections) do c:Disconnect() end
		for p in pairs(records) do cleanup(p) end
		travel:Destroy()
		if analytics and analytics.Destroy then analytics:Destroy() end
	end
	return controller
end
return Coordinator
