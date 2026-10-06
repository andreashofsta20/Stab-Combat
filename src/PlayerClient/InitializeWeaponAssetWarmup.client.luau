local warmup = require(script.Parent.Modules.WeaponAssetWarmup)
warmup.Init()
script.Destroying:Connect(warmup.Destroy)
