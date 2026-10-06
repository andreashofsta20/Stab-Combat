local audio = require(script.Parent.Modules.RemoteWeaponAudio)
script.Destroying:Connect(audio.Destroy)
audio.Init()
