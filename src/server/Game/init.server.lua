local RecieveTools = require(script:WaitForChild("RequestKnife"))
local Module = require(script:WaitForChild("GameLoop"))
local MainGame = require(script:WaitForChild("MainGame"))
local ServerStorage = game:GetService("ServerStorage")
for _, tool in ipairs(ServerStorage:WaitForChild("Knives"):GetChildren()) do
	tool:SetAttribute("IsKnife", true)
end




