-- Bounded travel lifecycle. Async request acceptance is not a completed
-- teleport: late failures and a player left behind are handled separately.
local Travel = {}
Travel.__index = Travel

local function validPlace(value)
	return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

local function safeData(options)
	if not options then return {} end
	local ok, value = pcall(function() return options:GetTeleportData() end)
	if not ok or (value ~= nil and type(value) ~= "table") then return nil end
	return value and table.clone(value) or {}
end

local function resultName(result)
	if type(result) == "string" then return result end -- deterministic fixtures
	local ok, name = pcall(function() return result.Name end)
	return ok and name or "Unknown"
end

function Travel.New(config, onFailure, deps)
	deps = deps or {}
	local context = deps.Game or game
	local self = setmetatable({
		Config = config.Teleport,
		Places = config,
		Players = deps.Players or context:GetService("Players"),
		TeleportService = deps.TeleportService or context:GetService("TeleportService"),
		HttpService = deps.HttpService or context:GetService("HttpService"),
		NewOptions = deps.NewOptions or function() return Instance.new("TeleportOptions") end,
		Spawn = deps.Spawn or task.spawn,
		Delay = deps.Delay or task.delay,
		Warn = deps.Warn or warn,
		OnFailure = onFailure,
		Pending = {},
		Destroyed = false,
	}, Travel)
	self.FailureConnection = self.TeleportService.TeleportInitFailed:Connect(function(player, result, _, placeId, options)
		local operation = self.Pending[player]
		if not operation or not operation.Awaiting or operation.PlaceId ~= placeId then return end
		local data = safeData(options)
		if not data or data.TutorialTravelNonce ~= operation.AttemptNonce then return end
		-- Duplicate events and failures from earlier operations/attempts cannot
		-- create another worker or clear the currently active operation.
		operation.Awaiting = false
		local name = resultName(result)
		local failure = {Reason = name, Retry = name == "Failure" or name == "Flooded",
			Delay = name == "Flooded" and self.Config.FloodDelaySeconds or self.Config.RetryDelaySeconds}
		if operation.InFlight then operation.DeferredFailure = failure
		else self:_HandleFailure(player, operation, failure) end
	end)
	self.LeaveConnection = self.Players.PlayerRemoving:Connect(function(player) self:Cancel(player) end)
	return self
end

function Travel:_Current(player, operation)
	return not self.Destroyed and self.Pending[player] == operation and player.Parent == self.Players
end

function Travel:_Fail(player, operation, reason)
	if self.Pending[player] ~= operation then return end
	self.Pending[player] = nil
	operation.Awaiting = false
	if player.Parent == self.Players and self.OnFailure then
		local ok = pcall(self.OnFailure, player, reason, operation)
		if not ok then self.Warn("[Tutorial] Travel recovery callback failed") end
	end
end

function Travel:_HandleFailure(player, operation, failure)
	if not self:_Current(player, operation) then return end
	operation.Awaiting = false
	if not failure.Retry or operation.Attempts >= self.Config.MaxAttempts then
		self:_Fail(player, operation, failure.Reason)
		return
	end
	operation.RetryScheduled = true
	self.Delay(failure.Delay, function()
		if not self:_Current(player, operation) or not operation.RetryScheduled then return end
		operation.RetryScheduled = false
		self:_Launch(player, operation)
	end)
end

function Travel:_Launch(player, operation)
	if not self:_Current(player, operation) then return end
	operation.Attempts += 1
	operation.AttemptNonce = self.HttpService:GenerateGUID(false)
	operation.Awaiting, operation.InFlight = true, true
	local ok = pcall(function()
		-- Fresh options keep Roblox's echoed failure options immutable for
		-- correlation. Retry always uses the original explicit reservation.
		local options = self.NewOptions()
		options.ReservedServerAccessCode = operation.AccessCode
		options.ServerInstanceId = operation.ServerInstanceId
		local data = table.clone(operation.Data)
		data.TutorialTravelNonce = operation.AttemptNonce
		options:SetTeleportData(data)
		operation.Options = options
		self.TeleportService:TeleportAsync(operation.PlaceId, {player}, options)
	end)
	operation.InFlight = false
	if not self:_Current(player, operation) then return end
	local failure = operation.DeferredFailure
	operation.DeferredFailure = nil
	if failure then self:_HandleFailure(player, operation, failure)
	elseif not ok then
		self:_HandleFailure(player, operation, {Reason = "RequestFailed", Retry = true, Delay = self.Config.RetryDelaySeconds})
	end
end

function Travel:Start(player, placeId, options)
	if self.Destroyed then return false, "TravelUnavailable" end
	if not player or player.Parent ~= self.Players then return false, "PlayerUnavailable" end
	if self.Pending[player] then return false, "TravelPending" end
	if not validPlace(placeId) or (placeId ~= self.Places.MainPlaceId and placeId ~= self.Places.TutorialPlaceId) then
		return false, "InvalidTravelDestination"
	end
	local data = safeData(options)
	if not data then return false, "InvalidTravelData" end
	local read, accessCode, instanceId, shouldReserve = pcall(function()
		return options and options.ReservedServerAccessCode or "",
			options and options.ServerInstanceId or "", options and options.ShouldReserveServer
	end)
	if not read or type(accessCode) ~= "string" or type(instanceId) ~= "string"
		or (accessCode ~= "" and instanceId ~= "") or shouldReserve == true then
		return false, "InvalidTravelOptions"
	end
	if placeId == self.Places.TutorialPlaceId and placeId ~= self.Places.MainPlaceId and accessCode == "" then
		return false, "MissingReservation"
	end
	local operation = {PlaceId = placeId, Data = data, AccessCode = accessCode,
		ServerInstanceId = instanceId, Attempts = 0, Awaiting = false}
	self.Pending[player] = operation -- claim before scheduling any yielding work
	self.Delay(self.Config.WatchdogSeconds, function()
		if self:_Current(player, operation) then self:_Fail(player, operation, "TravelTimedOut") end
	end)
	self.Spawn(function() self:_Launch(player, operation) end)
	return true
end

function Travel:IsPending(player)
	return self.Pending[player] ~= nil
end

function Travel:Cancel(player)
	self.Pending[player] = nil
end

function Travel:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.FailureConnection:Disconnect()
	self.LeaveConnection:Disconnect()
	table.clear(self.Pending)
end

return Travel
