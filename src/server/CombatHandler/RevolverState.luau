-- Pure authoritative magazine/reload state. No Tools, remotes, or yielding.
local State = {}

function State.New(capacity)
	return { ammo = capacity, reloadEnd = 0, nextShot = 0, sequence = 0, revision = 0 }
end

function State.Advance(state, now, capacity)
	if state.reloadEnd > 0 and now >= state.reloadEnd then
		state.ammo = capacity
		state.reloadEnd = 0
		state.revision += 1
		return true
	end
	return false
end

function State.AcceptSequence(state, sequence)
	if type(sequence) ~= "number" or sequence ~= sequence or sequence == math.huge
		or sequence <= state.sequence or sequence % 1 ~= 0 or sequence > 2147483647 then return false end
	state.sequence = sequence
	return true
end

function State.Fire(state, now, cooldownSeconds, capacity)
	State.Advance(state, now, capacity)
	if state.reloadEnd > 0 then return false, "Reloading" end
	if now < state.nextShot then return false, "Cooldown" end
	if state.ammo <= 0 then return false, "Empty" end
	state.ammo -= 1
	state.nextShot = now + cooldownSeconds
	state.revision += 1
	return true
end

function State.Reload(state, now, durationSeconds, capacity)
	State.Advance(state, now, capacity)
	if state.reloadEnd > 0 then return false, "Reloading" end
	if state.ammo >= capacity then return false, "Full" end
	state.reloadEnd = now + durationSeconds
	state.revision += 1
	State.Advance(state, now, capacity)
	return true
end

function State.CancelReload(state)
	if state.reloadEnd == 0 then return false end
	state.reloadEnd = 0
	state.revision += 1
	return true
end

function State.AllowRequest(bucket, now, burst, perSecond)
	bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.time) * perSecond)
	bucket.time = now
	if bucket.tokens < 1 then return false end
	bucket.tokens -= 1
	return true
end

return State
