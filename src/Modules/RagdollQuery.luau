-- Colliding corpse parts can be returned by queries despite CanQuery=false.
-- Exclude their folder explicitly from gameplay and cursor raycasts.
local Config = require(script.Parent.RagdollConfig)
local Query = {}

function Query.GetFolder()
	return workspace:FindFirstChild(Config.FolderName)
end

function Query.Exclude(ignore)
	local folder = Query.GetFolder()
	if folder then table.insert(ignore, folder) end
	return ignore
end

return Query
