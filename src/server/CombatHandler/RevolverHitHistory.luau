local Players = game:GetService("Players")
local Math = require(game:GetService("ReplicatedStorage").Modules.RevolverMath)
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
			table.insert(list, { time = now, frame = root.CFrame, character = character, round = round })
			while #list > config.MaxHistorySamples do table.remove(list, 1) end
			frames[player] = list
		else
			frames[player] = nil
		end
	end
end

function History.GetFrame(player, character, round, time, currentFrame, config)
	local list = frames[player]
	if not list or #list == 0 then return currentFrame end
	local latest = list[#list]
	-- Also catch teleports occurring between the most recent sample and this shot.
	if latest.character ~= character or latest.round ~= round
		or (latest.frame.Position - currentFrame.Position).Magnitude > config.TeleportResetDistance then
		frames[player] = nil
		return currentFrame
	end
	-- Never extrapolate backwards across respawns, teleports or a new round.
	if time < list[1].time then return currentFrame end
	for index = #list, 1, -1 do
		local before = list[index]
		if before.time <= time and before.character == character and before.round == round then
			local after = list[index + 1]
			if after and after.character == character and after.round == round then
				local alpha = math.clamp((time - before.time) / (after.time - before.time), 0, 1)
				return before.frame:Lerp(after.frame, alpha)
			end
			return before.frame
		end
	end
	return currentFrame
end

function History.Remove(player) frames[player] = nil end
return History
