-- Pure progress rules. Client packets never call Record directly.
local State = {}
local function finite(value)
	return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function State.New(steps, now)
	return {Steps=steps, Index=1, Progress=0, StartedAt=now, StepStartedAt=now, Completed=false, Credited={}}
end
function State.Step(state) return state.Steps[state.Index] end
function State.CanContinue(state, now)
	local step = State.Step(state)
	return not state.Completed and step ~= nil and now-state.StepStartedAt >= (step.MinSeconds or 0)
		and (step.Kind=="Read" or state.Progress >= step.Goal)
end
function State.Record(state, kind, amount, evidence)
	local step = State.Step(state)
	if state.Completed or not step or step.Kind=="Read" or step.Kind~=kind then return false end
	if not finite(amount) or amount<=0 then return false end
	if evidence then
		if state.Credited[evidence] then return false end
		state.Credited[evidence]=true
	end
	state.Progress=math.min(step.Goal,state.Progress+amount)
	return true
end
function State.Advance(state, now)
	if not State.CanContinue(state,now) then return false end
	if state.Index==#state.Steps then state.Completed=true; return true end
	state.Index+=1; state.Progress=0; state.StepStartedAt=now; state.Credited={}
	return true
end
function State.AllowRequest(bucket, now, burst, rate)
	bucket.Tokens=math.min(burst,(bucket.Tokens or burst)+math.max(0,now-(bucket.At or now))*rate)
	bucket.At=now
	if bucket.Tokens<1 then return false end
	bucket.Tokens-=1
	return true
end
return State
