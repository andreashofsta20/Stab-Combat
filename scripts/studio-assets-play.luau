-- Asset verification on actual clients, independently of gameplay startup.
-- The edit-mode PreloadAsync result alone cannot establish client delivery.
local Http=game:GetService("HttpService")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
for _, item in ipairs(game:GetDescendants()) do if item:IsA("BaseScript") then item.Enabled=false end end
local remote=Instance.new("RemoteEvent"); remote.Name,remote.Parent="BetaAssetAudit",RS
local ids,seen={},{}
for _, node in ipairs(game:GetDescendants()) do
	local property=node:IsA("Sound") and "SoundId" or node:IsA("Animation") and "AnimationId"
		or (node:IsA("ImageLabel") or node:IsA("ImageButton")) and "Image" or node:IsA("MeshPart") and "MeshId"
	if property then local id=node[property]; if id~="" and not seen[id] then seen[id]=true; table.insert(ids,{Id=id,Property=property,Class=node.ClassName,Path=node:GetFullName()}) end end
end
remote:SetAttribute("AssetIds",Http:JSONEncode(ids))
local server=Instance.new("Script"); server.Name="BetaAssetServer"
server.Source=[=[
local report={Clients={},AssetCount=#game:GetService("HttpService"):JSONDecode(game.ReplicatedStorage.BetaAssetAudit:GetAttribute("AssetIds"))}
game.ReplicatedStorage.BetaAssetAudit.OnServerEvent:Connect(function(player,data) report.Clients[player.Name]=data end)
local deadline=os.clock()+150
repeat task.wait(.5) until report.Clients.Player1 and report.Clients.Player2 or os.clock()>deadline
game:GetService("StudioTestService"):EndTest(report)
]=]
server.Parent=SSS
local client=Instance.new("LocalScript"); client.Name="BetaAssetClient"
client.Source=[=[
local RS=game:GetService("ReplicatedStorage")
local remote=RS:WaitForChild("BetaAssetAudit")
local ids=game:GetService("HttpService"):JSONDecode(remote:GetAttribute("AssetIds"))
local report={Results={},Errors={}}
game:GetService("LogService").MessageOut:Connect(function(message,kind)
	if (kind==Enum.MessageType.MessageError or kind==Enum.MessageType.MessageWarning) and #report.Errors<100 then table.insert(report.Errors,message) end
end)
local index,complete=0,0
for _=1,4 do task.spawn(function()
	while index<#ids do
		index+=1; local info=ids[index]; local id=info.Id
		local asset
		local ok,err=pcall(function()
			asset=Instance.new(info.Property=="MeshId" and "SpecialMesh" or info.Class)
			if info.Property=="MeshId" then asset.MeshType=Enum.MeshType.FileMesh end
			asset[info.Property]=id
			game:GetService("ContentProvider"):PreloadAsync({asset},function(_,status) report.Results[id]=tostring(status) end)
		end)
		if asset then asset:Destroy() end
		if not ok then report.Results[id]=tostring(err) elseif not report.Results[id] then report.Results[id]="No callback (unverified)" end
		complete+=1
	end
end) end
local deadline=os.clock()+120
repeat task.wait(.2) until complete==#ids or os.clock()>deadline
report.Completed,report.Incomplete=complete,complete<#ids
remote:FireServer(report)
]=]
client.Parent=game:GetService("StarterPlayer").StarterPlayerScripts
task.wait(3)
local ok,result=pcall(function() return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2,"AssetAudit") end)
print("STAB_CLIENT_ASSET_REPORT "..Http:JSONEncode({Started=ok,Result=ok and result or tostring(result)}))
