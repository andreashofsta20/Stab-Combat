-- // SERVICES // --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- // REMOTES // --
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ProfileHandlerRemotes = RemotesFolder:WaitForChild("ProfileHandler")
local ViewProfileOnClient = ProfileHandlerRemotes:WaitForChild("ViewProfileClient")

local TradeRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trading")
local TradeRemote = TradeRemotesFolder:WaitForChild("TradeUpdate")

local lastinventory = nil
local viewedProfileUserId: number? = nil

-- // MODULES // --
local RarityImage = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local GetLevelModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CalculateLevel"))
local GetThumbnail = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GetThumbnail"))

-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")
local FramesFolder = MainGUI:WaitForChild("Frames")

local PlayerProfileFrame = FramesFolder:WaitForChild("PlayerInfo")
local PlayerInfoContainer = PlayerProfileFrame:WaitForChild("Container")

local ButtonsFrame = PlayerInfoContainer:WaitForChild("PlayerFrame"):WaitForChild("Buttons")
local TradeButton = ButtonsFrame:WaitForChild("Trade")
local NotAbleToFrame = TradeButton:WaitForChild("NotAbleTo")

local InventoryFrame = PlayerProfileFrame:WaitForChild("Knives")
local InventoryItemsHolder = InventoryFrame:WaitForChild("Scroll")

local BackButton = PlayerProfileFrame:WaitForChild("Back")

local ItemTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InventoryTemplates"):WaitForChild("KnifeInventoryTemplate")

local RoundHistory = PlayerInfoContainer:WaitForChild("RoundHistory")
local RoundHistoryContainer = RoundHistory:WaitForChild("Scroll")
local RoundHistoryTemplate = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("BattleHistoryPlayerTemplates"):WaitForChild("BattleHistory")

-- // STATE & COOLDOWNS // --
local tradeCooldowns = {} 
local REQUEST_COOLDOWN = 15
local alive, generation, tradeAllowed = true, 0, false
local connections, cooldownTasks = {}, {}
local thumbnailTask

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
end

local function cancelThumbnail()
    generation += 1
    if thumbnailTask then task.cancel(thumbnailTask); thumbnailTask = nil end
end

local function destroy()
    if not alive then return end
    alive = false
    cancelThumbnail()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, thread in pairs(cooldownTasks) do task.cancel(thread) end
    table.clear(connections); table.clear(cooldownTasks); table.clear(tradeCooldowns)
    lastinventory, viewedProfileUserId = nil, nil
end
connect(PlayerProfileFrame.Destroying, destroy)
connect(PlayerProfileFrame:GetPropertyChangedSignal("Visible"), function()
    if not PlayerProfileFrame.Visible then
        cancelThumbnail()
        viewedProfileUserId, lastinventory, tradeAllowed = nil, nil, false
    end
end)

local function GetShortGameModeLabel(gameMode)
    if type(gameMode) ~= "string" then
        return "FFA"
    end

    local normalized = gameMode:lower()
    if normalized == "battle royale" or normalized == "battleroyale" or normalized == "br" then
        return "BR"
    elseif normalized == "free for all" or normalized == "ffa" then
        return "FFA"
    end

    return gameMode
end

local function CreateHistoryTemplate(data : SharedTable, portraits)
    local template = RoundHistoryTemplate:Clone()
    template.Parent = RoundHistoryContainer
    RoundHistory.Visible = true
    RoundHistoryContainer.Visible = true
    local Container  = template:WaitForChild("Container")

    local Stats = Container:WaitForChild("Stats")
    local Kills = Stats:WaitForChild("Kills#")
    local Placement = Stats:WaitForChild("Placement#")
    local PlrImage = Container:WaitForChild("Players"):WaitForChild("PlayerImage")
    local PlrsInRound = Container:WaitForChild("Players"):WaitForChild("OtherPlayers"):WaitForChild("PlayerAmount")

    local kills = data and data.Kills or 0
    local placement = data and data.Placement or nil
    local opponents = data and data.Opponents or 0
    local gameMode = GetShortGameModeLabel(data and data.GameMode or "FFA")

    local GameModeText = Container:WaitForChild("Divider"):WaitForChild("GameMode")
    GameModeText.Text = tostring(gameMode)
    
    Kills.Text = tostring(kills)
    if placement and placement > 0 then
        Placement.Text = "#" .. tostring(placement)
    else
        Placement.Text = "-"
    end

    
    PlrsInRound.Text = tostring(opponents)
    PlrImage.Image = ""
    table.insert(portraits, PlrImage)
    
    return template
end

local function ClearHistory()
    for _, v in pairs(RoundHistoryContainer:GetChildren()) do
        if v:IsA("Frame") then
            v:Destroy()
        end
    end
end

local function ClearInventory()
    for i , v in pairs(InventoryItemsHolder:GetChildren()) do
        if v:IsA("ImageButton") then
            v:Destroy()
        end
    end
end

local function LoadInventory(data : SharedTable)
    if not data then return end
    
    if not PlayerProfileFrame.Visible then
        return
    end

    ClearInventory()
    
    PlayerProfileFrame:WaitForChild("Container").Visible = false
    InventoryFrame.Visible = true
    BackButton.Visible = true
    PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile's Inventory"
    
    for knifeName, knifeData in pairs(data) do
        local Item = ItemTemplate:Clone()
        Item.Name = knifeName
        Item.KnifeName.Text = knifeName
        Item.KnifeImage.Image = tostring(knifeData.Image)
        Item.Quantity.Text = tostring(knifeData.Quantity) .. "x"

        local rarityInfo = RarityImage[knifeData.Rarity]
        if rarityInfo then
            Item.Rarity.Image = rarityInfo.Image
            Item.LayoutOrder = -rarityInfo.Priority
            Item.KnifeSkin.Text = knifeData.Rarity
        else
            Item.Rarity.Image = ""
            Item.LayoutOrder = 999 
        end

        if Item:FindFirstChild("Tradable") then
            Item.Tradable.Visible = knifeData.Tradeable == false
        end

        Item.Parent = InventoryItemsHolder
    end
    
end

connect(BackButton.MouseButton1Up, function()
    if InventoryFrame.Visible == true then
        BackButton.Visible = false
        InventoryFrame.Visible = false
        PlayerProfileFrame:WaitForChild("Container").Visible = true
        PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile View"
    end
end)

local function ClearProfileUI()
    local PlayerInfo = PlayerInfoContainer:WaitForChild("PlayerFrame")
    PlayerInfo.Username.Text = ""
    PlayerInfo.Level.Text = "level"
    
    local ProfileContainer = PlayerInfo:WaitForChild("ProfileContainer")
    ProfileContainer.ProfileImg.Image = ""
    
    local StatFrame = PlayerInfoContainer:WaitForChild("StatsFrame")
    
    for i , v in pairs(StatFrame:GetDescendants()) do
        if v:IsA("TextLabel") and v.Name ~= "Title" then
            v.Text = ""
        end
    end
    
    local LevelBarFrame = PlayerInfo:WaitForChild("LevelBar")
    LevelBarFrame:WaitForChild("NextLevel").Text = ""
    LevelBarFrame:WaitForChild("ProgressBar").Size = UDim2.new(0, 0,1, 0)
end

local function LoadProfileUI(PlayerInfo)
    ClearProfileUI()
    ClearInventory()
    ClearHistory()

    local xp = PlayerInfo.XP or 0
    local level, currentXP, toNext = GetLevelModule.GetLevel(xp)
    local progressRatio = 0
    if toNext > 0 then
        progressRatio = currentXP / toNext
    else
        progressRatio = 0
    end

    local PlayerInfoFrame = PlayerInfoContainer:WaitForChild("PlayerFrame")
    PlayerInfoFrame.Username.Text = PlayerInfo.Name or "N/A"
    PlayerInfoFrame.Level.Text = "Level: " .. tostring(level)

    local ProfileContainer = PlayerInfoFrame:WaitForChild("ProfileContainer")
    local portraits = {ProfileContainer.ProfileImg}

    local StatFrame = PlayerInfoContainer:WaitForChild("StatsFrame")
    StatFrame.Wins["Win#"].Text = PlayerInfo.Wins or "N/A"
    StatFrame.Deaths["Death#"].Text = PlayerInfo.Deaths or "N/A"
    StatFrame.Kills["Kill#"].Text = PlayerInfo.Kills or "N/A"

    local kills = PlayerInfo.Kills or 0
    local deaths = PlayerInfo.Deaths or 0
    local kdr = deaths > 0 and (kills / deaths) or kills
    StatFrame.KDR["KDR#"].Text = string.format("%.2f", kdr)

    local LevelFrame = PlayerInfoFrame:WaitForChild("LevelBar")
    local ProgressBar = LevelFrame:WaitForChild("ProgressBar")
    local NextLevelText = LevelFrame:WaitForChild("NextLevel")

    progressRatio = math.clamp(progressRatio, 0, 1)
    ProgressBar.Size = UDim2.new(progressRatio, 0, 1, 0)
    NextLevelText.Text = tostring(level + 1)

    PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = "Profile View"

    if PlayerInfo and type(PlayerInfo.RoundHistory) == "table" and #PlayerInfo.RoundHistory > 0 then
        -- Show newest rounds on the left (lowest LayoutOrder)
        for i, roundEntry in ipairs(PlayerInfo.RoundHistory) do
            if roundEntry.Placement and roundEntry.Placement > 0 then
                local template = CreateHistoryTemplate({
                    UserId = PlayerInfo.UserId,
                    Kills = roundEntry.Kills,
                    Placement = roundEntry.Placement,
                    Opponents = roundEntry.Opponents,
                    GameMode = roundEntry.GameMode or "FFA",
                }, portraits)
                -- Newest round gets LayoutOrder 0, next 1, etc.
                template.LayoutOrder = i - 1
            end
        end
    elseif PlayerInfo and PlayerInfo.LastRound and PlayerInfo.LastRound.Placement and PlayerInfo.LastRound.Placement > 0 then
        CreateHistoryTemplate({
            UserId = PlayerInfo.UserId,
            Kills = PlayerInfo.LastRound.Kills,
            Placement = PlayerInfo.LastRound.Placement,
            Opponents = PlayerInfo.LastRound.Opponents,
            GameMode = PlayerInfo.LastRound.GameMode or "FFA",
        }, portraits)
    end

    -- Render the data without yielding, then share one portrait across all rows.
    -- Cancelling or replacing this view invalidates a late thumbnail result.
    local token = generation
    thumbnailTask = task.defer(function()
        local ok, image = pcall(GetThumbnail.GetThumbnail, PlayerInfo.UserId)
        if not alive or token ~= generation or not PlayerProfileFrame.Visible then return end
        thumbnailTask = nil
        local content = if ok and type(image) == "string" then image else ""
        for _, portrait in ipairs(portraits) do
            if portrait.Parent then portrait.Image = content end
        end
    end)
end

connect(PlayerProfileFrame.Close.MouseButton1Up, function()
    PlayerProfileFrame.Visible = false
    Lighting.Blur.Enabled = false
    viewedProfileUserId = nil
end)

-- // BUTTON CONNECTIONS // --
for i , v in pairs(ButtonsFrame:GetChildren()) do
    if v:IsA("ImageButton") then
        if v.Name == "Inventory" then
            connect(v.MouseButton1Up, function()
                LoadInventory(lastinventory)
            end)
        elseif v.Name == "Trade" then
            connect(v.MouseButton1Up, function()
                if not viewedProfileUserId then return end
                if viewedProfileUserId == Player.UserId then return end
                
                -- Don't fire if the button is currently disabled
                if NotAbleToFrame.Visible then return end
                
                local targetId = viewedProfileUserId
                
                -- Instantly lock the button and set cooldown
                NotAbleToFrame.Visible = true
                tradeCooldowns[targetId] = os.clock() + REQUEST_COOLDOWN
                
                TradeRemote:FireServer("SEND_REQUEST", targetId)
                
                -- Re-enable button after cooldown expires
                if cooldownTasks[targetId] then task.cancel(cooldownTasks[targetId]) end
                cooldownTasks[targetId] = task.delay(REQUEST_COOLDOWN, function()
                    cooldownTasks[targetId] = nil
                    if not alive then return end
                    -- Only reset if the cooldown hasn't been cleared early
                    if tradeCooldowns[targetId] and os.clock() >= tradeCooldowns[targetId] then
                        tradeCooldowns[targetId] = nil
                        
                        -- Only hide the frame if we are still looking at the exact same profile
                        if viewedProfileUserId == targetId then
                            NotAbleToFrame.Visible = not tradeAllowed
                        end
                    end
                end)
            end)
        end
    end
end

-- // LISTEN FOR SERVER TRADE RESPONSES // --
connect(TradeRemote.OnClientEvent, function(actionType, data)
    -- Handle server rejection of the trade request
    if actionType == "ACTION_RESULT" and data.action == "SEND_REQUEST" then
        if not data.success then
            if data.extra and data.extra.targetUserId then
                local targetId = data.extra.targetUserId
                
                -- Clear the local cooldown early since the request was denied
                tradeCooldowns[targetId] = nil
                if cooldownTasks[targetId] then task.cancel(cooldownTasks[targetId]); cooldownTasks[targetId] = nil end
                
                -- If we are still viewing this player, we might need to update the button.
                -- However, if the level is too low, the profile loader already handles that.
                if viewedProfileUserId == targetId then
                    -- We re-check level here just in case they leveled up mid-view, 
                    -- but mainly this resets the cooldown lock.
                    local localXp = 0
                    local leaderstats = Player:FindFirstChild("leaderstats")
                    if leaderstats and leaderstats:FindFirstChild("XP") then
                        localXp = leaderstats.XP.Value
                    end
                    local localLevel = GetLevelModule.GetLevel(localXp)
                    
                    -- If they meet level requirements, unlock the button
                    if localLevel >= 10 and tradeAllowed then
                        NotAbleToFrame.Visible = false
                    end
                end
                
                warn("Trade Request Failed:", data.error)
            end
        end
    end
end)

-- // VIEW PROFILE EVENT // --
connect(ViewProfileOnClient.OnClientEvent, function(BasicInfo : SharedTable, inventory : SharedTable)
    if not alive or type(BasicInfo) ~= "table" or type(BasicInfo.UserId) ~= "number" then return end
    local userId = BasicInfo.UserId
    if userId ~= userId or userId <= 0 or userId == math.huge or userId % 1 ~= 0 then return end
    if FramesFolder:FindFirstChild("Spinner").Visible == true then return end
    if FramesFolder:FindFirstChild("Trade").Visible == true then return end
    
    for i , v in pairs(FramesFolder:GetChildren()) do
        if v:IsA("Frame") then
            v.Visible = false
        end
    end
    cancelThumbnail()
    viewedProfileUserId = userId
    
    -- // Level Checks //
    -- Get Local Player Level
    local localXp = 0
    local leaderstats = Player:FindFirstChild("leaderstats")
    if leaderstats and leaderstats:FindFirstChild("XP") then
        localXp = leaderstats.XP.Value
    end
    local localLevel = GetLevelModule.GetLevel(localXp)
    
    -- Get Viewed Player Level
    local targetXp = BasicInfo.XP or 0
    local targetLevel = GetLevelModule.GetLevel(targetXp)
    
    local meetsLevelRequirement = (localLevel >= 10) and (targetLevel >= 10)
    
    -- // Setting Checks & Cooldowns //
    local tradesEnabled = true 
    if BasicInfo.TradesEnabled ~= nil then
        tradesEnabled = BasicInfo.TradesEnabled 
    end
    
    local isSelf = viewedProfileUserId == Player.UserId
    local isOnCooldown = tradeCooldowns[viewedProfileUserId] and os.clock() < tradeCooldowns[viewedProfileUserId]
    tradeAllowed = tradesEnabled and not isSelf and meetsLevelRequirement and not BasicInfo.Loading and not BasicInfo.Unavailable
    
    -- Set NotAbleTo frame visibility
    if not tradeAllowed or isOnCooldown then
        NotAbleToFrame.Visible = true
    else
        NotAbleToFrame.Visible = false
    end
    
    -- // Show Profile //
    PlayerProfileFrame.Visible = true
    InventoryFrame.Visible = false
    BackButton.Visible = false
    PlayerProfileFrame.Container.Visible = true
    
    ClearProfileUI()
    
    lastinventory = type(inventory) == "table" and inventory or {}
    Lighting.Blur.Enabled = true
    
    LoadProfileUI(BasicInfo)
    
    PlayerProfileFrame:WaitForChild("Top"):WaitForChild("Text").Text = if BasicInfo.Loading then "Profile loading..."
        elseif BasicInfo.Unavailable then "Profile unavailable" else "Profile View"
end)

return {Destroy = destroy}
