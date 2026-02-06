-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KnivesRemotes = RemotesFolder:WaitForChild("Knife")
local ThrowKnifeRemote = KnivesRemotes:WaitForChild("ThrowKnife")


local StabKnifeRemote = KnivesRemotes:WaitForChild("StabKnife")

-- // MODULES // --
local ThrowKnifeModule = require(script.Parent:WaitForChild("ThrowKnife"))
local StabKnifeModule = require(script.Parent:WaitForChild("StabKnife"))

-- // THROWING KNIFE // --
ThrowKnifeRemote.OnServerEvent:Connect(function(player: Player, camOrigin: Vector3, targetPosition: Vector3, chargeRatio: number)
	ThrowKnifeModule.ThrowKnife(player, camOrigin, targetPosition, chargeRatio)
end)

-- // STABBING KNIFE // --
StabKnifeRemote.OnServerEvent:Connect(function(player : Player)
	StabKnifeModule.Stab(player)
end)

return {}
