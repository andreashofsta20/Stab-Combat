local Abbreviate = {}


local suffixes = {"", "K", "M", "B", "T", "QA", "QI", "SX", "SP", "OC", "NO", "DC", "UD", "DD", "TD", "QAD", "QID", "SXD", "SPD", "OCD", "NOD", "VG", "UVG"}
function Abbreviate.Ab(n)
	local s = tostring(math.floor(n))
	return string.sub(s, 1, ((#s - 1) % 3) + 1) .. (suffixes)[math.floor((#s - 1) / 3) + 1]
end

function Abbreviate.WithCommas(n)
	return tostring(n):reverse():gsub("%d%d%d", "%0,"):reverse():gsub("^,", "")
end

return Abbreviate	
