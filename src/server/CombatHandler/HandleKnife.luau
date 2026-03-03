-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local KnivesRemotes = RemotesFolder:WaitForChild("Knife")
local ThrowKnifeRemote = KnivesRemotes:WaitForChild("ThrowKnife")


local StabKnifeRemote = KnivesRemotes:WaitForChild("StabKnife")

-- // MODULES // --
local ThrowKnifeModule = require(script.Parent:WaitForChild("ThrowKnife"))
local StabKnifeModule = require(script.Parent:WaitForChild("StabKnife"))
local KNIFE_ACTION_MIN_GAP = 0.05
local lastKnifeActionAt: {[number]: number} = {}

local function canProcessAction(player: Player): boolean
	local now = os.clock()
	local prev = lastKnifeActionAt[player.UserId]
	if prev and (now - prev) < KNIFE_ACTION_MIN_GAP then
		return false
	end
	lastKnifeActionAt[player.UserId] = now
	return true
end

-- // THROWING KNIFE // --
ThrowKnifeRemote.OnServerEvent:Connect(function(player: Player, camOrigin: Vector3, targetPosition: Vector3, chargeRatio: number)
	if typeof(camOrigin) ~= "Vector3" or typeof(targetPosition) ~= "Vector3" or typeof(chargeRatio) ~= "number" then
		return
	end
	if not canProcessAction(player) then
		return
	end
	ThrowKnifeModule.ThrowKnife(player, camOrigin, targetPosition, chargeRatio)
end)

-- // STABBING KNIFE // --
StabKnifeRemote.OnServerEvent:Connect(function(player : Player)
	if not canProcessAction(player) then
		return
	end
	StabKnifeModule.Stab(player)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastKnifeActionAt[player.UserId] = nil
end)

return {}
