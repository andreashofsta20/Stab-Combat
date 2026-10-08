-- Warm only the local loadout. PreloadAsync and visual walks stay in background
-- coroutines, with no waits in camera, input, equip, or startup handlers.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(RS.Modules.WeaponAssetWarmupConfig)
local RevolverConfig = require(RS.Modules.RevolverConfig)
local KnifeEffectsConfig = require(RS.Modules.KnifeEffectsConfig)
local AudioConfig = require(RS.Modules.CombatAudioConfig)
local player = Players.LocalPlayer
local Warmup = {}
local initialized, generation, scanGeneration = false, 0, 0
local workerRunning, refreshScheduled = false, false
local connections, pathConnections = {}, {}
local queue, pending, seenIds = {}, {}, {}
-- MeshPart content properties can be protected. Passing its Instance to the
-- provider handles its dependencies without reading those properties. Weak
-- cache keys/order do not keep destroyed weapon replicas alive.
local seenObjects = setmetatable({}, {__mode = "k"})
local rememberedOrder = setmetatable({}, {__mode = "v"})
local rememberedIndex = 0
local currentKnife, currentGun = "", ""
local combatNames = {Charge = true, ChargeHold = true, Throw = true, Stab = true}
local soundNames = {EquipKnife = true, Stab = true, ThrowKnife = true, EliminatedPlayer = true}
local scheduleRefresh, startWorker

local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

local function id(value)
	if type(value) ~= "string" or value == "" or #value > 1024 then return nil end
	local number = value:match("^rbxassetid://(%d+)$") or value:match("[?&]id=(%d+)")
	if number then return tonumber(number) ~= 0 and "rbxassetid://" .. number or nil end
	return value
end

local function remembered(key)
	return type(key) == "string" and seenIds[key] or seenObjects[key]
end

local function remember(key)
	if remembered(key) then return end
	rememberedIndex = rememberedIndex % Config.MaxRememberedAssets + 1
	local previous = rememberedOrder[rememberedIndex]
	if previous then
		if type(previous) == "string" then seenIds[previous] = nil else seenObjects[previous] = nil end
	end
	rememberedOrder[rememberedIndex] = key
	if type(key) == "string" then seenIds[key] = true else seenObjects[key] = true end
end

local function enqueue(key, asset, className)
	if not initialized or not key or remembered(key) or pending[key] or #queue >= Config.MaxQueuedAssets then return end
	pending[key] = "queued"
	table.insert(queue, {key = key, asset = asset, className = className})
	startWorker()
end

local function enqueueId(value, className)
	local key = id(value)
	if key then enqueue(key, key, className) end
end

startWorker = function()
	if workerRunning or not initialized or #queue == 0 then return end
	workerRunning = true
	local token = generation
	task.defer(function()
		while initialized and token == generation and #queue > 0 do
			local jobs, assets, temporary = {}, {}, {}
			for _ = 1, math.min(Config.AssetsPerRequest, #queue) do
				local job = table.remove(queue, 1)
				pending[job.key] = "loading"
				local asset = job.asset
				if job.className then
					asset = Instance.new(job.className)
					if job.className == "Animation" then asset.AnimationId = job.asset else asset.SoundId = job.asset end
					table.insert(temporary, asset)
				end
				table.insert(jobs, job); table.insert(assets, asset)
			end
			pcall(function()
				ContentProvider:PreloadAsync(assets, function(assetId, status)
					if initialized and token == generation and status == Enum.AssetFetchStatus.Success then
						local key = id(assetId); if key then remember(key) end
					end
				end)
			end)
			for _, item in ipairs(temporary) do item:Destroy() end
			if token ~= generation then break end
			for _, job in ipairs(jobs) do
				pending[job.key] = nil
				-- Remember the attempt too: a denied/unavailable asset should not
				-- restart a background retry loop on every equip or respawn.
				remember(job.key)
			end
			if #queue > 0 then task.wait() end
		end
		workerRunning = false
		-- A destroyed/reinitialized controller still serializes behind the one
		-- native request already in flight. Late callbacks cannot alter its cache.
		if initialized and #queue > 0 then startWorker() end
	end)
end

local function enqueueItem(item)
	if item:IsA("MeshPart") then enqueue(item, item)
	elseif item:IsA("SpecialMesh") then
		local mesh, texture = id(item.MeshId), id(item.TextureId)
		if mesh or texture then enqueue("mesh:" .. (mesh or "") .. "|" .. (texture or ""), item) end
	elseif item:IsA("Animation") then local key = id(item.AnimationId); if key then enqueue(key, item) end
	elseif item:IsA("Sound") then local key = id(item.SoundId); if key then enqueue(key, item) end
	end
	-- SurfaceAppearance/MaterialVariant texture packs are streamed by the
	-- engine; ContentProvider does not support preloading these Instances.
end

local function scanWeapon(source, token, scanToken)
	local stack, count = {source}, 0
	while #stack > 0 and count < Config.MaxScanItemsPerWeapon do
		if not initialized or token ~= generation or scanToken ~= scanGeneration or not source.Parent then return end
		local item = table.remove(stack)
		count += 1; enqueueItem(item)
		-- Walk only this selected weapon; never enumerate Workspace or the skin
		-- catalog. Both work and retained traversal references are capped.
		for _, child in ipairs(item:GetChildren()) do
			if #stack + count >= Config.MaxScanItemsPerWeapon then break end
			table.insert(stack, child)
		end
		if count % Config.ScanItemsPerYield == 0 then task.wait() end
	end
end

local function value(stats, name)
	local field = stats and stats:FindFirstChild(name)
	return field and field:IsA("StringValue") and type(field.Value) == "string"
		and #field.Value <= 128 and field.Value or ""
end

local function selectedItem(item, folder)
	local ancestor = item
	for _ = 1, 32 do
		if not ancestor or ancestor == folder then return false end
		if ancestor.Parent == folder then return ancestor.Name == currentKnife or ancestor.Name == currentGun end
		ancestor = ancestor.Parent
	end
	return false
end

local function watchPaths()
	disconnect(pathConnections)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		table.insert(pathConnections, stats.ChildAdded:Connect(scheduleRefresh))
		table.insert(pathConnections, stats.ChildRemoved:Connect(scheduleRefresh))
		for _, name in ipairs({"EquippedKnife", "EquippedGun"}) do
			local field = stats:FindFirstChild(name)
			if field and field:IsA("StringValue") then table.insert(pathConnections, field.Changed:Connect(scheduleRefresh)) end
		end
	end
	for _, folderName in ipairs({"Knives", "Revolvers", "CombatAnimations", "Assets"}) do
		local folder = RS:FindFirstChild(folderName)
		if folder then
			local function changed(item)
				if folderName == "CombatAnimations" then
					if combatNames[item.Name] then scheduleRefresh() end
				elseif folderName == "Assets" then
					if item.Name == "Sounds" or soundNames[item.Name] then scheduleRefresh() end
				elseif selectedItem(item, folder) then scheduleRefresh() end
			end
			table.insert(pathConnections, folder.DescendantAdded:Connect(changed))
			table.insert(pathConnections, folder.DescendantRemoving:Connect(changed))
		end
	end
	for _, container in ipairs({player.Character or false, player:FindFirstChildOfClass("Backpack") or false}) do
		if container then
			table.insert(pathConnections, container.DescendantAdded:Connect(function(item)
				if selectedItem(item, container) then scheduleRefresh() end
			end))
		end
	end
end

local function source(folderName, name)
	if name == "" then return nil end
	local folder = RS:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(name)
	if template then return template end
	local character, backpack = player.Character, player:FindFirstChildOfClass("Backpack")
	return character and character:FindFirstChild(name) or backpack and backpack:FindFirstChild(name)
end

local function refresh()
	local stats = player:FindFirstChild("leaderstats")
	currentKnife, currentGun = value(stats, "EquippedKnife"), value(stats, "EquippedGun")
	watchPaths()
	scanGeneration += 1
	-- A changed loadout supersedes queued work, retaining only the one native
	-- request already in flight. This bounds churn and prioritizes the new skin.
	for _, job in ipairs(queue) do if pending[job.key] == "queued" then pending[job.key] = nil end end
	table.clear(queue)
	if currentGun ~= "" then
		local effects = RevolverConfig.Get(currentGun).Effects
		for _, name in ipairs({"EquipSoundId", "FireSoundId", "ReloadSoundId", "EmptySoundId", "FireAnimationId", "ReloadAnimationId"}) do
			enqueueId(effects[name], name:find("AnimationId") and "Animation" or "Sound")
		end
	end
	local combat = RS:FindFirstChild("CombatAnimations")
	if currentKnife ~= "" then
		if combat then for name in pairs(combatNames) do local clip = combat:FindFirstChild(name); if clip then enqueueItem(clip) end end end
		local effects = KnifeEffectsConfig.Get(currentKnife)
		enqueueId(effects.ThrowSoundId, "Sound"); enqueueId(effects.ImpactSoundId, "Sound")
	end
	if currentKnife ~= "" or currentGun ~= "" then
		enqueueId(AudioConfig.Hit.SoundId, "Sound")
		local assets = RS:FindFirstChild("Assets")
		local sounds = assets and assets:FindFirstChild("Sounds")
		if sounds then
			for name in pairs(soundNames) do
				if currentKnife ~= "" or name == "EliminatedPlayer" then local sound = sounds:FindFirstChild(name); if sound then enqueueItem(sound) end end
			end
		end
	end
	local knife, gun = source("Knives", currentKnife), source("Revolvers", currentGun)
	local token, scanToken = generation, scanGeneration
	if knife or gun then task.defer(function()
		if knife then scanWeapon(knife, token, scanToken) end
		if gun then scanWeapon(gun, token, scanToken) end
	end) end
end

scheduleRefresh = function()
	if not initialized or refreshScheduled then return end
	refreshScheduled = true
	local token = generation
	task.delay(Config.SelectionDelaySeconds, function()
		if not initialized or token ~= generation then return end
		refreshScheduled = false
		refresh()
	end)
end

function Warmup.Init()
	if initialized then return end
	initialized = true; generation += 1
	local function playerChanged(item) if item.Name == "leaderstats" or item:IsA("Backpack") then scheduleRefresh() end end
	local function replicatedChanged(item)
		if item.Name == "Knives" or item.Name == "Revolvers" or item.Name == "CombatAnimations" or item.Name == "Assets" then scheduleRefresh() end
	end
	table.insert(connections, player.ChildAdded:Connect(playerChanged))
	table.insert(connections, player.ChildRemoved:Connect(playerChanged))
	table.insert(connections, player.CharacterAdded:Connect(scheduleRefresh))
	table.insert(connections, player.CharacterRemoving:Connect(function() disconnect(pathConnections); scheduleRefresh() end))
	table.insert(connections, RS.ChildAdded:Connect(replicatedChanged))
	table.insert(connections, RS.ChildRemoved:Connect(replicatedChanged))
	watchPaths()
	local token = generation
	task.delay(Config.InitialDelaySeconds, function() if initialized and token == generation then scheduleRefresh() end end)
end

function Warmup.Destroy()
	if not initialized then return end
	initialized = false; generation += 1; scanGeneration += 1; refreshScheduled = false
	disconnect(connections); disconnect(pathConnections)
	table.clear(queue); table.clear(pending); table.clear(seenIds); table.clear(seenObjects); table.clear(rememberedOrder)
	currentKnife, currentGun, rememberedIndex = "", "", 0
end

return Warmup
