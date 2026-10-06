local Players = game:GetService("Players")
local Math = require(game:GetService("ReplicatedStorage").Modules.RevolverMath)
local Raycast = require(game:GetService("ReplicatedStorage").Modules.RevolverRaycast)
local History = {}
local frames = {}

function History.Sample(now, round, members, config)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if round and members[player.UserId] and root and root:IsA("BasePart")
			and humanoid and humanoid.Health > 0 and Math.IsFiniteVector(root.Position, 1000000) then
			local list = frames[player] or {}
			local previous = list[#list]
			if previous and (previous.character ~= character or previous.round ~= round
				or (previous.frame.Position - root.Position).Magnitude > config.TeleportResetDistance) then
				table.clear(list)
			end
			local snapshot = Raycast.GetCharacterGeometry(character)
			snapshot.time, snapshot.frame, snapshot.character, snapshot.round = now, root.CFrame, character, round
			table.insert(list, snapshot)
			while #list > config.MaxHistorySamples do table.remove(list, 1) end
			frames[player] = list
		else
			frames[player] = nil
		end
	end
end

local function bracket(player, character, round, time, currentFrame, config)
	if config.Enabled == false then return nil end
	local list = frames[player]
	if not list or #list == 0 then return nil end
	local latest = list[#list]
	-- Also catch teleports occurring between the most recent sample and this shot.
	if latest.character ~= character or latest.round ~= round
		or (latest.frame.Position - currentFrame.Position).Magnitude > config.TeleportResetDistance then
		frames[player] = nil
		return nil
	end
	-- Never extrapolate backwards across respawns, teleports or a new round.
	if time < list[1].time then return nil end
	-- A server hitch must not let a query hold on to a much older pose than
	-- the bounded rewind time requested by the shooting handler.
	if time - latest.time > 1 / config.SampleHz + 0.001 then return nil end
	for index = #list, 1, -1 do
		local before = list[index]
		if before.time <= time and before.character == character and before.round == round then
			local after = list[index + 1]
			if after and after.character == character and after.round == round then
				local alpha = math.clamp((time - before.time) / (after.time - before.time), 0, 1)
				return before, after, alpha
			end
			return before
		end
	end
	return nil
end

function History.GetFrame(player, character, round, time, currentFrame, config)
	local before, after, alpha = bracket(player, character, round, time, currentFrame, config)
	return before and (after and before.frame:Lerp(after.frame, alpha) or before.frame) or currentFrame
end

local function interpolateSize(before, after, alpha)
	return {before[1] + (after[1] - before[1]) * alpha,
		before[2] + (after[2] - before[2]) * alpha, before[3] + (after[3] - before[3]) * alpha}
end

function History.GetSnapshot(player, character, round, time, currentFrame, config)
	local before, after, alpha = bracket(player, character, round, time, currentFrame, config)
	if not before then
		local current = Raycast.GetCharacterGeometry(character)
		current.frame = currentFrame
		return current
	end
	if not after then return table.clone(before) end
	local result = {frame = before.frame:Lerp(after.frame, alpha), bodyParts = {}}
	-- The head and its blockers rewind together. Never manufacture head
	-- geometry by applying an old root transform to a current animation pose.
	if before.headPart and before.headPart == after.headPart then
		result.headPart = before.headPart
		result.headFrame = before.headFrame:Lerp(after.headFrame, alpha)
		result.headSize = interpolateSize(before.headSize, after.headSize, alpha)
	end
	local afterParts = {}
	for _, body in ipairs(after.bodyParts) do afterParts[body.part] = body end
	for _, body in ipairs(before.bodyParts) do
		local nextBody = afterParts[body.part]
		-- Newly replaced body parts invalidate precise head classification for
		-- this interval rather than allowing a shot through an unknown blocker.
		if not nextBody then result.headFrame, result.headSize, result.headPart = nil, nil, nil end
		table.insert(result.bodyParts, nextBody and {part = body.part,
			frame = body.frame:Lerp(nextBody.frame, alpha), size = interpolateSize(body.size, nextBody.size, alpha)} or body)
		afterParts[body.part] = nil
	end
	if next(afterParts) then result.headFrame, result.headSize, result.headPart = nil, nil, nil end
	return result
end

function History.Remove(player) frames[player] = nil end
return History
