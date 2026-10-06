-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
-- // REMOTES // --
local StartGameClientFolder = RemotesFolder:WaitForChild("StartGameClient")
local RecieveTools = StartGameClientFolder:WaitForChild("RecieveTools")

local RequestKnife = StartGameClientFolder:WaitForChild("RequestKnife")


-- // MAIN FUNCTIONS // --

RecieveTools.OnClientEvent:Connect(function()
	task.wait(0.5)
	RequestKnife:FireServer()
end)


-- MainGame.WipeTools owns removal on the server. Never destroy its Tool replicas
-- here: a delayed wipe can arrive after the owner has already equipped again.
-- Character child events update the hotbar when authoritative removal replicates.

return {}
