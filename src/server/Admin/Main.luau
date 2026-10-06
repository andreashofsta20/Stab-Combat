local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Commands = require(script.Parent:WaitForChild("Commands"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminRemote")
local MAX_ARGS = 8
local MAX_STRING_ARG_LENGTH = 256
local nextRequest = {}
local running = {}

local function dispatch(player, category: string, command: string, args: { any })
    local adminId = player.UserId
    if not Commands.CheckAdmin(adminId) then
        return
    end

    local categoryTable = Commands[category]
    if not categoryTable or not categoryTable.Commands then
        warn("Unknown category:", category)
        return
    end

    local fn = categoryTable.Commands[command]
    if typeof(fn) ~= "function" then
        warn("Unknown command:", category, command)
        return
    end

    local ok, err = pcall(function()
        fn(adminId, table.unpack(args, 1, args.n))
    end)
    if not ok then
        warn("Admin command error:", err)
    end
end

AdminRemote.OnServerEvent:Connect(function(player, category, command, ...)
    if not Commands.CheckAdmin(player.UserId) then return end
    if running[player] then return end
    local now = os.clock()
    if now < (nextRequest[player] or 0) then return end
    nextRequest[player] = now + 0.25
    if type(category) ~= "string" or type(command) ~= "string" then
        return
    end
    if #category > 64 or #command > 64 then
        return
    end

    local argCount = select("#", ...)
    if argCount > MAX_ARGS then
        return
    end
    local args = { ... }
    args.n = argCount
    for index = 1, argCount do
        local arg = args[index]
        local t = type(arg)
        if t == "nil" then continue end -- optional command arguments
        if t ~= "string" and t ~= "number" and t ~= "boolean" then
            return
        end
        if t == "string" and #arg > MAX_STRING_ARG_LENGTH then
            return
        end
        if t == "number" and (arg ~= arg or math.abs(arg) == math.huge) then return end
    end

    running[player] = true
    local ok, err = pcall(dispatch, player, category, command, args)
    running[player] = nil
    if not ok then warn("Admin dispatch failed: " .. tostring(err)) end
end)
Players.PlayerRemoving:Connect(function(player) nextRequest[player], running[player] = nil, nil end)

return {}
