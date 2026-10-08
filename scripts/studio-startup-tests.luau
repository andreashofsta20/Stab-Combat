local RS=game:GetService("ReplicatedStorage")
local args=game:GetService("StudioTestService"):GetTestArgs()
task.wait(35)
local report={Missing=args.Missing,Ready=RS:GetAttribute("ServerReady"),State=RS:GetAttribute("ServerStartupState"),
	Failures=RS:GetAttribute("ServerStartupFailures"),Pending=RS:GetAttribute("ServerStartupPending")}
report.Passed=report.Ready==false and report.State=="Failed" and type(report.Pending)=="string" and #report.Pending>0
game:GetService("StudioTestService"):EndTest(report)
