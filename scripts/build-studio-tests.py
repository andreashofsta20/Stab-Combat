#!/usr/bin/env python3
"""Create an unsaved native-place source overlay; never publishes or saves.

Requires a Rojo rbxlx built from this checkout. Native maps, UI and tools remain
in the loaded place. By default, stores use an injected memory adapter and
ProfileStore.Mock. --real-backend instead uses unique disposable store names.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import uuid

ROOT = Path(__file__).resolve().parents[1]

def literal(text):
    return json.dumps(text, ensure_ascii=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--players", type=int, default=2)
    parser.add_argument("--respawns", type=int, default=3)
    parser.add_argument("--port", type=int, default=8765, help="Loopback-only payload server")
    parser.add_argument("--soak-seconds", type=int, default=0)
    parser.add_argument("--real-backend", action="store_true", help="Unique disposable namespaces; never production player stores")
    parser.add_argument("--startup-matrix", action="store_true", help="No-player native tests with six temporarily missing required assets")
    args = parser.parse_args()
    namespace = "BetaAudit_20261008_"+uuid.uuid4().hex[:8]
    payload = [{"Path": ["ServerScriptService", "BetaAuditBackend"], "Class": "ModuleScript", "Source": (ROOT / "scripts/studio-backend.luau").read_text()}]
    lines = ["local Http = game:GetService('HttpService')", "local SSS = game:GetService('ServerScriptService')", "Http.HttpEnabled = true"]
    lines.append("local payload = Http:JSONDecode(Http:GetAsync('http://127.0.0.1:" + str(args.port) + "/" + args.output.with_suffix(".json").name + "'))")
    lines.append("for _, service in ipairs({SSS, game:GetService('StarterPlayer').StarterPlayerScripts, game:GetService('StarterPlayer').StarterCharacterScripts}) do for _, item in ipairs(service:GetDescendants()) do if item:IsA('BaseScript') then item.Enabled = false end end end")
    lines.append("local function put(path, class, source) local node = game; for i,name in ipairs(path) do local old = node:FindFirstChild(name); if not old or old.ClassName ~= class and i == #path then local fresh = Instance.new(i == #path and class or 'Folder'); fresh.Name = name; if old then for _, child in ipairs(old:GetChildren()) do child.Parent = fresh end; old:Destroy() end; fresh.Parent = node; old = fresh end; node = old end; if source then node.Source = source end; if node:IsA('BaseScript') then node.Enabled = true end; return node end")
    def walk(item, path):
        props = item.find("Properties")
        name = props.find("string[@name='Name']").text
        current = path + [name]
        if len(current) == 1:
            for child in item.findall("Item"): walk(child, current)
            return
        src = props.find("*[@name='Source']")
        source = src.text if src is not None else None
        if source is not None:
            if not args.real_backend:
                source = source.replace('game:GetService("DataStoreService")', 'require(game:GetService("ServerScriptService"):WaitForChild("BetaAuditBackend"))')
            else:
                source = source.replace('GetDataStore("____PS")', 'GetDataStore("'+namespace+'_Probe")')
            if current == ["ReplicatedStorage", "Modules", "DataConfig"]:
                source = source.replace('UseMockProfiles = false', 'UseMockProfiles = '+str(not args.real_backend).lower())
                for old,new in [("PlayerData_v1.0.2_MainData",namespace+"_Profiles"),("PlayerVIP_v1_TESTING",namespace+"_VIP"),("PurchaseReceipts_v1",namespace+"_Receipts")]:
                    source = source.replace(old,new)
            if args.real_backend:
                source=source.replace("PlayerData_v1.0.1_OldData",namespace+"_Legacy").replace("DailyQuestsProgress_v1.0",namespace+"_Quests").replace("AdminActionLogs_v1_TESTING",namespace+"_Admin")
            if current == ["ServerScriptService", "Game"]:
                source = source.replace('module.Start()', 'print("Beta audit controls round scheduling")')
        payload.append({"Path": current, "Class": item.attrib["class"], "Source": source})
        for child in item.findall("Item"): walk(child, current)
    for service in ET.parse(args.model).getroot().findall("Item"): walk(service, [])
    payload.append({"Path": ["ServerScriptService", "BetaAuditTests"], "Class": "Script", "Source": (ROOT / ("scripts/studio-startup-tests.luau" if args.startup_matrix else "scripts/studio-server-tests.luau")).read_text()})
    payload.append({"Path": ["StarterPlayer","StarterPlayerScripts","BetaAuditClientMetrics"],"Class":"LocalScript","Source":(ROOT/"scripts/studio-client-metrics.luau").read_text()})
    lines.append("for _, entry in ipairs(payload) do put(entry.Path, entry.Class, entry.Source) end")
    lines.append("print('BETA_OVERLAY_INSTALLED ' .. #payload)")
    lines.append("task.wait(3)")
    if args.startup_matrix:
        lines.append("local reports = {}")
        lines.append("for _, path in ipairs({'ServerStorage/Tropical Island','ServerStorage/Cargo Port','ServerStorage/Grids','ServerStorage/Classic ROBLOX','ServerStorage/Knives','ServerStorage/Revolvers'}) do local node = game; for name in path:gmatch('[^/]+') do node = node:FindFirstChild(name) end; local parent=node.Parent; node.Parent=nil; local ok,result=pcall(function() return game:GetService('StudioTestService'):ExecuteRunModeAsync({Missing=path}) end); node.Parent=parent; table.insert(reports,{Path=path,Started=ok,Result=ok and result or tostring(result)}); task.wait(2) end")
        lines.append("print('STAB_STARTUP_REPORT ' .. Http:JSONEncode(reports))")
    else:
        lines.append("local ok, result = pcall(function() return game:GetService('StudioTestService'):ExecuteMultiplayerTestAsync(" + str(args.players) + ", {Players=" + str(args.players) + ", Respawns=" + str(args.respawns) + ", SoakSeconds=" + str(args.soak_seconds) + ", RealBackend="+str(args.real_backend).lower()+", Namespace="+literal(namespace)+"}) end)")
        lines.append("print('STAB_NATIVE_REPORT ' .. Http:JSONEncode({Started=ok,Result=ok and result or tostring(result)}))")
    args.output.write_text("\n".join(lines) + "\n")
    args.output.with_suffix(".json").write_text(json.dumps(payload, ensure_ascii=True))

if __name__ == "__main__": main()
