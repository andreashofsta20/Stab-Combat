-- // SERVICES // --
local Module = {}
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")



-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")


local TopFrame = MainGUI:WaitForChild("Top")
local TopButtonsFrame = TopFrame:WaitForChild("Buttons")
local FramesFolder = MainGUI:WaitForChild("Frames")

-- // SOUNDS // --

local SoundHandlerModule = require(script.Parent.Modules:WaitForChild("SoundHandler"))
local UITransitions = require(script.Parent.Modules:WaitForChild("UITransitions"))
UITransitions.BindMenus(FramesFolder)
if SoundHandlerModule.BindClickSounds then SoundHandlerModule.BindClickSounds(MainGUI) end
require(script.Parent.Modules:WaitForChild("SpectateHandler"))


-- // MAIN FUNCTIONS // --

function Module.OpenFrame(FrameName : string)
	
	if FramesFolder:FindFirstChild("Spinner").Visible == true then return end
	if FramesFolder:FindFirstChild("Trade").Visible == true then return end
	
	local FrameToOpen = FramesFolder:FindFirstChild(FrameName)
	
	if not FrameToOpen then
		return
	end
	
	if FrameToOpen.Visible == true then
		local transition = UITransitions.Attach(FrameToOpen)
		if transition.Closing then transition.Open()
		else transition.Close(function() Lighting.Blur.Enabled = false end) end
		return
	end
	
	
	for i , v in pairs(FramesFolder:GetChildren()) do
		if v:IsA("GuiObject") then
			v.Visible = false
		end
	end
	Lighting.Blur.Enabled = true
	
	UITransitions.Attach(FrameToOpen)
	FrameToOpen.Visible = true
end


for i , v in pairs(TopButtonsFrame:GetChildren()) do
	if v:IsA("ImageButton") then
		local authoredSize = v.Size
		
		v.MouseEnter:Connect(function()
			UITransitions.Hover(v, authoredSize, true)
			SoundHandlerModule.PlaySound("HoverTopButtons")
		end)
		
		v.MouseLeave:Connect(function()
			UITransitions.Hover(v, authoredSize, false)
		end)
		
		v.MouseButton1Up:Connect(function()
			if v.Name == "Spectate" then
				-- SpectateHandler owns this input and rebinds it when its GUI is replaced.
				return
			end
			Module.OpenFrame(v.Name)
			SoundHandlerModule.PlaySound("ClickTopButtons")
		end)
		
		
		
	end
	
end







return Module
