

local char = script.Parent

while not char do
	char = script.Parent
	task.wait()
end


local Animate = char:WaitForChild("Animate")


if Animate then
	Animate.Enabled = false
end