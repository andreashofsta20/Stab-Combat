-- Pure server state. No client-provided counts, health or timing are accepted.
local State = {}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function State.New(character, round, capacity)
	return { character = character, round = round, remaining = capacity, readyAt = 0 }
end
function State.Eat(state, time, health, maxHealth, config)
	if not finite(time) or not finite(health) or not finite(maxHealth) or health <= 0
		or maxHealth <= 0 or health >= maxHealth or state.remaining <= 0 or time < state.readyAt then return nil end
	state.remaining -= 1
	state.readyAt = time + config.CooldownMs / 1000
	return math.min(maxHealth, health + config.HealAmount)
end
function State.AllowRequest(bucket, time, capacity, rate)
	bucket.tokens = math.min(capacity, bucket.tokens + math.max(0, time - bucket.time) * rate)
	bucket.time = time
	if bucket.tokens < 1 then return false end
	bucket.tokens -= 1
	return true
end
return State
