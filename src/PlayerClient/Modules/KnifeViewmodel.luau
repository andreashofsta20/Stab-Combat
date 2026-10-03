local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage.Modules.KnifeConfig)
local Motion = require(ReplicatedStorage.Modules.KnifeViewmodelMotion)
local ToolPhysics = require(ReplicatedStorage.Modules.RevolverToolPhysics).New(require(ReplicatedStorage.Modules.KnivesInfo))
local Presentation = require(script.Parent.WeaponViewmodel).New({
	Name = "KnifeFirstPerson", WarningPrefix = "KnifeFirstPerson", Motion = Motion,
})
local Viewmodel = {}
local initialized = false
local tuning = {FirstPerson = Config.FirstPerson, Pose = {R6RotationOffset = Config.FirstPerson.R6RotationOffset}}

function Viewmodel.Init()
	if initialized then return end
	initialized = true
	ToolPhysics.BindPlayer(Players.LocalPlayer)
end

function Viewmodel.Update(tool, allowed, dt, bodyAnimation, armAnimation, action)
	Viewmodel.Init()
	local elapsed = action and action.throwElapsed
	local visible = type(elapsed) ~= "number" or elapsed < Config.Presentation.HideHandleDelay
		or elapsed >= Config.Presentation.ReturnHandleDelay
	Presentation.Update(tool, tuning, allowed, false, false, dt, bodyAnimation, armAnimation, action, visible)
end

function Viewmodel.Clear() Presentation.Clear() end
function Viewmodel.IsActive(tool) return Presentation.IsActive(tool) end
function Viewmodel.IsFirstPerson(tool) return Presentation.IsFirstPerson(tool, tuning) end
function Viewmodel.GetVisualTool(tool) return Presentation.GetVisualTool(tool) end
function Viewmodel.GetOriginalTransparency(part) return Presentation.GetOriginalTransparency(part) end
function Viewmodel.SetOriginalTransparency(part, value) Presentation.SetOriginalTransparency(part, value) end

return Viewmodel
