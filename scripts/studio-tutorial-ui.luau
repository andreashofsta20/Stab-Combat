-- Native CLIENT-only visual/layout QA helper. Inject as a LocalScript in the
-- temporary Studio test overlay with ordinary CLIENT startup disabled.
-- It never calls tutorial remotes, touches profiles, or grants rewards.
-- Optional: provide ReplicatedStorage.TutorialVisualAudit to collect the
-- returned report in a StudioTestService multiplayer runner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local modules = player:WaitForChild("PlayerScripts"):WaitForChild("CLIENT"):WaitForChild("Modules")
local View = require(modules:WaitForChild("TutorialUI"))
local Guidance = require(modules:WaitForChild("TutorialGuidance"))
local report = {Checks = {}, Errors = {}, Mode = "native client layout checks"}
local connection = game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError and #report.Errors < 30 then table.insert(report.Errors, message) end
end)
local view = View.new(gui, function(action) report.LastAction = action end, function() return "Hold E to charge, then release to throw." end)
local guidance = Guidance.new(gui, view.SetGuidance, view.PulseCompletion)
local screen = gui:WaitForChild("TrainingGui")
local safeArea = screen:WaitForChild("SafeArea")
local rewards = {XP = 500, Gold = 500, Knife = "Shadow Dagger"}
local function inside(object, parent)
	local min, max = object.AbsolutePosition, object.AbsolutePosition + object.AbsoluteSize
	local parentMin, parentMax = parent.AbsolutePosition, parent.AbsolutePosition + parent.AbsoluteSize
	return min.X >= parentMin.X - 1 and min.Y >= parentMin.Y - 1 and max.X <= parentMax.X + 1 and max.Y <= parentMax.Y + 1
end
local function check(name, callback)
	local ok, reason = pcall(callback)
	table.insert(report.Checks, {Name = name, Passed = ok, Error = not ok and tostring(reason) or nil})
end
local function update(snapshot)
	view.Update(snapshot); guidance.Update(snapshot)
	task.wait(0.4) -- Native AutomaticSize / UIListLayout need render cycles.
end
for _, size in ipairs({Vector2.new(1280, 720), Vector2.new(390, 760), Vector2.new(740, 320)}) do
	safeArea.Size = UDim2.fromOffset(size.X, size.Y)
	task.wait(0.2)
	local prefix = string.format("%dx%d ", size.X, size.Y)
	check(prefix .. "offer footer remains reachable", function()
		update({Mode = "Offer", Rewards = rewards})
		local modal = safeArea.Modal
		assert(inside(modal, safeArea), "Modal exceeds available safe area")
		assert(inside(modal.Footer.Primary, modal), "Start button exceeds modal")
		assert(inside(modal.Footer.Secondary, modal), "Dismiss button exceeds modal")
		assert(modal.Content.AbsoluteSize.Y > 0, "No scrollable lesson space")
		assert(modal.Content.CanvasSize.Y.Offset >= 0)
	end)
	check(prefix .. "automatic action lesson keeps gameplay available", function()
		player:SetAttribute("TutorialActive", true)
		update({Mode = "Active", StepIndex = 6, StepCount = 11, StepStartedAt = workspace:GetServerTimeNow(), Progress = 0,
			Step = {Id = "throw", Kind = "KnifeThrow", Title = "Hit a target at range", Body = "Hold, aim, and release a charged knife.", Objective = "Eliminate the marked bandits.", Goal = 2}, Targets = {}})
		local card = safeArea.LessonCard
		assert(inside(card, safeArea), "Lesson card exceeds available safe area")
		assert(card.Actions.Continue.Visible == false, "Actionable step must advance automatically")
		assert(card.Lesson.AbsoluteSize.Y > 0, "No objective space")
		assert(safeArea.Modal.Visible == false and safeArea.ModalBackdrop.Visible == false)
		view.PulseCompletion(); assert(card.LessonSuccess.Visible)
	end)
	check(prefix .. "reward return and play states", function()
		update({Mode = "Complete", CanReturn = true, Rewards = rewards, RewardGranted = true})
		assert(safeArea.Modal.Footer.Primary.Text == "Return to lobby")
		player:SetAttribute("TutorialActive", false)
		update({Mode = "Complete", CanReturn = false, Rewards = rewards, RewardGranted = true})
		assert(safeArea.Modal.Footer.Primary.Text == "Play")
		assert(inside(safeArea.Modal.Footer.Primary, safeArea.Modal))
		update({Mode = "Complete", CanReturn = true, Rewards = rewards, RewardGranted = false})
		assert(safeArea.Modal.Footer.Primary.Text == "Return to lobby", "Aborted training cleanup lost its return route")
	end)
end
guidance.Destroy(); view.Destroy(); connection:Disconnect()
check("all tutorial visual instances are released", function()
	assert(gui:FindFirstChild("TrainingGui") == nil)
	assert(gui:FindFirstChild("TrainingTarget") == nil)
	assert(workspace:FindFirstChild("TutorialGuidance") == nil)
end)
print("TUTORIAL_UI_NATIVE_REPORT " .. HttpService:JSONEncode(report))
local remote = ReplicatedStorage:FindFirstChild("TutorialVisualAudit")
if remote then remote:FireServer(report) end
