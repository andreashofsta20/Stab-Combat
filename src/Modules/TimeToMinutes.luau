local Tools = {}



function Tools.MakeTimeMinute(Time : number)
	local minutes = math.floor(Time / 60)
	local seconds = Time % 60
	local timeString = string.format("%d:%02d", minutes, seconds)
	
	return timeString
end









return Tools