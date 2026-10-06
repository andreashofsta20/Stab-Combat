-- Share native pointer ownership between the weapon overlay and ADS. The
-- original preference returns only after both systems have released it.
local UIS = game:GetService("UserInputService")
local owners = {}
local visibleOwners = {}
local original
local Visibility = {}

function Visibility.Acquire(owner)
	if next(owners) == nil and next(visibleOwners) == nil then original = UIS.MouseIconEnabled end
	owners[owner] = true
	UIS.MouseIconEnabled = next(visibleOwners) ~= nil
end

function Visibility.Release(owner)
	if not owners[owner] then return end
	owners[owner] = nil
	if next(visibleOwners) then
		UIS.MouseIconEnabled = true
	elseif next(owners) then
		UIS.MouseIconEnabled = false
	else
		UIS.MouseIconEnabled = original
		original = nil
	end
end

function Visibility.Show(owner)
	if next(visibleOwners) == nil and next(owners) == nil then original = UIS.MouseIconEnabled end
	visibleOwners[owner] = true
	UIS.MouseIconEnabled = true
end

function Visibility.Hide(owner)
	if not visibleOwners[owner] then return end
	visibleOwners[owner] = nil
	if next(visibleOwners) then UIS.MouseIconEnabled = true
	elseif next(owners) then UIS.MouseIconEnabled = false
	else UIS.MouseIconEnabled = original; original = nil end
end

return Visibility
