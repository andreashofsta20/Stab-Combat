local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Commands = require(script.Parent:WaitForChild("Commands"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminRemote")
local MAX_ARGS = 8
local MAX_STRING_ARG_LENGTH = 256

local function dispatch(player, category: string, command: string, args: { any })
    print("Dispatch from", player.UserId, category, command, args)
    local adminId = player.UserId
    if not Commands.CheckAdmin(adminId) then
        warn(("Unauthorized admin call from %d for %s.%s"):format(adminId, tostring(category), tostring(command)))
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
        fn(adminId, table.unpack(args))
    end)
    if not ok then
        warn("Admin command error:", err)
    end
end

AdminRemote.OnServerEvent:Connect(function(player, category, command, ...)
    if type(category) ~= "string" or type(command) ~= "string" then
        return
    end
    if #category > 64 or #command > 64 then
        return
    end

    local args = { ... }
    if #args > MAX_ARGS then
        return
    end
    for _, arg in ipairs(args) do
        if type(arg) == "string" and #arg > MAX_STRING_ARG_LENGTH then
            return
        end
    end

    dispatch(player, category, command, args)
end)

return {}