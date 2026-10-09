-- READ-ONLY Studio Command Bar preflight: paste this file in Edit mode in EACH
-- authored place after syncing source. Reads objects/configuration literals.
-- No require(), clones, object/property writes, waits, store access or travel.
-- Passing means local setup passed; published travel/persistence still need QA.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local EXPECTED_UNIVERSE_ID, EXPECTED_MAIN_PLACE_ID = 9667193329, 119874582058419
local report = {
	Context = {PlaceId = game.PlaceId, UniverseId = game.GameId, Studio = RunService:IsStudio()},
	Configuration = {}, Assets = {}, Errors = {}, Warnings = {}, Notes = {}, Checks = 0,
	Unverified = {"Published destination belongs to the same experience", "Reserved-server travel and return",
		"Persistent profile handoff and once-only rewards", "Mesh collision, NPC pathfinding and real-device input"},
}
local function issue(level, code, path, message, scope)
	table.insert(report[level], {Code = code, Path = path, Message = message, Scope = scope or "LocalSetup"})
end
local function err(code, path, message, scope) issue("Errors", code, path, message, scope) end
local function warning(code, path, message) issue("Warnings", code, path, message) end
local function note(code, path, message) issue("Notes", code, path, message) end
local function pathOf(node) return node and node:GetFullName() or "(missing)" end
local function find(path)
	local node = game
	for name in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(name)
		if not node then return nil end
	end
	return node
end
local function expected(path, className, optional)
	report.Checks += 1
	local node = find(path)
	if not node then
		if not optional then err("MISSING_OBJECT", path, "Copy this authored object/source from the main place; Rojo does not create native assets.") end
		return nil
	end
	if className and not node:IsA(className) then
		err("WRONG_CLASS", path, "Expected " .. className .. "; found " .. node.ClassName .. ".")
		return nil
	end
	return node
end
-- Read literal settings without executing even configuration modules. Computed
-- settings produce a visible error rather than a guessed value.
local function source(path)
	local module = expected(path, "ModuleScript")
	if not module then return nil end
	local ok, text = pcall(function() return module.Source end)
	if not ok then err("SOURCE_UNREADABLE", path, "Use the Studio Command Bar in Edit mode so configuration Source can be read."); return nil end
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end
local function literal(text, key, path)
	local value = text and text:match("%f[%w_]" .. key .. "%f[^%w_]%s*=%s*([^,\n}]+)")
	value = value and value:match("^%s*(.-)%s*$")
	if value == "true" then return true elseif value == "false" then return false end
	if value and tonumber(value) then return tonumber(value) end
	if value then
		local quoted = value:match('^"([^"\\]*)"$') or value:match("^'([^'\\]*)'$")
		if quoted then return quoted end
	end
	if text then err("NON_LITERAL_CONFIG", path .. "." .. key, "Use a literal value for this setting, or validate the computed setting manually.") end
	return nil
end
local function positiveInteger(value)
	return type(value) == "number" and value > 0 and value % 1 == 0 and value < math.huge
end
local configPath = "ReplicatedStorage/Modules/TutorialConfig"
local tutorialSource = source(configPath)
local dataSource = source("ReplicatedStorage/Modules/DataConfig")
local npcSource = source("ReplicatedStorage/Modules/TutorialNPCConfig")
local config = {
	Enabled = literal(tutorialSource, "Enabled", configPath),
	Version = literal(tutorialSource, "Version", configPath),
	MainPlaceId = literal(tutorialSource, "MainPlaceId", configPath),
	TutorialPlaceId = literal(tutorialSource, "TutorialPlaceId", configPath),
	MapName = literal(tutorialSource, "MapName", configPath),
	RewardKnife = literal(tutorialSource, "Knife", configPath),
	XP = literal(tutorialSource, "XP", configPath), Gold = literal(tutorialSource, "Gold", configPath),
	EnableSoloPreview = literal(tutorialSource, "EnableSoloPreview", configPath),
	UseMockProfiles = literal(dataSource, "UseMockProfiles", "ReplicatedStorage/Modules/DataConfig"),
	NPCMaxAlive = literal(npcSource, "MaxAlive", "ReplicatedStorage/Modules/TutorialNPCConfig"),
	NPCSpawnHeight = literal(npcSource, "SpawnHeight", "ReplicatedStorage/Modules/TutorialNPCConfig"),
	NPCTemplateName = literal(npcSource, "TemplateName", "ReplicatedStorage/Modules/TutorialNPCConfig"),
}
report.Configuration = config
local preview = report.Context.Studio and config.EnableSoloPreview == true
local trainingPlace = positiveInteger(config.TutorialPlaceId) and game.PlaceId == config.TutorialPlaceId
local lobbyPlace = positiveInteger(config.MainPlaceId) and game.PlaceId == config.MainPlaceId
local role = if preview then "StudioMockPreview" elseif trainingPlace then "TrainingPlace" elseif lobbyPlace then "LobbyPlace" else "UnconfiguredPlace"
report.Context.Role, report.Context.SoloPreview = role, preview
report.Context.LiveRole = if trainingPlace then "TrainingPlace" elseif lobbyPlace then "LobbyPlace" else "UnconfiguredPlace"
report.Context.MockProfiles = config.UseMockProfiles == true
if not report.Context.Studio then warning("COMMAND_BAR_CONTEXT", "Studio", "Run this in the Studio Command Bar in Edit mode.") end
if RunService:IsRunning() then warning("RUNNING_SESSION", "Studio", "Use Edit mode: runtime-created objects can hide missing authored assets.") end
if game.GameId ~= EXPECTED_UNIVERSE_ID then err("WRONG_EXPERIENCE", "game.GameId", "Open a place inside experience " .. EXPECTED_UNIVERSE_ID .. "; a separate experience cannot share the profiles/tickets.", "LiveDeployment") end
if config.MainPlaceId ~= EXPECTED_MAIN_PLACE_ID then err("MAIN_PLACE_ID", configPath, "MainPlaceId must point to the authored lobby: " .. EXPECTED_MAIN_PLACE_ID .. ".", "LiveDeployment") end
if not positiveInteger(config.TutorialPlaceId) then
	err("TUTORIAL_PLACE_UNCONFIGURED", configPath, "Create/publish the training place INSIDE the existing experience, then set its positive TutorialPlaceId in BOTH places.", "LiveDeployment")
elseif config.TutorialPlaceId == config.MainPlaceId then err("SAME_PLACE_IDS", configPath, "MainPlaceId and TutorialPlaceId must differ.", "LiveDeployment") end
if report.Context.LiveRole == "UnconfiguredPlace" then err("CURRENT_PLACE_UNCONFIGURED", configPath, "This open place matches neither configured ID. Set TutorialPlaceId to this training place's published ID; retain MainPlaceId.", "LiveDeployment") end
if config.Enabled ~= true then warning("TUTORIAL_DISABLED", configPath, "Enabled=false prevents new starts. Enable it after completing setup.") end
if not positiveInteger(config.Version) then err("VERSION", configPath, "Use a positive integer version and deploy identical config to both places.") end
for _, key in ipairs({"XP", "Gold"}) do
	if type(config[key]) ~= "number" or config[key] < 0 or config[key] % 1 ~= 0 or config[key] == math.huge then err("REWARD_AMOUNT", configPath .. ".Rewards." .. key, "Use a nonnegative whole number.") end
end
if preview then
	if config.UseMockProfiles ~= true then err("PREVIEW_REQUIRES_MOCK", "ReplicatedStorage/Modules/DataConfig", "EnableSoloPreview requires UseMockProfiles=true in an ISOLATED Studio rehearsal.") end
	warning("PREVIEW_IS_NOT_LIVE", configPath .. ".Studio", "Preview bypasses ticket admission/travel and never grants real rewards. Restore both Studio flags to false before publishing.")
elseif config.UseMockProfiles == true then err("MOCK_PROFILES_FOR_LIVE_SETUP", "ReplicatedStorage/Modules/DataConfig", "Mock profiles are only for isolated Studio preview. Set UseMockProfiles=false for persistent live rewards.") end
if trainingPlace or preview then
	local ok, maxPlayers = pcall(function() return Players.MaxPlayers end)
	if ok then report.Context.MaxPlayers = maxPlayers end
	if not ok or maxPlayers ~= 1 then warning("MAX_PLAYERS", "Game Settings > Places", "Set TRAINING-place Max Players to 1. Ticket admission remains authoritative; retain lobby capacity.") end
end
note("SAME_UNIVERSE_DEPLOYMENT", configPath, "Publish identical source, rewards and profile-store names to both places. Creator Dashboard must show the destination in this experience; this script checks only the open place.")

-- Training still loads shared server groups, combat and ordinary client startup.
for _, name in ipairs({"DataStore", "CombatHandler", "Game", "ServicesHandler", "Trading", "CharacterDeath"}) do
	local boot = expected("ServerScriptService/" .. name, "Script")
	if boot and not boot.Enabled then err("DISABLED_STARTUP", pathOf(boot), "Enable this startup Script for published gameplay.") end
end
expected("ServerScriptService/StartupService", "ModuleScript")
expected("ServerScriptService/Packages/ProfileStore", "ModuleScript")
for _, name in ipairs({"TutorialCoordinator", "TutorialState", "TutorialRuntime", "TutorialArena", "TutorialRewards", "TutorialTickets", "TutorialTeleport", "TutorialRole", "TutorialAnalytics"}) do expected("ServerScriptService/Tutorial/" .. name, "ModuleScript") end
expected("ServerScriptService/ServicesHandler/TutorialService", "ModuleScript")
expected("ServerScriptService/DataStore/ProfileManager", "ModuleScript")
for _, name in ipairs({"StartupConfig", "StartupLoader", "TutorialSteps", "TutorialUIConfig", "MovementConfig", "MovementAdmission", "KnifeConfig", "RevolverConfig", "FoodConfig", "KeybindValidation", "KnivesInfo", "RevolversInfo"}) do expected("ReplicatedStorage/Modules/" .. name, "ModuleScript") end
local client = expected("StarterPlayer/StarterPlayerScripts/CLIENT", "LocalScript")
if client and not client.Enabled then err("DISABLED_CLIENT", pathOf(client), "Enable CLIENT so combat, hotbar and tutorial UI initialize.") end
expected("StarterPlayer/StarterPlayerScripts/CLIENT/TutorialHandler", "ModuleScript")
for _, name in ipairs({"TutorialUI", "TutorialGuidance", "TutorialGamepadBridge", "HandleGameUI"}) do expected("StarterPlayer/StarterPlayerScripts/CLIENT/Modules/" .. name, "ModuleScript") end
expected("ReplicatedStorage/GameActive", "BoolValue")
expected("ReplicatedStorage/Remotes", "Folder")
for _, remote in ipairs({
	"Knife/ThrowKnife", "Knife/StabKnife", "Knife/ThrewClient", "Knife/DamageDealtClient", "Knife/PlayerGotKilledRemote",
	"HotBar/Equip", "HotBar/EquippedClient", "ChangeStatus", "StartGameClient/RecieveTools", "StartGameClient/WipeTools",
	"RoundResults/GetRoundResults", "Client/NotificationClientRemotes/RecieveNotification", "RoundCountdown",
}) do expected("ReplicatedStorage/Remotes/" .. remote, "RemoteEvent") end
for _, remote in ipairs({"StartVoting", "RecieveVote", "ClearUIVotes"}) do expected("ReplicatedStorage/VotingRemotes/" .. remote, "RemoteEvent") end
-- Absence is OK for these server-created remotes; a wrong class is not.
for _, entry in ipairs({
	{"Tutorial", "Folder"}, {"Tutorial/StartTutorial", "RemoteEvent"}, {"Food", "Folder"}, {"Food/Eat", "RemoteEvent"},
	{"Revolver", "Folder"}, {"Revolver/Action", "RemoteEvent"}, {"Revolver/State", "RemoteEvent"}, {"Revolver/Shot", "RemoteEvent"},
	{"Revolver/Aim", "UnreliableRemoteEvent"}, {"MovementIntent", "RemoteEvent"}, {"KillCam", "RemoteEvent"},
}) do expected("ReplicatedStorage/Remotes/" .. entry[1], entry[2], true) end
note("SERVER_CREATED_REMOTES", "ReplicatedStorage/Remotes", "Tutorial, Food, Revolver, MovementIntent and KillCam remotes may be absent in Edit mode; enabled server startup creates them.")
local mainGui = expected("StarterGui/Main", "ScreenGui")
if mainGui and not mainGui.Enabled then warning("MAIN_GUI_DISABLED", pathOf(mainGui), "Enable the authored Main ScreenGui for hotbar and existing controls.") end
for _, path in ipairs({"Bottom", "Top/Buttons", "SpectateFrame", "Ingame/FFA/Top/PlayerList", "Ingame/BR/Top/PlayerList"}) do expected("StarterGui/Main/" .. path, "GuiObject") end
for _, slot in ipairs({"1", "2"}) do
	expected("StarterGui/Main/Bottom/" .. slot, "GuiObject")
	local image = expected("StarterGui/Main/Bottom/" .. slot .. "/SlotImage", "GuiObject")
	if image and not (image:IsA("ImageLabel") or image:IsA("ImageButton")) then err("HOTBAR_IMAGE_CLASS", pathOf(image), "Use an ImageLabel or ImageButton for SlotImage.") end
	expected("StarterGui/Main/Bottom/" .. slot .. "/SlotSelected", "GuiObject")
end
for _, mode in ipairs({"FFA", "BR"}) do expected("ReplicatedStorage/UITemplates/InGameUITemplates/" .. mode .. "/PlayerTemplate", "GuiObject") end
note("FOOD_SLOT", "StarterGui/Main/Bottom", "Slot 3 is optional: hotbar creates it from slot 2 for Burger supplies.")

local function catalogContains(text, name)
	if type(name) ~= "string" then return false end
	local escaped = name:gsub("([^%w])", "%%%1")
	return text ~= nil and (text:find('%[%s*"' .. escaped .. '"%s*%]%s*=') ~= nil or text:find("%[%s*'" .. escaped .. "'%s*%]%s*=") ~= nil)
end
local knifeSource, revolverSource = source("ReplicatedStorage/Modules/KnivesInfo"), source("ReplicatedStorage/Modules/RevolversInfo")
local function tool(path)
	local template = expected(path, "Tool")
	if not template then return nil end
	if not template.Archivable then err("TOOL_NOT_ARCHIVABLE", path, "Set Archivable=true so the server can clone this Tool.") end
	if template.RequiresHandle then
		local handle = template:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then err("TOOL_HANDLE", path, "RequiresHandle=true needs a direct child BasePart named Handle.") end
	end
	return template
end
for _, entry in ipairs({{"Knives", knifeSource}, {"Revolvers", revolverSource}}) do
	local name, catalog = entry[1], entry[2]
	local folder = expected("ServerStorage/" .. name)
	if folder and not (folder:IsA("Folder") or folder:IsA("Model")) then err("WEAPON_CONTAINER", pathOf(folder), "Use a Folder/Model containing exact catalog-named Tool templates.") end
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Tool") then
				tool("ServerStorage/" .. name .. "/" .. child.Name)
				if catalog and not catalogContains(catalog, child.Name) then warning("TOOL_NOT_IN_CATALOG", pathOf(child), "No literal key matches in the catalog; confirm the exact name.") end
			end
		end
		if catalog then
			for catalogName in catalog:gmatch('%[%s*"([^"]+)"%s*%]%s*=') do
				if not folder:FindFirstChild(catalogName) then err("CATALOG_TOOL_MISSING", "ServerStorage/" .. name .. "/" .. catalogName, "Copy the exact catalog-named Tool template. Players keep their selected skins when entering training.") end
			end
		end
	end
end
tool("ServerStorage/Knives/Bowie")
tool("ServerStorage/Revolvers/Normal Revolver")
if type(config.RewardKnife) == "string" and config.RewardKnife ~= "" then
	tool("ServerStorage/Knives/" .. config.RewardKnife)
	if knifeSource and not catalogContains(knifeSource, config.RewardKnife) then err("REWARD_KNIFE_CATALOG", configPath .. ".Rewards.Knife", "Reward must exactly match a KnivesInfo key and server Tool.") end
else err("REWARD_KNIFE", configPath .. ".Rewards.Knife", "Set an existing catalog knife name.") end
tool("ReplicatedStorage/Food/Burger")
local revolver = find("ServerStorage/Revolvers/Normal Revolver")
if revolver and not revolver:FindFirstChild("Muzzle", true) then warning("REVOLVER_MUZZLE", pathOf(revolver), "Add a Muzzle Attachment for a precise barrel origin; combat otherwise uses its fallback.") end

local function parts(folder)
	local result = {}
	if folder then for _, child in ipairs(folder:GetDescendants()) do if child:IsA("BasePart") then table.insert(result, child) end end end
	table.sort(result, function(a, b) return a.Name < b.Name end)
	return result
end
local function mapTemplate(name, required)
	local map = expected("ServerStorage/" .. name, nil, not required)
	if not map then return nil end
	if not (map:IsA("Model") or map:IsA("Folder")) then err("MAP_CLASS", pathOf(map), "Use a Model or Folder map template."); return nil end
	if not map.Archivable then err("MAP_NOT_ARCHIVABLE", pathOf(map), "Set Archivable=true so the map can be cloned.") end
	return map
end
-- Lobby maps are deliberately not required in training/Studio preview.
if lobbyPlace and not preview then
	for _, name in ipairs({"Tropical Island", "Cargo Port", "Grids", "Classic ROBLOX"}) do
		local map = mapTemplate(name, true)
		if map and #parts(map:FindFirstChild("Spawns", true)) == 0 then err("LOBBY_MAP_SPAWNS", pathOf(map), "Add Spawns with BasePart children for normal rounds.") end
	end
	expected("Workspace/IntermissionMap/Lobby/Spawns")
end
local needsTrainingAssets = trainingPlace or preview or report.Context.LiveRole == "UnconfiguredPlace"
local mapName = type(config.MapName) == "string" and config.MapName or "Studs"
local map = mapTemplate(mapName, needsTrainingAssets)
report.Assets.MapFixture = map and mapName or "Missing"
if not map and lobbyPlace and not preview then note("LOBBY_MAP_SCOPE", "ServerStorage/" .. mapName, "Studs is required in the TRAINING place; it is not needed to launch travel from the lobby.") end

-- ServerStorage is not raycastable without parenting a clone. Intersect oriented
-- part bounds mathematically to remain read-only. Actual collision needs Play QA.
local function boxIntersection(part, origin, direction)
	local localOrigin = part.CFrame:PointToObjectSpace(origin)
	local localDirection = part.CFrame:VectorToObjectSpace(direction)
	local half, low, high = part.Size * 0.5, 0, 1
	for _, axis in ipairs({"X", "Y", "Z"}) do
		local position, delta, extent = localOrigin[axis], localDirection[axis], half[axis]
		if math.abs(delta) < 1e-8 then
			if math.abs(position) > extent then return nil end
		else
			local first, last = (-extent - position) / delta, (extent - position) / delta
			if first > last then first, last = last, first end
			low, high = math.max(low, first), math.min(high, last)
			if low > high then return nil end
		end
	end
	return low
end
if map then
	local playerFolder = map:FindFirstChild("TutorialPlayerSpawns", true) or map:FindFirstChild("Spawns", true)
	local npcFolder = map:FindFirstChild("TutorialNPCSpawns", true)
	local playerSpawns, npcSpawns = parts(playerFolder), parts(npcFolder)
	report.Assets.PlayerSpawns, report.Assets.NPCSpawns = #playerSpawns, #npcSpawns
	if #playerSpawns == 0 then err("TRAINING_PLAYER_SPAWN", pathOf(map), "Add TutorialPlayerSpawns (or Spawns) with a BasePart marker. The alphabetically first marker is used.") end
	if #npcSpawns == 0 then warning("TRAINING_NPC_MARKERS", pathOf(map), "Add TutorialNPCSpawns markers on walkable floors. Without them the server uses offsets in front of the first player spawn.") end
	local geometry, complexGeometry, looseGeometry, scripts = {}, 0, 0, 0
	for _, child in ipairs(map:GetDescendants()) do
		if child:IsA("BaseScript") then scripts += 1 end
		if child:IsA("BasePart") and not (playerFolder and child:IsDescendantOf(playerFolder)) and not (npcFolder and child:IsDescendantOf(npcFolder)) then
			if child.CanQuery then table.insert(geometry, child) end
			if child:IsA("MeshPart") or child:IsA("UnionOperation") or child:IsA("WedgePart") or child:IsA("CornerWedgePart") or (child:IsA("Part") and child.Shape ~= Enum.PartType.Block) then complexGeometry += 1 end
			if not child.Anchored then looseGeometry += 1 end
		end
	end
	report.Assets.QueryableMapParts = #geometry
	if looseGeometry > 0 then warning("UNANCHORED_MAP_PARTS", pathOf(map), tostring(looseGeometry) .. " map parts are unanchored; anchor intended floors/walls or ensure valid assemblies.") end
	if scripts > 0 then note("MAP_SCRIPTS_REMOVED", pathOf(map), tostring(scripts) .. " BaseScripts are stripped from the training clone. Do not rely on them to create floors/spawns.") end
	if complexGeometry > 0 then warning("GEOMETRY_APPROXIMATION", pathOf(map), "Bounds can differ from mesh/union/wedge/rounded collision. Confirm every spawn in native Play mode.") end
	if #geometry == 0 then err("TRAINING_MAP_FLOOR", pathOf(map), "Add queryable floor BaseParts beneath spawns. Terrain outside the template is excluded by the NPC ground probe.") end
	local markerQuery = 0
	for _, list in ipairs({playerSpawns, npcSpawns}) do for _, marker in ipairs(list) do if marker.CanQuery then markerQuery += 1 end end end
	if markerQuery > 0 then warning("QUERYABLE_SPAWN_MARKERS", pathOf(map), "Use non-collidable, CanQuery=false markers; queryable markers can intercept the NPC ground probe above real floors.") end
	local function floorAt(frame, label)
		report.Checks += 1
		local origin, direction = frame.Position + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0)
		local nearest, floor
		for _, part in ipairs(geometry) do
			local distance = boxIntersection(part, origin, direction)
			if distance and (not nearest or distance < nearest) then nearest, floor = distance, part end
		end
		if not floor then err("SPAWN_WITHOUT_FLOOR", label, "No queryable map-part bounds lie within the server's 120-stud downward probe. Move the marker over a real map floor.")
		elseif not floor.CanCollide then warning("SPAWN_FLOOR_NOT_COLLIDABLE", label, "Nearest ground bounds belong to non-collidable " .. pathOf(floor) .. ". Confirm a solid floor beneath the character.") end
	end
	local height = type(config.NPCSpawnHeight) == "number" and config.NPCSpawnHeight or 4
	if playerSpawns[1] then
		floorAt(playerSpawns[1].CFrame * CFrame.new(0, height, 0), pathOf(playerSpawns[1]))
		local count = positiveInteger(config.NPCMaxAlive) and config.NPCMaxAlive or 4
		if count > 32 then warning("NPC_CHECK_LIMIT", "TutorialNPCConfig.MaxAlive", "Preflight checks 32 simultaneous NPC positions; inspect remaining positions manually.") end
		for index = 1, math.min(count, 32) do
			local marker = npcSpawns[((index - 1) % math.max(1, #npcSpawns)) + 1]
			local frame = marker and marker.CFrame * CFrame.new(0, height, 0) or playerSpawns[1].CFrame * CFrame.new((index - 2) * 8, height, -16 - index * 3)
			floorAt(frame, marker and pathOf(marker) or pathOf(map) .. "/FallbackNPC[" .. index .. "]")
		end
	end
end
local rigName = type(config.NPCTemplateName) == "string" and config.NPCTemplateName or "TutorialNPC"
local rig = find("ServerStorage/" .. rigName)
report.Assets.NPCRig = rig and rigName or "Built-in R6 fallback"
if rig then
	if not rig:IsA("Model") then warning("NPC_TEMPLATE_IGNORED", pathOf(rig), "Custom template must be a Model; otherwise the built-in R6 rig is used.")
	else
		if not rig.Archivable then err("NPC_NOT_ARCHIVABLE", pathOf(rig), "Set Archivable=true so the custom NPC can be cloned.") end
		if not rig:FindFirstChildOfClass("Humanoid") then err("NPC_HUMANOID", pathOf(rig), "Add a direct child Humanoid, or remove this optional template to use the built-in rig.") end
		local root = rig:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then err("NPC_ROOT", pathOf(rig), "Add a direct child BasePart named HumanoidRootPart.") end
		local head = rig:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then warning("NPC_HEAD", pathOf(rig), "Add a Head BasePart for head-hit lessons and readable target feedback.") end
		if not (rig:FindFirstChildWhichIsA("Motor6D", true) or rig:FindFirstChildWhichIsA("WeldConstraint", true)) then warning("NPC_RIG_JOINTS", pathOf(rig), "The server unanchors NPC parts. Add valid body joints/welds so the rig stays assembled.") end
	end
else note("NPC_FALLBACK", "ServerStorage/" .. rigName, "Custom rig is optional: the server builds a joined R6 practice bandit with Humanoid/root/head.") end
note("AVATAR_RIG", "Game Settings > Avatar", "Verify R6 as required by existing knife, movement and animation assets.")

local localErrors, deploymentErrors = 0, 0
for _, item in ipairs(report.Errors) do
	if item.Scope == "LiveDeployment" then deploymentErrors += 1 else localErrors += 1 end
end
report.Readiness = {
	LocalSetupPassed = localErrors == 0,
	LiveConfigurationPassed = deploymentErrors == 0 and not preview and config.UseMockProfiles == false,
	PublishedTravelAndPersistenceVerified = false,
}
report.Passed = #report.Errors == 0
report.Counts = {Errors = #report.Errors, Warnings = #report.Warnings, Checks = report.Checks}
print(string.format("[Tutorial preflight] %s | place %s | %d errors, %d warnings, %d checks", role, tostring(game.PlaceId), #report.Errors, #report.Warnings, report.Checks))
for _, level in ipairs({"Errors", "Warnings"}) do
	for _, item in ipairs(report[level]) do
		local message = string.format("[%s] %s — %s: %s", level == "Errors" and "ERROR" or "WARN", item.Code, item.Path, item.Message)
		if level == "Errors" then warn(message) else print(message) end
	end
end
print("TUTORIAL_PREFLIGHT_REPORT " .. Http:JSONEncode(report))
return report
