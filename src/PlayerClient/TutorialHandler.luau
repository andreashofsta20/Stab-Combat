local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local StartTutorialRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tutorial"):WaitForChild("StartTutorial")

local TutorialFrame = plr:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("TutorialFrame")
local StartOrSkipFrame = TutorialFrame:WaitForChild("StartOptions")

local StartButton = StartOrSkipFrame:WaitForChild("Options"):WaitForChild("Buttons"):WaitForChild("StartFrame"):WaitForChild("Button")
local SkipButton = StartOrSkipFrame:WaitForChild("Options"):WaitForChild("Buttons"):WaitForChild("DismissFrame"):WaitForChild("Button")

local pages = {
	TutorialFrame:WaitForChild("Page1"),
	TutorialFrame:WaitForChild("Page2"),
	TutorialFrame:WaitForChild("Page3")
}

local function showPage(index)
	StartOrSkipFrame.Visible = false
	for i, page in ipairs(pages) do
		page.Visible = (i == index)
	end
end

local function setupButtons()
	StartButton.MouseButton1Click:Connect(function()
		showPage(1)
	end)

	SkipButton.MouseButton1Click:Connect(function()
		TutorialFrame:Destroy()
	end)

	for i, page in ipairs(pages) do
		local nextButton = page:WaitForChild("Options"):WaitForChild("Buttons"):WaitForChild("StartFrame"):WaitForChild("Button")
		
		nextButton.MouseButton1Click:Connect(function()
			if i < #pages then
				showPage(i + 1)
			else
				TutorialFrame:Destroy()
			end
		end)
	end
end

StartTutorialRemote.OnClientEvent:Connect(function()
	TutorialFrame.Visible = true
	StartOrSkipFrame.Visible = true
	
	for _, page in ipairs(pages) do 
		page.Visible = false 
	end
	
	setupButtons()
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

task.wait(2)
StartTutorialRemote:FireServer()

return {}