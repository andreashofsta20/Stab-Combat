-- Test-only bounded native client samples and error collection.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local Stats=game:GetService("Stats")
local RS=game:GetService("ReplicatedStorage")
local remote=RS:WaitForChild("BetaAuditMetrics")
local samples,index={},0
local errors={}
game:GetService("LogService").MessageOut:Connect(function(message,kind)
	if kind==Enum.MessageType.MessageError and #errors<50 then table.insert(errors,message) end
end)
Run.RenderStepped:Connect(function(dt) index=index%600+1; samples[index]=dt*1000 end)
remote.OnClientEvent:Connect(function()
	local values=table.clone(samples); table.sort(values)
	remote:FireServer({MemoryMB=Stats:GetTotalMemoryUsageMb(),LuaKB=gcinfo(),Instances=#game:GetDescendants(),
		FrameP50=values[math.max(1,math.ceil(#values*.5))],FrameP95=values[math.max(1,math.ceil(#values*.95))],
		Errors=errors})
end)
