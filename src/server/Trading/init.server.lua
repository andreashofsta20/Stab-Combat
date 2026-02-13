-- TRADING SYSTEM INITIALIZATION

local TradeManager = require(script:WaitForChild("TradeManager"))
local TradeRequestsHandler = require(script:WaitForChild("TradeRequestsHandler"))

TradeManager.Init()

TradeRequestsHandler.Init()




