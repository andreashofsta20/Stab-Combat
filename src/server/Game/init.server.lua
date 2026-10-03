local ServerStorage = game:GetService("ServerStorage")
local Loader = require(game:GetService("ReplicatedStorage").Modules.StartupLoader)
require(script.Parent.StartupService).LoadGroup(script, {
	Priority = {"SpawnMap", "RoundHandler", "VotingHandler", "MainGame", "RequestKnife", "GameLoop"},
	Tasks = {{Name = "KnifeTemplates", Start = function()
		local knives = Loader.RequireChild(ServerStorage, "Knives")
		assert(knives:IsA("Folder") or knives:IsA("Model"), "ServerStorage.Knives must be a Folder or Model")
		for _, tool in ipairs(knives:GetChildren()) do
			if tool:IsA("Tool") then tool:SetAttribute("IsKnife", true) end
		end
	end}},
	Init = {GameLoop = function(module) module.Start() end},
})
