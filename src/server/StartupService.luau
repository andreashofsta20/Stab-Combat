local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.StartupConfig)
local Loader = require(RS.Modules.StartupLoader)
local Startup = {}
local groups = {}
local registeredAt = os.clock()
RS:SetAttribute("ServerReady", false)
RS:SetAttribute("ServerStartupState", "Loading")

local function update()
	local ready, failed, pending = true, {}, {}
	for _, name in ipairs(Config.RequiredServerGroups) do
		local group = groups[name]
		if not group then ready = false; table.insert(pending, name) end
		if group then
			for _, record in ipairs(group.Records) do
				local optional = (Config.OptionalServerModules or {})[name] or {}
				if not table.find(optional, record.Name) and record.State ~= "Ready" then
					ready = false; table.insert(pending, name .. "." .. record.Name)
					if record.State == "Failed" then table.insert(failed, name .. "." .. record.Name) end
				end
			end
		end
	end
	RS:SetAttribute("ServerStartupPending", table.concat(pending, ", "))
	RS:SetAttribute("ServerStartupFailures", table.concat(failed, ", "))
	local timedOut = not ready and os.clock() - registeredAt >= (Config.ReadyTimeoutSeconds or 30)
	RS:SetAttribute("ServerStartupState", (#failed > 0 or timedOut) and "Failed" or ready and "Ready" or "Loading")
	RS:SetAttribute("ServerReady", ready)
end

function Startup.LoadGroup(folder, options)
	if groups[folder.Name] then return groups[folder.Name] end
	options = options or {}
	local entries, seen = {}, {}
	for _, entry in ipairs(options.Tasks or {}) do table.insert(entries, entry) end
	local function add(name)
		if seen[name] then return end
		seen[name] = true
		table.insert(entries, {Name = name, Module = folder:FindFirstChild(name), Init = (options.Init or {})[name]})
	end
	for _, name in ipairs(options.Priority or {}) do add(name) end
	local remaining = {}
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("ModuleScript") and not seen[item.Name] then table.insert(remaining, item.Name) end
	end
	table.sort(remaining)
	for _, name in ipairs(remaining) do add(name) end
	groups[folder.Name] = {Ready = false, Records = {}}
	groups[folder.Name] = Loader.Start(folder, entries, update)
	update()
	return groups[folder.Name]
end

function Startup.AwaitReady()
	while RS:GetAttribute("ServerReady") ~= true do
		RS:GetAttributeChangedSignal("ServerReady"):Wait()
	end
end

-- The game loop remains fail-closed and can recover if a late dependency
-- completes. A bounded timer publishes failure without cancelling its job.

if Config.SlowModuleWarningSeconds > 0 then
	task.delay(Config.SlowModuleWarningSeconds, function()
		for _, name in ipairs(Config.RequiredServerGroups) do
			if not groups[name] then warn("[Startup] Server group never registered: " .. name) end
		end
	end)
end

task.delay(Config.ReadyTimeoutSeconds or 30, update)

return Startup
