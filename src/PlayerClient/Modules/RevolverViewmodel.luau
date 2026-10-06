local ReplicatedStorage = game:GetService("ReplicatedStorage")
return require(script.Parent.WeaponViewmodel).New({
	Name = "RevolverFirstPerson",
	Motion = require(ReplicatedStorage.Modules.RevolverViewmodelMath),
	PrepareVisual = require(script.Parent.RevolverEffects).SetFirstPerson,
})
