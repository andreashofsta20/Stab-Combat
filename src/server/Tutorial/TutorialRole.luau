local Config = require(game:GetService("ReplicatedStorage").Modules.TutorialConfig)
local RunService = game:GetService("RunService")
local Role = {}
function Role.IsPreview()
	return RunService:IsStudio() and Config.Studio.EnableSoloPreview==true
end
function Role.IsTutorial()
	local samePlacePrivate = Config.TutorialPlaceId>0 and Config.TutorialPlaceId==Config.MainPlaceId
		and game.PrivateServerId ~= ""
	return (Config.TutorialPlaceId>0 and game.PlaceId==Config.TutorialPlaceId
		and (Config.TutorialPlaceId~=Config.MainPlaceId or game.PrivateServerId~="")) or samePlacePrivate or Role.IsPreview()
end
return Role
