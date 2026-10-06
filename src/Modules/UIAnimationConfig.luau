return {
	Enabled = true,
	ReducedMotion = false, -- Instant transitions and no item reveal animations.
	-- Attach(frame, "Page") or Attach(frame, {OpenSeconds = 0.3, ...}).
	Profiles = {
		Modal = {OpenSeconds = 0.24, CloseSeconds = 0.14, OpenOffsetPixels = 12, CloseOffsetPixels = 8},
		Page = {OpenSeconds = 0.2, CloseSeconds = 0.1, OpenOffsetPixels = 6, CloseOffsetPixels = 4},
		Popup = {OpenSeconds = 0.2, CloseSeconds = 0.12, OpenOffsetPixels = 8, CloseOffsetPixels = 6},
	},
	-- These already have dedicated presentation controllers.
	ManagedExternally = {Spinner = true, Spectate = true},
	Reveal = {
		Seconds = 0.7,	
		StaggerSeconds = 0.019,
		MaxStaggerSeconds = 0.13,
		MaxCards = 16,
		MaxTargets = 48, -- One combined transparency tween per target.
		MaxNodesPerCard = 24,
		StartTransparency = 1,
	},
	OpenSeconds = 0.24,
	CloseSeconds = 0.14,
	OpenOffsetPixels = 12,
	CloseOffsetPixels = 8,
	TabSeconds = 0.14,
	HoverSeconds = 0.12,
	HoverSizeMultiplier = 1.06,
	SelectedColor = {71, 81, 95},
	DefaultColor = {46, 53, 63},
	AssetBatchSize = 4,
	AssetScanNodesPerFrame = 12,
}
