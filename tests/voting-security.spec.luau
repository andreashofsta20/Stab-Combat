return function(load)
	local passed = 0
	local function test(name, callback)
		local ok, problem = pcall(callback)
		if not ok then error(name .. ': ' .. tostring(problem), 0) end
		passed += 1
	end
	local function equal(actual, expected)
		assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
	end
	local function signal()
		local listeners = {}
		return {
			Connect = function(_, callback)
				table.insert(listeners, callback)
				return {Disconnect = function() end}
			end,
			Fire = function(_, ...)
				for _, callback in ipairs(listeners) do callback(...) end
			end,
		}
	end
	local function object(className, name)
		local item = {ClassName = className, Name = name, children = {}}
		function item:IsA(class) return self.ClassName == class end
		function item:FindFirstChild(childName) return self.children[childName] end
		function item:WaitForChild(childName)
			assert(self.children[childName], 'Unexpected yield for ' .. childName)
			return self.children[childName]
		end
		return item
	end
	local function child(parent, className, name)
		local item = object(className, name); item.Parent = parent; parent.children[name] = item; parent[name] = item
		return item
	end
	local function fixture()
		local f = {time = 10, tasks = 0, notifications = {}, warnings = {}, broadcasts = {}, vips = {}, vipChecks = 0}
		f.Players = object('Players', 'Players'); f.Players.PlayerRemoving = signal()
		f.RS = object('ReplicatedStorage', 'ReplicatedStorage')
		local votingRemotes = child(f.RS, 'Folder', 'VotingRemotes')
		child(votingRemotes, 'RemoteEvent', 'StartVoting')
		child(votingRemotes, 'RemoteEvent', 'ClearUIVotes').FireAllClients = function() end
		f.ReceiveVote = child(votingRemotes, 'RemoteEvent', 'RecieveVote'); f.ReceiveVote.OnServerEvent = signal()
		child(votingRemotes, 'RemoteEvent', 'VoteUpdate').FireAllClients = function(_, counts)
			table.insert(f.broadcasts, counts)
		end
		local remotes = child(f.RS, 'Folder', 'Remotes')
		local notificationRemote = child(child(child(remotes, 'Folder', 'Client'), 'Folder', 'NotificationClientRemotes'), 'RemoteEvent', 'RecieveNotification')
		function notificationRemote:FireClient() error('Disabled notification sent') end
		function notificationRemote:FireAllClients() error('Disabled server notification sent') end
		f.server = object('ServerScriptService', 'ServerScriptService')
		f.gameFolder = child(f.server, 'Folder', 'Game')
		local roundMarker = child(f.gameFolder, 'ModuleScript', 'RoundHandler')
		local notifyMarker = child(f.gameFolder, 'ModuleScript', 'SendNotification')
		local vipMarker = child(child(f.server, 'Folder', 'ServicesHandler'), 'ModuleScript', 'VIPService')
		f.round = {TimeToVote = true, VoteOptions = {{Id = 'Map:FFA'}, {Id = 'Map:BattleRoyale'}}, MapsAbleToVoteOn = {'Map:FFA', 'Map:BattleRoyale'}}
		f.round.ChangeStatus = function() end
		f.round.GetRandomMapFromVoting = function() return 'Map:FFA' end
		local modules = {
			[roundMarker] = f.round,
			[notifyMarker] = {SendNotification = function(_, message) table.insert(f.notifications, message) end},
			[vipMarker] = {HasVIPByUserId = function(id) f.vipChecks += 1; return f.vips[id] == true end},
		}
		f.env = {
			game = {GetService = function(_, service) return ({Players = f.Players, ReplicatedStorage = f.RS, ServerScriptService = f.server})[service] end},
			script = {Parent = f.gameFolder}, require = function(marker) assert(modules[marker]); return modules[marker] end,
			os = {clock = function() return f.time end},
			task = {delay = function() f.tasks += 1 end, wait = function() f.tasks += 1 end},
			warn = function(message) table.insert(f.warnings, message) end,
		}
		f.voting = load('Voting', f.env)
		function f:player(id)
			local player = object('Player', tostring(id)); player.UserId, player.Parent = id, self.Players
			player.attributes = {DataReady = true}
			function player:GetAttribute(name) return self.attributes[name] end
			local settings = child(child(player, 'Folder', 'leaderstats'), 'Folder', 'Settings')
			player.lobby = child(settings, 'BoolValue', 'LobbyMode'); player.lobby.Value = false
			return player
		end
		function f:vote(player, option) self.ReceiveVote.OnServerEvent:Fire(player, option) end
		return f
	end

	test('server recognizes a selected option and broadcasts one accepted vote', function()
		local f = fixture(); local player = f:player(1); f:vote(player, 'Map:FFA')
		equal(f.voting.Options['Map:FFA'].Votecount, 1); equal(f.broadcasts[1]['Map:FFA'], 1)
	end)
	test('VIP votes retain two votes', function()
		local f = fixture(); local player = f:player(1); f.vips[1] = true; f:vote(player, 'Map:FFA')
		equal(f.voting.Options['Map:FFA'].Votecount, 2)
	end)
	test('malformed and oversized remote options are rejected without reply or scheduling', function()
		local f = fixture(); local player = f:player(1)
		for _, option in ipairs({false, 10, {}, '', string.rep('a', 129)}) do f:vote(player, option) end
		equal(#f.notifications, 0); equal(#f.broadcasts, 0); equal(f.tasks, 0); equal(f.vipChecks, 0)
	end)
	test('unknown option is never reflected into notification or log', function()
		local f = fixture(); local player = f:player(1); f:vote(player, 'Unexpected Client Text')
		equal(f.notifications[1], 'Invalid voting option'); equal(#f.warnings, 0); equal(f.vipChecks, 0)
	end)
	test('direct calls have the same bounded validation', function()
		local f = fixture(); f.voting.SubmitVote(f:player(1), string.rep('a', 10000))
		equal(#f.notifications, 0); equal(f.vipChecks, 0)
	end)
	test('requests are throttled without allocating delayed tasks', function()
		local f = fixture(); local player = f:player(1)
		for _ = 1, 1000 do f:vote(player, 'Map:FFA') end
		equal(#f.broadcasts, 1); equal(f.vipChecks, 1); equal(f.tasks, 0)
	end)
	test('new players cannot vote before their data loads', function()
		local f = fixture(); local player = f:player(1); player.attributes.DataReady = false; f:vote(player, 'Map:FFA')
		equal(#f.notifications, 0); equal(f.vipChecks, 0); equal(next(f.voting.Votes), nil)
	end)
	test('missing settings cannot authorize a vote', function()
		local f = fixture(); local player = f:player(1); player.children.leaderstats = nil; f:vote(player, 'Map:FFA')
		equal(f.vipChecks, 0); equal(next(f.voting.Votes), nil)
	end)
	test('malformed lobby value and lobby mode both reject', function()
		for _, value in ipairs({true, 'false'}) do
			local f = fixture(); local player = f:player(1); player.lobby.Value = value; f:vote(player, 'Map:FFA')
			equal(f.vipChecks, 0); equal(next(f.voting.Votes), nil)
		end
	end)
	test('departed player cannot submit an option', function()
		local f = fixture(); local player = f:player(1); player.Parent = nil; f.voting.SubmitVote(player, 'Map:FFA')
		equal(f.vipChecks, 0); equal(next(f.voting.Votes), nil)
	end)
	test('voting after the server closes the window cannot change state', function()
		local f = fixture(); local player = f:player(1); f.round.TimeToVote = false; f:vote(player, 'Map:FFA')
		equal(f.vipChecks, 0); equal(next(f.voting.Votes), nil)
	end)
	test('switching removes the recorded weight after a VIP purchase', function()
		local f = fixture(); local first, second = f:player(1), f:player(2)
		f:vote(first, 'Map:FFA'); f:vote(second, 'Map:FFA'); f.vips[1] = true; f.time += 0.31
		f:vote(first, 'Map:BattleRoyale')
		equal(f.voting.Options['Map:FFA'].Votecount, 1); equal(f.voting.Options['Map:BattleRoyale'].Votecount, 2)
	end)
	test('switching removes the full prior VIP vote if ownership cache changes', function()
		local f = fixture(); local player = f:player(1); f.vips[1] = true; f:vote(player, 'Map:FFA')
		f.vips[1] = false; f.time += 0.31; f:vote(player, 'Map:BattleRoyale')
		equal(f.voting.Options['Map:FFA'].Votecount, 0); equal(f.voting.Options['Map:BattleRoyale'].Votecount, 1)
	end)
	test('same option cannot increment counts or broadcast twice', function()
		local f = fixture(); local player = f:player(1); f:vote(player, 'Map:FFA'); f.time += 0.31; f:vote(player, 'Map:FFA')
		equal(f.voting.Options['Map:FFA'].Votecount, 1); equal(#f.broadcasts, 1); equal(f.vipChecks, 1)
	end)
	test('leaving during voting removes the recorded vote and broadcasts once', function()
		local f = fixture(); local player = f:player(1); f.vips[1] = true; f:vote(player, 'Map:FFA')
		f.Players.PlayerRemoving:Fire(player)
		equal(f.voting.Options['Map:FFA'].Votecount, 0); equal(#f.broadcasts, 2)
		equal(f.voting.Votes[1], nil); equal(f.voting.VoteWeights[1], nil); equal(f.voting.Debounce[1], nil)
		f.Players.PlayerRemoving:Fire(player); equal(#f.broadcasts, 2)
	end)
	test('leaving after the window closes does not spam results or observers', function()
		local f = fixture(); local player = f:player(1); f:vote(player, 'Map:FFA'); f.round.TimeToVote = false
		f.Players.PlayerRemoving:Fire(player); equal(#f.broadcasts, 1)
	end)
	test('new voting sessions cannot inherit old votes, VIP weights or cooldowns', function()
		local f = fixture(); local player = f:player(1); f:vote(player, 'Map:FFA'); f.voting.Begin(f.round.VoteOptions)
		equal(next(f.voting.Votes), nil); equal(next(f.voting.VoteWeights), nil); equal(next(f.voting.Debounce), nil)
		f:vote(player, 'Map:FFA'); equal(f.voting.Options['Map:FFA'].Votecount, 1)
	end)
	test('wipe also clears recorded weights', function()
		local f = fixture(); f:vote(f:player(1), 'Map:FFA'); f.voting.WipeAll()
		equal(next(f.voting.Votes), nil); equal(next(f.voting.VoteWeights), nil); equal(next(f.voting.Options), nil)
	end)
	test('disabled notifications never wait for an unloaded player profile', function()
		local f = fixture(); local notifications = load('Notifications', f.env)
		local player = {WaitForChild = function() error('Profile wait must not happen') end}
		notifications.SendNotification(player, 'Example', 3, 'Error')
		notifications.SendNotificationServer('Example', 3, 'Error')
	end)

	print(tostring(passed) .. ' voting security checks passed')
end
