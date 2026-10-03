require(script.Parent.StartupService).LoadGroup(script, {
	Priority = {"TradeManager", "TradeRequestsHandler"},
	Init = {
		TradeManager = function(module) module.Init() end,
		TradeRequestsHandler = function(module) module.Init() end,
	},
})
