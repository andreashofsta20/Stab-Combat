-- Execute production geometry, VFX and controller lifecycle code with Roblox
-- stand-ins. Native mesh appearance and particle rendering need Studio QA.
return function(load)
	local passed = 0
	local function near(a, b) assert(math.abs(a - b) < 1e-5, tostring(a) .. " ~= " .. tostring(b)) end
	local function test(name, fn)
		local ok, failure = pcall(fn); assert(ok, name .. ": " .. tostring(failure))
		passed += 1; print("PASS " .. name)
	end
	local Vector, vm = {}, {}
	function Vector.new(x, y, z) return setmetatable({X = x, Y = y, Z = z}, vm) end
	function Vector:Dot(b) return self.X*b.X + self.Y*b.Y + self.Z*b.Z end
	function Vector:Cross(b) return Vector.new(self.Y*b.Z-self.Z*b.Y, self.Z*b.X-self.X*b.Z, self.X*b.Y-self.Y*b.X) end
	vm.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v:Dot(v)) end
		if key == "Unit" then return v / v.Magnitude end
		return Vector[key]
	end
	vm.__add = function(a, b) return Vector.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
	vm.__sub = function(a, b) return Vector.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
	vm.__mul = function(a, b) if type(a) == "number" then a, b = b, a end; return Vector.new(a.X*b, a.Y*b, a.Z*b) end
	vm.__div = function(a, b) return Vector.new(a.X/b, a.Y/b, a.Z/b) end
	vm.__unm = function(a) return a * -1 end
	local V = Vector.new
	Vector.zero, Vector.one = V(0,0,0), V(1,1,1)
	local Frame, fm = {}, {}
	local identity = {1,0,0,0,1,0,0,0,1}
	local function frame(position, matrix) return setmetatable({Position = position, matrix = matrix}, fm) end
	function Frame.new(x, y, z) return frame(type(x) == "table" and x or V(x or 0,y or 0,z or 0), table.clone(identity)) end
	function Frame:VectorToWorldSpace(v)
		local r = self.matrix
		return V(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
	end
	function Frame:PointToWorldSpace(v) return self.Position + self:VectorToWorldSpace(v) end
	function Frame:Inverse()
		local r = self.matrix
		local inverse = frame(Vector.zero,{r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]})
		inverse.Position = inverse:VectorToWorldSpace(-self.Position); return inverse
	end
	fm.__index = Frame
	fm.__mul = function(a, b)
		local matrix = {}
		for row = 0,2 do for col = 0,2 do
			local value = 0; for k = 0,2 do value += a.matrix[row*3+k+1]*b.matrix[k*3+col+1] end
			matrix[row*3+col+1] = value
		end end
		return frame(a:PointToWorldSpace(b.Position), matrix)
	end
	function Frame.Angles(x, y, z)
		local cx,sx,cy,sy,cz,sz = math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
		return frame(Vector.zero,{1,0,0,0,cx,-sx,0,sx,cx})
			* frame(Vector.zero,{cy,0,sy,0,1,0,-sy,0,cy}) * frame(Vector.zero,{cz,-sz,0,sz,cz,0,0,0,1})
	end
	function Frame.lookAt(position, target, up)
		local z = (position-target).Unit; local x = up:Cross(z).Unit; local y = z:Cross(x)
		return frame(position,{x.X,y.X,z.X,x.Y,y.Y,z.Y,x.Z,y.Z,z.Z})
	end
	local function signal()
		local s = {listeners = {}}
		function s:Connect(fn)
			local c = {Connected = true, fn = fn}; function c:Disconnect() self.Connected = false end
			table.insert(self.listeners,c); return c
		end
		function s:Fire(...) for _, c in ipairs(table.clone(self.listeners)) do if c.Connected then c.fn(...) end end end
		function s:Count() local n = 0; for _, c in ipairs(self.listeners) do if c.Connected then n += 1 end end; return n end
		return s
	end
	local methods, om = {}, {}
	om.__index = function(o, key)
		if methods[key] then return methods[key] end
		if o.props[key] ~= nil then return o.props[key] end
		for _, c in ipairs(o.children) do if c.Name == key then return c end end
	end
	om.__newindex = function(o, key, value)
		if key == "Parent" then
			if o.props.Parent then local i = table.find(o.props.Parent.children,o); if i then table.remove(o.props.Parent.children,i) end end
			if value then table.insert(value.children,o) end
		end
		o.props[key] = value
	end
	local function object(class, name, parent)
		local o = setmetatable({children = {}, attrs = {}, props = {ClassName = class, Name = name or class,
			Size = V(0.2,4,0.2), CFrame = Frame.new(), Transparency = 0, Archivable = true}},om)
		for _, key in ipairs({"ChildAdded","ChildRemoved","Changed","CharacterAdded","CharacterRemoving","OnClientEvent",
			"WindowFocusReleased","TextBoxFocused","MenuOpened"}) do o[key] = signal() end
		o.Parent = parent; return o
	end
	function methods:IsA(class)
		return self.ClassName == class or class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")
			or class == "BaseScript" and self.ClassName == "LocalScript"
	end
	function methods:GetChildren() return table.clone(self.children) end
	function methods:GetDescendants()
		local out = {}; for _, c in ipairs(self.children) do table.insert(out,c); for _, d in ipairs(c:GetDescendants()) do table.insert(out,d) end end
		return out
	end
	function methods:FindFirstChild(name, recursive)
		for _, c in ipairs(self.children) do if c.Name == name then return c end end
		if recursive then for _, c in ipairs(self.children) do local found = c:FindFirstChild(name,true); if found then return found end end end
	end
	function methods:WaitForChild(name) return assert(self:FindFirstChild(name),"Missing " .. name) end
	function methods:FindFirstChildOfClass(class) for _, c in ipairs(self.children) do if c:IsA(class) then return c end end end
	function methods:GetAttribute(key) return self.attrs[key] end
	function methods:Destroy() for _, c in ipairs(self:GetChildren()) do c:Destroy() end; self.Parent = nil; self.Destroyed = true end
	function methods:Clone()
		local copy = object(self.ClassName,self.Name)
		for key, value in pairs(self.props) do if key ~= "Parent" then copy[key] = value end end
		for _, c in ipairs(self.children) do c:Clone().Parent = copy end
		return copy
	end
	function methods:Play() self.Played = true end
	function methods:Emit(count) self.Emitted = count end
	local env = {Instance = {new = object},Vector3 = Vector,CFrame = Frame,
		typeof = function(v) return getmetatable(v) == vm and "Vector3" or type(v) end}
	local Config, EffectsConfig, Visual = load("Config"), load("EffectsConfig"), load("Visual",env)
	local function skin(length)
		local tool = object("Tool","Knife"); local handle = object("Part","Handle",tool)
		handle.Size, handle.Transparency, handle.CFrame = V(8,8,8),1,Frame.new(15,10,8)
		local blade = object("MeshPart","Blade",tool); blade.Size, blade.CFrame = V(0.2,length,0.2),Frame.new(3,5,8)
		return tool
	end
	local function extent(visual, position, normal)
		local minimum, maximum = math.huge,-math.huge
		for _, record in ipairs(visual.parts) do
			local p = record.part
			if p.Transparency < 1 then
				for _, x in ipairs({-1,1}) do for _, y in ipairs({-1,1}) do for _, z in ipairs({-1,1}) do
					local point = p.CFrame:PointToWorldSpace(V(x*p.Size.X/2,y*p.Size.Y/2,z*p.Size.Z/2))
					local distance = (point-position):Dot(normal.Unit)
					minimum, maximum = math.min(minimum,distance),math.max(maximum,distance)
				end end end
			end
		end
		return minimum, maximum
	end
	test("half the visible knife embeds into walls floors ceilings and slopes for each skin size", function()
		for _, length in ipairs({0.6,4,8}) do
			for _, normal in ipairs({V(1,0,0),V(0,1,0),V(0,-1,0),V(1,1,-1).Unit}) do
				local visual = Visual.Create(skin(length),EffectsConfig.Get("Knife")); local position = V(10,12,14)
				Visual.Stick(visual,position,V(0,0,-1),normal)
				local minimum, maximum = extent(visual,position,normal)
				near(minimum,-length/2); near(maximum,length/2)
			end
		end
	end)
	test("custom embedding leaves the configured visible depth and never swallows the full knife", function()
		local settings = EffectsConfig.Get("Knife"); settings.StickFraction,settings.StickDepth = 0,0.75
		local visual = Visual.Create(skin(4),settings); local pos,normal = V(2,3,4),V(1,0,0)
		Visual.Stick(visual,pos,-normal,normal); local minimum,maximum = extent(visual,pos,normal)
		near(minimum,-0.75); near(maximum,3.25)
		settings.StickDepth = 10; visual = Visual.Create(skin(4),settings)
		Visual.Stick(visual,pos,-normal,normal); minimum,maximum = extent(visual,pos,normal)
		near(minimum,-3.2); near(maximum,0.8)
	end)
	test("file mesh tip overrides and visible mesh offsets influence embedding", function()
		local settings = EffectsConfig.Get("Knife"); settings.TipDistance = 3
		local visual = Visual.Create(skin(4),settings); near(visual.tipDistance,3); near(visual.stickDepth,3)
		local tool = skin(4); local mesh = object("SpecialMesh","Mesh",tool.Blade); mesh.Offset = V(0,5,0)
		visual = Visual.Create(tool,EffectsConfig.Get("Knife")); near(visual.tipDistance,2); near(visual.stickDepth,2)
		near(visual.parts[2].offset.Position.Y,-5)
	end)
	test("projectiles restore template archiving strip runtime effects and cannot collide touch or enter raycasts", function()
		local tool = skin(4); tool.Archivable,tool.Blade.Archivable = false,false
		object("LocalScript","Equip",tool); object("Trail","OldTrail",tool.Blade); object("WeldConstraint","Weld",tool)
		local visual = Visual.Create(tool,EffectsConfig.Get("Knife"))
		assert(tool.Archivable == false and tool.Blade.Archivable == false)
		assert(not visual.model:FindFirstChild("Equip",true) and not visual.model:FindFirstChild("OldTrail",true))
		for _, record in ipairs(visual.parts) do
			local p = record.part; assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
		end
	end)
	local cleanup, world = {},object("Workspace")
	local effectEnv = table.clone(env)
	effectEnv.workspace = world
	effectEnv.game = {GetService = function() return {AddItem = function(_,item,seconds) table.insert(cleanup,{item=item,seconds=seconds}) end} end}
	for _, name in ipairs({"Color3","ColorSequence","ColorSequenceKeypoint","NumberRange","NumberSequence","Vector2"}) do
		effectEnv[name] = {new = function(...) return {...} end,fromRGB = function(...) return {...} end}
	end
	effectEnv.Enum = {NormalId={Front="Front"}}
	local Effects = load("Effects",effectEnv)
	test("one shot impact anchors expire after sparks and retain audio only when configured", function()
		local settings = EffectsConfig.Get("Knife"); Effects.Impact(V(0,0,0),V(0,1,0),settings)
		near(cleanup[#cleanup].seconds,0.25)
		local emitter = cleanup[#cleanup].item:FindFirstChild("Attachment"):FindFirstChild("ParticleEmitter")
		assert(emitter.Emitted == 7 and emitter.Enabled == false and emitter.Rate == 0)
		settings.ImpactSoundId = "rbxassetid://1"; Effects.Impact(V(0,0,0),V(1,0,0),settings)
		near(cleanup[#cleanup].seconds,5); assert(cleanup[#cleanup].item:FindFirstChild("Sound").Played)
		settings.ImpactSoundId,settings.ImpactSparkCount = "",0
		local before = #world:GetChildren(); Effects.Impact(V(0,0,0),V(1,0,0),settings); assert(#world:GetChildren() == before)
	end)
	local function controllerFixture()
		local f = {time=0, delayed={},effects=0}
		local e = table.clone(env); e.workspace = object("Workspace")
		local players = object("Players"); local player = object("Player","LocalPlayer",players); player.UserId=1
		players.LocalPlayer=player; function players:GetPlayerByUserId() return nil end
		local main = object("ScreenGui","Main",object("PlayerGui","PlayerGui",player))
		object("Folder","Frames",main)
		object("Frame","OnClickFrame",object("Frame","OnClick",object("Frame","Ability",object("Frame","StuffContainer",object("Frame","BottomLeft",main)))))
		local rs = object("ReplicatedStorage"); local mods = object("Folder","Modules",rs)
		local remote = object("Folder","Knife",object("Folder","Remotes",rs))
		for _, name in ipairs({"ThrowKnife","ThrewClient","StabKnife","DamageDealtClient"}) do object("RemoteEvent",name,remote) end
		local knives=object("Folder","Knives",rs); skin(4).Parent=knives
		local animations=object("Folder","CombatAnimations",rs)
		for _, name in ipairs({"Charge","ChargeHold","Throw","Stab"}) do object("Animation",name,animations) end
		object("BoolValue","GameActive",rs).Value=true
		local clientMods = object("Folder"); local controller = object("ModuleScript","Controller",clientMods)
		local map = {}; local function module(parent,name,value) map[object("ModuleScript",name,parent)] = value end
		module(mods,"KnifeConfig",Config); module(mods,"KnifeEffectsConfig",EffectsConfig)
		module(mods,"ProjectileMath",load("Math",{script={Parent={KnifeConfig="Config"}},require=function() return Config end,Vector3=Vector,typeof=env.typeof}))
		module(mods,"SprintState",{}); module(mods,"RevolverRaycast",{}); module(mods,"RagdollQuery",{})
		module(clientMods,"KnifeVisual",Visual)
		module(clientMods,"KnifeEffects",{Attach=function() return function() end end,Impact=function() f.effects += 1 end})
		module(clientMods,"KnifeHint",{Init=function() end,Update=function() end})
		module(clientMods,"KnifeViewmodel",{Init=function() end})
		module(clientMods,"SoundHandler",{Sounds={}})
		local input=object("UserInputService"); function input:GetFocusedTextBox() return nil end
		function input:GetMouseLocation() return V(0,0,0) end
		local run = {Heartbeat=signal(),BindToRenderStep=function() end}
		local services={Players=players,ReplicatedStorage=rs,UserInputService=input,RunService=run,TweenService={},GuiService=object("GuiService")}
		e.game={GetService=function(_,name) return assert(services[name],name) end}
		e.script,e.require=controller,function(item) return assert(map[item],item and item.Name) end
		e.Enum={RenderPriority={Camera={Value=100}}}; e.os={clock=function() return f.time end}
		e.task={delay=function(seconds,fn) table.insert(f.delayed,{at=f.time+seconds,fn=fn}) end}
		f.controller=load("Controller",e); f.controller.Init(); f.run,f.remote,f.world=run,remote.ThrewClient,e.workspace
		function f:shot(id,distance,normal)
			self.remote.OnClientEvent:Fire({visualOnly=true,shotId=id,shooterUserId=2,knifeName="Knife",origin=V(0,0,0),
				direction=V(0,0,-1),charge=0,destination=V(0,0,-distance),normal=normal})
		end
		function f:step(seconds)
			self.time += seconds; self.run.Heartbeat:Fire()
			for _, entry in ipairs(table.clone(self.delayed)) do
				if entry.at <= self.time then local i = table.find(self.delayed,entry); if i then table.remove(self.delayed,i); entry.fn() end end
			end
		end
		return f
	end
	test("many flying knives reuse one controller callback and stopped knives do not continue moving", function()
		local f=controllerFixture(); assert(f.run.Heartbeat:Count() == 1)
		for i=1,10 do f:shot(tostring(i),50,V(0,0,1)) end
		assert(f.run.Heartbeat:Count() == 1 and #f.world:GetChildren() == 10)
		f:step(0.05); local blade=f.world:GetChildren()[1].Blade; near(blade.CFrame.Position.Z,-25.8)
		f:step(0.1); near(blade.CFrame.Position.Z,-50); assert(f.effects == 10)
		local stopped=blade.CFrame; f:step(0.1); assert(blade.CFrame == stopped and f.effects == 10)
		f:step(4); assert(#f.world:GetChildren() == 0 and f.run.Heartbeat:Count() == 1)
	end)
	test("late authoritative impacts reconcile once and reset retirement without duplicate particles", function()
		local f=controllerFixture(); f:shot("late",1,nil); f:step(0.01)
		local blade=f.world:GetChildren()[1].Blade
		f.remote.OnClientEvent:Fire({shotId="observer_2_late",accepted=true,position=V(0,0,-2),normal=V(0,0,1)})
		near(blade.CFrame.Position.Z,-2); assert(f.effects == 1)
		f.remote.OnClientEvent:Fire({shotId="observer_2_late",accepted=true,position=V(0,0,-2),normal=V(0,0,1)})
		assert(f.effects == 1); f:step(0.2); assert(#f.world:GetChildren() == 1)
		f:step(4); assert(#f.world:GetChildren() == 0)
	end)
	test("duplicate observer packets and visual caps destroy replaced geometry without retaining callbacks", function()
		local f=controllerFixture(); f:shot("same",50,V(0,0,1)); local old=f.world:GetChildren()[1]
		f:shot("same",50,V(0,0,1)); assert(old.Destroyed and #f.world:GetChildren() == 1)
		for i=1,Config.Presentation.MaxVisuals+5 do f:shot(tostring(i),50,V(0,0,1)) end
		assert(#f.world:GetChildren() == Config.Presentation.MaxVisuals and f.run.Heartbeat:Count() == 1)
		f:step(7); assert(#f.world:GetChildren() == 0)
	end)
	print(string.format("%d knife projectile tests passed",passed))
end
