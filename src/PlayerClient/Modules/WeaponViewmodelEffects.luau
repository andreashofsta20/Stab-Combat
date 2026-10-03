-- Masks only this client's real weapon effects while its first-person copy is visible.
-- The camera models contain geometry only; no second VFX simulation is created.
local Effects = {}

function Effects.New(entries)
	local active = false
	local records, connections = {}, {}
	local manager = {}
	for _, entry in ipairs(entries) do
		local source = entry.source
		local record = {source = source, masks = {}, previous = {}, writing = false}
		if source:IsA("Light") then record.masks.Brightness = 0
		else
			local hasModifier = pcall(function() return source.LocalTransparencyModifier end)
			if hasModifier then record.masks.LocalTransparencyModifier = 1
			elseif source:IsA("Smoke") then record.masks.Opacity = 0
			else record.masks.Enabled = false end
		end
		if source:IsA("ParticleEmitter") then record.masks.Rate = 0 end
		function record.suppress()
			if not source.Parent then return end
			record.writing = true
			for property, masked in pairs(record.masks) do
				if source[property] ~= masked then
					record.previous[property] = source[property]
					source[property] = masked
				end
			end
			record.writing = false
		end
		table.insert(connections, source.Changed:Connect(function(property)
			if active and not record.writing and record.masks[property] ~= nil
				and source.Parent and source[property] ~= record.masks[property] then record.suppress() end
		end))
		table.insert(records, record)
	end

	function manager.SetActive(enabled)
		if active == enabled then return end
		active = enabled
		for _, record in ipairs(records) do
			local source = record.source
			if source.Parent then
				if enabled then
					for property in pairs(record.masks) do record.previous[property] = source[property] end
					if source:IsA("ParticleEmitter") or source:IsA("Trail") then source:Clear() end
					record.suppress()
				else
					record.writing = true
					for property, masked in pairs(record.masks) do
						if source[property] == masked then source[property] = record.previous[property] end
					end
					record.writing = false
				end
			end
		end
	end

	function manager.Guard()
		if active then for _, record in ipairs(records) do record.suppress() end end
	end

	function manager.Destroy()
		manager.SetActive(false)
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end
	return manager
end

return Effects
