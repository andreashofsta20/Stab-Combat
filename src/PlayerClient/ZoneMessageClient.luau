-- // SERVICES // --
local Players = game:GetService("Players")

-- // PLAYER // --
local Player = Players.LocalPlayer

-- // PLAYERGUI // --
local PlayerGui = Player.PlayerGui


-- // UI // --
local GUI = PlayerGui:WaitForChild("Main")

local OutsideZone = GUI:WaitForChild("OutsideZone")
local RecieveInfoRemote = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Zone"):WaitForChild("RecieveClient")


RecieveInfoRemote.OnClientEvent:Connect(function(boolean : boolean)
	if boolean then
		OutsideZone.Visible = true
	else
		OutsideZone.Visible = false
	end
end)

return {}