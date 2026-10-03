-- Actual cosmetic motion and wrapper sources, with small Roblox math stand-ins.
-- These checks do not claim native animation, collision or texture rendering.
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
	Vector.zero = V(0, 0, 0)
	local Frame, fm = {}, {}
	local identity = {1,0,0,0,1,0,0,0,1}
	local function frame(position, matrix) return setmetatable({Position = position, matrix = matrix}, fm) end
	function Frame.new(x, y, z) return frame(type(x) == "table" and x or V(x or 0, y or 0, z or 0), table.clone(identity)) end
	function Frame:VectorToWorldSpace(v)
		local r = self.matrix
		return V(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
	end
	function Frame:Inverse()
		local r = self.matrix
		local inverse = frame(Vector.zero, {r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]})
		inverse.Position = inverse:VectorToWorldSpace(-self.Position)
		return inverse
	end
	function Frame:VectorToObjectSpace(v) return self:Inverse():VectorToWorldSpace(v) end
	function Frame:Lerp(other, alpha)
		local matrix = {}; for i = 1, 9 do matrix[i] = self.matrix[i] + (other.matrix[i] - self.matrix[i]) * alpha end
		return frame(self.Position + (other.Position - self.Position) * alpha, matrix)
	end
	fm.__index = function(cf, key)
		if key == "Rotation" then return frame(Vector.zero, cf.matrix) end
		if key == "LookVector" then return cf:VectorToWorldSpace(V(0, 0, -1)) end
		return Frame[key]
	end
	fm.__mul = function(a, b)
		local matrix = {}
		for row = 0, 2 do for col = 0, 2 do
			local value = 0; for k = 0, 2 do value += a.matrix[row*3+k+1]*b.matrix[k*3+col+1] end
			matrix[row*3+col+1] = value
		end end
		return frame(a.Position + a:VectorToWorldSpace(b.Position), matrix)
	end
	function Frame.Angles(x, y, z)
		local cx,sx,cy,sy,cz,sz = math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
		return frame(Vector.zero,{1,0,0,0,cx,-sx,0,sx,cx})
			* frame(Vector.zero,{cy,0,sy,0,1,0,-sy,0,cy}) * frame(Vector.zero,{cz,-sz,0,sz,cz,0,0,0,1})
	end
	function Frame.fromAxisAngle(axis, angle)
		local x,y,z,c,s,k = axis.X,axis.Y,axis.Z,math.cos(angle),math.sin(angle),1-math.cos(angle)
		return frame(Vector.zero,{c+x*x*k,x*y*k-z*s,x*z*k+y*s,y*x*k+z*s,c+y*y*k,y*z*k-x*s,z*x*k-y*s,z*y*k+x*s,c+z*z*k})
	end
	function Frame:ToAxisAngle()
		local r = self.matrix
		local angle = math.acos(math.clamp((r[1]+r[5]+r[9]-1)/2,-1,1))
		local axis = V(r[8]-r[6],r[3]-r[7],r[4]-r[2])
		return axis.Magnitude < 1e-7 and V(1,0,0) or axis.Unit, angle
	end
	Frame.identity = Frame.new()
	local config = load("Config")
	local shared = load("SharedMotion", {CFrame = Frame, Vector3 = Vector})
	local motion = load("KnifeMotion", {CFrame = Frame, Vector3 = Vector,
		script = {Parent = {RevolverViewmodelMath = "SharedMotion"}}, require = function(name) assert(name == "SharedMotion"); return shared end})
	local settings = config.FirstPerson
	local function step(state, dt, action, body)
		return motion.Step(state, Frame.identity, dt or 1/60, false, false, 0, settings, body, nil, action)
	end
	local function settle(action, hz)
		local state = motion.New(); hz = hz or 60
		for _ = 1, hz*3 do step(state, 1/hz, action) end
		return state
	end
	test("knife uses fully zoomed visibility, thin arms and a single hand", function()
		assert(motion.FirstPerson(false,0.5,settings) and not motion.FirstPerson(false,0.56,settings))
		assert(not motion.FirstPerson(true,0.6,settings) and not motion.FirstPerson(false,1,settings))
		assert(settings.SupportArmEnabled == false and settings.ArmThicknessScale == 0.75)
	end)
	test("idle knife motion adds no charge or attack offset", function()
		local state = settle()
		near(state.actionFrame.Position.Magnitude,0)
		local _, angle = state.actionFrame:ToAxisAngle(); near(angle,0)
	end)
	test("charge raises and draws the knife back gradually", function()
		local state = motion.New(); step(state,1/60,{charging=true,charge=1})
		assert(state.actionFrame.Position.Y > 0 and state.actionFrame.Position.Y < settings.ChargeOffset[2])
		assert(state.actionFrame.Position.Z > 0 and state.actionFrame.Position.Z < settings.ChargeOffset[3])
		for _ = 1, 180 do step(state,1/60,{charging=true,charge=1}) end
		near(state.actionFrame.Position.Y,settings.ChargeOffset[2]); near(state.actionFrame.Position.Z,settings.ChargeOffset[3])
	end)
	test("overcharge stays capped and cannot pull the knife outside its configured pose", function()
		local full, over = settle({charging=true,charge=1}), settle({charging=true,charge=100})
		near((full.actionFrame.Position-over.actionFrame.Position).Magnitude,0)
		for i = 1,9 do near(full.actionFrame.matrix[i],over.actionFrame.matrix[i]) end
	end)
	test("canceling charge returns smoothly while preserving crouch animation", function()
		local state = settle({charging=true,charge=1}); local before = state.actionFrame.Position.Y
		local _, body = step(state,1/60,{},Frame.new(0,-0.4,0))
		assert(state.actionFrame.Position.Y < before and state.actionFrame.Position.Y > 0 and body.Position.Y < 0)
		for _ = 1,180 do step(state,1/60,{},Frame.new(0,-0.4,0)) end
		near(state.actionFrame.Position.Magnitude,0)
		assert(state.animation.Position.Y < -0.2)
	end)
	test("stab thrusts forward and returns after its visual duration", function()
		local state = motion.New(); step(state,1/60,{stabElapsed=settings.StabSeconds/2})
		assert(state.actionFrame.Position.Z < 0)
		for _ = 1,180 do step(state,1/60,{stabElapsed=settings.StabSeconds+1}) end
		near(state.actionFrame.Position.Magnitude,0)
	end)
	test("throw follows through without modifying the supplied camera frame", function()
		local state = motion.New(); local camera = Frame.new(1,2,3)
		motion.Step(state,camera,1/60,false,false,0,settings,nil,nil,{throwElapsed=settings.ThrowSeconds/2})
		assert(state.actionFrame.Position.Z < 0 and state.actionFrame.Position.Y > 0)
		near(camera.Position.X,1); near(camera.Position.Y,2); near(camera.Position.Z,3)
	end)
	test("missing negative and expired action timings remain neutral", function()
		for _, action in ipairs({{}, {stabElapsed=-1,throwElapsed=-1}, {stabElapsed=math.huge,throwElapsed=math.huge}}) do
			near(settle(action).actionFrame.Position.Magnitude,0)
		end
	end)
	test("charge smoothing agrees at 30 and 144 frames per second", function()
		local function simulate(hz)
			local state = motion.New(); for _ = 1,hz do step(state,1/hz,{charging=true,charge=0.7}) end; return state.actionFrame
		end
		local a,b = simulate(30),simulate(144)
		near((a.Position-b.Position).Magnitude,0)
		for i = 1,9 do near(a.matrix[i],b.matrix[i]) end
	end)
	test("zero elapsed render time does not move a charged action", function()
		local state = motion.New(); step(state,0,{charging=true,charge=1}); near(state.actionFrame.Position.Magnitude,0)
	end)
	local function fixture()
		local f = {binds=0,clears=0,updates={},player={},original=0.2}
		local presenter = {Clear=function() f.clears+=1 end,IsActive=function(tool) return tool==f.tool end,
			GetVisualTool=function(tool) return tool==f.tool and f.visual or nil end,
			GetOriginalTransparency=function() return f.original end,
			SetOriginalTransparency=function(_, value) f.original=value end,
			IsFirstPerson=function(tool,tuning) f.probedTuning=tuning; return tool==f.tool end,
			Update=function(...) table.insert(f.updates,table.pack(...)) end}
		local dependencies = {KnifeConfig=config,KnifeViewmodelMotion=motion,KnivesInfo={Knife={}},
			RevolverToolPhysics={New=function(catalog) assert(catalog.Knife); return {BindPlayer=function(player) assert(player==f.player); f.binds+=1 end} end},
			WeaponViewmodel={New=function(options) f.options=options; return presenter end}}
		local rs = {Modules={KnifeConfig="KnifeConfig",KnifeViewmodelMotion="KnifeViewmodelMotion",KnivesInfo="KnivesInfo",RevolverToolPhysics="RevolverToolPhysics"}}
		f.view=load("Viewmodel",{game={GetService=function(_,name) return name=="ReplicatedStorage" and rs or {LocalPlayer=f.player} end},
			script={Parent={WeaponViewmodel="WeaponViewmodel"}},require=function(name) return assert(dependencies[name]) end})
		f.tool,f.visual={},{Name="KnifeSkin"}
		return f
	end
	test("knife creates its own shared presenter and initializes held Tool physics once", function()
		local f=fixture(); f.view.Init(); f.view.Init(); f.view.Update(f.tool,true,1/60)
		assert(f.binds==1 and f.options.Name=="KnifeFirstPerson" and f.options.Motion==motion)
	end)
	test("thrown knife hides its clone only during the existing handle return window", function()
		local f=fixture()
		for _,case in ipairs({{0,true},{0.149,true},{0.15,false},{0.64,false},{0.65,true},{1,true}}) do
			f.view.Update(f.tool,true,1/60,nil,nil,{throwElapsed=case[1]})
			assert(f.updates[#f.updates][10]==case[2])
		end
	end)
	test("knife forwards real posture and charge state without changing gameplay configuration", function()
		local f=fixture(); local body,arm,action={},{},{charging=true,charge=0.8}
		f.view.Update(f.tool,true,0.02,body,arm,action)
		local args=f.updates[1]
		assert(args[1]==f.tool and args[2].FirstPerson==settings and args[3] and not args[4] and not args[5])
		assert(args[7]==body and args[8]==arm and args[9]==action)
		assert(config.Throw.Damage==50 and config.Stab.Damage==100 and config.Throw.MaxOriginDistance==8)
	end)
	test("camera probe original visibility and cleanup forward to the shared manager", function()
		local f=fixture(); assert(f.view.IsActive(f.tool) and f.view.IsFirstPerson(f.tool))
		assert(f.probedTuning.FirstPerson==settings and f.view.GetVisualTool(f.tool)==f.visual)
		near(f.view.GetOriginalTransparency({}),0.2)
		f.view.SetOriginalTransparency({},0.6); near(f.view.GetOriginalTransparency({}),0.6)
		f.view.Clear(); assert(f.clears==1)
	end)
	print("PASS "..passed.." knife viewmodel tests")
end
