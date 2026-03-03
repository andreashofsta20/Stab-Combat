local SprintState = {}

local sprintEnabled = false
local controller: ((boolean) -> boolean?)? = nil

function SprintState.SetController(newController: (boolean) -> boolean?)
	controller = newController
end

function SprintState.SetEnabled(enabled: boolean): boolean
	local desired = enabled == true
	local actual = desired

	if controller then
		local ok, result = pcall(controller, desired)
		if ok and type(result) == "boolean" then
			actual = result
		elseif not ok then
			actual = desired
		end
	end

	sprintEnabled = actual
	return sprintEnabled
end

function SprintState.Toggle(): boolean
	return SprintState.SetEnabled(not sprintEnabled)
end

function SprintState.GetEnabled(): boolean
	return sprintEnabled
end

return SprintState
