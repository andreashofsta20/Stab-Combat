local ServerStorage = game:GetService("ServerStorage")
local StartupLoader = require(game:GetService("ReplicatedStorage").Modules.StartupLoader)
local function mapTemplate(name)
	local template = StartupLoader.RequireChild(ServerStorage, name)
	assert(template:IsA("Model") or template:IsA("Folder"), "ServerStorage." .. name .. " must be a Model or Folder")
	return template
end
local Maps = {
	
	

	
	["Tropical Island"] = {
		
		MapFolder = mapTemplate("Tropical Island"),
		Name = "Tropical Island",
		VotingImage = "rbxassetid://70452409071350",
		ResultsImage = "rbxassetid://134309678506763"
		
	},
	
	
	["Cargo Port"] = {

		MapFolder = mapTemplate("Cargo Port"),
		Name = "Cargo Port",
		VotingImage = "rbxassetid://80627568706730",
		ResultsImage = "rbxassetid://110373121452497"

	},
	
	
	
	["Grids"] = {

		MapFolder = mapTemplate("Grids"),
		Name = "Grids",
		VotingImage = "rbxassetid://82181977781980",
		ResultsImage = "rbxassetid://71138965019130"

	},
	
	
	["Classic ROBLOX"] = {

		MapFolder = mapTemplate("Classic ROBLOX"),
		Name = "Classic ROBLOX",
		VotingImage = "rbxassetid://83806131745447",
		ResultsImage = "rbxassetid://134969036195314"

	},

	
	
	
	
	


	
	
}

return Maps
