-- Small reusable state; no Animator tracks, tweens, Instances or camera writes.
local Config = require(script.Parent.WeaponInspectConfig)
local Motion = {}
local presets = {}
for _, kind in ipairs({"Revolver", "Knife"}) do
	local source, frames = Config[kind], {}
	for _, key in ipairs(source.Frames) do
		local p, r = key.Position, key.Rotation
		table.insert(frames, {time = key.Time, frame = CFrame.new(p[1], p[2], p[3])
			* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))})
	end
	presets[kind] = {duration = source.Duration, frames = frames}
end

local function ease(t) return t * t * (3 - 2 * t) end

function Motion.New()
	return {playing = false, returning = false, elapsed = 0, segment = 1, pose = CFrame.identity}
end

function Motion.IsActive(state) return state.playing or state.returning end

function Motion.Start(state, kind)
	if Motion.IsActive(state) or not presets[kind] then return false end
	state.preset, state.playing, state.elapsed, state.segment = presets[kind], true, 0, 1
	state.pose = CFrame.identity
	return true
end

function Motion.Cancel(state, immediate)
	if immediate then
		state.playing, state.returning, state.pose = false, false, CFrame.identity
		state.preset, state.returnFrom = nil, nil
	elseif state.playing then
		state.playing, state.returning, state.elapsed, state.returnFrom = false, true, 0, state.pose
	end
end

function Motion.Step(state, dt)
	if not Motion.IsActive(state) then return CFrame.identity end
	state.elapsed += math.max(0, dt)
	if state.returning then
		local t = math.min(1, state.elapsed / Config.ReturnSeconds)
		state.pose = state.returnFrom:Lerp(CFrame.identity, ease(t))
		if t == 1 then Motion.Cancel(state, true) end
	else
		local preset = state.preset
		local t = math.min(1, state.elapsed / preset.duration)
		if t == 1 then Motion.Cancel(state, true); return CFrame.identity end
		local frames, segment = preset.frames, state.segment
		while segment < #frames - 1 and t >= frames[segment + 1].time do segment += 1 end
		state.segment = segment
		local first, last = frames[segment], frames[segment + 1]
		state.pose = first.frame:Lerp(last.frame, ease((t - first.time) / (last.time - first.time)))
	end
	return state.pose
end

return Motion
