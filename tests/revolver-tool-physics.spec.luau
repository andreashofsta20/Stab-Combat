-- Executes the real server module against signals that model Roblox lifecycle.
-- Collision flags are checked here; contact forces need the Studio probe.
return function(load)
	local Physics, catalog = load("Physics"), load("Catalog")
	local passed = 0
	local function test(name, callback)
		local ok, failure = pcall(callback)
		assert(ok, name .. ": " .. tostring(failure))
		passed += 1; print("PASS " .. name)
	end
	local function signal()
		local listeners = {}
		local event = {}
		function event:Connect(callback)
			local connection = {Connected = true, callback = callback}
			function connection:Disconnect() self.Connected = false end
			table.insert(listeners, connection)
			return connection
		end
		function event:Fire(...)
			for _, connection in ipairs(table.clone(listeners)) do
				if connection.Connected then connection.callback(...) end
			end
		end
		function event:Count()
			local count = 0
			for _, connection in ipairs(listeners) do if connection.Connected then count += 1 end end
			return count
		end
		return event
	end
	local methods = {}
	local function nodes(root)
		local result = {root}
		for _, child in ipairs(root.children) do
			for _, item in ipairs(nodes(child)) do table.insert(result, item) end
		end
		return result
	end
	local mt = {}
	mt.__index = function(item, key) return methods[key] or item.properties[key] end
	mt.__newindex = function(item, key, value)
		local previous = item.properties[key]
		if previous == value then return end
		if key == "Parent" then
			if previous then
				local ancestor = previous
				while ancestor do
					for _, descendant in ipairs(nodes(item)) do ancestor.DescendantRemoving:Fire(descendant) end
					ancestor = ancestor.Parent
				end
				local index = table.find(previous.children, item)
				if index then table.remove(previous.children, index) end
				item.properties.Parent = nil
				previous.ChildRemoved:Fire(item)
			end
			item.properties.Parent = value
			if value then
				table.insert(value.children, item)
				value.ChildAdded:Fire(item)
				local ancestor = value
				while ancestor do
					for _, descendant in ipairs(nodes(item)) do ancestor.DescendantAdded:Fire(descendant) end
					ancestor = ancestor.Parent
				end
			end
		else item.properties[key] = value end
		local event = item.properties.events[key]
		if event then event:Fire() end
	end
	local function object(class, name)
		return setmetatable({children = {}, properties = {ClassName = class, Name = name or class, events = {},
			ChildAdded = signal(), ChildRemoved = signal(), DescendantAdded = signal(), DescendantRemoving = signal(),
			CharacterAdded = signal(), CharacterRemoving = signal(), CanCollide = true, CanTouch = true,
			Massless = false, Anchored = false, CanQuery = true, CFrame = "unchanged", AssemblyLinearVelocity = "unchanged"}}, mt)
	end
	function methods:IsA(class)
		return self.ClassName == class or class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart")
	end
	function methods:GetChildren() return table.clone(self.children) end
	function methods:GetDescendants()
		self.properties.scans = (self.properties.scans or 0) + 1
		local result = nodes(self); table.remove(result, 1); return result
	end
	function methods:GetPropertyChangedSignal(property)
		local events = self.properties.events
		if not events[property] then events[property] = signal() end
		return events[property]
	end
	local name = next(catalog)
	local function scene()
		local player, character = object("Player"), object("Model", "Character")
		player.Character = character
		local tool, handle = object("Tool", name), object("Part", "Handle")
		handle.Parent, tool.Parent = tool, character
		return {player = player, character = character, tool = tool, handle = handle, physics = Physics.New(catalog)}
	end
	local function decorative(part) assert(not part.CanCollide and not part.CanTouch and part.Massless) end
	local function partConnections(part)
		local total = 0
		for _, event in pairs(part.properties.events) do total += event:Count() end
		return total
	end
	test("current equipped revolver is safe before any game/session state", function()
		local f = scene(); f.physics.BindPlayer(f.player); decorative(f.handle)
		assert(f.handle.Anchored == false and f.handle.CanQuery == true)
		assert(f.handle.CFrame == "unchanged" and f.handle.AssemblyLinearVelocity == "unchanged")
		assert(partConnections(f.handle) == 3)
	end)
	test("every catalog skin is covered", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		local count = 0
		for skin in pairs(catalog) do
			local tool, part = object("Tool", skin), object("MeshPart", "Skin")
			part.Parent, tool.Parent = tool, f.character; decorative(part); count += 1
		end
		assert(count > 40)
	end)
	test("non-revolver tools and character limbs are untouched", function()
		local f = scene()
		local knife, limb = object("Tool", "Some Knife"), object("Part", "Right Arm")
		local blade = object("MeshPart", "Blade"); blade.Parent, knife.Parent, limb.Parent = knife, f.character, f.character
		f.physics.BindPlayer(f.player)
		assert(blade.CanCollide and blade.CanTouch and not blade.Massless and partConnections(blade) == 0)
		assert(limb.CanCollide and limb.CanTouch and not limb.Massless and partConnections(limb) == 0)
	end)
	test("nested and late weapon skin parts become decorative", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		local folder, part = object("Folder", "Skin"), object("MeshPart", "Barrel")
		part.Parent, folder.Parent = folder, f.tool; decorative(part)
		local late = object("Part", "Muzzle"); late.Parent = folder; decorative(late)
		assert(partConnections(part) == 3 and partConnections(late) == 3)
	end)
	test("skin script property resets cannot restore collisions or mass", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		for _ = 1, 20 do
			f.handle.CanCollide = true; decorative(f.handle)
			f.handle.CanTouch = true; decorative(f.handle)
			f.handle.Massless = false; decorative(f.handle)
		end
		assert(f.tool.properties.scans == 1, "property changes must not rescan weapon")
	end)
	test("anchoring and query state are preserved even when unusual", function()
		local f = scene(); f.handle.Anchored, f.handle.CanQuery = true, false
		f.physics.BindPlayer(f.player); decorative(f.handle)
		assert(f.handle.Anchored and f.handle.CanQuery == false)
		f.handle.Anchored, f.handle.CanQuery = false, true
		assert(not f.handle.Anchored and f.handle.CanQuery)
	end)
	test("removed nested parts release listeners and are rebound on return", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		local folder, part = object("Folder"), object("Part")
		part.Parent, folder.Parent = folder, f.tool
		folder.Parent = nil; assert(partConnections(part) == 0)
		part.CanCollide, part.CanTouch, part.Massless = true, true, false
		assert(part.CanCollide and part.CanTouch and not part.Massless)
		folder.Parent = f.tool; decorative(part); assert(partConnections(part) == 3)
	end)
	test("unequip releases tool and part listeners", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		f.tool.Parent = object("Backpack")
		assert(partConnections(f.handle) == 0 and f.tool.DescendantAdded:Count() == 0 and f.tool.DescendantRemoving:Count() == 0)
		f.handle.CanCollide = true; assert(f.handle.CanCollide)
		f.tool.Parent = f.character; decorative(f.handle)
		assert(partConnections(f.handle) == 3 and f.tool.DescendantAdded:Count() == 1)
	end)
	test("respawn clears old rig and binds the new equipped weapon", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		local old = f.character
		f.player.CharacterRemoving:Fire(old)
		assert(partConnections(f.handle) == 0 and old.ChildAdded:Count() == 0 and old.ChildRemoved:Count() == 0)
		local character, tool, part = object("Model"), object("Tool", name), object("Part")
		part.Parent, tool.Parent = tool, character
		f.player.Character = character; f.player.CharacterAdded:Fire(character); decorative(part)
		f.player.CharacterRemoving:Fire(old); assert(partConnections(part) == 3)
	end)
	test("character replacement also cleans up without a removing event", function()
		local f = scene(); f.physics.BindPlayer(f.player)
		local character = object("Model")
		f.player.Character = character; f.player.CharacterAdded:Fire(character)
		assert(partConnections(f.handle) == 0 and f.character.ChildAdded:Count() == 0)
	end)
	test("players joining before a character are supported", function()
		local player, physics = object("Player"), Physics.New(catalog)
		physics.BindPlayer(player)
		local character, tool, part = object("Model"), object("Tool", name), object("Part")
		player.Character = character; player.CharacterAdded:Fire(character)
		part.Parent, tool.Parent = tool, character; decorative(part)
	end)
	test("duplicate player and character binds do not duplicate connections", function()
		local f = scene(); f.physics.BindPlayer(f.player); f.physics.BindPlayer(f.player)
		f.player.CharacterAdded:Fire(f.character)
		assert(partConnections(f.handle) == 3 and f.player.CharacterAdded:Count() == 1)
		assert(f.tool.properties.scans == 1 and f.character.ChildAdded:Count() == 1)
	end)
	test("player removal disconnects every lifecycle and property listener", function()
		local f = scene(); f.physics.BindPlayer(f.player); f.physics.RemovePlayer(f.player); f.physics.RemovePlayer(f.player)
		assert(partConnections(f.handle) == 0 and f.character.ChildAdded:Count() == 0 and f.character.ChildRemoved:Count() == 0)
		assert(f.player.CharacterAdded:Count() == 0 and f.player.CharacterRemoving:Count() == 0)
		assert(f.tool.DescendantAdded:Count() == 0 and f.tool.DescendantRemoving:Count() == 0)
		f.handle.CanCollide = true; assert(f.handle.CanCollide)
	end)
	test("separate players retain independent enforcement", function()
		local a, b = scene(), scene(); local physics = Physics.New(catalog)
		physics.BindPlayer(a.player); physics.BindPlayer(b.player)
		physics.RemovePlayer(a.player)
		b.handle.CanCollide = true; decorative(b.handle)
		assert(partConnections(a.handle) == 0 and partConnections(b.handle) == 3)
	end)
	print("Revolver Tool physics: " .. passed .. " tests passed")
end
