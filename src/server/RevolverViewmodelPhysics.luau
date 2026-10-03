local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Modules.RevolverConfig).FirstPersonPhysics
local Physics = {}
local started, elapsed, lastFailure = false, 0, nil

local function refresh()
	if not PhysicsService:IsCollisionGroupRegistered(Config.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(Config.CollisionGroup)
	end
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		if PhysicsService:CollisionGroupsAreCollidable(Config.CollisionGroup, group.name) then
			PhysicsService:CollisionGroupSetCollidable(Config.CollisionGroup, group.name, false)
		end
	end
end

local function update()
	local ok, failure = pcall(refresh)
	ReplicatedStorage:SetAttribute(Config.ReadyAttribute, ok)
	if not ok and tostring(failure) ~= lastFailure then
		lastFailure = tostring(failure)
		warn("[RevolverViewmodelPhysics] " .. lastFailure)
	elseif ok then lastFailure = nil end
end

function Physics.Init()
	if started then return end
	started = true
	assert(Config.GroupRefreshSeconds > 0, "Invalid viewmodel collision refresh interval")
	ReplicatedStorage:SetAttribute(Config.ReadyAttribute, false)
	update()
	-- A new map/service may register additional groups later. Only our mask changes.
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= Config.GroupRefreshSeconds then elapsed = 0; update() end
	end)
end

return Physics
