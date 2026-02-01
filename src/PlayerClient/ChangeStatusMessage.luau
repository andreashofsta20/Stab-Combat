
local RemotesFolder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local ChangeStatusRecieveRemote = RemotesFolder:WaitForChild("ChangeStatus")

local Player = game.Players.LocalPlayer

if not Player then warn("couldnt find player") 
	return
end


local Gui = Player.PlayerGui:WaitForChild("Main")

local StatusTextLabel = Gui:WaitForChild("SystemTexts"):WaitForChild("Status")



local function ChangeStats(arg : string)
	StatusTextLabel.Text = arg or "Error 101: No status recieved"
end




if ChangeStatusRecieveRemote then
	ChangeStatusRecieveRemote.OnClientEvent:Connect(function(arg : string)
		ChangeStats(arg)
	end)
end


return {}