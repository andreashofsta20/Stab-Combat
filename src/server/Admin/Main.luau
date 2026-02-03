local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Commands = require(script.Parent:WaitForChild("Commands"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin"):WaitForChild("AdminRemote")

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
    dispatch(player, category, command, { ... })
end)

return {}