local Profiles = require(script.Parent.Parent.DataStore.ProfileManager)
local Math = require(game:GetService("ReplicatedStorage").Modules.CompetitiveStats)
local Stats = {}
for _, method in ipairs({"Hit","Kill","Death","Round"}) do
	Stats[method] = function(player,...)
		if player:GetAttribute("PracticeActive") == true or player:GetAttribute("DataReady") ~= true then return end
		local profile = Profiles.GetProfile(player)
		if profile and profile:IsActive() then Math[method](profile.Data,...) end
	end
end
return Stats
