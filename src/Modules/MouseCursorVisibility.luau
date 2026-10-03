-- Share native pointer ownership between the weapon overlay and ADS. The
-- original preference returns only after both systems have released it.
local UIS = game:GetService("UserInputService")
local owners = {}
local original
local Visibility = {}

function Visibility.Acquire(owner)
	if next(owners) == nil then original = UIS.MouseIconEnabled end
	owners[owner] = true
	UIS.MouseIconEnabled = false
end

function Visibility.Release(owner)
	if not owners[owner] then return end
	owners[owner] = nil
	if next(owners) then
		UIS.MouseIconEnabled = false
	else
		UIS.MouseIconEnabled = original
		original = nil
	end
end

return Visibility
