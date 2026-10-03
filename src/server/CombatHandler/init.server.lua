require(script.Parent.StartupService).LoadGroup(script, {
	Priority = {"PlayerHitbox", "HandleKnife", "HandleRevolver", "FoodService", "HandleHotbar"},
	Init = {PlayerHitbox = function(module) module.Init() end},
})
