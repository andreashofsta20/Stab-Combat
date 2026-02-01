local SpawnMapModule = require(script.Parent.SpawnMap)
local RoundHandlerModule = require(script.Parent.RoundHandler)
local VotingHandlerModule = require(script.Parent.VotingHandler)



task.wait(2)



RoundHandlerModule.ChangeStatus("Waiting for game to load")


task.wait(5)

RoundHandlerModule.ChangeStatus("Game loaded")


task.wait(3)


return {}