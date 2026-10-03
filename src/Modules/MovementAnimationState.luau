local State = {}
function State.Select(humanoidState, moving, sprinting, crouching, sliding)
	if humanoidState == "Dead" or humanoidState == "Physics" or humanoidState == "Ragdoll" then return nil end
	if humanoidState == "Seated" then return "Sit" end
	if humanoidState == "Jumping" then return "Jump" end
	if humanoidState == "Freefall" then return "Fall" end
	if humanoidState == "Climbing" then return "Climb" end
	if sliding then return "Slide" end
	if crouching then return moving and "CrouchWalk" or "CrouchIdle" end
	if not moving then return "Idle" end
	return sprinting and "Run" or "Walk"
end
return State
