-- // SERVICES // --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")



-- // LOCALPLAYER // --
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui


-- // UI // --
local MainGUI = PlayerGui:WaitForChild("Main")

local FramesFolder = MainGUI:WaitForChild("Frames")
local InventoryFrameUI = FramesFolder:WaitForChild("Inventory")
local MenuFrame = InventoryFrameUI:WaitForChild("Menu")
local OtherFramesFolder = InventoryFrameUI:WaitForChild("Holders")
local CloseButton = InventoryFrameUI:WaitForChild("Close")
local GoBackButton = InventoryFrameUI:WaitForChild("Back")




local EmotesFrame = OtherFramesFolder:WaitForChild("Emotes"):WaitForChild("Scroll")

local KnivesInventoryFrame = OtherFramesFolder:WaitForChild("Knives"):WaitForChild("Scroll")


-- // MODULES // --
local RarityColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))

local InventoryRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Inventory")

local EquipKnifeRemote = InventoryRemotesFolder:WaitForChild("EquipKnife")






-- // MAIN FUNCTIONS // --

local function EquipKnife(KnifeName : string)
	
	if not KnifeName then return
	end
	
	EquipKnifeRemote:FireServer(KnifeName)
	
	for i , v in pairs(KnivesInventoryFrame:GetChildren()) do
		if v:IsA("ImageButton") and v.Name ~= KnifeName then
			if v.KnifeSelected.Visible == true then
				v.KnifeSelected.Visible = false
			end
		end
		
		if v:IsA("ImageButton") and v.Name == KnifeName then
			v.KnifeSelected.Visible = true
		end
	end
	
	
	
end


local function RefreshEmotesInventory()
	local EmotesFolder = Player:WaitForChild("leaderstats"):WaitForChild("Emotes")

	local ownedEmotes = {}

	for _, emote in pairs(EmotesFolder:GetChildren()) do
		local emoteName = emote.Name
		ownedEmotes[emoteName] = true

		local existingTemplate = EmotesFrame:FindFirstChild(emoteName)
		if existingTemplate then
			local rarityValue = emote:FindFirstChild("Rarity") and emote.Rarity.Value or "Common"
			local qtyText = emote:FindFirstChild("Quantity") and ("x" .. tostring(emote.Quantity.Value)) or "x1"

			existingTemplate.Quantity.Text = qtyText
			local rarityLabel = existingTemplate:FindFirstChild("EmoteRarity")
			if rarityLabel then
				rarityLabel.Text = rarityValue
			end
			existingTemplate.Rarity.Image = RarityColors[rarityValue].Image
			existingTemplate.LayoutOrder = -RarityColors[rarityValue].Priority

		else
			local template = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InventoryTemplates"):WaitForChild("EmoteInventoryTemplate"):Clone()

			template.Name = emoteName
			template.EmoteName.Text = emoteName
			template.EmoteRarity.Text = emote:FindFirstChild("Rarity") and emote.Rarity.Value or "Common"
			template.Rarity.Image = RarityColors[tostring(emote.Rarity.Value)].Image
			template.LayoutOrder = -RarityColors[tostring(emote.Rarity.Value)].Priority
			template.Quantity.Text = emote:FindFirstChild("Quantity") and "x" .. tostring(emote.Quantity.Value) or "x1"

			template.Parent = EmotesFrame
			template.Visible = true
			

			local ViewportFrame = template:WaitForChild("Rarity"):WaitForChild("EmoteViewport")
			local World = ViewportFrame:WaitForChild("World")
			local Rig = World:WaitForChild("Rig")
			local RigHumanoid = Rig:WaitForChild("Humanoid")

			local AnimationRig:Animation = Instance.new("Animation")
			AnimationRig.AnimationId = emote.Value

			local AnimationTrack = RigHumanoid:LoadAnimation(AnimationRig)
			AnimationTrack.Looped = true
			AnimationTrack:Play()
		end
	end


	for _, emote in pairs(EmotesFrame:GetChildren()) do
		if emote:IsA("ImageButton") and not ownedEmotes[emote.Name] then
			emote:Destroy()
		end
	end
end


local function RefreshKnivesInventory()
	local EquippedKnife = Player:WaitForChild("leaderstats"):WaitForChild("EquippedKnife").Value
	
	local inventoryFolder = Player:WaitForChild("leaderstats"):WaitForChild("Inventory")

	local ownedKnives = {}

	for _, knife in pairs(inventoryFolder:GetChildren()) do
		local knifeName = knife.Name
		ownedKnives[knifeName] = true

		local existingTemplate = KnivesInventoryFrame:FindFirstChild(knifeName)

		if existingTemplate then
			existingTemplate.Quantity.Text = knife:FindFirstChild("Quantity") and "x" .. tostring(knife.Quantity.Value) or "x1"
			existingTemplate.KnifeSkin.Text = knife:FindFirstChild("Rarity") and knife.Rarity.Value or "Common"
			existingTemplate.KnifeImage.Image = knife:FindFirstChild("Image") and knife.Image.Value or ""
			existingTemplate.Rarity.Image = RarityColors[tostring(knife.Rarity.Value)].Image
			existingTemplate.LayoutOrder = -RarityColors[tostring(knife.Rarity.Value)].Priority
			local tradeableValue = knife:FindFirstChild("Tradeable")
			if existingTemplate:FindFirstChild("Tradable") then
				existingTemplate.Tradable.Visible = (tradeableValue and tradeableValue:IsA("BoolValue") and tradeableValue.Value == false) or false
			end

			if not existingTemplate:GetAttribute("Connected") then
				existingTemplate.MouseButton1Click:Connect(function()
					EquipKnife(knifeName)
				end)
				existingTemplate:SetAttribute("Connected", true)
			end
		else
			local template = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InventoryTemplates"):WaitForChild("KnifeInventoryTemplate"):Clone()

			template.Name = knifeName
			template.KnifeName.Text = knifeName
			template.KnifeSkin.Text = knife:FindFirstChild("Rarity") and knife.Rarity.Value or "Common"
			template.KnifeImage.Image = knife:FindFirstChild("Image") and knife.Image.Value or ""
			template.Rarity.Image = RarityColors[tostring(knife.Rarity.Value)].Image
			template.LayoutOrder = -RarityColors[tostring(knife.Rarity.Value)].Priority
			template.Quantity.Text = knife:FindFirstChild("Quantity") and "x" .. tostring(knife.Quantity.Value) or "x1"
			local tradeableValue = knife:FindFirstChild("Tradeable")
			if template:FindFirstChild("Tradable") then
				template.Tradable.Visible = (tradeableValue and tradeableValue:IsA("BoolValue") and tradeableValue.Value == false) or false
			end

			template.Parent = KnivesInventoryFrame
			template.Visible = true
			
			template.MouseButton1Click:Connect(function()
				EquipKnife(knifeName)
			end)
			
			template:SetAttribute("Connected", true)
		end
	end

	for _, uiKnife in pairs(KnivesInventoryFrame:GetChildren()) do
		if uiKnife:IsA("ImageButton") and not ownedKnives[uiKnife.Name] then
			uiKnife:Destroy()
		end
	end
	
	for _, uiKnife in pairs(KnivesInventoryFrame:GetChildren()) do
		if uiKnife:IsA("ImageButton") and uiKnife.Name == EquippedKnife then
			uiKnife.KnifeSelected.Visible = true
		end
	end
	
end



local function CloseFrame()
	
	InventoryFrameUI.Visible = false
	Lighting.Blur.Enabled = false
end

local function BackFrame()
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("Frame") or v:IsA("ScrollingFrame") or v:IsA("CanvasGroup") then 
			v.Visible = false
		end
	end
	MenuFrame.Visible = true
	GoBackButton.Visible = false
end

local function basics()
	GoBackButton.MouseButton1Up:Connect(function()
		BackFrame()
	end)
	
	CloseButton.MouseButton1Up:Connect(function()
		CloseFrame()
	end)
	
end

function HideAllFrames()
	for i , v in pairs(OtherFramesFolder:GetChildren()) do
		if v:IsA("Frame") or v:IsA("ScrollingFrame") or v:IsA("CanvasGroup") then
			v.Visible = false
		end
	end 
	
	
	MenuFrame.Visible = false
	GoBackButton.Visible = true
end



local function OpenFrame(FrameName : string)
	local Frame : Frame = OtherFramesFolder:FindFirstChild(FrameName)
	if Frame then
		HideAllFrames()
		Frame.Visible = true
	else
		print("couldnt find")
	end
	
end


for i , v in pairs(MenuFrame:GetDescendants()) do
	if v:IsA("ImageButton") then
		v.MouseButton1Up:Connect(function()
			OpenFrame(v.Name)
			print(v.Name)
		end)
	end
end


task.spawn(function()
	while task.wait(3) do
		RefreshKnivesInventory()
		RefreshEmotesInventory()
	end
end)










basics()
RefreshEmotesInventory()
RefreshKnivesInventory()












return {}