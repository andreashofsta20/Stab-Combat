local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.FoodConfig)
local State = require(script.Parent.FoodState)
local MainGame = require(script.Parent.Parent.Game.MainGame)
local Food = {}
local states, connections, buckets = {}, {}, {}
local gameActive = ReplicatedStorage:WaitForChild("GameActive")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local folder = remotes:FindFirstChild("Food")
if not folder then folder = Instance.new("Folder"); folder.Name, folder.Parent = "Food", remotes end
assert(folder:IsA("Folder"), "Remotes.Food must be a Folder")
local eatRemote = folder:FindFirstChild("Eat")
if not eatRemote then eatRemote = Instance.new("RemoteEvent"); eatRemote.Name, eatRemote.Parent = "Eat", folder end
assert(eatRemote:IsA("RemoteEvent"), "Remotes.Food.Eat must be a RemoteEvent")
local warnedTemplate = false

local function now() return workspace:GetServerTimeNow() end
local function getRound(player)
	if player:GetAttribute("TutorialActive")==true then
		local runtime=require(script.Parent.Parent.Tutorial.TutorialRuntime)
		return runtime.IsActive(player) and player:GetAttribute("DataReady")==true and runtime.GetSession(player) or nil
	end
	local round = MainGame.RoundStats
	if not MainGame.GameActive or not gameActive.Value or not round or round.rewardsApplied
		or MainGame.PlayersInGame[player.UserId] ~= true or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("DataReady") ~= true then return nil end
	local stats = player:FindFirstChild("leaderstats")
	local settings = stats and stats:FindFirstChild("Settings")
	local lobby = settings and settings:FindFirstChild("LobbyMode")
	return not (lobby and lobby.Value) and round or nil
end

local function publish(player, state)
	local remaining = state and state.remaining or 0
	player:SetAttribute("FoodUses", remaining)
	player:SetAttribute("FoodCapacity", Config.Capacity)
	player:SetAttribute("FoodReadyAt", state and state.readyAt or 0)
	if state and state.tool and state.tool.Parent then
		state.tool:SetAttribute("FoodUses", remaining)
		state.tool:SetAttribute("FoodReadyAt", state.readyAt)
	end
end

function Food.Clear(player)
	local state = states[player]
	states[player] = nil
	if state then
		if state.deathConnection then state.deathConnection:Disconnect() end
		if state.tool then state.tool:Destroy() end
	end
	publish(player, nil)
end

function Food.Grant(player, character)
	local round = getRound(player)
	if not round or player.Character ~= character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or humanoid.Health <= 0 or not backpack then return nil end
	local previous = states[player]
	-- Repeated lifecycle notifications cannot refill a used Burger.
	if previous and previous.character == character and previous.round == round then return previous.tool end
	Food.Clear(player)
	local assets = ReplicatedStorage:FindFirstChild("Food")
	local template = assets and assets:FindFirstChild(Config.ToolName)
	local handle = template and template:FindFirstChild("Handle")
	if not template or not template:IsA("Tool") or (template.RequiresHandle and (not handle or not handle:IsA("BasePart"))) then
		if not warnedTemplate then warn("Food: add a Tool ReplicatedStorage.Food.Burger with a BasePart Handle (or RequiresHandle=false).") end
		warnedTemplate = true
		return nil
	end
	local tool = template:Clone()
	-- Imported food scripts could otherwise heal separately or run twice.
	for _, child in ipairs(tool:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") then child:Destroy()
		elseif child:IsA("BasePart") then child.Anchored, child.CanCollide, child.CanTouch, child.Massless = false, false, false, true end
	end
	tool.CanBeDropped, tool.Enabled = false, true
	tool:SetAttribute("FoodItem", Config.ToolName)
	tool:SetAttribute("FoodCapacity", Config.Capacity)
	tool:SetAttribute("FoodUses", Config.Capacity)
	tool:SetAttribute("FoodReadyAt", 0)
	local state = State.New(character, round, Config.Capacity)
	state.tool, state.humanoid = tool, humanoid
	states[player] = state
	state.deathConnection = humanoid.Died:Connect(function() if states[player] == state then Food.Clear(player) end end)
	tool.Parent = backpack
	publish(player, state)
	return tool
end

function Food.GetTool(player)
	local state = states[player]
	if not state or state.round ~= getRound(player) or state.character ~= player.Character
		or state.remaining <= 0 or state.humanoid.Health <= 0 then return nil end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = state.tool
	return tool and (tool.Parent == state.character or tool.Parent == backpack) and tool or nil
end

function Food.Store(player, tool)
	local state = states[player]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not state or state.tool ~= tool or not backpack then return false end
	tool.Parent = backpack
	return true
end

eatRemote.OnServerEvent:Connect(function(player, tool)
	local time = now()
	local bucket = buckets[player]
	if not bucket then bucket = { tokens = Config.RequestBurst, time = time }; buckets[player] = bucket end
	if not State.AllowRequest(bucket, time, Config.RequestBurst, Config.RequestsPerSecond) then return end
	local state = states[player]
	if not state or tool ~= state.tool or state.character ~= player.Character or tool.Parent ~= state.character
		or state.round ~= getRound(player) then return end
	local health = State.Eat(state, time, state.humanoid.Health, state.humanoid.MaxHealth, Config)
	if not health then return end
	state.humanoid.Health = health
	if player:GetAttribute("TutorialActive")==true then require(script.Parent.Parent.Tutorial.TutorialRuntime).Record(player,"Heal",state.remaining) end
	publish(player, state)
	if state.remaining == 0 then tool:Destroy() end
end)

local function refresh(player)
	local character = player.Character
	if not getRound(player) then Food.Clear(player); return end
	if not character then return end
	-- Only lifecycle work may yield; eating and switching are synchronous.
	local round = getRound(player)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 5)
		local backpack = player:WaitForChild("Backpack", 5)
		if humanoid and backpack and player.Parent == Players and player.Character == character and getRound(player) == round then
			Food.Grant(player, character)
		end
	end)
end

local function bindPlayer(player)
	if connections[player] then return end
	connections[player] = {
		player.CharacterAdded:Connect(function() refresh(player) end),
		player.CharacterRemoving:Connect(function() Food.Clear(player) end),
		player:GetAttributeChangedSignal("InRound"):Connect(function() refresh(player) end),
		player:GetAttributeChangedSignal("DataReady"):Connect(function() refresh(player) end),
	}
	refresh(player)
end
gameActive.Changed:Connect(function() for _, player in ipairs(Players:GetPlayers()) do refresh(player) end end)
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	Food.Clear(player)
	for _, connection in ipairs(connections[player] or {}) do connection:Disconnect() end
	connections[player], buckets[player] = nil, nil
end)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
return Food
