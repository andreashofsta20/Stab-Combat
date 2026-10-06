-- Executes production geometry, rewind history and both authoritative handlers.
return function(load)
	local passed = 0
	local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a).." ~= "..tostring(b)) end
	local function test(name,fn)
		local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); passed+=1; print("PASS "..name)
	end
	local Vector,vm = {},{}
	function Vector.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vm) end
	local V=Vector.new
	function Vector:Dot(v) return self.X*v.X+self.Y*v.Y+self.Z*v.Z end
	vm.__index=function(v,key)
		if key=="Magnitude" then return math.sqrt(v:Dot(v)) end
		if key=="Unit" then return v/v.Magnitude end
		return Vector[key]
	end
	vm.__add=function(a,b) return V(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
	vm.__sub=function(a,b) return V(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
	vm.__mul=function(a,b) if type(a)=="number" then a,b=b,a end; return V(a.X*b,a.Y*b,a.Z*b) end
	vm.__div=function(a,b) return V(a.X/b,a.Y/b,a.Z/b) end
	vm.__unm=function(a) return a*-1 end
	Vector.zero=V(0,0,0)
	local Frame,fm={},{}
	local identity={1,0,0,0,1,0,0,0,1}
	local function frame(pos,matrix) return setmetatable({Position=pos,matrix=matrix},fm) end
	function Frame.new(x,y,z) return frame(type(x)=="table" and x or V(x or 0,y or 0,z or 0),table.clone(identity)) end
	function Frame:VectorToWorldSpace(v)
		local r=self.matrix; return V(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
	end
	function Frame:VectorToObjectSpace(v)
		local r=self.matrix; return V(r[1]*v.X+r[4]*v.Y+r[7]*v.Z,r[2]*v.X+r[5]*v.Y+r[8]*v.Z,r[3]*v.X+r[6]*v.Y+r[9]*v.Z)
	end
	function Frame:PointToWorldSpace(v) return self.Position+self:VectorToWorldSpace(v) end
	function Frame:PointToObjectSpace(v) return self:VectorToObjectSpace(v-self.Position) end
	function Frame:Lerp(other,alpha)
		local r={}; for i=1,9 do r[i]=self.matrix[i]+(other.matrix[i]-self.matrix[i])*alpha end
		return frame(self.Position+(other.Position-self.Position)*alpha,r)
	end
	fm.__index=Frame
	fm.__mul=function(a,b)
		local r={}; for row=0,2 do for col=0,2 do
			local sum=0; for k=0,2 do sum+=a.matrix[row*3+k+1]*b.matrix[k*3+col+1] end; r[row*3+col+1]=sum
		end end; return frame(a:PointToWorldSpace(b.Position),r)
	end
	function Frame.Angles(x,y,z)
		local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
		return frame(Vector.zero,{1,0,0,0,cx,-sx,0,sx,cx})*frame(Vector.zero,{cy,0,sy,0,1,0,-sy,0,cy})*frame(Vector.zero,{cz,-sz,0,sz,cz,0,0,0,1})
	end
	local function signal()
		local s={listeners={}}
		function s:Connect(fn) local c={fn=fn}; function c:Disconnect() self.disconnected=true end; table.insert(self.listeners,c); return c end
		function s:Fire(...) for _,c in ipairs(table.clone(self.listeners)) do if not c.disconnected then c.fn(...) end end end
		return s
	end
	local methods,om={},{}
	om.__index=function(o,key)
		if methods[key] then return methods[key] end
		if key=="Position" and o.props.CFrame then return o.props.CFrame.Position end
		if o.props[key]~=nil then return o.props[key] end
		for _,child in ipairs(o.children) do if child.Name==key then return child end end
	end
	om.__newindex=function(o,key,value)
		if key=="Parent" then
			local old=o.props.Parent; if old then local index=table.find(old.children,o); if index then table.remove(old.children,index) end end
			if value then table.insert(value.children,o) end
		end
		o.props[key]=value
	end
	local function object(class,name,parent)
		local o=setmetatable({props={ClassName=class,Name=name or class},children={},attributes={}},om)
		if class=="Part" then o.CFrame,o.Size=Frame.new(),V(2,2,2) end
		for _,key in ipairs({"OnServerEvent","PlayerAdded","PlayerRemoving","CharacterRemoving"}) do o[key]=signal() end
		o.Parent=parent; return o
	end
	function methods:IsA(class) return self.ClassName==class or class=="BasePart" and self.ClassName=="Part" end
	function methods:GetChildren() return table.clone(self.children) end
	function methods:FindFirstChild(name,recursive)
		for _,c in ipairs(self.children) do if c.Name==name then return c end end
		if recursive then for _,c in ipairs(self.children) do local found=c:FindFirstChild(name,true); if found then return found end end end
	end
	function methods:FindFirstChildOfClass(class) for _,c in ipairs(self.children) do if c:IsA(class) then return c end end end
	function methods:WaitForChild(name) return assert(self:FindFirstChild(name),"Missing "..name) end
	function methods:GetAttribute(name) return self.attributes[name] end
	function methods:GetNetworkPing() return self.Ping or 0 end
	local typeof=function(v) return getmetatable(v)==vm and "Vector3" or type(v) end
	local base={CFrame=Frame,Vector3=Vector,typeof=typeof,Instance={new=object},Enum={RaycastFilterType={Exclude="Exclude"}},RaycastParams={new=function() return {} end}}
	local Math=load("Math",base)
	local rayEnv=table.clone(base); rayEnv.script={Parent={RevolverMath="Math"}}; rayEnv.require=function() return Math end
	local Raycast=load("Raycast",rayEnv)
	local Config,KnifeConfig=load("Config"),load("KnifeConfig")
	local projectileEnv=table.clone(base); projectileEnv.script={Parent={KnifeConfig="KnifeConfig"}}; projectileEnv.require=function() return KnifeConfig end
	local Projectile=load("Projectile",projectileEnv)
	local function part(character,name,pos,size,rotation)
		local p=object("Part",name,character); p.CFrame=Frame.new(pos)*(rotation or Frame.new()); p.Size=size or V(2,2,2); return p
	end
	local function character(name,pos)
		local char=object("Model",name)
		local hum=object("Humanoid","Humanoid",char); hum.Health,hum.MaxHealth=100,100
		local root=part(char,"HumanoidRootPart",pos,V(2,2,1))
		local head=part(char,"Head",pos+V(0,2,0),V(2,1,1))
		part(char,"Torso",pos,V(2,2,1))
		part(char,"Hitbox",pos,V(6,7.5,6))
		return char,hum,root,head
	end
	local function target(char)
		local t=Raycast.GetCharacterGeometry(char); t.frame=char.HumanoidRootPart.CFrame*Frame.new(table.unpack(Config.Default.HitboxOffset)); return t
	end
	local function castParts(parts,excluded,ignoreInsideOrigins)
		return function(origin,vector)
			if vector.Magnitude<1e-8 then return nil end
			local nearest=vector.Magnitude; local hit
			for _,p in ipairs(parts) do
				local skip=false; local current=p
				while current do if table.find(excluded or {},current) then skip=true; break end; current=current.Parent end
				if ignoreInsideOrigins and not skip then
					-- Model Workspace's surface-ray behavior separately from the
					-- pure slab helper, which reports distance zero inside a box.
					local localOrigin=p.CFrame:PointToObjectSpace(origin)
					if math.abs(localOrigin.X)<=p.Size.X/2 and math.abs(localOrigin.Y)<=p.Size.Y/2 and math.abs(localOrigin.Z)<=p.Size.Z/2 then skip=true end
				end
				if not skip then
					local d=Math.RayBoxDistance(origin,vector.Unit,p.CFrame,{p.Size.X,p.Size.Y,p.Size.Z},nearest)
					if d and d<nearest then nearest=d; hit={Instance=p,Distance=d,Position=origin+vector.Unit*d,Normal=V(0,0,1)} end
				end
			end
			return hit
		end
	end
	local empty=function() return nil end
	test("third person cursor can select a rear head between the avatar and camera",function()
		local char=character("RearVictim",V(0,0,4)); local t=target(char)
		local hit=Raycast.Resolve(V(0,2,8),V(0,0,-1),V(0,2,0),Config.Default,{t},empty,V(0,2,0))
		assert(hit and hit.victim==t and hit.headshot,"A head visible behind the avatar must remain selectable before the camera ray reaches the avatar")
		near(hit.position.Z,3.5)
	end)
	test("precise head shots converge past the broad proxy while body hits keep the forgiving envelope",function()
		local char=character("Victim",V(0,0,-20)); local t=target(char)
		local head=Raycast.Resolve(V(0,2,0),V(0,0,-1),V(0.7,1.5,-1),Config.Default,{t},empty)
		assert(head.victim==t and head.headshot); near(head.position.Z,-19.5)
		local body=Raycast.Resolve(V(0,0,0),V(0,0,-1),V(0,0,0),Config.Default,{t},empty)
		assert(body.victim==t and not body.headshot); near(body.position.Z,-18)
		local edge=Raycast.Resolve(V(1.8,2,0),V(0,0,-1),V(1.8,2,0),Config.Default,{t},empty)
		assert(edge.victim==t and not edge.headshot,"Broad shoulder area may only award body damage")
	end)
	test("head boundaries and rotated head sizes use local coordinates",function()
		local char,_,_,head=character("Victim",V(0,0,-20)); local t=target(char)
		near(Raycast.GetHeadshotDistance(V(1,2,0),V(0,0,-1),100,t),19.5)
		assert(not Raycast.GetHeadshotDistance(V(1.0001,2,0),V(0,0,-1),100,t))
		head.CFrame=head.CFrame*Frame.Angles(0,math.pi/2,0); t=target(char)
		near(Raycast.GetHeadshotDistance(V(0.49,2,0),V(0,0,-1),100,t),19)
		assert(not Raycast.GetHeadshotDistance(V(0.51,2,0),V(0,0,-1),100,t))
		assert(not Raycast.GetHeadshotDistance(V(0,2,0),V(0,0,-1),18,t),"Range stops before the actual head")
	end)
	test("torso and animated arms in front of a head block headshot bonuses",function()
		local char=character("Victim",V(0,0,-20)); local t=target(char)
		assert(not Raycast.GetHeadshotDistance(V(0,-5,-20),V(0,1,0),30,t))
		part(char,"Right Arm",V(0,2,-18),V(1,1,1)); t=target(char)
		local hit=Raycast.Resolve(V(0,2,0),V(0,0,-1),V(0,2,0),Config.Default,{t},empty)
		assert(hit.victim==t and not hit.headshot)
	end)
	test("an accessory cannot manufacture head geometry or block the head with a hat handle",function()
		local char,_,_,head=character("Victim",V(0,0,-20))
		local hat=object("Accessory","Hat",char); part(hat,"Head",V(0,2,-10),V(8,8,8))
		local t=target(char); near(Raycast.GetHeadshotDistance(V(0,2,0),V(0,0,-1),100,t),19.5)
		head.Parent=nil; t=target(char); assert(not Raycast.GetHeadshotDistance(V(0,2,0),V(0,0,-1),100,t))
	end)
	test("world cover stops head shots and an exposed head remains hittable above covered shoulders",function()
		local char=character("Victim",V(0,0,-20)); local t=target(char)
		local wall=part(nil,"Wall",V(0,2,-18),V(10,1,0.5))
		local hit=Raycast.Resolve(V(0,2,0),V(0,0,-1),V(0,2,0),Config.Default,{t},castParts({wall}))
		assert(not hit.victim and not hit.headshot and hit.surface==wall)
		wall.CFrame=Frame.new(0,0,-18); wall.Size=V(10,2.4,0.5)
		hit=Raycast.Resolve(V(0,2,0),V(0,0,-1),V(0,2,0),Config.Default,{t},castParts({wall}))
		assert(hit.victim==t and hit.headshot)
	end)
	test("a closer player body absorbs a line that would headshot a farther player",function()
		local farther=character("Farther",V(0,0,-25)); local nearer=character("Nearer",V(0,2,-12))
		local far,close=target(farther),target(nearer)
		for _,list in ipairs({{far,close},{close,far}}) do
			local hit=Raycast.Resolve(V(0,2,0),V(0,0,-1),V(0,2,0),Config.Default,list,empty)
			assert(hit.victim==close and not hit.headshot)
		end
	end)
	test("cursor cover can be hit in either direction from the trusted head",function()
		local camera,direction,head=V(0,2,8),V(0,0,-1),V(0,2,0)
		local wall=part(nil,"NarrowWall",V(0,2,-1),V(0.2,2,0.2)); local worldCast=castParts({wall})
		local resolved=Raycast.Resolve(camera,direction,head,Config.Default,{},worldCast)
		assert(resolved and resolved.surface==wall); near(resolved.position.Z,-0.9)
		wall.CFrame=Frame.new(0,2,4)
		resolved=Raycast.Resolve(camera,direction,head,Config.Default,{},worldCast)
		assert(resolved and resolved.surface==wall); near(resolved.position.Z,3.9)
	end)
	test("overhead camera can aim upward from a low muzzle at an elevated forward target",function()
		local camera,muzzle,point=V(0,25,10),V(1,2,-1),V(1,15,-6)
		local direction=(point-camera).Unit; local t={frame=Frame.new(point)}
		local resolved=Raycast.Resolve(camera,direction,muzzle,Config.Default,{t},empty,V(0,2,0))
		assert(resolved and resolved.victim==t)
		assert((resolved.position-muzzle):Dot(direction)<0,"A full 3D dot check would wrongly reject this elevated overhead target")
		assert(resolved.position.Z<muzzle.Z)
	end)
	test("a camera inside a rear body proxy does not force the head ray forward",function()
		local char=character("NearbyRear",V(0,0,7)); local t=target(char)
		local resolved=Raycast.Resolve(V(0,0,8),V(0,0,-1),V(0,0,0),Config.Default,{t},empty)
		assert(resolved and resolved.victim==t and not resolved.headshot)
		near(resolved.position.Z,5)
	end)
	test("head and body cursor targets work all around the character before and beyond its position",function()
		for index=0,15 do
			local angle=index*math.pi/8; local outward=V(math.sin(angle),0,math.cos(angle))
			for _,distance in ipairs({4,-20}) do
				local char=character("OrbitVictim",outward*distance); local t=target(char)
				for _,height in ipairs({0,2}) do
					local head=V(0,height,0); local camera=head+outward*8
					local hit=Raycast.Resolve(camera,-outward,head,Config.Default,{t},empty)
					assert(hit and hit.victim==t and hit.headshot==(height==2),"Cursor targets must work at every yaw and either side of the avatar")
					assert(hit.distance<=Config.Default.Range)
					if distance>0 then assert((hit.position-head):Dot(-outward)<0,"Close rear shots legitimately oppose camera forward") end
				end
			end
		end
	end)
	test("unobstructed cosmetic muzzle is used while invalid or beyond endpoint origins fall back",function()
		local physical,cosmetic,destination=V(0,2,0),V(0.5,2.5,-1),V(0,2,-10)
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,empty)==cosmetic)
		for _,bad in ipairs({false,"bad",V(0/0,0,0),V(math.huge,0,0),V(1000001,0,0),destination,V(4,2,-11)}) do
			assert(Raycast.GetVisualShotOrigin(physical,bad,destination,empty)==physical)
		end
		assert(Raycast.GetVisualShotOrigin(physical,nil,destination,empty)==physical)
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,physical,empty)==physical)
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,nil)==physical)
	end)
	test("decorative advance past a near wall uses the validated physical origin",function()
		for _,angle in ipairs({0,math.pi/2,-math.pi/2}) do
			local pose=Frame.new(8,3,5)*Frame.Angles(0,angle,0)
			local physical,cosmetic,destination=pose:PointToWorldSpace(V(0,2,0)),pose:PointToWorldSpace(V(0,2.5,-1.1)),pose:PointToWorldSpace(V(0,2,-0.6))
			local wall=part(nil,"NearWall",pose:PointToWorldSpace(V(0,2,-0.7)),V(10,10,0.2),Frame.Angles(0,angle,0))
			assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,castParts({wall}))==physical)
		end
	end)
	test("replaced physical origin cannot reach a cosmetic muzzle through a wall or endpoint",function()
		local physical,cosmetic,destination=V(0,2,0),V(1,2,-0.2),V(0,2,-10)
		local wall=part(nil,"OffsetWall",V(0.5,2,-0.1),V(0.05,2,0.05)); local worldCast=castParts({wall})
		assert(not worldCast(physical,destination-physical),"The accepted physical shot is clear")
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,worldCast)==physical)
		-- Unlike the final endpoint check, the origin-segment check is strict.
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,function(_,vector) return {Distance=vector.Magnitude} end)==physical)
	end)
	test("side pillar blocks cosmetic trajectory without introducing a second endpoint",function()
		local physical,cosmetic,destination=V(0,2,0),V(1,2,0),V(0,2,-10)
		local pillar=part(nil,"SidePillar",V(0.8,2,-2),V(0.3,2,0.3)); local worldCast=castParts({pillar})
		assert(not worldCast(physical,destination-physical) and not worldCast(physical,cosmetic-physical))
		assert(Raycast.GetVisualShotOrigin(physical,cosmetic,destination,worldCast)==physical)
		near(destination.Z,-10)
	end)
	test("cosmetic shot accepts the same final wall endpoint within surface tolerance",function()
		local physical,cosmetic,destination=V(0,2,0),V(0.5,2.5,-1),V(0,2,-10)
		for _,shortening in ipairs({0,0.015,0.03}) do
			local chosen=Raycast.GetVisualShotOrigin(physical,cosmetic,destination,function(origin,vector)
				if origin==cosmetic then return {Distance=vector.Magnitude-shortening} end
			end)
			assert(chosen==(shortening<=0.02 and cosmetic or physical))
		end
	end)
	local function fixture(weapon)
		local f={time=10,worldParts={},damage={},states={},shots={},results={},visuals={}}
		local env=table.clone(base)
		local players=object("Players","Players")
		f.player=object("Player","Shooter",players); f.player.UserId=1
		f.victim=object("Player","Victim",players); f.victim.UserId=2
		f.player.attributes={DataReady=true,InRound=true}; f.victim.attributes={DataReady=true,InRound=true}
		f.player.Character,f.shooterHum,f.shooterRoot,f.shooterHead=character("Shooter",V(0,0,0))
		f.victim.Character,f.victimHum,f.victimRoot,f.victimHead=character("Victim",V(0,0,-20))
		for _,p in ipairs({f.player,f.victim}) do for _,child in ipairs(p.Character:GetChildren()) do if child:IsA("BasePart") then table.insert(f.worldParts,child) end end end
		function players:GetPlayers() return {f.player,f.victim} end
		f.tool=object("Tool",weapon or "RevolverA",f.player.Character)
		local stats=object("Folder","leaderstats",f.player)
		local selected=object("StringValue","EquippedGun",stats); selected.Value=f.tool.Name
		local inventory=object("Folder","RevolverInventory",stats); local owned=object("Folder",f.tool.Name,inventory)
		object("IntValue","Quantity",owned).Value=1
		local rs=object("ReplicatedStorage","ReplicatedStorage")
		local remotes=object("Folder","Remotes",rs); local knife=object("Folder","Knife",remotes)
		local damage=object("RemoteEvent","DamageDealtClient",knife)
		function damage:FireClient(...) table.insert(f.damage,{...}) end
		local results=object("RemoteEvent","ThrewClient",knife)
		function results:FireClient(_,data) table.insert(f.results,data) end
		function results:FireAllClients(data) table.insert(f.visuals,data) end
		local revolver=object("Folder","Revolver",remotes)
		f.action=object("RemoteEvent","Action",revolver)
		local stateRemote=object("RemoteEvent","State",revolver); function stateRemote:FireClient(_,data) table.insert(f.states,data); f.session=data.Session end
		local shot=object("RemoteEvent","Shot",revolver); function shot:FireAllClients(data) table.insert(f.shots,data) end
		object("UnreliableRemoteEvent","Aim",revolver).FireAllClients=function() end
		local ss=object("ServerStorage","ServerStorage"); local guns=object("Folder","Revolvers",ss); object("Tool",f.tool.Name,guns)
		local knives=object("Folder","Knives",ss); object("Tool",f.tool.Name,knives)
		local main={GameActive=true,PlayersInGame={[1]=true,[2]=true},RoundStats={}}
		function main.DamagePlayer(_,victim,hum,amount)
			if hum.Parent~=victim.Character or hum.Health<=0 or victim.Character:FindFirstChildOfClass("ForceField") then return 0 end
			f.lastAmount=amount; local before=hum.Health; hum.Health=math.max(0,before-amount); return before-hum.Health
		end
		f.main, f.players=main,players
		local run={Heartbeat=signal()}
		local services={Players=players,ReplicatedStorage=rs,ServerStorage=ss,RunService=run,HttpService={GenerateGUID=function() return "session" end}}
		env.game={GetService=function(_,name) return assert(services[name],name) end}
		env.workspace={GetServerTimeNow=function() return f.time end}
		function env.workspace:Raycast(origin,vector,params) return castParts(f.worldParts,params.FilterDescendantsInstances,f.ignoreInsideOrigins)(origin,vector) end
		env.os={clock=function() return f.time end}
		rs.Modules={RevolverConfig="Config",RevolverMath="Math",RevolverRaycast="Raycast",RevolversInfo="Catalog",RevolverToolPhysics="Physics",RevolverPoseMath="Pose",RagdollQuery="Query",ProjectileMath="Projectile"}
		local dependencies={Config=Config,Math=Math,Raycast=Raycast,Projectile=Projectile,Catalog={[f.tool.Name]={}},
			Physics={New=function() return {BindPlayer=function() end,RemovePlayer=function() end} end},Pose={},Query={Exclude=function(ignore) return ignore end},
			State=load("State"),Game=main,Hitboxes={GetPlayerFromHitbox=function(p)
				local current=p; while current do if current==(f.resolveCharacter or f.victim.Character) then return f.victim,f.resolveHumanoid or f.victimHum end; current=current.Parent end
			end}}
		env.require=function(name) return assert(dependencies[name],name) end
		env.script={Parent={RevolverState="State",RevolverHitHistory="History",PlayerHitbox="Hitboxes",Parent={Game={MainGame="Game"}}}}
		f.history=load("History",env); dependencies.History=f.history
		f.throw=load("Throw",env); load("Server",env)
		function f:fire(kind,y,extra)
			self.shooterHead.CFrame=Frame.new(0,y or 2,0)
			if kind=="Knife" then return self.throw.Throw(self.player,"knife-"..tostring(self.time),self.shooterHead.Position,V(0,0,-1),1,extra) end
			if not self.session then self.action.OnServerEvent:Fire(self.player,"Sync",nil,0) end
			self.sequence=(self.sequence or 0)+1
			self.action.OnServerEvent:Fire(self.player,"Fire",self.session,self.sequence,self.cameraOrigin or self.shooterHead.Position,self.cameraDirection or V(0,0,-1),self.shotTimestamp or self.time,extra)
		end
		function f:wall(pos,size) local wall=part(nil,"Wall",pos,size); table.insert(self.worldParts,wall); return wall end
		return f
	end
	test("revolver server applies exactly 34 body and 70 head damage with authoritative feedback",function()
		for _,case in ipairs({{0,34,false},{2,70,true}}) do
			local f=fixture(); f:fire("Revolver",case[1],not case[3])
			near(f.lastAmount,case[2]); near(f.victimHum.Health,100-case[2]); assert(#f.damage==1 and #f.shots==1)
			assert(f.damage[1][6]==case[3] and f.damage[1][4]=="Revolver","Client extra headshot flags must have no effect")
		end
	end)
	local function moveVictim(f,position)
		for _,p in ipairs(f.victim.Character:GetChildren()) do
			if p:IsA("BasePart") then p.CFrame=Frame.new(position)*p.CFrame end
		end
	end
	test("server accepts close rear body and head shots across a full camera orbit",function()
		for index=0,15 do
			local angle=index*math.pi/8; local outward=V(math.sin(angle),0,math.cos(angle))
			for _,case in ipairs({{0,34,false},{2,70,true}}) do
				local f=fixture(); moveVictim(f,outward*4+V(0,0,20))
				f.cameraOrigin=V(0,case[1],0)+outward*8; f.cameraDirection=-outward
				f:fire("Revolver",case[1])
				assert(#f.shots==1 and #f.damage==1 and f.shots[1].Hit)
				near(f.lastAmount,case[2]); assert(f.damage[1][6]==case[3])
				near((f.shots[1].Origin-f.shooterHead.Position).Magnitude,0)
				assert((f.shots[1].Position-f.shots[1].Origin):Dot(f.cameraDirection)<0)
			end
		end
	end)
	test("a solid rear cursor target between head and camera receives one shot instead of camera rejection",function()
		local f=fixture(); f.cameraOrigin=V(0,2,8)
		local rear=f:wall(V(0,2,4),V(2,2,1)); f:fire("Revolver",2)
		assert(#f.shots==1 and #f.damage==0 and f.states[#f.states].Reason=="Fired")
		assert(f.shots[1].Surface==rear); near(f.shots[1].Position.Z,3.5)
		near(f.states[#f.states].Ammo,Config.Capacity-1)
	end)
	test("head-to-target cover still blocks a rear victim seen from the other side of that wall",function()
		local f=fixture(); moveVictim(f,V(0,0,24)); f.cameraOrigin=V(0,2,8)
		local wall=f:wall(V(0,2,2),V(10,10,0.2)); f:fire("Revolver",2)
		assert(#f.shots==1 and #f.damage==0 and not f.lastAmount)
		assert(f.shots[1].Surface==wall and not f.shots[1].Hit); near(f.shots[1].Position.Z,1.9)
		near(f.victimHum.Health,100)
	end)
	test("untrusted camera distances and malformed aim remain rejected without firing",function()
		for _,camera in ipairs({V(0,2,Config.Security.MaxCameraDistance+1),V(0/0,2,0)}) do
			local f=fixture(); f.cameraOrigin=camera; f:fire("Revolver",2)
			assert(#f.shots==0 and #f.damage==0 and f.states[#f.states].Ammo==Config.Capacity)
		end
	end)
	test("low animated barrels cannot block a clear cursor shot over a ledge",function()
		for _,case in ipairs({{0,34,false,-18},{2,70,true,-19.5}}) do
			local firstOrigin,firstPosition
			for _,pose in ipairs({{0,-1.5,-0.5,0},{1,-1.6,-1,math.pi/2},{-1,-1.8,1,-math.pi/2}}) do
				local f=fixture(); local y=case[1]
				f.shooterHead.CFrame=Frame.new(0,y,0)
				local muzzle=part(f.tool,"Muzzle",V(pose[1],y+pose[2],pose[3]),V(0.1,0.1,0.1),Frame.Angles(math.pi/3,pose[4],math.pi/4))
				local ledge=f:wall(V(0,y-2,-5),V(8,3,1))
				local cast=castParts({ledge})
				assert(not cast(f.shooterHead.Position,V(0,0,-20)),"The cursor and stable eye line must clear the ledge")
				assert(cast(muzzle.Position,V(0,y,-20)-muzzle.Position),"The former animated barrel line must hit the ledge")
				f:fire("Revolver",y)
				assert(#f.shots==1 and #f.damage==1,"One clear shot must produce one accepted hit")
				local shot=f.shots[1]
				near((shot.Origin-f.shooterHead.Position).Magnitude,0)
				near(shot.Position.Z,case[4]); near(f.lastAmount,case[2]); near(f.victimHum.Health,100-case[2])
				assert(shot.Hit and shot.Surface~=ledge and f.damage[1][6]==case[3])
				if firstOrigin then
					near((shot.Origin-firstOrigin).Magnitude,0); near((shot.Position-firstPosition).Magnitude,0)
				else firstOrigin,firstPosition=shot.Origin,shot.Position end
			end
		end
	end)
	test("real eye level cover stops one shot regardless of lowered rotated or advanced barrels",function()
		local firstOrigin,firstPosition
		for _,pose in ipairs({{0,0.1,-0.5,0},{1,-1,-2,math.pi/2},{-1,3,-6,-math.pi/2}}) do
			local f=fixture(); f.cameraOrigin=V(0,2,8)
			part(f.tool,"Muzzle",V(pose[1],pose[2],pose[3]),V(0.1,0.1,0.1),Frame.Angles(math.pi/3,pose[4],math.pi/4))
			local wall=f:wall(V(0,2,-5),V(8,8,1)); f:fire("Revolver",2)
			assert(#f.shots==1 and #f.damage==0 and not f.lastAmount)
			local shot=f.shots[1]
			near((shot.Origin-f.shooterHead.Position).Magnitude,0); near(shot.Position.Z,-4.5)
			assert(shot.Surface==wall and not shot.Hit)
			near(f.victimHum.Health,100); assert(f.states[#f.states].Ammo==Config.Capacity-1)
			if firstOrigin then
				near((shot.Origin-firstOrigin).Magnitude,0); near((shot.Position-firstPosition).Magnitude,0)
			else firstOrigin,firstPosition=shot.Origin,shot.Position end
		end
	end)
	test("near cursor cover is hit from the stable eye instead of rejected behind an advanced barrel",function()
		local f=fixture(); f.cameraOrigin=V(0,2,8)
		part(f.tool,"Muzzle",V(1,2,-2),V(0.1,0.1,0.1))
		local wall=f:wall(V(0,2,-1),V(0.2,2,0.2)); f:fire("Revolver",2)
		assert(#f.shots==1 and #f.damage==0 and not f.lastAmount)
		local shot=f.shots[1]; near((shot.Origin-f.shooterHead.Position).Magnitude,0)
		assert(shot.Surface==wall and not shot.Hit); near(shot.Position.Z,-0.9)
		assert(f.states[#f.states].Reason=="Fired" and f.states[#f.states].Ammo==Config.Capacity-1)
	end)
	test("tiny muzzle penetration still hits cover when engine rays miss their containing wall",function()
		local f=fixture(); f.ignoreInsideOrigins=true; f.cameraOrigin=V(2,2,8)
		local muzzle=part(f.tool,"Muzzle",V(0,2,-1.005),V(0.1,0.1,0.1))
		local wall=f:wall(V(0,2,-1.5),V(0.5,4,1))
		assert(not castParts({wall},{},true)(muzzle.Position,V(0,0,-20)),"Engine-like ray from inside the wall must miss it")
		f:fire("Revolver",2)
		assert(#f.shots==1 and #f.damage==0 and not f.lastAmount)
		local shot=f.shots[1]; near((shot.Origin-f.shooterHead.Position).Magnitude,0)
		assert(shot.Surface==wall and not shot.Hit); near(shot.Position.Z,-1)
		near(f.victimHum.Health,100); assert(f.states[#f.states].Ammo==Config.Capacity-1)
	end)
	test("knife server deals 50 body damage and headshots one tap any living health",function()
		local body=fixture("KnifeA"); assert(body:fire("Knife",0,true)); near(body.lastAmount,50); near(body.victimHum.Health,50); assert(body.damage[1][6]==false)
		for _,health in ipairs({30,100,175}) do
			local f=fixture("KnifeA"); f.victimHum.Health=health; assert(f:fire("Knife",2,false))
			near(f.lastAmount,health); near(f.victimHum.Health,0); assert(#f.damage==1 and f.damage[1][6]==true)
			near(f.results[1].position.Z,-19.5)
		end
	end)
	test("both weapon handlers deny cover hits and protected victims without feedback",function()
		for _,kind in ipairs({"Knife","Revolver"}) do
			local f=fixture(kind=="Knife" and "KnifeA" or nil); f:wall(V(0,2,-10),V(10,10,1)); f:fire(kind,2)
			near(f.victimHum.Health,100); assert(#f.damage==0)
			local protected=fixture(kind=="Knife" and "KnifeA" or nil); object("ForceField","ForceField",protected.victim.Character); protected:fire(kind,2)
			near(protected.victimHum.Health,100); assert(#protected.damage==0)
		end
	end)
	test("knife proxy cannot deal fallback body damage through cover behind its front",function()
		for _,y in ipairs({0,2}) do
			local f=fixture("KnifeA"); f:wall(V(0,1,-18.5),V(10,10,0.2)); f:fire("Knife",y)
			near(f.victimHum.Health,100); assert(not f.lastAmount and #f.damage==0)
		end
	end)
	test("knife head peeks remain lethal above body cover",function()
		local f=fixture("KnifeA"); f:wall(V(0,0,-18.5),V(10,2.4,0.2)); f:fire("Knife",2)
		near(f.victimHum.Health,0); assert(f.damage[1][6]==true)
	end)
	test("dead victims and stale knife humanoids cannot be damaged or produce hit feedback",function()
		for _,kind in ipairs({"Knife","Revolver"}) do
			local f=fixture(kind=="Knife" and "KnifeA" or nil); f.victimHum.Health=0; f:fire(kind,2)
			assert(not f.lastAmount and #f.damage==0)
		end
		local f=fixture("KnifeA"); f.resolveCharacter,f.resolveHumanoid=f.victim.Character,f.victimHum
		f.victim.Character=character("Replacement",V(8,0,-20))
		f:fire("Knife",2); near(f.victimHum.Health,100); assert(not f.lastAmount and #f.damage==0)
	end)
	test("lag compensation interpolates actual animated head and body blocker snapshots",function()
		local f=fixture(); local lag=Config.LagCompensation; local round=f.main.RoundStats
		f.history.Sample(9.8,round,f.main.PlayersInGame,lag)
		f.victimRoot.CFrame=Frame.new(4,0,-20); f.victimHead.CFrame=Frame.new(4,3,-20)
		f.victim.Character.Torso.CFrame=Frame.new(4,0,-20)
		f.history.Sample(9.9,round,f.main.PlayersInGame,lag)
		local snapshot=f.history.GetSnapshot(f.victim,f.victim.Character,round,9.85,f.victimRoot.CFrame,lag)
		near(snapshot.frame.Position.X,2); near(snapshot.headFrame.Position.X,2); near(snapshot.headFrame.Position.Y,2.5)
		near(snapshot.bodyParts[1].frame.Position.X,2)
		local shot=Raycast.Resolve(V(2,2.5,0),V(0,0,-1),V(2,2.5,0),Config.Default,{snapshot},empty)
		assert(shot.headshot)
		local latest=f.history.GetSnapshot(f.victim,f.victim.Character,round,9.9,f.victimRoot.CFrame,lag)
		latest.frame=Frame.new(100,100,100)
		near(f.history.GetSnapshot(f.victim,f.victim.Character,round,9.9,f.victimRoot.CFrame,lag).frame.Position.X,4)
	end)
	test("revolver server rewinds head geometry instead of aiming at the current animated head",function()
		local f=fixture(); f.player.Ping=0.15
		f.history.Sample(9.8,f.main.RoundStats,f.main.PlayersInGame,Config.LagCompensation)
		f.shotTimestamp=9.85
		f.victimHead.CFrame=Frame.new(8,2,-20)
		f:fire("Revolver",2); near(f.lastAmount,70); assert(f.damage[1][6]==true)
	end)
	test("history never reuses geometry across teleports round changes or character replacements",function()
		for _,change in ipairs({"teleport","round","character","too-old","disabled","stale-sample"}) do
			local f=fixture(); local round=f.main.RoundStats; local lag=table.clone(Config.LagCompensation)
			f.history.Sample(9.8,round,f.main.PlayersInGame,lag)
			local time=9.85
			if change=="teleport" then f.victimRoot.CFrame=Frame.new(100,0,-20); f.victimHead.CFrame=Frame.new(100,2,-20)
			elseif change=="round" then round={}; f.victimHead.CFrame=Frame.new(8,2,-20)
			elseif change=="character" then f.victim.Character,f.victimHum,f.victimRoot,f.victimHead=character("Replacement",V(8,0,-20))
			elseif change=="too-old" then time=9.7; f.victimHead.CFrame=Frame.new(8,2,-20)
			elseif change=="stale-sample" then time=10; f.victimHead.CFrame=Frame.new(8,2,-20)
			elseif change=="disabled" then lag.Enabled=false; f.victimHead.CFrame=Frame.new(8,2,-20) end
			local snapshot=f.history.GetSnapshot(f.victim,f.victim.Character,round,time,f.victimRoot.CFrame,lag)
			near(snapshot.headFrame.Position.X,f.victimHead.Position.X)
		end
	end)
	test("replacement body geometry prevents a historical head bonus across an invalid interpolation",function()
		local f=fixture(); local round=f.main.RoundStats; local lag=Config.LagCompensation
		f.history.Sample(9.8,round,f.main.PlayersInGame,lag)
		f.victim.Character.Torso.Parent=nil; part(f.victim.Character,"Torso",V(0,0,-20),V(2,2,1))
		f.history.Sample(9.9,round,f.main.PlayersInGame,lag)
		local snapshot=f.history.GetSnapshot(f.victim,f.victim.Character,round,9.85,f.victimRoot.CFrame,lag)
		assert(not snapshot.headFrame)
	end)
	print(string.format("%d headshot damage tests passed",passed))
end
