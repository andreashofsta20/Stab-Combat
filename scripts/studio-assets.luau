-- Read-only native asset audit plus a disposable backend probe in its own
-- namespace. Does not read player records, publish, or save the loaded place.
local Http = game:GetService("HttpService")
local report = {PlaceId=game.PlaceId,UniverseId=game.GameId,MaxPlayers=game:GetService("Players").MaxPlayers,
	MissingTemplates={},AssetResults={},Properties={},CatalogCounts={}}
for _, property in ipairs({"AuthorityMode","StreamingEnabled","SignalBehavior","PhysicsSteppingMethod"}) do
	local ok,value=pcall(function() return workspace[property] end)
	report.Properties[property]=tostring(value)
end
Http.HttpEnabled = true
local payload=Http:JSONDecode(Http:GetAsync("http://127.0.0.1:8765/run2-practice.json"))
for _, entry in ipairs(payload) do
	if entry.Path[1]=="ReplicatedStorage" and entry.Path[2]=="Modules" and entry.Source then
		local item=game.ReplicatedStorage.Modules:FindFirstChild(entry.Path[3]) or Instance.new("ModuleScript")
		item.Name,item.Source,item.Parent=entry.Path[3],entry.Source,game.ReplicatedStorage.Modules
	end
end
for kind,catalog in pairs({Knives=require(game.ReplicatedStorage.Modules.KnivesInfo),Revolvers=require(game.ReplicatedStorage.Modules.RevolversInfo)}) do
	local count=0; local folder=game.ServerStorage:FindFirstChild(kind)
	for name in pairs(catalog) do
		count+=1; local tool=folder and folder:FindFirstChild(name)
		if not tool or not tool:IsA("Tool") or tool.RequiresHandle and not tool:FindFirstChild("Handle") then table.insert(report.MissingTemplates,kind.."/"..name) end
	end
	report.CatalogCounts[kind]=count
end
local assets,seen={},{}
for _, node in ipairs(game:GetDescendants()) do
	local property=node:IsA("Sound") and "SoundId" or node:IsA("Animation") and "AnimationId"
		or (node:IsA("ImageLabel") or node:IsA("ImageButton")) and "Image" or node:IsA("MeshPart") and "MeshId"
	if property then
		local value=node[property]
		if value~="" and not seen[value] then seen[value]=true; table.insert(assets,value) end
	end
end
local complete,index=0,0
for _=1,4 do task.spawn(function()
	while index<#assets do
		index+=1; local id=assets[index]
		local ok,err=pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({id},function(content,status) report.AssetResults[content]=tostring(status) end)
		end)
		if not ok then report.AssetResults[id]=tostring(err) end
		complete+=1
	end
end) end
local deadline=os.clock()+120
repeat task.wait(.2) until complete==#assets or os.clock()>deadline
report.AssetCount,report.AssetRequestsCompleted=#assets,complete
report.Incomplete=complete<#assets
local key=Http:GenerateGUID(false)
local ok,err=pcall(function()
	local store=game:GetService("DataStoreService"):GetDataStore("BetaAudit_20261008_Probe")
	local value=store:UpdateAsync(key,function(old) assert(old==nil); return {Version=1,Probe=true} end)
	assert(value and value.Probe)
	local read=store:GetAsync(key); assert(read and read.Probe)
	store:RemoveAsync(key)
end)
report.LiveBackend={Available=ok,Error=not ok and tostring(err) or nil,Namespace="BetaAudit_20261008_Probe"}
print("STAB_ASSET_REPORT "..Http:JSONEncode(report))
