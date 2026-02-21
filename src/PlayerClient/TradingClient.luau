local Plr = game.Players.LocalPlayer
local PlrGui = Plr:WaitForChild("PlayerGui")
local MainGui = PlrGui:WaitForChild("Main")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local TradingRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")

-- remotes
local RecieveRequestRemote = TradingRemotesFolder:WaitForChild("TradeUpdate")
local AcceptRequestRemote = TradingRemotesFolder:WaitForChild("AcceptRequest")
local DeclineRequestRemote = TradingRemotesFolder:WaitForChild("DeclineRequest")


local UITemplates = ReplicatedStorage:WaitForChild("UITemplates")
local TradingTemplatesFolder = UITemplates:WaitForChild("TradeRequestTemplates")
local RecieveRequestTemplate = TradingTemplatesFolder:WaitForChild("TradeRequest")

local layoutorder = 0

local TradeRequestsFrame = MainGui:WaitForChild("TradeRequests")



-- main trading frame
local TradeFrame = MainGui:WaitForChild("Frames"):WaitForChild("Trade")


RecieveRequestRemote.OnClientEvent:Connect(function(tradeData)
    if tradeData.UpdateType == "REQUEST_RECEIVED" and tradeData.Sender then
        layoutorder = layoutorder + 1
        local template = RecieveRequestTemplate:Clone()
        template:WaitForChild("Header").Text = tradeData.Sender.Name .. " has sent you a trade request"
        template.Parent = TradeRequestsFrame
        template.LayoutOrder = layoutorder
        template.Accept.MouseButton1Click:Connect(function()
            AcceptRequestRemote:FireServer(tradeData.Sender.UserId)
            template:Destroy()
        end)
        template.Decline.MouseButton1Click:Connect(function()
            DeclineRequestRemote:FireServer(tradeData.Sender.UserId)
            template:Destroy()
        end)
    end
end)












return {}
