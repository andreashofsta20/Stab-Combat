local camera = require(script.Parent.Modules.FirstPersonPostureCamera)
camera.Init()
script.Destroying:Connect(camera.Destroy)
