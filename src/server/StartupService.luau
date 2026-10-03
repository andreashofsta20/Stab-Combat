local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.StartupConfig)
local Loader = require(RS.Modules.StartupLoader)
local Startup = {}
local groups = {}
RS:SetAttribute("ServerReady", false)
RS:SetAttribute("ServerStartupState", "Loading")

local function update()
	local ready, failed, pending = true, {}, {}
	for _, name in ipairs(Config.RequiredServerGroups) do
		local group = groups[name]
		if not group or not group.Ready then ready = false; table.insert(pending, name) end
		if group then
			for _, record in ipairs(group.Records) do
				if record.State == "Failed" then table.insert(failed, name .. "." .. record.Name) end
			end
		end
	end
	RS:SetAttribute("ServerStartupPending", table.concat(pending, ", "))
	RS:SetAttribute("ServerStartupFailures", table.concat(failed, ", "))
	RS:SetAttribute("ServerStartupState", #failed > 0 and "Failed" or ready and "Ready" or "Loading")
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

if Config.SlowModuleWarningSeconds > 0 then
	task.delay(Config.SlowModuleWarningSeconds, function()
		for _, name in ipairs(Config.RequiredServerGroups) do
			if not groups[name] then warn("[Startup] Server group never registered: " .. name) end
		end
	end)
end

return Startup
