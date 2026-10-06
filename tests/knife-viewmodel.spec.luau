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
	function Frame:PointToWorldSpace(v) return self.Position + self:VectorToWorldSpace(v) end
	function Frame:Inverse()
		local r = self.matrix
		local inverse = frame(Vector.zero, {r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]})
		inverse.Position = inverse:VectorToWorldSpace(-self.Position)
		return inverse
	end
	function Frame:VectorToObjectSpace(v) return self:Inverse():VectorToWorldSpace(v) end
	function Frame:Lerp(other, alpha)
		-- Native CFrame.Lerp interpolates a rotation, never nine independent
		-- matrix entries. Preserve the rendered grip's orthonormal basis here.
		local delta = self.Rotation:Inverse() * other.Rotation
		local axis, angle = delta:ToAxisAngle()
		local rotation = self.Rotation * Frame.fromAxisAngle(axis, angle * alpha)
		return frame(self.Position + (other.Position - self.Position) * alpha, rotation.matrix)
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
	local geometry = load("Geometry", {CFrame = Frame, Vector3 = Vector,
		game = {GetService = function() return {Modules = {RevolverConfig = "Physics"}} end},
		script = {Parent = {WeaponViewmodelVisibility = "Visibility"}},
		require = function(name) return name == "Physics" and {FirstPersonPhysics = {}} or {} end})
	local function render(pose, camera, grip)
		local handle = {Parent = true, CFrame = Frame.identity}
		local blade = {Parent = true, CFrame = Frame.new(0, 0.8, -0.2)}
		local copy = {}
		local sourceRight, joint = {}, {C0 = grip or Frame.new(0,-1,0), C1 = Frame.identity}
		joint.Part0, joint.Part1 = sourceRight, handle
		function joint:IsA(class) return class == "JointInstance" end
		function sourceRight:FindFirstChild(name) return name == "RightGrip" and joint or nil end
		local visual = {right = {Size = V(1,2,1)}, left = {}, shell = {},
			sourceRight = sourceRight, sourceHandle = handle,
			weaponVisibility = {SetActive = function() end, Guard = function() end},
			pieces = {{part = copy, source = blade}}}
		camera = camera or Frame.identity
		geometry.Place(visual, camera, pose, settings, settings.R6RotationOffset, Frame.identity, true)
		local wrist = camera:Inverse():PointToWorldSpace(visual.right.CFrame:PointToWorldSpace(V(0,-1,0)))
		local tip = camera:Inverse():PointToWorldSpace(copy.CFrame:PointToWorldSpace(V(0,0.4,0)))
		return wrist, tip, camera:Inverse() * visual.right.CFrame
	end
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
	test("the rendered R6 wrist rises in camera space through crouch slide and steep camera angles", function()
		for _, pitch in ipairs({-1.45, 0, 1.45}) do
			for _, drop in ipairs({0, -0.4, -0.8}) do
				local idle, charged = motion.New(), motion.New()
				local camera = Frame.new(10, 7 + drop, -3) * Frame.Angles(pitch, 0.7, 0)
				local posture = Frame.new(0, drop, 0) * Frame.Angles(0.25, -0.2, 0.15)
				local a, b
				for _ = 1, 180 do
					a = motion.Step(idle, camera, 1/60, false, false, 0, settings, posture, nil, {})
					b = motion.Step(charged, camera, 1/60, false, false, 0, settings, posture, nil, {charging = true, charge = 1})
				end
				near(b.Position.Y, settings.ArmPosition[2] + settings.ChargeOffset[2])
				local worldIdle = (camera * a * Frame.Angles(math.pi/2, 0, 0)):PointToWorldSpace(V(0, -1, 0))
				local worldCharged = (camera * b * Frame.Angles(math.pi/2, 0, 0)):PointToWorldSpace(V(0, -1, 0))
				local rise = camera:Inverse():PointToWorldSpace(worldCharged).Y - camera:Inverse():PointToWorldSpace(worldIdle).Y
				assert(rise > 1.3 and rise < 2.7, tostring(rise))
			end
		end
	end)
	test("fully charged hand stays high through the source ChargeHold animation transition", function()
		local state = motion.New(); local charge = {charging = true, charge = 1}
		local held
		for _ = 1, 180 do held = step(state,1/60,charge) end
		local wrist = (held * Frame.Angles(math.pi/2,0,0)):PointToWorldSpace(V(0,-1,0))
		assert(wrist.Y > 0.5, "full charge must show a high overhand grip")
		-- The real hold clip, walking bob and camera sway change beneath the pose.
		for i = 1, 600 do
			local result = motion.Step(state, Frame.Angles(math.sin(i)*0.7,math.cos(i)*0.7,0),1/60,false,false,16,settings,
				Frame.new(0,-0.4,0)*Frame.Angles(-0.3,0.2,0),Frame.Angles(-0.8,0,0),charge)
			near((result.Position-held.Position).Magnitude,0)
			for n = 1,9 do near(result.matrix[n],held.matrix[n]) end
		end
		local lowered = step(state,1/60,{})
		assert(lowered.Position.Y < held.Position.Y and lowered.Position.Y > settings.ArmPosition[2])
		for _ = 1,180 do lowered = step(state,1/60,{}) end
		near(lowered.Position.Y, settings.ArmPosition[2])
	end)
	test("entering first person already fully charged reaches the same held pose", function()
		local state = motion.New(); local result
		for _ = 1,180 do result = step(state,1/60,{charging=true,charge=1},Frame.new(0,-0.4,0)) end
		near(result.Position.Y,settings.ArmPosition[2]+settings.ChargeOffset[2])
		local fresh = motion.New(); local idle = step(fresh,1/60,{})
		assert(idle.Position.Y < settings.ArmPosition[2]); near(fresh.chargeBlend,0)
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
	test("stab prepares then drives the whole arm forward with a held grip before recovering", function()
		local state = settle()
		step(state, 1/60, {stabElapsed = settings.StabSeconds * settings.StabWindupFraction})
		assert(state.actionFrame.Position.X > 0 and state.actionFrame.Position.Z > 0)
		step(state, 1/60, {stabElapsed = settings.StabSeconds * settings.StabThrustFraction})
		near(state.actionFrame.Position.X, settings.StabOffset[1])
		near(state.actionFrame.Position.Z, settings.StabOffset[3])
		assert(state.actionFrame.Position.X < -0.25 and state.actionFrame.Position.Z < -1.2)
		local _, angle = state.actionFrame:ToAxisAngle(); assert(angle < math.rad(18))
		local extended = state.actionFrame
		step(state, 1/60, {stabElapsed = settings.StabSeconds * (settings.StabThrustFraction + settings.StabHoldFraction) / 2})
		near((state.actionFrame.Position - extended.Position).Magnitude, 0)
		for index = 1,9 do near(state.actionFrame.matrix[index], extended.matrix[index]) end
		step(state, 1/60, {stabElapsed = settings.StabSeconds})
		near(state.actionFrame.Position.Magnitude, 0)
		local _, recovered = state.actionFrame:ToAxisAngle(); near(recovered, 0)
	end)
	test("the actual renderer moves both wrist and blade forward rather than swinging around the arm center", function()
		for _, pitch in ipairs({-1.4,0,1.4}) do
			for _, grip in ipairs({Frame.new(0,-1,0), Frame.new(0.1,-0.9,0.05) * Frame.Angles(0.1,0.3,-0.2)}) do
				local state = settle()
				local camera = Frame.new(7,3,-2) * Frame.Angles(pitch,0.7,0)
				local prepared = motion.Step(state,camera,1/60,false,false,24,settings,
					Frame.Angles(-0.8,0.4,0.2),Frame.Angles(1.2,-0.4,0),
					{stabElapsed = settings.StabSeconds * settings.StabWindupFraction})
				local extended = motion.Step(state,camera,1/60,false,false,24,settings,
					Frame.Angles(0.8,-0.4,-0.2),Frame.Angles(-1.2,0.4,0),
					{stabElapsed = settings.StabSeconds * settings.StabThrustFraction})
				local preparedWrist, preparedTip, preparedArm = render(prepared,camera,grip)
				local extendedWrist, extendedTip, extendedArm = render(extended,camera,grip)
				local wristTravel, bladeTravel = extendedWrist-preparedWrist, extendedTip-preparedTip
				near(wristTravel.Z, settings.StabOffset[3] - settings.StabWindupOffset[3])
				assert(wristTravel.Z < -1.5 and math.abs(wristTravel.X) < 0.5)
				near((wristTravel-bladeTravel).Magnitude,0)
				for index=1,9 do near(preparedArm.matrix[index],extendedArm.matrix[index]) end
			end
		end
	end)
	test("rendered extension remains readable for multiple frames at 30 60 and 144 FPS", function()
		for _, hz in ipairs({30,60,144}) do
			local state = settle(nil,hz)
			local idle = step(state,1/hz,{})
			local idleWrist, idleTip = render(idle)
			local heldFrames, fullFrames, furthest = 0,0,0
			for index=0, math.ceil(settings.StabSeconds*hz) do
				local elapsed = index/hz
				local pose = step(state,1/hz,{stabElapsed=elapsed})
				local wrist, tip = render(pose)
				furthest = math.min(furthest,wrist.Z-idleWrist.Z)
				if wrist.Z-idleWrist.Z < -1.1 and tip.Z-idleTip.Z < -1.1 then heldFrames += 1 end
				if elapsed >= settings.StabSeconds*settings.StabThrustFraction
					and elapsed <= settings.StabSeconds*settings.StabHoldFraction then
					fullFrames += 1
					near(state.actionFrame.Position.Z,settings.StabOffset[3])
				end
			end
			assert(furthest < -1.25 and heldFrames/hz > 0.07 and fullFrames >= math.floor(hz*0.06),tostring(hz))
			near(state.actionFrame.Position.Magnitude,0)
		end
	end)
	test("first-person stab ignores competing character animation during the complete thrust and held extension", function()
		for _, hz in ipairs({30,60,144}) do
			local neutral, animated = settle(nil,hz), settle(nil,hz)
			for _, fraction in ipairs({settings.StabWindupFraction,0.3,settings.StabThrustFraction,0.5,settings.StabHoldFraction}) do
				local attack = {stabElapsed=settings.StabSeconds*fraction}
				local a = motion.Step(neutral,Frame.identity,1/hz,false,false,0,settings,nil,nil,attack)
				local b = motion.Step(animated,Frame.Angles(0.7,1.2,0),1/hz,false,false,32,settings,
					Frame.new(0.2,-0.3,0.1)*Frame.Angles(0.8,0.5,-0.4),Frame.Angles(-1.4,0.5,0.3),attack,
					{airborne=true})
				near((a.Position-b.Position).Magnitude,0)
				for index=1,9 do near(a.matrix[index],b.matrix[index]) end
			end
		end
	end)
	test("a rapid tap then held charge finishes the rendered stab before raising the hand at 30 60 and 144 FPS", function()
		for _, hz in ipairs({30,60,144}) do
			local plain, held = settle(nil,hz), settle(nil,hz)
			for index=0, math.floor(settings.StabSeconds*hz) do
				local elapsed = index/hz
				if elapsed < settings.StabSeconds then
					local heldFor = math.max(0,elapsed-0.025)
					local action = {stabElapsed=elapsed,holdingCharge=elapsed>=0.025,
						charging=heldFor>=config.Throw.HoldThreshold,charge=heldFor/config.Throw.MaxChargeTime}
					local a = step(plain,1/hz,{stabElapsed=elapsed})
					local b = step(held,1/hz,action)
					local wristA,tipA = render(a); local wristB,tipB = render(b)
					near((wristA-wristB).Magnitude,0); near((tipA-tipB).Magnitude,0)
					near(held.chargeBlend,0)
					assert(action.charging==(heldFor>=config.Throw.HoldThreshold))
					near(action.charge,heldFor/config.Throw.MaxChargeTime)
				end
			end
			local amount = (settings.StabSeconds-0.025)/config.Throw.MaxChargeTime
			local visible = step(held,1/hz,{stabElapsed=settings.StabSeconds,charging=true,charge=amount})
			assert(held.actionFrame.Position.Y > 0 and held.actionFrame.Position.Y < settings.ChargeOffset[2]*(0.35+amount*0.65))
			assert(held.chargeBlend > 0 and held.chargeBlend < 1)
			for _=1,hz*2 do visible = step(held,1/hz,{stabElapsed=settings.StabSeconds+1,charging=true,charge=1}) end
			local charged = step(settle({charging=true,charge=1},hz),1/hz,{charging=true,charge=1})
			local wristA,tipA = render(visible); local wristB,tipB = render(charged)
			near((wristA-wristB).Magnitude,0); near((tipA-tipB).Magnitude,0)
		end
	end)
	test("canceling a deferred charge cannot raise the hand after the stab has recovered", function()
		for _, hz in ipairs({30,60,144}) do
			local plain, canceled = settle(nil,hz), settle(nil,hz)
			for index=0, math.ceil((settings.StabSeconds+0.3)*hz) do
				local elapsed = index/hz
				local a = step(plain,1/hz,{stabElapsed=elapsed})
				local b = step(canceled,1/hz,{stabElapsed=elapsed,charging=elapsed>=0.23 and elapsed<0.3,
					charge=math.max(0,elapsed-0.025),holdingCharge=elapsed<0.3})
				local wristA,tipA = render(a); local wristB,tipB = render(b)
				near((wristA-wristB).Magnitude,0); near((tipA-tipB).Magnitude,0)
				near(canceled.chargeBlend,0)
			end
			near(canceled.actionFrame.Position.Magnitude,0)
		end
	end)
	test("a new released throw takes sole control of the rendered hand and cannot resurrect the old stab", function()
		for _, hz in ipairs({30,60,144}) do
			local oldStab, onlyThrow = settle(nil,hz), settle(nil,hz)
			for index=0, math.floor(0.2*hz) do
				local elapsed = index/hz
				step(oldStab,1/hz,{stabElapsed=elapsed,charging=elapsed>=0.18,charge=elapsed})
			end
			local lastPose
			for index=0, math.ceil((settings.ThrowSeconds+0.3)*hz) do
				local elapsed = index/hz
				local a = step(onlyThrow,1/hz,{throwElapsed=elapsed})
				local b = step(oldStab,1/hz,{stabElapsed=0.2+elapsed,throwElapsed=elapsed,charging=false,charge=0.2})
				local wristA,tipA = render(a); local wristB,tipB = render(b)
				near((wristA-wristB).Magnitude,0); near((tipA-tipB).Magnitude,0)
				for matrixIndex=1,9 do near(a.matrix[matrixIndex],b.matrix[matrixIndex]) end
				lastPose = b
			end
			assert(lastPose and oldStab.actionFrame.Position.Magnitude < 0.002)
		end
		-- Even an unusually early new throw must retire the old stab after the
		-- throw pulse ends; gameplay admission remains the controller's concern.
		local state = settle(); step(state,1/60,{stabElapsed=0.15})
		step(state,1/60,{stabElapsed=0.16,throwElapsed=0})
		step(state,1/60,{stabElapsed=0.4,throwElapsed=0.39})
		near(state.actionFrame.Position.Magnitude,0)
	end)
	test("a newer stab clears an older charge or throw pose instead of stacking its rotation", function()
		for _, previous in ipairs({{charging=true,charge=1},{throwElapsed=0.1}}) do
			local stale, reference = settle(previous),settle()
			for _, elapsed in ipairs({0,0.07,0.16,0.22,0.3,0.42}) do
				local a = step(reference,1/60,{stabElapsed=elapsed})
				local b = step(stale,1/60,{stabElapsed=elapsed,throwElapsed=0.2+elapsed})
				local wristA,tipA = render(a); local wristB,tipB = render(b)
				near((wristA-wristB).Magnitude,0); near((tipA-tipB).Magnitude,0)
				near(stale.chargeBlend,0)
			end
		end
	end)
	test("stab pose follows elapsed action time equally at 30 60 and 144 FPS", function()
		local function simulate(hz, elapsed)
			local state = settle(nil, hz)
			for index = 0, math.floor(elapsed * hz) do step(state, 1/hz, {stabElapsed = index / hz}) end
			step(state, 1/hz, {stabElapsed = elapsed})
			return state.actionFrame
		end
		for _, fraction in ipairs({0, 0.1, 0.18, 0.3, 0.38, 0.5, 0.56, 0.8, 1}) do
			local reference = simulate(60, settings.StabSeconds * fraction)
			for _, hz in ipairs({30, 144}) do
				local pose = simulate(hz, settings.StabSeconds * fraction)
				near((pose.Position - reference.Position).Magnitude, 0)
				for index = 1, 9 do near(pose.matrix[index], reference.matrix[index]) end
			end
		end
	end)
	test("canceling or rebuilding a stab cannot retain an extended arm on the next equipped knife", function()
		local state = settle()
		step(state,1/60,{stabElapsed=settings.StabSeconds*0.5})
		assert(state.actionFrame.Position.Z < -1.2)
		step(state,1/60,{})
		near(state.actionFrame.Position.Magnitude,0)
		local rebuilt = motion.New()
		local idle = step(rebuilt,1/60,{})
		local restarted = step(state,1/60,{stabElapsed=0})
		near(rebuilt.actionFrame.Position.Magnitude,0)
		near(state.actionFrame.Position.Magnitude,0)
		assert(idle.Position.Z > restarted.Position.Z-0.1)
	end)
	test("new stabs restart at neutral and malformed timings cannot poison the action pose", function()
		local state = settle()
		step(state, 1/60, {stabElapsed = settings.StabSeconds * settings.StabThrustFraction})
		assert(state.actionFrame.Position.X < 0)
		for _, elapsed in ipairs({0, -1, math.huge, 0/0}) do
			step(state, 1/60, {stabElapsed = elapsed, throwElapsed = 0/0})
			near(state.actionFrame.Position.Magnitude, 0)
		end
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
