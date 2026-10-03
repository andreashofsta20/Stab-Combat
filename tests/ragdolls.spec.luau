return function(load)
	local mock,passed=load("Mock"),0
	local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); passed+=1; print("PASS "..name) end
	local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a).." ~= "..tostring(b)) end
	local function count(model,class) local total=0; for _, item in ipairs(model:GetDescendants()) do if item:IsA(class) then total+=1 end end; return total end
	local function die(f,player,kind)
		local char=player.Character; f.service.SetImpact(char,kind or "Revolver",f.Vector.new(0,0,-1))
		char.Humanoid.Health=0; return f.service.OnDeath(char)
	end
	test("existing and future avatars preserve joints before death and initialize once",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); f.service.Init()
		assert(p.Character.Humanoid.BreakJointsOnDeath==false and p.Character.Humanoid.Died:Count()==1)
		local later=f.player(); assert(later.Character.Humanoid.BreakJointsOnDeath==false)
		assert(p.Character.Torso.CollisionGroup==f.config.CharacterCollisionGroup)
		local custom=f.object("Part","Custom",p.Character); custom.CollisionGroup="Custom"
		p.Character.DescendantAdded:Fire(custom); assert(custom.CollisionGroup=="Custom")
	end)
	test("R6 corpse preserves clothes and accessories with five sockets and a welded invisible root",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local original=p.Character; original.Archivable=false
		local corpse=die(f,p); assert(corpse and corpse~=original and not original.Archivable)
		assert(count(corpse,"BallSocketConstraint")==5 and count(corpse,"Motor6D")==0)
		assert(corpse.Shirt and corpse.Hat.Handle.AccessoryWeld.Part0==corpse.Head)
		assert(corpse.HumanoidRootPart.RagdollRoot.Part1==corpse.Torso)
		assert(corpse.HumanoidRootPart.Transparency==1 and not corpse.HumanoidRootPart.CanCollide)
		assert(corpse.Torso.CanCollide and not corpse.Hat.Handle.CanCollide)
		assert(not corpse.Humanoid.EvaluateStateMachine and not corpse.Humanoid.RequiresNeck)
		assert(original:GetAttribute("Ragdolled") and original.Torso.Transparency==1 and not original.Hitbox.CanQuery)
	end)
	test("R15 body builds fourteen bounded sockets without rigid limb motors",function()
		local f=mock.New(load); local p=f.player(); f.character(p,true); f.service.Init()
		local corpse=die(f,p); assert(corpse and count(corpse,"BallSocketConstraint")==14 and count(corpse,"Motor6D")==0)
		for _, item in ipairs(corpse:GetDescendants()) do if item:IsA("BallSocketConstraint") then
			assert(item.LimitsEnabled and item.TwistLimitsEnabled and item.Restitution==0)
			near((item.Attachment0.Parent.CFrame:PointToWorldSpace(item.Attachment0.CFrame.Position)
				-item.Attachment1.Parent.CFrame:PointToWorldSpace(item.Attachment1.CFrame.Position)).Magnitude,0)
		end end
	end)
	test("corpse contains no executable scripts tools hitboxes displays spawn shields or animation controller",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local corpse=die(f,p)
		for _, class in ipairs({"LuaSourceContainer","Tool","ForceField","BillboardGui","Animator"}) do assert(count(corpse,class)==0,class) end
		assert(not corpse.Hitbox and not corpse.WeaponAttachments and not corpse.Head.Smoke.Enabled)
	end)
	test("inline deferred and repeated death notifications create only one corpse",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local corpse=die(f,p)
		p.Character.Humanoid.Died:Fire(); assert(f.service.OnDeath(p.Character)==nil)
		assert(#f.workspace.DeathRagdolls:GetChildren()==1 and #f.jobs==1 and corpse.Parent)
	end)
	test("death never destroys a respawned avatar and corpses outlive character replacement",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local original=p.Character; local corpse=die(f,p)
		p.CharacterRemoving:Fire(original); original:Destroy(); local nextCharacter=f.character(p)
		f.advance(2); assert(corpse.Parent and nextCharacter.Parent and nextCharacter.Torso.Transparency==0)
		f.advance(3); assert(corpse.Destroyed and nextCharacter.Parent and nextCharacter.Humanoid.Health==100)
	end)
	test("character removal catches a death before deferred Died and disconnects the old hooks",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local original=p.Character
		original.Humanoid.Health=0; p.CharacterRemoving:Fire(original)
		assert(#f.workspace.DeathRagdolls:GetChildren()==1 and original.Humanoid.Died:Count()==0)
		assert(original.DescendantAdded:Count()==0)
		p.Character=nil; f.players.PlayerRemoving:Fire(p)
		assert(p.CharacterAdded:Count()==0 and p.CharacterRemoving:Count()==0)
	end)
	test("all weapon impacts gently push the entire body and tip the torso once",function()
		for _, kind in ipairs({"Revolver","KnifeStab","KnifeThrow"}) do
			local f=mock.New(load); local p=f.player(); f.service.Init(); local corpse=die(f,p,kind); local torso=corpse.Torso
			assert(torso.OwnerSet and torso.Owner==nil)
			near(torso.Impulse.Z,-f.config.Impact[kind].Speed*torso.AssemblyMass)
			near(torso.Impulse.Y,f.config.Impact[kind].Lift*torso.AssemblyMass)
			assert(torso.AngularImpulse.X<0 and torso.AngularImpulse.Y==0 and torso.AngularImpulse.Z==0)
			assert(torso.AngularImpulseCalls==1)
			for _, part in ipairs(corpse:GetChildren()) do if part:IsA("BasePart") and part~=corpse.PrimaryPart then
				assert(part.ImpulseCalls==1); near(part.Impulse.Z/part.AssemblyMass,torso.Impulse.Z/torso.AssemblyMass)
			end end
		end
	end)
	test("stationary deaths tip away from front back and side hits without adding yaw spin",function()
		for _, direction in ipairs({{0,0,-1},{0,0,1},{1,0,0},{-1,0,0},{1,-2,1}}) do
			local f=mock.New(load); local p=f.player(); f.service.Init()
			local shot=f.Vector.new(table.unpack(direction))
			f.service.SetImpact(p.Character,"Revolver",shot); p.Character.Humanoid.Health=0
			local corpse=f.service.OnDeath(p.Character); local torso=corpse.Torso
			local flat=f.Vector.new(shot.X,0,shot.Z).Unit
			assert(torso.AssemblyLinearVelocity.Magnitude==0 and torso.AssemblyAngularVelocity.Magnitude==0)
			assert(torso.Impulse:Dot(flat)>0)
			assert(torso.AngularImpulse:Cross(f.Vector.new(0,1,0)):Dot(flat)>0,"Torso tipped toward the attacker")
			near(torso.AngularImpulse.Y,0)
			near(torso.Impulse.Magnitude/torso.AssemblyMass,math.sqrt(2.5*2.5+0.6*0.6))
		end
	end)
	test("a vertical hit still nudges and tips the body rather than launching it vertically",function()
		local f=mock.New(load); local p=f.player(); f.service.Init()
		f.service.SetImpact(p.Character,"Revolver",f.Vector.new(0,-1,0)); p.Character.Humanoid.Health=0
		local corpse=f.service.OnDeath(p.Character)
		assert(corpse.Torso.Impulse.Z<0 and corpse.Torso.AngularImpulse.X<0)
		near(corpse.Torso.Impulse.Y/corpse.Torso.AssemblyMass,f.config.Impact.Revolver.Lift)
	end)
	test("welded body parts share a single nudge and the invisible root receives no extra kick",function()
		local f=mock.New(load); local p=f.player(); f.service.Init(); local corpse=p.Character:Clone()
		local torso,motion=f.rig.Build(corpse,p.Character,f.config); corpse.Parent=f.workspace.DeathRagdolls
		corpse["Right Arm"].AssemblyRootPart=corpse["Left Arm"]
		corpse["Left Arm"].AssemblyRootPart=corpse["Left Arm"]
		f.rig.Start(corpse,torso,f.config,{Kind="Revolver",Direction=f.Vector.new(1,0,0)},motion)
		assert((corpse["Right Arm"].ImpulseCalls or 0)+(corpse["Left Arm"].ImpulseCalls or 0)==1)
		assert(not corpse.PrimaryPart.ImpulseCalls and torso.AngularImpulseCalls==1)
	end)
	test("movement is inherited with finite speed limits and invalid impact vectors are ignored",function()
		local f=mock.New(load); local p=f.player(); f.service.Init()
		p.Character.Torso.AssemblyLinearVelocity=f.Vector.new(1000,0,0)
		p.Character.Torso.AssemblyAngularVelocity=f.Vector.new(0,1000,0)
		f.service.SetImpact(p.Character,"Revolver",f.Vector.new(0/0,0,0))
		p.Character.Humanoid.Health=0; local corpse=f.service.OnDeath(p.Character)
		near(corpse.Torso.AssemblyLinearVelocity.Magnitude,f.config.MaxInheritedSpeed)
		near(corpse.Torso.AssemblyAngularVelocity.Magnitude,f.config.MaxInheritedAngularSpeed)
		near(corpse.Torso.Impulse.Z,-f.config.Impact.Default.Speed*corpse.Torso.AssemblyMass)
	end)
	test("corpse budget evicts the oldest and finite timers remove all remaining models",function()
		local f=mock.New(load,{MaxCorpses=2}); f.service.Init()
		local first=die(f,f.player()); local second=die(f,f.player()); local third=die(f,f.player())
		assert(first.Destroyed and second.Parent and third.Parent and #f.workspace.DeathRagdolls:GetChildren()==2)
		f.advance(5); assert(#f.workspace.DeathRagdolls:GetChildren()==0)
	end)
	test("malformed avatars and clone failure leave death visible without leaking a partial corpse",function()
		for _, failure in ipairs({"joints","clone"}) do
			local f=mock.New(load); local p=f.player(); f.service.Init(); local char=p.Character
			if failure=="clone" then char.failClone=true else for _, item in ipairs(char:GetDescendants()) do if item:IsA("Motor6D") then item:Destroy() end end end
			char.Archivable=false; char.Humanoid.Health=0
			assert(f.service.OnDeath(char)==nil and not char.Archivable and char.Torso.Transparency==0)
			assert(#f.workspace.DeathRagdolls:GetChildren()==0 and #f.warnings==1 and #f.jobs==0)
		end
	end)
	test("living avatars and disabled config produce no corpses or death hooks",function()
		local f=mock.New(load); local p=f.player(); assert(f.service.OnDeath(p.Character)==nil)
		local off=mock.New(load,{Enabled=false}); local p2=off.player(); off.service.Init()
		assert(p2.Character.Humanoid.BreakJointsOnDeath and p2.Character.Humanoid.Died:Count()==0)
		p2.Character.Humanoid.Health=0; assert(off.service.OnDeath(p2.Character)==nil)
	end)
	test("query exclusions work before initialization and include the configurable corpse folder",function()
		local f=mock.New(load,{FolderName="TestCorpses"}); local p=f.player()
		local ignore={p.Character}; assert(f.query.Exclude(ignore)==ignore and #ignore==1)
		f.service.Init(); local corpse=die(f,p); assert(corpse.Parent==f.workspace.TestCorpses)
		local filtered=f.query.Exclude({p.Character}); assert(filtered[2]==corpse.Parent)
		assert(not f.physics:CollisionGroupsAreCollidable(f.config.CollisionGroup,f.config.CharacterCollisionGroup))
		assert(not f.physics:CollisionGroupsAreCollidable(f.config.CollisionGroup,f.config.CollisionGroup))
	end)
	print(string.format("%d ragdoll tests passed",passed))
end
