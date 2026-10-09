local RS = game:GetService("ReplicatedStorage")
local Loader = require(RS.Modules.StartupLoader)
local folder = script.Parent.Parent.Tutorial
local remotes = Loader.RequireChild(RS,"Remotes","Folder")
local function child(parent,name,class)
	local instance=parent:FindFirstChild(name)
	if not instance then instance=Instance.new(class); instance.Name=name; instance.Parent=parent end
	assert(instance:IsA(class),"Tutorial remote has an invalid class: "..name)
	return instance
end
local remote=child(child(remotes,"Tutorial","Folder"),"StartTutorial","RemoteEvent")
local config=require(RS.Modules.TutorialConfig)
return require(folder.TutorialCoordinator).New({
	Players=game:GetService("Players"),RS=RS,RunService=game:GetService("RunService"),HttpService=game:GetService("HttpService"),
	Remote=remote,Config=config,Steps=require(RS.Modules.TutorialSteps),
	State=require(folder.TutorialState),Runtime=require(folder.TutorialRuntime),Arena=require(folder.TutorialArena),
	Rewards=require(folder.TutorialRewards),Tickets=require(folder.TutorialTickets),Travel=require(folder.TutorialTeleport),Role=require(folder.TutorialRole),
	Analytics=require(folder.TutorialAnalytics).New(config),
	Profiles=require(script.Parent.Parent.DataStore.ProfileManager),Food=require(script.Parent.Parent.CombatHandler.FoodService),
	MovementConfig=require(RS.Modules.MovementConfig),NPCConfig=require(RS.Modules.TutorialNPCConfig),
	Knives=require(RS.Modules.KnivesInfo),Revolvers=require(RS.Modules.RevolversInfo),DataConfig=require(RS.Modules.DataConfig),
	NewOptions=function() return Instance.new("TeleportOptions") end,
})
