local RevolversInfo = require(script.Parent:WaitForChild("RevolversInfo"))

-- ============================================================
-- Revolver case helpers
-- Skins are built from RevolversInfo so rarity + image can never drift.
-- Godly revolvers are NEVER unboxable (Robux-only).
-- ============================================================
local NOT_UNBOXABLE_RARITIES = { Godly = true }
local NOT_UNBOXABLE_REVOLVERS = {}

local function buildRevolverSkins(names)
	if #names > 11 then
		error("[CasesInfo] A revolver case cannot contain more than 11 items")
	end

	local skins = {}
	for _, name in ipairs(names) do
		local info = RevolversInfo[name]
		if not info then
			warn("[CasesInfo] Revolver missing from RevolversInfo, skipped:", name)
		elseif NOT_UNBOXABLE_RARITIES[info.Rarity] or NOT_UNBOXABLE_REVOLVERS[name] or info.tradeable == false then
			warn("[CasesInfo] Revolver not allowed in cases, skipped:", name)
		else
			skins[name] = {
				SkinName = name;
				Rarity = info.Rarity;
				Image = info.Image;
			}
		end
	end
	return skins
end

local REVOLVER_CASE_IMAGE = "rbxassetid://116321142920388" -- TODO: replace with real revolver case art

local Cases = {
	["Knife Case 1"] = {
		ItemType = "Knife";
		Order = 1;
		Price = 1000;
		Percentages = {
			Common = 17;
			Rare = 10;
			Epic = 8.95;
			Legendary = 1;
			Godly = 0.1;
		};
		CaseImage = "rbxassetid://116321142920388";
		EmoteCase = false;
		Skins = {
			Bowie = {
				SkinName = "Ice Wave";
				Rarity = "Common";
				Image = "rbxassetid://128915035739702"; -- no change, already correct
			};
			["Shadow Dagger"] = {
				SkinName = "Cyan";
				Rarity = "Common";
				Image = "rbxassetid://136446725670672"; -- updated from your module 2
			};
			["Gut Knife"] = {
				SkinName = "Blue Pixels";
				Rarity = "Common";
				Image = "rbxassetid://94733020530911"; -- updated from module 2
			};
			Karambit = {
				SkinName = "Glacial";
				Rarity = "Rare";
				Image = "rbxassetid://117139977173647"; -- no change, new skin image
			};
			Huntsman = {
				SkinName = "Arctic";
				Rarity = "Rare";
				Image = "rbxassetid://110090371443131"; -- no change, matches module 1 updated
			};
			Flip = {
				SkinName = "Spectrum";
				Rarity = "Rare";
				Image = "rbxassetid://131414680575050"; -- no change, matches your first module fix
			};
			Skeleton = {
				SkinName = "Blue Swirls";
				Rarity = "Epic";
				Image = "rbxassetid://117258497744746"; -- updated from module 2
			};
			Butterfly = {
				SkinName = "Blue Fade";
				Rarity = "Epic";
				Image = "rbxassetid://97175454317266"; -- updated from module 2
			};
			Bayonet = {
				SkinName = "Iceberg";
				Rarity = "Legendary";
				Image = "rbxassetid://87524479567401"; -- updated from module 2
			};
			Frostbite = {
				SkinName = "Frostbite";
				Rarity = "Godly";
				Image = "rbxassetid://131938644607549"; -- unchanged, no better match
			};
		};
	};

	["Emote Case"] = {
		ItemType = "Emote";
		Order = 100;
		Price = 500;
		Percentages = {
			Common = 60;
			Rare = 27.5;
			Epic = 0;
			Legendary = 12;
			Godly = 0.5;
		};
		CaseImage = "rbxassetid://116321142920388";
		EmoteCase = true;
		Skins = {
			["Out the Sky"] = {
				SkinName = "Out the Sky";
				Rarity = "Legendary";
				Image = ""; -- no image provided, leave empty or update later
			};
			["Godly Dance"] = {
				SkinName = "Godly Dance";
				Rarity = "Godly";
				Image = ""; -- no image provided
			};
			Sit = {
				SkinName = "Sit";
				Rarity = "Common";
				Image = ""; -- no image provided
			};
			Griddy = {
				SkinName = "Griddy";
				Rarity = "Rare";
				Image = ""; -- no image provided
			};
		};
	};

	-- ========================================================
	-- REVOLVER CASES (maximum 10 revolvers per case)
	-- Items of the same rarity have equal odds within each case.
	-- Every eligible non-Godly revolver is obtainable from exactly one case.
	-- ========================================================
	["Outlaw Revolver Case"] = {
		ItemType = "Revolver";
		Order = 10;
		Price = 600;
		Percentages = { Common = 10; Rare = 70; Epic = 20 };
		CaseImage = REVOLVER_CASE_IMAGE;
		EmoteCase = false;
		Skins = buildRevolverSkins({
			"Normal Revolver",
			"White&Black Revolver",
			"Aurum Revolver", "Azure Revolver", "Honeyed Revolver", "Onyx Revolver",
			"Amber Revolver", "Berserk Revolver", "Frostbite Revolver", "Glacial Revolver",
			"Blossom Revolver",
		});
	};

	["Frostbarrel Revolver Case"] = {
		ItemType = "Revolver";
		Order = 11;
		Price = 1200;
		Percentages = { Epic = 100 };
		CaseImage = REVOLVER_CASE_IMAGE;
		EmoteCase = false;
		Skins = buildRevolverSkins({
			"Camo Revolver", "Cosmic Revolver", "Grim Revolver", "Mystic Revolver",
			"Nebula Revolver", "Radiant Revolver", "Seraph Revolver", "Sapphire Revolver",
			"Sylvan Revolver", "Sterling Revolver",
		});
	};

	["Hellfire Revolver Case"] = {
		ItemType = "Revolver";
		Order = 12;
		Price = 1200;
		Percentages = { Epic = 60; Legendary = 40 };
		CaseImage = REVOLVER_CASE_IMAGE;
		EmoteCase = false;
		Skins = buildRevolverSkins({
			"Steampunk Revolver", "Tidal Revolver", "Toxic Revolver", "Twilight Revolver",
			"Venom Revolver", "Verdant Revolver",
			"Blaze Revolver", "Crimson Revolver", "Dragon Scale Revolver", "Hellfire Revolver",
		});
	};

	["Void Revolver Case"] = {
		ItemType = "Revolver";
		Order = 13;
		Price = 2500;
		Percentages = { Legendary = 100 };
		CaseImage = REVOLVER_CASE_IMAGE;
		EmoteCase = false;
		Skins = buildRevolverSkins({
			"Inferno Revolver", "Jade Revolver", "Love Train Revolver", "Mysterious Revolver",
			"Permafrost Revolver", "Phantom Revolver", "Royal Revolver", "Scarlet Revolver",
			"Spectral Revolver", "Shattered Revolver",
		});
	};

	["Eclipse Revolver Case"] = {
		ItemType = "Revolver";
		Order = 14;
		Price = 2500;
		Percentages = { Legendary = 100 };
		CaseImage = REVOLVER_CASE_IMAGE;
		EmoteCase = false;
		Skins = buildRevolverSkins({
			"Winter Revolver", "Void Revolver", "Vermilion Revolver", "Umbra Revolver",
			"Tempest Revolver", "Abyssal Tide Revolver", "Arcane Revolver", "Amethyst Revolver",
			"Divine Revolver",
		});
	};
}

-- Sanity check at load: a rarity with weight must have at least one item.
for caseName, caseData in pairs(Cases) do
	for rarity, weight in pairs(caseData.Percentages) do
		if weight > 0 then
			local found = false
			for _, skin in pairs(caseData.Skins) do
				if skin.Rarity == rarity then found = true break end
			end
			if not found then
				warn(("[CasesInfo] %s has weight for %s but no %s items"):format(caseName, rarity, rarity))
			end
		end
	end
end

return Cases
