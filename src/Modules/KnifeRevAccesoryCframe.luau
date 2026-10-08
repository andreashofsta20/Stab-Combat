-- Offsets are relative to Torso (R6) / UpperTorso (R15), measured at the
-- template's Handle, PrimaryPart, or the MeshPart itself.
-- Position uses studs; CFrame.Angles uses radians.
local knifeOffset = CFrame.new(
	-0.189239502, 0.379319191, 0.620000000,
	-0.222041219, -0.644848764, -0.731346548,
	0.238113225, 0.691498339, -0.682006001,
	0.945515692, -0.325576723, 5.85366661e-06
)
local standardKnifeOffset = CFrame.new(
	-0.289943695, 0.179214478, 0.553275108,
	-0.042444229, -0.682285190, -0.729852915,
	-0.055117186, 0.730997860, -0.680150211,
	0.997577250, 0.011358991, -0.068632305
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
			["Ethereal"] = {
				Offset = CFrame.new(
					0.509431839, -0.561836243, 0.521640778,
					-0.039632343, -0.676248074, -0.735607445,
					-0.125529006, 0.733722866, -0.667752445,
					0.991298199, 0.065875500, -0.113967910
				),
			},
			["Valentine Knife"] = {
				Offset = CFrame.new(
					0.505278587, -0.514328003, 0.611926317,
					0.061837211, -0.660243273, -0.748501837,
					0.036866199, 0.750936151, -0.659344971,
					0.997405052, 0.013177730, 0.070776381
				),
			},
			["Void Strike"] = {
				Offset = CFrame.new(
					0.757263184, 0.983345032, 0.682749748,
					-0.043813076, -0.782442510, -0.621179461,
					0.007296102, -0.622010708, 0.782974601,
					-0.999013305, 0.029772209, 0.032961003
				),
			},
			["Frostbite"] = {
				Offset = CFrame.new(
					-0.087934494, 0.270317078, 0.628620148,
					0.016174495, -0.680602431, -0.732474208,
					-0.066936493, 0.730189681, -0.679957867,
					0.997626185, 0.060027391, -0.033746600
				),
			},
			["Bayonet"] = { Offset = standardKnifeOffset },
			["Butterfly"] = {
				Offset = CFrame.new(
					-0.106981277, 0.056068420, 0.559507370,
					-0.002372155, 0.681266844, -0.732031465,
					-0.026135832, 0.731741130, 0.681081295,
					0.999655664, 0.020747839, 0.016069680
				),
			},
			["Skeleton"] = {
				Offset = CFrame.new(
					-0.099523544, 0.164985657, 0.561218262,
					-0.042478204, -0.682256162, -0.729878128,
					-0.055758506, 0.731017947, -0.680076361,
					0.997540414, 0.011808515, -0.069093913
				),
			},
			["Flip"] = {
				Offset = CFrame.new(
					-0.043319702, 0.121879578, 0.559555054,
					-0.042483509, -0.682288051, -0.729847908,
					-0.054985806, 0.730996966, -0.680161655,
					0.997582793, 0.011235870, -0.068571307
				),
			},
			["Karambit"] = {
				Offset = CFrame.new(
					-0.129875183, -0.073829651, 0.545019150,
					-0.042324960, -0.227204710, -0.972926855,
					-0.055805176, 0.972816825, -0.224751532,
					0.997544169, 0.044781722, -0.053853691
				),
			},
			["Huntsman"] = {
				Offset = CFrame.new(
					0.016946793, 0.054618835, 0.560480118,
					-0.042476118, -0.682248831, -0.729885101,
					-0.056247160, 0.731018960, -0.680035114,
					0.997512937, 0.012168765, -0.069425359
				),
			},
			["Shadow Dagger"] = {
				Offset = CFrame.new(
					-0.053272247, 0.072265625, 0.555988312,
					-0.042491704, -0.682309985, -0.729827046,
					-0.054068133, 0.730986714, -0.680246353,
					0.997632802, 0.010555640, -0.067952096
				),
			},
			["Gut Knife"] = {
				Offset = CFrame.new(
					-0.025944233, 0.043067932, 0.557350159,
					-0.042489827, -0.682278097, -0.729857087,
					-0.054253608, 0.731014550, -0.680201650,
					0.997622669, 0.010695770, -0.068076663
				),
			},
			["Bowie"] = {
				Offset = CFrame.new(
					-0.010316849, 0.083938599, 0.560897827,
					-0.007152796, -0.682218790, -0.731113076,
					-0.023284908, 0.731047332, -0.681929529,
					0.999703407, 0.012146324, -0.021114349
				),
			},
			["Ice Knife"] = {
				Offset = CFrame.new(
					 0.505278587, -0.58, 0.611926317,
					 0.061837211, -0.660243273, -0.748501837,
				 0.036866199, 0.750936151, -0.659344971,
				 0.997405052, 0.013177730, 0.070776381
				),
			},

			["Nature Knife"] = {
				Offset = CFrame.new(
			0.42, -0.58, 0.611926317,
			0.061837211, -0.660243273, -0.748501837,
			0.036866199, 0.750936151, -0.659344971,
			0.997405052, 0.013177730, 0.070776381
			),
			},
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
			["Void Strike Revolver"] = {
				Offset = CFrame.new(0, 0.3, 0.1)
					* revolverBase
					* CFrame.Angles(math.rad(30), 0, 0),
			},
		},
	},
}
