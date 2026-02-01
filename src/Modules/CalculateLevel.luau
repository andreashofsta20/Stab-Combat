local LevelModule = {} 


local LevelXPTable = {
	[0] = 100,
	[1] = 500,
	[2] = 1000,
	[3] = 1600,
	[4] = 2300,
	[5] = 3100,
	[6] = 4000,
	[7] = 5000,
	[8] = 6100,
	[9] = 7300,
	[10] = 8600,
	[11] = 10000,
	[12] = 11500,
	[13] = 13100,
	[14] = 14800,
	[15] = 16600,
	[16] = 18500,
	[17] = 20500,
	[18] = 22600,
	[19] = 24800,
	[20] = 27100,
	[21] = 29500,
	[22] = 32000,
	[23] = 34600,
	[24] = 37300,
	[25] = 40100,
	[26] = 43000,
	[27] = 46000,
	[28] = 49100,
	[29] = 52300,
	[30] = 55600,
	[31] = 59000,
	[32] = 62500,
	[33] = 66100,
	[34] = 69800,
	[35] = 73600,
	[36] = 77500,
	[37] = 81500,
	[38] = 85600,
	[39] = 89800,
	[40] = 94100,
	[41] = 98500,
	[42] = 103000,
	[43] = 107600,
	[44] = 112300,
	[45] = 117100,
	[46] = 122000,
	[47] = 127000,
	[48] = 132100,
	[49] = 137300,
	[50] = 142600,
	[51] = 148000,
	[52] = 153500,
	[53] = 159100,
	[54] = 164800,
	[55] = 170600,
	[56] = 176500,
	[57] = 182500,
	[58] = 188600,
	[59] = 194800,
	[60] = 201100,
	[61] = 207500,
	[62] = 214000,
	[63] = 220600,
	[64] = 227300,
	[65] = 234100,
	[66] = 241000,
	[67] = 248000,
	[68] = 255100,
	[69] = 262300,
	[70] = 269600,
	[71] = 277000,
	[72] = 284500,
	[73] = 292100,
	[74] = 299800,
	[75] = 307600,
	[76] = 315500,
	[77] = 323500,
	[78] = 331600,
	[79] = 339800,
	[80] = 348100,
	[81] = 356500,
	[82] = 365000,
	[83] = 373600,
	[84] = 382300,
	[85] = 391100,
	[86] = 400000,
	[87] = 409000,
	[88] = 418100,
	[89] = 427300,
	[90] = 436600,
	[91] = 446000,
	[92] = 455500,
	[93] = 465100,
	[94] = 474800,
	[95] = 484600,
	[96] = 494500,
	[97] = 504500,
	[98] = 514600,
	[99] = 524800,
	[100] = 535100,
}



function LevelModule.GetLevel(xp: number)
	local level = 0

	for i = 0, 100 do
		if xp >= LevelXPTable[i] then
			level = i
		else
			break
		end
	end

	local currentXP = math.max(0, xp - LevelXPTable[level])
	local nextXP = LevelXPTable[level + 1]
	local toNext = nextXP and math.max(0, nextXP - xp) or 0

	return level, currentXP, toNext
end


function LevelModule.GetLevelProgress(xp: number)
	local level = 0

	for i = 0, 100 do
		if xp >= LevelXPTable[i] then
			level = i
		else
			break
		end
	end

	local currentXP = math.max(0, xp - LevelXPTable[level])
	local nextXP = LevelXPTable[level + 1]
	local totalNeeded = nextXP and (nextXP - LevelXPTable[level]) or 1

	local percent = math.clamp(currentXP / totalNeeded, 0, 1)

	return percent
end



return LevelModule	
