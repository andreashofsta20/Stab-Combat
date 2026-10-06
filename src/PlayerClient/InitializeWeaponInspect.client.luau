local inspect = require(script.Parent.Modules.WeaponInspectController)
inspect.Init()
script.Destroying:Connect(inspect.Destroy)
