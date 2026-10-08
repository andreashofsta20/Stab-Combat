-- Read-only inspection of the user's published place. Does not start gameplay,
-- publish changes or access player stores. Run via Studio's documented CLI.
local Http = game:GetService("HttpService")
local report = {PlaceId = game.PlaceId, UniverseId = game.GameId, Missing = {}, Assets = {}, Properties = {}}
for _, property in ipairs({"AuthorityMode", "StreamingEnabled", "SignalBehavior", "PhysicsSteppingMethod"}) do
	local ok, value = pcall(function() return workspace[property] end)
	report.Properties[property] = ok and tostring(value) or tostring(value)
end
local function inspect(path, class)
	local node = game
	for part in path:gmatch("[^/]+") do node = node and node:FindFirstChild(part) end
	if not node or (class and not node:IsA(class)) then table.insert(report.Missing, path) end
end
for _, path in ipairs({"ReplicatedStorage/Remotes", "ReplicatedStorage/UITemplates", "ServerStorage/Knives", "ServerStorage/Revolvers",
	"ServerStorage/Tropical Island", "ServerStorage/Cargo Port", "ServerStorage/Grids", "ServerStorage/Classic ROBLOX",
	"ServerStorage/Zone", "StarterGui/Main", "Workspace/IntermissionMap/Lobby/Spawns"}) do inspect(path) end
local assets, instances, scripts = {}, 0, 0
for _, node in ipairs(game:GetDescendants()) do
	instances += 1
	if node:IsA("LuaSourceContainer") then scripts += 1 end
	local property = node:IsA("Sound") and "SoundId" or node:IsA("Animation") and "AnimationId"
		or (node:IsA("ImageLabel") or node:IsA("ImageButton")) and "Image" or node:IsA("MeshPart") and "MeshId"
	if property then
		local ok, content = pcall(function() return node[property] end)
		if ok and content ~= "" and not assets[content] then assets[content] = true; table.insert(report.Assets, content) end
	end
end
report.InstanceCount, report.ScriptCount = instances, scripts
report.InventoryTemplates = {}
for _, name in ipairs({"PlayerInfo", "TradeRequesting", "Settings", "Spinner"}) do inspect("StarterGui/Main/Frames/" .. name) end
inspect("ReplicatedStorage/UITemplates/BattleHistoryPlayerTemplates/BattleHistory/Container/Divider/GameMode", "TextLabel")
print("STAB_STUDIO_INSPECTION " .. Http:JSONEncode(report))
