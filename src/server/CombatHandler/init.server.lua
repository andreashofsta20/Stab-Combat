-- Initialize player hitbox system first
local PlayerHitbox = require(script:WaitForChild("PlayerHitbox"))
PlayerHitbox.Init()

for i , v in pairs(script:GetChildren()) do
	if v:IsA("ModuleScript") then
		require(v)
	end
end
