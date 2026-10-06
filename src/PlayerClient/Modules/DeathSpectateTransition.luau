-- A brief, owned camera transition. It creates no parts or render connections
-- while idle and never changes CameraMode, zoom limits or character physics.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local Config = require(ReplicatedStorage.Modules.SpectateConfig)
local RagdollQuery = require(ReplicatedStorage.Modules.RagdollQuery)
local Transition = {}

function Transition.New(player)
	local controller = {}
	local generation = 0
	local pendingThread, renderConnection
	local ownedCamera, ownedSubject

	local function writePose(camera, frame, focus)
		camera.CFrame, camera.Focus = frame, focus
	end

	local function ownsCamera()
		if not ownedCamera or workspace.CurrentCamera ~= ownedCamera
			or ownedCamera.CameraType ~= Enum.CameraType.Scriptable then return false end
		local character = player.Character
		local currentHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- CFrame/Focus are presentation, not an ownership signal. Native camera
		-- updates and other offsets must not strand our temporary Scriptable mode.
		-- The engine may clear a destroyed subject before CharacterRemoving runs.
		return ownedCamera.CameraSubject == nil or ownedCamera.CameraSubject == ownedSubject
			or currentHumanoid ~= nil and ownedCamera.CameraSubject == currentHumanoid
	end

	local function releaseCamera()
		if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
		if ownsCamera() then
			if ownedCamera.CameraSubject == nil then
				local character = player.Character
				ownedCamera.CameraSubject = character and character:FindFirstChildOfClass("Humanoid") or nil
			end
			ownedCamera.CameraType = Enum.CameraType.Custom
		end
		ownedCamera, ownedSubject = nil, nil
	end

	function controller.Cancel()
		generation += 1
		if pendingThread then task.cancel(pendingThread); pendingThread = nil end
		releaseCamera()
	end

	function controller.IsPending()
		return pendingThread ~= nil
	end

	function controller.Begin(character, onReady)
		controller.Cancel()
		local camera = workspace.CurrentCamera
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not camera or not humanoid or player.Character ~= character or humanoid.Health > 0
			or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then return false end
		local token = generation
		local startedAt = os.clock()
		local originalFrame = camera.CFrame
		local look = originalFrame.LookVector
		local horizontal = Vector3.new(look.X, 0, look.Z)
		if horizontal.Magnitude < 0.001 then horizontal = Vector3.new(0, 0, -1) end
		local offset = -horizontal.Unit * Config.DeathViewDistance + Vector3.new(0, Config.DeathViewHeight, 0)
		local focusOffset = Vector3.new(0, Config.DeathViewFocusHeight, 0)
		local originalTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
			or character:FindFirstChild("HumanoidRootPart")
		local anchor = originalTorso
		local corpseModel, rayParams, filteredCorpse
		local ignore = { character, camera }
		local function updateFilter()
			if not rayParams or filteredCorpse == corpseModel then return end
			filteredCorpse = corpseModel
			if corpseModel then table.insert(ignore, corpseModel) end
			-- A late exact reference can also be the first replicated corpse.
			local folder = RagdollQuery.GetFolder()
			if folder and not table.find(ignore, folder) then table.insert(ignore, folder) end
			rayParams.ExcludeInstances = ignore
		end
		local function selectAnchor()
			local reference = character:FindFirstChild("DeathRagdollReference")
			local corpse = reference and reference:IsA("ObjectValue") and reference.Value
			if corpse and corpse.Parent then
				local torso = corpse:FindFirstChild("UpperTorso") or corpse:FindFirstChild("Torso")
					or corpse:FindFirstChild("HumanoidRootPart")
				if torso and torso:IsA("BasePart") then anchor, corpseModel = torso, corpse end
				updateFilter()
			end
		end
		local function unobstructedFrame(frame, focus)
			local direction = frame.Position - focus
			local distance = direction.Magnitude
			if distance < 0.0001 then return frame end
			-- Probe the interpolated camera position too, so its path cannot cross
			-- a wall even when the desired final position is on the focus side.
			local result = workspace:Raycast(focus, direction, rayParams)
			if not result then return frame end
			local hitDistance = math.clamp(result.Distance, 0, distance)
			local safeDistance = math.max(0, hitDistance - Config.DeathViewCollisionPadding)
			if hitDistance > Config.DeathViewMinimumDistance then
				safeDistance = math.max(Config.DeathViewMinimumDistance, safeDistance)
			end
			local point = focus + direction.Unit * safeDistance
			return frame + (point - frame.Position)
		end
		local function startDeathView()
			selectAnchor()
			if Config.DeathViewEnabled and not VRService.VREnabled and anchor and anchor:IsA("BasePart") then
				rayParams = RaycastParams.new()
				rayParams.IgnoreWater, rayParams.RespectCanCollide = true, true
				-- Allocate/query the filter once, then only update it if the exact
				-- corpse arrives late. Native weapon/viewmodel parts are excluded too.
				for _, other in ipairs(Players:GetPlayers()) do
					if other ~= player and other.Character then table.insert(ignore, other.Character) end
				end
				RagdollQuery.Exclude(ignore)
				if corpseModel then table.insert(ignore, corpseModel) end
				filteredCorpse = corpseModel
				rayParams.ExcludeInstances = ignore
				-- Claim a distinct initial pose immediately so a posture/sway system
				-- cannot undo a saved offset from the last native-camera frame.
				local initialFocus = anchor.Position + focusOffset
				local initialFrame = unobstructedFrame(originalFrame:Lerp(CFrame.lookAt(anchor.Position + offset, initialFocus), 0.01), initialFocus)
				ownedCamera, ownedSubject = camera, humanoid
				camera.CameraType = Enum.CameraType.Scriptable
				writePose(camera, initialFrame, CFrame.new(initialFocus))
				local function update()
					if token ~= generation then return end
					if player.Character ~= character or humanoid.Health > 0 or not ownsCamera() then controller.Cancel(); return end
					-- The server's reference can arrive after the death remote. Resolve it
					-- during this one-second window, never scan the world for a namesake.
					selectAnchor()
					if not anchor or not anchor.Parent then return end
					local focus = anchor.Position + focusOffset
					local target = CFrame.lookAt(anchor.Position + offset, focus)
					local blend = math.clamp((os.clock() - startedAt) / Config.DeathViewPullbackSeconds, 0.01, 1)
					blend = blend * blend * (3 - 2 * blend)
					writePose(camera, unobstructedFrame(originalFrame:Lerp(target, blend), focus), CFrame.new(focus))
				end
				renderConnection = RunService.RenderStepped:Connect(function()
					local ok, err = pcall(update)
					if not ok then
						-- Keep the delayed native-camera handoff, but stop the failed effect.
						releaseCamera()
						warn("Death camera released after an error: " .. tostring(err))
					end
				end)
			end
		end
		local ok, err = pcall(startDeathView)
		if not ok then
			releaseCamera()
			warn("Death camera skipped after an error: " .. tostring(err))
		end
		pendingThread = task.delay(Config.DeathViewSeconds, function()
			if token ~= generation then return end
			pendingThread = nil -- never cancel the currently executing delayed task
			local valid = player.Character == character and humanoid.Health <= 0
				and workspace.CurrentCamera == camera
				and (ownedCamera and ownsCamera() or not ownedCamera
					and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid)
			releaseCamera()
			if valid then onReady() end
		end)
		return true
	end

	return controller
end

return Transition
