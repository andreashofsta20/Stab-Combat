-- // SERVICES // --
local Module = {}
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")



-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")


local TopFrame = MainGUI:WaitForChild("Top")
local TopButtonsFrame = TopFrame:WaitForChild("Buttons")
local FramesFolder = MainGUI:WaitForChild("Frames")


-- // MAIN FUNCTIONS // --

function Module.OpenFrame(FrameName : string)
	
	if FramesFolder:FindFirstChild("Spinner").Visible == true then return end
	
	local FrameToOpen = FramesFolder:FindFirstChild(FrameName)
	
	if not FrameToOpen then
		return
	end
	
	if FrameToOpen.Visible == true then
		FrameToOpen.Visible = false
		Lighting.Blur.Enabled = false
		return
	end
	
	
	for i , v in pairs(FramesFolder:GetChildren()) do
		if v:IsA("Frame") then
			v.Visible = false
		end
	end
	Lighting.Blur.Enabled = true
	
	FrameToOpen.Visible = true
end


local function HoverButton(Image : ImageButton)
	local goal = { Size = UDim2.new(0.081, 0,135, 0) } 
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(Image, tweenInfo, goal)
	tween:Play()
end

local function UnHoverButton(Image : ImageButton)
	local goal = { Size = UDim2.new(0.071, 0,1, 0) }
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(Image, tweenInfo, goal)
	tween:Play()
end

for i , v in pairs(TopButtonsFrame:GetChildren()) do
	if v:IsA("ImageButton") then
		
		v.MouseEnter:Connect(function()
			HoverButton(v)
		end)
		
		v.MouseLeave:Connect(function()
			UnHoverButton(v)
		end)
		
		v.MouseButton1Up:Connect(function()
			Module.OpenFrame(v.Name)
		end)
		
		
		
	end
	
end







return Module