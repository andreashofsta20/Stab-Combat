-- Keep the shop controller API; images load through Roblox when displayed.
-- No texture preload queue or hierarchy scan is needed.
local Assets = {}

function Assets.New(_root)
	return {
		QueueImage = function(_id) end,
		Destroy = function() end,
	}
end

return Assets
