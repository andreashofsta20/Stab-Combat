-- A teleport payload contains a locator only. The server-only ticket is the
-- authority for admission, the destination reservation and return routing.
local Tickets = {}
Tickets.__index = Tickets

local function positiveInteger(value)
	return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

local function nonempty(value)
	return type(value) == "string" and #value > 0 and #value <= 256
end

local function validToken(value)
	return type(value) == "string" and #value >= 16 and #value <= 64
		and value:match("^[%w%-_]+$") ~= nil
end

function Tickets.New(config, deps)
	deps = deps or {}
	local context = deps.Game or game
	local store = deps.Store
	if not store then
		local memory = deps.MemoryStoreService or context:GetService("MemoryStoreService")
		store = memory:GetHashMap(config.TicketStoreName)
	end
	return setmetatable({
		Config = config,
		Game = context,
		Players = deps.Players or context:GetService("Players"),
		TeleportService = deps.TeleportService or context:GetService("TeleportService"),
		HttpService = deps.HttpService or context:GetService("HttpService"),
		Store = store,
		Now = deps.Now or os.time,
	}, Tickets)
end

function Tickets:Issue(player, replay)
	local config, context = self.Config, self.Game
	if not positiveInteger(config.TutorialPlaceId) or not positiveInteger(config.MainPlaceId)
		or context.PlaceId ~= config.MainPlaceId or not positiveInteger(context.GameId) then
		return nil, "TutorialNotConfigured"
	end
	-- Same-place tutorial runs are valid as private reserved servers. The main
	-- place can still be used as the tutorial destination when the player needs
	-- isolation without a separate published tutorial place.
	if not player or player.Parent ~= self.Players or not positiveInteger(player.UserId) then
		return nil, "PlayerUnavailable"
	end
	local ttl = config.TicketTTLSeconds
	if not positiveInteger(ttl) or ttl > 3888000 then return nil, "InvalidTicketExpiry" end
	local reserved, accessCode, privateServerId = pcall(function()
		return self.TeleportService:ReserveServerAsync(config.TutorialPlaceId)
	end)
	if not reserved or not nonempty(accessCode) or not nonempty(privateServerId) then
		return nil, "TicketReservationFailed"
	end
	-- Reservation and storage yield. A departed player must never receive a
	-- newly issued credential or cause another teleport after those yields.
	if player.Parent ~= self.Players then return nil, "PlayerUnavailable" end
	local token = self.HttpService:GenerateGUID(false)
	if not validToken(token) then return nil, "TicketCreationFailed" end
	local record = {
		Version = config.Version,
		UserId = player.UserId,
		UniverseId = context.GameId,
		SourcePlaceId = context.PlaceId,
		TutorialPlaceId = config.TutorialPlaceId,
		PrivateServerId = privateServerId,
		ExpiresAt = self.Now() + ttl,
		ReturnPlaceId = config.MainPlaceId,
		-- ServerInstanceId routes public servers. A reserved/private source
		-- cannot be restored with its JobId; return to the main place instead.
		ReturnJobId = context.PrivateServerId == "" and context.JobId or "",
		Replay = replay == true,
		ClaimedJobId = "",
	}
	local saved = pcall(function() self.Store:SetAsync(token, record, ttl) end)
	if not saved then return nil, "TicketStorageUnavailable" end
	if player.Parent ~= self.Players then return nil, "PlayerUnavailable" end
	return {
		Token = token,
		AccessCode = accessCode,
		PrivateServerId = privateServerId,
		ExpiresAt = record.ExpiresAt,
		ReturnPlaceId = record.ReturnPlaceId,
		ReturnJobId = record.ReturnJobId,
		Replay = record.Replay,
	}
end

function Tickets:Claim(player)
	local config, context = self.Config, self.Game
	if not positiveInteger(config.TutorialPlaceId) or context.PlaceId ~= config.TutorialPlaceId
		or not nonempty(context.PrivateServerId) or context.PrivateServerOwnerId ~= 0
		or not nonempty(context.JobId) then return nil, "InvalidTutorialServer" end
	if not player or player.Parent ~= self.Players or not positiveInteger(player.UserId) then
		return nil, "PlayerUnavailable"
	end
	local joined, data = pcall(function() return player:GetJoinData() end)
	if not joined or type(data) ~= "table" or data.SourceGameId ~= context.GameId
		or data.SourcePlaceId ~= config.MainPlaceId then return nil, "InvalidTutorialSource" end
	local payload = data.TeleportData
	if type(payload) ~= "table" then return nil, "MissingTutorialTicket" end
	local token = payload.TutorialToken or payload.Token
	if not validToken(token) then return nil, "MissingTutorialTicket" end
	if payload.TutorialVersion ~= nil and payload.TutorialVersion ~= config.Version then
		return nil, "UnsupportedTutorialVersion"
	end
	local claimId = self.HttpService:GenerateGUID(false)
	local claimed, record = pcall(function()
		return self.Store:UpdateAsync(token, function(current)
			-- The transform can run more than once. It performs no grants,
			-- network requests, replication or other external side effects.
			if type(current) ~= "table" or current.Version ~= config.Version
				or current.UserId ~= player.UserId or current.UniverseId ~= context.GameId
				or current.SourcePlaceId ~= config.MainPlaceId
				or current.TutorialPlaceId ~= config.TutorialPlaceId
				or current.PrivateServerId ~= context.PrivateServerId
				or current.ReturnPlaceId ~= config.MainPlaceId
				or not positiveInteger(current.ExpiresAt) or current.ExpiresAt <= self.Now()
				or type(current.ReturnJobId) ~= "string" or #current.ReturnJobId > 256
				or type(current.Replay) ~= "boolean"
				or current.ClaimedJobId ~= "" or player.Parent ~= self.Players then return nil end
			local nextRecord = table.clone(current)
			nextRecord.ClaimedJobId, nextRecord.ClaimId = context.JobId, claimId
			return nextRecord
		end, config.TicketTTLSeconds)
	end)
	if not claimed then return nil, "TicketStorageUnavailable" end
	if type(record) ~= "table" or record.ClaimedJobId ~= context.JobId or record.ClaimId ~= claimId then
		return nil, "TutorialTicketRejected"
	end
	if player.Parent ~= self.Players then return nil, "PlayerUnavailable" end
	return record
end

return Tickets
