local ProfileManager = require(script:WaitForChild("ProfileManager"))
local Module = require(script.OnJoined)
local Module2 = require(script:WaitForChild("KeyBindHandler"))
local Module3 = require(script:WaitForChild("LeaderboardsHandler"))

for i , v in pairs(script:GetChildren()) do
    if v:IsA("ModuleScript") then
        require(v)
    end
end
