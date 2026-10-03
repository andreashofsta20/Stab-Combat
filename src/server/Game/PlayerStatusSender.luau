local StatusReciever = {}
local RemotesFolder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local SendStatusRemote = RemotesFolder:WaitForChild("ChangeStatus")


function StatusReciever.EditClientStatus(StatusText : string)
	local RS = game:GetService("ReplicatedStorage")
	if RS:GetAttribute("GameStatus") == StatusText then return end
	RS:SetAttribute("GameStatus", StatusText)
	SendStatusRemote:FireAllClients(StatusText)
end



return StatusReciever
