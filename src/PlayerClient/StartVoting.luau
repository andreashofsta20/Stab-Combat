local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VotingRemotesFolder = ReplicatedStorage:WaitForChild("VotingRemotes")

local StartVotingRemote = VotingRemotesFolder:WaitForChild("StartVoting")

local ClearVotesRemote = VotingRemotesFolder:WaitForChild("ClearUIVotes")

local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")

local VotingTemplatesFolder = UITemplates:WaitForChild("VotingTemplates")

local MapVoteTemplate = VotingTemplatesFolder:WaitForChild("MapVoteTemplate")




local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Lighting = game:GetService("Lighting")


local PlayerGui = Player.PlayerGui

local GUI = PlayerGui:WaitForChild("Main")

local VotingFrame = GUI:WaitForChild("VotingFrame")

local VotingOptionsHolder = VotingFrame:WaitForChild("VotingOptionsHolder")

local SendVote = VotingRemotesFolder:WaitForChild("RecieveVote")

local FramesFolder = GUI:WaitForChild("Frames")

local ExitButton = VotingFrame:WaitForChild("Close")

local function Close()
	Lighting.Blur.Enabled = false
	VotingFrame.Visible = false
end

ExitButton.MouseButton1Up:Connect(function()
	Close()
end)

local function MakeFrameVisible()
	if Player:FindFirstChild("leaderstats"):FindFirstChild("Settings"):FindFirstChild("LobbyMode").Value then
		return
	end
	print("Making voting frame visible")
	if VotingFrame then
		print("found votingframe")
		VotingFrame.Visible = true
	else
		print("error")
	end
end

local function MakeFrameInVisible()
	VotingFrame.Visible = false
	
	for i , v in pairs(FramesFolder:GetChildren()) do
		if v:IsA("Frame") and v.Visible == true then
			return
		end
	end
end

local function ClearVoting()
	for i, v in pairs(VotingOptionsHolder:GetChildren()) do
		if v:IsA("Frame") then
			v:Destroy()
		end
	end
end




StartVotingRemote.OnClientEvent:Connect(function(data : SharedTable, VotingTime : number)
	
	MakeFrameVisible()
	



	
	local ClickedVoteButton = false
	
	for i, v in pairs(data) do
		print(i, v)
		local MapVoteFrame = MapVoteTemplate:Clone()
		if MapVoteTemplate then
			MapVoteFrame.Parent = VotingOptionsHolder
			MapVoteFrame.Name = tostring(i)
			MapVoteFrame.Divider.MapName.Text = v["Name"]
			MapVoteFrame.MapImage.Image = v["VotingImage"]
			MapVoteFrame.VoteButton.MouseButton1Up:Connect(function()
				SendVote:FireServer(v["Name"])
				if not ClickedVoteButton then
				end
				ClickedVoteButton = true
			end)
			
		else
			print("didnt find")
		end
	end
	
	
	
	
	print(data)
end)

ClearVotesRemote.OnClientEvent:Connect(function()
	MakeFrameInVisible()
	ClearVoting()
	
end)

return {}