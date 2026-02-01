local Module = {}
local Players = game:GetService("Players")



function Module.GetThumbnail(UserId)
	local i , v = pcall(function()
		return Players:GetUserThumbnailAsync(UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)

	if i then
		if v then
			return v
		end
	else
		print("couldnt find")
	end
end



return Module	
