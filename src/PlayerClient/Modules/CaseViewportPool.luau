local RunService = game:GetService("RunService")
local Pool = {}
Pool.CardBatchSize = 10
Pool.MaxPreviews = 10
Pool.MaxLoadsPerFrame = 2

-- Exclude the entire preview world while making lightweight GUI cards. Clone is
-- synchronous; restore the template flag before any caller is allowed to yield.
function Pool.CloneCard(template)
	local viewport = template:FindFirstChild("EmoteViewport")
	local world = viewport and viewport:FindFirstChild("World")
	local archivable = world and world.Archivable
	if world then world.Archivable = false end
	local ok, copy = pcall(function() return template:Clone() end)
	if world then world.Archivable = archivable end
	if not ok then error(copy, 2) end
	return copy, world
end

local function cloneWorld(source)
	local archivable = source.Archivable
	source.Archivable = true
	local ok, world = pcall(function() return source:Clone() end)
	source.Archivable = archivable
	if ok then return world end
	return nil
end

local function stop(entry)
	if entry.track then entry.track:Stop(0) end
	if entry.slot then
		if entry.camera and entry.slot.viewport.CurrentCamera == entry.camera then entry.slot.viewport.CurrentCamera = nil end
		entry.slot.entry = nil
		entry.slot = nil
	end
	entry.world.Parent = nil
end

local function destroyAnimation(entry)
	if entry.track then entry.track:Stop(0); entry.track:Destroy(); entry.track = nil end
	if entry.animation then entry.animation:Destroy(); entry.animation = nil end
	entry.animationId = nil
end

function Pool.New(sourceWorld, clip, isVisible)
	local self = {slots = {}, entries = {}, candidates = {}, wanted = {}, destroyed = false, generation = 0, elapsed = 0}
	function self:Add(card, animationId)
		local viewport = card:FindFirstChild("EmoteViewport")
		if self.destroyed or not viewport or not sourceWorld or type(animationId) ~= "string" or animationId == "" then return end
		table.insert(self.slots, {card = card, viewport = viewport, animationId = animationId})
	end
	function self:Update()
		if self.destroyed then return end
		if not isVisible() or not clip.Parent then
			for _, entry in ipairs(self.entries) do if entry.slot then stop(entry) end end
			return
		end
		local position, size = clip.AbsolutePosition, clip.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		local left, right = position.X - size.X * 0.2, position.X + size.X * 1.2
		local top, bottom = position.Y, position.Y + size.Y
		local center = position.X + size.X / 2
		local candidates = self.candidates
		table.clear(candidates)
		for _, slot in ipairs(self.slots) do
			local card = slot.card
			if card.Parent and card.Visible then
				local p, s = card.AbsolutePosition, card.AbsoluteSize
				if s.X > 0 and s.Y > 0 and p.X < right and p.X + s.X > left and p.Y < bottom and p.Y + s.Y > top then
					slot.distance = math.abs(p.X + s.X / 2 - center)
					table.insert(candidates, slot)
				end
			end
		end
		table.sort(candidates, function(a, b) return a.distance < b.distance end)
		local wanted = self.wanted
		table.clear(wanted)
		for index = 1, math.min(Pool.MaxPreviews, #candidates) do wanted[candidates[index]] = true end
		for _, entry in ipairs(self.entries) do if entry.slot and not wanted[entry.slot] then stop(entry) end end
		local creates, loads = 0, 0
		for index = 1, math.min(Pool.MaxPreviews, #candidates) do
			local slot = candidates[index]
			local entry = slot.entry
			if not entry then
				-- Favor a spare already holding this animation before changing a track.
				for _, available in ipairs(self.entries) do
					if not available.slot and (not entry or available.animationId == slot.animationId) then entry = available end
					if entry and entry.animationId == slot.animationId then break end
				end
				if not entry and #self.entries < Pool.MaxPreviews and creates < Pool.MaxLoadsPerFrame then
					creates += 1
					local world = cloneWorld(sourceWorld)
					if world then
						entry = {world = world}
						table.insert(self.entries, entry)
					end
				end
				if entry then
					entry.slot, slot.entry = slot, entry
					entry.world.Parent = slot.viewport
					entry.camera = entry.camera or entry.world:FindFirstChildWhichIsA("Camera", true)
					if entry.camera then slot.viewport.CurrentCamera = entry.camera end
				end
			end
			if entry then
				if entry.animationId == slot.animationId and entry.track then
					if not entry.track.IsPlaying then entry.track:Play(0) end
				elseif loads < Pool.MaxLoadsPerFrame and not entry.loading and slot.failedId ~= slot.animationId then
					loads += 1
					destroyAnimation(entry)
					local rig = entry.world:FindFirstChild("Rig")
					local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
					if humanoid then
						local animator = humanoid:FindFirstChildOfClass("Animator")
						if not animator then animator = Instance.new("Animator"); animator.Parent = humanoid end
						local animation = Instance.new("Animation")
						animation.AnimationId = slot.animationId
						local generation = self.generation
						entry.loading = true
						local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
						entry.loading = false
						-- Protect teardown even if asset loading yields in a future engine version.
						if self.destroyed or self.generation ~= generation or entry.slot ~= slot then
							if ok and track then track:Stop(0); track:Destroy() end
							animation:Destroy(); return
						end
						if ok and track then
							entry.track, entry.animation, entry.animationId = track, animation, slot.animationId
							track.Looped = true; track:Play(0)
						else animation:Destroy(); slot.failedId = slot.animationId end
					end
				end
			end
		end
	end
	function self:Destroy()
		if self.destroyed then return end
		self.destroyed = true; self.generation += 1
		if self.connection then self.connection:Disconnect(); self.connection = nil end
		for _, entry in ipairs(self.entries) do stop(entry); destroyAnimation(entry); entry.world:Destroy() end
		table.clear(self.entries); table.clear(self.slots); table.clear(self.candidates); table.clear(self.wanted)
	end
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self.elapsed += dt
		if self.elapsed >= 1 / 30 then self.elapsed = 0; self:Update() end
	end)
	return self
end

return Pool
