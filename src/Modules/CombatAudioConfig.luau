return {
	Observer = {
		-- Presentation from accepted server events only; owners already predict their sounds.
		MaxVoices = 24,
		RememberedEvents = 256,
		RollOffMode = "LinearSquare", -- avoid the abrupt quietness of default inverse falloff
		Revolver = {MinDistance = 14, MaxDistance = 260, VolumeScale = 1.1},
		-- The short whoosh needs a wider full-volume area to remain identifiable
		-- during nearby fights. It still fades before the revolver's audible range.
		KnifeThrow = {MinDistance = 16, MaxDistance = 160, VolumeScale = 1.1},
	},
	Hit = {
		SoundId = "rbxassetid://79414317792890",
		Volume = 0.22,
		PlaybackSpeed = 1,
		-- One local sound per server-confirmed hit; misses never play it.
		WeaponKinds = {Revolver = true, KnifeThrow = true},
		MaxActiveSounds = 12,
		Lifetime = 3,
	},
}
