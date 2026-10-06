-- Native camera/menu cooperation; no continuous render loop or camera poses.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")
local Cursor = require(RS.Modules.MouseCursorVisibility)
local Config = require(RS.Modules.CameraToggleConfig)
local player = Players.LocalPlayer
local Menu = {}
local connections, uiConnections = {}, {}
local initialized, writingMode = false, false
local main, modal, savedMode, savedMin, ownedMin
local zoomBinding = "MenuCameraZoomRestore"

local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

local function visible(object)
	if not object then return false end
	local ancestor = object
	while ancestor and ancestor ~= player do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
		if ancestor:IsA("LayerCollector") and not ancestor.Enabled then return false end
		ancestor = ancestor.Parent
	end
	return ancestor == player
end

local function blocked()
	local frames = main and main:FindFirstChild("Frames")
	if frames then
		for _, frame in ipairs(frames:GetChildren()) do
			if frame:IsA("GuiObject") and visible(frame) then return true end
		end
	end
	local emote = main and main:FindFirstChild("EmoteFrame")
	return visible(emote and emote:FindFirstChild("background"))
		or visible(main and main:FindFirstChild("TutorialFrame"))
end

local function ownCamera()
	local character, camera = player.Character, workspace.CurrentCamera
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return not VRService.VREnabled and humanoid and humanoid.Health > 0
		and character:GetAttribute("Ragdolled") ~= true and camera
		and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
end

local function setMode(mode)
	writingMode = true
	player.CameraMode = mode
	writingMode = false
end

local function restoreZoom()
	RunService:UnbindFromRenderStep(zoomBinding)
	if ownedMin and player.CameraMinZoomDistance == ownedMin then
		player.CameraMinZoomDistance = math.min(savedMin, player.CameraMaxZoomDistance)
	end
	savedMin, ownedMin = nil, nil
end

local function release()
	if modal then modal.Visible = false end
	Cursor.Hide("MenuCamera")
	restoreZoom()
	if savedMode and player.CameraMode == Enum.CameraMode.Classic then setMode(savedMode) end
	savedMode = nil
end

local function update()
	if not initialized then return end
	if not blocked() then release(); return end
	if modal then modal.Visible = true end
	Cursor.Show("MenuCamera")
	if savedMode or not ownCamera() then return end
	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson and distance > Config.FirstPersonDistance then return end
	savedMode = player.CameraMode
	setMode(Enum.CameraMode.Classic)
	restoreZoom()
	local minimum = player.CameraMinZoomDistance
	local target = math.clamp(Config.ReturnZoomDistance, minimum, player.CameraMaxZoomDistance)
	if target > minimum then
		savedMin, ownedMin = minimum, target
		player.CameraMinZoomDistance = target
		RunService:BindToRenderStep(zoomBinding, Enum.RenderPriority.Camera.Value + 4, restoreZoom)
	end
end

local function bindUI()
	disconnect(uiConnections)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local replacement = gui and gui:FindFirstChild("Main")
	if main ~= replacement then
		release()
		if modal then modal:Destroy(); modal = nil end
		main = replacement
	end
	if gui then
		table.insert(uiConnections, gui.ChildAdded:Connect(bindUI))
		table.insert(uiConnections, gui.ChildRemoved:Connect(bindUI))
	end
	if main then
		if not modal then
			modal = Instance.new("TextButton")
			modal.Name, modal.Text = "MenuCursorRelease", ""
			modal.BackgroundTransparency, modal.TextTransparency = 1, 1
			modal.Size, modal.Position = UDim2.fromOffset(1, 1), UDim2.fromOffset(-4, -4)
			modal.Active, modal.Selectable, modal.Modal, modal.Visible = false, false, true, false
			modal.Parent = main
		end
		table.insert(uiConnections, main.ChildAdded:Connect(bindUI))
		table.insert(uiConnections, main.ChildRemoved:Connect(bindUI))
		table.insert(uiConnections, main:GetPropertyChangedSignal("Enabled"):Connect(update))
		local function watch(object)
			if object and object:IsA("GuiObject") then
				table.insert(uiConnections, object:GetPropertyChangedSignal("Visible"):Connect(update))
			end
		end
		local frames = main:FindFirstChild("Frames")
		if frames then
			watch(frames)
			table.insert(uiConnections, frames.ChildAdded:Connect(bindUI))
			table.insert(uiConnections, frames.ChildRemoved:Connect(bindUI))
			for _, frame in ipairs(frames:GetChildren()) do watch(frame) end
		end
		local emote = main:FindFirstChild("EmoteFrame")
		if emote then
			watch(emote); watch(emote:FindFirstChild("background"))
			table.insert(uiConnections, emote.ChildAdded:Connect(bindUI))
			table.insert(uiConnections, emote.ChildRemoved:Connect(bindUI))
		end
		watch(main:FindFirstChild("TutorialFrame"))
	end
	update()
end

function Menu.IsWritingMode() return writingMode end
function Menu.IsSuspendingFirstPerson() return savedMode == Enum.CameraMode.LockFirstPerson end
function Menu.IsBlocking() return initialized and blocked() end

function Menu.Init()
	if initialized then return end
	initialized = true
	table.insert(connections, player.ChildAdded:Connect(function(child) if child:IsA("PlayerGui") then bindUI() end end))
	table.insert(connections, player.ChildRemoved:Connect(function(child) if child:IsA("PlayerGui") then bindUI() end end))
	table.insert(connections, player.CharacterAdded:Connect(update))
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(update))
	bindUI()
end

function Menu.Destroy()
	if not initialized then return end
	initialized = false
	disconnect(connections); disconnect(uiConnections)
	release()
	if modal then modal:Destroy(); modal = nil end
	main = nil
end

return Menu
