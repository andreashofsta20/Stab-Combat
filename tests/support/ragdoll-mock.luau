-- Instance lifecycle and translational frames only; this is not a physics solver.
local Mock = {}
local V, vm = {}, {}
function V.new(x, y, z) return setmetatable({X=x, Y=y, Z=z, kind="Vector3"}, vm) end
function V:Dot(other) return self.X*other.X + self.Y*other.Y + self.Z*other.Z end
function V:Cross(other) return V.new(self.Y*other.Z-self.Z*other.Y, self.Z*other.X-self.X*other.Z, self.X*other.Y-self.Y*other.X) end
vm.__index = function(v, key)
	if key == "Magnitude" then return math.sqrt(v:Dot(v)) end
	if key == "Unit" then return v/v.Magnitude end
	return V[key]
end
vm.__add = function(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub = function(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul = function(a,b) if type(a)=="number" then a,b=b,a end; return V.new(a.X*b,a.Y*b,a.Z*b) end
vm.__div = function(a,b) return V.new(a.X/b,a.Y/b,a.Z/b) end
V.zero = V.new(0,0,0)
local F, fm = {}, {}
function F.new(x,y,z) return setmetatable({Position=type(x)=="table" and x or V.new(x or 0,y or 0,z or 0)},fm) end
function F:PointToObjectSpace(point) return point-self.Position end
function F:PointToWorldSpace(point) return point+self.Position end
fm.__index = function(f,key)
	if key == "Rotation" then return F.identity end
	if key == "LookVector" then return V.new(0,0,-1) end
	return F[key]
end
fm.__mul = function(a,b) return F.new(a.Position+b.Position) end
F.identity = F.new()

local function signal()
	local listeners, s = {}, {}
	function s:Connect(fn)
		local c={Connected=true}; function c:Disconnect() self.Connected=false end
		table.insert(listeners,{fn=fn,c=c}); return c
	end
	function s:Fire(...) for _, listener in ipairs(table.clone(listeners)) do if listener.c.Connected then listener.fn(...) end end end
	function s:Count() local n=0; for _, l in ipairs(listeners) do if l.c.Connected then n+=1 end end; return n end
	return s
end
local methods, meta = {}, {}
meta.__index = function(o,key)
	if methods[key] then return methods[key] end
	if key=="Position" and o.props.CFrame then return o.props.CFrame.Position end
	if o.props[key]~=nil then return o.props[key] end
	if o.signals[key] then return o.signals[key] end
	for _, c in ipairs(o.children) do if c.Name==key then return c end end
end
meta.__newindex = function(o,key,value)
	if key~="Parent" then o.props[key]=value; return end
	local previous=o.props.Parent
	if previous==value then return end
	if previous then local i=table.find(previous.children,o); if i then table.remove(previous.children,i) end end
	o.props.Parent=value
	if value then
		table.insert(value.children,o)
		local ancestor=value
		while ancestor do ancestor.DescendantAdded:Fire(o); ancestor=ancestor.Parent end
	end
end
local function object(class,name,parent)
	local o=setmetatable({props={ClassName=class,Name=name or class,Archivable=true},children={},signals={},attributes={}},meta)
	for _, name in ipairs({"DescendantAdded","Died","CharacterAdded","CharacterRemoving","PlayerAdded","PlayerRemoving","Destroying"}) do o.signals[name]=signal() end
	if class=="Part" or class=="MeshPart" then
		o.CFrame,o.Size,o.Transparency=F.new(),V.new(2,2,1),0
		o.CollisionGroup,o.CanCollide,o.CanQuery,o.CanTouch="Default",true,true,true
		o.AssemblyLinearVelocity,o.AssemblyAngularVelocity,o.AssemblyMass=V.zero,V.zero,2
	end
	o.Parent=parent; return o
end
function methods:IsA(class)
	return class==self.ClassName or class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="MeshPart")
		or class=="LuaSourceContainer" and (self.ClassName=="Script" or self.ClassName=="LocalScript" or self.ClassName=="ModuleScript")
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
	local out={}; for _, c in ipairs(self.children) do table.insert(out,c); for _, n in ipairs(c:GetDescendants()) do table.insert(out,n) end end; return out
end
function methods:FindFirstChild(name) for _, c in ipairs(self.children) do if c.Name==name then return c end end end
function methods:FindFirstChildOfClass(class) for _, c in ipairs(self.children) do if c:IsA(class) then return c end end end
function methods:SetAttribute(name,value) self.attributes[name]=value end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:Destroy()
	if self.Destroyed then return end
	self.Destroying:Fire(); for _, c in ipairs(self:GetChildren()) do c:Destroy() end
	self.Parent=nil; self.Destroyed=true
end
function methods:Clone()
	if not self.Archivable then return nil end
	if self.failClone then error("Clone failure") end
	local copies={}
	local function tree(original)
		local copy=object(original.ClassName,original.Name); copies[original]=copy
		for _, c in ipairs(original.children) do if c.Archivable then tree(c).Parent=copy end end
		return copy
	end
	local copy=tree(self)
	for original, clone in pairs(copies) do
		for key,value in pairs(original.props) do if key~="Parent" then clone[key]=copies[value] or value end end
		clone.attributes=table.clone(original.attributes)
	end
	return copy
end
function methods:CanSetNetworkOwnership() assert(self.Parent and self.Parent.Parent); return true end
function methods:SetNetworkOwner(owner) self.OwnerSet=true; self.Owner=owner end
function methods:ApplyImpulse(impulse)
	self.Impulse = impulse
	self.ImpulseCalls = (self.ImpulseCalls or 0) + 1
end
function methods:ApplyAngularImpulse(impulse)
	self.AngularImpulse = impulse
	self.AngularImpulseCalls = (self.AngularImpulseCalls or 0) + 1
end
function methods:GetPlayers() return self:GetChildren() end

function Mock.New(load, overrides)
	local f={time=0,jobs={},warnings={}}
	f.config=load("Config"); for key,value in pairs(overrides or {}) do f.config[key]=value end
	f.workspace=object("Workspace","Workspace"); f.players=object("Players","Players")
	f.physics={groups={Default=true},relations={}}
	function f.physics:IsCollisionGroupRegistered(name) return self.groups[name]==true end
	function f.physics:RegisterCollisionGroup(name) self.groups[name]=true end
	function f.physics:GetRegisteredCollisionGroups() local out={}; for name in pairs(self.groups) do table.insert(out,{name=name}) end; return out end
	function f.physics:CollisionGroupSetCollidable(a,b,value) self.relations[a..":"..b]=value; self.relations[b..":"..a]=value end
	function f.physics:CollisionGroupsAreCollidable(a,b) local value=self.relations[a..":"..b]; return value==nil or value end
	local services={Players=f.players,PhysicsService=f.physics,ReplicatedStorage={Modules={RagdollConfig="Config"}}}
	f.env={game={GetService=function(_,name) return assert(services[name],name) end},workspace=f.workspace,
		script={Parent={RagdollConfig="Config",RagdollRig="Rig"}},Instance={new=object},Vector3=V,CFrame=F,
		typeof=function(v) return type(v)=="table" and v.kind or type(v) end,
		Enum={HumanoidDisplayDistanceType={None="None"}},task={delay=function(seconds,fn) table.insert(f.jobs,{at=f.time+seconds,fn=fn}) end},
		warn=function(message) table.insert(f.warnings,message) end}
	f.rig=load("Rig",f.env)
	f.env.require=function(name) return assert(({Config=f.config,Rig=f.rig})[name],name) end
	f.service=load("Service",f.env); f.query=load("Query",f.env)
	function f.advance(seconds)
		f.time+=seconds
		for _, job in ipairs(table.clone(f.jobs)) do if job.at<=f.time then table.remove(f.jobs,table.find(f.jobs,job)); job.fn() end end
	end
	function f.character(player, r15)
		local character=object("Model",player.Name,f.workspace); player.Character=character
		local humanoid=object("Humanoid","Humanoid",character); humanoid.Health=100; humanoid.BreakJointsOnDeath=true
		object("Animator","Animator",humanoid); object("LocalScript","Animate",character)
		local function part(name,x,y) local p=object("Part",name,character); p.CFrame=F.new(x,y,0); return p end
		local function joint(name,a,b)
			local motor=object("Motor6D",name,a); motor.Part0,motor.Part1=a,b
			motor.C0,motor.C1=F.new((b.Position-a.Position)/2),F.new((a.Position-b.Position)/2)
			return motor
		end
		local root=part("HumanoidRootPart",0,3)
		local torso=part(r15 and "UpperTorso" or "Torso",0,3)
		local head=part("Head",0,4.5); joint("Neck",torso,head)
		if r15 then
			local lower=part("LowerTorso",0,2); joint("Root",root,lower); joint("Waist",lower,torso)
			for _, side in ipairs({"Left","Right"}) do
				local x=side=="Left" and -1 or 1
				local upper=part(side.."UpperArm",x,3); local arm=part(side.."LowerArm",x,2); local hand=part(side.."Hand",x,1.5)
				joint(side.."Shoulder",torso,upper); joint(side.."Elbow",upper,arm); joint(side.."Wrist",arm,hand)
				local thigh=part(side.."UpperLeg",x,1.5); local leg=part(side.."LowerLeg",x,0.5); local foot=part(side.."Foot",x,0)
				joint(side.."Hip",lower,thigh); joint(side.."Knee",thigh,leg); joint(side.."Ankle",leg,foot)
			end
		else
			joint("RootJoint",root,torso)
			for _, side in ipairs({"Left","Right"}) do local x=side=="Left" and -1.5 or 1.5
				joint(side.." Shoulder",torso,part(side.." Arm",x,3)); joint(side.." Hip",torso,part(side.." Leg",x/3,1))
			end
		end
		local accessory=object("Accessory","Hat",character); local handle=object("Part","Handle",accessory)
		local weld=object("Weld","AccessoryWeld",handle); weld.Part0,weld.Part1=head,handle
		object("Shirt","Shirt",character); object("Decal","Face",head)
		object("Part","Hitbox",character); object("Tool","Revolver",character)
		object("Folder","WeaponAttachments",character); object("ForceField","ForceField",character)
		object("BillboardGui","HealthBar",head); object("ParticleEmitter","Smoke",head).Enabled=true
		player.CharacterAdded:Fire(character)
		return character,humanoid,torso
	end
	function f.player()
		local p=object("Player","Player"..tostring(#f.players:GetPlayers()+1),f.players); f.character(p); f.players.PlayerAdded:Fire(p); return p
	end
	f.object,f.Vector,f.Frame=object,V,F
	return f
end

return Mock
