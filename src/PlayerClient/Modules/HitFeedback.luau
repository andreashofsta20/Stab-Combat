local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Config = require(RS.Modules.CombatAudioConfig).Hit
local Feedback = {}
local initialized = false
local active = {}

function Feedback.Init()
	if initialized then return end
	initialized = true
	local remote = RS:WaitForChild("Remotes"):WaitForChild("Knife"):WaitForChild("DamageDealtClient")
	remote.OnClientEvent:Connect(function(_, amount, weaponKind)
		if not Config.WeaponKinds[weaponKind] or type(amount) ~= "number"
			or amount ~= amount or amount <= 0 or amount == math.huge or Config.SoundId == "" then return end
		for index = #active, 1, -1 do if not active[index].Parent then table.remove(active, index) end end
		if #active >= Config.MaxActiveSounds then table.remove(active, 1):Destroy() end
		local sound = Instance.new("Sound")
		sound.Name, sound.SoundId, sound.Volume = "CombatHit", Config.SoundId, Config.Volume
		sound.PlaybackSpeed, sound.Looped, sound.Parent = Config.PlaybackSpeed, false, SoundService
		table.insert(active, sound)
		sound.Ended:Once(function() sound:Destroy() end)
		sound:Play()
		Debris:AddItem(sound, Config.Lifetime)
	end)
end

return Feedback
