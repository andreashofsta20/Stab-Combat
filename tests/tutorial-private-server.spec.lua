local function newPlayer()
    local attrs = {
        DataReady = true,
        InRound = false,
        InventoryLocked = false,
        TutorialRewardPublishing = false,
        TutorialTravelPending = false,
    }
    local player = {
        UserId = 1,
        Parent = {},
        attributes = attrs,
    }

    function player:GetAttribute(name)
        return attrs[name]
    end

    function player:SetAttribute(name, value)
        attrs[name] = value
    end

    return player
end

local function newOptions()
    local options = {
        ReservedServerAccessCode = "",
        ServerInstanceId = "",
        Data = nil,
    }

    function options:SetTeleportData(data)
        self.Data = data
    end

    return options
end

local function loadCoordinator()
    return require(script.Parent.Parent.src.server.Tutorial.TutorialCoordinator)
end

local coordinatorModule = loadCoordinator()
local players = {}
local player = newPlayer()
player.Parent = players
players[1] = player

local travelCalls = {}
local controller = coordinatorModule.New({
    Players = players,
    RS = {
        GetAttribute = function() return true end,
    },
    Profiles = {
        GetProfile = function() return { IsActive = function() return true end } end,
    },
    Config = {
        Enabled = true,
        Version = 1,
        MainPlaceId = 11,
        TutorialPlaceId = 11,
        Rewards = { XP = 500, Gold = 500, Knife = "Shadow Dagger" },
        RewardSaveTimeoutSeconds = 20,
        AutoReturnSeconds = 8,
        DataReadyTimeoutSeconds = 3,
        RequestBurst = 100,
        RequestsPerSecond = 100,
        SampleSeconds = 0.1,
        ProgressPushSeconds = 0.25,
        SuccessPauseSeconds = 0.65,
        SessionTimeoutSeconds = 1800,
        PreparationTimeoutSeconds = 30,
        StartCooldownSeconds = 10,
    },
    State = {
        CanContinue = function() return true end,
        Step = function() return {} end,
    },
    Steps = { { Id = "welcome", Kind = "Read", Goal = 1, MinSeconds = 0 } },
    Rewards = {
        Assess = function() return "Eligible" end,
        ReadReceipt = function() return { XP = 0, Gold = 0, Knife = "Shadow Dagger" } end,
    },
    Runtime = {
        Remove = function() end,
        Register = function() end,
        GetTargets = function() return {} end,
        GetSession = function() return nil end,
    },
    Role = {
        IsTutorial = function() return false end,
        IsPreview = function() return false end,
    },
    Travel = {
        New = function(_, callback)
            return {
                IsPending = function() return false end,
                Start = function(p, placeId, options)
                    table.insert(travelCalls, { player = p, placeId = placeId, options = options })
                    return true
                end,
                Cancel = function() end,
                Destroy = function() end,
            }
        end,
    },
    Tickets = {
        New = function()
            return {
                Issue = function()
                    return { Token = "token", AccessCode = "secret" }
                end,
            }
        end,
    },
    Analytics = nil,
    Food = {
        Clear = function() end,
    },
    NewOptions = newOptions,
    Remote = {
        FireClient = function() end,
    },
})

controller.Handle(player, "Start")

assert(#travelCalls == 1, "same-place tutorial should reserve and teleport the player")
assert(travelCalls[1].placeId == 11, "same-place tutorial should use the main place ID")
assert(travelCalls[1].options.ReservedServerAccessCode == "secret", "same-place tutorial should include a reserved server access code")
print("PASS same-place tutorial private server")
