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

local GunSkinsInventoryFrame = OtherFramesFolder:WaitForChild("GunSkins"):WaitForChild("Scroll")

local InventoryTemplates = ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("InventoryTemplates")
local RevolverInventoryTemplate = InventoryTemplates:WaitForChild("RevolverInventoryTemplate")


-- // MODULES // --
local RarityColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityColor"))
local RevolversInfo = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RevolversInfo"))

local InventoryRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Inventory")

local EquipKnifeRemote = InventoryRemotesFolder:WaitForChild("EquipKnife")
local EquipRevolverRemote = InventoryRemotesFolder:WaitForChild("EquipRevolver")

local function getItemValue(item: Instance, field: string, defaultValue: any)
	local child = item:FindFirstChild(field)
	if child and (child:IsA("StringValue") or child:IsA("IntValue") or child:IsA("BoolValue")) then
		return child.Value
	end
	local attribute = item:GetAttribute(field)
	if attribute ~= nil then
		return attribute
	end
	return defaultValue
end

local function getRarityData(rarity: any)
	if type(rarity) == "string" and rarity ~= "" and RarityColors[rarity] then
		return RarityColors[rarity], rarity
	end
	return RarityColors.Common, "Common"
end






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

local function EquipRevolver(revolverName : string)
	if not revolverName then return end

	EquipRevolverRemote:FireServer(revolverName)

	for _, v in pairs(GunSkinsInventoryFrame:GetChildren()) do
		if v:IsA("ImageButton") and v.Name ~= revolverName then
			if v:FindFirstChild("RevolverSelected") and v.RevolverSelected.Visible == true then
				v.RevolverSelected.Visible = false
			end
		end

		if v:IsA("ImageButton") and v.Name == revolverName then
			if v:FindFirstChild("RevolverSelected") then
				v.RevolverSelected.Visible = true
			end
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

local function findTemplateChild(template: Instance, name: string): Instance?
	return template:FindFirstChild(name, true)
end

local function applyRevolverTemplate(template: Instance, revolver: Instance, revolverName: string)
	local info = RevolversInfo[revolverName]
	local rarityValue = getItemValue(revolver, "Rarity", info and info.Rarity or "Common")
	local rarityData, rarityName = getRarityData(rarityValue)
	local imageValue = getItemValue(revolver, "Image", info and info.Image or "")
	local quantityValue = tonumber(getItemValue(revolver, "Quantity", 1)) or 1
	local tradeableValue = getItemValue(revolver, "Tradeable", info and info.Tradeable == true)

	local revolverNameLabel = findTemplateChild(template, "RevolverName")
	if revolverNameLabel and revolverNameLabel:IsA("TextLabel") then
		revolverNameLabel.Text = revolverName
	end

	local rarityText = findTemplateChild(template, "KnifeSkin")
	if rarityText and rarityText:IsA("TextLabel") then
		rarityText.Text = rarityName
	end

	local revolverImage = findTemplateChild(template, "RevolverImage")
	if revolverImage and (revolverImage:IsA("ImageLabel") or revolverImage:IsA("ImageButton")) then
		revolverImage.Image = imageValue or ""
	end

	local rarityImage = findTemplateChild(template, "Rarity")
	if rarityImage and (rarityImage:IsA("ImageLabel") or rarityImage:IsA("ImageButton")) then
		rarityImage.Image = rarityData.Image
	end

	template.LayoutOrder = -rarityData.Priority

	local quantityLabel = findTemplateChild(template, "Quantity")
	if quantityLabel and (quantityLabel:IsA("TextLabel") or quantityLabel:IsA("TextButton")) then
		quantityLabel.Text = "x" .. tostring(quantityValue)
		quantityLabel.Visible = true
	end

	local tradableLabel = findTemplateChild(template, "Tradable")
	if tradableLabel then
		tradableLabel.Visible = tradeableValue ~= true
	end
end

local function RefreshRevolversInventory()
	local EquippedGun = Player:WaitForChild("leaderstats"):WaitForChild("EquippedGun").Value

	local inventoryFolder = Player:WaitForChild("leaderstats"):WaitForChild("RevolverInventory")

	local ownedRevolvers = {}

	for _, revolver in pairs(inventoryFolder:GetChildren()) do
		local revolverName = revolver.Name
		ownedRevolvers[revolverName] = true

		local existingTemplate = GunSkinsInventoryFrame:FindFirstChild(revolverName)

		if existingTemplate then
			applyRevolverTemplate(existingTemplate, revolver, revolverName)

			if not existingTemplate:GetAttribute("Connected") then
				existingTemplate.MouseButton1Click:Connect(function()
					EquipRevolver(revolverName)
				end)
				existingTemplate:SetAttribute("Connected", true)
			end
		else
			local template = RevolverInventoryTemplate:Clone()

			template.Name = revolverName
			applyRevolverTemplate(template, revolver, revolverName)

			if template:FindFirstChild("RevolverSelected") then
				template.RevolverSelected.Visible = false
			end

			template.Parent = GunSkinsInventoryFrame
			template.Visible = true

			template.MouseButton1Click:Connect(function()
				EquipRevolver(revolverName)
			end)

			template:SetAttribute("Connected", true)
		end
	end

	for _, uiRevolver in pairs(GunSkinsInventoryFrame:GetChildren()) do
		if uiRevolver:IsA("ImageButton") and not ownedRevolvers[uiRevolver.Name] then
			uiRevolver:Destroy()
		end
	end

	for _, uiRevolver in pairs(GunSkinsInventoryFrame:GetChildren()) do
		if uiRevolver:IsA("ImageButton") then
			if uiRevolver:FindFirstChild("RevolverSelected") then
				uiRevolver.RevolverSelected.Visible = uiRevolver.Name == EquippedGun
			end
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
	--		print(v.Name)
		end)
	end
end


task.spawn(function()
	while task.wait(3) do
		RefreshKnivesInventory()
		RefreshRevolversInventory()
		RefreshEmotesInventory()
	end
end)










basics()
RefreshEmotesInventory()
RefreshKnivesInventory()
RefreshRevolversInventory()












return {}