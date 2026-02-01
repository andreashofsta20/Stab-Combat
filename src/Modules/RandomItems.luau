local Get = {}

local caseinfo = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CasesInfo"))

function Get.RandomItem(casename: string)
	if not caseinfo[casename] then
		warn("Case not found:", casename)
		return nil
	end

	local caseData = caseinfo[casename]
	local itemsDict = caseData.Skins

	local itemsArray = {}
	for knifeName, knifeData in pairs(itemsDict) do
		knifeData.Name = knifeName 
		table.insert(itemsArray, knifeData)
	end

	if #itemsArray == 0 then
		warn("No items in case:", casename)
		return nil
	end

	local randomIndex = math.random(1, #itemsArray)
	local randomKnife = itemsArray[randomIndex]

	return randomKnife 
end

return Get