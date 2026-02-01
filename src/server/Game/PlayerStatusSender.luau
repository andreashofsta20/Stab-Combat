local StatusReciever = {}
local RemotesFolder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local SendStatusRemote = RemotesFolder:WaitForChild("ChangeStatus")


function StatusReciever.EditClientStatus(StatusText : string)
	SendStatusRemote:FireAllClients(StatusText)
end



return StatusReciever