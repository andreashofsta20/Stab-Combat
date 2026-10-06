-- Fixed F input; one small wrist tilt, brief hold, then neutral. Camera-copy only.
return {
	Key = "F", CooldownSeconds = 0.5, ReturnSeconds = 0.14,
	EquipGraceSeconds = 0.2, AfterActionSeconds = 0.4, MaxCameraDistance = 0.6,
	PostureAttribute = "FirstPersonMovementPosture",
	Revolver = {
		Duration = 5,
		Frames = {
			{Time = 0, Position = {0, 0, 0}, Rotation = {0, 0, 0}},
			{Time = 0.32, Position = {-0.04, 0.035, 0}, Rotation = {-3, -8, -18}},
			{Time = 0.62, Position = {-0.04, 0.035, 0}, Rotation = {-3, -8, -18}},
			{Time = 1, Position = {0, 0, 0}, Rotation = {0, 0, 0}},
		},
	},
	Knife = {
		Duration = 5,
		Frames = {
			{Time = 0, Position = {0, 0, 0}, Rotation = {0, 0, 0}},
			{Time = 0.32, Position = {-0.035, 0.04, 0}, Rotation = {-5, 10, -22}},
			{Time = 0.62, Position = {-0.035, 0.04, 0}, Rotation = {-5, 10, -22}},
			{Time = 1, Position = {0, 0, 0}, Rotation = {0, 0, 0}},
		},
	},
}
