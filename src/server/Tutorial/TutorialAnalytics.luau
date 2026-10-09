-- Observability only: server lessons call this after validated actions.
-- Analytics delivery can never authorize progress, rewards or travel.
local Analytics = {}
Analytics.__index = Analytics

local function text(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end

local function integer(value, minimum, maximum)
	return type(value) == "number" and value == value and value >= minimum and value <= maximum and value % 1 == 0
end

function Analytics.New(config, deps)
	deps = deps or {}
	local context = deps.Game or game
	local settings = type(config) == "table" and config.Analytics
	local self = setmetatable({Enabled = false, Sessions = {}, Destroyed = false,
		Spawn = deps.Spawn or (task and task.spawn), Version = type(config) == "table" and config.Version,
		Players = deps.Players, Service = deps.AnalyticsService, Steps = deps.Steps}, Analytics)
	-- Disabled analytics never requests platform services or loads dependencies.
	if type(settings) ~= "table" or settings.Enabled ~= true then return self end
	if not text(settings.FunnelName, 50) or not integer(self.Version, 1, 2147483647) then return self end
	local ready = pcall(function()
		self.Players = self.Players or context:GetService("Players")
		self.Service = self.Service or context:GetService("AnalyticsService")
		if not self.Steps then self.Steps = require(context:GetService("ReplicatedStorage").Modules.TutorialSteps) end
		self.IsStudio = deps.IsStudio or function() return context:GetService("RunService"):IsStudio() end
	end)
	if not ready or type(self.Steps) ~= "table" or #self.Steps < 1 or #self.Steps > 98 then return self end
	self.FunnelName, self.Enabled = settings.FunnelName .. "_Replay", true
	self.LeaveConnection = self.Players.PlayerRemoving:Connect(function(player) self.Sessions[player] = nil end)
	return self
end

function Analytics:_Available(player)
	if self.Destroyed or not self.Enabled or not player or player.Parent ~= self.Players then return false end
	local ok, studio = pcall(self.IsStudio)
	return ok and studio ~= true
end

function Analytics:_Fields(replay, lastIndex)
	-- These are the documented enum key names. Keep values low-cardinality:
	-- no usernames, user IDs, reservation codes or ticket/session IDs.
	return {CustomField01 = "Version - " .. tostring(self.Version),
		CustomField02 = replay and "Mode - Replay" or "Mode - Onboarding",
		CustomField03 = lastIndex ~= nil and "Last lesson - " .. tostring(lastIndex) or "Map - Studs"}
end

function Analytics:_Send(player, fn)
	-- Claim/dedupe before scheduling. A failing backend is dropped without a
	-- retry loop that could amplify quota use or affect the gameplay caller.
	self.Spawn(function()
		if not self:_Available(player) then return end
		pcall(fn)
	end)
end

function Analytics:_Funnel(player, session, step, name)
	local fields = self:_Fields(session.Replay)
	self:_Send(player, function()
		if session.Replay then
			self.Service:LogFunnelStepEvent(player, self.FunnelName, session.Id, step, name, fields)
		else
			self.Service:LogOnboardingFunnelStepEvent(player, step, name, fields)
		end
	end)
end

function Analytics:Started(player, sessionId, replay)
	if not self:_Available(player) or not text(sessionId, 128) then return false end
	local old = self.Sessions[player]
	if old and (old.Id == sessionId or not old.Terminal) then return false end
	local session = {Id = sessionId, Replay = replay == true, LastIndex = 0, Terminal = false}
	self.Sessions[player] = session
	self:_Funnel(player, session, 1, "Started")
	return true
end

-- index identifies a COMPLETED configured lesson, not a client request or a
-- lesson merely displayed. Sequential validation avoids falsely filling the
-- preceding funnel steps, which Roblox does when higher steps are logged.
function Analytics:Step(player, sessionId, index, name, replay)
	if not self:_Available(player) then return false end
	local session = self.Sessions[player]
	if not session or session.Id ~= sessionId or session.Terminal or session.Replay ~= (replay == true)
		or not integer(index, 1, #self.Steps) or index ~= session.LastIndex + 1 then return false end
	local configured = self.Steps[index]
	if type(configured) ~= "table" then return false end
	if name ~= nil and name ~= configured.Id and name ~= configured.Title then return false end
	local label = configured.Id or configured.Title
	if not text(label, 100) then return false end
	session.LastIndex = index
	self:_Funnel(player, session, index + 1, label)
	return true
end

function Analytics:Completed(player, sessionId, replay)
	if not self:_Available(player) then return false end
	local session = self.Sessions[player]
	if not session or session.Id ~= sessionId or session.Terminal or session.Replay ~= (replay == true)
		or session.LastIndex ~= #self.Steps then return false end
	session.Terminal = true
	self:_Funnel(player, session, #self.Steps + 2, "Completed")
	return true
end

function Analytics:Skipped(player, sessionId, replay)
	if sessionId == nil and self.Sessions[player] == nil then sessionId = "lobby-offer" end
	if not self:_Available(player) or not text(sessionId, 128) then return false end
	local session = self.Sessions[player]
	if session and (session.Id ~= sessionId or session.Terminal or session.Replay ~= (replay == true)) then return false end
	-- Skipping the optional lobby invitation needs no Started funnel event.
	-- Record a separate outcome, never a later funnel step: a later step would
	-- implicitly mark every earlier lesson completed in Roblox's charts.
	if not session then
		session = {Id = sessionId, Replay = replay == true, LastIndex = 0}
		self.Sessions[player] = session
	end
	session.Terminal = true
	local fields = self:_Fields(session.Replay, session.LastIndex)
	self:_Send(player, function() self.Service:LogCustomEvent(player, "TutorialSkipped", 1, fields) end)
	return true
end

function Analytics:Remove(player)
	self.Sessions[player] = nil
end

function Analytics:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	if self.LeaveConnection then self.LeaveConnection:Disconnect() end
	table.clear(self.Sessions)
end

return Analytics
