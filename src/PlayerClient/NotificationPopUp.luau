-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TS = game:GetService("TweenService")


-- // TEMPLATES // --
local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local NotificationTemplatesFolder = UITemplates:WaitForChild("NotificationTemplates")
local NotificationTemplate = NotificationTemplatesFolder:WaitForChild("NotificationTemplate")



-- // PLAYER // --
local Player = Players.LocalPlayer


-- // PLAYERGUI // --
local PlayerGui = Player.PlayerGui


-- // REMOTE FOLDERS // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ClientRemotesFolder = RemotesFolder:WaitForChild("Client")
local NotificationClientRemotesFolder = ClientRemotesFolder:WaitForChild("NotificationClientRemotes")


-- // REMOTES // --
local RecieveNotificationRemote = NotificationClientRemotesFolder:WaitForChild("RecieveNotification")


-- // UI // --
local GUI = PlayerGui:WaitForChild("Main")
local NotificationsHolderFrame = GUI:WaitForChild("NotificationsHolder")



-- // TWEEN // --
local TweenInfo = TweenInfo.new(
	
	0.5,
	Enum.EasingStyle.Linear,
	Enum.EasingDirection.In

)

local layoutOrderCounter = 0





-- // MAIN // --


local function CleanNotification(message : string, duration : number, image : string)
	local Notification = NotificationTemplate:Clone()
	local MessageLabel = Notification:WaitForChild("NotificationMessage")

	MessageLabel.Text = message
	Notification.AddGold.ProfileImage.Image = image
	Notification.Parent = NotificationsHolderFrame
	layoutOrderCounter -= 1
	if duration == 99999999 then
		Notification.LayoutOrder = -99999999
	else
		Notification.LayoutOrder = layoutOrderCounter
	end

	Notification.BackgroundTransparency = 1
	MessageLabel.TextTransparency = 1

	local tweenIn = TS:Create(Notification, TweenInfo, {BackgroundTransparency = 0})
	local tweenTextIn = TS:Create(MessageLabel, TweenInfo, {TextTransparency = 0})
	tweenIn:Play()
	tweenTextIn:Play()

	task.wait(duration)

	local tweenOut = TS:Create(Notification, TweenInfo, {BackgroundTransparency = 1})
	local tweenTextOut = TS:Create(MessageLabel, TweenInfo, {TextTransparency = 1})
	tweenOut:Play()
	tweenTextOut:Play()

	tweenOut.Completed:Wait()
	Notification:Destroy()
end




RecieveNotificationRemote.OnClientEvent:Connect(function(message : string, duration : number, image : string)
	CleanNotification(message, duration, image)
	
end)


return {}
