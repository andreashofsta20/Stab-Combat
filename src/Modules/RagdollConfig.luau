-- Death presentation only. Damage, kill credit and respawning stay in MainGame.
local Config = {
	Enabled = true,
	LifetimeSeconds = 5,
	MaxCorpses = 32, -- evict the oldest if a busy server reaches this budget
	FolderName = "DeathRagdolls",
	CollisionGroup = "DeathRagdolls",
	CharacterCollisionGroup = "PlayerCharacters",
	MaxInheritedSpeed = 60,
	MaxInheritedAngularSpeed = 10,
	-- Small whole-body nudge away from the hit, plus a separate torso tip.
	-- Speed/Lift are added velocity (studs/sec); TiltImpulse is angular impulse
	-- per torso assembly mass. Keep it modest to tip over without spinning.
	Impact = {
		Default = { Speed = 1, Lift = 0.15, TiltImpulse = 2 },
		Revolver = { Speed = 2.5, Lift = 0.6, TiltImpulse = 2.5 },
		KnifeStab = { Speed = 1.75, Lift = 0.25, TiltImpulse = 2.2 },
		KnifeThrow = { Speed = 2, Lift = 0.4, TiltImpulse = 2.3 },
	},
	Joints = {
		Default = { UpperAngle = 65, TwistLowerAngle = -45, TwistUpperAngle = 45, Friction = 0 },
		Neck = { UpperAngle = 40, TwistLowerAngle = -45, TwistUpperAngle = 45, Friction = 0 },
		Shoulder = { UpperAngle = 100, TwistLowerAngle = -75, TwistUpperAngle = 75, Friction = 0 },
		Hip = { UpperAngle = 55, TwistLowerAngle = -30, TwistUpperAngle = 30, Friction = 0 },
		Waist = { UpperAngle = 30, TwistLowerAngle = -25, TwistUpperAngle = 25, Friction = 0 },
		Elbow = { UpperAngle = 45, TwistLowerAngle = -5, TwistUpperAngle = 5, Friction = 0 },
		Knee = { UpperAngle = 45, TwistLowerAngle = -5, TwistUpperAngle = 5, Friction = 0 },
		Wrist = { UpperAngle = 25, TwistLowerAngle = -15, TwistUpperAngle = 15, Friction = 0 },
		Ankle = { UpperAngle = 25, TwistLowerAngle = -15, TwistUpperAngle = 15, Friction = 0 },
	},
}

assert(Config.LifetimeSeconds > 0 and Config.LifetimeSeconds < math.huge, "Invalid ragdoll lifetime")
assert(Config.MaxCorpses >= 1 and Config.MaxCorpses % 1 == 0, "Invalid ragdoll budget")
return Config
