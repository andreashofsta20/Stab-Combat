local RS = game:GetService("ReplicatedStorage")
local Loader = require(RS.Modules.StartupLoader)
local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local remotes = Loader.RequireChild(RS, "Remotes", "Folder")
local tutorial = Loader.RequireChild(remotes, "Tutorial", "Folder")
local remote = Loader.RequireChild(tutorial, "StartTutorial", "RemoteEvent")

remote.OnServerEvent:Connect(function(player)
	local profile = Profiles.GetProfile(player)
	if player:GetAttribute("DataReady") ~= true or not profile or not profile:IsActive() then return end
	if profile.Data.FirstTimePlaying == false then
		profile.Data.FirstTimePlaying = true
		remote:FireClient(player)
	end
end)
return {}
