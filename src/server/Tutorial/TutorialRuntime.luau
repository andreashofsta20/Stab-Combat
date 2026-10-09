-- Server-only bridge used by existing combat handlers. Authorization is based
-- on these registries, never tags/attributes sent by a client.
local Runtime = {}
local sessions, targets = {}, {}
function Runtime.Register(player, session) sessions[player]=session end
function Runtime.GetSession(player) return sessions[player] end
function Runtime.IsActive(player)
	local session=sessions[player]
	return session~=nil and session.Active==true and not session.Progress.Completed
end
function Runtime.Record(player, kind, evidence)
	local session=sessions[player]
	if Runtime.IsActive(player) and not session.Preparing and session.OnAction then session.OnAction(kind,evidence) end
end
function Runtime.RegisterTarget(player, model)
	assert(sessions[player], "Tutorial target needs a registered session")
	targets[model]={Owner=player, Session=sessions[player], Credited=false}
end
function Runtime.RemoveTarget(model) targets[model]=nil end
function Runtime.GetTarget(player, part)
	local current=part
	while current do
		local target=targets[current]
		if target then
			if target.Owner~=player or target.Session~=sessions[player] or not Runtime.IsActive(player) then return nil end
			local humanoid=current:FindFirstChildOfClass("Humanoid")
			return current.Parent and humanoid and humanoid.Health>0 and current or nil, humanoid
		end
		current=current.Parent
	end
	return nil
end
function Runtime.GetTargets(player)
	local result={}
	if not Runtime.IsActive(player) then return result end
	for model, target in pairs(targets) do
		local humanoid=model:FindFirstChildOfClass("Humanoid")
		if target.Owner==player and target.Session==sessions[player] and model.Parent and humanoid and humanoid.Health>0 then
			table.insert(result,model)
		end
	end
	return result
end
function Runtime.Damage(player, model, amount, kind)
	local target=targets[model]
	local character=player.Character
	local attacker=character and character:FindFirstChildOfClass("Humanoid")
	local humanoid=model and model:FindFirstChildOfClass("Humanoid")
	if not target or target.Owner~=player or target.Session~=sessions[player] or not Runtime.IsActive(player)
		or target.Session.Preparing==true
		or not model.Parent
		or not attacker or attacker.Health<=0 or not humanoid or humanoid.Health<=0
		or model:FindFirstChildOfClass("ForceField") or type(amount)~="number" or amount~=amount or amount<=0 or amount==math.huge then return 0 end
	local before=humanoid.Health
	humanoid:TakeDamage(math.min(amount,before))
	local dealt=math.max(0,before-humanoid.Health)
	if dealt>0 and humanoid.Health<=0 and not target.Credited then
		target.Credited=true
		Runtime.Record(player,kind,model)
		Runtime.Record(player,"Eliminate",model)
	end
	return dealt
end
function Runtime.OnDeath(player, character)
	local session=sessions[player]
	if session and session.OnDeath then session.OnDeath(character); return true end
	return false
end
function Runtime.Remove(player)
	for model,target in pairs(targets) do if target.Owner==player then targets[model]=nil end end
	sessions[player]=nil
end
return Runtime
