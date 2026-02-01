local CombatHandler = script:WaitForChild("CombatHandler")
local Game = script:WaitForChild("Game")
local DataStore = script:WaitForChild("DataStore")
local ServicesHandler = script:WaitForChild("ServicesHandler")


local Module = require(DataStore.OnJoined)
local Module2 = require(DataStore:WaitForChild("KeyBindHandler"))

local RecieveTools = require(Game:WaitForChild("RequestKnife"))
local Module3 = require(Game:WaitForChild("GameLoop"))
local MainGame = require(Game:WaitForChild("MainGame"))
local ServerStorage = game:GetService("ServerStorage")
for _, tool in ipairs(ServerStorage:WaitForChild("Knives"):GetChildren()) do
	tool:SetAttribute("IsKnife", true)
end


for i , v in pairs(ServicesHandler:GetChildren()) do
	if v:IsA("ModuleScript") then
		require(v)
	end
end




