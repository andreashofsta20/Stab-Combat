-- Decals and textures have their own visibility; hiding the parent part is insufficient.
-- Keep authored appearance separate from local masks, including older-engine fallback.
local Visibility = {}

function Visibility.New(faces)
	local records, bySource, connections = {}, {}, {}
	local active = false
	local manager = {}
	for _, source in ipairs(faces) do
		local supported, previous = pcall(function()
			local value = source.LocalTransparencyModifier
			source.LocalTransparencyModifier = value -- test write access once, outside rendering
			return value
		end)
		local property = supported and "LocalTransparencyModifier" or "Transparency"
		local record = {source = source, property = property, previous = supported and previous or source.Transparency, writing = false}
		bySource[source] = record
		function record.hide()
			if source.Parent and source[property] ~= 1 then
				record.previous = source[property]
				record.writing = true; source[property] = 1; record.writing = false
			end
		end
		table.insert(connections, source.Changed:Connect(function(changed)
			if active and not record.writing and changed == property and source.Parent and source[property] ~= 1 then record.hide() end
		end))
		table.insert(records, record)
	end

	function manager.GetTransparency(source)
		local record = bySource[source]
		return active and record and record.property == "Transparency" and record.previous or source.Transparency
	end

	function manager.SetActive(enabled)
		if active == enabled then return end
		active = enabled
		for _, record in ipairs(records) do
			local source, property = record.source, record.property
			if source.Parent then
				if enabled then record.previous = source[property]; record.hide()
				elseif source[property] == 1 then
					record.writing = true; source[property] = record.previous; record.writing = false
				end
			end
		end
	end

	function manager.Guard()
		if active then for _, record in ipairs(records) do record.hide() end end
	end

	function manager.Destroy()
		manager.SetActive(false)
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
	end
	return manager
end

return Visibility
