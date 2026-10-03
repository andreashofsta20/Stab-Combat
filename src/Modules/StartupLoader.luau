local Config = require(script.Parent.StartupConfig)
local Loader = {}
local owners, queue = {}, {}
local running = false

function Loader.RequireChild(parent, name, className)
	local timeout = tonumber(Config.AssetWaitSeconds) or 10
	if timeout ~= timeout or timeout < 0 or timeout == math.huge then timeout = 10 end
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, timeout)
	assert(child, ("Missing required asset %s.%s after %.1fs"):format(parent.Name, name, timeout))
	if className then assert(child:IsA(className), parent.Name .. "." .. name .. " must be a " .. className) end
	return child
end

local function pump()
	if running then return end
	running = true
	task.defer(function()
		local index, batch = 1, 0
		local limit = math.clamp(math.floor(tonumber(Config.ModulesPerFrame) or 2), 1, 16)
		while index <= #queue do
			local launch = queue[index]
			index += 1
			launch()
			batch += 1
			if batch >= limit and index <= #queue then batch = 0; task.wait() end
		end
		table.clear(queue)
		running = false
	end)
end

-- One queue per VM spreads startup work across frames. Yielding/erroring jobs
-- run independently and cannot stop unrelated modules later in the queue.
function Loader.Start(owner, entries, onChanged)
	if owners[owner] then return owners[owner] end
	local state = {Records = {}, Ready = false, Complete = false, Loaded = 0, Failed = 0, Total = #entries}
	owners[owner] = state
	local function publish()
		local loaded, failed = 0, 0
		for _, record in ipairs(state.Records) do
			if record.State == "Ready" then loaded += 1 elseif record.State == "Failed" then failed += 1 end
		end
		state.Loaded, state.Failed = loaded, failed
		state.Complete = loaded + failed == state.Total
		state.Ready = loaded == state.Total
		owner:SetAttribute("StartupState", failed > 0 and "Failed" or state.Ready and "Ready" or "Loading")
		owner:SetAttribute("StartupLoaded", loaded)
		owner:SetAttribute("StartupTotal", state.Total)
		owner:SetAttribute("StartupFailed", failed)
		if onChanged then onChanged(state) end
	end
	for _, entry in ipairs(entries) do
		local record = {Name = entry.Name, State = "Queued"}
		table.insert(state.Records, record)
		table.insert(queue, function()
			record.State = "Loading"
			if entry.Module then entry.Module:SetAttribute("StartupState", "Loading") end
			local startedAt = os.clock()
			local warningAfter = tonumber(Config.SlowModuleWarningSeconds) or 10
			if warningAfter > 0 then
				task.delay(warningAfter, function()
					if record.State == "Loading" then
						warn(("[Startup] %s.%s is still loading after %.1fs; check its dependencies."):format(owner.Name, entry.Name, warningAfter))
					end
				end)
			end
			task.spawn(function()
				local ok, result = xpcall(function()
					if entry.Start then return entry.Start() end
					assert(entry.Module and entry.Module:IsA("ModuleScript"), "Missing ModuleScript: " .. entry.Name)
					local module = require(entry.Module)
					if entry.Init then entry.Init(module) end
					return module
				end, debug.traceback)
				record.State, record.Duration = ok and "Ready" or "Failed", os.clock() - startedAt
				if ok then record.Result = result else
					record.Error = tostring(result)
					warn(("[Startup] %s.%s failed: %s"):format(owner.Name, entry.Name, record.Error))
				end
				if entry.Module then
					entry.Module:SetAttribute("StartupState", record.State)
					entry.Module:SetAttribute("StartupDuration", record.Duration)
				end
				publish()
			end)
		end)
	end
	publish()
	pump()
	return state
end

return Loader
