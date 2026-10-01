-- Offsets are relative to Torso (R6) / UpperTorso (R15), measured at the
-- template's Handle, PrimaryPart, or the MeshPart itself.
-- Position uses studs; CFrame.Angles uses radians.
local knifeOffset = CFrame.new(
	-0.189239502, 0.379319191, 0.620000000,
	-0.222041219, -0.644848764, -0.731346548,
	0.238113225, 0.691498339, -0.682006001,
	0.945515692, -0.325576723, 5.85366661e-06
)

-- Includes the +0.15 right and -0.1 up adjustments from your examples.
local revolverBase = CFrame.new(
	-1.14834509, -1.5207468, 0.0278930664,
	1, 3.72879725e-07, -1.06765183e-05,
	1.06830266e-05, -0.0349067077, 0.999390662,
	-2.95584633e-11, -0.999390602, -0.0349067077
)

return {
	Knife = {
		StatName = "EquippedKnife",
		DisplayName = "BackKnife",
		MotorName = "KnifeMotor",
		TemplateFolders = { "KnifeAttachmentTest", "Knives" },
		DefaultOffset = knifeOffset,
		Items = {
			["Ethereal"] = { Offset = knifeOffset },
			["Valentine Knife"] = { Offset = knifeOffset },
			-- Add an entry for each knife that needs a different fit:
			-- ["Bowie"] = {
			--     Offset = CFrame.new(x, y, z)
			--         * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll)),
			--     R15Offset = CFrame.new(x, y, z), -- optional R15 override
			--     TemplateName = "Bowie", -- optional cosmetic template alias
			-- },
		},
	},
	Revolver = {
		StatName = "EquippedGun",
		DisplayName = "SideRevolver",
		MotorName = "RevMotor",
		TemplateFolders = { "RevolverAttachmentTest", "Revolvers" },
		DefaultOffset = revolverBase * CFrame.Angles(math.rad(25), 0, 0),
		Items = {
			["Ethereal Revolver"] = {
				Offset = revolverBase * CFrame.Angles(math.rad(25), 0, 0),
			},
			["Valentine Revolver"] = {
				Offset = revolverBase * CFrame.Angles(
					math.rad(-140), math.rad(-90), math.rad(-180)
				),
			},
		},
	},
}
