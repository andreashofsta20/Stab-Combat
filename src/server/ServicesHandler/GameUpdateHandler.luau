local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")


local function MakeFrameVisible()
    for i , v in pairs(Players:GetPlayers()) do
        local playerGui = v:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local Main = playerGui:FindFirstChild("Main")
            local frame = Main:FindFirstChild("GameUpdate")
            if frame then
                frame.Visible = true
            end
        end
    end
    
end
local function softShutdown()
    MakeFrameVisible()
    task.wait(3)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			TeleportService:Teleport(game.PlaceId, player)
		end)
	end
end

game:BindToClose(function()
    MakeFrameVisible()
	softShutdown()
	task.wait(3)
end)


return {}