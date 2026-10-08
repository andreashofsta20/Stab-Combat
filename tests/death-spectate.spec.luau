-- Production camera/controller code with deterministic scheduling and ownership.
local Vector, vm = {}, {}
function Vector.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vm) end
vm.__index=function(v,key)
	if key=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
	if key=="Unit" then return Vector.new(v.X/v.Magnitude,v.Y/v.Magnitude,v.Z/v.Magnitude) end
end
vm.__add=function(a,b) return Vector.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return Vector.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__unm=function(a) return Vector.new(-a.X,-a.Y,-a.Z) end
vm.__mul=function(a,b) return Vector.new(a.X*b,a.Y*b,a.Z*b) end
local Frame, fm = {}, {}
function Frame.new(x,y,z) return setmetatable({Position=type(x)=="table" and x or Vector.new(x,y,z),LookVector=Vector.new(0,0,-1)},fm) end
function Frame.lookAt(point,focus) local f=Frame.new(point); f.LookVector=(focus-point).Unit; return f end
function Frame:Lerp(other,alpha) local f=Frame.new(self.Position+(other.Position-self.Position)*alpha); f.LookVector=other.LookVector; return f end
fm.__index=Frame
fm.__eq=function(a,b) return a.Position.X==b.Position.X and a.Position.Y==b.Position.Y and a.Position.Z==b.Position.Z end
fm.__add=function(a,b) local f=Frame.new(a.Position+b); f.LookVector=a.LookVector; return f end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end

return function(load)
	local passed=0
	local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); passed+=1; print("PASS "..name) end
	local function fixture()
		local f={now=0,jobs={},cancelled={},characters={},raycasts=0,paramsCreated=0}
		local function resume(thread,...)
			if f.cancelled[thread] then return end
			local ok,delay=coroutine.resume(thread,...); assert(ok,delay)
			if coroutine.status(thread)~="dead" then table.insert(f.jobs,{at=f.now+(delay or 0),thread=thread}) end
		end
		f.task={}
		function f.task.spawn(fn,...) local t=coroutine.create(fn); resume(t,...); return t end
		function f.task.delay(delay,fn) local t=coroutine.create(fn); table.insert(f.jobs,{at=f.now+delay,thread=t}); return t end
		function f.task.cancel(thread) assert(thread~=coroutine.running(),"cancelled executing task"); f.cancelled[thread]=true end
		function f.task.wait(delay) return coroutine.yield(delay or 0) end
		function f.advance(seconds)
			local target=f.now+seconds
			while true do
				table.sort(f.jobs,function(a,b) return a.at<b.at end)
				local job=f.jobs[1]; if not job or job.at>target then break end
				table.remove(f.jobs,1); f.now=job.at; resume(job.thread)
			end
			f.now=target
		end
		local function signal()
			local s={listeners={}}
			function s:Connect(fn) local c={Connected=true}; function c:Disconnect() self.Connected=false end; table.insert(self.listeners,{fn=fn,c=c}); return c end
			function s:Fire(...) for _, l in ipairs(table.clone(self.listeners)) do if l.c.Connected then f.task.spawn(l.fn,...) end end end
			function s:Count() local n=0; for _, l in ipairs(self.listeners) do if l.c.Connected then n+=1 end end; return n end
			return s
		end
		local function node(class,name,parent)
			local props={ClassName=class,Name=name,Visible=false,Health=class=="Humanoid" and 100 or nil}
			local n={children={},attributes={},signals={}}
			function n:IsA(kind) return kind==self.ClassName or kind=="BasePart" and self.ClassName=="Part" end
			function n:FindFirstChild(name) return self.children[name] end
			function n:FindFirstChildOfClass(kind) for _,c in pairs(self.children) do if c:IsA(kind) then return c end end end
			function n:GetChildren() local t={}; for _,c in pairs(self.children) do table.insert(t,c) end; return t end
			function n:WaitForChild(name)
				if not self.children[name] and f.waitHook then f.waitHook(self,name) end
				return self.children[name] or node("GuiObject",name,self)
			end
			function n:GetAttribute(name) return self.attributes[name] end
			function n:GetAttributeChangedSignal(name) self.signals[name]=self.signals[name] or signal(); return self.signals[name] end
			function n:GetPropertyChangedSignal(name) local key="Property:"..name; self.signals[key]=self.signals[key] or signal(); return self.signals[key] end
			function n:SetAttribute(name,value) local old=self.attributes[name]; self.attributes[name]=value; if old~=value then self:GetAttributeChangedSignal(name):Fire() end end
			for _,event in ipairs({"Changed","HealthChanged","CharacterAdded","CharacterRemoving","ChildAdded","ChildRemoved","Destroying","MouseEnter","MouseLeave","MouseButton1Down","MouseButton1Up","MouseButton1Click","OnClientEvent"}) do n[event]=signal() end
			function n:Destroy()
				self.Destroying:Fire(); self.Destroyed=true
				for _, child in ipairs(self:GetChildren()) do child:Destroy() end
				self.Parent=nil
			end
			setmetatable(n,{__index=function(self,key) local value=props[key]; if value~=nil then return value end; return self.children[key] end,__newindex=function(self,key,value)
				if self.onWrite then value=self.onWrite(key,value) end
				local old=props[key]; if old==value then return end
				props[key]=value
				if key=="Parent" then
					if old and old.children then old.children[self.Name]=nil; old.ChildRemoved:Fire(self) end
					if value and value.children then value.children[self.Name]=self; value.ChildAdded:Fire(self) end
				end
				self:GetPropertyChangedSignal(key):Fire()
				if key=="Value" then self.Changed:Fire(value) end
				if key=="Health" then self.HealthChanged:Fire(value) end
			end})
			n.Parent=parent
			return n
		end
		f.node=node
		local function character(name,health)
			local c=node("Model",name,{})
			local h=node("Humanoid","Humanoid",c); h.Health=health or 0
			local torso=node("Part","Torso",c); torso.Position=Vector.new(0,3,0)
			return c,h,torso
		end
		f.character,f.humanoid,f.torso=character("Victim",0)
		f.player=node("Player","Victim",{}); f.player.UserId=1; f.player.Character=f.character; f.player.CameraMode="LockFirstPerson"; f.player.attributes.InRound=true
		local gui=node("PlayerGui","PlayerGui",f.player); f.main=node("ScreenGui","Main",gui)
		f.killer=node("Player","Killer",{}); f.killer.UserId=2; f.killer.DisplayName="Killer"; f.killer.attributes.InRound=true
		f.killer.Character,f.killerHumanoid=character("Killer",100)
		f.players={LocalPlayer=f.player,PlayerAdded=signal(),PlayerRemoving=signal()}; f.player.Parent=f.players; f.killer.Parent=f.players
		f.members={f.player,f.killer}
		function f.players:GetPlayers() return table.clone(f.members) end
		function f.players:GetPlayerByUserId(id) for _,p in ipairs(f.members) do if p.UserId==id then return p end end end
		local rs=node("Folder","ReplicatedStorage",{})
		rs.Modules={SpectateConfig="Config",RagdollQuery="RagdollQuery"}
		rs.children.Modules=rs.Modules
		function rs.Modules:WaitForChild(name) return self[name] or name end
		f.active=node("BoolValue","GameActive",rs); f.active.Value=true
		f.timer=node("NumberValue","Timer",rs); f.timer.Value=60
		local remotes=node("Folder","Remotes",rs); f.remote=node("RemoteEvent","KillCam",remotes)
		f.run={RenderStepped=signal(),Heartbeat=signal()}
		f.camera=node("Camera","Camera",nil); f.camera.CFrame=Frame.new(0,5,0); f.camera.Focus=Frame.new(0,5,-.5)
		f.camera.CameraType="Custom"; f.camera.CameraSubject=f.humanoid
		f.workspace=node("Workspace","Workspace",nil); f.workspace.CurrentCamera=f.camera
		f.vr={VREnabled=false}; f.config=load("Config")
		function f.roundCameraProperties()
			-- Model engine storage: assigned CFrames are rounded before readback.
			f.camera.onWrite=function(key,value)
				if key=="CFrame" or key=="Focus" then
					local p=value.Position
					local stored=Frame.new(math.round(p.X*1e5)/1e5,math.round(p.Y*1e5)/1e5,math.round(p.Z*1e5)/1e5)
					stored.LookVector=value.LookVector; value=stored
				end
				return value
			end
		end
		function f.workspace:FindFirstChild(name) return name=="DeathRagdolls" and f.ragdollFolder or nil end
		function f.workspace:Raycast(origin,direction,params)
			f.raycasts+=1; f.lastRayParams=params; f.lastRayOrigin,f.lastRayDirection=origin,direction
			local wall=f.wall
			if not wall or params.RespectCanCollide and wall.CanCollide==false then return nil end
			for _,ignore in ipairs(params.ExcludeInstances) do
				local ancestor=wall
				while ancestor do if ancestor==ignore then return nil end; ancestor=ancestor.Parent end
			end
			if math.abs(direction.Z)<.00001 then return nil end
			local t=(wall.Position.Z-origin.Z)/direction.Z
			if t<0 or t>1 then return nil end
			return {Distance=direction.Magnitude*t,Position=origin+direction*t,Instance=wall}
		end
		function f.obstruction(z,collidable,parent)
			f.wall=node("Part","Wall",parent); f.wall.Position=Vector.new(0,3,z); f.wall.CanCollide=collidable~=false; return f.wall
		end
		local services={Players=f.players,ReplicatedStorage=rs,RunService=f.run,Workspace=f.workspace,VRService=f.vr,TweenService={},Lighting={Blur={Enabled=false}}}
		f.env={game={GetService=function(_,name) return assert(services[name],name) end},workspace=f.workspace,
			Enum={CameraType={Custom="Custom",Scriptable="Scriptable"},EasingStyle={Quad="Quad"},EasingDirection={Out="Out"}},
			Vector3=Vector,CFrame=Frame,task=f.task,os={clock=function() return f.now end},TweenInfo={new=function() return {} end},
			RaycastParams={new=function() f.paramsCreated+=1; return {} end},
			script={Parent={DeathSpectateTransition="Transition",SoundHandler="SoundHandler"}}}
		f.ragdollQuery=load("RagdollQuery",{workspace=f.workspace,script={Parent={RagdollConfig="RagdollConfig"}},require=function() return {FolderName="DeathRagdolls"} end})
		local transition=load("Transition",setmetatable({require=function(name) if name=="Config" then return f.config elseif name=="RagdollQuery" then return f.ragdollQuery end; error(name) end},{__index=f.env}))
		f.controller=transition.New(f.player)
		f.knives={Starter={Image="rbxassetid://11"},Gold={Image="rbxassetid://22"}}; f.clickSounds=0
		f.env.require=function(name)
			if name=="Transition" then return transition elseif name=="Config" then return f.config
			elseif name=="SpectateHandler" then return f.handler
			elseif name=="UITransitions" then return {BindMenus=function() end}
			elseif name=="SoundHandler" then return {PlaySound=function(name) assert(name=="ClickTopButtons"); f.clickSounds+=1 end}
			elseif name=="KnivesInfo" then return f.knives elseif name=="TimeToMinutes" then return {MakeTimeMinute=function(seconds) return string.format("%d:%02d",math.floor(seconds/60),seconds%60) end} end
			error(name)
		end
		function f.render() f.run.RenderStepped:Fire() end
		function f.heartbeat() f.run.Heartbeat:Fire() end
		function f.corpse(x)
			local c,_,t=character("Victim_Ragdoll",0); t.Position=Vector.new(x or 0,3,0)
			local ref=f.character:FindFirstChild("DeathRagdollReference") or node("ObjectValue","DeathRagdollReference",f.character); ref.Value=c
			return c,t
		end
		function f.spectate()
			f.handler=load("Spectate",f.env); f.frame=f.main.children.SpectateFrame
			f.bottom=f.frame.Bottom; f.name=f.frame.CurrentlySpectatingUser
			f.kills=f.bottom.MiddleFrame.Kills.KillsText
			f.knife=f.bottom.MiddleFrame.Inventory.KnifeEquippedFrame.Slot.KnifeImage
			f.match=f.frame.MatchStats.StatsText
			return f.handler
		end
		function f.addPlayer(id,health,inRound)
			local p=node("Player","Player"..id,nil); p.UserId=id; p.DisplayName="Player"..id
			p.attributes.InRound=inRound~=false; p.Character=character(p.Name,health or 100); p.Parent=f.players
			table.insert(f.members,p); f.players.PlayerAdded:Fire(p); return p
		end
		function f.removePlayer(p)
			f.players.PlayerRemoving:Fire(p); table.remove(f.members,assert(table.find(f.members,p))); p.Parent=nil
		end
		function f.replaceTargetCharacter(p,lateHumanoid)
			local previous=p.Character; if previous then p.CharacterRemoving:Fire(previous) end
			local c=node("Model",p.Name.."New",{}); p.Character=c; p.CharacterAdded:Fire(c)
			if not lateHumanoid then local h=node("Humanoid","Humanoid",c); h.Health=100 end
			return c
		end
		function f.connectionCount()
			local total=0
			local function count(instance)
				for _,s in pairs(instance.signals) do total+=s:Count() end
				for _,event in ipairs({"Changed","HealthChanged","CharacterAdded","CharacterRemoving","ChildAdded","ChildRemoved","Destroying","MouseEnter","MouseLeave","MouseButton1Down","MouseButton1Up","MouseButton1Click","OnClientEvent"}) do total+=instance[event]:Count() end
				for _, child in ipairs(instance:GetChildren()) do count(child) end
			end
			count(f.main); count(f.camera); count(f.workspace); count(f.active); count(f.timer); count(f.remote)
			for _,p in ipairs(f.members) do count(p); if p.Character then count(p.Character) end end
			total+=f.players.PlayerAdded:Count()+f.players.PlayerRemoving:Count()
			return total
		end
		function f.respawn()
			f.player.CharacterRemoving:Fire(f.character)
			f.character,f.humanoid,f.torso=character("Victim",100); f.player.Character=f.character
			f.camera.CameraSubject=f.humanoid; f.player.CharacterAdded:Fire(f.character)
		end
		return f
	end
	test("idle transition creates no frames connections or timers",function()
		local f=fixture(); assert(not f.controller.IsPending() and #f.jobs==0 and f.run.RenderStepped:Count()==0)
		f.controller.Cancel(); assert(f.camera.CameraType=="Custom" and f.player.CameraMode=="LockFirstPerson")
		assert(f.paramsCreated==0 and f.raycasts==0)
	end)
	test("unobstructed death pullback reuses one query parameter object only while active",function()
		local f=fixture(); local corpse=f.corpse(); f.controller.Begin(f.character,function() end)
		local params=f.lastRayParams; assert(f.paramsCreated==1 and params.RespectCanCollide and params.IgnoreWater)
		assert(table.find(params.ExcludeInstances,f.character) and table.find(params.ExcludeInstances,corpse)
			and table.find(params.ExcludeInstances,f.camera) and table.find(params.ExcludeInstances,f.killer.Character))
		f.advance(.2); for _=1,10 do f.render(); assert(f.lastRayParams==params) end
		near(f.camera.CFrame.Position.Z,6); assert(f.paramsCreated==1)
		local casts=f.raycasts; f.controller.Cancel(); f.render(); f.advance(2); assert(f.raycasts==casts)
	end)
	test("collidable wall keeps interpolated and final camera on the corpse side with padding",function()
		local f=fixture(); f.corpse(); f.obstruction(2); f.controller.Begin(f.character,function() end)
		for _=1,12 do f.advance(1/60); f.render(); assert(f.camera.CFrame.Position.Z<2) end
		local distance=(f.camera.CFrame.Position-f.camera.Focus.Position).Magnitude
		near(distance,f.lastRayDirection.Magnitude*(2/6)-f.config.DeathViewCollisionPadding)
		assert(f.camera.CFrame.Position.Z>0 and f.paramsCreated==1)
	end)
	test("noncollidable decorations and corpse camera models do not obstruct the death view",function()
		for _,parent in ipairs({"decoration","original","corpse","camera","folder"}) do
			local f=fixture(); local corpse=f.corpse(); f.ragdollFolder=f.node("Folder","DeathRagdolls",nil)
			local owner=parent=="original" and f.character or parent=="corpse" and corpse or parent=="camera" and f.camera or parent=="folder" and f.ragdollFolder or nil
			f.obstruction(2,parent~="decoration",owner); f.controller.Begin(f.character,function() end); f.advance(.2); f.render()
			near(f.camera.CFrame.Position.Z,6)
		end
	end)
	test("a very close wall relaxes minimum distance without pushing the camera through it",function()
		local f=fixture(); f.corpse(); f.obstruction(.02); f.controller.Begin(f.character,function() end); f.advance(.2); f.render()
		assert(f.camera.CFrame.Position.Z<.02); near((f.camera.CFrame.Position-f.camera.Focus.Position).Magnitude,0)
	end)
	test("late corpse reference updates only the reused obstruction filter",function()
		local f=fixture(); f.controller.Begin(f.character,function() end); local params=f.lastRayParams
		local corpse=f.corpse(); f.obstruction(2,true,corpse); f.advance(.2); f.render()
		assert(f.lastRayParams==params and f.paramsCreated==1 and table.find(params.ExcludeInstances,corpse)); near(f.camera.CFrame.Position.Z,6)
	end)
	test("own death pulls back smoothly for one second then hands native camera back",function()
		local f=fixture(); f.corpse(); local ready=0
		assert(f.controller.Begin(f.character,function() ready+=1 end)); assert(f.camera.CameraType=="Scriptable")
		local initial=f.camera.CFrame.Position.Z; assert(initial>0 and initial<6)
		f.advance(.08); f.render(); assert(f.camera.CFrame.Position.Z>initial and f.camera.CFrame.Position.Z<6)
		f.advance(.12); f.render(); near(f.camera.CFrame.Position.Z,6); near(f.camera.CFrame.Position.Y,4.75)
		assert(f.player.CameraMode=="LockFirstPerson" and ready==0)
		f.advance(.79); assert(ready==0); f.advance(.01); assert(ready==1 and f.camera.CameraType=="Custom")
		assert(f.run.RenderStepped:Count()==0 and not f.controller.IsPending())
	end)
	test("camera follows exact ragdoll torso instead of hidden original and accepts late replication",function()
		local f=fixture(); f.controller.Begin(f.character,function() end); f.advance(.2); f.render(); near(f.camera.CFrame.Position.X,0)
		local _,torso=f.corpse(4); f.render(); near(f.camera.CFrame.Position.X,4)
		torso.Position=Vector.new(7,1,0); f.render(); near(f.camera.CFrame.Position.X,7); near(f.camera.CFrame.Position.Y,2.75)
	end)
	test("cancellation releases only owned camera and prevents delayed handoff",function()
		local f=fixture(); local ready=0; f.controller.Begin(f.character,function() ready+=1 end)
		f.controller.Cancel(); f.advance(2); assert(ready==0 and f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
	end)
	test("rounded first-person camera properties retain death ownership and complete handoff",function()
		local f=fixture(); f.roundCameraProperties(); f.torso.Position=Vector.new(.1234567,3.7654321,.9876543)
		local ready=0; f.controller.Begin(f.character,function() ready+=1 end)
		for _=1,30 do f.advance(1/60); f.render(); assert(f.camera.CameraType=="Scriptable" and f.controller.IsPending()) end
		f.advance(.51); assert(ready==1 and f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
	end)
	test("respawn cancels a rounded first-person death camera without leaving Scriptable",function()
		local f=fixture(); f.spectate(); f.roundCameraProperties(); f.torso.Position=Vector.new(.1234567,3.7654321,.9876543)
		f.remote.OnClientEvent:Fire("Respawn",2,2); f.advance(.08); f.render(); f.respawn(); f.advance(2)
		assert(f.camera.CameraType=="Custom" and f.camera.CameraSubject==f.humanoid and f.run.RenderStepped:Count()==0)
	end)
	test("rounded first-person death reaches FFA killer view and BR spectator UI",function()
		for _,mode in ipairs({"Respawn","Spectate"}) do
			local f=fixture(); f.spectate(); f.roundCameraProperties(); f.torso.Position=Vector.new(.1234567,3.7654321,.9876543)
			if mode=="Spectate" then f.player:SetAttribute("InRound",false) end
			f.remote.OnClientEvent:Fire(mode,2,2); f.advance(.2); f.render(); f.advance(.8)
			assert(f.camera.CameraType=="Custom" and f.camera.CameraSubject==f.killerHumanoid and f.frame.Visible==(mode=="Spectate"))
		end
	end)
	test("initial and render collision failures return native control and still complete handoff",function()
		for _,duringRender in ipairs({false,true}) do
			local f=fixture(); local ready=0
			local function fail() error("simulated collision query failure") end
			if not duringRender then f.workspace.Raycast=fail end
			assert(f.controller.Begin(f.character,function() ready+=1 end))
			if duringRender then f.workspace.Raycast=fail; f.render() end
			assert(f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0 and f.controller.IsPending())
			f.advance(1); assert(ready==1 and not f.controller.IsPending())
		end
	end)
	test("pose-only updates cannot strand the owned death camera or cancel its handoff",function()
		local f=fixture(); local ready=0; f.controller.Begin(f.character,function() ready+=1 end)
		f.camera.CFrame=Frame.new(50,60,70); f.camera.Focus=Frame.new(20,30,40); f.render(); f.advance(2)
		assert(f.camera.CameraType=="Custom" and ready==1 and f.run.RenderStepped:Count()==0)
	end)
	test("respawn native subject reassignment releases the death camera before its next frame",function()
		local f=fixture(); f.spectate(); f.remote.OnClientEvent:Fire("Respawn",2,2)
		local newCharacter=f.node("Model","NewCharacter",{}); local newHumanoid=f.node("Humanoid","Humanoid",newCharacter); newHumanoid.Health=100
		f.player.Character=newCharacter; f.camera.CameraSubject=newHumanoid
		f.camera.CFrame=Frame.new(30,40,50); f.player.CharacterAdded:Fire(newCharacter); f.advance(2)
		assert(f.camera.CameraType=="Custom" and f.camera.CameraSubject==newHumanoid and f.run.RenderStepped:Count()==0)
	end)
	test("camera replacement and changed subject preserve other camera owner",function()
		for _,replace in ipairs({false,true}) do
			local f=fixture(); local ready=0; f.controller.Begin(f.character,function() ready+=1 end)
			if replace then f.workspace.CurrentCamera={CameraType="Scriptable",CFrame=Frame.new(99,99,99)} else f.camera.CameraSubject=f.killerHumanoid end
			f.render(); f.advance(2); assert(ready==0 and f.workspace.CurrentCamera.CameraType=="Scriptable")
		end
	end)
	test("a cleared death subject still releases Scriptable and hands off to the killer",function()
		local f=fixture(); f.spectate(); f.remote.OnClientEvent:Fire("Respawn",2,2)
		f.camera.CameraSubject=nil; f.camera.Focus=Frame.new(0,0,0); f.advance(1)
		assert(f.camera.CameraType=="Custom" and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("a revived or replaced character cannot open delayed spectator",function()
		for _,replaced in ipairs({false,true}) do
			local f=fixture(); local ready=0; f.controller.Begin(f.character,function() ready+=1 end)
			if replaced then f.player.Character=f.node("Model","NewCharacter",{}) else f.humanoid.Health=100 end
			f.render(); f.advance(2); assert(ready==0 and not f.controller.IsPending())
		end
	end)
	test("new transition cancels stale delay without removing newer timer",function()
		local f=fixture(); local first,second=0,0; f.controller.Begin(f.character,function() first+=1 end)
		f.advance(.4); f.controller.Begin(f.character,function() second+=1 end)
		f.advance(.6); assert(first==0 and second==0 and f.controller.IsPending()); f.advance(.4); assert(second==1)
	end)
	test("VR and disabled death camera retain view but still delay spectating",function()
		for _,vr in ipairs({false,true}) do
			local f=fixture(); f.vr.VREnabled=vr; f.config.DeathViewEnabled=vr; local ready=0
			f.controller.Begin(f.character,function() ready+=1 end); assert(f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
			f.advance(1); assert(ready==1)
		end
	end)
	test("living avatars foreign subjects and existing custom cameras are not taken over",function()
		for _,reason in ipairs({"living","subject","scriptable"}) do
			local f=fixture(); if reason=="living" then f.humanoid.Health=100 elseif reason=="subject" then f.camera.CameraSubject=f.killerHumanoid else f.camera.CameraType="Scriptable" end
			assert(not f.controller.Begin(f.character,function() error("unexpected handoff") end)); assert(#f.jobs==0)
		end
	end)
	test("battle royale keeps victim death visible before selecting killer",function()
		local f=fixture(); f.spectate(); f.corpse(); f.player:SetAttribute("InRound",false)
		f.remote.OnClientEvent:Fire("Spectate",2,0); assert(f.camera.CameraType=="Scriptable" and not f.frame.Visible)
		f.advance(.99); assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid)
		f.advance(.01); assert(f.frame.Visible and f.camera.CameraType=="Custom" and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("FFA waits one second while keeping original server respawn deadline",function()
		local f=fixture(); f.spectate(); f.corpse(); f.remote.OnClientEvent:Fire("Respawn",2,2)
		f.advance(.99); assert(f.camera.CameraSubject==f.humanoid and not f.frame.Visible)
		f.advance(.01); assert(f.camera.CameraSubject==f.killerHumanoid and not f.frame.Visible)
		f.advance(1); f.heartbeat(); assert(f.run.Heartbeat:Count()==0)
	end)
	test("game end new round and manual stop cancel pending automatic spectate",function()
		for _,reason in ipairs({"end","round","stop"}) do
			local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.remote.OnClientEvent:Fire("Spectate",2,0)
			f.advance(.25)
			if reason=="end" then f.active.Value=false; f.active.Changed:Fire(false)
			elseif reason=="round" then f.player:SetAttribute("InRound",true)
			elseif reason=="respawn" then f.respawn() else f.handler.StopSpectating() end
			f.advance(1); assert(not f.frame.Visible and f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
		end
	end)
	test("BR elimination attribute may replicate after the remote without skipping delay",function()
		local f=fixture(); f.spectate(); f.remote.OnClientEvent:Fire("Spectate",2,0); f.advance(1)
		assert(not f.frame.Visible); f.player:SetAttribute("InRound",false); f.advance(.1)
		assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("remote arriving before death Health replication waits without idle render work",function()
		for _,mode in ipairs({"Spectate","Respawn"}) do
			local f=fixture(); f.spectate(); f.humanoid.Health=100
			if mode=="Spectate" then f.player:SetAttribute("InRound",false) end
			f.remote.OnClientEvent:Fire(mode,2,2); assert(f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
			f.advance(.19); f.humanoid.Health=0; f.advance(.01); assert(f.camera.CameraType=="Scriptable")
			f.advance(.99); assert(f.camera.CameraSubject==f.humanoid); f.advance(.01)
			assert(f.camera.CameraSubject==f.killerHumanoid and f.frame.Visible==(mode=="Spectate"))
		end
	end)
	test("replication retry is bounded and cancellation prevents spectating a new avatar",function()
		for _,reason in ipairs({"timeout","respawn","round","stop","camera"}) do
			local f=fixture(); f.spectate(); f.humanoid.Health=100; f.player:SetAttribute("InRound",false)
			f.remote.OnClientEvent:Fire("Spectate",2,0); f.advance(.1)
			if reason=="respawn" then f.respawn()
			elseif reason=="round" then f.active.Value=false; f.active.Changed:Fire(false)
			elseif reason=="stop" then f.handler.StopSpectating()
			elseif reason=="camera" then f.camera.CameraType="Scriptable" end
			f.advance(2); f.humanoid.Health=0; f.advance(2)
			assert(not f.frame.Visible and f.run.RenderStepped:Count()==0 and f.run.Heartbeat:Count()==0)
		end
	end)
	test("exact dead-character remote is accepted and an old corpse message after respawn is rejected",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false)
		local previous=f.character; f.respawn()
		f.remote.OnClientEvent:Fire("Spectate",2,0,previous); f.advance(.2)
		assert(f.camera.CameraType=="Custom" and #f.jobs==0 and not f.frame.Visible)
		f.humanoid.Health=0; f.remote.OnClientEvent:Fire("Spectate",2,0,f.character)
		assert(f.camera.CameraType=="Scriptable"); f.advance(1); assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("manual spectate cancels automatic handoff and exit restores own camera",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.remote.OnClientEvent:Fire("Spectate",2,0)
		f.handler.ToggleFrame(); assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
		f.handler.StopSpectating(); f.advance(2); assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid)
	end)
	test("late death remote after round end does not start a new death camera",function()
		local f=fixture(); f.spectate(); f.active.Value=false; f.active.Changed:Fire(false)
		f.remote.OnClientEvent:Fire("Spectate",2,0); f.advance(2)
		assert(not f.frame.Visible and f.camera.CameraType=="Custom" and f.run.RenderStepped:Count()==0)
	end)
	test("no surviving players leaves normal UI and creates no spectator loops",function()
		local f=fixture(); f.spectate(); f.killer:SetAttribute("InRound",false); f.player:SetAttribute("InRound",false)
		f.remote.OnClientEvent:Fire("Spectate",0,0); f.advance(1)
		assert(not f.frame.Visible and f.run.Heartbeat:Count()==0 and f.run.RenderStepped:Count()==0)
	end)
	test("BR lobby respawn retains target while a manual exit cancels delayed repair",function()
		for _,exit in ipairs({false,true}) do
			local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.remote.OnClientEvent:Fire("Spectate",2,0); f.advance(1)
			f.respawn(); f.heartbeat(); assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
			if exit then f.handler.StopSpectating() end
			f.advance(.2); assert(f.frame.Visible~=exit and f.camera.CameraSubject==(exit and f.humanoid or f.killerHumanoid))
		end
	end)
	test("spectator and FFA tracking leave external camera takeover intact",function()
		for _,mode in ipairs({"Spectate","Respawn"}) do
			local f=fixture(); f.spectate(); if mode=="Spectate" then f.player:SetAttribute("InRound",false) end
			f.remote.OnClientEvent:Fire(mode,2,2); f.advance(1); f.camera.CameraType="Scriptable"; f.camera.CameraSubject=f.humanoid
			f.heartbeat(); assert(f.camera.CameraType=="Scriptable" and f.camera.CameraSubject==f.humanoid and not f.frame.Visible)
		end
	end)
	test("round kills time display mode and name update immediately without polling",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.player:SetAttribute("CurrentRoundMode","Free For All")
		f.handler.StartSpectating(); assert(f.camera.CameraSubject==f.killerHumanoid and f.kills.Text=="0")
		f.killer:SetAttribute("CurrentRoundKills",3); assert(f.kills.Text=="3")
		f.timer.Value=59; assert(string.find(f.match.Text,"0:59",1,true))
		f.player:SetAttribute("CurrentRoundMode","Battle Royale"); assert(string.find(f.match.Text,"Battle Royale",1,true))
		f.killer.DisplayName="<b>Killer</b>"; assert(f.name.Text=="<b>Killer</b>" and f.name.RichText==false)
		f.killer:SetAttribute("CurrentRoundKills",0/0); assert(f.kills.Text=="0")
		assert(f.run.Heartbeat:Count()==0 and f.run.RenderStepped:Count()==0 and #f.jobs==0)
	end)
	test("late equipped knife replication replacement removal and unknown values clear stale icons",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		assert(f.knife.Image=="")
		local stats=f.node("Folder","leaderstats",f.killer)
		local knife=f.node("StringValue","EquippedKnife",nil); knife.Value="Starter"; knife.Parent=stats
		assert(f.knife.Image=="rbxassetid://11")
		knife.Value="Gold"; assert(f.knife.Image=="rbxassetid://22")
		knife.Value="Unknown"; assert(f.knife.Image=="")
		knife.Value="Starter"; knife.Parent=nil; assert(f.knife.Image=="" and knife.Changed:Count()==0)
		local replacement=f.node("StringValue","EquippedKnife",nil); replacement.Value="Gold"; replacement.Parent=stats
		assert(f.knife.Image=="rbxassetid://22")
		stats.Parent=nil; assert(f.knife.Image=="" and replacement.Changed:Count()==0)
		local newer=f.node("Folder","leaderstats",f.killer)
		replacement.Parent=newer; assert(f.knife.Image=="rbxassetid://22")
		replacement.Parent=nil
		f.node("Folder","EquippedKnife",newer); assert(f.knife.Image=="")
	end)
	test("deterministic arrows wrap living targets and dead InRound avatars do not inflate alive count",function()
		local f=fixture(); f.spectate(); local last=f.addPlayer(9); local middle=f.addPlayer(5); f.addPlayer(3,0)
		f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		assert(f.camera.CameraSubject==f.killerHumanoid and string.find(f.match.Text,">3</font>",1,true))
		f.bottom.ArrowRight.MouseButton1Click:Fire(); assert(f.camera.CameraSubject==middle.Character.Humanoid)
		f.bottom.ArrowRight.MouseButton1Click:Fire(); assert(f.camera.CameraSubject==last.Character.Humanoid)
		f.bottom.ArrowRight.MouseButton1Click:Fire(); assert(f.camera.CameraSubject==f.killerHumanoid)
		f.bottom.ArrowLeft.MouseButton1Click:Fire(); assert(f.camera.CameraSubject==last.Character.Humanoid)
		last.Character.Humanoid.Health=0; assert(f.camera.CameraSubject==f.killerHumanoid)
		assert(string.find(f.match.Text,">2</font>",1,true))
	end)
	test("target leaving or elimination selects the next living player and detaches old character listeners",function()
		local f=fixture(); f.spectate(); local other=f.addPlayer(4); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		local previous=f.killer.Character; f.removePlayer(f.killer)
		assert(f.camera.CameraSubject==other.Character.Humanoid and previous.Humanoid.HealthChanged:Count()==0)
		assert(f.killer.CharacterAdded:Count()==0 and f.killer:GetAttributeChangedSignal("CurrentRoundKills"):Count()==0)
		other:SetAttribute("InRound",false); assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid)
	end)
	test("FFA spectating waits through a missing character and resumes when a late humanoid replicates",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		local previous=f.killer.Character; f.killerHumanoid.Health=0
		assert(f.frame.Visible and f.name.Text=="Waiting for player..." and f.camera.CameraSubject==f.humanoid)
		local newer=f.replaceTargetCharacter(f.killer,true)
		assert(f.frame.Visible and previous.Humanoid.HealthChanged:Count()==0 and previous.ChildAdded:Count()==0)
		local humanoid=f.node("Humanoid","Humanoid",newer)
		assert(f.camera.CameraSubject==humanoid and f.name.Text=="Killer")
		f.killer:SetAttribute("InRound",false); assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid)
		assert(#f.jobs==0 and f.run.Heartbeat:Count()==0)
	end)
	test("local late humanoid and native camera subject changes keep manual spectating on its target",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		f.player.CharacterRemoving:Fire(f.character)
		local newer=f.node("Model","LateOwnCharacter",{}); f.player.Character=newer; f.player.CharacterAdded:Fire(newer)
		local humanoid=f.node("Humanoid","Humanoid",newer); f.camera.CameraSubject=humanoid
		assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
		f.handler.StopSpectating(); assert(f.camera.CameraSubject==humanoid)
	end)
	test("camera replacement reconnects expected native ownership and preserves foreign camera takeovers",function()
		for _,custom in ipairs({false,true}) do
			local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
			local nextCamera=f.node("Camera","NextCamera",nil); nextCamera.CameraType=custom and "Custom" or "Scriptable"
			nextCamera.CameraSubject=custom and f.humanoid or f.killerHumanoid
			f.workspace.CurrentCamera=nextCamera
			assert(f.frame.Visible==custom and nextCamera.CameraSubject==f.killerHumanoid)
			assert(f.camera:GetPropertyChangedSignal("CameraSubject"):Count()==0)
			if custom then
				local foreign=f.node("Part","Cutscene",nil); nextCamera.CameraSubject=foreign
				assert(not f.frame.Visible and nextCamera.CameraSubject==foreign)
			end
		end
	end)
	test("native nil subject repairs once but foreign subjects and round participants cannot enter manual spectate",function()
		local f=fixture(); f.spectate(); f.handler.StartSpectating(); assert(not f.frame.Visible)
		f.player:SetAttribute("InRound",false); f.active.Value=false; f.handler.StartSpectating(); assert(not f.frame.Visible)
		f.active.Value=true; f.camera.CameraType="Scriptable"; f.handler.StartSpectating(); assert(not f.frame.Visible)
		f.camera.CameraType="Custom"; f.camera.CameraSubject=f.node("Part","Foreign",nil)
		f.handler.StartSpectating(); assert(not f.frame.Visible)
		f.camera.CameraSubject=f.humanoid; f.handler.StartSpectating(); f.camera.CameraSubject=nil
		assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("external UI close restores saved visibility and cancels camera tracking",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false)
		f.main.SystemTexts.Status.Visible=false; f.main.Bottom.Visible=true; f.handler.StartSpectating()
		f.frame.Visible=false
		assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid and not f.main.SystemTexts.Status.Visible and f.main.Bottom.Visible)
		f.killer:SetAttribute("CurrentRoundKills",9); assert(f.kills.Text=="0")
	end)
	test("BR waits for other player round membership replication before consuming automatic entry",function()
		local f=fixture(); f.spectate(); f.killer:SetAttribute("InRound",false); f.player:SetAttribute("InRound",false)
		f.remote.OnClientEvent:Fire("Spectate",2,0); f.advance(1); assert(not f.frame.Visible)
		f.killer:SetAttribute("InRound",true); assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
	end)
	test("FFA camera property event at its deadline restores an owned killer subject",function()
		local f=fixture(); f.spectate(); f.remote.OnClientEvent:Fire("Respawn",2,2); f.advance(1)
		f.now=2; f.camera.CameraSubject=nil
		assert(f.camera.CameraSubject==f.humanoid); f.advance(1); assert(f.camera.CameraSubject==f.humanoid)
	end)
	test("thirty target respawns and round teardown cycles retain a fixed listener count",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false)
		local baseline=f.connectionCount()
		for cycle=1,30 do
			f.handler.StartSpectating(); local old=f.killer.Character
			local newer=f.replaceTargetCharacter(f.killer,false)
			assert(f.frame.Visible and f.camera.CameraSubject==newer.Humanoid)
			assert(old.ChildAdded:Count()==0 and old.ChildRemoved:Count()==0 and old.Humanoid.HealthChanged:Count()==0)
			f.killer:SetAttribute("CurrentRoundKills",cycle); assert(f.kills.Text==tostring(cycle))
			f.active.Value=false; assert(not f.frame.Visible and f.camera.CameraSubject==f.humanoid)
			f.active.Value=true; assert(f.connectionCount()==baseline)
		end
		f.handler.Destroy(); f.handler.Destroy(); assert(f.connectionCount()==0 and f.remote.OnClientEvent:Count()==0)
		f.handler.Init(); f.handler.Init(); assert(f.connectionCount()==baseline and f.remote.OnClientEvent:Count()==1)
		f.handler.StartSpectating(); assert(f.frame.Visible)
	end)
	test("destroyed Main and isolated spectator frame automatically rebind new UI without duplicate remotes",function()
		for _,mainRemoved in ipairs({false,true}) do
			local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
			local oldFrame,oldArrow=f.frame,f.bottom.ArrowLeft
			if mainRemoved then f.main:Destroy(); f.main=f.node("ScreenGui","Main",f.player.PlayerGui)
			else f.frame:Destroy(); f.node("GuiObject","SpectateFrame",f.main) end
			f.advance(0)
			local current=f.main.SpectateFrame
			assert(current~=oldFrame and current.Visible and f.remote.OnClientEvent:Count()==1)
			assert(oldArrow.MouseButton1Click:Count()==0)
			f.handler.StopSpectating(); assert(not current.Visible and f.camera.CameraSubject==f.humanoid)
		end
	end)
	test("delayed BR death replication survives the server lobby respawn deadline and obeys later cancellation",function()
		for _,cancel in ipairs({false,"stop","round","participant"}) do
			local f=fixture(); f.spectate(); f.humanoid.Health=100; f.player:SetAttribute("InRound",false)
			f.remote.OnClientEvent:Fire("Spectate",2,0,f.character)
			f.advance(.7); f.humanoid.Health=0; f.advance(.05); assert(f.camera.CameraType=="Scriptable")
			f.advance(.75)
			if cancel=="stop" then f.handler.StopSpectating()
			elseif cancel=="round" then f.active.Value=false
			elseif cancel=="participant" then f.player:SetAttribute("InRound",true) end
			f.respawn(); f.advance(1)
			assert(f.frame.Visible==(cancel==false) and f.camera.CameraType=="Custom")
			assert(f.camera.CameraSubject==(cancel and f.humanoid or f.killerHumanoid))
		end
	end)
	test("BR elimination membership replicating after lobby respawn still opens the intended spectator",function()
		local f=fixture(); f.spectate(); f.humanoid.Health=100
		f.remote.OnClientEvent:Fire("Spectate",2,0,f.character)
		f.advance(.7); f.humanoid.Health=0; f.advance(.8); f.respawn()
		assert(not f.frame.Visible and f.camera.CameraType=="Custom")
		f.advance(.3); f.player:SetAttribute("InRound",false)
		assert(f.frame.Visible and f.camera.CameraSubject==f.killerHumanoid)
		f.advance(5); assert(f.frame.Visible and f.remote.OnClientEvent:Count()==1)
	end)
	test("original and replacement top spectate buttons toggle once and play one click sound",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false)
		local button=f.main.Top.Buttons.Spectate; button.ClassName="ImageButton"
		f.env.script.Parent.Modules={WaitForChild=function(_,name) return name end}
		load("Frames",f.env)
		button.MouseButton1Up:Fire(); assert(f.frame.Visible and f.clickSounds==1)
		button.MouseButton1Up:Fire(); assert(not f.frame.Visible and f.clickSounds==2)
		f.main:Destroy(); f.main=f.node("ScreenGui","Main",f.player.PlayerGui); f.advance(0)
		local replacement=f.main.Top.Buttons.Spectate
		replacement.MouseButton1Up:Fire(); assert(f.main.SpectateFrame.Visible and f.clickSounds==3)
		replacement.MouseButton1Up:Fire(); assert(not f.main.SpectateFrame.Visible and f.clickSounds==4)
		assert(replacement.MouseButton1Up:Count()==1 and f.remote.OnClientEvent:Count()==1)
	end)
	test("partial replacement UI waiters cancel on destruction and the next complete replacement reconnects",function()
		local f=fixture(); f.spectate(); f.player:SetAttribute("InRound",false); f.handler.StartSpectating()
		f.main:Destroy()
		local partial=f.node("ScreenGui","Main",f.player.PlayerGui)
		f.waitHook=function(instance,name) if instance==partial and name=="SpectateFrame" then f.task.wait(10) end end
		f.advance(0); assert(f.remote.OnClientEvent:Count()==0 and partial.Destroying:Count()==1)
		partial:Destroy(); assert(partial.Destroying:Count()==0)
		f.main=f.node("ScreenGui","Main",f.player.PlayerGui); f.advance(0)
		assert(f.main.SpectateFrame.Visible and f.remote.OnClientEvent:Count()==1)
		f.handler.Destroy()
		for _, job in ipairs(f.jobs) do assert(f.cancelled[job.thread]) end
		assert(f.player.PlayerGui.ChildAdded:Count()==0 and f.workspace:GetPropertyChangedSignal("CurrentCamera"):Count()==0)
	end)
	test("replicated ragdoll reference identifies one clone and is cleaned with its lifetime",function()
		local ragdollLoad=function(name,env) local names={Mock="RagdollMock",Config="RagdollConfig",Rig="RagdollRig",Service="RagdollService",Query="RagdollQuery"}; return load(assert(names[name],name),env) end
		local mock=load("RagdollMock"); local f=mock.New(ragdollLoad); local p=f.player(); f.service.Init()
		local original=p.Character; original.Humanoid.Health=0; local corpse=f.service.OnDeath(original)
		local ref=original:FindFirstChild("DeathRagdollReference"); assert(ref and ref:IsA("ObjectValue") and ref.Value==corpse)
		assert(f.service.OnDeath(original)==nil and #original:GetChildren()>0)
		local newer=f.character(p); f.advance(5); assert(ref.Destroyed and corpse.Destroyed and newer.Parent)
	end)
	print(tostring(passed).." death/spectate tests passed")
end
