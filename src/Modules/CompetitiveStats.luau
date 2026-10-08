-- Fixed keys keep the aggregate small; skins share their weapon family.
local Stats = {}
local MAX = 2147483647
local function row(source, fields)
	local result = {}
	for _, field in ipairs(fields) do
		local value = type(source) == "table" and source[field]
		result[field] = type(value) == "number" and value == value and value >= 0 and value <= MAX and value % 1 == 0 and value or 0
	end
	return result
end
function Stats.Repair(source)
	local result = {Version=1,Modes={},Weapons={}}
	for _, mode in ipairs({"FFA","BattleRoyale"}) do result.Modes[mode] = row(type(source) == "table" and type(source.Modes) == "table" and source.Modes[mode],{"Kills","Deaths","Rounds","Wins","Forfeits"}) end
	for _, weapon in ipairs({"KnifeThrow","KnifeStab","Revolver"}) do result.Weapons[weapon] = row(type(source) == "table" and type(source.Weapons) == "table" and source.Weapons[weapon],{"Hits","Damage","Kills"}) end
	return result
end
local function ensure(data)
	if type(data.CompetitiveStats) ~= "table" or data.CompetitiveStats.Version ~= 1 then data.CompetitiveStats = Stats.Repair(data.CompetitiveStats) end
	return data.CompetitiveStats
end
local function add(target, field, value) target[field] = math.min(MAX,target[field]+(value or 1)) end
function Stats.Hit(data,weapon,damage)
	local target = ensure(data).Weapons[weapon]
	if target and type(damage) == "number" and damage == damage and damage > 0 and damage < math.huge then add(target,"Hits"); add(target,"Damage",math.floor(damage)) end
end
function Stats.Kill(data,mode,weapon)
	local stats = ensure(data)
	if stats.Modes[mode] then add(stats.Modes[mode],"Kills") end
	if stats.Weapons[weapon] then add(stats.Weapons[weapon],"Kills") end
end
function Stats.Death(data,mode) local target = ensure(data).Modes[mode]; if target then add(target,"Deaths") end end
function Stats.Round(data,mode,won,forfeited)
	local target = ensure(data).Modes[mode]; if not target then return end
	add(target,"Rounds"); if forfeited then add(target,"Forfeits") elseif won then add(target,"Wins") end
end
return Stats
