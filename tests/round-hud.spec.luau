-- Production HUD lifecycle and allocation checks with Roblox UI stand-ins.
local function signal()
	local entries, event = {}, {}
	function event:Connect(fn)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false end
		table.insert(entries, {fn = fn, connection = connection}); return connection
	end
	function event:Fire(...)
		for _, entry in ipairs(table.clone(entries)) do if entry.connection.Connected then entry.fn(...) end end
	end
	function event:Count()
		local count = 0; for _, entry in ipairs(entries) do if entry.connection.Connected then count += 1 end end; return count
	end
	return event
end
return function(load)
	local passed = 0
	local function test(name, fn)
		local ok, failure = pcall(fn); assert(ok, name .. ': ' .. tostring(failure)); passed += 1; print('PASS ' .. name)
	end
	local function fixture()
		local f = {clones = 0}
		local methods, meta = {}, {}
		function meta.__index(self, name)
			if methods[name] then return methods[name] end
			if self.props[name] ~= nil then return self.props[name] end
			if self.signals[name] then return self.signals[name] end
			for _, child in ipairs(self.children) do if child.Name == name then return child end end
		end
		function meta.__newindex(self, key, value)
			local old = self.props[key]; if old == value then return end
			if key == 'Parent' then
				if old then local index = table.find(old.children, self); if index then table.remove(old.children, index) end end
				self.props.Parent = value; if value then table.insert(value.children, self) end
			else self.props[key] = value end
			if self.signals['Property_' .. key] then self.signals['Property_' .. key]:Fire() end
		end
		local function object(class, name, parent)
			local node = setmetatable({props = {ClassName = class, Name = name, Visible = false}, children = {}, signals = {Destroying = signal(), Changed = signal()}, attributes = {}}, meta)
			node.Parent = parent; return node
		end
		function methods:IsA(class) return self.ClassName == class or class == 'GuiObject' and (self.ClassName == 'Frame' or self.ClassName == 'TextLabel' or self.ClassName == 'ImageLabel') end
		function methods:GetChildren() return table.clone(self.children) end
		function methods:FindFirstChild(name, recursive)
			for _, child in ipairs(self.children) do if child.Name == name then return child end end
			if recursive then for _, child in ipairs(self.children) do local found = child:FindFirstChild(name, true); if found then return found end end end
		end
		function methods:FindFirstChildWhichIsA(class, recursive)
			for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
			if recursive then for _, child in ipairs(self.children) do local found = child:FindFirstChildWhichIsA(class, true); if found then return found end end end
		end
		function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
		function methods:GetPropertyChangedSignal(name) self.signals['Property_' .. name] = self.signals['Property_' .. name] or signal(); return self.signals['Property_' .. name] end
		function methods:GetAttributeChangedSignal(name) self.signals['Attribute_' .. name] = self.signals['Attribute_' .. name] or signal(); return self.signals['Attribute_' .. name] end
		function methods:GetAttribute(name) return self.attributes[name] end
		function methods:SetAttribute(name, value)
			if self.attributes[name] == value then return end
			self.attributes[name] = value; if self.signals['Attribute_' .. name] then self.signals['Attribute_' .. name]:Fire() end
		end
		function methods:Destroy()
			if self.Destroyed then return end
			self.Destroyed = true; self.Destroying:Fire()
			for _, child in ipairs(self:GetChildren()) do child:Destroy() end
			self.Parent = nil
		end
		local function copy(source)
			local node = object(source.ClassName, source.Name)
			for key, value in pairs(source.props) do if key ~= 'Parent' then node.props[key] = value end end
			for _, child in ipairs(source.children) do copy(child).Parent = node end
			return node
		end
		function methods:Clone() f.clones += 1; return copy(self) end
		function f.newPlayer(id, name)
			local player = object('Player', name); player.UserId = id
			player:SetAttribute('CurrentRoundParticipant', true); player:SetAttribute('InRound', true); player:SetAttribute('CurrentRoundKills', 0)
			return player
		end
		f.player, f.other = f.newPlayer(1, 'Local'), f.newPlayer(2, 'Other')
		f.players = {LocalPlayer = f.player, PlayerAdded = signal(), PlayerRemoving = signal(), list = {f.player, f.other}}
		function f.players:GetPlayers() return table.clone(self.list) end
		f.player:SetAttribute('CurrentRoundMode', 'FFA')
		local gui = object('PlayerGui', 'PlayerGui', f.player); f.main = object('ScreenGui', 'Main', gui)
		f.ingame = object('Frame', 'Ingame', f.main)
		f.br = object('Frame', 'Top', object('Frame', 'BR', f.ingame)); f.ffa = object('Frame', 'Top', object('Frame', 'FFA', f.ingame))
		f.brList, f.ffaList = object('Frame', 'PlayerList', f.br), object('Frame', 'PlayerList', f.ffa)
		object('UIListLayout', 'Layout', f.brList); object('UIListLayout', 'Layout', f.ffaList)
		f.buttons = object('Frame', 'Buttons', object('Frame', 'Top', f.main)); f.spectate = object('Frame', 'SpectateFrame', f.main)
		local rs = object('Folder', 'ReplicatedStorage')
		f.active = object('BoolValue', 'GameActive', rs); f.active.Value = true
		f.countdown = object('RemoteEvent', 'RoundCountdown', object('Folder', 'Remotes', rs)); f.countdown.OnClientEvent = signal()
		local templates = object('Folder', 'InGameUITemplates', object('Folder', 'UITemplates', rs))
		for _, mode in ipairs({'FFA', 'BR'}) do
			local template = object('Frame', 'PlayerTemplate', object('Folder', mode, templates))
			object('TextLabel', 'PlayerName', template); object('TextLabel', 'PlayerKills', template)
			object('ImageLabel', 'ProfileImg', template); object('ImageLabel', 'DeadImg', template); object('UIStroke', 'Stroke', template)
		end
		f.module = load({game = {GetService = function(_, name) return name == 'Players' and f.players or rs end}, Color3 = {fromRGB = function(r, g, b) return tostring(r) .. ',' .. g .. ',' .. b end}})
		function f.row(player, mode) return (mode == 'BR' and f.brList or f.ffaList):FindFirstChild(player.Name) end
		return f
	end
	test('round rows reuse their instances through one hundred kill updates', function()
		local f = fixture(); local row, other, clones = f.row(f.player), f.row(f.other), f.clones
		for kills = 1, 100 do f.other:SetAttribute('CurrentRoundKills', kills) end
		assert(f.clones == clones and f.row(f.player) == row and f.row(f.other) == other)
		assert(other.PlayerKills.Text == '100' and other.LayoutOrder < row.LayoutOrder and not f.buttons.Visible)
	end)
	test('participants are added and removed individually without rebuilding peers', function()
		local f = fixture(); local row, clones = f.row(f.player), f.clones
		f.other:SetAttribute('CurrentRoundParticipant', false); assert(not f.row(f.other) and f.row(f.player) == row and f.clones == clones)
		f.other:SetAttribute('CurrentRoundParticipant', true); assert(f.row(f.other) and f.row(f.player) == row and f.clones == clones + 1)
	end)
	test('BR death updates only the row styling and preserves living rows', function()
		local f = fixture(); f.player:SetAttribute('CurrentRoundMode', 'BR')
		local row, clones = f.row(f.other, 'BR'), f.clones; f.other:SetAttribute('InRound', false)
		assert(f.row(f.other, 'BR') == row and f.clones == clones and row.DeadImg.Visible and row.LayoutOrder == 100000)
		assert(row.PlayerName.TextTransparency > 0 and not f.ffa.Visible and not f.row(f.player))
	end)
	test('departure disconnects callbacks and cannot recreate a row from GetPlayers during removal', function()
		local f = fixture(); local other = f.other
		f.players.PlayerRemoving:Fire(other); assert(not f.row(other))
		for _, name in ipairs({'CurrentRoundKills', 'CurrentRoundParticipant', 'InRound'}) do assert(other:GetAttributeChangedSignal(name):Count() == 0) end
		local clones = f.clones; other:SetAttribute('CurrentRoundKills', 999); assert(f.clones == clones and not f.row(other))
	end)
	test('new players have one owned observer and duplicate join delivery adds no callbacks', function()
		local f = fixture(); local player = f.newPlayer(3, 'New'); table.insert(f.players.list, player)
		f.players.PlayerAdded:Fire(player); f.players.PlayerAdded:Fire(player)
		assert(f.row(player) and player:GetAttributeChangedSignal('CurrentRoundKills'):Count() == 1)
	end)
	test('round end clears rows while preserving layout and reopening follows spectator visibility', function()
		local f = fixture(); f.active.Value = false; f.active.Changed:Fire(false)
		assert(not f.row(f.player) and not f.ffa.Visible and f.ffaList:FindFirstChild('Layout') and f.buttons.Visible)
		f.player:SetAttribute('InRound', false); f.active.Value = true; f.active.Changed:Fire(true); assert(not f.row(f.player))
		f.spectate.Visible = true; assert(f.row(f.player) and not f.buttons.Visible)
		f.countdown.OnClientEvent:Fire('roundover'); assert(not f.row(f.player) and f.buttons.Visible)
	end)
	test('UI destruction releases all owned signals and prevents further rebuilding', function()
		local f = fixture(); f.ingame:Destroy(); f.module.Destroy()
		assert(f.players.PlayerAdded:Count() == 0 and f.players.PlayerRemoving:Count() == 0 and f.active.Changed:Count() == 0)
		assert(f.countdown.OnClientEvent:Count() == 0 and f.other:GetAttributeChangedSignal('CurrentRoundKills'):Count() == 0)
		local clones = f.clones; f.other:SetAttribute('CurrentRoundKills', 100); f.active.Changed:Fire(true); assert(f.clones == clones)
	end)
	print(string.format('%d round HUD tests passed', passed))
end
