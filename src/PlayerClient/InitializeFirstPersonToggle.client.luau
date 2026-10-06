local toggle = require(script.Parent.Modules.FirstPersonToggle)
toggle.Init()
script.Destroying:Connect(toggle.Destroy)
