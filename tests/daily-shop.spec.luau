return function(load)
	local Mock, Config, Catalog = load("Mock"), load("Config"), load("Catalog")
	local Knives, Revolvers, Levels = load("Knives"), load("Revolvers"), load("Levels")
	local definitions = {Knife = Knives, Revolver = Revolvers}
	local function clone(t) local out = {}; for k,v in pairs(t) do out[k] = type(v) == "table" and clone(v) or v end; return out end
	local function eq(a,b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
	local passed = 0
	local function test(name, fn)
		local ok, err = pcall(fn); if not ok then error(name .. ": " .. tostring(err), 0) end
		passed += 1; print("PASS " .. name)
	end
	local function fixture()
		local f = Mock.fixture(load)
		f.config = clone(Config)
		f.register(f.modulesFolder,"UIAnimationConfig",load("AnimationConfig"))
		for key, value in pairs({DailyShopConfig = f.config, DailyShopCatalog = Catalog, KnivesInfo = Knives,
			RevolversInfo = Revolvers, CalculateLevel = Levels, Abbreviate = load("Abbreviate"), RarityColor = load("Rarity"), ProductIDS = load("Products")}) do f.register(f.modulesFolder, key, value) end
		for kind, items in pairs(f.config.Items) do
			for name in pairs(items) do Mock.object("Tool", name, f.SS[kind == "Knife" and "Knives" or "Revolvers"]) end
		end
		f.shop = f:load("Server", f.servicesFolder, "DailyShopHandler")
		function f:request() self.shop.HandleRemote(self.player, self.config.Protocol.Request); return self.remote.LastPayload end
		function f:buy(offer, rotation) self.shop.HandleRemote(self.player, self.config.Protocol.Buy, rotation or self.shop.GetSnapshot(self.player).RotationId, offer.Id); return self.remote.LastPayload end
		return f
	end
	test("same catalog and date produce identical offers regardless of dictionary insertion order", function()
		local entries = Catalog.Build(Config, definitions)
		local reversed = clone(Config); reversed.Items = {Revolver = {}, Knife = {}}
		for _, kind in ipairs({"Revolver", "Knife"}) do
			local keys = {}; for name in pairs(Config.Items[kind]) do table.insert(keys, name) end
			table.sort(keys, function(a,b) return a>b end)
			for _, name in ipairs(keys) do reversed.Items[kind][name] = {} end
		end
		local other = Catalog.Build(reversed, definitions)
		local a, b = Catalog.Rotate(Config, entries, 1800000000), Catalog.Rotate(reversed, other, 1800000000)
		eq(a.RotationId, b.RotationId); eq(#a.Offers, 5)
		for i, offer in ipairs(a.Offers) do eq(offer.Id, b.Offers[i].Id) end
	end)
	test("a full year of rotations has no duplicate, Godly or emote offers", function()
		local entries = Catalog.Build(Config, definitions); local seen = {}
		for day = 1, 365 do
			local rotation = Catalog.Rotate(Config, entries, 1800000000 + day*86400)
			eq(#rotation.Offers, 5); local today = {}
			for _, item in ipairs(rotation.Offers) do
				assert(not today[item.Id]); today[item.Id] = true; seen[item.Id] = true
				assert(item.Rarity ~= "Godly" and (item.ItemType == "Knife" or item.ItemType == "Revolver"))
				eq(item.ProductName, item.ItemType .. " - " .. item.Name)
			end
		end
		local count = 0; for _ in pairs(seen) do count+=1 end; assert(count > 20)
	end)
	test("UTC midnight and configured offsets change rotation exactly at their boundary", function()
		local entries = Catalog.Build(Config, definitions)
		local before = Catalog.Rotate(Config, entries, 1800057599)
		local after = Catalog.Rotate(Config, entries, before.ResetsAt)
		assert(before.RotationId ~= after.RotationId); eq(after.ResetsAt - before.ResetsAt, 86400)
		local offset = clone(Config); offset.ResetOffsetSeconds = 3600
		local id,_,time = Catalog.Window(offset, 1800000000); local nextId = Catalog.Window(offset,time)
		assert(id ~= nextId); eq(time%86400,3600)
	end)
	test("allowlist rejects Godly content, bad numbers and missing models", function()
		local config = clone(Config)
		config.Items.Knife.Frostbite = {}; config.Items.Knife["Shadow Dagger"] = {}
		config.Items.Emote = {Griddy = {Price = 1, MinLevel = 0}}
		config.Items.Revolver["Bubble Gun Revolver"] = {}; config.Items.Revolver["White&Black Revolver"] = {}
		config.Items.Knife.Bowie = {Price = 0/0}; config.Items.Knife.Butterfly = {MinLevel = math.huge}
		local entries, issues = Catalog.Build(config, definitions, function(_,name) return name ~= "Karambit" end)
		assert(#issues >= 5)
		for _, entry in ipairs(entries) do
			assert(entry.Name ~= "Karambit" and entry.Name ~= "Bowie" and entry.Name ~= "Butterfly")
			assert(entry.Rarity ~= "Godly")
		end
	end)
	test("overrides apply to valid items and disabled/small catalogs produce no filler", function()
		local config = clone(Config); config.Items = {Knife = {Bowie = {Price = 777, MinLevel = 2}}, Revolver = {}}
		local entries = Catalog.Build(config, definitions); eq(entries[1].Price, 777); eq(entries[1].MinLevel,2)
		eq(#Catalog.Rotate(config,entries,1800000000).Offers,1)
		config.Enabled = false; eq(#Catalog.Rotate(config,entries,1800000000).Offers,0)
	end)
	test("successful purchase charges the server price and saves one item with one daily marker", function()
		local f = fixture(); local snapshot = f:request(); local offer = snapshot.Offers[1]; local cash = f.cash.Value
		local result = f:buy(offer); eq(result.Code,"Success"); eq(f.cash.Value,cash-offer.Price); eq(f.grants,1); eq(f.saves,1)
		eq(f.saved.Purchased[offer.Id],true); eq(f.stats.Inventory[offer.Name].Quantity.Value,1)
	end)
	test("revolver purchases grant to RevolverInventory and use their own server price and marker", function()
		local f=fixture(); local offer=f:request().Offers[5]; local cash=f.cash.Value
		eq(f:buy(offer).Code,"Success"); eq(f.stats.RevolverInventory[offer.Name].Quantity.Value,1)
		eq(f.stats.Inventory[offer.Name],nil); eq(f.cash.Value,cash-offer.Price)
		eq(f.profile.Data.DailyShop.Purchased[offer.Id],true)
	end)
	test("disabled shop and missing or invalid server models never produce purchasable filler", function()
		local f=fixture(); f.config.Enabled=false; local snapshot=f:request(); eq(#snapshot.Offers,0)
		eq(f:buy({Id="Knife:Bowie"}).Code,"Disabled"); eq(f.grants,nil)
		local other=fixture(); other.SS.Knives:ClearAllChildren(); other.SS.Revolvers:ClearAllChildren()
		Mock.object("Folder","Bowie",other.SS.Knives)
		eq(#other:request().Offers,0); eq(other.grants,nil)
	end)
	test("daily marker blocks buying again after trading away or rejoining with the same profile", function()
		local f = fixture(); local offer = f:request().Offers[1]; f:buy(offer); f.stats.Inventory[offer.Name]:Destroy()
		f:step(1); eq(f:buy(offer).Code,"Purchased"); eq(f.grants,1)
		local reconnect = fixture(); reconnect.profile.Data = clone(f.profile.Data)
		eq(reconnect:buy(offer).Code,"Purchased"); eq(reconnect.grants,nil)
	end)
	test("server rejects owned items, low levels and insufficient Gold without mutating cash", function()
		local f = fixture(); local offers = f:request().Offers
		local owned = Mock.object("StringValue", offers[1].Name, f.stats.Inventory); Mock.object("IntValue","Quantity",owned,2)
		local cash = f.cash.Value; eq(f:buy(offers[1]).Code,"Owned"); eq(f.cash.Value,cash)
		f:step(1); f.xp.Value=150; eq(f:buy(offers[3]).Code,"LevelLocked"); eq(f.cash.Value,cash)
		f:step(1); f.cash.Value=1; eq(f:buy(offers[1]).Code,"Owned")
		owned:Destroy(); f:step(1); eq(f:buy(offers[1]).Code,"InsufficientGold"); eq(f.cash.Value,1); eq(f.grants,nil)
	end)
	test("expired, unoffered, Godly and emote identifiers cannot buy anything", function()
		local f = fixture(); local snapshot = f:request(); local offer = snapshot.Offers[1]; local cash = f.cash.Value
		f.now = snapshot.ResetsAt; eq(f:buy(offer,snapshot.RotationId).Code,"Expired")
		for _, id in ipairs({"Knife:Frostbite","Emote:Griddy","Revolver:Bubble Gun Revolver","Knife:Unknown"}) do
			f:step(1); eq(f:buy({Id=id}).Code,"Unavailable")
		end
		eq(f.cash.Value,cash); eq(f.grants,nil)
	end)
	test("spam and malformed packets have bounded responses and grants", function()
		local f = fixture(); local offer = f:request().Offers[1]; local reads=f.remote.ClientCalls
		for _=1,100 do f:request() end; eq(f.remote.ClientCalls,reads)
		for _, id in ipairs({{},0/0,math.huge,7,string.rep("a",10000)}) do f.shop.HandleRemote(f.player,Config.Protocol.Buy,"1:1",id) end
		eq(f.remote.ClientCalls,reads)
		for _=1,100 do f:buy(offer) end; eq(f.grants,1); eq(f.remote.ClientCalls,reads+1)
		f:step(1); eq(f:buy(offer).Code,"Purchased")
	end)
	test("loading, departed or lost-session players cannot spend or receive items", function()
		local f = fixture(); local offer = f:request().Offers[1]
		f.player:SetAttribute("DataReady",false); eq(f:buy(offer).Code,"Loading"); eq(f.grants,nil)
		f:step(1); f.player:SetAttribute("DataReady",true); f.active=false
		eq(f:buy(offer).Code,"Loading"); eq(f.grants,nil)
		f:step(1); f.active=true; f.player.Parent=nil; local replies=f.remote.ClientCalls; f:buy(offer)
		eq(f.remote.ClientCalls,replies); eq(f.grants,nil)
	end)
	test("partial failed grant refunds and removes its partial item without setting a marker", function()
		local f=fixture(); local offer=f:request().Offers[1]; local cash=f.cash.Value; f.failGrant=true
		eq(f:buy(offer).Code,"GrantFailed"); eq(f.cash.Value,cash); eq(f.stats.Inventory[offer.Name],nil)
		eq(f.profile.Data.DailyShop.Purchased[offer.Id],nil); eq(f.saves,0)
		f.failGrant=false; f:step(1); eq(f:buy(offer).Code,"Success")
	end)
	test("failure on a zero-quantity existing item restores its quantity and balance", function()
		local f=fixture(); local offer=f:request().Offers[1]; local item=Mock.object("StringValue",offer.Name,f.stats.Inventory)
		Mock.object("IntValue","Quantity",item,0); f.failGrant=true; local cash=f.cash.Value
		eq(f:buy(offer).Code,"GrantFailed"); eq(item.Quantity.Value,0); eq(f.cash.Value,cash)
	end)
	test("existing PurchaseGoldRemote routes daily commands while numeric products still prompt Roblox", function()
		local f=fixture(); local gameFolder=Mock.object("Folder","Game",f.server)
		f.register(gameFolder,"SendNotification",{SendNotification=function() end})
		f.register(f.servicesFolder,"VIPService",{})
		f.register(f.servicesFolder,"ReceiptArchive",load("ReceiptArchive", {}))
		f:load("Purchases",f.servicesFolder,"PurchaseHandler")
		f.remote.OnServerEvent:Fire(f.player,Config.Protocol.Request); local offer=f.remote.LastPayload.Offers[1]
		f.remote.OnServerEvent:Fire(f.player,Config.Protocol.Buy,f.remote.LastPayload.RotationId,offer.Id)
		eq(f.remote.LastPayload.Code,"Success"); eq(f.prompts,0)
		f.remote.OnServerEvent:Fire(f.player,3548743272); eq(f.prompts,1)
	end)
	local function authoredDaily(f, holders, templates)
		local add=Mock.object
		f.frame=add("Frame","Daily",holders)
		f.others=add("Frame","Others",f.frame); f.mainDaily=add("Frame","Main",f.frame)
		add("TextLabel","ResetTimer",f.frame); add("TextLabel","ShopStatus",f.frame)
		local folder=add("Folder","DailyShopTemplates",templates)
		local function template(name, large)
			local card=add("ImageButton",name,folder)
			local owned=add("Frame","AlreadyOwned",card); local image=add("ImageLabel","ItemImage",card)
			local divider=add("Frame","Divider",card); local productName=add("TextLabel","ProductName",divider)
			local price=large and add("TextLabel","Text",add("Frame","ItemPrice",card)) or add("TextLabel","Price",divider)
			return card,{Owned=owned,Image=image,Name=productName,Price=price}
		end
		local small,smallFields=template("SmallItemTemplate",false); local large,largeFields=template("LargeItemTemplate",true)
		f.layout={
			{Template=small,Fields=smallFields,Parent=f.others,Position=Mock.UDim2.fromScale(0,0)},
			{Template=small,Fields=smallFields,Parent=f.others,Position=Mock.UDim2.fromScale(0,0.5)},
			{Template=small,Fields=smallFields,Parent=f.others,Position=Mock.UDim2.fromScale(0,1)},
			{Template=large,Fields=largeFields,Parent=f.mainDaily,Position=Mock.UDim2.fromScale(0,0)},
			{Template=large,Fields=largeFields,Parent=f.mainDaily,Position=Mock.UDim2.fromScale(1,0)},
		}
		function f:card(index) index=index or 1; return (index<=3 and self.others or self.mainDaily):FindFirstChild("DailyShopSlot"..index) end
	end
	local function clientFixture(prepare, customize)
		local f=fixture(); local holders=Mock.object("Folder","Holders"); local templates=Mock.object("Folder","UITemplates")
		authoredDaily(f,holders,templates)
		if customize then customize(f) end
		f.shopFrame=Mock.object("Frame","Shop"); f.shopFrame.Visible=true
		f.remote.OnSend=function(...) f.shop.HandleRemote(f.player,...) end
		f.remote.OnReply=function(_,payload) f.remote.OnClientEvent:Fire(payload) end
		f.client=f:load("Client",nil).New(f.player,f.frame,f.remote,f.shopFrame,f.layout)
		f.frame.Visible=true
		f.client.Open()
		if prepare~=false then f:tickFrames(12) end
		return f
	end
	test("daily cards reuse templates with prefixed names, server prices and server-backed purchase state", function()
		local f=clientFixture(); local card=f:card(); local offer=f.shop.GetSnapshot(f.player).Offers[1]
		eq(card.Divider.ProductName.Text,offer.ProductName); eq(card.ItemImage.Image,offer.Image); eq(card.Active,true)
		card.Activated:Fire(); eq(f.remote.LastPayload.Code,"Success"); f:tickFrames(12); eq(f:card().AlreadyOwned.Visible,true); eq(card.Active,false)
		eq(f.remote.LastRequest[1],Config.Protocol.Buy); eq(f.prompts,0)
	end)
	test("ownership, funds and levels update from replicated values without reopening the daily frame", function()
		local f=clientFixture(); local card=f:card(); local offer=f.shop.GetSnapshot(f.player).Offers[1]
		local item=Mock.object("StringValue",offer.Name,f.stats.Inventory); Mock.object("IntValue","Quantity",item,1)
		f:tickFrames(6); eq(card.AlreadyOwned.Visible,true); eq(card.Active,false)
		item:Destroy(); f:tickFrames(6); eq(card.Active,true)
		f.cash.Value=0; f:tickFrames(6); eq(card.Active,false); assert(string.find(card.Divider.Price.Text,"Not enough"))
		f.cash.Value=100000; f.xp.Value=150; f:tickFrames(6); eq(f:card(3).Active,false); assert(string.find(f:card(3).Divider.Price.Text,"Level"))
	end)
	test("visible daily frame refreshes at midnight while hidden frame does no network work", function()
		local f=clientFixture(); local old=f.remote.LastPayload.RotationId; local reset=f.remote.LastPayload.ResetsAt
		local card=f:card(); local clones=f.clones
		f.now=reset; f:step(2); f:tickFrames(6); assert(f.remote.LastPayload.RotationId~=old)
		eq(#f.others:GetChildren(),3); eq(#f.mainDaily:GetChildren(),2); eq(f.clones,clones); eq(f:card(),card)
		f.frame.Visible=false; local requests=f.remote.ServerCalls; f:step(86401); eq(f.remote.ServerCalls,requests)
		f.frame.Visible=true; assert(f.remote.ServerCalls>requests)
	end)
	test("lost purchase response recovers and daily client releases all hooks on GUI destruction", function()
		local f=clientFixture(); f.remote.OnReply=nil
		f:card().Activated:Fire(); f:tickFrames(6); eq(f:card().Divider.Price.Text,"Purchasing...")
		f.remote.OnReply=function(_,payload) f.remote.OnClientEvent:Fire(payload) end
		f:step(9); f:tickFrames(6); eq(f:card().AlreadyOwned.Visible,true)
		local oldButton=f:card(); f.frame:Destroy()
		eq(f.heartbeat:Count(),0); eq(f.remote.OnClientEvent:Count(),0); eq(oldButton.Activated:Count(),0)
	end)
	test("loading data recovers automatically and failed snapshots do not stall the shop", function()
		local f=clientFixture(); f.player:SetAttribute("DataReady",false); f.client.Refresh(); f:step(2)
		f.player:SetAttribute("DataReady",true); f:step(2); f:tickFrames(6); eq(#f.others:GetChildren(),3); eq(#f.mainDaily:GetChildren(),2)
		f.remote.OnClientEvent:Fire({Kind=Config.Protocol.Response,Ready=false,Code="Error"})
		f:step(2); f:tickFrames(6); eq(f:card().Active,true); eq(f.frame.ShopStatus.Text,"")
	end)
	test("shop tweens cancel stale close callbacks and restore authored position and scale", function()
		local f=fixture(); local frame=Mock.object("Frame","Shop"); local position=frame.Position
		local scale=Mock.object("UIScale","Scale",frame); scale.Scale=1.2
		local transitions=f:load("Transitions",nil); local controller=transitions.Attach(frame)
		eq(transitions.Attach(frame),controller); frame.Visible=true; eq(scale.Scale,1.2)
		local closed=0; controller.Close(function() closed+=1 end); local old=f.tweens[#f.tweens]
		controller.Open(); old.Completed:Fire("Completed"); eq(frame.Visible,true); eq(closed,0)
		controller.Close(function() closed+=1 end); f.tweens[#f.tweens].Completed:Fire("Completed")
		eq(frame.Visible,false); eq(closed,1); eq(scale.Scale,1.2); eq(frame.Position,position)
		frame:Destroy(); eq(frame:GetPropertyChangedSignal("Visible"):Count(),0)
	end)
	test("exact five authored cards prepare one per frame with the correct fields, parents and positions", function()
		local f=clientFixture(false); eq(#f.others:GetChildren(),0)
		for index=1,5 do
			f:tickFrames(1)
			eq(#f.others:GetChildren()+#f.mainDaily:GetChildren(),index)
			local card=f:card(index); eq(card.Position,f.layout[index].Position); eq(card.Parent,f.layout[index].Parent)
			assert(card.Divider.ProductName.Text~="")
			if index>3 then assert(card.ItemPrice.Text.Text~=""); eq(card.Divider.Price,nil) end
		end
		eq(f.instanceCalls,nil)
	end)
	test("reopening and repeated snapshots preserve all five cards and idle UI performs no property writes", function()
		local f=clientFixture(); f.frame.Visible=false; f:tickFrames(6)
		local clones,writes,requests=f.clones,f.writes,f.remote.ServerCalls
		f:tickFrames(120); eq(f.writes,writes)
		for _=1,10 do f.frame.Visible=true; f.frame.Visible=false end
		eq(f.clones,clones); eq(f.remote.ServerCalls,requests)
		local card=f:card(); f.remote.OnClientEvent:Fire(f.shop.GetSnapshot(f.player)); f:tickFrames(6)
		eq(f:card(),card); eq(f.clones,clones); eq(f.instanceCalls,nil)
	end)
	test("failed authored template preparation stops once without a per-frame error or allocation loop",function()
		local f=clientFixture(false); f.layout[1].Template:SetAttribute("FailClone",true)
		f:tickFrames(1); eq(#f.warnings,1); eq(f.heartbeat:Count(),0); eq(#f.others:GetChildren(),0)
		f:tickFrames(60); eq(#f.warnings,1); eq(f.instanceCalls,nil)
	end)
	test("a frame-based large template uses its existing ItemPrice button without creating controls",function()
		local f=clientFixture(true,function(state)
			state.layout[4].Template.ClassName="Frame"; state.layout[4].Template.ItemPrice.ClassName="ImageButton"
		end)
		local card=f:card(4); eq(card.ItemPrice.Active,true); card.ItemPrice.Activated:Fire(); f:tickFrames(6)
		eq(f.remote.LastPayload.Code,"Success"); eq(card.AlreadyOwned.Visible,true); eq(f.instanceCalls,nil)
	end)
	local function guiFixture(legacy)
		local f=fixture(); local add=Mock.object
		f.player.PlayerGui=add("Folder","PlayerGui",f.player)
		local main=add("ScreenGui","Main",f.player.PlayerGui); f.frames=add("Folder","Frames",main)
		f.shopFrame=add("Frame","Shop",f.frames); f.menu=add("Frame","Menu",f.shopFrame)
		f.holders=add("Folder","Holders",f.shopFrame)
		f.close=add("ImageButton","Close",f.shopFrame); f.back=add("ImageButton","Back",f.shopFrame)
		add("TextLabel","Text",add("Frame","Top",f.shopFrame))
		f.knifeFrame=add("ScrollingFrame",legacy and "Cases" or "KnivesCases",f.holders)
		f.revFrame=not legacy and add("ScrollingFrame","RevolversCases",f.holders) or f.knifeFrame
		f.emoteFrame=add("ScrollingFrame","Emotes",f.holders)
		f.tabs=add("Frame","CratesTabSelection",f.shopFrame)
		for _, name in ipairs({"Knives","Revolvers","Emotes"}) do add("ImageButton",name,f.tabs) end
		for _, name in ipairs({"Cases","Daily","Robux"}) do add("ImageButton",name,f.menu) end
		local popup=add("Frame","CasesPopup",f.shopFrame); add("ImageButton","Close",add("Frame","Top",add("Frame","Holder",popup)))
		local spinner=add("Frame","Spinner",f.frames); local container=add("Frame","Container",spinner)
		add("Frame","SpinFrame",container); add("Frame","Spinner",container)
		local buttons=add("Frame","Buttons",spinner)
		for _, name in ipairs({"Exit","OpenAgain","Skip"}) do add("ImageButton",name,buttons) end
		add("TextLabel","Header",buttons)
		local robux=add("Frame","Robux",f.holders); local robuxTabs=add("Frame","TabSelection",robux)
		for _, name in ipairs({"Gold","Passes","VIP"}) do add("ScrollingFrame",name,robux); add("ImageButton",name,robuxTabs) end
		local subscribe=add("Frame","SubscribeFrame",robux.VIP)
		add("TextLabel","SubscriptionStatus",subscribe); add("ImageButton","3548752161",subscribe); add("ImageButton","3548752035",subscribe)
		local cases=add("Folder","CaseOpening",f.remotes); add("RemoteEvent","OpenCase",cases); add("RemoteEvent","CaseAnimationClient",cases)
		local templates=add("Folder","UITemplates",f.RS); local caseTemplates=add("Folder","CaseOpeningTemplates",templates)
		authoredDaily(f,f.holders,templates)
		for _, name in ipairs({"OddsItemTemplate","OddsItemTemplateEmote","CaseSpinnerTemplate","CaseSpinnerTemplateEmote"}) do add("ImageButton",name,caseTemplates) end
		local caseTemplate=add("ImageButton","CaseTemplate",caseTemplates)
		add("ImageLabel","CaseImage",caseTemplate); local bottom=add("Frame","Bottom",caseTemplate)
		add("TextLabel","CaseName",bottom); add("TextLabel","CaseCost",bottom)
		f.register(f.modulesFolder,"CasesInfo",{
			KnifeCase={ItemType="Knife",Price=1000,Order=1},
			RevolverCase={ItemType="Revolver",Price=600,Order=2},
			EmoteCase={ItemType="Emote",EmoteCase=true,Price=500,Order=3},
		})
		f.register(f.modulesFolder,"RandomItems",{}); f.register(f.modulesFolder,"Emotes",{})
		local client=add("Folder","CLIENT"); local modules=add("Folder","Modules",client)
		f.register(modules,"SoundHandler",{PlaySound=function() end}); f.register(modules,"CaseViewportPool",{})
		f.register(modules,"DailyShopClient",f:load("Client",nil))
		f:load("Reveal",modules,"UIReveal")
		f:load("Transitions",modules,"UITransitions")
		f:load("ShopTransitions",modules,"ShopTransitions")
		f.register(modules,"ShopAssets",f:load("Assets",nil))
		f:load("ShopGUI",client)
		f.clientFolder,f.clientModules=client,modules
		f.shopFrame.Visible=true; f.menu.Visible=true
		f:tickFrames(12)
		return f
	end
	test("actual ShopGUI opens Daily and Cases with the requested category frames and exact colors", function()
		local f=guiFixture(false)
		f.menu.Daily.Activated:Fire(); eq(f.holders.Daily.Visible,true); eq(f.menu.Visible,false); eq(f.tabs.Visible,false)
		f.back.Activated:Fire(); eq(f.menu.Visible,true); eq(f.holders.Daily.Visible,false)
		f.menu.Cases.Activated:Fire(); eq(f.knifeFrame.Visible,false); eq(f.revFrame.Visible,true); eq(f.tabs.Visible,true)
		eq(f.tabs.Revolvers.BackgroundColor3,"71,81,95"); eq(f.tabs.Knives.BackgroundColor3,"46,53,63")
		f.tabs.Revolvers.Activated:Fire(); eq(f.knifeFrame.Visible,false); eq(f.revFrame.Visible,true)
		eq(f.tabs.Revolvers.BackgroundColor3,"71,81,95"); eq(f.tabs.Knives.BackgroundColor3,"46,53,63")
		f.tabs.Emotes.Activated:Fire(); eq(f.revFrame.Visible,false); eq(f.emoteFrame.Visible,true)
		f.menu.Robux.Activated:Fire(); eq(f.tabs.Visible,false); eq(f.emoteFrame.Visible,false)
		f.menu.Cases.Activated:Fire(); eq(f.revFrame.Visible,true); eq(f.tabs.Revolvers.BackgroundColor3,"71,81,95")
	end)
	test("legacy shared case frame filters categories without rebuilding or duplicating cards", function()
		local f=guiFixture(true); local count=#f.knifeFrame:GetChildren()
		f.menu.Cases.Activated:Fire(); eq(f.knifeFrame.KnifeCase.Visible,false); eq(f.knifeFrame.RevolverCase.Visible,true)
		for _=1,10 do f.tabs.Revolvers.Activated:Fire(); f.tabs.Knives.Activated:Fire() end
		f.tabs.Revolvers.Activated:Fire(); eq(f.knifeFrame.KnifeCase.Visible,false); eq(f.knifeFrame.RevolverCase.Visible,true)
		eq(#f.knifeFrame:GetChildren(),count); eq(f.knifeFrame.RevolverCase.Activated:Count(),1)
	end)
	test("root opening uses one position tween, never scales or adds UI and duplicate opens are coalesced",function()
		local f=fixture(); local frame=Mock.object("Frame","Shop"); local authored=Mock.object("UIScale","AuthoredScale",frame); authored.Scale=0.85
		local transitions=f:load("Transitions",nil); local control=transitions.Attach(frame)
		local children=#frame:GetChildren(); frame.Visible=true; local count=#f.tweens
		control.Open(); control.Open(); eq(#f.tweens,count); eq(count,1); eq(f.tweens[1].Target,frame)
		eq(f.tweens[1].Goals.Scale,nil); eq(#frame:GetChildren(),children); eq(authored.Scale,0.85); eq(f.instanceCalls,nil)
	end)
	test("actual top-button hover keeps authored proportions and rapid shop toggles cannot leave stale blur callbacks",function()
		local f=guiFixture(false); local main=f.shopFrame.Parent.Parent
		local top=Mock.object("Frame","Top",main); local buttons=Mock.object("Frame","Buttons",top)
		local button=Mock.object("ImageButton","Shop",buttons); button.Size=Mock.UDim2.new(0.071,0,1,0)
		Mock.object("Frame","Trade",f.frames); f.register(f.clientModules,"SpectateHandler",{})
		f:load("FramesHandler",f.clientFolder)
		button.MouseEnter:Fire(); assert(button.Size.Y.Scale<1.1); assert(button.Size.X.Scale<0.08)
		button.MouseLeave:Fire(); eq(button.Size,Mock.UDim2.new(0.071,0,1,0))
		f.shopFrame.Visible=false; button.MouseButton1Up:Fire(); eq(f.shopFrame.Visible,true)
		button.MouseButton1Up:Fire(); local closeTween=f.tweens[#f.tweens]
		button.MouseButton1Up:Fire(); closeTween.Completed:Fire("Completed")
		eq(f.shopFrame.Visible,true); eq(f.services.Lighting.Blur.Enabled,true)
	end)
	test("UI image warming is bounded, deduplicated, runs outside opening, and tolerates missing assets",function()
		local f=fixture(); local root=Mock.object("Frame","Shop")
		for i=1,30 do local image=Mock.object("ImageLabel","Image"..i,root); image.Image="rbxassetid://"..(i%7+1) end
		local warmer=f:load("Assets",nil).New(root); f.failPreload=true; f:tickFrames(20)
		local seen={}; for _,batch in ipairs(f.preloads) do assert(#batch<=4); for _,id in ipairs(batch) do assert(not seen[id]); seen[id]=true end end
		local count=#f.preloads; warmer.QueueImage("rbxassetid://1"); f:tickFrames(6); eq(#f.preloads,count)
		eq(f.heartbeat:Count(),0); warmer.Destroy()
	end)
	print(string.format("Passed %d daily shop checks",passed))
end
