local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remote = RS.Remotes:WaitForChild("Practice")
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.Parent = "Practice", false, 25, player:WaitForChild("PlayerGui")
local connections = {}
local function own(signal, fn) table.insert(connections,signal:Connect(fn)) end
local function button(text, y)
	local b = Instance.new("TextButton")
	b.Text, b.Size, b.Position = text, UDim2.fromOffset(190,38), UDim2.new(1,-210,1,y)
	b.TextColor3, b.BackgroundColor3, b.TextSize, b.Parent = Color3.new(1,1,1), Color3.fromRGB(35,40,55), 16, gui
	return b
end
local enter = button("PRACTICE",-55)
local gun, knife, reload, stab = button("REVOLVER",-100), button("KNIFE",-145), button("RELOAD",-190), button("STAB",-235)
local status = Instance.new("TextLabel")
status.Size, status.Position, status.BackgroundTransparency = UDim2.fromOffset(520,50), UDim2.new(.5,-260,0,90), 1
status.TextColor3, status.TextStrokeTransparency, status.TextSize, status.Parent = Color3.new(1,1,1), .3, 18, gui
local function active() return player:GetAttribute("PracticeActive") == true end
local function refresh()
	enter.Visible = player:GetAttribute("DataReady") == true and player:GetAttribute("InRound") ~= true
	enter.Text = active() and "RETURN TO LOBBY" or "PRACTICE"
	for _, control in ipairs({gun,knife,reload,stab,status}) do control.Visible = active() end
end
local function shoot(action)
	if not active() or Input:GetFocusedTextBox() then return end
	local camera = workspace.CurrentCamera; if not camera then return end
	local pointer = Input:GetMouseLocation()
	local ray = camera:ViewportPointToRay(pointer.X,pointer.Y)
	if not action then
		local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
		action = tool and tool.Name == "Bowie" and "Throw" or "Fire"
	end
	remote:FireServer(action,ray.Origin,ray.Direction.Unit)
end
own(enter.Activated,function() remote:FireServer(active() and "Exit" or "Enter") end)
own(gun.Activated,function() remote:FireServer("EquipRevolver") end)
own(knife.Activated,function() remote:FireServer("EquipKnife") end)
own(reload.Activated,function() remote:FireServer("Reload") end)
own(stab.Activated,function() shoot("Stab") end)
own(Input.InputBegan,function(input,processed)
	if processed or not active() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then shoot()
	elseif input.KeyCode == Enum.KeyCode.R then remote:FireServer("Reload")
	elseif input.KeyCode == Enum.KeyCode.One then remote:FireServer("EquipKnife")
	elseif input.KeyCode == Enum.KeyCode.Two then remote:FireServer("EquipRevolver") end
end)
own(Input.TouchTapInWorld,function(_,processed) if not processed then shoot() end end)
own(remote.OnClientEvent,function(data)
	status.Text = string.format("%s  •  Hits %d / %d  •  Ammo %d",data.Message or "",data.Hits or 0,data.Attempts or 0,data.Ammo or 0)
end)
for _, name in ipairs({"PracticeActive","InRound","DataReady"}) do own(player:GetAttributeChangedSignal(name),refresh) end
own(gui.Destroying,function() for _, connection in ipairs(connections) do connection:Disconnect() end; table.clear(connections) end)
own(script.Destroying,function() gui:Destroy() end)
refresh()
return {}
