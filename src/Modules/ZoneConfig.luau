return {
	PhasesEnabled = true,
	-- Hold then shrink; fractions are relative to authored initial XZ size.
	Phases = {
		{Hold = 45, Shrink = 30, Fraction = 0.65},
		{Hold = 35, Shrink = 30, Fraction = 0.35},
		{Hold = 25, Shrink = 30, Fraction = 0.12},
		{Hold = 10, Shrink = 20, Fraction = 0},
	},
}
